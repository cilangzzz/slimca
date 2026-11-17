/// budget_snapshot v2 形状与兼容对账测试（§5.6⑬、§11.2 W15「预算体系」）。
///
/// 覆盖（任务口径「预算快照 v2 形状与兼容」）：
/// - **v2 形状**：`{"v":2,"daily":[…],"monthly":[…]}`——daily 项键形与 v1
///   逐键一致（向后兼容契约）；monthly 项含 carry_over/period_start/
///   period_end；
/// - **daily 口径**：money 总预算 used=当日支出、分类预算 used=当日该分类
///   支出、kcal 预算 used=当日 kcal_in-kcal_out（§5.4 kcal 账本「吃=支出、
///   运动=再入账」）；
/// - **monthly 周期窗口**：day_of_month_start=15 → 含当日的 [上月15, 本月15)
///   窗口（跨月窗口聚合）；
/// - **单步结转（carry_over）**：上一周期 remaining 非负部分并入 amount；
/// - **兼容解析**：手写 v1 形状 JSON（无 v/monthly 键）可被 v2 前的读取口径
///   （'daily' 键直读）解析——即 v1 行在投影重算前不破坏旧读取端；
/// - **自愈升级**：v1 快照行经 recomputeAll 整行升级为 v2（§5.6 自愈）。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
// as drift：测试内覆写快照列用 drift.Value（前缀形态与 core_db 测试惯例一致）。
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// 测试日历（2026-02）：02-03 落在 start=15 的周期窗口 [01-15, 02-15) 内，
/// 也落在 start=1 的二月窗口内——双窗口口径同日校验。
const String kDay = '2026-02-03';

/// 窗口内另一日（上一月侧，只对 start=15 窗口可见）。
const String kPrevMonthDay = '2026-01-20';

