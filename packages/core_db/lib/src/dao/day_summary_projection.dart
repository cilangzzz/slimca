/// day_summary 投影 v1（§5.6⑬「当日聚合投影」）。
///
/// 派生量永不存储到同步表、永不同步（§5.1/§6.1 原则 3）；双端从明细行各自
/// 重建、永远自愈（§6.5 冲突矩阵末行）。重建规则（§5.6）：任何 entry_line /
/// corrections 变更 → 标记当日 dirty → 重算；仪表盘冷启动首帧直读本表、
/// 零业务查询（§3.2 快照直出）。
///
/// v1 聚合口径（以 §5.6 字段清单为准）：
/// - kcal_in / kcal_out：entry_lines(type=calorie,direction=in / type=burn,
///   direction=out) 按 entries.date 归日聚合，仅计入 status=active 且
///   「行未软删、所属事件未软删」的行——superseded/void/deleted 一律不计入；
/// - spend_minor / income_minor：type=money direction=out / in，同上过滤；
/// - net_kcal = kcal_in - kcal_out（§3.5 摄入-消耗）；
/// - todo_done / todo_total：todos.date 当日且未软删，done_at 非空计完成；
///   收集箱（date=NULL，§5.5⑩）不计入任何日投影；
/// - budget_snapshot：daily 预算（period_type='daily'，§5.4⑥）余量快照，
///   money 账本 used=当日支出、kcal 账本 used=kcal_in-kcal_out（§5.4 kcal
///   账本「预算=收入、吃=支出、运动=再入账」口径）；
/// - savings_progress：P1 存钱上线后启用，v1 恒 NULL（§5.6⑬）；
/// - tz_offset_min：当日最近写入事件行的时区；无事件时沿用旧投影行，否则 0。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';

/// 预算快照 JSON 形状（budget_snapshot 列，§5.6⑬）。
///
/// 上层按此形状直读快照渲染预算卡（§3.2 预算状态色）：
/// `{"daily":[{"ledger_id":"…","category_id":null,"amount":200000,
///   "used":1850,"remaining":198350}]}`——kcal 预算同形状（amount/used/
/// remaining 单位为 kcal）。无 daily 预算时为 `{"daily":[]}`。
class DaySummaryProjection {
  DaySummaryProjection(this._db);

  final AppDatabase _db;

  /// 重算指定日并 UPSERT 投影行（dirty=false、built_at=now，§5.6⑬）。
  ///
  /// 幂等可重入；不自带事务——在调用方事务内执行时与业务写同事务生效
  /// （§6.2 写路径「业务行 + 投影同事务」），独立调用时末步为单行原子 UPSERT。
  Future<DaySummary> recomputeDaySummary(String date) async {
    final lines = await _aggregateLines(date);
    final todos = await _aggregateTodos(date);
    final tz = await _resolveTz(date);
    final snapshot = await _budgetSnapshot(date);

    await _db.into(_db.daySummaries).insertOnConflictUpdate(
          DaySummariesCompanion.insert(
            date: date,
            tzOffsetMin: tz,
            kcalIn: lines.kcalIn,
            kcalOut: lines.kcalOut,
            netKcal: lines.kcalIn - lines.kcalOut,
            spendMinor: lines.spendMinor,
            incomeMinor: lines.incomeMinor,
            todoDone: todos.done,
            todoTotal: todos.total,
            budgetSnapshot: jsonEncode(snapshot),
            // P1 存钱上线后启用（§5.6⑬ savings_progress 行）。
            savingsProgress: const Value(null),
            builtAt: DateTime.now().millisecondsSinceEpoch,
            dirty: const Value(false),
          ),
        );
    return (_db.select(_db.daySummaries)
          ..where((t) => t.date.equals(date)))
        .getSingle();
  }

  /// 响应式读投影：仪表盘卡片墙直驱（§10.1 Drift reactive stream 行）。
  /// 无投影行时发 null（调用方按零值快照渲染）。
  Stream<DaySummary?> watchDaySummary(String date) =>
      (_db.select(_db.daySummaries)..where((t) => t.date.equals(date)))
          .watchSingleOrNull();

  /// 标记当日 dirty（§5.6 重建规则第一步）。
  ///
  /// 供绕过 core_db 仓库直写明细的写入方（W7 起的同步 pull 等）调用；
  /// 日期尚无投影行时为 no-op——首次重算会整行建立。
  Future<void> markDayDirty(String date) async {
    await (_db.update(_db.daySummaries)
          ..where((t) => t.date.equals(date)))
        .write(const DaySummariesCompanion(dirty: Value(true)));
  }

