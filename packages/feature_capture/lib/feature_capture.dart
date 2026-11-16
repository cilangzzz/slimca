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
/// DI 契约（§10.4 壳负责装配）：宿主 override
/// `captureGatewayProvider.overrideWithValue(
///   createCaptureGateway(db: AppDatabase, clock: HlcClock))`（可选注入
///   DaySummaryProjection 联动仪表盘投影，§5.6⑬）与
/// `captureParserProvider.overrideWithValue(coreAiAdapterBridge)`。
/// 持久化实现复用 core_db 的 DriftEntryRepository/DriftEntryLineRepository
/// （§10.4「实现在 core_db」），本库只做录入编排与审计落库。
library;

export 'src/capture_controller.dart';
export 'src/capture_gateway.dart';
export 'src/capture_models.dart';
export 'src/capture_money.dart';
export 'src/capture_page.dart';
export 'src/capture_parser.dart';
export 'src/widgets/capture_ai_input.dart';
export 'src/widgets/capture_amount_input.dart';
export 'src/widgets/capture_category_picker.dart';
export 'src/widgets/capture_confirm_card.dart';
export 'src/widgets/capture_date_row.dart';
export 'src/widgets/capture_direction_toggle.dart';
export 'src/widgets/capture_ledger_picker.dart';
export 'src/widgets/capture_parsing_state.dart';
export 'src/widgets/capture_recent_chips.dart';
export 'src/widgets/capture_side_toggle.dart';
export 'src/widgets/capture_text_field.dart';
