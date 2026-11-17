/// 账单流/分类汇总/日简报的响应式读取仓库（§3.4 账单页 + §5.6⑬
/// day_summary 投影直读；§3.2 首帧直读本表、零业务查询）。
///
/// 读取纪律（§5.1/§5.2②）：
/// - 只读活跃行：entries.status ∈ {confirmed, edited}（§5.2①，draft 是
///   AI 可覆盖态、不进账单流）、lines.status = active（superseded/void
///   是被修正的历史行）、deleted_at IS NULL（墓碑行不出现在任何列表）；
/// - join 读最新分类名：分类改名后账单流跟随最新名（逻辑引用不建外键，
///   §5.4⑤/§6.2）；kcal 行可挂餐饮子类，同为 join 条件；
/// - 月口径：`date >= 月初 AND date < 次月初`（§5.1 半开区间，TEXT
///   固定宽度字典序即时间序）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart' as drift;

import 'ledger_calendar.dart';
import 'ledger_models.dart';

/// 账本读取仓库接口（§10.4 分层纪律：页面依赖抽象，Drift 实现可替换）。
abstract interface class LedgerRepository {
  /// 按日分组的月账单流（§3.4；日期降序、组内按录入时序）。
  ///
  /// [categoryId] 非空时按"行分类"过滤：只保留命中行的账，且日合计/
  /// 月合计在过滤后的行上重算——筛选态的数字自洽（§3.4 分类筛选）。
  ///
  /// [ledgerId] 非空时按"行账本"过滤（§11.2 W15 多账本 P1、§5.4④）：
  /// money 账本 id 只见该账本流水，kcal 账本 id 只见热量/运动行——
  /// 过滤互斥由行级 ledger_id 保证（§5.2② 行必挂账本）。
  Stream<List<LedgerDayGroup>> watchMonthBillGroups(
    String month, {
    String? categoryId,
    String? ledgerId,
  });

  /// 月度分类汇总（§3.4 统计雏形：per-category money 行求和；支出降序）。
  /// [ledgerId] 非空时仅汇总该账本的 money 行（W15 多账本，§5.4④）。
  Stream<List<LedgerCategorySum>> watchMonthCategorySums(
    String month, {
    String? ledgerId,
  });

  /// 某日的日简报（§3.4：今日收支/热量摘要；数据走 day_summary 投影）。
  /// 当日投影行尚未构建（如今日还没有记录）时发 null——由 UI 展示零值
  /// 与引导，而不是构造假数据（§5.6⑬ 本地件只读）。
  ///
  /// W15 注（§11.2 多账本）：日简报恒**全量口径**——day_summary 投影无
  /// per-账本拆列（§5.6⑬），per-账本视角请用账单流/报表页的 ledgerId 过滤。
  Stream<LedgerDayBriefing?> watchDayBriefing(String date);

  /// 全部分类选项（筛选条/管理页共用；kind → sort 排序，§5.4⑤）。
  Stream<List<LedgerCategoryOption>> watchCategoryOptions();
}

/// Drift 实现（复用 core_db AppDatabase 的真值表；查询风格与
/// feature_dashboard / core_db 既有仓库一致：join + watch 直驱）。
class DriftLedgerRepository implements LedgerRepository {
  DriftLedgerRepository(this._db);

  final cdb.AppDatabase _db;

  /// entries.status 的活跃口径（§5.2①：draft 为 AI 可覆盖态；确认后
  /// 进入 confirmed；含修正为 edited）。
  static const List<String> _activeEntryStatuses = <String>[
    'confirmed',
    'edited',
  ];

