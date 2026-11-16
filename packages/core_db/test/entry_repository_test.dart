/// EntryRepository / EntryLineRepository 的 Drift 实现测试
/// （§5.2①②、§5.1 软删墓碑、§5.3 facet 行、§6.5 money 行不可变与墓碑拒绝复活）。
library;

import 'dart:math';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('upsert/find 往返：枚举、公共列与 facet 行保真（§5.2①②）', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;
      final kcalLedger = (await db.LedgerDao(database).kcalLedger())!;

      final entry = makeEntry(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000a001',
        date: '2026-11-23',
        kind: domain.EntryKind.mixed,
        source: domain.EntrySource.chip,
        status: domain.EntryStatus.confirmed,
        title: '午餐+买菜',
        note: '复记',
      );
      await entryRepo.upsert(entry);

      final line = makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000a002',
        entryId: entry.id,
        type: domain.LineType.money,
        amount: 4850,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        categoryId: null,
        currency: 'CNY',
        confidence: null,
      );
      await lineRepo.upsert(line);
      final kcalLine = makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000a003',
        entryId: entry.id,
        type: domain.LineType.calorie,
        amount: 720,
        direction: domain.LineDirection.income,
        ledgerId: kcalLedger.id,
        confidence: 0.86,
      );
      await lineRepo.upsert(kcalLine);

      final fetched = (await entryRepo.findById(entry.id))!;
      expect(fetched.kind, domain.EntryKind.mixed);
      expect(fetched.source, domain.EntrySource.chip);
      expect(fetched.status, domain.EntryStatus.confirmed);
      expect(fetched.note, '复记');
      expect(fetched.meta.hlc, entry.meta.hlc, reason: 'hlc 定宽编码往返一致');
      expect(fetched.meta.schemaVer, 1);

      final lines = await lineRepo.findByEntryId(entry.id);
      expect(lines, hasLength(2), reason: '§5.3：同一事件拆出金额+热量两个 facet 行');
      final money = lines.singleWhere((l) => l.type == domain.LineType.money);
      expect(money.amount, 4850);
      expect(money.direction, domain.LineDirection.outcome);
      expect(money.ledgerId, moneyLedger.id);
      expect(money.meta.hlc, line.meta.hlc);
      final kcal = lines.singleWhere((l) => l.type == domain.LineType.calorie);
      expect(kcal.confidence, closeTo(0.86, 1e-9), reason: 'AI 置信度 0-1（§5.2②）');

      // findByDate / findActiveByLedger / findByCorrectionOf 基线。
      expect((await entryRepo.findByDate('2026-11-23')), hasLength(1));
      expect(
        (await lineRepo.findActiveByLedger(moneyLedger.id))
            .where((l) => l.entryId == entry.id),
        hasLength(1),
      );
      expect(await lineRepo.findByCorrectionOf(line.id), isEmpty);
    } finally {
      await database.close();
    }
  });

  test('findByDateRange：kinds 过滤走 (kind,date) 索引形态 + 排除墓碑（§5.2①）', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      final rng = Random(7);

      final foodA = makeEntry(
        clock,
        id: seededUuid(rng),
        date: '2026-11-20',
        kind: domain.EntryKind.food,
      );
      final expenseB = makeEntry(
        clock,
        id: seededUuid(rng),
        date: '2026-11-21',
        kind: domain.EntryKind.expense,
      );
      final foodC = makeEntry(
        clock,
        id: seededUuid(rng),
        date: '2026-11-22',
        kind: domain.EntryKind.food,
      );
      final outsideD = makeEntry(
        clock,
        id: seededUuid(rng),
        date: '2026-11-25',
        kind: domain.EntryKind.food,
      );
      for (final e in [foodA, expenseB, foodC, outsideD]) {
        await entryRepo.upsert(e);
      }
      await entryRepo.softDelete(foodC.id, hlc: clock.hlc());

      final all = await entryRepo.findByDateRange('2026-11-20', '2026-11-22');
      expect(all.map((e) => e.id).toSet(), {foodA.id, expenseB.id},
          reason: '区间闭区间命中 A/B；C 已墓碑不计');

      final foodOnly = await entryRepo.findByDateRange(
        '2026-11-19',
        '2026-11-26',
        kinds: [domain.EntryKind.food],
      );
      expect(foodOnly.map((e) => e.id).toSet(), {foodA.id, outsideD.id},
          reason: 'kinds 过滤 + 全区间；墓碑 C 不计');

      final multi = await entryRepo.findByDateRange(
        '2026-11-19',
        '2026-11-26',
        kinds: [domain.EntryKind.food, domain.EntryKind.expense],
      );
      expect(multi.map((e) => e.id).toSet(), {foodA.id, expenseB.id, outsideD.id});

      // 空 kinds 列表等价于不过滤（不生成 IN 子句）。
      final noKind = await entryRepo.findByDateRange(
        '2026-11-19',
        '2026-11-26',
        kinds: const <domain.EntryKind>[],
      );
      expect(noKind, hasLength(3), reason: '墓碑 C 不计');
    } finally {
      await database.close();
    }
  });

  test('softDelete 墓碑：详情可见、列表/流排除、upsert 拒绝复活（§5.1/§6.5）', () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      const day = '2026-11-23';
      final entry = makeEntry(clock, id: 'e1-fixed', date: day);

      // watch 流当前快照（drift watch 首帧=当前查询结果）。
      expect(await entryRepo.watchByDate(day).first, isEmpty);
      await entryRepo.upsert(entry);
      final listed = await entryRepo.watchByDate(day).first;
      expect(listed, hasLength(1));

      await entryRepo.softDelete(entry.id, hlc: clock.hlc());

      final tombstone = (await entryRepo.findById(entry.id))!;
      expect(tombstone.isDeleted, isTrue, reason: '§5.1：软删墓碑 deleted_at 非 NULL');
      expect(tombstone.meta.deletedAt, isNotNull);

      expect(await entryRepo.watchByDate(day).first, isEmpty,
          reason: '业务列表/流排除墓碑');
      expect(await entryRepo.findByDate(day), isEmpty);

      // 删后编辑保持删除胜出（§6.5 删除行）：带未删 meta 的 upsert 不复活。
      final revived = entry.copyWith(meta: clock.meta());
      await entryRepo.upsert(revived);
      final stillDeleted = (await entryRepo.findById(entry.id))!;
      expect(stillDeleted.isDeleted, isTrue, reason: '§6.5：墓碑拒绝复活');
      expect(await entryRepo.watchByDate(day).first, isEmpty);

      // softDelete 不存在的行 → 明确报错。
      await expectLater(
        entryRepo.softDelete('no-such-row', hlc: clock.hlc()),
        throwsStateError,
      );
    } finally {
      await database.close();
    }
  });

  test('supersede：新增修正行 + 旧行置 superseded + 事件 confirmed→edited（§5.2②）',
      () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final projection = db.DaySummaryProjection(database);
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;

      final entryId = '0196a7e0-0000-7000-8000-00000000b001';
      await entryRepo.upsert(makeEntry(
        clock,
        id: entryId,
        date: '2026-11-23',
        kind: domain.EntryKind.expense,
        status: domain.EntryStatus.confirmed,
      ));
      final oldLineId = '0196a7e0-0000-7000-8000-00000000b002';
      await lineRepo.upsert(makeLine(
        clock,
        id: oldLineId,
        entryId: entryId,
        type: domain.LineType.money,
        amount: 1850,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      ));

      // 投影联动注入：修正后当日支出应即时更新（§11.1 W2 验收口径）。
      final reactiveRepo = db.DriftEntryLineRepository(
        database,
        projection: projection,
      );
      final correctionId = '0196a7e0-0000-7000-8000-00000000b003';
      await reactiveRepo.supersede(
        oldLineId,
        makeLine(
          clock,
          id: correctionId,
          entryId: entryId,
          type: domain.LineType.money,
          amount: 2000,
          direction: domain.LineDirection.outcome,
          ledgerId: moneyLedger.id,
          currency: 'CNY',
        ),
      );

      // 旧行：superseded；新行：active + correction_of 指回（§5.2②）。
      final oldRow = (await lineRepo.findById(oldLineId))!;
      expect(oldRow.status, domain.LineStatus.superseded);
      final newRow = (await lineRepo.findById(correctionId))!;
      expect(newRow.status, domain.LineStatus.active);
      expect(newRow.correctionOf, oldLineId);
      expect(newRow.amount, 2000);
      expect(await lineRepo.findByCorrectionOf(oldLineId), [newRow]);

      // 事件状态联动：confirmed → edited（§5.2①「含修正」）。
      final entry = (await entryRepo.findById(entryId))!;
      expect(entry.status, domain.EntryStatus.edited);

      // 修正链正确后投影即时更新：旧金额 1850 不计、新金额 2000 计入
      // （superseded 行不计入聚合，§5.6⑬）。
      final summary = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals('2026-11-23')))
          .getSingle();
      expect(summary.spendMinor, 2000);
    } finally {
      await database.close();
    }
  });

  test('supersede 非法路径：非 active / 跨事件 / correction_of 不匹配 → 抛错',
      () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;

      const entryA = '0196a7e0-0000-7000-8000-00000000c001';
      const entryB = '0196a7e0-0000-7000-8000-00000000c004';
      await entryRepo.upsert(makeEntry(clock, id: entryA, date: '2026-11-23'));
      await entryRepo.upsert(makeEntry(clock, id: entryB, date: '2026-11-24'));
      const lineId = '0196a7e0-0000-7000-8000-00000000c002';
      await lineRepo.upsert(makeLine(
        clock,
        id: lineId,
        entryId: entryA,
        type: domain.LineType.money,
        amount: 500,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      ));

      // correction_of 显式指向别的行 → ArgumentError（§5.2② correction_of）。
      await expectLater(
        lineRepo.supersede(
          lineId,
          makeLine(
            clock,
            id: '0196a7e0-0000-7000-8000-00000000c003',
            entryId: entryA,
            type: domain.LineType.money,
            amount: 600,
            direction: domain.LineDirection.outcome,
            ledgerId: moneyLedger.id,
            currency: 'CNY',
            correctionOf: 'other-line',
          ),
        ),
        throwsArgumentError,
      );

      // 跨事件修正 → ArgumentError（§5.2② entry_id）。
      await expectLater(
        lineRepo.supersede(
          lineId,
          makeLine(
            clock,
            id: '0196a7e0-0000-7000-8000-00000000c005',
            entryId: entryB,
            type: domain.LineType.money,
            amount: 600,
            direction: domain.LineDirection.outcome,
            ledgerId: moneyLedger.id,
            currency: 'CNY',
          ),
        ),
        throwsArgumentError,
      );

      // 第一次合法修正（correction_of 缺省自动补指）。
      const correctionId = '0196a7e0-0000-7000-8000-00000000c006';
      await lineRepo.supersede(
        lineId,
        makeLine(
          clock,
          id: correctionId,
          entryId: entryA,
          type: domain.LineType.money,
          amount: 600,
          direction: domain.LineDirection.outcome,
          ledgerId: moneyLedger.id,
          currency: 'CNY',
        ),
      );
      expect((await lineRepo.findById(correctionId))!.correctionOf, lineId);

      // 对已 superseded 的旧行再修正 → StateError（修正链线性，§5.2②）。
      await expectLater(
        lineRepo.supersede(
          lineId,
          makeLine(
            clock,
            id: '0196a7e0-0000-7000-8000-00000000c007',
            entryId: entryA,
            type: domain.LineType.money,
            amount: 700,
            direction: domain.LineDirection.outcome,
            ledgerId: moneyLedger.id,
            currency: 'CNY',
          ),
        ),
        throwsStateError,
      );

      // 修正不存在的旧行 → StateError。
      await expectLater(
        lineRepo.supersede(
          'ghost-line',
          makeLine(
            clock,
            id: '0196a7e0-0000-7000-8000-00000000c008',
            entryId: entryA,
            type: domain.LineType.money,
            amount: 700,
            direction: domain.LineDirection.outcome,
            ledgerId: moneyLedger.id,
            currency: 'CNY',
          ),
        ),
        throwsStateError,
      );
    } finally {
      await database.close();
    }
  });

  test('money 行不可变：confirmed 父事件下改金额事实抛错，draft 可改（§3.4/§6.5）',
      () async {
    final database = await tryOpenTestDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，仓库测试未执行');
      return;
    }
    try {
      final clock = TestClock('3F8A12C0B7D4');
      final entryRepo = db.DriftEntryRepository(database);
      final lineRepo = db.DriftEntryLineRepository(database);
      final moneyLedger = (await db.LedgerDao(database).defaultMoneyLedger())!;

      const entryId = '0196a7e0-0000-7000-8000-00000000d101';
      await entryRepo.upsert(makeEntry(
        clock,
        id: entryId,
        date: '2026-11-23',
        status: domain.EntryStatus.confirmed,
      ));
      const lineId = '0196a7e0-0000-7000-8000-00000000d102';
      final confirmedLine = makeLine(
        clock,
        id: lineId,
        entryId: entryId,
        type: domain.LineType.money,
        amount: 1850,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      );
      await lineRepo.upsert(confirmedLine);

      // 改金额 → MoneyLineImmutableException（§3.4「不可变性由仓库层强制」）。
      await expectLater(
        lineRepo.upsert(
          confirmedLine.copyWith(amount: 2000, meta: clock.meta()),
        ),
        throwsA(isA<domain.MoneyLineImmutableException>()),
      );

      // 改分类（金额事实族）同样被拒。
      await expectLater(
        lineRepo.upsert(
          confirmedLine.copyWith(categoryId: 'cat-x', meta: clock.meta()),
        ),
        throwsA(isA<domain.MoneyLineImmutableException>()),
      );

      // 改 status（active→void）也被拒：确认后的 money 行整体不可变（§6.5）。
      await expectLater(
        lineRepo.upsert(
          confirmedLine.copyWith(
            status: domain.LineStatus.void_,
            meta: clock.meta(),
          ),
        ),
        throwsA(isA<domain.MoneyLineImmutableException>()),
      );

      // 仅刷新 §5.1 公共列（同步回写场景）放行。
      final metaOnly = confirmedLine.copyWith(meta: clock.meta());
      await lineRepo.upsert(metaOnly);
      final reread = (await lineRepo.findById(lineId))!;
      expect(reread.amount, 1850);
      expect(reread.meta.updatedAt, metaOnly.meta.updatedAt);

      // draft 事件下的 money 行不设防（§6.5：draft 时 AI 字段可被覆盖）。
      const draftEntryId = '0196a7e0-0000-7000-8000-00000000d103';
      await entryRepo.upsert(makeEntry(
        clock,
        id: draftEntryId,
        date: '2026-11-23',
        status: domain.EntryStatus.draft,
      ));
      final draftLine = makeLine(
        clock,
        id: '0196a7e0-0000-7000-8000-00000000d104',
        entryId: draftEntryId,
        type: domain.LineType.money,
        amount: 100,
        direction: domain.LineDirection.outcome,
        ledgerId: moneyLedger.id,
        currency: 'CNY',
      );
      await lineRepo.upsert(draftLine);
      await lineRepo.upsert(
        draftLine.copyWith(amount: 150, meta: clock.meta()),
      );
      expect((await lineRepo.findById(draftLine.id))!.amount, 150);

      // 父事件缺失 → 可读错误（FK 由库层兜底）。
      await expectLater(
        lineRepo.upsert(makeLine(
          clock,
          id: '0196a7e0-0000-7000-8000-00000000d105',
          entryId: 'ghost-entry',
          type: domain.LineType.money,
          amount: 100,
          direction: domain.LineDirection.outcome,
          ledgerId: moneyLedger.id,
        )),
        throwsStateError,
      );
    } finally {
      await database.close();
    }
  });
}