void main() {
  test('v2 形状：daily 逐项口径 + monthly 周期窗口 + 单步结转', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，budget_snapshot v2 测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;
      final db.Ledger kcal = (await db.LedgerDao(database).kcalLedger())!;
      final List<db.Category> categories =
          await db.CategoryDao(database).getAll();
      final String catFood = categories
          .firstWhere((c) => c.name == '餐饮-正餐')
          .id;
      final String catTraffic =
          categories.firstWhere((c) => c.name == '交通').id;

      // ── 流水：kDay（分类支出 + kcal）与 kPrevMonthDay（仅 money 支出）──
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      Future<void> seedDay(
        String day,
        List<domain.EntryLine> Function(String entryId) buildLines,
      ) async {
        final String entryId =
            '0196a7e0-0000-7000-8000-${day.replaceAll('-', '').substring(2)}e1';
        await entryRepo.upsert(makeEntry(clock, id: entryId, date: day));
        for (final domain.EntryLine line in buildLines(entryId)) {
          await lineRepo.upsert(line);
        }
      }

      // 02-03：餐饮 3000 + 交通 2000 + 无分类 500 + kcal 摄入 1800 + burn 300。
      await seedDay(kDay, (String entryId) => <domain.EntryLine>[
        _moneyLine(clock, entryId: entryId, ledgerId: money.id, categoryId: catFood, amount: 3000, seq: 1, day: kDay),
        _moneyLine(clock, entryId: entryId, ledgerId: money.id, categoryId: catTraffic, amount: 2000, seq: 2, day: kDay),
        _moneyLine(clock, entryId: entryId, ledgerId: money.id, categoryId: null, amount: 500, seq: 3, day: kDay),
        _kcalInLine(clock, entryId: entryId, ledgerId: kcal.id, amount: 1800, seq: 4, day: kDay),
        _burnLine(clock, entryId: entryId, ledgerId: kcal.id, amount: 300, seq: 5, day: kDay),
      ]);
      // 01-20（start=15 窗口侧）：交通 1500 + 无分类 700。
      await seedDay(kPrevMonthDay, (String entryId) => <domain.EntryLine>[
        _moneyLine(clock, entryId: entryId, ledgerId: money.id, categoryId: catTraffic, amount: 1500, seq: 6, day: kPrevMonthDay),
        _moneyLine(clock, entryId: entryId, ledgerId: money.id, categoryId: null, amount: 700, seq: 7, day: kPrevMonthDay),
      ]);

      // ── 预算：daily×3（总/分类/kcal）+ monthly×2（跨月窗口/结转） ──
      final db.BudgetsDao budgets = db.BudgetsDao(database);
      await budgets.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 10000,
      );
      await budgets.upsertBudget(
        ledgerId: money.id,
        categoryId: catFood,
        periodType: db.kBudgetPeriodDaily,
        amount: 4000,
      );
      await budgets.upsertBudget(
        ledgerId: kcal.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 2000,
      );
      // 跨月窗口月预算（起点 15，不结转）。
      await budgets.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodMonthly,
        amount: 90000,
        dayOfMonthStart: 15,
      );
      // 起点为 1 的月预算，带结转，挂 kcal 账本（同一 (ledger,category,
      // period) 只允许一条现行预算——BudgetsDao 契约，故结转用例换 kcal
      // 账本作用域）：上窗口 [01-01, 02-01) kcal used=0（01-20 仅 money
      // 支出）→ 剩余 5000 → 本窗口 amount=5000+5000=10000。
      await budgets.upsertBudget(
        ledgerId: kcal.id,
        periodType: db.kBudgetPeriodMonthly,
        amount: 5000,
        dayOfMonthStart: 1,
        carryOver: true,
      );

      final db.DaySummaryProjection projection =
          db.DaySummaryProjection(database);
      final db.DaySummary row = await projection.recomputeDaySummary(kDay);
      final Map<String, Object?> snapshot =
          jsonDecode(row.budgetSnapshot) as Map<String, Object?>;

      // ── v2 顶层形状 ──
      expect(snapshot['v'], 2, reason: 'W15 v2 版本标记');
      final List<Object?> daily = snapshot['daily']! as List<Object?>;
      final List<Object?> monthly = snapshot['monthly']! as List<Object?>;
      expect(daily.length, 3, reason: 'daily 总/分类/kcal 三条');
      expect(monthly.length, 2, reason: 'monthly 两条（起点 15/起点 1）');

      // ── daily 项键形与 v1 逐键一致（向后兼容契约）──
      for (final Object? rawItem in daily) {
        expect((rawItem! as Map<Object?, Object?>).keys.toSet(),
            <String>{'ledger_id', 'category_id', 'amount', 'used', 'remaining'},
            reason: 'v2 daily 项与 v1 键形完全一致——旧读取端按 daily 键直读不受影响');
      }

      // 总预算 used=当日全部支出（3000+2000+500=5500）。
      final Map<Object?, Object?> totalDaily = daily
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> item) =>
              item['ledger_id'] == money.id && item['category_id'] == null);
      expect(totalDaily['used'], 5500);
      expect(totalDaily['amount'], 10000);
      expect(totalDaily['remaining'], 4500);

      // 分类预算 used=该分类当日支出（餐饮 3000）。
      final Map<Object?, Object?> foodDaily = daily
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> item) =>
              item['category_id'] == catFood);
      expect(foodDaily['used'], 3000);
      expect(foodDaily['remaining'], 1000);

      // kcal 预算 used=摄入-消耗（1800-300=1500，§5.4 kcal 口径）。
      final Map<Object?, Object?> kcalDaily = daily
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> item) =>
              item['ledger_id'] == kcal.id);
      expect(kcalDaily['used'], 1500, reason: 'kcal 预算=吃-运动再入账');
      expect(kcalDaily['remaining'], 500);

      // ── monthly 项：起点 15 → 窗口 [2026-01-15, 2026-02-15)，
      // used=窗口内支出（01-20 的 1500+700 + 02-03 的 5500=7700）──
      final Map<Object?, Object?> monthly15 = monthly
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> item) =>
              item['period_start'] == '2026-01-15');
      expect(monthly15['period_end'], '2026-02-15');
      expect(monthly15['carry_over'], false);
      expect(monthly15['used'], 7700,
          reason: '月度窗口跨月聚合（§5.4⑥ day_of_month_start）');
      expect(monthly15['amount'], 90000);
      expect(monthly15['remaining'], 82300);

      // ── monthly 结转：kcal 账本、起点 1 → 窗口 [2026-02-01, 2026-03-01)，
      // 上窗口 [01-01, 02-01) kcal used=0 → carry=5000，
      // amount=10000、used=1500、remaining=8500 ──
      final Map<Object?, Object?> monthlyCarry = monthly
          .cast<Map<Object?, Object?>>()
          .firstWhere((Map<Object?, Object?> item) =>
              item['ledger_id'] == kcal.id &&
              item['period_start'] == '2026-02-01');
      expect(monthlyCarry['carry_over'], true);
      expect(monthlyCarry['amount'], 10000, reason: '单步结转：amount+=上期剩余（§5.4⑥）');
      expect(monthlyCarry['used'], 1500);
      expect(monthlyCarry['remaining'], 8500);
    } finally {
      await database.close();
    }
  });

  test('兼容与自愈：v1 形状行可被旧口径解析；recomputeAll 整行升级为 v2', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，budget_snapshot v2 测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;
      final db.DaySummaryProjection projection =
          db.DaySummaryProjection(database);

      const String day = '2026-04-01';
      const String entryId = '0196a7e0-0000-7000-8000-00000000c001';
      await db.DriftEntryRepository(database).upsert(
          makeEntry(clock, id: entryId, date: day));
      await db.DriftEntryLineRepository(database).upsert(_moneyLine(
        clock,
        entryId: entryId,
        ledgerId: money.id,
        categoryId: null,
        amount: 2500,
        seq: 1,
        day: day,
      ));
      await projection.recomputeDaySummary(day);

      // 手写 v1 形状快照覆写（模拟 W2 旧投影行）。
      const String v1Json = '{"daily":[{"ledger_id":"LM","category_id":null,'
          '"amount":8000,"used":2500,"remaining":5500}]}';
      await (database.update(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .write(db.DaySummariesCompanion(
        budgetSnapshot: const drift.Value(v1Json),
      ));

      // v1 行的旧读取口径（'daily' 键直读）：键存在、daily 项完整——
      // v2 升级不破坏旧读取端（向后兼容承诺）。
      final db.DaySummary before = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();
      final Map<String, Object?> v1 = jsonDecode(before.budgetSnapshot)
          as Map<String, Object?>;
      expect(v1.containsKey('daily'), isTrue);
      expect(v1.containsKey('v'), isFalse, reason: 'v1 行无版本键');
      final Map<Object?, Object?> v1Item =
          (v1['daily']! as List<Object?>).single as Map<Object?, Object?>;
      expect(v1Item['used'], 2500);

      // 自愈升级（§5.6「可随时全量重建」）：重算整行升级为 v2。本例无
      // 预算行 → daily 回落 v2 空集（v1 读取端拿到的数组形状不变、只是
      // 内容按真实口径重算——v1 行里的快照本来就是可重建的派生量）。
      await projection.recomputeAll();
      final db.DaySummary after = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();
      final Map<String, Object?> v2 =
          jsonDecode(after.budgetSnapshot) as Map<String, Object?>;
      expect(v2['v'], 2, reason: 'v1 行经自愈重算升级为 v2');
      expect(v2['daily'], isEmpty);
      expect(v2['monthly'], isEmpty);
    } finally {
      await database.close();
    }
  });
}

