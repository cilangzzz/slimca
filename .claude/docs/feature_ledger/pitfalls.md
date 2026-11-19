# 坑点 — feature_ledger

按跨模块影响排序。前四条都来自真实事故或口径刻意不一致。

## 1. 报表序列含 draft、账单流不含——对账数字对不上先查这条（跨模块口径）

`watchBucketSeries`/`watchCategoryStacks` 的兜底聚合 SQL **没有** `e.status IN ('confirmed','edited')` 条件——与 core_db day_summary 投影 `_kDayAggregateSql` 同口径，**draft 行计入**（保证投影直读与兜底可互换）。而 `watchMonthBillGroups`/`watchMonthCategorySums` 排除 draft。同一笔 AI 未确认记录：报表页有数、账单页没有，不是 bug，是口径设计。新加统计视图时必须选边并注明。

## 2. customSelect 的 readsFrom 必须显式声明（watch 永不更新类事故）

drift 的 `customSelect().watch()` 不自动推断 readsFrom——UNION 子查询尤其如此。缺省空集 = 任何表变更都不触发重跑，流**永不更新**且不报错。本模块三处 customSelect（桶序列/分类堆叠/账本+默认徽标）全部显式声明 `{entryLines, entries, daySummaries?, categories?/settings}`。新加 customSelect watch 忘写 readsFrom 是最隐蔽的坑。

## 3. drift QueryRow 类型化读取 + StreamBuilder 静默吞错（fd9d619 真实事故）

`QueryRow.readNullable<Object>` 抛「Could not find a matching SQL type」——无类型读取不被支持，列恒 TEXT 就按 `readNullable<String>` 读（settings.value 存 JSON 字符串值）。叠加 `StreamBuilder` **无 errorBuilder** 时流错误被静默吞掉，表现为「列表恒空」而非崩溃——账本管理页曾因此白屏式空列表。新 watch 流建议 builder 里检查 `snapshot.hasError`。

## 4. per-账本过滤时投影直读分支整体不拼，变量列表同步（fd9d619 修过 Expected 5 got 3）

day_summary 无 per-账本拆列：`watchBucketSeries(ledgerId: 非 null)` 时 UNION 的 day_summaries 分支**整体不拼进 SQL**，对应两个占位符变量也不传。改这段 SQL 时分支条件与 variables 必须同进退，否则运行期「Expected N got M」。

## 5. budget_snapshot 三形态兼容 + kcal 口径判定依赖外部账本集合

`parseBudgetSnapshot` 需要调用方传 `kcalLedgerIds`（快照项只带 ledger_id 不带 kind，软删账本不参与判定）——脱离 `watchDayBriefing` 单独复用解析器时容易漏传导致 isKcal 全 false。月度预算不混入简报「每日目标」行（UI 层按 periodType 过滤）；旧平铺形态的 used/remaining 是按当日投影值合成的近似值（升级期兼容，投影重算后消失）。

## 6. 日期口径两套失败策略：月前缀硬失败、展示标签软防御

`LedgerCalendar.monthRange` 对非法 `yyyy-MM` 抛 ArgumentError（字典序失去时间语义必须硬失败）；但 `dayGroupTitle/dayLabel/dayAxisLabel/monthAxisLabel` 对脏数据**原样返回不抛异常**（防止单行脏数据炸整页）。新加日期处理函数先想清楚属于哪类：参与查询区间判定的硬失败，纯展示的软防御。

## 7. 分类筛选是行级过滤且合计重算（「全部」态语义不同）

`watchMonthBillGroups(categoryId:)` 只保留命中行的账并重算日/月合计；未分类行（category_id IS NULL）只在「全部」态出现——按分类筛选时永远看不到未分类账单。做「未分类」筛选入口需要显式 `IS NULL` 条件，现有参数表达不了。

## 8. budgets/ledgers 写路径禁止直写（事务纪律在 DAO）

W5-6 版直写 budgets 漏 outbox 入队（数据不出网），W15 收口 BudgetsDao：业务行与 outbox 行同事务入队 + budget_snapshot v2 全投影行重算联动。同理 kcal 账本不可删不可多开、同 (ledger,category,period) 单现行预算折叠都是 DAO 契约。在本包写这些表 = 绕过同步与投影，必然造成端云不一致。

## 9. 金额/热量全程无 double；解析层是唯一入口

DB 与模型全是 INTEGER（分/kcal）；`parseYuanToMinor` 是元文本→分的唯一入口（最多两位小数），`parseKcal` 上限 99999。绕过解析层自己算（如 `double * 100`）会引入浮点误差——目标对话框、未来新表单一律走 LedgerFormat。

## 10. 逻辑引用不建外键：删除分类/账本后的 join 行为

categories/ledgers 对账单是逻辑引用：删分类后历史账单行原样保留，join 读最新名的查询里已删分类落「未分类」（LEFT JOIN 条件带 `deleted_at IS NULL`）；但 `watchDailyBudgets` 的分类名回填对已删分类显示「已删分类」——两处兜底文案不同是各自的 UI 语境，别「统一」掉。同步侧 pull 需保证父表行先于子表行落库（core_db 契约）。

## 11. 简报恒全量口径（多账本）

`watchDayBriefing` 无账本参数——day_summary 投影无 per-账本拆列，日简报永远是全量数字。账本筛选条切到某 money 账本时简报卡数字不变，是预期行为；per-账本收支看账单流日合计或报表页过滤。
