/// SavingsGoalsDao / SavingsContributionsDao 测试（§5.5⑪⑫、§3.6 存钱目标、
/// §11.2 W13 主线「存钱目标（留存钩子）」）。
///
/// 覆盖：
/// 1. 目标 create/updateDetails（哨兵语义）/softDelete（归档=软删墓碑、
///    重复归档幂等）→ sync_outbox 行快照同事务入队、payload 回放一致、
///    墓碑以 delete 语义出网（§6.2/§5.6⑯）；
/// 2. 贡献 append append-only + 幂等（按 goal+date+source，首写胜；来源
///    不同各占一行互不挤占）+ outbox 覆盖 + 按目标求和（排除墓碑）+
///    目标校验失败事务回滚（§6.1/§6.2）；
/// 3. DAO 写路径投影联动（§5.6⑬ W13）：建档/追加即时写入当日
///    savings_progress 快照、其后日期标 dirty、归档清零 + 自愈。
///
/// 测试纪律：无网络、无真实通知；宿主缺 sqlite3 运行库时温和跳过（同既有
/// 策略）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  /// 读 sync_outbox 全部行（测试内无 ack 路径，即全部 pending）。
  Future<List<SyncOutboxItem>> outboxRows(AppDatabase db) =>
      db.select(db.syncOutbox).get();

  /// 读业务表原始行快照（与 §5.6⑯ payload 同构的 snake_case 平铺）。
  Future<Map<String, Object?>?> rawRow(
    AppDatabase db,
    String table,
    String rowId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable.withString(rowId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// 回放一致性断言：payload JSON 解码后与业务表原始行逐键一致。
  Future<void> expectPayloadEqualsRow(
    AppDatabase db,
    SyncOutboxItem outboxRow,
  ) async {
    final payload = jsonDecode(outboxRow.payload) as Map<String, Object?>;
    final row = await rawRow(db, outboxRow.targetTable, outboxRow.rowId);
    expect(row, isNotNull, reason: '出网行必须指向已落库的业务行（§6.2）');
    expect(
      payload,
      equals(row),
      reason: '${outboxRow.targetTable}/${outboxRow.rowId} '
          'payload 必须与落库行同源（§6.2 行快照回放一致性）',
    );
  }

  test('目标 CRUD：create/updateDetails 哨兵/归档幂等；outbox 同事务、回放一致',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，SavingsGoalsDao 测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言本次写路径。
      final dao = SavingsGoalsDao(db);

      // create：§5.5⑪ 全字段落行 + 1 条 upsert 出网行。
      final goal = await dao.create(
        name: '买镜头',
        targetMinor: 600000,
        method: kSavingsMethodDaily365,
        rhythm: '{"type":"daily365","step_cents":365}',
        deadline: '2027-01-25',
        startedOn: '2026-02-08',
        id: 'goal-1',
      );
      expect(goal.name, '买镜头');
      expect(goal.targetMinor, 600000);
      expect(goal.method, kSavingsMethodDaily365);
      expect(goal.status, kSavingsGoalStatusActive);
      expect(goal.startedOn, '2026-02-08');
      expect(goal.deadline, '2027-01-25');
      expect(goal.revision, 1);
      expect(goal.deletedAt, isNull);
      expect(goal.hlc, isNotEmpty, reason: '§5.1 公共列齐备');

      var rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'create → 1 条出网行（§6.2）');
      expect(rows.single.targetTable, 'savings_goals');
      expect(rows.single.rowId, 'goal-1');
      expect(rows.single.op, 'upsert');
      await expectPayloadEqualsRow(db, rows.single);
      var payload =
          jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['method'], 'daily365');
      expect(payload['rhythm'], '{"type":"daily365","step_cents":365}');
      expect(payload['started_on'], '2026-02-08');
      expect(payload['target_minor'], 600000);
      expect(payload['deleted_at'], isNull, reason: '存活行 upsert 出网');

      // updateDetails：哨兵语义——只动目标金额与状态，其余字段不动。
      await dao.updateDetails(
        id: 'goal-1',
        targetMinor: 660000,
        status: kSavingsGoalStatusCompleted,
      );
      var row = (await dao.findById('goal-1'))!;
      expect(row.targetMinor, 660000);
      expect(row.status, kSavingsGoalStatusCompleted);
      expect(row.name, '买镜头', reason: '哨兵字段不动');
      expect(row.deadline, '2027-01-25', reason: '哨兵字段不动');
      expect(row.revision, 2);
      rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'pending 出网行收敛到最新快照');
      expect(rows.single.baseRevision, 2);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['status'], 'completed');
      expect(payload['target_minor'], 660000);

      // 显式置空截止日（null 与哨兵区分）。
      await dao.updateDetails(id: 'goal-1', deadline: null);
      expect((await dao.findById('goal-1'))!.deadline, isNull);

      // 归档（软删墓碑）→ delete 语义出网（§5.6⑯/§6.5）。
      await dao.softDelete('goal-1');
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      expect(rows.single.op, 'delete', reason: '墓碑行以 delete 语义出网');
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      final tombstoneAt = payload['deleted_at'];
      expect(tombstoneAt, isNotNull);

      // 重复归档幂等：保留首次墓碑时刻（与 TodoDao.softDelete 同口径）。
      await dao.softDelete('goal-1');
      final again = (await dao.findById('goal-1'))!;
      expect(again.deletedAt, tombstoneAt, reason: '不覆盖首次墓碑时刻');

      // 无此行 → StateError。
      await expectLater(
        dao.updateDetails(id: 'ghost-goal', name: 'x'),
        throwsStateError,
      );
      await expectLater(dao.softDelete('ghost-goal'), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('贡献追加：幂等按 goal+date+source（首写胜）、来源互不挤占、outbox '
      '同事务、求和排除墓碑、目标校验失败回滚', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，SavingsContributionsDao 测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db);
      final goals = SavingsGoalsDao(db);
      final dao = SavingsContributionsDao(db);
      await goals.create(
        name: '旅行基金',
        targetMinor: 100000,
        method: kSavingsMethodCustom,
        rhythm: '{"daily_cents":2000}',
        startedOn: '2026-02-08',
        id: 'goal-2',
      );

      // 首次人工投币：落行 + 出网（快照回放一致、source 落列、slot/note 原样）。
      final first = await dao.append(
        goalId: 'goal-2',
        amountMinor: 2000,
        date: '2026-02-08',
        slot: 1,
        note: '第 1 格',
        id: 'contrib-1',
      );
      expect(first.source, kSavingsSourceManual, reason: '缺省人工投币');
      expect(first.amountMinor, 2000);
      expect(first.slot, 1);
      expect(first.note, '第 1 格');
      expect(first.revision, 1);
      var rows = await outboxRows(db);
      var contribOutbox = rows
          .where((r) => r.targetTable == 'savings_contributions')
          .toList();
      expect(contribOutbox, hasLength(1), reason: '目标 1 条 + 贡献 1 条');
      expect(contribOutbox.single.rowId, 'contrib-1');
      expect(contribOutbox.single.op, 'upsert');
      await expectPayloadEqualsRow(db, contribOutbox.single);
      var payload =
          jsonDecode(contribOutbox.single.payload) as Map<String, Object?>;
      expect(payload['goal_id'], 'goal-2');
      expect(payload['date'], '2026-02-08');
      expect(payload['amount_minor'], 2000);
      expect(payload['slot'], 1);
      expect(payload['source'], 'manual');

      // 幂等命中：同 (goal,date,source) 重复追加 → 返回既有行（首写胜），
      // 不落新行、不入新出网项、不推版本（§6.2 只对真实写入入队）。
      final replay = await dao.append(
        goalId: 'goal-2',
        amountMinor: 9999,
        date: '2026-02-08',
        id: 'contrib-dup',
      );
      expect(replay.id, first.id);
      expect(replay.amountMinor, 2000, reason: '首写胜：后传金额不覆盖');
      expect(await dao.sumByGoal('goal-2'), 2000);
      contribOutbox = (await outboxRows(db))
          .where((r) => r.targetTable == 'savings_contributions')
          .toList();
      expect(contribOutbox, hasLength(1), reason: '幂等命中不入队');
      expect(contribOutbox.single.baseRevision, 1, reason: 'no-op 不推版本');

      // 来源不同互不挤占：同日 todo 联动另起一行（§3.6 待办联动打卡）。
      final todoCoin = await dao.append(
        goalId: 'goal-2',
        amountMinor: 5000,
        date: '2026-02-08',
        source: kSavingsSourceTodo,
        id: 'contrib-2',
      );
      expect(todoCoin.id, isNot(first.id));
      expect(todoCoin.source, kSavingsSourceTodo);
      // 不同日期人工再投一行。
      await dao.append(
        goalId: 'goal-2',
        amountMinor: 3000,
        date: '2026-02-09',
        id: 'contrib-3',
      );
      expect(await dao.sumByGoal('goal-2'), 10000);
      expect(await dao.watchSumByGoal('goal-2').first, 10000,
          reason: '响应式求和（§10.1 reactive stream）');

      // 幂等探针：按 (goal,date,source) 查存活行。
      expect(
          (await dao.findEffective(goalId: 'goal-2', date: '2026-02-08'))!.id,
          first.id);
      expect(
          (await dao.findEffective(
                  goalId: 'goal-2',
                  date: '2026-02-08',
                  source: kSavingsSourceTodo))
              !.id,
          'contrib-2');

      // 远端墓碑（模拟同步 pull 落库）：求和排除墓碑行、探针不命中。
      await (db.update(db.savingsContributions)
            ..where((t) => t.id.equals('contrib-3')))
          .write(const SavingsContributionsCompanion(
              deletedAt: Value(1764000000000)));
      expect(await dao.sumByGoal('goal-2'), 7000,
          reason: '墓碑贡献不计入进度（§5.1 删除行）');
      expect(
          await dao.findEffective(goalId: 'goal-2', date: '2026-02-09'), isNull);

      // 时间线：append-only 无改删方法；watchByGoal 含墓碑行（上层自行过滤）。
      final timeline = await dao.watchByGoal('goal-2').first;
      expect(timeline.map((c) => c.id).toList(),
          ['contrib-1', 'contrib-2', 'contrib-3'],
          reason: '打卡日升序、同日按创建序');
      expect(timeline.where((c) => c.id == 'contrib-3').single.deletedAt,
          isNotNull);

      // 目标校验：无此行/已归档 → StateError（事务整体回滚，无半途行）。
      await expectLater(
        dao.append(goalId: 'ghost-goal', amountMinor: 100, date: '2026-02-08'),
        throwsStateError,
      );
      await goals.softDelete('goal-2');
      await expectLater(
        dao.append(goalId: 'goal-2', amountMinor: 100, date: '2026-02-10'),
        throwsStateError,
      );
      expect(await dao.sumByGoal('goal-2'), 7000,
          reason: '失败追加随事务回滚，无半途贡献行');
    } finally {
      await db.close();
    }
  });

  test('DAO 写路径投影联动：建档/追加即时写入当日 savings_progress、其后日期 '
      '标 dirty 自愈、归档清零（§5.6⑬）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，存钱投影联动测试未执行');
      return;
    }
    try {
      final projection = DaySummaryProjection(db);
      final goals = SavingsGoalsDao(db, projection: projection);
      final dao = SavingsContributionsDao(db, projection: projection);

      Future<DaySummary?> summaryOf(String date) =>
          (db.select(db.daySummaries)..where((t) => t.date.equals(date)))
              .getSingleOrNull();

      // 建档（startedOn 缺省=设备本地当日）：建档日与当日立即重算——当日
      // 快照从 NULL 变有值（dirty 标记只扫非空行，覆盖不到首目标的 NULL
      // 空态，§3.2 快照直出）。
      await goals.create(
        name: '买镜头',
        targetMinor: 10000,
        method: kSavingsMethodCustom,
        rhythm: '{"daily_cents":500}',
        id: 'goal-p1',
      );
      final today = dom.formatCalendarDay(DateTime.now());
      final todaySummary = await summaryOf(today);
      expect(todaySummary, isNotNull, reason: '建档当日即时重算（§3.2 快照直出）');
      final parsedToday = parseSavingsProgress(todaySummary!.savingsProgress!);
      expect(parsedToday['goal-p1']?.targetMinor, 10000);
      expect(parsedToday['goal-p1']?.contributedMinor, 0);

      // 未来起始的目标：当日快照仍为 NULL（未生效，正确空态）。
      await goals.create(
        name: '明年的年货',
        targetMinor: 3000,
        method: kSavingsMethodCustom,
        rhythm: '{"daily_cents":300}',
        startedOn: '2027-01-01',
        id: 'goal-future',
      );
      final parsedFuture =
          parseSavingsProgress((await summaryOf(today))!.savingsProgress!);
      expect(parsedFuture.containsKey('goal-future'), isFalse,
          reason: 'started_on > 当日：目标未生效，不进当日快照');

      // 追加贡献：贡献日即时重算、dirty 复位。
      await dao.append(
        goalId: 'goal-p1',
        amountMinor: 2500,
        date: '2026-12-01',
        id: 'contrib-p1',
      );
      final day1 = await summaryOf('2026-12-01');
      expect(
        parseSavingsProgress(day1!.savingsProgress!)['goal-p1']
            ?.contributedMinor,
        2500,
      );
      expect(day1.dirty, isFalse, reason: '贡献日重算后 dirty 复位');

      // 预建更晚日期快照行（12-05），随后 12-03 追加贡献：累计口径下 12-05
      // 的快照已过期 → 标 dirty 交后台自愈（§5.6 重建规则）。
      final stale = await projection.recomputeDaySummary('2026-12-05');
      expect(
        parseSavingsProgress(stale.savingsProgress!)['goal-p1']
            ?.contributedMinor,
        2500,
      );
      await dao.append(
        goalId: 'goal-p1',
        amountMinor: 1000,
        date: '2026-12-03',
        id: 'contrib-p2',
      );
      final healed = await summaryOf('2026-12-05');
      expect(healed!.dirty, isTrue, reason: '其后日期快照标 dirty');
      expect(
        parseSavingsProgress(healed.savingsProgress!)['goal-p1']
            ?.contributedMinor,
        2500,
        reason: 'dirty 行保持旧值，等待后台重算',
      );
      await projection.recomputeDirtyDays();
      final healedNow = await summaryOf('2026-12-05');
      expect(healedNow!.dirty, isFalse);
      expect(
        parseSavingsProgress(healedNow.savingsProgress!)['goal-p1']
            ?.contributedMinor,
        3500,
        reason: '自愈吸收 12-03 贡献（累计口径）',
      );
      // 12-01 快照不受晚于它的贡献影响（累计口径单向推进）。
      expect(
        parseSavingsProgress(
            (await summaryOf('2026-12-01'))!.savingsProgress!)['goal-p1']
            ?.contributedMinor,
        2500,
      );

      // 归档：当日即时清零（无有效目标 → NULL）；其余日期标 dirty 后台
      // 自愈清零。
      await goals.softDelete('goal-p1');
      final zeroedToday = await summaryOf(today);
      expect(zeroedToday!.savingsProgress, isNull,
          reason: '归档后当日快照清 NULL（§5.6⑬ 空态）');
      final staleArchived = await summaryOf('2026-12-01');
      expect(staleArchived!.dirty, isTrue, reason: '其余进度行标 dirty');
      expect(
        parseSavingsProgress(staleArchived.savingsProgress!)['goal-p1'],
        isNotNull,
        reason: 'dirty 行保持旧值等待自愈',
      );
      await projection.recomputeDirtyDays();
      expect((await summaryOf('2026-12-01'))!.savingsProgress, isNull,
          reason: '自愈后清零');
      expect((await summaryOf('2026-12-05'))!.savingsProgress, isNull,
          reason: '自愈后清零');
    } finally {
      await db.close();
    }
  });
}
