/// 仪表盘数据源（§3.2 快照直出、§5.6⑬ day_summary 投影、§10.4 分层）。
///
/// 分层约定：页面只依赖抽象 [DashboardRepository]（构造注入），不触碰
/// AppDatabase 具体类；本文件内 [DriftDashboardRepository] 是 W2 的 Drift
/// 实现（§5.6⑬ 读侧 watch + 重建规则 v1）。core_db 的 DAO/投影按 §10.4
/// 「随 feature 需求增量补充」成熟后可整体迁入，接口不变。
///
/// Drift 2.x API 口径（与 core_db 对齐）：join 用 `innerJoin()` 函数、
/// upsert 用 `insertOnConflictUpdate` 扩展——勿引 Drift 3 的 `InnerJoin`
/// 类写法（§10.3 环境实况：解析版本 drift 2.29）。
library;

import 'dart:async';

import 'package:core_db/core_db.dart' as db;
// 只取日期校验入口，避免与 core_db 生成行类（Entry/EntryLine）同名冲突（§5.2）。
import 'package:core_domain/core_domain.dart' show validateCalendarDay;
import 'package:drift/drift.dart' as drift;

import 'dashboard_models.dart';

/// 仪表盘数据源抽象（§3.2「首帧读投影不发起业务查询」的读侧契约）。
abstract interface class DashboardRepository {
  /// watch 某本地日历日的 day_summary 投影（§5.6⑬「reactive stream 直驱」，
  /// §10.1 Drift 行）。当日尚未重建过投影时发 null。
  ///
  /// [date] 必须为本地日历日 `yyyy-MM-dd`（§5.1，非法即抛 ArgumentError）。
  Stream<DashboardDaySummary?> watchDay(String date);

  /// watch 月份累计支出（分）——支出卡「本月累计」（§3.2 卡片墙）。
  ///
  /// 聚合读投影表（day_summaries 逐日 spend_minor 求和）而非明细表，与
  /// §5.6「仪表盘首帧直读本表、零业务查询」同一口径。
  /// [month] 必须为 `yyyy-MM` 月前缀（§5.1 日期口径）。
  Stream<int> watchMonthSpendMinor(String month);

  /// watch 全投影表「有记录日」集合（UI-规范与重设计.md §3.3 月格色点数据源）：
  /// 返回有任一钱/热量记录的本地日历日 `yyyy-MM-dd` 集合（§5.6⑬ day_summary
  /// 逐日行直读——行存在且四项标量非零即「有记录」，与
  /// [DashboardDaySummary.hasAnyRecord] 同口径）。
  ///
  /// 全表 watch：投影表一天一行、规模有界（本地单用户），代价可忽略；月网格
  /// 翻月箭头在任意月切换均有色点数据（组合容器焦点月为内部状态，宿主无法
  /// 逐月订阅）。月格 Compact 色点（每格 ≤3 色点，V1 一点=有记录；点数/
  /// 分类色映射随 W17 记录条数投影扩展，§3.2 密度三档）。
  Stream<Set<String>> watchRecordedDays();

  /// 重建某日投影（§5.6 重建规则 v1：entry_lines ⋈ entries 明细聚合 →
  /// upsert 投影行、清 dirty）。写路径（feature_capture/feature_ledger 落库）
  /// 后调用，即可实现「手动记一笔→仪表盘环/支出卡即时更新」（§11.1 W2 验收）；
  /// 可随时全量逐日重建（自愈，§5.6）。
  Future<void> recomputeDay(String date);
}

/// [DashboardRepository] 的 Drift 实现（§10.4 core_db 之上的读侧适配）。
class DriftDashboardRepository implements DashboardRepository {
  DriftDashboardRepository(this._db);

  final db.AppDatabase _db;

  @override
  Stream<DashboardDaySummary?> watchDay(String date) {
    validateCalendarDay(date, name: 'date');
    final query = _db.select(_db.daySummaries)
      ..where((t) => t.date.equals(date));
    return query.watchSingleOrNull().map(_mapRow);
  }

