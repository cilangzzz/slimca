/// W14 健身计划漏斗事件名（§11.2 W14 主线「健身计划（留存钩子）」、§3.5
/// 健身计划 P1、W14 任务 3「workout_started/set_logged/workout_completed
/// 漏斗」）。
///
/// 注：同 W13 口径（w13_funnel_events.dart 文件头）——core_domain 的
/// TelemetryFunnel 常量表冻结于 W7-8 录入/同步链路，W14 三个事件名属健身
/// 钩子，落点在壳层（apps/mobile）常量——事件 wire 名与任务口径一字不差，
/// 后续若 core_domain 收编再平移（壳层常量先行，不阻塞埋点接入）。
///
/// 隐私口径（§3.9）：props 只允许标量枚举标签（source）与计数值（sets/
/// rest_s），动作名、计划名等业务内容禁入（TelemetryPrivacy.sanitizeProps
/// 兜底）。
library;

/// W14 漏斗事件名常量。
abstract final class W14TelemetryFunnel {
  /// 开练（§3.5 组间计时器入口：留存钩子首步——「开始训练」）。
  static const String workoutStarted = 'workout_started';

  /// 记组（§3.5 组明细 exercise_sets：每完成一组记一次，「练起来了」）。
  static const String setLogged = 'set_logged';

  /// 训练完成（§5.5⑦ template_instance 会话 + 组明细同事务落库——「练完了」）。
  static const String workoutCompleted = 'workout_completed';
}
