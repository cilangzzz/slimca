/// 组间计时器「锁屏可跑」底座之一：唤醒锁抽象（§11.2 W14 主线「健身计划：
/// 模板排期+组间计时（锁屏可跑）+组明细」、§3.5 健身计划 P1、W14 任务 2）。
///
/// 分层（§10.4 壳层装配，与 W13 ReminderScheduler 同款纪律）：
/// - 抽象只在本文件；生产实现 [WakelockPlusKeepAwakeService]
///   （wakelock_plus 适配器，见 wakelock_plus_keep_awake.dart——真实行为
///   真机验收 remaining）；
/// - 测试实现 `FakeKeepAwakeService`（fake_keep_awake_service.dart，记录
///   调用序列，禁平台通道）。
///
/// 语义边界（骨架口径，诚实声明）：enable=训练进行中保持屏幕常亮
/// （Android FLAG_KEEP_SCREEN_ON 窗口旗标语义，免权限声明）；「锁屏后仍
/// 长跑」需前台服务（Android FGS）——骨架不申请（§3.3 最小权限），本抽象
/// 即前台服务/唤醒锁实现的替换点。锁屏可跑的正确性由两条腿承担：
/// ①剩余休息秒一律以绝对时刻计算（见 workout_session_controller.dart，
/// 进程冻结恢复后按时钟即时重算）；②常驻通知挂原生倒计时（见
/// rest_timer_notifier.dart）。remaining：真机验收 + 后台长跑如需再评估
/// foregroundServiceType。
library;

/// 唤醒锁抽象（W14 任务 2）。
///
/// 实现纪律（§6.1 原则 1 同款）：平台通道异常不得向上抛——常亮缺失不伤
/// 业务（训练照常进行），适配器内部自行兜底。
abstract interface class KeepAwakeService {
  /// 开练：保持屏幕常亮（训练进行中）。
  Future<void> enable();

  /// 训练结束/放弃：释放常亮。
  Future<void> disable();
}