  @override
  Stream<int> watchMonthSpendMinor(String month) {
    // 月份区间按 TEXT 定宽字典序比较（yyyy-MM-dd 定宽，§5.1）。
    final String start = _monthStart(month);
    final String end = _nextMonthStart(month);
    final query = _db.select(_db.daySummaries)
      ..where(
        (t) =>
            t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end),
      );
    return query.watch().map(
      (List<db.DaySummary> rows) => rows.fold<int>(
        0,
        (int sum, db.DaySummary row) => sum + row.spendMinor,
      ),
    );
  }

  @override
  Stream<Set<String>> watchRecordedDays() {
    // 全表 watch + 「有记录」过滤（与 hasAnyRecord 同口径，§3.2）。
    final query = _db.select(_db.daySummaries).watch();
    return query.map(
      (List<db.DaySummary> rows) => rows
          .where(
            (db.DaySummary r) =>
                r.kcalIn != 0 ||
                r.kcalOut != 0 ||
                r.spendMinor != 0 ||
                r.incomeMinor != 0,
          )
          .map((db.DaySummary r) => r.date)
          .toSet(),
    );
  }

  @override
  Future<void> recomputeDay(String date) async {
    validateCalendarDay(date, name: 'date');
    await _db.transaction(() async {
      // ── 1) 明细聚合（§5.6 重建规则：任何 entry_line/corrections 变更 →
      //       标记当日 dirty → 后台重算；此处为重算本体）──
      // 剔除：entry 墓碑（§5.1 软删行）、行墓碑、非 active 行
      //（superseded=被修正旧行、void=作废，§5.2②——修正=新增行，旧行不再计入）。
      final linesQuery = _db.select(_db.entryLines).join([
        drift.innerJoin(
          _db.entries,
          _db.entryLines.entryId.equalsExp(_db.entries.id),
        ),
      ]);
      linesQuery.where(
        _db.entries.date.equals(date) &
            _db.entries.deletedAt.isNull() &
            _db.entryLines.status.equals('active') &
            _db.entryLines.deletedAt.isNull(),
      );
      final List<drift.TypedResult> lineRows = await linesQuery.get();
      int kcalIn = 0;
      int kcalOut = 0;
      int spendMinor = 0;
      int incomeMinor = 0;
      for (final drift.TypedResult row in lineRows) {
        final db.EntryLine line = row.readTable(_db.entryLines);
        switch (line.type) {
          case 'calorie': // §5.2②：calorie 行 amount=kcal，direction=in
            if (line.direction == 'in') {
              kcalIn += line.amount;
            }
          case 'burn': // §5.2②：burn 行 amount=kcal，direction=out（运动再入账）
            if (line.direction == 'out') {
              kcalOut += line.amount;
            }
          case 'money': // §5.2②：money 行 amount=分，expense=out / income=in
            if (line.direction == 'out') {
              spendMinor += line.amount;
            } else if (line.direction == 'in') {
              incomeMinor += line.amount;
            }
        }
      }

      // ── 2) 待办完成度（§5.6⑬ todo_done/todo_total；计划族独立于事件模型）──
      final todos = await (_db.select(
        _db.todos,
      )..where((t) => t.date.equals(date) & t.deletedAt.isNull())).get();
      final int todoTotal = todos.length;
      final int todoDone = todos.where((t) => t.doneAt != null).length;

      // ── 3) 预算快照（§5.6⑬ budget_snapshot）：v1 取每日全类目预算——
      //       kcal 账本=热量预算、money 账本=支出预算（§5.4⑥ budgets）──
      final DashboardBudgetSnapshot budget = await _readDailyBudgets();

      // ── 4) upsert 投影行（§5.6⑬：一天一行、永不同步；dirty 清零、
      //       built_at 刷新；savings_progress P1 启用前恒 NULL）──
      final DateTime now = DateTime.now();
      await _db
          .into(_db.daySummaries)
          .insertOnConflictUpdate(
            db.DaySummariesCompanion.insert(
              date: date,
              tzOffsetMin: now.timeZoneOffset.inMinutes,
              kcalIn: kcalIn,
              kcalOut: kcalOut,
              netKcal: kcalIn - kcalOut,
              spendMinor: spendMinor,
              incomeMinor: incomeMinor,
              todoDone: todoDone,
              todoTotal: todoTotal,
              budgetSnapshot: budget.encode(),
              builtAt: now.millisecondsSinceEpoch,
              dirty: const drift.Value(false),
            ),
          );
    });
  }

  /// 每日全类目预算（§5.4⑥）：kcal 账本 → kcalBudget，money 账本 →
  /// spendBudgetMinor；同账本多行预算取首行（MVP 单账本、§3.4）。
  Future<DashboardBudgetSnapshot> _readDailyBudgets() async {
    final query = _db.select(_db.budgets).join([
      drift.innerJoin(
        _db.ledgers,
        _db.budgets.ledgerId.equalsExp(_db.ledgers.id),
      ),
    ]);
    query.where(
      _db.budgets.periodType.equals('daily') &
          _db.budgets.categoryId.isNull() &
          _db.budgets.deletedAt.isNull() &
          _db.ledgers.deletedAt.isNull(),
    );
    final List<drift.TypedResult> rows = await query.get();
    int? kcalBudget;
    int? spendBudgetMinor;
    for (final drift.TypedResult row in rows) {
      final db.Ledger ledger = row.readTable(_db.ledgers);
      final int amount = row.readTable(_db.budgets).amount;
      switch (ledger.kind) {
        case 'kcal':
          kcalBudget ??= amount;
        case 'money':
          spendBudgetMinor ??= amount;
      }
    }
    return DashboardBudgetSnapshot(
      kcalBudget: kcalBudget,
      spendBudgetMinor: spendBudgetMinor,
    );
  }

  DashboardDaySummary? _mapRow(db.DaySummary? row) {
    if (row == null) {
      return null;
    }
    return DashboardDaySummary(
      date: row.date,
      kcalIn: row.kcalIn,
      kcalOut: row.kcalOut,
      netKcal: row.netKcal,
      spendMinor: row.spendMinor,
      incomeMinor: row.incomeMinor,
      todoDone: row.todoDone,
      todoTotal: row.todoTotal,
      budget: DashboardBudgetSnapshot.tryParse(row.budgetSnapshot),
      savings: parseSavingsProgress(row.savingsProgress),
    );
  }
}

/// `yyyy-MM` 月前缀校验与区间起点（TEXT 定宽字典序，§5.1）。
final RegExp _monthPattern = RegExp(r'^\d{4}-\d{2}$');

String _monthStart(String month) {
  if (!_monthPattern.hasMatch(month)) {
    throw ArgumentError.value(month, 'month', '必须为 yyyy-MM 月前缀（§5.1 日期口径）');
  }
  return '$month-01';
}

String _nextMonthStart(String month) {
  final int year = int.parse(month.substring(0, 4));
  final int m = int.parse(month.substring(5, 7));
  final int nextYear = m == 12 ? year + 1 : year;
  final int nextMonth = m == 12 ? 1 : m + 1;
  return '$nextYear-${nextMonth.toString().padLeft(2, '0')}-01';
}
