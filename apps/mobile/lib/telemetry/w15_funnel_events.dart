/// W15 漏斗事件名（§11.2 W15 主线「多账本+预算体系+统计报表」）。
///
/// 注：同 W13/W14 口径（w13_funnel_events.dart 文件头）——core_domain 的
/// TelemetryFunnel 常量表冻结于 W7-8 录入/同步链路，W15 三个事件名属账本
/// 域钩子，落点在壳层（apps/mobile）常量——事件 wire 名与任务口径一字不差
/// （report_viewed/budget_set/ledger_switched），后续若 core_domain 收编再
/// 平移（壳层常量先行，不阻塞埋点接入）。
///
/// 隐私口径（§3.9）：props 只允许标量枚举标签（kind/scope 等），账本名、
/// 预算金额数值等业务内容禁入（TelemetryPrivacy.sanitizeProps 兜底）。
library;

/// W15 漏斗事件名常量。
abstract final class W15TelemetryFunnel {
  /// 统计报表查看（§3.4 统计报表 P1、§4.3 /stats：漏斗首步——「看报表」）。
  static const String reportViewed = 'report_viewed';

  /// 预算设置（§3.4 月度+分类预算 P1、§5.4⑥ budgets：漏斗中步——「设预算」；
  /// props.scope = daily_total/kcal/category/monthly 标量标签）。
  static const String budgetSet = 'budget_set';

  /// 账本切换（§3.4 多账本 P1「账本切换抽屉」：漏斗中步——「用了多账本」；
  /// props.kind = money/kcal 标量标签）。
  static const String ledgerSwitched = 'ledger_switched';
}
