import 'package:flutter/material.dart';

import 'contrast.dart';
import 'motion_config.dart';
import 'slimca_sizes.dart';
import 'slimca_spacing.dart';
import 'slimca_theme.dart';

/// Material 3 主题构建（§8.1-§8.3）：浅/深两套，全部从语义 token 构造。
///
/// - MotionConfig 挂进主题（§8.1「动效与主题同源同发」、§9.2「动效 token 挂进主题」）；
/// - ColorScheme 以 tokens.primary 为种子经 fromSeed 补齐 M3 派生槽位
///   （§8.3 dynamic_color 仅映射 primary/seed 两源、保品牌识别），再用语义 token
///   覆盖关键槽位，保「双主色锚定：绿是吃、橘是钱」（§8.2）；
/// - WCAG AA 对比度护栏（§8.3/§8.4）：装配前对语义 token 组合做关键对校验，
///   不达标自动降级到最近安全 tone（[enforceSlimcaAa]，幂等——内置主题包与
///   ThemeProfile.toSlimcaTheme 产物已过护栏，此处为手写 token 的兜底闸门）；
/// - 约束 token 层（W17 插曲 UI-规范 §2.2）SlimcaSpacing/SlimcaSizes 挂进主题，
///   与 SlimcaTheme/MotionConfig 同层装配，组件层统一引用；
/// - 主题切换动画由 SlimcaThemeMorph 承担（§9.3#10），本函数只负责装配。
ThemeData buildTheme({
  required Brightness brightness,

  /// 第 2 层语义 token；缺省 → 内置浅/深默认 token（§8.2 语义 token 清单）。
  SlimcaTheme? semantic,

  /// 动效 token；缺省 → MotionLevel=full 的 §9.2 表值。
  /// 业务应传 `MotionConfig.forLevel(savedLevel, motionScale: savedScale)`。
  MotionConfig? motion,

  /// 间距尺度 token（W17 插曲 UI-规范 §2.2）；缺省 → 官方刻度默认档。
  SlimcaSpacing? spacing,

  /// 尺寸/命中/状态层约束 token（W17 插曲 UI-规范 §2.2）；缺省 → 官方值默认档。
  SlimcaSizes? sizes,
}) {
  // §8.3 护栏兜底：不达标关键对自动降级到最近安全 tone（幂等）。
  final SlimcaTheme tokens = enforceSlimcaAa(
    semantic ?? SlimcaTheme.defaultFor(brightness),
  );
  final MotionConfig motionConfig =
      motion ?? MotionConfig.forLevel(MotionLevel.full);
  final SlimcaSpacing spacingConfig = spacing ?? SlimcaSpacing.standard;
  final SlimcaSizes sizesConfig = sizes ?? SlimcaSizes.standard;

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
    extensions: <ThemeExtension<dynamic>>{
      tokens,
      motionConfig,
      spacingConfig,
      sizesConfig,
    },
    // 注：圆角/密度/字重滑杆（§8.2 radiusScale/density/fontScale）与 M3 组件级
    // Theme 覆盖在 P1 主题编辑器（§8.4）接线；组件层现阶段直接读 token，不依赖全局覆盖。
  );
}
