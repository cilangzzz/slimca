/// 组间计时器「锁屏可跑」底座之二：通知常驻计时（W14 任务 2「通知常驻计时
/// （复用 W13 flutter_local_notifications 适配器）」）。
///
/// 分层同 W13（§10.4 壳层装配）：抽象只在本文件；生产实现
/// `FlutterLocalWorkoutTimerNotifier`（flutter_local_workout_timer_notifier
/// .dart——与 W13 FlutterLocalReminderScheduler 同一插件、同款惰性初始化与
/// 渠道模式，独立渠道 workout_timer）；测试实现 `FakeWorkoutTimerNotifier`
/// （fake_workout_timer_notifier.dart，记录 show/cancel 调用序列）。
///
/// 「计时」口径（骨架诚实边界）：休息倒计时的**展示**交给 Android 原生
/// Chronometer（`chronometerEndsAtMs` 非空 → usesChronometer +
/// chronometerCountDown，API 24+）——倒计时由系统 UI 驱动，进程被冻结/锁屏
/// 仍走秒（「锁屏可跑」的展示半边）；剩余秒的**业务判定**不在通知侧，而在
/// 训练控制器以绝对时刻（rest_ends_at = now + rest_s，注入时钟）计算——
/// 测试禁真实计时器（W14 任务 5），状态推进只由注入时钟驱动。remaining：
/// 前台服务（进程冻结下的后台落库/联动）随真机表现于 W15+ 评估。
library;

/// 训练常驻通知的固定 id：整个训练生命周期复用同一条（upsert 更新文本），
/// 结束/放弃时 cancel。取 W14 专用常量段，与 W13 待办提醒的 FNV 派生 id
/// （reminder_scheduler.dart notificationIdFor）天然不相撞。
const int kWorkoutTimerNotificationId = 0x5714;

/// Android 通知渠道 id（独立于 W13 todo_reminders）。
const String kWorkoutTimerChannelId = 'workout_timer';

/// Android 通知渠道名（系统设置里展示）。
const String kWorkoutTimerChannelName = '健身训练计时';

/// Android 通知渠道描述。
const String kWorkoutTimerChannelDescription =
    '训练进行中与组间休息的常驻计时（Slimca 健身计划）';

/// 一条常驻计时通知请求（upsert 语义：同 id 覆盖文本与倒计时基点）。
class WorkoutTimerNotice {
  const WorkoutTimerNotice({
    required this.notificationId,
    required this.title,
    required this.body,
    this.ongoing = true,
    this.chronometerEndsAtMs,
  });

  /// 本地通知 id（本域恒为 [kWorkoutTimerNotificationId]）。
  final int notificationId;

  /// 通知标题（如「训练进行中」「组间休息」）。
  final String title;

  /// 通知正文（计划名/动作名/已完成组数——本地通知内容，不入遥测，§3.9）。
  final String body;

  /// 常驻：训练未结束不可下滑清除（适配器同时固定 autoCancel=false——
  /// 点击不清除，结束由控制器 cancel）。
  final bool ongoing;

  /// 非空 → 通知挂 Android 原生倒计时 Chronometer 至该绝对时刻
  /// （usesChronometer+chronometerCountDown，锁屏/冻结仍走秒）；null →
  /// 纯文本（无倒计时）。
  final int? chronometerEndsAtMs;

  @override
  bool operator ==(Object other) =>
      other is WorkoutTimerNotice &&
      other.notificationId == notificationId &&
      other.title == title &&
      other.body == body &&
      other.ongoing == ongoing &&
      other.chronometerEndsAtMs == chronometerEndsAtMs;

  @override
  int get hashCode => Object.hash(
        notificationId,
        title,
        body,
        ongoing,
        chronometerEndsAtMs,
      );

  @override
  String toString() =>
      'WorkoutTimerNotice(id: $notificationId, title: $title, '
      'ongoing: $ongoing, chronometerEndsAtMs: $chronometerEndsAtMs)';
}

/// 常驻计时通知抽象（W14 任务 2）。
///
/// 接口纪律（与 W13 ReminderScheduler 同款，§6.1）：实现不得向上抛异常——
/// 通知缺失不伤业务（组间计时在前台 UI 卡内照跑）。
abstract interface class WorkoutTimerNotifier {
  /// 展示/更新一条常驻通知（同 id upsert）。
  Future<void> show(WorkoutTimerNotice notice);

  /// 取消一条常驻通知（训练结束/放弃）。
  Future<void> cancel({required int notificationId});
}
