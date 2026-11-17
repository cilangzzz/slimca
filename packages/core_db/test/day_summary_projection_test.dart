/// day_summary 投影 v1 对账测试（§5.6⑬、§11.1 W2「day_summary 投影 v1」）。
///
/// 策略（任务口径）：随机生成 N 条 entry + entry_lines（含修正 supersede、
/// 软删墓碑、void 作废、跨日、事件改期），经 recomputeAll / recomputeDaySummary
/// 落投影后，与「手写 SQL 直接聚合」逐字段比对——测试内的 oracle 是独立
/// 逐指标查询（与投影实现的单条 CASE 聚合查询刻意不同构，互为印证）。
///
/// 另覆盖：todo_done/todo_total、tz_offset_min 解析链、dirty 自愈链路
/// （markDayDirty → recomputeDirtyDays）、无数据日不产生投影行。
library;

import 'dart:convert';
import 'dart:math';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
// hide isNull：matcher 的 isNull（expect(x, isNull)）与 drift 顶层 isNull
// 同名冲突；本测试只用 matcher 版本（列谓词走实例方法 t.deletedAt.isNull()）。
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// 测试日期集（§5.1 date=本地日历日 TEXT yyyy-MM-dd）。
const List<String> kDays = [
  '2026-11-20',
  '2026-11-21',
  '2026-11-22',
  '2026-11-23',
  '2026-11-24',
];

