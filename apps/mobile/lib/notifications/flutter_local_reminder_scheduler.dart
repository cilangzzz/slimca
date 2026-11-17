/// flutter_local_notifications 适配器（§11.2 W13 任务 3「本地通知：… +
/// flutter_local_notifications 适配器」）。
///
/// - Android：`todo_reminders` 渠道 + Android 13+ POST_NOTIFICATIONS 运行时
///   请求（manifest 已声明 uses-permission，见 android/app/src/main/
///   AndroidManifest.xml——运行时请求在本适配器 [ensurePermission] 内接线）；
/// - iOS：alert+badge+sound 请求（ DarwinInitializationSettings 关闭启动期
///   自动弹窗，统一走显式请求）；
/// - 调度：`zonedSchedule`，时刻为 UTC 毫秒的绝对瞬间（§5.5⑩ remind_at
///   口径）——`TZDateTime.from(utc 时刻, tz.UTC)` 构造，与设备时区无关；
/// - 提醒时刻精度取 `inexactAllowWhileIdle`（不申请精确闹钟特批权限，
///   §3.3 最小权限；分钟级误差对待办提醒可接受——remaining：真机验收时
///   如需秒级准时再评估 SCHEDULE_EXACT_ALARM）。
///
/// remaining：真实通道真机验收（W13 集成环境无真机/无平台通道——单元与
/// 冒烟测试一律注入 FakeReminderScheduler，禁真实通知）。
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_scheduler.dart';

/// 真实通道适配器（生产装配；构造零副作用、平台通道在首法调用时惰性初始化
/// ——测试误注入也不会触发通道）。
class FlutterLocalReminderScheduler implements ReminderScheduler {
  FlutterLocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// 惰性初始化：插件 init + 时区库 + Android 渠道。失败静默标记未初始化
  /// （下次调用重试；§6.1 通知缺失不伤业务）。
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        // 启动期不自动弹权限框：统一由 ensurePermission 显式请求。
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
        kTodoReminderChannelId,
        kTodoReminderChannelName,
        description: kTodoReminderChannelDescription,
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  @override
  Future<bool> ensurePermission() async {
    try {
      await _ensureInitialized();
      // Android 13+（API 33）POST_NOTIFICATIONS 运行时请求；API <33 或非
      // Android 平台返回 null → 视为已授权（无运行时权限语义）。
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final androidGranted = await android?.requestNotificationsPermission();

      final ios = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      final iosGranted = await ios
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // 双端请求都未发生（桌面/测试环境）→ true；任一端明确拒绝 → false。
      if (androidGranted == null && iosGranted == null) return true;
      return (androidGranted ?? true) && (iosGranted ?? true);
    } on Object {
      // 平台通道异常（插件未注册/桌面端无实现）：不向上抛（接口纪律），
      // 视为未授权——调度仍继续，系统侧拒发展示。
      return false;
    }
  }

  @override
  Future<void> schedule(TodoReminder reminder) async {
    try {
      await _ensureInitialized();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          kTodoReminderChannelId,
          kTodoReminderChannelName,
          channelDescription: kTodoReminderChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      );
      // remind_at 为 UTC 毫秒（§5.5⑩）：以 UTC 时刻构造绝对瞬间调度，
      // zonedSchedule 只取该瞬间（不涉设备时区换算）。
      final when = tz.TZDateTime.from(
        DateTime.fromMillisecondsSinceEpoch(reminder.remindAtMs, isUtc: true),
        tz.UTC,
      );
      await _plugin.zonedSchedule(
        reminder.id,
        kTodoReminderChannelName,
        reminder.title,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.todoId,
      );
    } on Object {
      // 调度失败静默（§6.1 通知缺失不伤业务）：下轮 todos 变更整轮重排
      // 自愈（对账以「计划集」为准，漏排的 id 会在下次 reconcile 补上）。
    }
  }

  @override
  Future<void> cancel({required int notificationId}) async {
    try {
      await _ensureInitialized();
      await _plugin.cancel(notificationId);
    } on Object {
      // 取消失败静默：残留通知由系统按时间自然到期（一次性），不影响数据。
    }
  }
}
