# API — 账单流查询域（LedgerRepository）

读取仓库：账单流（按日分组）、月度分类汇总、日简报、分类选项。全部响应式 watch 流，页面依赖抽象接口 `LedgerRepository`，Drift 实现 `DriftLedgerRepository(_db)` 构造注入。

读取纪律（实现内强制，调用方无需重复处理）：

- 只读活跃行：entries.status ∈ {confirmed, edited}（draft 是 AI 可覆盖态不进账单流）、lines.status = active、deleted_at IS NULL（墓碑不出现在任何列表）；
- join categories 取**最新**分类名/token（逻辑引用不建外键，分类改名后账单流跟随最新名）；
- 月口径 `date >= 月初 AND date < 次月初` 半开区间。

## watchMonthBillGroups

```dart
Stream<List<LedgerDayGroup>> watchMonthBillGroups(
  String month, {
  String? categoryId,
  String? ledgerId,
});
```

- `month`：`yyyy-MM` 月前缀；非法形态抛 ArgumentError（固定宽度被破坏会使 TEXT 字典序失去时间语义，必须硬失败）。
- `categoryId` 非空：按**行分类**过滤——只保留命中行的账，且日合计/月合计在过滤后的行上重算（筛选态数字自洽）；未分类行只在「全部」态出现。
- `ledgerId` 非空：按**行账本**过滤（W15 多账本）——money 账本 id 只见该账本流水，kcal 账本 id 只见热量/运动行；过滤集合互斥由行级 ledger_id 保证（一行一账本）。
- 返回：日期降序、组内按录入时序（ORDER BY 是性能优化，分组契约在 `_groupRows` 显式成立，不依赖游标顺序）。

## watchMonthCategorySums

```dart
Stream<List<LedgerCategorySum>> watchMonthCategorySums(
  String month, {
  String? ledgerId,
});
```

月度 per-category money 行求和（支出降序），`customSelect` 聚合 watch。未分类行由 LEFT JOIN + GROUP BY 自然落出（categoryId=null）；LEFT JOIN 条件带 `deleted_at IS NULL`——已删分类的历史账单归入「未分类」而非丢名字。

## watchDayBriefing

```dart
Stream<LedgerDayBriefing?> watchDayBriefing(String date);
```

- `date`：`yyyy-MM-dd` 自然日（内部经 core_domain `validateCalendarDay` 校验）。
- day_summary 投影行直读（`watchSingleOrNull` + asyncMap）——当日投影行尚未构建时发 `null`，由 UI 展示零值引导，不造假数据。
- `asyncMap` 内一次读取 kcal 账本 id 集合用于快照口径判定（快照项只带 ledger_id 不带 kind；软删账本不参与判定）。
- **恒全量口径**：day_summary 无 per-账本拆列，不接受账本参数；per-账本视角用账单流/报表的 ledgerId 过滤。
- 快照解析见 [data-model.md](data-model.md) 的 parseBudgetSnapshot 节。

## watchCategoryOptions

```dart
Stream<List<LedgerCategoryOption>> watchCategoryOptions();
```

全部分类（未删），kind → sort → 创建序排序。筛选条/管理页/简报卡分类名回填共用。

## 页面：LedgerPage

账本 Tab 页，结构自上而下：日简报卡 → 账本筛选条（W15，`manageRepository` 非空才显示）→ 月份切换条 → 分类筛选条 → 月度分类汇总卡 → 按日分组账单流。

```dart
LedgerPage({
  required LedgerRepository repository,
  LedgerAdminRepository? adminRepository,   // 分类管理入口
  LedgerManageRepository? manageRepository, // 账本筛选条 + 账本管理入口
  ReportRepository? reportRepository,       // 统计入口
  DateTime? initialMonth,                   // 缺省=今天所在月
  DateTime? briefingDate,                   // 简报日，缺省=今天（测试注入固定日）
  void Function(String entryId)? onEditEntry,       // 编辑回调→壳接 capture 修正链
  VoidCallback? onOpenCategoryManage,       // 覆写导航（宿主自定义转场）
  VoidCallback? onOpenLedgerManage,         // 覆写导航
  VoidCallback? onOpenReport,               // 覆写导航
  VoidCallback? onStartCapture,             // 空月「立即记录」→壳接录入抽屉
});
```

- 导航覆写回调优先于默认 push：`onOpenXxx` 非空走宿主转场（PageRouteBuilder 注入，§9.5），否则缺省 `MaterialPageRoute` push 对应页面。
- 某入口显示条件 = 对应覆写回调或仓库任一非空（`_canOpenCategories/_canOpenManage/_canOpenReport`）。
- 首帧直出：StreamBuilder 无数据时渲染空占位，不转圈（§3.2 无加载态阻塞）。
- 账单条目点按 → `onEditEntry(entryId)`；尾列文本优先级：支出 > 收入 > 消耗 kcal > 摄入 kcal。

## 组件：LedgerDayBriefingCard

日简报卡（当日 支出/收入/净热量 三指标 + 预算达成行）。`{required LedgerRepository repository, required DateTime date}`。内部两条 StreamBuilder：简报流 + 分类选项流（快照只带 category_id，分类名经 options 回填；已删分类显示「已删分类」）。只渲染 daily 周期预算（月度预算不混入每日目标行）；预算余=success 色、超支=danger 色。

## 测试锚点

`ledger_page_report` / `ledger_page_ledger_manage` / `ledger_filter_all` / `ledger_filter_<categoryId>` / `ledger_filter_ledger_all` / `ledger_filter_ledger_<ledgerId>` / `ledger_summary_card` / `ledger_day_<date>`（按日分节定位）。
