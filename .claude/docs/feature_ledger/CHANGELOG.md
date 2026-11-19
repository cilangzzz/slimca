# Changelog - feature_ledger

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。

---

## [2026-11-17] W15 多账本+预算体系+统计报表（周/月/年+钱-热量双轴）

**类型**: feat
**提交**: fd9d619
**风险**: HIGH

本模块从「记账雏形」扩为完整账本域：新增统计报表域与账本生命周期域，预算快照升级 v2，账单流接入多账本过滤。**HIGH 原因**：budget_snapshot 数据形状变更（v1→v2）+ 同提交改了 core_db 数据层与 ui_kit 转场（跨模块）。

### 变更文件（feature_ledger 范围，17 文件 +4315/-169）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/report_repository.dart | +216/-0 | 新增 DriftReportRepository：桶序列 day_summary 直读 + entry_lines 兜底 UNION watch；分类堆叠桶×分类聚合；per-账本过滤整条走兜底 |
| lib/src/report_models.dart | +156/-0 | ReportPeriod/ReportRange/reportRangeFor/reportBucketKeys（桶轴零填充）+ ReportBucketPoint/ReportCategoryStack |
| lib/src/widgets/report_page.dart | +1213/-0 | ReportPage：周/月/年三档切换 + 支出构成堆叠条 + 热量趋势折线（in/out/net 三线）+ 钱-热量双轴联动（点桶三面板同步高亮 + 详情条），全部 CustomPainter + 语义 token 配色 |
| lib/src/ledger_manage_repository.dart | +141/-0 | 新增 LedgerManageRepository：账本切换/归档清单读取（单 SQL 联查 settings 默认指针）+ 写路径委托 core_db LedgerDao |
| lib/src/widgets/ledger_manage_page.dart | +474/-0 | 账本管理页：默认徽标/内置 kcal 只读行/新建/重命名/归档恢复 + 测试锚点常量 |
| lib/src/ledger_models.dart | +151/-31 | parseBudgetSnapshot 扩 v2 解包（daily+monthly 双数组、周期窗口/结转），v1/平铺形态向后兼容 |
| lib/src/ledger_admin_repository.dart | +124/-102 | 预算写路径收口 core_db BudgetsDao（原直写 budgets 改委托：outbox 同事务入队 + 快照联动）；新增 watchMonthlyBudgets/setMonthlySpendGoal/clearMonthlySpendGoal；目标账本解析改 settings 默认指针优先 |
| lib/src/ledger_repository.dart | +35/-10 | watchMonthBillGroups/watchMonthCategorySums 增加 ledgerId 可选过滤（行级 ledger_id） |
| lib/src/widgets/category_manage_page.dart | +228/-3 | 新增月度支出目标区（金额+周期起点 1..28+结转开关对话框）与测试锚点 |
| lib/src/ledger_calendar.dart | +74/-0 | W15 周期口径：weekRange/yearRange/shiftWeek/shiftYear + 轴标签/周标题助手 |
| lib/src/widgets/ledger_page.dart | +179/-10 | 账本筛选条（全部+可用账本）与账本管理/统计入口接线 |
| lib/src/widgets/ledger_brief_card.dart | +8/-1 | 日简报只渲染 daily 周期预算（月度预算不混入每日目标行） |
| lib/feature_ledger.dart | +37/-12 | 导出新增域（ReportRepository/LedgerManageRepository/两页面） |
| test/report_repository_test.dart | +442/-0 | 报表聚合 oracle 对账：随机全年数据逐桶对账 |
| test/report_page_test.dart | +340/-0 | 双轴联动选中/跨面板同步/反选、三档切换 |
| test/multiledger_filter_test.dart | +297/-0 | 多账本过滤互斥：账单流/汇总/报表序列 per-账本拆分自洽 |
| test/budget_snapshot_v2_compat_test.dart | +200/-0 | v2/v1/平铺三形态兼容 + 简报不混月度预算 |

### 集成修复（同提交，非 feature_ledger 文件但直接关系本模块行为）

- 修 ledger_manage_repository 流恒空：drift QueryRow 不支持无类型 readNullable\<Object\>（抛 Could not find a matching SQL type）→ settings.value 恒 TEXT 改 readNullable\<String\>；StreamBuilder 无 errorBuilder 静默吞错是表现层放大器。
- 修报表桶序列 per-账本分支 SQL 占位符与变量数不匹配（Expected 5 got 3）：day_summaries UNION 分支整体不拼、变量同步不传。

### 影响范围

- **API**: 新增 ReportRepository（2 watch）、LedgerManageRepository（6 方法）、LedgerAdminRepository 月度目标 3 方法；LedgerRepository 两方法加 ledgerId 可选参数（向后兼容）。
- **跨模块**: core_db（LedgerDao 多账本生命周期、BudgetsDao 预算 CRUD、day_summary 投影 budget_snapshot v2）、apps/mobile（/stats 路由、预算设置页、录入页账本选择器、仪表盘接快照 v2、W15 漏斗）、ui_kit（新增 SlimcaSharedAxisPage）。全仓 597 用例全绿。
- **数据模型**: budget_snapshot JSON v1→v2（双数组），升级期三形态兼容读取；budgets 表启用 period=daily/monthly + day_of_month_start/carry_over 列。
- **配置**: 无新增配置项。

### 回滚指南

