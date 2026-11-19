# api-receipt.md — 拍照与小票解析路径

> 覆盖：拍照菜品识别（百度先行 → Vision LLM 兜底）与端侧小票 OCR（→ 用户确认后复用文本
> 管线）。文本管线/缓存/降级基础见 [api-parse.md](api-parse.md) 与 [api-llm.md](api-llm.md)。

## 拍照识别（PhotoParser）

```dart
Future<ParseResult> parse(PhotoParseRequest request);
```

`PhotoParseRequest`：`imageBytes`（原图字节，即用即焚）+ `mime` + `date`（本地日历日，入口校验）。
拍照通道**恒单边热量口径**（`ParseMode.kcalOnly`，无金额语义）。

流程（失败一律值返回 StructuredFailure）：

1. **端侧压缩** `ImageCompressor.compress`：坏字节/空字节抛 `PhotoCompressionException`
   → invalidRequest → 手填。缺省 `PureDartImageCompressor`（纯 Dart，无平台通道）：
   EXIF 方向烘焙 → 最长边缩至 1280 以内（**只缩不放大**）→ 重编码 JPEG q80（mime 恒 image/jpeg）。
2. **缓存键** `computePhotoInputHash(compressed.bytes, mime)`：信封含 mime 与字节数 + 压缩
   规范形字节。命中（`kPhotoPromptVersion = w11-12-photo-v1` 且 <7 天）→ 重放。
3. **双供应商 fallback**：按装配顺序逐个 `ImageDishAdapter.recognize(compressed)`，成功即短路；
   异常（LlmException 已分类）与空候选都是「该供应商失败 → 切下一个」。多供应商失败的
   degradeLevel 取全程最重档（断网/额度是持续性信号，不因后续瞬时失败丢失）。
4. **草稿组装** `assembleDishParseJson`：候选 → §7.2 受约束 JSON（单边热量行），再过既有
   校验器（与文本管线同一映射权威，缓存回放语义一致）。全部失败 → StructuredFailure。

### 草稿组装规则（红线）

- 每百克热量优先级：**联查命中 > 模型直报 hint（`kcalPer100gHint`）> `kFallbackKcalPer100g`
  （150.0 本地估计基准）**。LLM 直报热量不可信——只作初值。
- 份量：联查默认份量 > 候选基准 > `kDefaultDishPortionG`（100g）。
- 置信度：**未联查命中 → 候选置信度 × `kUncalibratedConfidencePenalty`（0.8）降档**
  （确认卡 <0.5 强制高亮「份量可能不准」）。
- 行级热量 = Σ菜品 kcal（超 5000 截断）；title = 菜名「、」连接截 20 字。

### ImageDishAdapter（识别供应商接缝）

```dart
abstract interface class ImageDishAdapter {
  String get providerId;            // ai_parses.provider
  String get modelId;               // ai_parses.model
  FoodRefSource get dishRefSource;  // 百度=baidu / Vision LLM=llm
  Future<List<DishCandidate>> recognize(CompressedImage image);
}
```

契约：输入恒为压缩规范形；**空列表 = 正常业务分支**（非菜品照片，编排层据此切兜底）；
失败抛 `LlmException` 分类异常（不新增分类）；实现自带超时+瞬时重试。

- `BaiduDishAdapter`：OpenAI 风格无关协议（`POST {base}/rest/2.0/image-classify/v2/dish`，
  表单 `image=urlencode(base64(字节))`）。鉴权两条路：短效 accessToken 直注入，或 AK/SK 经
  OAuth2 `client_credentials` 在线换取（进程内缓存至到期前 60s）。百度无份量输出 → 统一填
  `defaultPortionG`。业务错误码分类：17/19=额度耗尽（quota）、18=QPS 限流、6/100/110/111=鉴权、
  216201/216202=图片非法、其余=服务端瞬时（切兜底）。
- `VisionLlmDishAdapter`：复用 OpenAI 兼容适配器多模态能力（text + image_url data-url 内联）；
  响应经 `extractDishes` 宽容提取（行级字段缺失逐项跳过；模型直报 kcal 只换算每百克参考带回）。
  超时经 `LlmRequest.timeoutOverride` 放宽到 12s。

## 小票解析（ReceiptParser）

```dart
Future<ReceiptParseResult> parse(ReceiptParseRequest request);
```

`ReceiptParseRequest`：`imageBytes` + `mime` + `date`（锚点日）+
**`cloudParseConfirmed`（缺省 false，用户确认闸门——core_ai 无法验证 UI 确认事件，契约由宿主遵守）**。

流程与三态返回（sealed `ReceiptParseResult`）：