  /// 只重算 dirty=1 的日期（§5.6「标记当日 dirty → 后台重算」的后台半步，
  /// 亦是崩溃后的自愈入口）。同一事务内逐日重算。
  Future<void> recomputeDirtyDays() {
    return _db.transaction(() async {
      final rows = await _db
          .customSelect('SELECT date FROM day_summaries WHERE dirty = 1')
          .get();
      for (final row in rows) {
        await recomputeDaySummary(row.read<String>('date'));
      }
    });
  }

  /// 全量重建（§5.6「可随时全量重建（自愈）」）。
  ///
  /// 范围：有未删事件的日期 + 有未删带日待办的日期 + 已有投影行（可能只剩
  /// 墓碑/已全部作废的旧日期需要清零重写）。同一事务内逐日重算。
  Future<void> recomputeAll() {
    return _db.transaction(() async {
      final dates = <String>{};
      final entryRows = await _db
          .customSelect('SELECT DISTINCT date FROM entries WHERE deleted_at IS NULL')
          .get();
      for (final row in entryRows) {
        dates.add(row.read<String>('date'));
      }
      final todoRows = await _db
          .customSelect(
              'SELECT DISTINCT date FROM todos WHERE date IS NOT NULL AND deleted_at IS NULL')
          .get();
      for (final row in todoRows) {
        dates.add(row.read<String>('date'));
      }
      final summaryRows =
          await _db.customSelect('SELECT date FROM day_summaries').get();
      for (final row in summaryRows) {
        dates.add(row.read<String>('date'));
      }
      for (final date in dates) {
        await recomputeDaySummary(date);
      }
    });
  }

  // ── 聚合实现 ──────────────────────────────────────────────────────────

  Future<({int kcalIn, int kcalOut, int spendMinor, int incomeMinor})>
      _aggregateLines(String date) async {
    final row = await _db
        .customSelect(_kDayAggregateSql, variables: [Variable.withString(date)])
        .getSingle();
    return (
      kcalIn: row.read<int>('kcal_in'),
      kcalOut: row.read<int>('kcal_out'),
      spendMinor: row.read<int>('spend_minor'),
      incomeMinor: row.read<int>('income_minor'),
    );
  }

  /// §5.6⑬ 明细聚合 SQL：只数 active 行，行/事件墓碑均排除；按 entries.date
  /// 归日（§5.1「一切聚合按 date 分组，杜绝 UTC 错日」）。
  static const String _kDayAggregateSql = 'SELECT '
      "COALESCE(SUM(CASE WHEN l.type = 'calorie' AND l.direction = 'in' "
      'THEN l.amount ELSE 0 END), 0) AS kcal_in, '
      "COALESCE(SUM(CASE WHEN l.type = 'burn' AND l.direction = 'out' "
      'THEN l.amount ELSE 0 END), 0) AS kcal_out, '
      "COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'out' "
      'THEN l.amount ELSE 0 END), 0) AS spend_minor, '
      "COALESCE(SUM(CASE WHEN l.type = 'money' AND l.direction = 'in' "
      'THEN l.amount ELSE 0 END), 0) AS income_minor '
      'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
      "WHERE e.date = ? AND l.status = 'active' "
      'AND l.deleted_at IS NULL AND e.deleted_at IS NULL';

