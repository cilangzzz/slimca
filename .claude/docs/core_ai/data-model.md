# data-model.md — 解析结果数据模型

> 覆盖：core_ai 产出的全部草稿/留痕模型及与 core_db 表的落点关系。core_ai 只产草稿，
> entries/entry_lines/food_items 实体化与落库由宿主 feature 层编排（表结构见
> ../core_db/README.md）。

## 单位与枚举口径（三条管线共用）

- 金额：int **分**（>0）；热量：int **kcal** ∈ [0,5000]；置信度 double ∈ [0,1]。
- `ParseMode`（单边开关，参与缓存键）：both / moneyOnly(wire=`money_only`) / kcalOnly(wire=`kcal_only`)。
- `AiInputKind`（wire 进 ai_parses.input_kind）：text / voice / photo。
- `LineType` / `LineDirection` / `EntryKind`：复用 core_domain 枚举（一字不差，杜绝映射漂移）。
  calorie 行 direction 恒 in；money 行 income=false→out（支出）/true→in。
- `ConfidenceBand` 三色档：≥0.8 green / ≥0.5 yellow / 其余 red（与 ui_kit SlimcaConfidenceDot
  同口径）；`ParsedLineDraft.band` 便捷取档。
- `FoodRefSource`（wire 进 food_items.ref_source）：usda / off / baidu / local / llm。

## ParseResult（sealed，三条管线统一的成功/失败值类型）

### ParseSuccess

| 字段 | 说明 |
|---|---|
| `title` | entries.title 预填（≤20 字） |
| `kind` | EntryKind；单边模式按保留行推导（钱+热量=mixed/仅钱=expense/仅热量=food） |
| `lines` | List<ParsedLineDraft>，见下 |
| `inputHash` | 缓存键（sha256） |
| `record` | AiParseRecord（宿主落库后 entries.ai_parse_id 引用其 id 溯源） |
| `fromCache` | 是否 <7 天缓存回放 |
| `parseNotes` | 估算依据说明（entries.note 追加，可关） |
| `notes` | 非阻断提示（越界行丢弃、kind 推导、category 未命中挂其他等） |
| `confidence`（getter） | =record.confidence = 全行最小值（最弱 facet 决定确认卡高亮档） |

### StructuredFailure（失败=正常业务分支，不抛异常）

| 字段 | 说明 |
|---|---|
| `reason` | AiFailureReason（11 值，见下） |
| `degradeLevel` | AiDegradeLevel（UI 指路：1 manualForm / 2 deferredQueue / 3 quotaNotice / 4 providerFallback） |
| `rawInput` | 原输入保留（手填预填/入队重放）；照片/小票只落描述符 `photo:<hash>`、`receipt:ocr-*` |
| `context` | ParseContext（延迟队列重放必需） |
| `attempts` | 管线级尝试次数（适配器内部瞬时重试不计入） |
| `errors` | 人读中文错误清单 |
| `lastRawOutput` | 末次原始输出（排查用；**ai_parses.raw_output 只存成功解析**） |
| `cause` | 底层异常（诊断用） |

`AiFailureReason`：timeout / network / rate_limit / quota / auth / invalid_request /
bad_response（适配器分类）+ invalid_json / validation_failed / empty_result（内容校验分类）+
provider_error。

## ParsedLineDraft（产出行草稿 → entry_lines 落库口径）

| 字段 | 说明 |
|---|---|
| `type` | LineType.money / calorie |
| `direction` | LineDirection（calorie=in；money 按 income 布尔） |
| `amount` | int：money=分 / calorie=kcal（构造 assert 非负、置信度 ∈[0,1]） |
| `confidence` | AI 产出行必填 |
| `ledgerHint` | LLM 输出 ledger_hint（如 'default'→宿主映射默认账本 id） |
| `categoryId` / `categoryHint` / `categorySuggestNew` | 分类解析落点（见 [api-parse.md](api-parse.md)） |
| `currency` | money 行，缺省 CNY |
| `items` | 仅 calorie 行：List<ParsedFoodItemDraft> |
| `payload` | 行级明细引用 JSON 载荷（merchant / ledger_hint；宿主 jsonEncode 落库） |

