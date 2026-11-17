/// Slimca 录入域（§10.4 packages/feature_capture）。
///
/// W2 主线（§11.1 W2「手动记账 CRUD 全链路（无 AI）」）：
/// - 手动记账表单 [CapturePage]（仅记钱档）：金额数字键盘（分存储）、方向
///   in/out、分类/账本/日期/备注（§3.3/§3.4）；
/// - 提交经 EntryRepository 落库：entries(kind=expense) + entry_lines
///   (type=money)，HLC 由 HlcClock 签发（§6.3）；
/// - 编辑既有记录 = 新增 correction 行 supersede 旧行（金额不可变，§3.4），
///   corrections 审计行随写落库（§5.6⑮）；
/// - Riverpod AsyncNotifier 控制器 [captureControllerProvider] 供宿主注入。
///
/// W3-4 主线（§11.1「AI 双解析闭环（文本）」、§3.3、§2.4）：
/// - AI 双解析流：文本输入区 [CaptureAiInput] → 解析中呼吸态
///   [CaptureParsingState] → 确认卡 [CaptureConfirmCard]（AI 初值预填 +
///   SlimcaCountUp 800ms + 热量环 sweep + SlimcaConfidenceDot 三档 + 份量
///   滑杆联动重算，§9.3#4、§2.3 步骤 3-4）→ 确认经
///   [CaptureGateway.submitAiCapture] 同事务落库（entries + calorie/money 行 +
///   food_items + ai_parses 留痕 + corrections 差异审计，§5.2/§5.6⑭⑮）；
/// - 解析器抽象 [CaptureParser] 与注入点 [captureParserProvider]（§7.1
///   adapter 在 core_ai，宿主桥接 override；测试注入 Fake，禁真实网络）；
/// - input_hash 缓存（§3.3/§5.6⑭ sha256 + UUIDv7 内嵌时间戳 7 天时效）；
/// - 失败降级（§7.4）：结构化失败/超时 → 自动手填表单，原文保留；
/// - 最近记录 chip 复记（§2.4-1 ≤5 秒，[kRecentChipLimit] 条横滑）；
/// - 单边开关（§3.3）：钱+热量 / 仅记钱 / 仅记热量（kcal-only 只产 calorie 行）。
///
/// W11-12 主线「拍照通道」（§11.2、§3.3 拍照通道、§3.7 数据主权、§5.6㉑）：
/// - 入口 [CapturePhotoEntry]（拍照/相册双入口 + raw_input 口径隐私提示）→
///   [CaptureController.startPhotoCapture]：取图（[CaptureImageSource]，
///   image_picker 薄封装由壳注入；测试用 [FakeImageSource]）→ 端侧压缩
///   （[CaptureImageCompressor]，长边 1280、JPEG q80 常量
///   [kCaptureCompressLongEdge]/[kCaptureCompressJpegQuality]）→ raw_input
///   上云闸门分流（[captureRawInputCloudEnabledProvider] 默认关=字节不出端：
///   [CaptureOnDeviceEstimator] 端侧粗估 + 人工确认；开=[CapturePhotoParser]
///   云端识别 12s 超时，[CapturePhotoParserFallback] 百度→Vision 双供应商）→
///   确认卡复用（W3-4 份量滑杆联动）→ [CaptureGateway.submitAiCapture]
///   落库（source=photo，kind 按行集合推导，§5.2①）；
/// - 解析后即焚（§3.7/§11.2 任务 3）：确认落库成功后经
///   [CaptureAttachmentStore.registerBurned] 登记 attachments 行（登记即
///   burned，blob_ref 恒 NULL=原图不落服务端；现成桥接
///   [DbCaptureAttachmentStore] 调 core_db AttachmentsDao——先删文件再推
///   `active → burned` 状态机，§5.6㉑）+ 控制器兜底删除临时文件；关闭上云时
///   [captureOnDeviceEstimatorProvider] 缺省 [NoOnDeviceEstimator]（最严
///   兜底：无端侧模型直接人工确认，绝不把字节送出端）；
/// - 失败降级（§11.2 任务 4）：识别失败/超时/端侧无法估计 → 自动手填且
///   待焚原件保留——已拍数据在用户确认前绝不即焚；
/// - 漏斗埋点（§11.2 任务 5、§2.3）：[CapturePhotoFunnel]
///   photo_capture_open/photo_parse_result/photo_confirm + 全程护栏
///   [kPhotoPathGuardMs]/[photoPathWithinGuard]（拍照 ≤15s，metric 复用
///   capture_open_to_confirm_ms，tags.path='photo'）；
/// - 确定性 Fake 集（[FakeImageSource]/[FakeImageCompressor]/
///   [FakeCapturePhotoParser]/[FakeCaptureOnDeviceEstimator]/
///   [FakeCaptureAttachmentStore]）供测试与壳层预览，禁真实网络/相机
///   （§11.2 硬规则）。
///
/// DI 契约（§10.4 壳负责装配）：宿主 override
/// `captureGatewayProvider.overrideWithValue(
///   createCaptureGateway(db: AppDatabase, clock: HlcClock))`（可选注入
///   DaySummaryProjection 联动仪表盘投影，§5.6⑬）与
/// `captureParserProvider.overrideWithValue(coreAiAdapterBridge)`。
/// W11-12 拍照通道新增注入点：[captureImageSourceProvider]（image_picker
/// 薄封装）、[captureImageCompressorProvider]（端侧压缩插件）、
/// [capturePhotoParserProvider]（百度菜品识别→Vision LLM 组合，真实凭据
/// 未提供，按 dart-define/配置注入，缺省 Fake，remaining：待凭据联调）、
/// [captureRawInputCloudEnabledProvider]（settings RawInputPolicy 同步读）、
/// [captureOnDeviceEstimatorProvider]（端侧 OCR/模型，缺省最严兜底）、
/// [captureAttachmentStoreProvider]（注入 [DbCaptureAttachmentStore] 桥接
/// core_db AttachmentsDao 即焚状态机，§5.6㉑）、
/// [capturePhotoTelemetryProvider]（TelemetryService，缺省
/// 不发事件）。
/// 持久化实现复用 core_db 的 DriftEntryRepository/DriftEntryLineRepository
/// （§10.4「实现在 core_db」），本库只做录入编排与审计落库。
library;

export 'src/capture_attachment_store.dart';
export 'src/capture_controller.dart';
export 'src/capture_gateway.dart';
export 'src/capture_models.dart';
export 'src/capture_money.dart';
export 'src/capture_page.dart';
export 'src/capture_parser.dart';
export 'src/capture_photo_compressor.dart';
export 'src/capture_photo_estimator.dart';
export 'src/capture_photo_fakes.dart';
export 'src/capture_photo_models.dart';
export 'src/capture_photo_parser.dart';
export 'src/capture_photo_source.dart';
export 'src/capture_photo_telemetry.dart';
export 'src/widgets/capture_ai_input.dart';
export 'src/widgets/capture_amount_input.dart';
export 'src/widgets/capture_category_picker.dart';
export 'src/widgets/capture_confirm_card.dart';
export 'src/widgets/capture_date_row.dart';
export 'src/widgets/capture_direction_toggle.dart';
export 'src/widgets/capture_ledger_picker.dart';
export 'src/widgets/capture_parsing_state.dart';
export 'src/widgets/capture_photo_entry.dart';
export 'src/widgets/capture_recent_chips.dart';
export 'src/widgets/capture_side_toggle.dart';
export 'src/widgets/capture_text_field.dart';
