/// 提醒规划（§11.2 W13 任务 3「重复待办的提醒按展开实例调度」）。
///
/// 纯函数：todos 快照 → 应调度的提醒请求集。调度语义：
/// - 一次性待办（repeat_rule 空）：remind_at 未过期 → 1 条，实例日=计划日；
/// - 重复待办（repeat_rule + 锚点）：RRULE 在「max(锚点, 今天) → 今天+horizon」
///   窗口内展开（`rrule_expand.dart`），每个实例日按 remind_at 的本地时刻
///   （HH:mm）生成一条提醒——「每天 08:00 提醒」= 每个实例日 08:00 各一条；
/// - 过期实例不补发（≤ now 过滤）；单待办实例数有防御上限（§6.1）。
///
/// 对账（`ReminderSyncCoordinator`）以通知 id 为键：实例日变化 → id 变化 →
/// 旧 id 取消、新 id 调度，无需逐字段 diff 待办行。
library;

import 'package:core_db/core_db.dart' show Todo;

import 'reminder_scheduler.dart';
import 'rrule_expand.dart';

/// 单待办最大展开实例数（重复待办调度窗口内的防御上限，§6.1）。
const int kMaxInstancesPerTodo = 32;

/// 调度窗口缺省跨度（重复待办向前滚动续排——协调器每次 todos 变更重算，
/// 30 天后临近的实例在下次变更时自然补上；窗口尾部断排是已知语义）。
const Duration kReminderHorizon = Duration(days: 30);

/// 由待办行集合规划提醒请求（key=通知 id）。
///
/// - [now]：判定「未过期」的基准时刻（调用方注入，测试可 fake）；
/// - [horizon]：重复实例展开窗口跨度（缺省 [kReminderHorizon]）。
Map<int, TodoReminder> planTodoReminders({
  required List<Todo> todos,
  required DateTime now,
  Duration horizon = kReminderHorizon,
}) {
  final plan = <int, TodoReminder>{};
  for (final todo in todos) {
    // 墓碑/无提醒时刻：不参与（§5.1 删除行、§5.5⑩ remind_at）。
    if (todo.deletedAt != null || todo.remindAt == null) continue;
    final remindAt = todo.remindAt!;
    final reminderTime = DateTime.fromMillisecondsSinceEpoch(remindAt);

    final isRecurring =
        todo.repeatRule != null && todo.repeatRule!.trim().isNotEmpty;
    if (!isRecurring) {
      // 一次性：过期不补发；实例日=计划日（id 稳定键）。
      if (remindAt <= now.millisecondsSinceEpoch) continue;
      final id = notificationIdFor(todo.id, todo.date);
      plan[id] = TodoReminder(
        id: id,
        todoId: todo.id,
        title: todo.title,
        remindAtMs: remindAt,
        instanceDate: todo.date,
      );
      continue;
    }

    // 重复待办：锚点=rrule_anchor_date（TodoDao create 缺省回填计划日；
    // 收集箱重复待办需显式锚点，缺锚点降级为不展开——§6.1）。
    final anchorText = todo.rruleAnchorDate ?? todo.date;
    if (anchorText == null) continue;
    final anchor = _parseDay(anchorText);
    if (anchor == null) continue;

    // 展开窗口：max(锚点, 今天) → 今天+horizon（历史实例不补发）。
    final today = DateTime(now.year, now.month, now.day);
    final windowStart =
        anchor.isBefore(today) ? today : anchor;
    final windowEnd = today.add(horizon);
    final instances = expandRruleInstances(
      rrule: todo.repeatRule!,
      anchor: anchor,
      rangeStart: windowStart,
      rangeEnd: windowEnd,
      maxInstances: kMaxInstancesPerTodo,
    );
    for (final day in instances) {
      // 实例提醒时刻 = 实例日 + remind_at 的本地时刻（HH:mm）。
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        reminderTime.hour,
        reminderTime.minute,
      );
      final atMs = at.millisecondsSinceEpoch;
      if (atMs <= now.millisecondsSinceEpoch) continue; // 过期实例不补发。
      final dateText =
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      final id = notificationIdFor(todo.id, dateText);
      plan[id] = TodoReminder(
        id: id,
        todoId: todo.id,
        title: todo.title,
        remindAtMs: atMs,
        instanceDate: dateText,
      );
    }
  }
  return plan;
}

/// `yyyy-MM-dd` → 当日 00:00 本地时间；非法输入返回 null（自愈降级，§6.1）。
DateTime? _parseDay(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}
