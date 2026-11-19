# core_ai — AI 解析引擎

> 基础层·共享服务。被 feature_capture 与 apps/mobile（壳装配）依赖。
> 职责：把「一件事」输入（文本/语音转写/照片/小票）解析为「热量 + 花费」双账结构化草稿。
> 本文档基于代码现状（packages/core_ai），不照抄 docs/design/ 规划文档。

## 模块边界

**产出草稿，不落库**。core_ai 只负责到 `ParseSuccess / StructuredFailure / ReceiptPrefillResult`
为止；entries/entry_lines/food_items/attachments 实体化、HLC 发戳、ai_parses 持久留痕的
事务落库由宿主 feature 层（feature_capture 的 CaptureGateway）经 core_db 仓库编排。
食物库联查校准以钩子预留（`AiRefCalibrator` 文本侧 / `DishRefLookup` 拍照侧），缺省透传——
USDA/OpenFoodFacts 快表尚未接入。

依赖方向（pubspec）：`core_domain`（领域枚举 + 日历日校验）、`core_db`（ai_parses 表行对象
+ UUIDv7 生成）、`drift`、`http`、`crypto`、`image`。不依赖任何 feature_* 包。

## 四条管线总览

| 管线 | 入口 | 供应商 | 失败出口 |
|---|---|---|---|
| 文本解析（打字/语音转写） | `AiParser.parse(ParseInput)` | `LlmAdapter`（OpenAI 兼容；缺省 HeuristicFakeLlmAdapter） | `StructuredFailure`（值返回，不抛异常） |
| 拍照识别 | `PhotoParser.parse(PhotoParseRequest)` | 百度菜品识别先行 → Vision LLM 兜底（缺省 FakeDishAdapter.fixed） | `StructuredFailure` |
| 小票解析 | `ReceiptParser.parse(ReceiptParseRequest)` | 端侧 OCR（ML Kit/Vision 平台通道骨架，缺省 Fake）→ 确认后复用文本管线 | `ReceiptParseFailedResult` |
| 结果缓存 | `AiParseCache.find/save` | 内存实现 / Drift 实现（ai_parses 表） | — |

三条解析管线共用一张错误分类表（`LlmException` sealed 家族）与一张降级映射表（§7.4 四级）；
失败一律作值返回（「健壮性即产品体验」），唯一抛点是入口契约违例（非法日历日/空输入）。

## 关键口径（速记）

- 金额一律**分**（int，>0）；热量一律**整数 kcal** ∈ [0,5000]；置信度 ∈ [0,1] 三色档
  （≥0.8 绿 / ≥0.5 黄 / 其余红）。校验器（parse_validator）是硬闸门，schema/提示词只是引导。
- 缓存键 `input_hash = sha256(规范化输入信封)`；**单边模式参与哈希，日期与输入通道不参与**
  （常吃常花跨日重复输入必须命中）。7 天时效由 UUIDv7 id 内嵌时间判定，无 created_at 列；
  `prompt_version` 不同的历史记录视为未命中。
- 校验失败带纠错回喂重试 1 次；适配器内部瞬时重试（超时/网络/限流/5xx，线性退避）与
  解析级重试互不叠加。
- 隐私纪律：拍照原图与小票原图即用即焚（不落库不上云）；小票 OCR 全端侧，云解析需
  `cloudParseConfirmed=true` 用户确认闸门；`StructuredFailure.rawInput` 对照片/小票只落
  描述符（`photo:<hash>` / `receipt:ocr-*`）。

## 快速接入（壳层现行装配）

文本通道由壳层 `apps/mobile/lib/ai/capture_parser_factory.dart` 装配：
key 未配 → `HeuristicFakeLlmAdapter`（确定性离线桩，走完整管线）；key 已配 →
`OpenAiCompatibleAdapter`（缺省 openai.com + gpt-4o-mini，自定义模型退 json_object 宽档）。
拍照/小票通道由本包工厂装配：`createPhotoParser`（`SLIMCA_BAIDU_*` / `SLIMCA_AI_*`）与
`createReceiptParser`（`SLIMCA_RECEIPT_OCR=mlkit|vision|fake`）。凭据只走 dart-define/
环境变量，不入仓库文件。

## 详细文档

- [api-parse.md](api-parse.md) — 文本解析入口：AiParser 签名/参数/返回/错误、缓存、分类解析
- [api-receipt.md](api-receipt.md) — 拍照（百度/Vision 双供应商）与小票端侧 OCR 路径
- [api-llm.md](api-llm.md) — LLM 通道：adapter 接口/预设/错误分类、缓存实现、四级降级、Fake 切换
- [data-model.md](data-model.md) — 解析结果模型：双账行草稿/菜品明细/留痕记录/小票草稿字段结构
- [code-patterns.md](code-patterns.md) — 扩展点操作路径：接入新 LLM 供应商 / 新识别渠道 / 新 OCR / 联查库
- [pitfalls.md](pitfalls.md) — 坑点清单（key 纪律、通道 id≠展示名、超时与降级、Fake 切换条件等）
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（最新在上，含跨模块影响与风险）

## 跨模块引用

- ai_parses 表 schema、UUIDv7 生成：../core_db/README.md（core_ai 直读直写该表）
- LineType/LineDirection/EntryKind 枚举与 `validateCalendarDay`：../core_domain/README.md
- AI 双解析流状态机、确认卡、CaptureGateway 落库（ai_parses 持久留痕承担方）：../feature_capture/README.md
- 壳层装配（capture_parser_factory/bridge、photo_parser_factory）：见 apps/mobile 壳文档

## 测试布局（结构性）

test/ 共 18 文件（约 4300 行）：管线按域分文件（parser_validation/cache/retry_failure、
photo_pipeline/photo_draft/photo_factory、receipt_parser/receipt_field_extractor/
receipt_ocr_adapters、baidu/vision adapter、openai_adapter、fakes、image_compressor）。
硬规则：测试一律离线（MockClient/Fake 注入）；唯一豁免 `live_llm_smoke_test.dart`——
`SLIMCA_AI_KEY` 环境变量缺席整组 skip。DriftAiParseCache 测试在宿主缺 sqlite3 运行库时
温和跳过。