### ParsedFoodItemDraft（→ food_items 逐菜品）

`name`（中文优先）/ `portionG`（克，份量滑杆联动重算基准，必须 >0）/ `kcal`（int）/
`proteinG` `carbG` `fatG`（缺 0）/ `refSource` / `refId`（联查命中后回填）/ `confidence`
（缺失继承行级）。拍照侧 kcalPer100g 换算与降档规则见 [api-receipt.md](api-receipt.md)。

## AiParseRecord（ai_parses 留痕，本地件永不同步）

| 字段 | 说明 |
|---|---|
| `id` | UUIDv7（应用层生成）；**7 天时效由其内嵌时间判定，表无 created_at 列** |
| `inputKind` / `inputHash` | text|voice|photo / sha256 缓存键 |
| `provider` / `model` | 供应商与模型（可 A/B 对比） |
| `rawOutput` | 原始受约束 JSON（缓存回放与排查） |
| `latencyMs` / `costMicro` | 延迟 / 成本（微元，无价目通道记 0 不虚报） |
| `confidence` | 全行最小值 |
| `promptVersion` | 回放兼容闸门：文本 `w3-4-v1`、拍照 `w11-12-photo-v1`（分轨） |

`toDbRow()/fromDbRow` 与 core_db `AiParse` 行对象互转；`createdAtMs` 从 id 前 48 位提取，
非 v7 布局抛 FormatException。**与宿主落库关系**：壳层文本通道的持久留痕由 feature_capture
CaptureGateway 承担（core_ai 内只注入内存缓存，避免同一输入双写 ai_parses 两行）。

## 拍照通道模型（photo_models.dart）

- `PhotoImageInput`（bytes+mime，原图即用即焚）→ `CompressedImage`（bytes+mime 恒
  image/jpeg+宽高；识别供应商只见规范形）→ `DishCandidate`（name/grams/confidence/
  categoryHint?/kcalPer100gHint?）。常量：`kDefaultDishPortionG`=100、
  `kFallbackKcalPer100g`=150、`kUncalibratedConfidencePenalty`=0.8。
- `PhotoCompressionException`：压缩前置失败（识别供应商 HTTP 失败复用 LlmException 家族）。
- `DishRefEntry`/`DishRefLookup`：联查参考条目（kcalPer100g/refSource/refId?/defaultPortionG?）。

## 小票通道模型（receipt_models.dart）

- `ReceiptImageInput`（bytes+mime；不做统一重编码，文字保真优先于体积）。
- `ReceiptDateTime`：day（`yyyy-MM-dd`，已过真实日历日校验）+ time?（`HH:mm`）；
  `occurredAtMsUtc(tzOffsetMin)` 把本地墙钟折算 UTC（组件回读不一致即非法返回 null，不猜）。
- `ReceiptLineItem`：name / amountMinor?（null=该行金额未解析出，宁缺不猜）/ quantity?
  （x2/×2 后缀）。上限 `kMaxReceiptLineItems`=30。
- `ReceiptDraft`：merchant? / totalMinor? / datetime? / lineItems / rawText（OCR 全文，仅端侧
  内存，不进结构化文本不上云）/ warnings（降档说明，「未识别即声明」）；
  `hasText`（false=坏小票 → 手填）/ `hasPrefillFields`。

## 线别约定（宿主消费须知）

- ParseSuccess.notes / ReceiptDraft.warnings 是面向用户确认卡的信任语言，不要吞掉。
- 单边模式下 ParsedLineDraft 集合已过滤；宿主无需再按 mode 过滤（但确认卡 UI 单边开关
  仍可展示/切换，由 feature_capture 负责）。
- `StructuredFailure.rawInput` 对拍照/小票是描述符而非原文——UI 不要把它当用户文本回显。
