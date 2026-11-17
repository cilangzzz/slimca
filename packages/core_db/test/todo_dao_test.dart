/// TodoDao 基础 CRUD 测试（§5.5⑩ todos、§3.6 待办基础 P0、§11.1 W2）。
///
/// 覆盖：
/// 1. create + watchByDate/watchInbox 流（收集箱 date=NULL、未完成排前）；
/// 2. setDone 勾选/取消往返 +「只前进」no-op（§6.5 todo.done 行）；
/// 3. updateDetails 哨兵语义与改期、softDelete 墓碑（流排除、详情保留）；
/// 4. 投影联动：待办变更即时更新当日 todo_done/todo_total（§5.6 重建规则）；
/// 5. W13 重复/提醒字段（§11.2 W13、§5.5⑩）：repeat_rule/rrule_anchor_date
///    （锚点缺省=计划日）/remind_at 落列、三字段独立哨兵、outbox 快照携带
///    新字段（§6.2 行快照回放）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('create + watch：按日流/收集箱流可见性，未完成排前（§3.2 预览排序）',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，TodoDao 测试未执行');
      return;
    }
    try {
      final dao = TodoDao(db);
      const day = '2026-11-23';

      expect(await dao.watchByDate(day).first, isEmpty);
      expect(await dao.watchInbox().first, isEmpty);

      // 收集箱（date=NULL，§5.5⑩）。
      final inbox = await dao.create(title: '想到就记');
      expect(inbox.date, isNull);
      expect(inbox.doneAt, isNull);
      expect(inbox.revision, 1);
      expect(inbox.hlc, isNotEmpty, reason: '§5.1 公共列齐备');

      final first = await dao.create(title: '买菜', date: day);
      final second = await dao.create(
        title: '复盘',
        date: day,
        note: '晚间',
        dueAt: 1764000000000,
        goalLink: 'goal-1',
      );

      final inboxList = await dao.watchInbox().first;
      expect(inboxList.map((t) => t.id).toList(), [inbox.id],
          reason: '收集箱流只含 date IS NULL 行');

      final dayList = await dao.watchByDate(day).first;
      expect(dayList.map((t) => t.id).toList(), [first.id, second.id],
          reason: '全部未完成时按创建序');
      expect(second.note, '晚间');
      expect(second.dueAt, 1764000000000);
      expect(second.goalLink, 'goal-1');

      // 勾选先建的待办：未完成排前（done_at IS NULL DESC，§3.2 卡片墙）。
      await dao.setDone(first.id, done: true);
      final reordered = await dao.watchByDate(day).first;
      expect(reordered.map((t) => t.id).toList(), [second.id, first.id]);
    } finally {
      await db.close();
    }
  });

  test('setDone：勾选/取消往返；重复操作只前进不覆盖（§6.5 todo.done）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，TodoDao 测试未执行');
      return;
    }
    try {
      final dao = TodoDao(db);
      final todo = await dao.create(title: '健身 30 分钟', date: '2026-11-23');

      await dao.setDone(todo.id, done: true);
      final done1 = (await dao.findById(todo.id))!;
      expect(done1.doneAt, isNotNull);
      final revisionAfterDone = done1.revision;

      // 重复勾选：保留首次完成时刻（§6.5「完成事件只前进」本地投影）。
      await dao.setDone(todo.id, done: true);
      final done2 = (await dao.findById(todo.id))!;
      expect(done2.doneAt, done1.doneAt, reason: '§6.5：不覆盖首次完成时刻');
      expect(done2.revision, revisionAfterDone, reason: 'no-op 不再推版本');

      // 取消完成。
      await dao.setDone(todo.id, done: false);
      final undone = (await dao.findById(todo.id))!;
      expect(undone.doneAt, isNull);
      expect(undone.revision, greaterThan(revisionAfterDone));
      final revisionAfterUndo = undone.revision;

      // 未完成状态重复取消：no-op。
      await dao.setDone(todo.id, done: false);
      final again = (await dao.findById(todo.id))!;
      expect(again.doneAt, isNull);
      expect(again.revision, revisionAfterUndo);

      // 不存在的行 → StateError。
      await expectLater(
        dao.setDone('ghost-todo', done: true),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('updateDetails 哨兵/改期 + softDelete 墓碑（流排除、详情保留）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，TodoDao 测试未执行');
      return;
    }
    try {
      final dao = TodoDao(db);
      const day = '2026-11-23';
      final todo = await dao.create(title: '旧标题', date: day);

      // 只改标题（其余字段走哨兵，§5.5⑩）。
      await dao.updateDetails(id: todo.id, title: '新标题');
      var row = (await dao.findById(todo.id))!;
      expect(row.title, '新标题');
      expect(row.note, isNull);
      expect(row.date, day, reason: '哨兵字段不动');
      expect(row.revision, 2);

      // 显式传 null 表示置空（与哨兵区分）。
      final withNote = await dao.create(title: '带备注', date: day, note: '细节');
      await dao.updateDetails(id: withNote.id, note: null);
      row = (await dao.findById(withNote.id))!;
      expect(row.note, isNull);

      // 改期：旧日清空、新日出现（新旧两日投影联动，§5.6）。
      // 注意：旧日还留有上一步只置空 note 的「带备注」待办（date 未动），
      // 故旧日流应只剩它，而非空——被改期行不再可见。
      await dao.updateDetails(id: todo.id, date: '2026-11-24');
      final remainingOnOldDay = await dao.watchByDate(day).first;
      expect(remainingOnOldDay.map((t) => t.id).toList(), [withNote.id],
          reason: '改期后旧日只剩未移动的带备注待办');
      final moved = await dao.watchByDate('2026-11-24').first;
      expect(moved.map((t) => t.id).toList(), [todo.id]);

      // 软删墓碑（§5.1 删除行）：watch 排除、findById 保留。
      await dao.softDelete(todo.id);
      final tombstone = (await dao.findById(todo.id))!;
      expect(tombstone.deletedAt, isNotNull);
      expect((await dao.watchByDate('2026-11-24').first), isEmpty);

      // 重复软删幂等：deleted_at 保持首次墓碑值。
      await dao.softDelete(todo.id);
      final tombstone2 = (await dao.findById(todo.id))!;
      expect(tombstone2.deletedAt, tombstone.deletedAt);

      // 不存在的行 → StateError。
      await expectLater(
        dao.updateDetails(id: 'ghost-todo', title: 'x'),
        throwsStateError,
      );
      await expectLater(dao.softDelete('ghost-todo'), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('投影联动：create/setDone/softDelete 即时更新 todo_done/todo_total；'
      '收集箱不入日投影', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，TodoDao 测试未执行');
      return;
    }
    try {
      final projection = DaySummaryProjection(db);
      final dao = TodoDao(db, projection: projection);
      const day = '2026-12-05';

      Future<DaySummary> summaryOfDay() => (db.select(db.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingle();

      // 收集箱待办不产生任何日投影行（§5.5⑩ date NULL=收集箱）。
      final inbox = await dao.create(title: '无日期待办');
      expect(inbox.date, isNull);
      final inboxRow = await (db.select(db.daySummaries)
            ..where((t) => t.date.equals(day)))
          .getSingleOrNull();
      expect(inboxRow, isNull);

      // 新建 → todo_total 增。
      final a = await dao.create(title: '待办A', date: day);
      final b = await dao.create(title: '待办B', date: day);
      var summary = await summaryOfDay();
      expect(summary.todoTotal, 2);
      expect(summary.todoDone, 0);
      expect(summary.dirty, isFalse, reason: '联动重算后 dirty 复位（§5.6）');

      // 勾选 → todo_done 增。
      await dao.setDone(a.id, done: true);
      summary = await summaryOfDay();
      expect(summary.todoDone, 1);

      // 勾选后取消 → 计数回退。
      await dao.setDone(b.id, done: true);
      await dao.setDone(b.id, done: false);
      summary = await summaryOfDay();
      expect(summary.todoDone, 1, reason: '取消完成回退 todo_done');

      // 软删 → 移出计数（墓碑不计入，§5.1/§5.6）。
      await dao.softDelete(a.id);
      summary = await summaryOfDay();
      expect(summary.todoTotal, 1);
      expect(summary.todoDone, 0);

      // 收集箱待办勾选不触碰任何日投影。
      await dao.setDone(inbox.id, done: true);
      summary = await summaryOfDay();
      expect(summary.todoTotal, 1);
      expect(summary.todoDone, 0);
    } finally {
      await db.close();
    }
  });

  test('W13 重复字段：repeatRule/rruleAnchorDate 缺省=计划日、remindAt 落列、'
      '三字段独立哨兵、outbox 快照携带新字段（§5.5⑩/§6.2）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，TodoDao 重复字段测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言新字段的出网快照。
      final dao = TodoDao(db);

      // 有日期重复待办：锚点缺省=计划日（RFC5545 DTSTART 语义）。
      final daily = await dao.create(
        title: '喝 8 杯水',
        date: '2026-02-08',
        repeatRule: 'FREQ=DAILY;INTERVAL=1',
      );
      expect(daily.repeatRule, 'FREQ=DAILY;INTERVAL=1');
      expect(daily.rruleAnchorDate, '2026-02-08',
          reason: '锚点缺省=计划日（DTSTART 语义，§11.2 W13）');
      expect(daily.remindAt, isNull);

      // 显式锚点覆盖（系列起始早于首个实例）+ 提醒时刻。
      final weekly = await dao.create(
        title: '周复盘',
        date: '2026-02-09',
        repeatRule: 'FREQ=WEEKLY;BYDAY=MO',
        rruleAnchorDate: '2026-02-02',
        remindAt: 1770000000000,
      );
      expect(weekly.rruleAnchorDate, '2026-02-02');
      expect(weekly.remindAt, 1770000000000);

      // 收集箱重复待办：无日期且未显式给锚点 → anchor NULL（无展开起点）。
      final inboxRepeat = await dao.create(
        title: '想到就记的重复想法',
        repeatRule: 'FREQ=DAILY',
      );
      expect(inboxRepeat.date, isNull);
      expect(inboxRepeat.rruleAnchorDate, isNull);

      // updateDetails：三字段独立哨兵——清空 repeat_rule 不隐式清锚点
      // （series 语义调整由上层决定，§5.5⑩）。
      await dao.updateDetails(id: weekly.id, repeatRule: null);
      final cleared = (await dao.findById(weekly.id))!;
      expect(cleared.repeatRule, isNull);
      expect(cleared.rruleAnchorDate, '2026-02-02', reason: '锚点独立，不隐式清');
      expect(cleared.remindAt, 1770000000000);
      // 改计划日不隐式平移锚点。
      await dao.updateDetails(id: daily.id, date: '2026-02-10');
      final moved = (await dao.findById(daily.id))!;
      expect(moved.date, '2026-02-10');
      expect(moved.rruleAnchorDate, '2026-02-08',
          reason: '改期不平移锚点（展开口径由上层按 RFC5545 处理）');
      // 显式置空锚点与提醒。
      await dao.updateDetails(id: weekly.id, rruleAnchorDate: null, remindAt: null);
      final nulled = (await dao.findById(weekly.id))!;
      expect(nulled.rruleAnchorDate, isNull);
      expect(nulled.remindAt, isNull);

      // 出网快照携带新字段（§6.2 行快照回放一致性：RRULE+锚点随行出网，
      // 对端可重建同一切换语义）。
      final rows = await db.select(db.syncOutbox).get();
      final dailyOutbox =
          rows.where((r) => r.targetTable == 'todos' && r.rowId == daily.id);
      final payload =
          jsonDecode(dailyOutbox.single.payload) as Map<String, Object?>;
      expect(payload['repeat_rule'], 'FREQ=DAILY;INTERVAL=1');
      expect(payload['rrule_anchor_date'], '2026-02-08');
      expect(payload['remind_at'], isNull);
      // 改期后 todos 出网快照收敛为最新状态（baseRevision 推进）。
      expect(dailyOutbox.single.baseRevision, 2);
    } finally {
      await db.close();
    }
  });
}
