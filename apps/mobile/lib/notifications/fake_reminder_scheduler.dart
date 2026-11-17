/// ReminderScheduler 的测试桩（§11.2 W13 任务 3「Fake（测试）」、
/// 测试纪律「禁真实通知/平台通道」）。
///
/// 只记录调用序列，不触发任何通知：`scheduled`/`cancelled` 供测试断言
/// 「重复待办按展开实例调度」（每实例一条调用）与「删除后取消」等对账
/// 行为；`permissionGranted` 开关模拟 Android 13+ POST_NOTIFICATIONS 拒绝。
library;

import 'reminder_scheduler.dart';

/// 记录型调度器（测试装配：`reminderSchedulerProvider.overrideWithValue`）。
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.permissionGranted = true});

  /// ensurePermission 的返回值（模拟系统授权/拒绝）。
  bool permissionGranted;

  /// ensurePermission 调用计数（协调器启动期一次性请求的断言锚点）。
  int ensurePermissionCallCount = 0;

  /// 按调用序累积的调度请求（不覆盖重排——断言调用序列）。
  final List<TodoReminder> scheduled = [];

  /// 按调用序累积的取消 id。
  final List<int> cancelled = [];

  /// 当前「存活」视图（schedule 覆盖写、cancel 移除）——测试便捷断言。
  final Map<int, TodoReminder> activeById = <int, TodoReminder>{};

  @override
  Future<bool> ensurePermission() async {
    ensurePermissionCallCount++;
    return permissionGranted;
  }

  @override
  Future<void> schedule(TodoReminder reminder) async {
    scheduled.add(reminder);
    activeById[reminder.id] = reminder;
  }

  @override
  Future<void> cancel({required int notificationId}) async {
    cancelled.add(notificationId);
    activeById.remove(notificationId);
  }

  /// 某待办当前存活的实例日集合（断言「按展开实例调度」的形状）。
  Set<String?> activeInstanceDatesOf(String todoId) => activeById.values
      .where((r) => r.todoId == todoId)
      .map((r) => r.instanceDate)
      .toSet();

  /// 清空调用记录（用例间隔离）。
  void reset() {
    scheduled.clear();
    cancelled.clear();
    activeById.clear();
    ensurePermissionCallCount = 0;
  }
}
