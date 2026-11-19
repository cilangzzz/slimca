# api-parse.md — 文本解析入口

> 覆盖：打字与语音转写共用的一条管线（规范化 → input_hash → 缓存回放 → 受约束 LLM 请求
> → 校验/映射 → 纠错重试 1 次 → 值返回）。拍照/小票路径见 [api-receipt.md](api-receipt.md)；
> 结果模型字段明细见 [data-model.md](data-model.md)；通道配置见 [api-llm.md](api-llm.md)。

## AiParser（解析器抽象，feature 层依赖此接口）

```dart
abstract interface class AiParser {
  Future<ParseResult> parse(ParseInput input);
}
```

生产实现唯一：`LlmAiParser`。测试注入 `FakeAiParser`（脚本桩，见 [api-llm.md](api-llm.md) Fake 一节）。

### ParseInput / ParseContext（参数）

| 字段 | 类型 | 说明 |
|---|---|---|
| `ParseInput.rawText` | String | 用户原文（管线内先 `normalizeParseInput`：折叠空白含全角空格） |
| `ParseInput.kind` | AiInputKind | text/voice/photo（进 ai_parses.input_kind；不参与缓存键） |
| `ParseContext.date` | String | 本地日历日 `yyyy-MM-dd`，入口做 `validateCalendarDay` 校验；提示词日期锚点 |
| `ParseContext.mode` | ParseMode | both / moneyOnly / kcalOnly（单边开关；**参与缓存键**） |

### 返回（sealed ParseResult）

- `ParseSuccess`：title/kind/lines 草稿 + inputHash + record（ai_parses 留痕）+ fromCache +
  parseNotes + notes（越界行丢弃、kind 推导等非阻断提示）。行草稿结构见 [data-model.md](data-model.md)。
- `StructuredFailure`：reason + degradeLevel（指路）+ rawInput（原输入保留，手填预填/入队重放）
  + attempts + errors（人读中文）+ lastRawOutput（排查用，不落库）+ cause。**不抛异常**。

### 抛出的例外（仅入口契约）

- `ArgumentError`：`context.date` 非合法日历日；`rawText` 规范化后为空（UI 层应先拦截空输入）。

## LlmAiParser 构造参数

| 参数 | 缺省 | 说明 |
|---|---|---|
| `adapter` | 必填 | LlmAdapter（见 [api-llm.md](api-llm.md)） |
| `cache` | 必填 | AiParseCache；壳层现行装配注入 `InMemoryAiParseCache`（持久留痕由 feature_capture CaptureGateway 承担，避免双写） |
| `categoryResolver` | `PresetCategoryResolver()` | category_hint → 内置分类；宿主注入 name→id 实映射 |
| `refCalibrator` | `PassthroughRefCalibrator()` | 食物库联查校准钩子（W3-4 缺省透传） |
| `nowMs` / `newParseId` | 墙钟 / core_db `generateUuidV7` | 注入用（测试确定性）；UUIDv7 内嵌时间是缓存时效判定依据 |
| `cacheTtl` | `kAiParseCacheTtl`（7 天） | 缓存时效 |
| `maxValidationAttempts` | 2 | 首发 1 次 + 纠错重试 1 次（§7.1 上限，不可叠加更多） |

## parse() 内部流程（错误出口标注）

1. **规范化** `normalizeParseInput`；空 → ArgumentError。
2. **缓存键** `computeInputHash(normalized, mode)`（sha256；信封 `slimca-ai-parse|v1|<mode>|<text>`）。
3. **缓存命中**：`cache.find(hash)` 且 `promptVersion == kPromptVersion`（现为 `w3-4-v1`）且
   `isFreshAt(now, ttl)` → 重放 raw_output（再过一次校验器）。缓存行损坏视为未命中，走实时管线。
4. **组请求**：system = `buildSystemPrompt(mode/date/内置分类枚举)`；jsonIntent=jsonSchema，
   schema = `buildParseJsonSchema(mode)`（both 档 oneOf 双分支；单边档只给对应分支）；
   temperature 0.2。adapter 异常 → `_failureFromAdapter` 映射（见 [api-llm.md](api-llm.md) 错误分类表）。
5. **受约束解码 + 校验**（`validateAndMap`）：字段级违例抛 `AiValidationException`
   （reason=validationFailed / invalidJson / emptyResult）。
6. **纠错回喂重试**：把上轮输出 + 错误清单（`buildRetryInstruction`）追加进消息再调一次；
   仍失败 → `StructuredFailure(degradeLevel=manualForm)`。
7. **成功收尾**：写 `cache.save(AiParseRecord)`（provider/model/latency/cost/confidence=全行最小值/
   promptVersion）→ ParseSuccess。

### 校验器硬闸门口径（parse_validator）

- 顶层必须 JSON 对象；title/kind/lines 必需；容忍 markdown 围栏与前后缀文字
  （`extractJsonPayload` 取首个 `{` 到最后一个 `}`）。
- 金额行 `amount_minor`：严格 int 分（字符串 "1800"、小数 1800.5 都是类型错 → 重试纠偏），>0。
- 热量行 `amount_kcal`：int ∈ [0,5000]；行 direction 恒 in；money 方向由 `income` 布尔
  （缺省 false = 支出 out）。
- 每行 `confidence` 必填 ∈[0,1]；菜品级缺失继承行级。菜品 `portion_g` 必须为正
  （份量滑杆重算基准）；`ref_source` 缺省 llm。
- 单边模式越界行（kcalOnly 里的 money 行等）**丢弃记 note**，不算违例；kind 随保留行重推导。
- category_hint 未命中内置 → 挂「其他」并 `categorySuggestNew=true`（记 note，不失败）。

## 缓存接口（AiParseCache）

```dart
abstract interface class AiParseCache {
  Future<AiParseRecord?> find(String inputHash);  // 该 hash 最新一条；时效判断在管线内
  Future<void> save(AiParseRecord record);        // 幂等 upsert
}
```

- `InMemoryAiParseCache`：进程内 memo（测试/预览；每 hash 只留最新一条）。
- `DriftAiParseCache(appDatabase)`：直读直写 core_db `ai_parses` 表；`ORDER BY id DESC LIMIT 1`
  取最新（UUIDv7 字典序=时间序），`InsertMode.replace` upsert。**壳层文本通道当前未接线此实现**
  （持久留痕由 feature_capture CaptureGateway 同事务落库），拍照通道工厂 cache 参数缺省内存实现。
- `AiParseRecord.createdAtMs`：从 UUIDv7 前 48 位提取；非 v7 布局抛 FormatException（不静默降级）。
  负年龄（时钟回拨/跨设备导入）一律视为过期。

## 分类解析（CategoryResolver）

- core_ai 只做**名字域**解析；id 映射由宿主注入（从 core_db categories 表装载 name→id），
  避免复制内置分类 id（运行期真值在数据库）。
- `PresetCategoryResolver(nameToId, aliases, fallbackCategoryId)`：命中判定 = 别名归一 → 查
  nameToId；未注入映射时退回 `kDefaultPresetCategoryNames`（22 个内置分类名，与 core_db
  seed 同名单）；未命中 → `suggestNew=true`，categoryId 给 fallbackCategoryId（可为 null）。
- 提示词的内置分类枚举来自 `knownCategoryNames`，改分类名单时两处（core_db seed 与此常量）
  需同步，见 [pitfalls.md](pitfalls.md)。