// ── 夹具 ─────────────────────────────────────────────────────────────────

/// money-out 行（§5.2②：ledger 必填、currency 恒 CNY）。
domain.EntryLine _moneyLine(
  TestClock clock, {
  required String entryId,
  required String ledgerId,
  required String? categoryId,
  required int amount,
  required int seq,
  required String day,
}) =>
    makeLine(
      clock,
      id: '0196a7e0-0000-7000-8000-'
          '${day.replaceAll('-', '').substring(2)}l$seq',
      entryId: entryId,
      type: domain.LineType.money,
      amount: amount,
      direction: domain.LineDirection.outcome,
      ledgerId: ledgerId,
      categoryId: categoryId,
      currency: 'CNY',
    );

/// calorie-in 行（kcal 账本）。
domain.EntryLine _kcalInLine(
  TestClock clock, {
  required String entryId,
  required String ledgerId,
  required int amount,
  required int seq,
  required String day,
}) =>
    makeLine(
      clock,
      id: '0196a7e0-0000-7000-8000-'
          '${day.replaceAll('-', '').substring(2)}l$seq',
      entryId: entryId,
      type: domain.LineType.calorie,
      amount: amount,
      direction: domain.LineDirection.income,
      ledgerId: ledgerId,
    );

/// burn-out 行（kcal 账本，运动再入账）。
domain.EntryLine _burnLine(
  TestClock clock, {
  required String entryId,
  required String ledgerId,
  required int amount,
  required int seq,
  required String day,
}) =>
    makeLine(
      clock,
      id: '0196a7e0-0000-7000-8000-'
          '${day.replaceAll('-', '').substring(2)}l$seq',
      entryId: entryId,
      type: domain.LineType.burn,
      amount: amount,
      direction: domain.LineDirection.outcome,
      ledgerId: ledgerId,
    );
