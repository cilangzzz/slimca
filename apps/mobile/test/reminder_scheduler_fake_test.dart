// W13 本地通知调度测试（§11.2 W13 任务 3「ReminderScheduler 抽象 + Fake +
// 重复待办的提醒按展开实例调度」）。
//
// 覆盖（Fake 下记录调度调用，禁真实通知/平台通道）：
// 1. 规划纯函数（reminder_planner.dart）：
//    - 一次性待办 → 1 条（实例日=计划日；过期不补发）；
//    - 重复待办 FREQ=DAILY;COUNT=3 → 按展开实例逐条（同刻 HH:mm）；
//    - FREQ=WEEKLY;BYDAY=MO,WE → 每周双实例；
//    - 窗口上限（horizon）与单待办实例数防御；
//    - 通知 id 稳定派生（同 (todo, 实例日) 恒等）。
// 2. 对账协调器（ReminderSyncCoordinator + FakeReminderScheduler + 内存库）：
//    - 启动期一次性权限请求；
//    - 建档（带 remind_at）→ schedule 调用记录；软删 → cancel；
//    - 重复待办 → 实例数条 schedule（每实例一条）。
//
// 内存 Drift 库（禁真实 IO/网络）；宿主缺 sqlite3 运行库时温和跳过
// （widget_test 同口径）。now 一律注入或以「now+N 天」构造，跨宿主稳定。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/notifications/fake_reminder_scheduler.dart';
import 'package:slimca/notifications/reminder_planner.dart';
import 'package:slimca/notifications/reminder_scheduler.dart';
import 'package:slimca/notifications/reminder_sync.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（widget_test 同口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
Future<db.AppDatabase?> _tryOpenMemoryDatabase() async {
  final database = db.AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    if (_isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 轮询直到条件满足（drift watch 流重发是真实异步——plain test 无 fake clock）。
Future<void> _pollUntil(
  bool Function() condition, {
  int tries = 200,
}) async {
  for (var i = 0; i < tries; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('轮询超时：条件未满足');
}

void main() {
  group('通知 id 派生（reminder_scheduler.dart）', () {
    test('同 (todoId, 实例日) 恒等、跨实例互异、非负 int', () {
      final a1 = notificationIdFor('todo-1', '2026-12-01');
      final a2 = notificationIdFor('todo-1', '2026-12-01');
      final a3 = notificationIdFor('todo-1', '2026-12-02');
      final b = notificationIdFor('todo-2', '2026-12-01');
      final none = notificationIdFor('todo-1', null);
      expect(a1, a2, reason: '稳定派生（取消对账键，跨重启可复现）');
      expect(a1, isNot(a3), reason: '实例日变化即换 id（改期自动重排）');
      expect(a1, isNot(b));
      expect(a1, isNot(none));
      expect(a1 >= 0, isTrue, reason: '通知 id 非负');
    });
  });

  group('提醒规划（§11.2 W13 任务 3「按展开实例调度」）', () {
    final now = DateTime(2026, 11, 17, 9, 0);
    db.AppDatabase? database;
    db.TodoDao? dao;

    setUp(() async {
      database = await _tryOpenMemoryDatabase();
      if (database != null) {
        dao = db.TodoDao(database!);
      }
    });

    tearDown(() async {
      await database?.close();
      database = null;
      dao = null;
    });

    /// 规划结果快捷断言。
    Map<int, TodoReminder> planOf(List<db.Todo> todos, {DateTime? at}) =>
        planTodoReminders(todos: todos, now: at ?? now);

    test('一次性待办：未过期 1 条（实例日=计划日），过期不补发', () async {
      final openedDb = database;
      final todoDao = dao;
      if (openedDb == null || todoDao == null) {
        return; // Windows 宿主缺 sqlite3.dll：跳过（集成机有库）。
      }
      final tomorrow8 = DateTime(now.year, now.month, now.day + 1, 8, 0);
      final date = formatCalendarDay(DateTime(now.year, now.month, now.day));
      final created = await todoDao.create(
        title: '交作业',
        date: date,
        remindAt: tomorrow8.millisecondsSinceEpoch,
      );
      final rows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(created.id)))
          .get();

      final plan = planOf(rows);
      expect(plan.length, 1, reason: '一次性待办恰好一条提醒');
      final reminder = plan.values.single;
      expect(reminder.todoId, created.id);
      expect(reminder.title, '交作业');
      expect(reminder.instanceDate, date);
      expect(reminder.remindAtMs, tomorrow8.millisecondsSinceEpoch);

      // 过期时刻（昨天 08:00）：不补发。
      final yesterday8 = DateTime(now.year, now.month, now.day - 1, 8, 0);
      final past = await todoDao.create(
        title: '过期项',
        date: date,
        remindAt: yesterday8.millisecondsSinceEpoch,
      );
      final pastRows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(past.id)))
          .get();
      expect(planOf(pastRows), isEmpty, reason: '过期提醒不补发');
    });

    test('重复待办 FREQ=DAILY;COUNT=3：按展开实例 3 条、同刻 HH:mm', () async {
      final openedDb = database;
      final todoDao = dao;
      if (openedDb == null || todoDao == null) return;
      final anchor = DateTime(now.year, now.month, now.day + 2);
      final anchorText = formatCalendarDay(anchor);
      final remind8 =
          DateTime(anchor.year, anchor.month, anchor.day, 8, 0)
              .millisecondsSinceEpoch;
      final created = await todoDao.create(
        title: '每日拉伸',
        date: anchorText,
        repeatRule: 'FREQ=DAILY;COUNT=3',
        remindAt: remind8,
      );
      final rows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(created.id)))
          .get();

      final plan = planOf(rows);
      expect(plan.length, 3, reason: 'COUNT=3 → 三个展开实例各一条');
      // 每实例 08:00（实例日 + remind_at 的本地时刻）；锚点在未来→全保留。
      final dates = plan.values
          .map((r) => r.instanceDate ?? '')
          .toSet();
      expect(dates.length, 3, reason: '三个不同实例日');
      for (final reminder in plan.values) {
        final at = DateTime.fromMillisecondsSinceEpoch(reminder.remindAtMs);
        expect(at.hour, 8, reason: '实例提醒时刻=remind_at 的本地 HH:mm');
        expect(at.minute, 0);
      }
      // 过期实例不补发：now 推到锚点当日 09:00 → 锚点 08:00 已过，
      // 剩后两实例（COUNT 语义仍自锚点计满 3，窗口过滤只留未来）。
      final later = DateTime(anchor.year, anchor.month, anchor.day, 9, 0);
      expect(planOf(rows, at: later).length, 2,
          reason: '锚点日 08:00 已过 → 过滤，剩后两实例');
    });

    test('重复待办 FREQ=WEEKLY;BYDAY=MO,WE：每周双实例', () async {
      final openedDb = database;
      final todoDao = dao;
      if (openedDb == null || todoDao == null) return;
      // 2026-12-07 是周一。
      final created = await todoDao.create(
        title: '跑步',
        date: '2026-12-07',
        repeatRule: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=5',
        remindAt: DateTime(2026, 12, 7, 7, 30).millisecondsSinceEpoch,
      );
      final rows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(created.id)))
          .get();

      final plan = planTodoReminders(
        todos: rows,
        now: DateTime(2026, 12, 1),
      );
      expect(plan.length, 5, reason: 'COUNT=5：Mo/We 双实例 × 2.5 周');
      final dates = plan.values
          .map((r) => r.instanceDate ?? '')
          .toList()
        ..sort();
      expect(dates, [
        '2026-12-07',
        '2026-12-09',
        '2026-12-14',
        '2026-12-16',
        '2026-12-21',
      ], reason: 'BYDAY=MO,WE 每周一双周三一');
    });

    test('无锚点重复待办（收集箱未显式锚点）与无提醒时刻：不规划', () async {
      final openedDb = database;
      final todoDao = dao;
      if (openedDb == null || todoDao == null) return;
      final inboxRecurring = await todoDao.create(
        title: '收集箱重复（缺锚点）',
        repeatRule: 'FREQ=DAILY;COUNT=3',
        // date=null 且未给 rruleAnchorDate → 锚点 NULL（§5.5⑩ 口径）。
      );
      final inboxRows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(inboxRecurring.id)))
          .get();
      expect(planOf(inboxRows), isEmpty, reason: '无锚点降级为不展开（§6.1）');

      final noReminder = await todoDao.create(
          title: '只有重复无提醒时刻',
          date: formatCalendarDay(
              DateTime(now.year, now.month, now.day + 2)),
          repeatRule: 'FREQ=DAILY;COUNT=3');
      final noReminderRows = await (openedDb.select(openedDb.todos)
            ..where((t) => t.id.equals(noReminder.id)))
          .get();
      expect(planOf(noReminderRows), isEmpty, reason: 'remind_at 空 → 无提醒');
    });
  });

  group('对账协调器（ReminderSyncCoordinator + Fake 调度记录）', () {
    db.AppDatabase? database;
    db.TodoDao? dao;
    FakeReminderScheduler? fake;
    ReminderSyncCoordinator? coordinator;

    setUp(() async {
      final opened = await _tryOpenMemoryDatabase();
      if (opened == null) {
        return; // Windows 宿主缺 sqlite3.dll：跳过（集成机有库）。
      }
      database = opened;
      dao = db.TodoDao(opened);
      fake = FakeReminderScheduler();
      coordinator = ReminderSyncCoordinator(db: opened, scheduler: fake!);
    });

    tearDown(() async {
      await coordinator?.stop();
      await database?.close();
      database = null;
      dao = null;
      fake = null;
      coordinator = null;
    });

    test('启动期一次性权限请求；建档带提醒 → schedule 一条；软删 → cancel', () async {
      final todoDao = dao;
      final scheduler = fake;
      final sync = coordinator;
      if (todoDao == null || scheduler == null || sync == null) {
        return; // 内存库不可用：跳过（集成机有 sqlite3）。
      }
      await sync.start();
      expect(scheduler.ensurePermissionCallCount, 1,
          reason: '启动期一次性 POST_NOTIFICATIONS 运行时请求（§11.2 任务 3）');
      // 重复 start 幂等。
      await sync.start();
      expect(scheduler.ensurePermissionCallCount, 1);

      final tomorrow8 = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day + 1,
        8,
        0,
      );
      final created = await todoDao.create(
        title: '带提醒的一次性待办',
        date: formatCalendarDay(DateTime.now()),
        remindAt: tomorrow8.millisecondsSinceEpoch,
      );
      await _pollUntil(() => scheduler.scheduled.length == 1);
      final reminder = scheduler.scheduled.single;
      expect(reminder.todoId, created.id);
      expect(reminder.title, '带提醒的一次性待办');
      expect(reminder.remindAtMs, tomorrow8.millisecondsSinceEpoch);
      expect(reminder.id,
          notificationIdFor(created.id, reminder.instanceDate));

      // 软删墓碑（§5.1）→ 流重发 → 对账取消该 id。
      await todoDao.softDelete(created.id);
      await _pollUntil(() => scheduler.cancelled.contains(reminder.id));
      expect(scheduler.activeById, isEmpty, reason: '取消后无存活通知');
    });

    test('重复待办：按展开实例逐条调度（每实例一条调用）', () async {
      final todoDao = dao;
      final scheduler = fake;
      final sync = coordinator;
      if (todoDao == null || scheduler == null || sync == null) return;
      await sync.start();
      final today = DateTime.now();
      final anchor = DateTime(today.year, today.month, today.day + 2);
      final created = await todoDao.create(
        title: '连续记账三天',
        date: formatCalendarDay(anchor),
        repeatRule: 'FREQ=DAILY;COUNT=3',
        remindAt: DateTime(anchor.year, anchor.month, anchor.day, 8, 0)
            .millisecondsSinceEpoch,
      );
      await _pollUntil(() => scheduler.activeById.length == 3);
      expect(
        scheduler.scheduled.length,
        3,
        reason: '重复待办按展开实例调度：每实例一条 schedule 调用',
      );
      final instanceDates = scheduler.activeInstanceDatesOf(created.id);
      expect(instanceDates.length, 3, reason: '三个展开实例日');
      for (final reminder in scheduler.scheduled) {
        expect(reminder.todoId, created.id);
      }
    });

    test('改期（实例日变化）→ 旧 id 取消、新 id 调度', () async {
      final todoDao = dao;
      final scheduler = fake;
      final sync = coordinator;
      if (todoDao == null || scheduler == null || sync == null) return;
      await sync.start();
      final today = DateTime.now();
      final day1 = DateTime(today.year, today.month, today.day + 1, 8, 0);
      final day3 = DateTime(today.year, today.month, today.day + 3, 8, 0);
      final created = await todoDao.create(
        title: '改期待办',
        date: formatCalendarDay(DateTime(today.year, today.month, today.day + 1)),
        remindAt: day1.millisecondsSinceEpoch,
      );
      await _pollUntil(() => scheduler.activeById.length == 1);
      final oldId = scheduler.scheduled.single.id;

      // 改计划日到 +3 天（一次性实例日=计划日 → id 变化触发重排）。
      await todoDao.updateDetails(
        id: created.id,
        date: formatCalendarDay(DateTime(today.year, today.month, today.day + 3)),
        remindAt: day3.millisecondsSinceEpoch,
      );
      await _pollUntil(() => scheduler.cancelled.contains(oldId));
      await sync.settleForTest();
      final active = scheduler.activeById.values.toList();
      expect(active.length, 1, reason: '改期后仍恰好一条');
      expect(active.single.remindAtMs, day3.millisecondsSinceEpoch);
      expect(active.single.id, isNot(oldId), reason: '实例日变化 → 新 id');
    });
  });
}
