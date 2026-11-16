/// Slimca 账本域特性包（§11.1 W5-6「分类/每日目标/日简报」主线）。
///
/// ## 导出内容
///
/// - `LedgerRepository` / `DriftLedgerRepository`：账单流（按日分组）、月度
///   分类汇总、日简报（day_summary 投影直读）与分类选项的响应式读取
///   （§3.4、§5.6⑬）。
/// - `LedgerAdminRepository` / `DriftLedgerAdminRepository`：分类增删改
///   （逻辑引用 categories 表，§5.4⑤）与每日目标落库（budgets
///   period=daily，§5.4⑥），写入带 HLC 戳（§6.2 写路径纪律）。
/// - `LedgerPage`：账本 Tab 页——日简报卡 + 月份切换 + 分类筛选 +
///   按日分组账单列表 + 月度分类汇总；编辑入口回调走既有 correction
///   supersede 链（§3.3 金额不可变，§10.4 由壳接线 `showCaptureSheet(seed:)`）。
/// - `CategoryManagePage`：分类管理页——每日目标设置（总支出/总热量/分
///   类）与分类增删改（内置分类不可删，§5.4⑤）。
/// - `LedgerDayBriefingCard`：日简报卡片（§3.4：今日收支/热量摘要，数据走
///   day_summary 投影）。
/// - 模型/格式化/日历助手：`ledger_models.dart` / `ledger_format.dart` /
///   `ledger_calendar.dart` / `ledger_colors.dart`。
///
/// ## 装配约定
///
/// 依赖注入采用构造注入（与 feature_dashboard 同款，§10.4 分层纪律）：
/// 宿主（apps/mobile）持有 `AppDatabase` 单例，按需构造
/// `DriftLedgerRepository(db)` / `DriftLedgerAdminRepository(db)` 注入页面；
/// 编辑入口经 `LedgerPage.onEditEntry` 回调由壳唤起录入抽屉
/// `showCaptureSheet(seed: CaptureSeed(editEntryId: id))`。
library;

export 'src/ledger_admin_repository.dart';
export 'src/ledger_calendar.dart';
export 'src/ledger_colors.dart';
export 'src/ledger_format.dart';
export 'src/ledger_models.dart';
export 'src/ledger_repository.dart';
export 'src/widgets/category_manage_page.dart';
export 'src/widgets/ledger_brief_card.dart';
export 'src/widgets/ledger_page.dart';
