/// TodoDao 基础 CRUD 测试（§5.5⑩ todos、§3.6 待办基础 P0、§11.1 W2）。
///
/// 覆盖：
/// 1. create + watchByDate/watchInbox 流（收集箱 date=NULL、未完成排前）；
/// 2. setDone 勾选/取消往返 +「只前进」no-op（§6.5 todo.done 行）；
/// 3. updateDetails 哨兵语义与改期、softDelete 墓碑（流排除、详情保留）；
/// 4. 投影联动：待办变更即时更新当日 todo_done/todo_total（§5.6 重建规则）。
library;

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
}
