/// 待办提醒调度抽象（§11.2 W13 任务 3「本地通知」、§5.5⑩ remind_at）。
///
/// 分层（§10.4 壳层装配）：本文件只定义值对象与接口——
/// - 生产实现：[FlutterLocalReminderScheduler]（flutter_local_notifications
///   真实通道，Android 13+ POST_NOTIFICATIONS 运行时请求在适配器内接线，
///   真机验收 remaining）；
/// - 测试实现：`FakeReminderScheduler`（记录调度调用，禁真实通知/平台通道）。
///
/// 调度粒度：**重复待办按展开实例逐条调度**（§11.2 W13 任务 3）——RRULE
/// 实例展开见 `rrule_expand.dart`，实例→提醒请求见 `reminder_planner.dart`；
/// 每条请求以 (todo_id, 实例日) 派生稳定 int 通知 id（[notificationIdFor]），
/// 跨重启取消/重排可对账（`ReminderSyncCoordinator` 差异对账）。
library;

/// 待办提醒请求（§5.5⑩ remind_at 列的一次实例化）。
class TodoReminder {
  const TodoReminder({
    required this.id,
    required this.todoId,
    required this.title,
    required this.remindAtMs,
    this.instanceDate,
  });

  /// 本地通知 id（稳定派生：[notificationIdFor]，取消/重排对账键）。
  final int id;

  /// 归属待办 id（§5.5⑩ todos.id）。
  final String todoId;

  /// 通知正文（=待办标题；本地通知内容，不入遥测——§3.9 内容禁入）。
  final String title;

  /// 提醒时刻 UTC 毫秒（§5.5⑩ remind_at 口径）。
  final int remindAtMs;

  /// 展开实例日 `yyyy-MM-dd`（重复待办的 RRULE 实例；一次性待办=其计划日，
  /// 可为 null）。参与通知 id 派生——改期即换 id，对账自动重排。
  final String? instanceDate;

  @override
  bool operator ==(Object other) =>
      other is TodoReminder &&
      other.id == id &&
      other.todoId == todoId &&
      other.title == title &&
      other.remindAtMs == remindAtMs &&
      other.instanceDate == instanceDate;

  @override
  int get hashCode => Object.hash(id, todoId, title, remindAtMs, instanceDate);

  @override
  String toString() =>
      'TodoReminder(id: $id, todoId: $todoId, instanceDate: $instanceDate, '
      'remindAtMs: $remindAtMs)';
}

/// 待办提醒调度抽象（§11.2 W13 任务 3）。
///
/// 实现纪律（§6.1 原则 1 同款）：权限被拒不阻塞调度——调度本身在各平台
/// 均可成功，拒发的只是系统通知展示；调度器内部自行兜底、不向上抛异常。
abstract interface class ReminderScheduler {
  /// 确保通知权限就绪（Android 13+ POST_NOTIFICATIONS 运行时请求 / iOS
  /// alert+badge+sound 请求）。返回是否被授予；未授予仍可继续调度。
  Future<bool> ensurePermission();

  /// 调度一条本地通知（重复待办的每个展开实例各调一次，§11.2 任务 3）。
  /// 同 id 重复调度覆盖旧条目。
  Future<void> schedule(TodoReminder reminder);

  /// 取消一条本地通知（按稳定 id；待办删除/改期后对账调用）。
  Future<void> cancel({required int notificationId});
}

/// Android 通知渠道 id（§11.2 任务 3「真实通道」；适配器建渠道时使用）。
const String kTodoReminderChannelId = 'todo_reminders';

/// Android 通知渠道名（系统设置里展示）。
const String kTodoReminderChannelName = '待办提醒';

/// Android 通知渠道描述。
const String kTodoReminderChannelDescription = '待办的到点提醒（Slimca 计划）';

/// FNV-1a 32 位散列（稳定、无外部依赖）：通知 id 派生用。
///
/// 不用 `String.hashCode`——其值跨进程/平台不稳定，无法作为重启后取消
/// 对账的持久键（§11.2 任务 3「按展开实例调度」的重排语义依赖稳定性）。
int _fnv1a32(String input) {
  var hash = 0x811C9DC5;
  for (final code in input.codeUnits) {
    hash ^= code;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// (todo_id, 实例日) → 稳定正 int 通知 id。
///
/// 同一待办的不同实例（重复待办逐条调度，§11.2 任务 3）各自独立 id；
/// 实例日变化（改期/锚点平移）即换 id——对账时旧 id 被取消、新 id 被调度。
/// 取 31 位正数段（Android 通知 id 为 int，保持非负便于对账断言）。
int notificationIdFor(String todoId, String? instanceDate) {
  return _fnv1a32('$todoId|$instanceDate') & 0x7FFFFFFF;
}