  @override
  Stream<List<LedgerDayGroup>> watchMonthBillGroups(
    String month, {
    String? categoryId,
    String? ledgerId,
  }) {
    final ({String start, String end}) range = LedgerCalendar.monthRange(month);
    // entry_lines → entries（主干，取 date/title/kind）→ categories（左连，
    // 取最新分类名/token；未分类行为 null，§5.2②）。
    final query = _db.select(_db.entryLines).join(<drift.Join>[
      // entries 列要被读取（date/title/kind），故不关 useColumns（与
      // feature_dashboard join 读双表同款）。
      drift.innerJoin(
        _db.entries,
        _db.entries.id.equalsExp(_db.entryLines.entryId),
      ),
      drift.leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.entryLines.categoryId),
      ),
    ]);
    var predicate = _db.entries.date.isBiggerOrEqualValue(range.start) &
        _db.entries.date.isSmallerThanValue(range.end) &
        _db.entries.deletedAt.isNull() &
        _db.entries.status.isIn(_activeEntryStatuses) &
        _db.entryLines.status.equals(dom.LineStatus.active.wire) &
        _db.entryLines.deletedAt.isNull();
    // 多账本过滤（§11.2 W15、§5.4④）：行级 ledger_id 精确匹配——账本间
    // 互斥（一行一账本，§5.2②），过滤集合两两不相交。
    if (ledgerId != null) {
      predicate = predicate & _db.entryLines.ledgerId.equals(ledgerId);
    }
    query.where(predicate);
    query.orderBy(<drift.OrderingTerm>[
      drift.OrderingTerm.desc(_db.entries.date),
      drift.OrderingTerm.asc(_db.entries.createdAt),
      drift.OrderingTerm.asc(_db.entryLines.hlc),
    ]);
    return query.watch().map(
          (List<drift.TypedResult> rows) => _groupRows(rows, categoryId),
        );
  }

  /// 行 → 按日分组结构。先按 entry 归并行（facet 拆行 §5.2②：一次录入
  /// 的多行同属一条账），再按日期聚组并降序——DB 的 ORDER BY 是性能
  /// 优化，分组契约在这里显式成立，不依赖游标顺序。
  List<LedgerDayGroup> _groupRows(
    List<drift.TypedResult> rows,
    String? categoryId,
  ) {
    final Map<String, cdb.Entry> entryRowsById = <String, cdb.Entry>{};
    final Map<String, List<LedgerBillLine>> linesByEntry =
        <String, List<LedgerBillLine>>{};
    final List<String> entryOrder = <String>[];
    for (final drift.TypedResult row in rows) {
      final cdb.Entry entryRow = row.readTable(_db.entries);
      final cdb.EntryLine lineRow = row.readTable(_db.entryLines);
      final cdb.Category? categoryRow = row.readTableOrNull(_db.categories);
      // 分类筛选按"行分类"过滤（§3.4）；未分类行只在「全部」态出现。
      if (categoryId != null && lineRow.categoryId != categoryId) {
        continue;
      }
      final List<LedgerBillLine> lines =
          linesByEntry.putIfAbsent(entryRow.id, () => <LedgerBillLine>[]);
      if (lines.isEmpty) {
        entryRowsById[entryRow.id] = entryRow;
        entryOrder.add(entryRow.id);
      }
      lines.add(LedgerBillLine(
        lineId: lineRow.id,
        entryId: entryRow.id,
        type: dom.LineType.fromWire(lineRow.type),
        amount: lineRow.amount,
        direction: dom.LineDirection.fromWire(lineRow.direction),
        categoryId: lineRow.categoryId,
        categoryName: categoryRow?.name,
        colorToken: categoryRow?.colorToken,
      ));
    }
    final Map<String, List<LedgerBillEntry>> byDay =
        <String, List<LedgerBillEntry>>{};
    for (final String entryId in entryOrder) {
      final cdb.Entry entryRow = entryRowsById[entryId]!;
      byDay
          .putIfAbsent(entryRow.date, () => <LedgerBillEntry>[])
          .add(LedgerBillEntry(
            entryId: entryRow.id,
            date: entryRow.date,
            kind: dom.EntryKind.fromWire(entryRow.kind),
            title: entryRow.title,
            status: dom.EntryStatus.fromWire(entryRow.status),
            lines: linesByEntry[entryId]!,
          ));
    }
    // 固定宽度 TEXT 直接字符串比较即时间序（§5.1），倒序=最新在前。
    final List<String> dates = byDay.keys.toList()
      ..sort((String a, String b) => b.compareTo(a));
    return <LedgerDayGroup>[
      for (final String date in dates)
        LedgerDayGroup(date: date, entries: byDay[date]!),
    ];
  }

  @override
  Stream<List<LedgerCategorySum>> watchMonthCategorySums(
    String month, {
    String? ledgerId,
  }) {
    final ({String start, String end}) range = LedgerCalendar.monthRange(month);
    // 月度 per-category money 行求和（§3.4 统计雏形）：customSelect 聚合
    // （与 core_db 投影同款口径）。未分类行 category_id IS NULL 由
    // LEFT JOIN + GROUP BY 自然落出；LEFT JOIN 条件带上 deleted_at IS
    // NULL——已删分类的历史账单归入"未分类"而非丢名字（§5.4⑤ 逻辑引用）。
    // W15 多账本：ledger_id 可选过滤（§5.4④，过滤集合互斥）。
    final String ledgerFilter =
        ledgerId == null ? '' : '  AND l.ledger_id = ?';
    final String sql = <String>[
      'SELECT l.category_id AS category_id,',
      '       c.name AS category_name,',
      '       c.color_token AS color_token,',
      "       COALESCE(SUM(CASE WHEN l.direction = 'out' THEN l.amount ELSE 0 END), 0) AS spend_minor,",
      "       COALESCE(SUM(CASE WHEN l.direction = 'in' THEN l.amount ELSE 0 END), 0) AS income_minor",
      'FROM entry_lines l',
      'INNER JOIN entries e ON e.id = l.entry_id',
      'LEFT JOIN categories c ON c.id = l.category_id AND c.deleted_at IS NULL',
      "WHERE l.type = 'money'",
      "  AND l.status = 'active'",
      '  AND l.deleted_at IS NULL',
      '  AND e.date >= ?',
      '  AND e.date < ?',
      '  AND e.deleted_at IS NULL',
      "  AND e.status IN ('confirmed', 'edited')",
      ledgerFilter,
      'GROUP BY l.category_id',
      'ORDER BY spend_minor DESC',
    ].join(' ');
    return _db
        .customSelect(
      sql,
      variables: <drift.Variable<String>>[
        drift.Variable.withString(range.start),
        drift.Variable.withString(range.end),
        if (ledgerId != null) drift.Variable.withString(ledgerId),
      ],
    )
        .watch()
        .map((List<drift.QueryRow> rows) => <LedgerCategorySum>[
              for (final drift.QueryRow row in rows)
                LedgerCategorySum(
                  categoryId: row.readNullable<String>('category_id'),
                  categoryName: row.readNullable<String>('category_name'),
                  colorToken: row.readNullable<String>('color_token'),
                  spendMinor: row.read<int>('spend_minor'),
                  incomeMinor: row.read<int>('income_minor'),
                ),
            ]);
  }

  @override
  Stream<LedgerDayBriefing?> watchDayBriefing(String date) {
    dom.validateCalendarDay(date, name: 'date');
    return (_db.select(_db.daySummaries)
          ..where((t) => t.date.equals(date)))
        .watchSingleOrNull()
        .asyncMap((cdb.DaySummary? row) async {
      if (row == null) {
        return null;
      }
      // 快照项只带 ledger_id 不带 kind，需按账本表解析 kcal 口径
      // （§5.4④ kcal 账本）；账本行近乎恒定，asyncMap 内一次读取即可。
      final Set<String> kcalLedgerIds = await _kcalLedgerIds();
      return LedgerDayBriefing(
        date: row.date,
        kcalIn: row.kcalIn,
        kcalOut: row.kcalOut,
        netKcal: row.netKcal,
        spendMinor: row.spendMinor,
        incomeMinor: row.incomeMinor,
        budgets: parseBudgetSnapshot(
          row.budgetSnapshot,
          daySpendMinor: row.spendMinor,
          dayNetKcal: row.netKcal,
          kcalLedgerIds: kcalLedgerIds,
        ),
      );
    });
  }

  /// kcal 账本 id 集合（§5.4④；软删账本不参与口径判定）。
  Future<Set<String>> _kcalLedgerIds() async {
    final List<cdb.Ledger> rows = await (_db.select(_db.ledgers)
          ..where(
            (t) => t.kind.equals(kLedgerKindKcal) & t.deletedAt.isNull(),
          ))
        .get();
    return rows.map((cdb.Ledger row) => row.id).toSet();
  }

  @override
  Stream<List<LedgerCategoryOption>> watchCategoryOptions() {
    return (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            // 非 join 查询的 orderBy 以闭包形态声明（与 core_db
            // CategoryDao.getAll 同款）；kind → sort → 创建序。
            (t) => drift.OrderingTerm.asc(t.kind),
            (t) => drift.OrderingTerm.asc(t.sort),
            (t) => drift.OrderingTerm.asc(t.createdAt),
          ]))
        .watch()
        .map((List<cdb.Category> rows) => <LedgerCategoryOption>[
              for (final cdb.Category row in rows)
                LedgerCategoryOption(
                  id: row.id,
                  name: row.name,
                  icon: row.icon,
                  kind: row.kind,
                  colorToken: row.colorToken,
                  isPreset: row.isPreset,
                ),
            ]);
  }
}
