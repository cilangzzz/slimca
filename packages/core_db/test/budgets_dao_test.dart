/// BudgetsDao 对账测试（§5.4⑥ budgets、§11.2 W15「预算体系」）。
///
/// 覆盖（任务口径「预算快照 v2 形状与兼容」的 DAO 半边）：
/// - CRUD 形状：upsert 插入/原行更新（同 (ledger,category,period) 一条
///   现行预算）、软删墓碑、周期/起点/结转字段；
/// - 校验：period wire 值、amount 正数、monthly 起点 1..28、账本/分类
///   存在性（逻辑引用人工校验）；
/// - kcal 账本预算允许（预算=kcal，§5.4 kcal 账本行）；
/// - outbox 同事务入队（§6.2/§5.6⑯）：upsert=op upsert、软删=op delete、
///   重复设置折叠为一条 pending（入队去重）；
/// - 投影联动（§5.6⑬ W15 v2）：注入 projection 后预算写路径重算全部
///   投影行的 budget_snapshot（dirty 复位、快照含预算项）。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过（与 W1 schema 冒烟同一策略）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
// as drift：测试内 where 表达式 `&` 组合算子（前缀导入扩展不生效，须裸导入）。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('CRUD 形状：upsert 插入→原行更新、软删墓碑、outbox 入队与折叠', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，BudgetsDao 测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      await drainSeedOutbox(database);
      final db.BudgetsDao dao = db.BudgetsDao(database);
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;

      // 新建（daily 总预算）。
      final db.Budget first = await dao.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 10000,
      );
      expect(first.periodType, db.kBudgetPeriodDaily);
      expect(first.categoryId, isNull);
      expect(first.amount, 10000);
      expect(first.dayOfMonthStart, 1);
      expect(first.carryOver, isFalse);
      expect(first.deletedAt, isNull);

      // outbox：业务行快照同事务入队（§6.2）。
      List<db.SyncOutboxItem> outbox = await (database.select(
        database.syncOutbox,
      )..where((t) => t.targetTable.equals('budgets')))
          .get();
      expect(outbox.length, 1, reason: '一条预算一行出网');
      expect(outbox.single.op, 'upsert');
      expect(outbox.single.rowId, first.id);

      // 同 (ledger, category, period) 重复设置 = 原行改额（不堆叠多行）。
      final db.Budget updated = await dao.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 12000,
      );
      expect(updated.id, first.id, reason: '同一现行预算原行更新');
      expect(updated.amount, 12000);
      expect(updated.revision, first.revision + 1);
      outbox = await (database.select(database.syncOutbox)
            ..where((t) => t.targetTable.equals('budgets')))
          .get();
      expect(outbox.length, 1, reason: '入队去重：同事务折叠为一条 pending');
      expect(outbox.single.rowId, first.id);

      // 分类预算与总预算是不同预算（NULL 与非 NULL，§5.4⑥）。
      final db.Category category =
          (await db.CategoryDao(database).getAll()).first;
      final db.Budget catBudget = await dao.upsertBudget(
        ledgerId: money.id,
        categoryId: category.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 3000,
      );
      expect(catBudget.id, isNot(first.id));
      expect(catBudget.categoryId, category.id);
      expect(
        await dao.findCurrent(ledgerId: money.id, periodType: db.kBudgetPeriodDaily),
        isNotNull,
        reason: '总预算独立存在',
      );

      // 月度预算（monthly）：起点/结转字段落库。
      final db.Budget monthly = await dao.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodMonthly,
        amount: 200000,
        dayOfMonthStart: 15,
        carryOver: true,
      );
      expect(monthly.periodType, db.kBudgetPeriodMonthly);
      expect(monthly.dayOfMonthStart, 15);
      expect(monthly.carryOver, isTrue);

      // 软删墓碑 + delete 语义出网（§5.1 删除行/§5.6⑯）。
      await dao.softDeleteBudget(monthly.id);
      final db.Budget? tombstoned = await (database.select(database.budgets)
            ..where((t) => t.id.equals(monthly.id)))
          .getSingleOrNull();
      expect(tombstoned?.deletedAt, isNotNull);
      final List<db.SyncOutboxItem> budgetOutbox = await (database.select(
        database.syncOutbox,
      )..where((t) => t.targetTable.equals('budgets') & t.rowId.equals(monthly.id)))
          .get();
      expect(budgetOutbox.single.op, 'delete', reason: '墓碑行以 delete 出网');
      // 幂等：已删重复软删 no-op（§6.5 删除策略）。
      await dao.softDeleteBudget(monthly.id);
      expect(
        await (database.select(database.budgets)
              ..where((t) => t.id.equals(monthly.id)))
            .getSingleOrNull(),
        isNotNull,
        reason: '墓碑行保留（墓碑拒绝复活、不做物理删，§5.1）',
      );
    } finally {
      await database.close();
    }
  });

  test('校验：period wire 值/正数/月起点 1..28/账本与分类存在性', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，BudgetsDao 测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final db.BudgetsDao dao = db.BudgetsDao(database);
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;
      final db.Category category =
          (await db.CategoryDao(database).getAll()).first;

      expect(
        () => dao.upsertBudget(
          ledgerId: money.id,
          periodType: 'weekly',
          amount: 100,
        ),
        throwsArgumentError,
        reason: 'period 限 daily/monthly（§5.4⑥）',
      );
      expect(
        () => dao.upsertBudget(
          ledgerId: money.id,
          periodType: db.kBudgetPeriodDaily,
          amount: 0,
        ),
        throwsArgumentError,
        reason: 'amount 必须为正（§5.4⑥）',
      );
      expect(
        () => dao.upsertBudget(
          ledgerId: money.id,
          periodType: db.kBudgetPeriodMonthly,
          amount: 100,
          dayOfMonthStart: 29,
        ),
        throwsArgumentError,
        reason: '月起点 1..28（规避大小月边界）',
      );
      expect(
        () => dao.upsertBudget(
          ledgerId: 'ledger-not-exists',
          periodType: db.kBudgetPeriodDaily,
          amount: 100,
        ),
        throwsStateError,
        reason: '账本存在性人工校验（逻辑引用不建外键，§5.4④）',
      );
      expect(
        () => dao.upsertBudget(
          ledgerId: money.id,
          categoryId: 'category-not-exists',
          periodType: db.kBudgetPeriodDaily,
          amount: 100,
        ),
        throwsStateError,
        reason: '分类存在性人工校验（§5.4⑤）',
      );

      // kcal 账本预算允许（预算=kcal 整数，§5.4 kcal 账本行）。
      final db.Ledger kcal = (await db.LedgerDao(database).kcalLedger())!;
      final db.Budget kcalBudget = await dao.upsertBudget(
        ledgerId: kcal.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 2000,
      );
      expect(kcalBudget.amount, 2000);

      // 分类级预算（categoryId 非空=分类预算，§5.4⑥）。
      final db.Budget catBudget = await dao.upsertBudget(
        ledgerId: money.id,
        categoryId: category.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 3000,
      );
      expect(catBudget.categoryId, category.id);
      expect(catBudget.ledgerId, money.id);
    } finally {
      await database.close();
    }
  });

  test('投影联动：预算写入后全部投影行 budget_snapshot 重算（W15 v2）', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，BudgetsDao 测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;
      final db.DaySummaryProjection projection =
          db.DaySummaryProjection(database);
      final db.BudgetsDao dao = db.BudgetsDao(database, projection: projection);

      // 先落两日流水并构建投影行（无预算 → v2 空集）。
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      const String day1 = '2026-03-01';
      const String day2 = '2026-03-02';
      // id 为 TEXT 主键（§5.1），测试用固定串即可（无格式校验）。
      const String entryId1 = '0196a7e0-0000-7000-8000-00000000b101';
      const String entryId2 = '0196a7e0-0000-7000-8000-00000000b102';
      await entryRepo.upsert(
          makeEntry(clock, id: entryId1, date: day1, title: 'd1'));
      await entryRepo.upsert(
          makeEntry(clock, id: entryId2, date: day2, title: 'd2'));
      await lineRepo.upsert(makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000b103',
        entryId: entryId1,
        type: domain.LineType.money,
        amount: 4000,
        direction: domain.LineDirection.outcome,
        ledgerId: money.id,
        currency: 'CNY',
      ));
      await lineRepo.upsert(makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000b104',
        entryId: entryId2,
        type: domain.LineType.money,
        amount: 6000,
        direction: domain.LineDirection.outcome,
        ledgerId: money.id,
        currency: 'CNY',
      ));
      await projection.recomputeAll();

      for (final String day in <String>[day1, day2]) {
        final db.DaySummary row = await (database.select(database.daySummaries)
              ..where((t) => t.date.equals(day)))
            .getSingle();
        final Map<String, Object?> snapshot =
            jsonDecode(row.budgetSnapshot) as Map<String, Object?>;
        expect(snapshot['daily'], isEmpty, reason: '建预算前 v2 空集');
        expect(row.dirty, isFalse);
      }

      // 建预算（注入 projection 的 DAO 写路径）→ 两日快照都应出现预算项。
      await dao.upsertBudget(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodDaily,
        amount: 5000,
      );
      for (final String day in <String>[day1, day2]) {
        final db.DaySummary row = await (database.select(database.daySummaries)
              ..where((t) => t.date.equals(day)))
            .getSingle();
        final Map<String, Object?> snapshot =
            jsonDecode(row.budgetSnapshot) as Map<String, Object?>;
        expect(snapshot['v'], 2);
        final List<Object?> daily = snapshot['daily']! as List<Object?>;
        expect(daily.length, 1);
        final Map<Object?, Object?> item = daily.single as Map<Object?, Object?>;
        expect(item['ledger_id'], money.id);
        expect(item['amount'], 5000);
        expect(
          item['used'],
          day == day1 ? 4000 : 6000,
          reason: 'daily 预算按日重算 used（§5.4⑥）',
        );
        expect(item['remaining'], (item['amount'] as int) - (item['used'] as int));
        expect(row.dirty, isFalse, reason: '联动重算后 dirty 复位（§5.6）');
      }

      // 清除预算 → 快照回落空集（联动双向）。
      final db.Budget? budget = await dao.findCurrent(
        ledgerId: money.id,
        periodType: db.kBudgetPeriodDaily,
      );
      await dao.softDeleteBudget(budget!.id);
      final db.DaySummary row = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day1)))
          .getSingle();
      final Map<String, Object?> snapshot =
          jsonDecode(row.budgetSnapshot) as Map<String, Object?>;
      expect(snapshot['daily'], isEmpty);
    } finally {
      await database.close();
    }
  });
}
