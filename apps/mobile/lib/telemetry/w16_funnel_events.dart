/// W16 漏斗事件名（§11.2 W16 主线「主题编辑器+6 主题包+dynamic_color+端侧
/// 小票 OCR」）。
///
/// 注：同 W13/W14/W15 口径（w13_funnel_events.dart 文件头）——core_domain 的
/// TelemetryFunnel 常量表冻结于 W7-8 录入/同步链路，W16 两个事件名属主题域
/// 钩子，落点在壳层（apps/mobile）常量——事件 wire 名与任务口径一字不差
/// （theme_editor_opened/theme_changed），后续若 core_domain 收编再平移。
///
/// 隐私口径（§3.9）：props 只允许标量枚举标签（theme_id=包 id、source=选择
/// 来源），包名/颜色值等业务内容禁入（TelemetryPrivacy.sanitizeProps 兜底）。
library;

/// W16 漏斗事件名常量。
abstract final class W16TelemetryFunnel {
  /// 主题编辑器打开（§11.2 W16 任务 5「theme_editor_opened」：漏斗首步——
  /// 「进编辑器」；设置页主题入口唤起即记）。
  static const String themeEditorOpened = 'theme_editor_opened';

  /// 主题切换（§11.2 W16 任务 5「theme_changed」：漏斗终点——「换肤生效」；
  /// props.theme_id = 包 id 标量标签、props.source = preset/custom 标量标签）。
  static const String themeChanged = 'theme_changed';
}
