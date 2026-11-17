/// Slimca AI 解析域（§10.4 packages/core_ai：LLM adapter + JSON Schema +
/// 校准联查接缝；§11.1 W3-4「AI 双解析闭环（文本）」的管线与缓存底座）。
///
/// 内容（§7 管线）：
/// - LLM 适配器抽象与 OpenAI 兼容实现（可配 baseUrl/apiKey/model；预设
///   GPT-4o-mini / Qwen-VL / GLM-4V；response_format json_schema 与
///   json_object 两档 capability；多模态 content 段（text + image_url，
///   §3.3 拍照通道）；超时/重试/错误分类，§7.1/§7.5）；
/// - AiParser 管线（规范化 → input_hash → 缓存回放 → 受约束 JSON 解码 →
///   字段校验/§7.3 映射 → 校验失败重试 1 次 → StructuredFailure 一级降级，
///   §7.1-§7.4）；
/// - input_hash 缓存（§5.6⑭ ai_parses：<7 天时效、UUIDv7 id 内嵌时间判定；
///   内存实现与 Drift 实现）；
/// - 拍照通道（§3.3 拍照通道 P1、§11.2 W11-12 主线）：端侧压缩抽象与
///   纯 Dart 实现（长边 1280/JPEG q80）、百度菜品识别适配器（OpenAI 风格
///   无关 HTTP 协议）、Vision LLM 适配器（复用 OpenAI 兼容 vision 能力，
///   响应走 §7.2 口径）、双供应商 fallback 编排 [PhotoParser]（百度先行 →
///   Vision 兜底 → StructuredFailure 复用既有降级语义）、food_items 草稿
///   组装（§5.2③，联查钩子 [DishRefLookup] 留接口）、dart-define 装配工厂
///   （SLIMCA_BAIDU_* / SLIMCA_AI_*，缺省 Fake——真实凭据待联调）；
/// - 四级降级接口（§7.4：一级内建于 StructuredFailure，二三四级留接口）；
/// - 端侧小票 OCR（§11.2 W16 主线、§10.1 OCR 行「ML Kit/Vision 端侧——不
///   传原图」、§3.7 端侧优先「OCR 全端侧，仅用户确认后才走云解析或直接
///   落库——不自动上云」）：ReceiptOcrAdapter 抽象（图片字节→ReceiptDraft
///   商户/合计/时间/明细行）、端侧字段抽取器（纯 Dart 保守正则，不猜——
///   宁缺不错）、ML Kit/Vision 平台通道适配器骨架（通道桥注入；native
///   handler 待壳层接线，remaining 真机验收）、FakeReceiptOcrAdapter
///   （fixture，默认 mock）、ReceiptDraft→结构化文本→复用既有 AiParser
///   文本管线（单边 money，§3.3）的衔接管线与 dart-define 装配工厂；
/// - 确定性 Fake（FakeLlmAdapter / FakeAiParser / FakeDishAdapter /
///   FakeReceiptOcrAdapter，测试与预览用）；
/// - 缺省离线桩（HeuristicFakeLlmAdapter：正则抽取产 §7.2 受约束 JSON，
///   宿主未配 API key 时经 LlmAiParser 走完整管线的「默认 mock」，§11.1）。
///
/// 分层边界（§10.4）：本库产出解析草稿（ParseSuccess/StructuredFailure），
/// entries/entry_lines 实体化、HLC 发戳与落库由宿主 feature 层经 core_db
/// 仓库编排；食物库联查校准（§7.1 第 6 步）以 AiRefCalibrator（文本）与
/// DishRefLookup（拍照）钩子预留。
library;

export 'src/cache/ai_parse_cache.dart';
export 'src/cache/drift_ai_parse_cache.dart';
export 'src/degrade/degrade_hooks.dart';
export 'src/fake/fake_adapter.dart';
export 'src/fake/fake_dish_adapter.dart';
export 'src/fake/fake_parser.dart';
export 'src/fake/fake_receipt_ocr_adapter.dart';
export 'src/fake/heuristic_fake_adapter.dart';
export 'src/llm/llm_adapter.dart';
export 'src/llm/openai_adapter.dart';
export 'src/parse/ai_parser.dart';
export 'src/parse/parse_categories.dart';
export 'src/parse/parse_models.dart';
export 'src/parse/parse_schema.dart';
export 'src/parse/parse_validator.dart';
export 'src/photo/baidu_dish_adapter.dart';
export 'src/photo/image_compressor.dart';
export 'src/photo/photo_factory.dart';
export 'src/photo/photo_models.dart';
export 'src/photo/photo_parser.dart';
export 'src/photo/vision_dish_adapter.dart';
export 'src/receipt/platform_receipt_ocr_adapters.dart';
export 'src/receipt/receipt_factory.dart';
export 'src/receipt/receipt_field_extractor.dart';
export 'src/receipt/receipt_models.dart';
export 'src/receipt/receipt_ocr_adapter.dart';
export 'src/receipt/receipt_ocr_channel.dart';
export 'src/receipt/receipt_parser.dart';
export 'src/receipt/receipt_text_bridge.dart';