  Future<({int done, int total})> _aggregateTodos(String date) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS todo_total, '
          'COALESCE(SUM(CASE WHEN done_at IS NOT NULL THEN 1 ELSE 0 END), 0) '
          'AS todo_done FROM todos WHERE date = ? AND deleted_at IS NULL',
          variables: [Variable.withString(date)],
        )
        .getSingle();
    return (
      total: row.read<int>('todo_total'),
      done: row.read<int>('todo_done'),
    );
  }

  /// tz 解析（§5.1 日期约定）：当日最近写入事件行的 tz_offset_min；
  /// 无事件行时沿用旧投影行（清零日保留原时区语义），再否则 0。
  Future<int> _resolveTz(String date) async {
    final rows = await _db
        .customSelect(
          'SELECT tz_offset_min FROM entries WHERE date = ? '
          'AND deleted_at IS NULL ORDER BY updated_at DESC, hlc DESC LIMIT 1',
          variables: [Variable.withString(date)],
        )
        .get();
    if (rows.isNotEmpty) {
      return rows.first.read<int>('tz_offset_min');
    }
    final existing = await (_db.select(_db.daySummaries)
          ..where((t) => t.date.equals(date)))
        .getSingleOrNull();
    return existing?.tzOffsetMin ?? 0;
  }

  /// 预算余量快照（§5.4⑥ budgets + §5.6⑬ budget_snapshot）。
  ///
  /// v1 只展开 daily 预算：money 账本 used=当日该账本（或账本+分类）支出；
  /// kcal 账本 used=该账本当日 kcal_in-kcal_out（吃=支出、运动=再入账，
  /// §5.4 kcal 账本行）。月度预算（period_type='monthly'，P1）不进日快照。
  Future<Map<String, Object?>> _budgetSnapshot(String date) async {
    // 当日 money 支出按 (ledger_id, category_id) 分组。
    final spendRows = await _db
        .customSelect(
          'SELECT l.ledger_id AS ledger_id, l.category_id AS category_id, '
          'COALESCE(SUM(l.amount), 0) AS total '
          'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
          "WHERE e.date = ? AND l.type = 'money' AND l.direction = 'out' "
          "AND l.status = 'active' AND l.deleted_at IS NULL "
          'AND e.deleted_at IS NULL GROUP BY l.ledger_id, l.category_id',
          variables: [Variable.withString(date)],
        )
        .get();
    // 当日 kcal 按 ledger 分组（calorie=摄入、burn=再入账）。
    final kcalRows = await _db
        .customSelect(
          'SELECT l.ledger_id AS ledger_id, '
          "COALESCE(SUM(CASE WHEN l.type = 'calorie' AND l.direction = 'in' "
          'THEN l.amount ELSE 0 END), 0) AS kcal_in, '
          "COALESCE(SUM(CASE WHEN l.type = 'burn' AND l.direction = 'out' "
          'THEN l.amount ELSE 0 END), 0) AS kcal_out '
          'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
          "WHERE e.date = ? AND l.type IN ('calorie', 'burn') "
          "AND l.status = 'active' AND l.deleted_at IS NULL "
          'AND e.deleted_at IS NULL GROUP BY l.ledger_id',
          variables: [Variable.withString(date)],
        )
        .get();

    final spendByLedgerCat = <String, int>{};
    final spendByLedger = <String, int>{};
    for (final row in spendRows) {
      // money 行 ledger_id 必填（§5.2②）；NULL 组防御性跳过（无归属不进预算）。
      final ledgerId = row.readNullable<String>('ledger_id');
      if (ledgerId == null) {
        continue;
      }
      final categoryId = row.readNullable<String>('category_id');
      final total = row.read<int>('total');
      if (categoryId == null) {
        spendByLedger[ledgerId] = (spendByLedger[ledgerId] ?? 0) + total;
      } else {
        final key = '$ledgerId|$categoryId';
        spendByLedgerCat[key] = (spendByLedgerCat[key] ?? 0) + total;
        spendByLedger[ledgerId] = (spendByLedger[ledgerId] ?? 0) + total;
      }
    }
    final kcalInByLedger = <String, int>{};
    final kcalOutByLedger = <String, int>{};
    for (final row in kcalRows) {
      // kcal 行归集到内置 kcal 账本（§5.2②）；未挂账本的组不进预算口径。
      final ledgerId = row.readNullable<String>('ledger_id');
      if (ledgerId == null) {
        continue;
      }
      kcalInByLedger[ledgerId] = row.read<int>('kcal_in');
      kcalOutByLedger[ledgerId] = row.read<int>('kcal_out');
    }

    final kindOf = <String, String>{};
    final ledgers = await (_db.select(_db.ledgers)
          ..where((t) => t.deletedAt.isNull()))
        .get();
    for (final ledger in ledgers) {
      kindOf[ledger.id] = ledger.kind;
    }

    final budgets = await (_db.select(_db.budgets)
          ..where((t) =>
              t.periodType.equals('daily') & t.deletedAt.isNull()))
        .get();
    final items = <Map<String, Object?>>[];
    for (final budget in budgets) {
      final int used;
      if (kindOf[budget.ledgerId] == 'kcal') {
        // kcal 预算：吃=支出、运动=再入账（§5.4 kcal 账本行口径）。
        used = (kcalInByLedger[budget.ledgerId] ?? 0) -
            (kcalOutByLedger[budget.ledgerId] ?? 0);
      } else if (budget.categoryId == null) {
        used = spendByLedger[budget.ledgerId] ?? 0;
      } else {
        used = spendByLedgerCat['${budget.ledgerId}|${budget.categoryId}'] ?? 0;
      }
      items.add(<String, Object?>{
        'ledger_id': budget.ledgerId,
        'category_id': budget.categoryId,
        'amount': budget.amount,
        'used': used,
        'remaining': budget.amount - used,
      });
    }
    return <String, Object?>{'daily': items};
  }
}
