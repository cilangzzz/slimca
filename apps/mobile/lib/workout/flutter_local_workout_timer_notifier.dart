/// flutter_local_notifications 适配器（W14 任务 2「复用 W13
/// flutter_local_notifications 适配器」）。
///
/// 复用口径：与 W13 FlutterLocalReminderScheduler（notifications/
/// flutter_local_reminder_scheduler.dart）**同一插件、同款惰性初始化与
/// 渠道模式**，仅独立渠道 workout_timer（低重要度：训练计时静默不打断）；
/// 一次性 `show` 而非 `zonedSchedule`——常驻计时是「此刻展示 + 原生倒计时
/// 基点」，不是未来时刻调度（§5.5⑩ remind_at 语义族之外的 W14 新形态）。
///
/// - Android：`when`=休息结束绝对时刻 + `usesChronometer` +
///   `chronometerCountDown` → 系统原生倒计时（进程冻结/锁屏仍走秒，API
///   24+；低版本回落纯文本正文）；
/// - iOS：无原生倒计时，正文携带剩余秒（由控制器在到点/skip 时 upsert）；
/// - `ongoing` 常驻 + `autoCancel=false`：训练未结束不可下滑清除；
///
/// remaining：真实通道真机验收（W14 集成环境无真机/无平台通道——单元与
/// 冒烟测试一律注入 FakeWorkoutTimerNotifier，禁真实通知）。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'rest_timer_notifier.dart';

/// 真实通道适配器（生产装配；构造零副作用、平台通道在首法调用时惰性初始化
/// ——测试误注入也不会触发通道）。
class FlutterLocalWorkoutTimerNotifier implements WorkoutTimerNotifier {
  FlutterLocalWorkoutTimerNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// 惰性初始化：插件 init + Android 渠道。失败静默标记未初始化（下次调用
  /// 重试；§6.1 通知缺失不伤业务）。
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // 启动期不自动弹权限框（与 W13 同口径：权限由待办提醒域显式请求；
        // 计时通知沿用同一份授权结果）。
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _plugin.initialize(settings);
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        kWorkoutTimerChannelId,
        kWorkoutTimerChannelName,
        description: kWorkoutTimerChannelDescription,
        // 低重要度：常驻计时静默驻留通知栏，不响铃不弹出（训练不打断）。
        importance: Importance.low,
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> show(WorkoutTimerNotice notice) async {
    try {
      await _ensureInitialized();
      final endsAt = notice.chronometerEndsAtMs;
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          kWorkoutTimerChannelId,
          kWorkoutTimerChannelName,
          channelDescription: kWorkoutTimerChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          silent: true, // upsert 更新不出声（每组一更，静默是训练语义）。
          ongoing: notice.ongoing, // 常驻：训练未结束不可下滑清除。
          autoCancel: false, // 点击不清除——结束由控制器统一 cancel。
          onlyAlertOnce: true, // 同 id upsert 不重复打扰。
          showWhen: endsAt != null,
          when: endsAt,
          // 原生倒计时（chronometerCountDown，API 24+）：锁屏/进程冻结仍走秒
          // ——「锁屏可跑」的展示半边（业务判定在控制器，见 rest_timer_notifier
          // .dart 文档）。
          usesChronometer: endsAt != null,
          chronometerCountDown: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: false,
        ),
      );
      await _plugin.show(
        notice.notificationId,
        notice.title,
        notice.body,
        details,
      );
    } on Object {
      // 展示失败静默（§6.1）：组间计时在前台 UI 卡内照跑，下次 upsert 自愈。
    }
  }

  @override
  Future<void> cancel({required int notificationId}) async {
    try {
      await _ensureInitialized();
      await _plugin.cancel(notificationId);
    } on Object {
      // 取消失败静默：残留常驻通知由下次训练 upsert/结束 cancel 兜底（§6.1）。
    }
  }
}
