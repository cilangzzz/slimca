# API — 统计报表域（ReportRepository + report_models）

统计报表数据层与页面（§3.4 P1、§11.2 W15）。数据层纪律：day_summary 直读为主源（首帧零业务查询）、entry_lines 聚合兜底（投影未建/自愈途中的日期）；两者并成一条 UNION ALL 查询 watch，避免双流 combine 竞态。

**口径警告**：兜底聚合与 core_db 投影 `_kDayAggregateSql` 同一过滤口径（l.status='active'、行/事件未删，**draft 亦计入**）——与账单流仓库的活跃口径（排除 draft）刻意不同，保证直读与兜底数字可互换。对账时注意。

## ReportPeriod / ReportRange / reportRangeFor

```dart
enum ReportPeriod { week, month, year }  // 周一为一周起点；年档按月分桶

class ReportRange {
  final ReportPeriod period;
  final String start;         // 含，yyyy-MM-dd
  final String endExclusive;  // 不含
  final bool byMonth;         // 年档=true（按月分桶），周/月档按日分桶
}

ReportRange reportRangeFor(ReportPeriod period, DateTime anchor);
```

区间解析经 `LedgerCalendar.weekRange/monthRange/yearRange`（见 [api-bill-view.md](api-bill-view.md) 引用的同一日历助手）。

## reportBucketKeys

```dart
List<String> reportBucketKeys(ReportRange range);
```

枚举区间内全部桶键（日桶 `yyyy-MM-dd`、月桶 `yyyy-MM`，升序）。**零填充的桶轴**：图表 x 轴恒展示完整区间（无数据桶画零值），选中态与数据桶对齐——双轴联动按索引寻址的前提。

## watchBucketSeries

```dart
Stream<List<ReportBucketPoint>> watchBucketSeries({
  required ReportRange range,
  String? ledgerId,
});
```

桶序列（周/月档按日、年档按月）：每桶 kcal_in/kcal_out/spend_minor/income_minor。

- 实现：单条 `UNION ALL` customSelect watch——entry_lines 聚合分支（兜底）+ day_summaries 直读分支（`from_summary=1` 标记）；Dart 侧按桶「有投影行用投影、无投影行用兜底」合并，区间内零填充。
- **per-账本过滤（ledgerId 非空）时 day_summaries 分支整体不拼**（投影无 per-账本拆列，兜底即主源）；SQL 占位符与变量数必须同步增减——fd9d619 曾因分支不拼但变量照传报「Expected 5 got 3」。
- `readsFrom` 必须显式声明 `{entryLines, entries, daySummaries?}`（customSelect 不自动推断，缺省空集 watch 永不更新）。

## watchCategoryStacks

```dart
Stream<List<ReportCategoryStack>> watchCategoryStacks({
  required ReportRange range,
  String? ledgerId,
});
```

桶 × 分类支出切片（堆叠条形数据源）：money-out 行，桶内金额降序。未分类行 categoryId=null（LEFT JOIN 保底）；已删分类的名字以删除前行名为准（join 条件带 `deleted_at IS NULL`）。年档按月前缀 `substr(e.date,1,7)` 分桶。`readsFrom: {entryLines, entries, categories}`。

## ReportBucketPoint / ReportCategoryStack

```dart
class ReportBucketPoint {
  final String bucketKey;  // 日桶 yyyy-MM-dd / 月桶 yyyy-MM
  final int spendMinor, incomeMinor, kcalIn, kcalOut;
  int get netKcal => kcalIn - kcalOut;
}

class ReportCategoryStack {
  final String bucketKey;
  final String? categoryId;      // null=未分类
  final String? categoryName, colorToken;
  final int spendMinor;
}
```

## 页面：ReportPage

```dart
ReportPage({
  required ReportRepository repository,
  ReportPeriod initialPeriod = ReportPeriod.month, // 缺省月档
  DateTime? initialAnchor,                         // 缺省今天（测试注入固定日）
  void Function(String bucketKey)? onEditEntry,    // 「看当日」下钻，壳接线
});
```

四面板：周期切换条（周/月/年 chips + ‹ 标题 › 步进）→ 支出构成堆叠条形 → 热量趋势折线（摄入/消耗/净三线，零基线居中）→ 钱-热量双轴联动卡（上轴花费柱 moneyOut、下轴净热量柱——净>0 用 kcalIn 色「吃多了」、净<0 用 kcalOut 色「练回来了」）+ 选中桶详情条。

联动机制：三面板共享 `_selectedBucket` 状态；点任一图元 → `_selectBucket`（同桶再点=反选）→ 三面板同步高亮该桶 + 详情条显示该桶钱/热量数字。周期/档位切换时选中桶清空（旧桶可能不在新区间）。

实现约束（改图表前必读）：

- 颜色全部经 `SlimcaTheme` token 解析后**传入画笔**，画笔无主题依赖（§8.2）。
- 图表命中换算与画笔共用 `_ChartGeometry` 常量（padding/桶宽公式）——点桶索引与渲染对齐同源。
- x 轴稀疏标注：≤12 桶全标，更多时标首、尾与四分位。
- 堆叠分类取全区间 top5 + 「其他」，分类层序全区间一致（堆叠不随桶跳变）。
- 柱宽上限手写比较（rawBar<2.0 / >28.0），不用 `num.clamp`（返回 num，避免隐式下转型）。

测试锚点：`report_period_week/month/year`、`report_stacked_chart`、`report_kcal_chart`、`report_dual_axis`、`report_detail_strip`、`report_detail_drill`。