void main() {
  test('投影对账：随机 entry+lines（含修正/软删/void/跨日/改期）→ recomputeAll '
      '→ 与手写 SQL 直查聚合一致', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，投影对账测试未执行');
      return;
    }
    try {
      // 固定种子：随机但可复现（回归时失败可重放）。
      final rng = Random(20261123);
      final clock = TestClock('3F8A12C0B7D4', baseMs: 1763251200000);

      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;
      final kcalLedger = (await db.LedgerDao(database).kcalLedger())!;
      final category = (await db.CategoryDao(database).getAll()).first;

      // 写路径不注入投影：先落明细，末尾统一 recomputeAll（§5.6 自愈语义）。
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final todoDao = db.TodoDao(database);
      final projection = db.DaySummaryProjection(database);

      final activeLines = <domain.EntryLine>[];
      final entryIds = <String>[];

      // 每日先固定落一条锚点事件：保证 recomputeAll 后每个测试日都有投影行
      // （逐日 getSingle 对账不依赖随机分布；软删阶段锚点不入选，同理）。
      final anchorIds = <String>{};
      for (final day in kDays) {
        final anchorId = seededUuid(rng);
        await entryRepo.upsert(makeEntry(clock, id: anchorId, date: day));
        entryIds.add(anchorId);
        anchorIds.add(anchorId);
      }

      // ── 1) 随机生成 36 条事件，每条 1-3 个 facet 行（§5.2② 拆行口径）──
      for (var i = 0; i < 36; i++) {
        final date = kDays[rng.nextInt(kDays.length)];
        final entryId = seededUuid(rng, timestampMs: 1763251200000 + i);
        final kind = [
          domain.EntryKind.food,
          domain.EntryKind.fitness,
          domain.EntryKind.expense,
          domain.EntryKind.mixed,
        ][rng.nextInt(4)];
        // 大多 confirmed；约 1/4 draft（AI 未确认语义，§5.2① status 行）。
        final status = rng.nextInt(4) == 0
            ? domain.EntryStatus.draft
            : domain.EntryStatus.confirmed;
        final entry = makeEntry(
          clock,
          id: entryId,
          date: date,
          kind: kind,
          status: status,
        );
        await entryRepo.upsert(entry);
        entryIds.add(entryId);

        final lineCount = 1 + rng.nextInt(3);
        for (var j = 0; j < lineCount; j++) {
          final line = _randomLine(
            rng,
            clock,
            entryId: entryId,
            moneyLedgerId: moneyLedger.id,
            kcalLedgerId: kcalLedger.id,
            categoryId: category.id,
          );
          await lineRepo.upsert(line);
          activeLines.add(line);
        }
      }

      // ── 2) 随机修正：对若干 active 行走 supersede（§5.2② correction_of）──
      final supersedeCount = 4 + rng.nextInt(4);
      for (var i = 0; i < supersedeCount; i++) {
        final victim = activeLines[rng.nextInt(activeLines.length)];
        if (victim.status != domain.LineStatus.active) {
          continue;
        }
        final corrected = makeLine(
          clock,
          id: seededUuid(rng, timestampMs: 1763300000000 + i),
          entryId: victim.entryId,
          type: victim.type,
          amount: victim.amount + 1 + rng.nextInt(500),
          direction: victim.direction,
          ledgerId: victim.ledgerId,
          categoryId: victim.categoryId,
          currency: victim.currency,
          correctionOf: victim.id,
        );
        await lineRepo.supersede(victim.id, corrected);
        activeLines
          ..remove(victim)
          ..add(corrected);
      }

      // ── 3) void 作废：直接置 status（绕过仓库守卫，投影仍必须排除）──
      final voidCount = 2 + rng.nextInt(3);
      for (var i = 0; i < voidCount && i < activeLines.length; i++) {
        final target = activeLines[rng.nextInt(activeLines.length)];
        if (target.status != domain.LineStatus.active) {
          continue;
        }
        await (database.update(database.entryLines)
              ..where((t) => t.id.equals(target.id)))
            .write(const db.EntryLinesCompanion(status: Value('void')));
        activeLines.remove(target);
      }

      // ── 4) 软删墓碑：随机删几条事件（§5.1 删除行；行不级联，聚合需排除）。
      // 锚点事件不入选：每日恒有未删事件，投影行必在。
      final deletedIds = <String>{};
      for (var i = 0; i < 5 && entryIds.length > anchorIds.length; i++) {
        final victimId = entryIds[rng.nextInt(entryIds.length)];
        if (deletedIds.contains(victimId) || anchorIds.contains(victimId)) {
          continue;
        }
        await entryRepo.softDelete(victimId, hlc: clock.hlc());
        deletedIds.add(victimId);
        activeLines.removeWhere((l) => l.entryId == victimId);
      }

      // ── 5) 事件改期（跨日语义）：优先挑一条带明细行的未删事件移到另一日 ──
      final movableId = entryIds.firstWhere(
        (id) => !deletedIds.contains(id) && !anchorIds.contains(id),
        orElse: () => entryIds.firstWhere((id) => !deletedIds.contains(id)),
      );
      final movable = (await entryRepo.findById(movableId))!;
      final moved = movable.copyWith(
        date: '2026-11-24',
        meta: movable.meta.copyWith(
          updatedAt: 1763400000000,
          hlc: domain.Hlc(
            physicalMs: 1763400000000,
            counter: 0,
            deviceId: clock.deviceId,
          ).format(),
          revision: movable.meta.revision + 1,
        ),
      );
      await entryRepo.upsert(moved);

      // ── 6) 待办：每日 0-4 条，半数勾选；另有一条收集箱与一条墓碑 ──
      final inboxTodo = await todoDao.create(title: '收集箱事项'); // date=NULL
      expect(inboxTodo.date, isNull);
      for (final day in kDays) {
        final count = rng.nextInt(5);
        for (var i = 0; i < count; i++) {
          final todo = await todoDao.create(title: '待办-$day-$i', date: day);
          if (rng.nextBool()) {
            await todoDao.setDone(todo.id, done: true);
          }
        }
      }
      final doomedTodo = await todoDao.create(title: '会被删的待办', date: kDays.first);
      await todoDao.softDelete(doomedTodo.id);

      // ── 7) 全量重算（§5.6「可随时全量重建（自愈）」）──
      await projection.recomputeAll();

      // ── 8) 对账：投影行 vs 手写 SQL 直查聚合 ──
      for (final day in kDays) {
        final expectedKcalIn = await _oracleSum(database, day, 'calorie', 'in');
        final expectedKcalOut = await _oracleSum(database, day, 'burn', 'out');
        final expectedSpend = await _oracleSum(database, day, 'money', 'out');
        final expectedIncome = await _oracleSum(database, day, 'money', 'in');
        final expectedTodos = await _oracleTodos(database, day);

        final summary = await (database.select(database.daySummaries)
              ..where((t) => t.date.equals(day)))
            .getSingle();

        expect(summary.kcalIn, expectedKcalIn, reason: '$day kcal_in 对账');
        expect(summary.kcalOut, expectedKcalOut, reason: '$day kcal_out 对账');
        expect(summary.netKcal, expectedKcalIn - expectedKcalOut,
            reason: '$day net_kcal 对账');
        expect(summary.spendMinor, expectedSpend, reason: '$day spend_minor 对账');
        expect(summary.incomeMinor, expectedIncome, reason: '$day income_minor 对账');
        expect(summary.todoDone, expectedTodos.done, reason: '$day todo_done 对账');
        expect(summary.todoTotal, expectedTodos.total, reason: '$day todo_total 对账');

        expect(summary.dirty, isFalse, reason: '重算后 dirty 复位（§5.6）');
        expect(summary.builtAt, greaterThan(0));
        expect(summary.savingsProgress, isNull,
            reason: '§5.6⑬ W13 实装：本场景无当日有效目标 → 快照保持 NULL'
                '（专项对账见 savings_projection_test）');
        expect(jsonDecode(summary.budgetSnapshot), <String, Object?>{
          'v': 2,
          'daily': <Object?>[],
          'monthly': <Object?>[],
        }, reason: '未建预算时快照为 v2 空集（§5.6⑬ budget_snapshot，W15 v2 '
            'daily 项键形向后兼容 v1）');
        expect(summary.tzOffsetMin, 480, reason: '§5.1：取当日事件行时区');
      }

      // 无数据日不产生投影行（recomputeAll 只覆盖有明细/待办/旧行的日期）。
      final emptyDay = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals('2026-11-30')))
          .getSingleOrNull();
      expect(emptyDay, isNull);
    } finally {
      await database.close();
    }
  });

  test('单日重算：recomputeDaySummary 直算与全量重建结果一致；清零日保留时区', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，投影对账测试未执行');
      return;
    }
    try {
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final projection = db.DaySummaryProjection(database);
      final clock = TestClock('3F8A12C0B7D4');

      const day = '2026-12-01';
      final entryId = '0196a7e0-0000-7000-8000-00000000d001';
      await entryRepo.upsert(makeEntry(
        clock,
        id: entryId,
        date: day,
        kind: domain.EntryKind.mixed,
      ));
      await lineRepo.upsert(makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000d002',
        entryId: entryId,
        type: domain.LineType.money,
        amount: 2500,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      ));

      final single = await projection.recomputeDaySummary(day);
      expect(single.spendMinor, 2500);
      expect(single.kcalIn, 0);
      expect(single.tzOffsetMin, 480);

      // 事件软删后重算：聚合清零、tz 沿用旧投影行（§5.6 自愈，§5.1 墓碑不计入）。
      await entryRepo.softDelete(entryId, hlc: '1763500000000:000001:3F8A12C0B7D4');
      final zeroed = await projection.recomputeDaySummary(day);
      expect(zeroed.spendMinor, 0);
      expect(zeroed.incomeMinor, 0);
      expect(zeroed.kcalIn, 0);
      expect(zeroed.tzOffsetMin, 480, reason: '无事件行时沿用旧投影行时区');
    } finally {
      await database.close();
    }
  });

  test('投影自愈：外部直改明细 + markDayDirty → recomputeDirtyDays 后对账', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，投影对账测试未执行');
      return;
    }
    try {
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final projection = db.DaySummaryProjection(database);

      const day = '2026-12-02';
      final entryId = '0196a7e0-0000-7000-8000-00000000e001';
      final clock = TestClock('3F8A12C0B7D4');
      await entryRepo.upsert(
          makeEntry(clock, id: entryId, date: day));
      final lineId = '0196a7e0-0000-7000-8000-00000000e002';
      // 建行后用 raw SQL 直改金额，模拟「绕过仓库的外部写」（W7 起同步
      // pull 直写明细；仓库不可变守卫不适用于该路径，投影必须自愈吸收）。
      await lineRepo.upsert(makeLine(
        clock,
        id: lineId,
        entryId: entryId,
        type: domain.LineType.money,
        amount: 100,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      ));
      await projection.recomputeAll();
      final before = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();
      expect(before.spendMinor, 100);

      // 外部直改（模拟 W7 同步 pull 直写）：100 → 250。
      await (database.update(database.entryLines)
            ..where((t) => t.id.equals(lineId)))
          .write(const db.EntryLinesCompanion(amount: Value(250)));
      await projection.markDayDirty(day);
      await projection.recomputeDirtyDays();

      final after = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();
      expect(after.spendMinor, 250, reason: '§5.6 自愈：dirty 行重算吸收外部变更');
      expect(after.dirty, isFalse, reason: '重算完成 dirty 复位');

      // 再次 recomputeDirtyDays 应为 no-op（无 dirty 行）。
      await (database.update(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .write(const db.DaySummariesCompanion(dirty: Value(true)));
      await projection.recomputeDirtyDays();
      final again = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();
      expect(again.spendMinor, 250);
      expect(again.dirty, isFalse);
    } finally {
      await database.close();
    }
  });
}

