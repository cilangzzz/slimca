/// wakelock_plus 适配器（W14 任务 2「wakelock_plus 适配器」）。
///
/// - Android：`FLAG_KEEP_SCREEN_ON` 窗口旗标（免 WAKE_LOCK 权限声明，
///   插件官方语义）；iOS：`UIApplication.isIdleTimerDisabled`；
/// - 桌面/无实现环境插件抛错 → 静默吞掉（§6.1 降级纪律：常亮缺失不伤
///   业务，训练照常进行）。
///
/// remaining：真实行为真机验收（W14 集成环境无真机/无平台通道——单元与
/// 冒烟测试一律注入 FakeKeepAwakeService，禁真实平台通道）。
library;

import 'package:wakelock_plus/wakelock_plus.dart';

import 'keep_awake_service.dart';

/// wakelock_plus 生产适配器（§10.4 壳负责装配）。
///
/// 构造零副作用：平台通道调用发生在首法（enable/disable）时——测试误注入
/// 也不会触发通道（与 W13 FlutterLocalReminderScheduler 同款惰性纪律）。
class WakelockPlusKeepAwakeService implements KeepAwakeService {
  const WakelockPlusKeepAwakeService();

  @override
  Future<void> enable() async {
    try {
      await WakelockPlus.enable();
    } on Object {
      // 平台通道异常（插件未注册/宿主无实现）：静默降级（§6.1）。
    }
  }

  @override
  Future<void> disable() async {
    try {
      await WakelockPlus.disable();
    } on Object {
      // 释放失败不阻塞训练结束流程（§6.1）：下次 enable 幂等覆盖。
    }
  }
}