| 返回 | 触发条件 | 用途 |
|---|---|---|
| `ReceiptPrefillResult` | OCR 有文本且 `cloudParseConfirmed=false` | 直接落库路径：草稿预填确认卡，**零上云** |
| `ReceiptParsedResult` | 确认后云解析成功 | 携 ParseSuccess（单边 money 行）+ draft |
| `ReceiptParseFailedResult` | OCR 异常 / 坏小票（无文本，draft=null）/ 云解析失败（draft 保留可预填） | 复用 §7.4 降级语义 → 手填 |

- OCR 阶段全端侧：原图不落库不上云，`ReceiptDraft.rawText` 仅端侧内存（不进结构化文本、
  不落 ai_parses）。
- 云解析阶段：`buildReceiptStructuredText(draft)` → 文本管线（`ParseMode.moneyOnly`，
  kind=text，复用同一 AiParser 实例 → 同一缓存/提示词版本）。结构化文本**只含商户/合计/
  小票时间/明细品名（≤`kReceiptTextItemCap`=10 条，不带明细金额）**——金额恰好出现一次，
  杜绝真实 LLM 逐行拆单；无合计金额则文本管线 emptyResult → 手填（不猜金额）。
- 日期预填 `resolveReceiptSuggestedDate`：小票日期合法 → 用小票日期；否则回退请求锚点日。
- 端侧 OCR 不经 ai_parses 留痕（无 LLM 成本）；重跑属预期（端侧廉价），云解析侧靠缓存防重复计费。

### ReceiptOcrAdapter（端侧 OCR 接缝）

```dart
abstract interface class ReceiptOcrAdapter {
  String get providerId;
  String get modelId;
  Future<ReceiptDraft> recognize(ReceiptImageInput image); // 原图字节不出设备
}
```

- 契约：**禁任何 HTTP/云端调用**；空结果返回 `hasText=false` 草稿（不抛异常）；失败抛
  LlmException 分类异常；超时骨架口径 `kReceiptOcrTimeout`=8s（待真机校准）。
- 「识别/理解」分层：通道只回文本行；字段理解全部在 `extractReceiptFields`（纯 Dart 保守
  正则，**宁缺不错**——抽取不到的字段一律 null + warnings）。合计关键词「实收/实付」优先于
  「合计/应付」；明细行以行尾金额为锚点；非真实日期（如 2026-13-40）返回 null 不猜。
- 平台通道协议：通道名 `slimca/receipt_ocr`、method `recognizeReceipt`、args
  `{imageBytes, mime}`、result `{textLines: [...]}`（兼容整段 text）。`MethodChannelReceiptOcrChannel`
  把 MissingPluginException → invalidRequest（native handler 待壳层接线）、PlatformException →
  badResponse。
- `MlKitReceiptOcrAdapter`（Android）/`VisionReceiptOcrAdapter`（iOS）为骨架：**native handler
  由壳层 apps/mobile 接线，真机验收 remaining**；字段级置信度未接入（骨架不猜）。

## dart-define 装配工厂

`createPhotoParser(...)`（photo_factory.dart）装配优先级：

| 配置 | 装配 |
|---|---|
| 双配百度 + AI | `[BaiduDishAdapter, VisionLlmDishAdapter]`（百度先行） |
| 仅百度 | `[BaiduDishAdapter]`——**兜底缺位 → 百度失败即 StructuredFailure，不以 Fake 充数** |
| 仅 AI（SLIMCA_AI_KEY 非空） | `[VisionLlmDishAdapter]`（缺省 DashScope qwen-vl-plus；须视觉模型，注入 gpt-4o-mini 会导致兜底不可用） |
| 全缺省 | `[FakeDishAdapter.fixed()]`（确定性离线桩） |

`createReceiptParser(...)`（receipt_factory.dart）：`SLIMCA_RECEIPT_OCR=mlkit|vision|fake` 显式
指定；未指定按平台（Android→mlkit、iOS→vision、桌面/测试→Fake fixed）；`aiParser` 缺省
`LlmAiParser + HeuristicFakeLlmAdapter`（默认 mock；生产应注入与文本通道同一实例共享缓存）。

凭据键：`SLIMCA_BAIDU_ACCESS_TOKEN` 或 `SLIMCA_BAIDU_API_KEY`+`SLIMCA_BAIDU_SECRET_KEY`、
`SLIMCA_AI_BASE`/`SLIMCA_AI_KEY`/`SLIMCA_AI_MODEL`（与文本通道同一组口径）。显式参数 >
dart-define 常量（测试以参数注入覆盖；`String.fromEnvironment` 是编译期常量，运行期不可改写）。

超时口径：照片总口径 12s（百度 10s 先败先切、Vision 12s）；文本 5s；端侧 OCR 8s（骨架）。