// ── 手写 SQL oracle（与投影实现不同构：逐指标独立查询）─────────────────

/// 单指标直接聚合（status=active、行/事件未删——§5.6⑬ 口径）。
Future<int> _oracleSum(
  db.AppDatabase database,
  String date,
  String type,
  String direction,
) async {
  final row = await database
      .customSelect(
        'SELECT COALESCE(SUM(l.amount), 0) AS total '
        'FROM entry_lines l INNER JOIN entries e ON e.id = l.entry_id '
        'WHERE e.date = ? AND l.type = ? AND l.direction = ? '
        "AND l.status = 'active' AND l.deleted_at IS NULL "
        'AND e.deleted_at IS NULL',
        variables: [
          Variable.withString(date),
          Variable.withString(type),
          Variable.withString(direction),
        ],
      )
      .getSingle();
  return row.read<int>('total');
}

/// 待办计数直接查询（COUNT 两次，与投影的 SUM-CASE 不同构）。
Future<({int done, int total})> _oracleTodos(
  db.AppDatabase database,
  String date,
) async {
  final totalRow = await database
      .customSelect(
        'SELECT COUNT(*) AS c FROM todos WHERE date = ? AND deleted_at IS NULL',
        variables: [Variable.withString(date)],
      )
      .getSingle();
  final doneRow = await database
      .customSelect(
        'SELECT COUNT(*) AS c FROM todos '
        'WHERE date = ? AND deleted_at IS NULL AND done_at IS NOT NULL',
        variables: [Variable.withString(date)],
      )
      .getSingle();
  return (done: doneRow.read<int>('c'), total: totalRow.read<int>('c'));
}

