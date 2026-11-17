/// Slimca 账本域特性包（§11.1 W5-6「分类/每日目标/日简报」主线 +
/// §11.2 W15「多账本+预算体系+统计报表」主线）。
///
/// ## 导出内容
///
/// - `LedgerRepository` / `DriftLedgerRepository`：账单流（按日分组）、月度
///   分类汇总、日简报（day_summary 投影直读）与分类选项的响应式读取
///   （§3.4、§5.6⑬）；W15 多账本：账单流/分类汇总带 ledgerId 过滤
///   （§5.4④，过滤集合互斥）。
/// - `ReportRepository` / `DriftReportRepository`（W15）：统计报表数据层——
///   桶序列（周/月档按日、年档按月；day_summary 直读 + entry_lines 聚合
///   兜底，§5.6⑬）与桶×分类支出堆叠切片（§3.4）。
/// - `LedgerAdminRepository` / `DriftLedgerAdminRepository`：分类增删改
///   （逻辑引用 categories 表，§5.4⑤）与每日/月度目标落库（budgets
///   period=daily/monthly，§5.4⑥；W15 起预算写路径收口 core_db
///   BudgetsDao：outbox 同事务入队 + budget_snapshot v2 联动）。
/// - `LedgerManageRepository` / `DriftLedgerManageRepository`（W15）：账本
///   生命周期——建账本/重命名/归档软删/切换默认（写路径委托 core_db
///   LedgerDao；kcal 账本不可删不可多开由 DAO 强制，§5.4④）。
/// - `LedgerPage`：账本 Tab 页——日简报卡 + 账本筛选条（W15）+ 月份切换 +
///   分类筛选 + 按日分组账单列表 + 月度分类汇总；统计入口 push
///   [ReportPage]、账本管理入口 push [LedgerManagePage]；编辑入口回调走
///   既有 correction supersede 链（§3.3 金额不可变，§10.4 由壳接线
///   `showCaptureSheet(seed:)`）。
/// - `ReportPage`（W15，§3.4 统计报表）：周/月/年三档切换；金额按分类
///   堆叠条形（CustomPainter，语义 token 配色）+ 热量按日折线（in/out/net
///   三线）+ 钱-热量双轴联动视图（点桶三面板同步高亮 + 详情条）。
/// - `LedgerManagePage`（W15，§5.4④）：账本管理页——默认徽标/重命名/
///   设为默认/归档/恢复；kcal 内置账本只读行。
/// - `CategoryManagePage`：分类管理页——每日目标（总支出/总热量/分类）+
///   月度支出目标（周期起点/结转，W15）与分类增删改（内置分类不可删，
///   §5.4⑤）。
/// - `LedgerDayBriefingCard`：日简报卡片（§3.4：今日收支/热量摘要，数据走
///   day_summary 投影）。
/// - 模型/格式化/日历助手：`ledger_models.dart`（含 budget_snapshot v2/
///   v1/平铺三形态兼容解析 parseBudgetSnapshot、LedgerSwitchOption）/
///   `ledger_format.dart` / `ledger_calendar.dart`（含 W15 周/年区间与
///   图表轴标签）/ `ledger_colors.dart` / `report_models.dart`。
///
/// ## 装配约定
///
/// 依赖注入采用构造注入（与 feature_dashboard 同款，§10.4 分层纪律）：
/// 宿主（apps/mobile）持有 `AppDatabase` 单例，按需构造
/// `DriftLedgerRepository(db)` / `DriftLedgerAdminRepository(db)` /
/// `DriftLedgerManageRepository(db)` / `DriftReportRepository(db)` 注入页面；
/// 编辑入口经 `LedgerPage.onEditEntry` 回调由壳唤起录入抽屉
/// `showCaptureSheet(seed: CaptureSeed(editEntryId: id))`。
library;

export 'src/ledger_admin_repository.dart';
export 'src/ledger_calendar.dart';
export 'src/ledger_colors.dart';
export 'src/ledger_format.dart';
export 'src/ledger_manage_repository.dart';
export 'src/ledger_models.dart';
export 'src/ledger_repository.dart';
export 'src/report_models.dart';
export 'src/report_repository.dart';
export 'src/widgets/category_manage_page.dart';
export 'src/widgets/ledger_brief_card.dart';
export 'src/widgets/ledger_manage_page.dart';
export 'src/widgets/ledger_page.dart';
export 'src/widgets/report_page.dart';
