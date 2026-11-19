# feature_ledger — 记账与统计

业务层模块。账本域的完整 UI + 数据仓库：按日分组账单流（entry+lines join）、月度分类汇总、日简报（day_summary 投影直读）、统计报表（周/月/年三档 + 钱-热量双轴联动）、分类管理（categories 增删改）、每日/月度目标（budgets）、账本生命周期管理（多账本）。

对应产品文档 §3.4（账单页/统计报表）、§5.4④⑤⑥（ledgers/categories/budgets）、§11.1 W5-6、§11.2 W15。

## 模块边界

- **不做录入**：AI 解析→双账落库属 `feature_capture`（../feature_capture/README.md）；本模块只读账 + 提供管理写路径。编辑入口经 `LedgerPage.onEditEntry` 回调由壳唤起录入抽屉 `showCaptureSheet(seed: CaptureSeed(editEntryId:))`，走既有 correction supersede 链（金额不可变，修改=新增行 supersede 旧行）。
- **不直写业务表**：分类直写 categories（本包发 HLC 戳）；budgets 写路径收口 core_db BudgetsDao、账本写路径收口 core_db LedgerDao（outbox 同事务入队由 DAO 强制）。
- **不做同步**：outbox 上送/拉取属 `feature_sync`（../feature_sync/README.md）。
- 不持有 Riverpod Provider——依赖注入为纯构造注入，装配在 `apps/mobile`（../apps-mobile/README.md）。

## 依赖

`core_domain`（LineType/EntryKind 等枚举与日期口径）+ `core_db`（AppDatabase 真值表、BudgetsDao/LedgerDao/LocalWriteClock）+ `ui_kit`（SlimcaTheme 三层 token、SlimcaStaggerItem）+ `drift`（join/customSelect watch）。见 ../core_db/README.md、../ui_kit/README.md。

## 对外 API 索引

全部经包出口 `package:feature_ledger/feature_ledger.dart` 导出。宿主持 `AppDatabase` 单例，按需构造 `DriftLedgerRepository(db)` / `DriftLedgerAdminRepository(db)` / `DriftLedgerManageRepository(db)` / `DriftReportRepository(db)` 注入页面。

| 域 | 接口 | 方法数 | 详情 |
|----|------|--------|------|
| 账单流查询 | `LedgerRepository`（Drift 实现同名前缀 Drift） | 4 watch | [api-bill-view.md](api-bill-view.md) |
| 统计报表 | `ReportRepository` | 2 watch | [api-report.md](api-report.md) |
| 分类/预算管理（写） | `LedgerAdminRepository` | 14（3 watch + 11 写） | [api-admin.md](api-admin.md) |
| 账本生命周期 | `LedgerManageRepository` | 6（2 watch + 4 写） | [api-admin.md](api-admin.md) |
| 页面入口 | `LedgerPage` / `ReportPage` / `LedgerManagePage` / `CategoryManagePage` / `LedgerDayBriefingCard` | 5 | 各 api-*.md「页面」节 |

辅助面：`LedgerFormat`（金额/kcal 格式化与解析）、`LedgerCalendar`（月/周/年区间与轴标签）、`parseBudgetSnapshot`（快照三形态解析）、`normalizeLedgerColorToken` + `ledgerColorFromToken`（语义色 token 白名单与解析）、`reportRangeFor` / `reportBucketKeys`（报表区间与桶轴）。

## 关键服务流程（非平凡）

### 报表桶序列双源合并（watchBucketSeries）

1. 单条 `UNION ALL` SQL watch：entry_lines 聚合分支（兜底，含 draft）+ day_summaries 直读分支（投影，仅全量口径拼入）；
2. Dart 侧按桶「有投影行用投影、无投影行用兜底」合并（`from_summary` 标记位区分）；
3. `reportBucketKeys` 枚举区间全桶零填充——图表 x 轴完整、双轴联动按索引寻址。
4. **per-账本过滤时 day_summary 无拆列，整条走兜底**（UNION 投影分支整体不拼）。

### budget_snapshot 三形态解析（parseBudgetSnapshot）

core_db v2（daily+monthly 双数组）→ core_db v1（仅 daily）→ feature_dashboard 平铺形态（按当日投影值合成 used/remaining）。解析失败一律返回空列表——快照是派生数据，简报卡退化为「目标未设置」提示而非崩溃。月度预算不混入日简报「每日目标」行。

### 账单流按日分组（watchMonthBillGroups）

entry_lines join entries join categories（左连取最新分类名）→ 行级过滤（分类/账本）→ Dart 侧按 entry 归并 facet 行 → 按日聚组降序。**分类筛选在过滤后的行上重算日/月合计**（数字自洽）。

## 数据模型

见 [data-model.md](data-model.md)：LedgerBillEntry/LedgerBillLine（entry_line facet 行的 UI 呈现）、LedgerDayGroup、LedgerDayBriefing + LedgerBudgetItem、LedgerDailyBudget、LedgerSwitchOption、LedgerCategoryOption、ReportRange/ReportBucketPoint/ReportCategoryStack。表结构真值见 ../core_db/README.md（entries/entry_lines/ledgers/categories/budgets/day_summaries/settings）。

## 模块特定约定

- **金额=分、kcal=整数，全程无 double**（§5.1）；展示两位小数、解析最多两位（`LedgerFormat.parseYuanToMinor`）。
- **日期为本地自然日 TEXT** `yyyy-MM-dd` / `yyyy-MM`，固定宽度字典序即时间序；查询一律半开区间 `[start, endExclusive)`。
- **分类色只存语义 token 名**（9 白名单），渲染经 `ledgerColorFromToken` 解析，禁 hex（§8.2，见 ../ui_kit/README.md）。
- **读取活跃口径**：entries.status ∈ {confirmed, edited}（draft 不进账单流/分类汇总）；但报表兜底聚合按投影口径 **draft 计入**——两处口径刻意不同，见 pitfalls.md。
- **删除一律软删墓碑**；分类对账单是逻辑引用（不建外键），已删分类的历史账单 join 落「未分类」；内置 20+ 分类不可删。

## 代码模式索引

见 [code-patterns.md](code-patterns.md)：新增统计视图卡片的完整步骤、新增账单过滤维度的 SQL/predicate 双改点、管理写路径委托 DAO 的套路、新页面装配与测试锚点约定。

## 已知坑点（详见 [pitfalls.md](pitfalls.md)）

- customSelect 的 `readsFrom` 必须显式声明，缺省空集 watch 永不更新。
- drift QueryRow 不支持无类型 `readNullable<Object>`；StreamBuilder 无 errorBuilder 会静默吞流错误（账本列表恒空事故）。
- 报表序列含 draft、账单流不含——对账时数字对不上先查这条。
- 简报 `watchDayBriefing` 恒全量口径（day_summary 无 per-账本拆列），per-账本视角用账单流/报表过滤。

## 详细文档

- [api-bill-view.md](api-bill-view.md) — 账单流查询域（LedgerRepository + LedgerPage + 日简报卡）
- [api-report.md](api-report.md) — 统计报表域（ReportRepository + report_models + ReportPage）
- [api-admin.md](api-admin.md) — 管理域（LedgerAdminRepository + LedgerManageRepository + 分类/账本管理页）
- [data-model.md](data-model.md) — 展示模型与 facet 行呈现、budget_snapshot 三形态
- [code-patterns.md](code-patterns.md) — 代码模式与扩展套路
- [pitfalls.md](pitfalls.md) — 已知坑点
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史
