/// Slimca 录入域（§10.4 packages/feature_capture）。
///
/// W2 主线（§11.1 W2「手动记账 CRUD 全链路（无 AI）」）：
/// - 手动记账录入页 [CapturePage]：金额数字键盘（分存储）、方向 in/out、
///   分类/账本/日期/备注（§3.3/§3.4）；
/// - 提交经 EntryRepository 落库：entries(kind=expense) + entry_lines
///   (type=money)，HLC 由 HlcClock 签发（§6.3）；
/// - 编辑既有记录 = 新增 correction 行 supersede 旧行（金额不可变，§3.4），
///   corrections 审计行随写落库（§5.6⑮）；
/// - 单边开关（§3.3）state 字段先行冻结，热量输入区 W3-4 接 AI；
/// - Riverpod AsyncNotifier 控制器 [captureControllerProvider] 供宿主注入。
///
/// DI 契约（§10.4 壳负责装配）：宿主 override
/// `captureGatewayProvider.overrideWithValue(
///   createCaptureGateway(db: AppDatabase, clock: HlcClock))`（可选注入
///   DaySummaryProjection 联动仪表盘投影，§5.6⑬）。持久化实现复用 core_db
/// 的 DriftEntryRepository/DriftEntryLineRepository（§10.4「实现在 core_db」），
/// 本库只做录入编排与 corrections 审计落库（§5.6⑮）。
library;

export 'src/capture_controller.dart';
export 'src/capture_gateway.dart';
export 'src/capture_models.dart';
export 'src/capture_money.dart';
export 'src/capture_page.dart';
export 'src/widgets/capture_amount_input.dart';
export 'src/widgets/capture_category_picker.dart';
export 'src/widgets/capture_direction_toggle.dart';
export 'src/widgets/capture_ledger_picker.dart';
export 'src/widgets/capture_side_toggle.dart';