- 回滚: `git revert fd9d619`（会连带回滚 core_db 的 BudgetsDao/LedgerDao 与 apps/mobile 装配——三路集成收口提交，单独回滚本包会编译失败）。
- 检查文件: packages/feature_ledger/lib/src/report_*.dart、ledger_manage_repository.dart、ledger_admin_repository.dart、packages/core_db/lib/src/dao/{budgets_dao,ledger_dao,day_summary_projection}.dart、apps/mobile/lib/app/{router,providers}.dart。
- 副作用: 已写入的 v2 快照（monthly 数组）与 monthly budgets 行在旧代码下被忽略/不解析（v1 解析器只读 daily，数据不丢但月度预算功能消失）；apps/mobile 的 /stats 路由与预算设置页一并消失；budget_snapshot_v2 测试与多账本测试删除。

---

## [2026-11-16] W5-6 记账完整化+语音(Fake链路)+健身+同步引擎（M1 功能项）

**类型**: feat
**提交**: 3022e4d
**风险**: HIGH

本模块功能奠基：账单流/日简报/分类管理/每日目标全量落地。**HIGH 原因**：同提交修复 core_db 投影联动核心 bug（DriftEntryLineRepository.upsert 误传 date，影响所有走采集写入的投影行）+ feature_sync 同步引擎同步落地（跨模块核心流程变更）。

### 变更文件（feature_ledger 范围，14 文件 +4281/-47）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/ledger_repository.dart | +267/-0 | LedgerRepository 接口 + Drift 实现：按日分组账单流（行级分类过滤、合计重算）、月度分类汇总（customSelect）、日简报（day_summary 直读 + 快照解析）、分类选项流 |
| lib/src/ledger_admin_repository.dart | +406/-0 | 分类增删改（HLC 戳、软删墓碑、内置不可删）+ 每日目标 set/clear（当期直写 budgets，W15 已收口） |
| lib/src/ledger_models.dart | +374/-0 | LedgerBillLine/LedgerBillEntry/LedgerDayGroup/LedgerDayBriefing/LedgerDailyBudget/LedgerCategoryOption + parseBudgetSnapshot（v1/平铺双形态） |
| lib/src/widgets/ledger_page.dart | +707/-0 | 账本 Tab 页：简报卡+月份切换+分类筛选+汇总卡+按日分组账单流+空态引导 |
| lib/src/widgets/category_manage_page.dart | +865/-0 | 分类管理页：每日目标卡 + 分类清单（增删改对话框、语义色 token 选择） |
| lib/src/widgets/ledger_brief_card.dart | +244/-0 | 日简报卡：三指标 + 预算达成行（超支标红） |
| lib/src/ledger_format.dart | +96/-0 | 金额/kcal 格式化与解析（分↔元、无 double） |
| lib/src/ledger_calendar.dart | +109/-0 | 月口径助手：monthRange/shiftMonth/monthTitle/dayGroupTitle 等 |
| lib/src/ledger_colors.dart | +24/-0 | ledgerColorFromToken：语义 token→Color 解析 |
| lib/feature_ledger.dart | +38/-5 | 包出口扩为完整导出面 |
| pubspec.yaml | +16/-36 | 依赖 core_domain/core_db/ui_kit 正式接线（workspace path 依赖） |
| test/feature_ledger_test.dart | +214/-6 | 格式化/日历/快照解析/token 白名单单测 |
| test/category_manage_test.dart | +429/-0 | 分类管理与每日目标 widget 测试 |
| test/ledger_page_test.dart | +492/-0 | 账单流/筛选/简报卡 widget 测试 |

### 影响范围

- **API**: 模块 API 面从 0 建立——4 仓库接口前三个（LedgerRepository 4 watch、LedgerAdminRepository 12 方法、LedgerPage/CategoryManagePage/LedgerDayBriefingCard）。
- **跨模块**: core_db（投影 date 误传 bug 修复——采集写入路径投影行此前必炸「父事件不存在」；修 dayPattern 捕获组 RangeError——本模块 dayGroupTitle/日简报卡曾整页崩）、feature_sync（新增包）、feature_plan、apps/mobile（壳装配+路由）、core_ai。本包测试 25 例全绿。
- **数据模型**: 无表结构变更（消费 core_db schema v1）；budget_snapshot 读 v1 形态。
- **配置**: 无。

### 回滚指南

- 回滚: `git revert 3022e4d`（将清空整个模块功能并连带回滚 feature_sync/feature_plan/壳装配；本包 0 功能可用是回滚后的正常态——W1 骨架保留在更早提交）。
- 检查文件: packages/feature_ledger/lib/src/**（全量）、packages/core_db/lib/src/**/entry_line_repository.dart（投影修复不在回滚后重现——需单独评估）、apps/mobile/lib/app/router.dart。
- 副作用: core_db 投影 date bug 修复随本提交一起被 revert，采集路径投影行会重新炸；壳路由对本包页面的引用一并消失；依赖本包测试锚点的集成测试失效。

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: chore
**提交**: 3b1f64c
**风险**: LOW

pub workspace 建仓提交：feature_ledger 仅含包骨架（pubspec/README/analysis_options/占位测试），无业务代码。

### 变更文件（feature_ledger 范围，9 文件 +160/-0）

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +55/-0 | 包声明：workspace 成员、sdk ^3.8.0 |
| .gitignore / .metadata / LICENSE / analysis_options.yaml / CHANGELOG.md | +49/-0 | Flutter 包脚手架 |
| README.md | +39/-0 | pub 模板占位 |
| lib/feature_ledger.dart | +5/-0 | 空库占位 |
| test/feature_ledger_test.dart | +12/-0 | 占位测试 |

### 影响范围

- **API**: 无。
- **跨模块**: 同提交创建全部 10 包 + CI + Supabase 迁移（仓库奠基提交）；对本包无行为影响。
- **数据模型**: 无。
- **配置**: pub workspace 聚合（根 pubspec.yaml）。
