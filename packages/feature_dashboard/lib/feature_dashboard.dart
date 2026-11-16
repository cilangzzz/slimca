/// Slimca 日期仪表盘（feature_dashboard，§10.4 packages/feature_dashboard）。
///
/// 职责（§3.2 统一日期仪表盘、§11.1 W2 主线「仪表盘骨架填充 + day_summary
/// 投影 v1——手动记一笔→仪表盘环/支出卡即时更新」）：
/// - 真页 [DashboardPage]：日期大字 + 周历条（7 日可点选）+ 卡片墙；
/// - 切日用 SlimcaSharedAxisSwitcher（§9.3#2，280ms ≤ 切日预算），入场用
///   SlimcaStaggerItem 级联（§9.3#1，80ms 级联上浮）；
/// - 卡片墙：热量环（摄入/消耗/净+预算余）、今日支出+本月累计、净热量、
///   存钱进度占位（读 day_summary.savings_progress，§5.6⑬）；
/// - 空态：当日无记录时引导首次录入（§3.2）。
///
/// 数据源：构造注入 [DashboardRepository]（§10.4 分层——页面不依赖
/// AppDatabase 具体类），watch 投影流直驱（§5.6⑬「冷启动首帧直读本表、
/// 零业务查询」），全程无 spinner（§3.2 快照直出）。
library;

// ── 数据契约（§5.6⑬ day_summary 投影的读侧映射）────────────────
export 'src/dashboard_models.dart';
export 'src/dashboard_repository.dart';

// ── 日历工具（§5.1 本地日历日口径）──────────────────────────────
export 'src/calendar.dart';

// ── 页面（§3.2）─────────────────────────────────────────────────
export 'src/widgets/dashboard_page.dart';
export 'src/widgets/day_cards.dart';
