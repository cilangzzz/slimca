/// 统计报表读取仓库（§3.4「统计报表 P1」、§11.2 W15「钱-热量双轴联动视图」）。
///
/// 数据层纪律（任务口径「day_summary 直读 + entry_lines 聚合兜底」）：
/// - **day_summary 直读**（§5.6⑬/§3.2 首帧零业务查询）：序列主源——投影行
///   已含每桶的 kcal/spend 聚合，直读本表零明细扫描；
/// - **entry_lines 聚合兜底**：区间内尚无投影行的日期（投影未建/自愈途中）
///   从明细行按同口径聚合补齐——聚合 SQL 与 core_db 投影 `_kDayAggregateSql`
///   同一过滤口径（l.status='active'、行/事件未删；draft 亦计入，§5.6⑬），
///   直读与兜底数字可互换；
/// - **单流响应式**（§10.1 Drift reactive stream）：直读与兜底并成一条
///   `UNION ALL` 查询 watch——day_summaries/entry_lines/entries 任一变更
///   重跑，Dart 侧按桶「有投影行用投影、无投影行用兜底」合并，避免双流
///   combine 的竞态；
/// - **per-账本过滤**（§11.2 W15 多账本）：day_summary 无 per-账本拆列，
///   ledgerId 非空时整条序列走 entry_lines 聚合口径（兜底即主源）；
/// - **分类堆叠**：day_summary 无 per-分类列，堆叠条形恒走 entry_lines
///   聚合（GROUP BY 桶×分类）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/drift.dart' as drift;

import 'report_models.dart';

/// 报表仓库接口（§10.4 分层纪律：页面依赖抽象，Drift 实现可替换）。
abstract interface class ReportRepository {
  /// 桶序列（周/月档按日、年档按月；§3.4 趋势折线 + 双轴联动数据源）。
  ///
  /// 区间内每个桶必有返回项（无数据桶为零值）——图表零填充与选中态索引
  /// 对齐（reportBucketKeys 枚举同构）。
  Stream<List<ReportBucketPoint>> watchBucketSeries({
    required ReportRange range,
    String? ledgerId,
  });

  /// 桶 × 分类支出切片（堆叠条形数据源；money-out 行，按桶内金额降序）。
  ///
  /// 未分类行 categoryId=null（LEFT JOIN 保底，§5.2②）；已删分类的名字
  /// 以删除前行名为准（join 条件带 deleted_at IS NULL，§5.4⑤ 逻辑引用）。
  Stream<List<ReportCategoryStack>> watchCategoryStacks({
    required ReportRange range,
    String? ledgerId,
  });
}

/// Drift 实现（复用 core_db 真值表；查询风格与账单仓库同款：customSelect
/// watch 直驱，§5.6⑬）。
class DriftReportRepository implements ReportRepository {
  DriftReportRepository(this._db);

  final cdb.AppDatabase _db;

  @override
  Stream<List<ReportBucketPoint>> watchBucketSeries({
    required ReportRange range,
    String? ledgerId,
  }) {
    final String bucketExpr =
        range.byMonth ? 'substr(e.date, 1, 7)' : 'e.date';
    final String summaryBucketExpr =
        range.byMonth ? 'substr(d.date, 1, 7)' : 'd.date';
    // 兜底聚合（entry_lines 口径与 core_db 投影一致，见类文档头）。
    final String ledgerFilter =
        ledgerId == null ? '' : ' AND l.ledger_id = ?';
    // per-账本过滤时投影无拆列、整条走兜底（day_summaries 分支整体不拼，
    // 见类文档头；全量口径才有 UNION 投影直读分支）。
    final String summaryBranch = ledgerId == null
        ? <String>[
            'UNION ALL',
            'SELECT $summaryBucketExpr AS bucket,',
            '  COALESCE(SUM(d.kcal_in), 0) AS kcal_in,',
            '  COALESCE(SUM(d.kcal_out), 0) AS kcal_out,',
            '  COALESCE(SUM(d.spend_minor), 0) AS spend_minor,',
            '  COALESCE(SUM(d.income_minor), 0) AS income_minor,',
            '  1 AS from_summary',
            'FROM day_summaries d',
            'WHERE d.date >= ? AND d.date < ?',
            'GROUP BY bucket',
          ].join(' ')
        : '';
    final String sql = <String>[
      'SELECT $bucketExpr AS bucket,',
      "  COALESCE(SUM(CASE WHEN l.type = 'calorie' AND l.direction = 'in' THEN l.amount ELSE 0 END), 0) AS kcal_in,",
      "  COALESCE(SUM(CASE WHEN l.type = 'burn' AND l.direction = 'out' THEN l.amount ELSE 0 END), 0) AS kcal_out,",
      "  COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'out' THEN l.amount ELSE 0 END), 0) AS spend_minor,",
      "  COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'in' THEN l.amount ELSE 0 END), 0) AS income_minor,",
      '  0 AS from_summary',
      'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id',
      'WHERE e.date >= ? AND e.date < ?',
      "  AND l.status = 'active' AND l.deleted_at IS NULL",
      '  AND e.deleted_at IS NULL$ledgerFilter',
      'GROUP BY bucket',
      summaryBranch,
      'ORDER BY bucket ASC',
    ].join(' ');
    final List<drift.Variable<String>> variables = <drift.Variable<String>>[
      drift.Variable.withString(range.start),
      drift.Variable.withString(range.endExclusive),
      if (ledgerId != null) drift.Variable.withString(ledgerId),
      // day_summary 直读分支（§5.6⑬）：per-账本过滤时投影无拆列、整条走兜底。
      if (ledgerId == null) ...<drift.Variable<String>>[
        drift.Variable.withString(range.start),
        drift.Variable.withString(range.endExclusive),
      ],
    ];
    return _db
        .customSelect(
          sql,
          variables: variables,
          // 显式声明涉及表（UNION 子查询的表变更触发重跑；customSelect 不
          // 自动推断 readsFrom，缺省空集会使 watch 永不更新，drift 契约）。
          readsFrom: <drift.ResultSetImplementation<drift.Table, drift.DataClass>>{
            _db.entryLines,
            _db.entries,
            if (ledgerId == null) _db.daySummaries,
          },
        )
        .watch()
        .map((List<drift.QueryRow> rows) => _mergeSeries(rows, range));
  }