/// 随机 facet 行：calorie(in)/burn(out)/money(out|in)，金额与热量维度并存
/// （§5.2② type/direction 行、§5.4 kcal 账本归集）。
domain.EntryLine _randomLine(
  Random rng,
  TestClock clock, {
  required String entryId,
  required String moneyLedgerId,
  required String kcalLedgerId,
  required String categoryId,
}) {
  final roll = rng.nextInt(10);
  if (roll < 4) {
    // 摄入行（calorie=in，§5.2② direction 行）。
    return makeLine(
      clock,
      id: seededUuid(rng),
      entryId: entryId,
      type: domain.LineType.calorie,
      amount: 50 + rng.nextInt(1500),
      direction: domain.LineDirection.income,
      ledgerId: kcalLedgerId,
      confidence: rng.nextBool() ? 0.5 + rng.nextDouble() / 2 : null,
    );
  } else if (roll < 6) {
    // 消耗行（burn=out）。
    return makeLine(
      clock,
      id: seededUuid(rng),
      entryId: entryId,
      type: domain.LineType.burn,
      amount: 30 + rng.nextInt(900),
      direction: domain.LineDirection.outcome,
      ledgerId: kcalLedgerId,
    );
  } else if (roll < 9) {
    // 支出行（money=out，挂默认账本+分类，§5.2② ledger/category 行）。
    return makeLine(
      clock,
      id: seededUuid(rng),
      entryId: entryId,
      type: domain.LineType.money,
      amount: 100 + rng.nextInt(50000),
      direction: domain.LineDirection.outcome,
      ledgerId: moneyLedgerId,
      categoryId: categoryId,
      currency: 'CNY',
    );
  }
  // 收入行（money=in）。
  return makeLine(
    clock,
    id: seededUuid(rng),
    entryId: entryId,
    type: domain.LineType.money,
    amount: 100 + rng.nextInt(20000),
    direction: domain.LineDirection.income,
    ledgerId: moneyLedgerId,
    currency: 'CNY',
  );
}
