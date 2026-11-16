import 'package:flutter/material.dart';

import 'motion_config.dart';
import 'slimca_theme.dart';

/// Material 3 主题构建（§8.1-§8.3）：浅/深两套，全部从语义 token 构造。
///
/// - MotionConfig 挂进主题（§8.1「动效与主题同源同发」、§9.2「动效 token 挂进主题」）；
/// - ColorScheme 以 tokens.primary 为种子经 fromSeed 补齐 M3 派生槽位
///   （§8.3 dynamic_color 仅映射 primary/seed 两源、保品牌识别），再用语义 token
///   覆盖关键槽位，保「双主色锚定：绿是吃、橘是钱」（§8.2）；
/// - 主题切换动画由 SlimcaThemeMorph 承担（§9.3#10），本函数只负责装配。
ThemeData buildTheme({
  required Brightness brightness,

  /// 第 2 层语义 token；缺省 → 内置浅/深默认 token（§8.2 语义 token 清单）。
  SlimcaTheme? semantic,

  /// 动效 token；缺省 → MotionLevel=full 的 §9.2 表值。
  /// 业务应传 `MotionConfig.forLevel(savedLevel, motionScale: savedScale)`。
  MotionConfig? motion,
}) {
  final SlimcaTheme tokens = semantic ?? SlimcaTheme.defaultFor(brightness);
  final MotionConfig motionConfig =
      motion ?? MotionConfig.forLevel(MotionLevel.full);

  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: tokens.primary,
        brightness: brightness,
      ).copyWith(
        primary: tokens.primary,
        onPrimary: tokens.onPrimary,
        secondary: tokens.moneyOut, // 暖橘 = 金额主色（§8.2 双主色锚定）
        onSecondary: tokens.onPrimary,
        surface: tokens.surface,
        onSurface: tokens.onSurface,
        error: tokens.danger,
        onError: tokens.onPrimary,
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.surface,
    extensions: <ThemeExtension<dynamic>>{tokens, motionConfig},
    // 注：圆角/密度/字重滑杆（§8.2 radiusScale/density/fontScale）与 M3 组件级
    // Theme 覆盖在 P1 主题编辑器（§8.4）接线；组件层现阶段直接读 token，不依赖全局覆盖。
  );
}
