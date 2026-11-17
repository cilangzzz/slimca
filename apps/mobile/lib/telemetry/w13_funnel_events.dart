/// W13 留存钩子漏斗事件名（§11.2 W13 主线「待办完整版+存钱目标」、§3.6
/// 存钱目标 P1 留存钩子）。
///
/// 注：core_domain 的 TelemetryFunnel 常量表（core_domain/lib/src/telemetry.dart）
/// 冻结于 W7-8 的录入/同步链路；W13 三个事件名属存钱/重复待办钩子，落点在
/// 壳层（apps/mobile）常量——事件 wire 名与任务口径一字不差，后续若
/// core_domain 收编再平移（壳层常量先行，不阻塞埋点接入）。
///
/// 隐私口径（§3.9）：props 只允许标量枚举标签（method/freq 等），金额数值、
/// 标题等业务内容禁入（TelemetryPrivacy.sanitizeProps 兜底）。
library;

/// W13 漏斗事件名常量。
abstract final class W13TelemetryFunnel {
  /// 存钱目标建档（§3.6 存钱目标 P1：留存钩子首步——「设目标」）。
  static const String savingsGoalCreated = 'savings_goal_created';

  /// 投币打卡（§3.6「投币式打卡」：进度=贡献行求和 §5.5⑫——「存进去」）。
  static const String coinIn = 'coin_in';

  /// 重复待办建档（§3.6 待办完整版 P1「重复（RRULE）」+ 提醒）。
  static const String todoRecurrenceCreated = 'todo_recurrence_created';
}