  /// UNION 行 → 桶序列：按桶「有投影行用投影、无投影行用兜底」，区间内
  /// 桶零填充（图表 x 轴完整、选中索引与桶一一对应）。
  List<ReportBucketPoint> _mergeSeries(
    List<drift.QueryRow> rows,
    ReportRange range,
  ) {
    final Map<String, ReportBucketPoint> fromSummary =
        <String, ReportBucketPoint>{};
    final Map<String, ReportBucketPoint> fromLines =
        <String, ReportBucketPoint>{};
    for (final drift.QueryRow row in rows) {
      final String bucket = row.read<String>('bucket');
      final bool summary = (row.read<int>('from_summary')) == 1;
      final point = ReportBucketPoint(
        bucketKey: bucket,
        kcalIn: row.read<int>('kcal_in'),
        kcalOut: row.read<int>('kcal_out'),
        spendMinor: row.read<int>('spend_minor'),
        incomeMinor: row.read<int>('income_minor'),
      );
      if (summary) {
        fromSummary[bucket] = point;
      } else {
        fromLines[bucket] = point;
      }
    }
    return <ReportBucketPoint>[
      for (final String key in reportBucketKeys(range))
        fromSummary[key] ??
            fromLines[key] ??
            ReportBucketPoint(
              bucketKey: key,
              kcalIn: 0,
              kcalOut: 0,
              spendMinor: 0,
              incomeMinor: 0,
            ),
    ];
  }

  @override
  Stream<List<ReportCategoryStack>> watchCategoryStacks({
    required ReportRange range,
    String? ledgerId,
  }) {
    // 桶×分类 money-out 求和（§3.4 堆叠条形；口径与序列一致——active 行、
    // 行/事件未删，draft 计入，§5.6⑬）。年档按月前缀分桶（substr 1..7）。
    final String bucketExpr =
        range.byMonth ? 'substr(e.date, 1, 7)' : 'e.date';
    final String ledgerFilter =
        ledgerId == null ? '' : '  AND l.ledger_id = ?';
    final String sql = <String>[
      'SELECT $bucketExpr AS bucket,',
      '  l.category_id AS category_id,',
      '  c.name AS category_name,',
      '  c.color_token AS color_token,',
      '  COALESCE(SUM(l.amount), 0) AS spend_minor',
      'FROM entry_lines l',
      'INNER JOIN entries e ON e.id = l.entry_id',
      'LEFT JOIN categories c ON c.id = l.category_id AND c.deleted_at IS NULL',
      "WHERE l.type = 'money' AND l.direction = 'out'",
      "  AND l.status = 'active' AND l.deleted_at IS NULL",
      '  AND e.deleted_at IS NULL',
      '  AND e.date >= ? AND e.date < ?',
      ledgerFilter,
      'GROUP BY bucket, l.category_id',
      'ORDER BY bucket ASC, spend_minor DESC',
    ].join(' ');
    return _db
        .customSelect(
          sql,
          variables: <drift.Variable<String>>[
            drift.Variable.withString(range.start),
            drift.Variable.withString(range.endExclusive),
            if (ledgerId != null) drift.Variable.withString(ledgerId),
          ],
          readsFrom: <drift.ResultSetImplementation<drift.Table, drift.DataClass>>{
            _db.entryLines,
            _db.entries,
            _db.categories,
          },
        )
        .watch()
        .map((List<drift.QueryRow> rows) => <ReportCategoryStack>[
              for (final drift.QueryRow row in rows)
                ReportCategoryStack(
                  bucketKey: row.read<String>('bucket'),
                  categoryId: row.readNullable<String>('category_id'),
                  categoryName: row.readNullable<String>('category_name'),
                  colorToken: row.readNullable<String>('color_token'),
                  spendMinor: row.read<int>('spend_minor'),
                ),
            ]);
  }
}
