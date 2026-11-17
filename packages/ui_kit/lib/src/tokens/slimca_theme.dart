import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'palette.dart';

/// 第 2 层：语义 token（§8.2 语义 token 清单）。
///
/// 第 3 层（组件）只允许引用本层 token 与 ColorScheme/[MotionConfig]，
/// lint 禁止裸色值/裸时长（§8.2 第 3 层、§9.2）；ui_kit 只导出语义组件。
///
/// 双主色锚定（§8.2）：健康绿 = 热量（kcalIn/kcalOut/net），暖橘 = 金额（moneyIn/moneyOut），
/// 色相全主题包固定，只允许调明度/饱和度（§8.1「换主题不换认知」）。
class SlimcaTheme extends ThemeExtension<SlimcaTheme> {
  const SlimcaTheme({
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceCard,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.kcalIn,
    required this.kcalOut,
    required this.net,
    required this.moneyIn,
    required this.moneyOut,
    required this.success,
    required this.warn,
    required this.danger,
    this.radiusScale = 1.0,
    this.density = 1.0,
    this.fontScale = 1.0,
    this.motionScale = 1.0,
  });

  // ── 背景层级（§8.2）─────────────────────────────────────────────
  /// 页面基底
  final Color surface;

  /// 次级背景（分隔带/骨架/禁用底）
  final Color surfaceMuted;

  /// 卡片底（亮于/暗于 [surface] 一个层级）
  final Color surfaceCard;

  // ── 正文与描边（§8.2 清单未列，组件层必需的补充 token，"14+ 语义字段"允许扩展）
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color outline;

  // ── 品牌主色（交互锚点，§8.2）
  final Color primary;
  final Color onPrimary;

  // ── 热量语义（健康绿锚定，§8.2；kcal 账本「吃=支出、运动=再入账」§2.1③）
  /// 摄入
  final Color kcalIn;

  /// 消耗（运动再入账）
  final Color kcalOut;

  /// 净热量数字
  final Color net;

  // ── 金额语义（暖橘锚定，§8.2）
  /// 收入
  final Color moneyIn;

  /// 支出
  final Color moneyOut;

  // ── 状态（置信度三色点复用，§8.2/§2.3/§7.3）
  final Color success;
  final Color warn;
  final Color danger;

  // ── 形状/密度/字重/动效强度滑杆（§8.2；motionScale 由 MotionConfig.forLevel 消费）
  final double radiusScale;
  final double density;
  final double fontScale;
  final double motionScale;

  /// 内置默认浅色语义 token（由第 1 层色板推导，§8.2 三层架构）。
  ///
  /// W1 基线零漂移承诺：本静态值 = `_fromPalette(defaults, light)` 原始推导
  /// （外延 tone 如浅色 moneyIn/kcalOut ≈70 不达 AA 正文阈值是 W1 已知口径），
  /// §8.3 WCAG AA 护栏在**装配层**执行（buildTheme / ThemeProfile.toSlimcaTheme
  /// 出口自动降级到最近安全 tone），不回写本基线——壳层 theme_pack 复刻表
  /// 与本值逐值相等（W16 零漂移测试锚点）。
  static final SlimcaTheme light = _fromPalette(
    SlimcaPalette.defaults,
    Brightness.light,
  );

  /// 内置默认深色语义 token（零漂移承诺同 [light]）。
  /// 注：AMOLED 纯黑（§8.3 曜黑）是独立开关的独立主题包，不在此默认值内。
  static final SlimcaTheme dark = _fromPalette(
    SlimcaPalette.defaults,
    Brightness.dark,
  );

  static SlimcaTheme defaultFor(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// 色板 → 语义 token 的推导入口（公开 W1 基线推导表，tone 选取遵循 M3
  /// 明度惯例；供主题包层复用，替代壳层复刻副本）。
  ///
  /// 注意：本方法**不含** §8.3 WCAG AA 护栏——基线必须与 W1 静态值逐值一致
  /// （零漂移）；护栏降级发生在 [enforceSlimcaAa]（buildTheme 与
  /// ThemeProfile.toSlimcaTheme 装配出口调用）。
  static SlimcaTheme fromPalette(SlimcaPalette p, Brightness brightness) =>
      _fromPalette(p, brightness);

  /// 色板 → 语义 token 的默认推导（tone 选取遵循 M3 明度惯例）。
  static SlimcaTheme _fromPalette(SlimcaPalette p, Brightness brightness) {
    if (brightness == Brightness.dark) {
      return SlimcaTheme(
        surface: p.neutralTone(6),
        surfaceMuted: p.neutralTone(12),
        surfaceCard: p.neutralTone(16),
        onSurface: p.neutralTone(90),
        onSurfaceMuted: p.neutralTone(70),
        outline: p.neutralTone(50),
        primary: p.kcalTone(80),
        onPrimary: p.kcalTone(20),
        kcalIn: p.kcalTone(80),
        kcalOut: p.kcalTone(60),
        net: p.kcalTone(85),
        moneyIn: p.moneyTone(85),
        moneyOut: p.moneyTone(70),
        success: p.kcalTone(80),
        warn: p.moneyTone(75),
        danger: p.dangerTone(80),
      );
    }
    return SlimcaTheme(
      surface: p.neutralTone(98),
      surfaceMuted: p.neutralTone(94),
      surfaceCard: p.neutralTone(100),
      onSurface: p.neutralTone(10),
      onSurfaceMuted: p.neutralTone(40),
      outline: p.neutralTone(50),
      primary: p.kcalTone(40),
      onPrimary: p.kcalTone(100),
      kcalIn: p.kcalTone(40),
      kcalOut: p.kcalTone(70),
      net: p.kcalTone(30),
      moneyIn: p.moneyTone(70),
      moneyOut: p.moneyTone(40),
      success: p.kcalTone(40),
      warn: p.moneyTone(55),
      danger: p.dangerTone(45),
    );
  }

  /// 拷贝并替换字段（ThemeExtension 契约；§8.3 主题包 = 本结构的 token 集）。
  @override
  SlimcaTheme copyWith({
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceCard,
    Color? onSurface,
    Color? onSurfaceMuted,
    Color? outline,
    Color? primary,
    Color? onPrimary,
    Color? kcalIn,
    Color? kcalOut,
    Color? net,
    Color? moneyIn,
    Color? moneyOut,
    Color? success,
    Color? warn,
    Color? danger,
    double? radiusScale,
    double? density,
    double? fontScale,
    double? motionScale,
  }) => SlimcaTheme(
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    surfaceCard: surfaceCard ?? this.surfaceCard,
    onSurface: onSurface ?? this.onSurface,
    onSurfaceMuted: onSurfaceMuted ?? this.onSurfaceMuted,
    outline: outline ?? this.outline,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    kcalIn: kcalIn ?? this.kcalIn,
    kcalOut: kcalOut ?? this.kcalOut,
    net: net ?? this.net,
    moneyIn: moneyIn ?? this.moneyIn,
    moneyOut: moneyOut ?? this.moneyOut,
    success: success ?? this.success,
    warn: warn ?? this.warn,
    danger: danger ?? this.danger,
    radiusScale: radiusScale ?? this.radiusScale,
    density: density ?? this.density,
    fontScale: fontScale ?? this.fontScale,
    motionScale: motionScale ?? this.motionScale,
  );

  /// 主题切换 morph 的插值（§8.3「主题切换 = ColorScheme.lerp + ThemeExtensionTween」）。
  @override
  SlimcaTheme lerp(covariant ThemeExtension<SlimcaTheme>? other, double t) {
    if (identical(this, other) || other == null) return this;
    final SlimcaTheme o = other as SlimcaTheme;
    return SlimcaTheme(
      surface: Color.lerp(surface, o.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, o.surfaceMuted, t)!,
      surfaceCard: Color.lerp(surfaceCard, o.surfaceCard, t)!,
      onSurface: Color.lerp(onSurface, o.onSurface, t)!,
      onSurfaceMuted: Color.lerp(onSurfaceMuted, o.onSurfaceMuted, t)!,
      outline: Color.lerp(outline, o.outline, t)!,
      primary: Color.lerp(primary, o.primary, t)!,
      onPrimary: Color.lerp(onPrimary, o.onPrimary, t)!,
      kcalIn: Color.lerp(kcalIn, o.kcalIn, t)!,
      kcalOut: Color.lerp(kcalOut, o.kcalOut, t)!,
      net: Color.lerp(net, o.net, t)!,
      moneyIn: Color.lerp(moneyIn, o.moneyIn, t)!,
      moneyOut: Color.lerp(moneyOut, o.moneyOut, t)!,
      success: Color.lerp(success, o.success, t)!,
      warn: Color.lerp(warn, o.warn, t)!,
      danger: Color.lerp(danger, o.danger, t)!,
      radiusScale: lerpDouble(radiusScale, o.radiusScale, t)!,
      density: lerpDouble(density, o.density, t)!,
      fontScale: lerpDouble(fontScale, o.fontScale, t)!,
      motionScale: lerpDouble(motionScale, o.motionScale, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SlimcaTheme &&
        other.surface == surface &&
        other.surfaceMuted == surfaceMuted &&
        other.surfaceCard == surfaceCard &&
        other.onSurface == onSurface &&
        other.onSurfaceMuted == onSurfaceMuted &&
        other.outline == outline &&
        other.primary == primary &&
        other.onPrimary == onPrimary &&
        other.kcalIn == kcalIn &&
        other.kcalOut == kcalOut &&
        other.net == net &&
        other.moneyIn == moneyIn &&
        other.moneyOut == moneyOut &&
        other.success == success &&
        other.warn == warn &&
        other.danger == danger &&
        other.radiusScale == radiusScale &&
        other.density == density &&
        other.fontScale == fontScale &&
        other.motionScale == motionScale;
  }

  @override
  int get hashCode => Object.hash(
    surface,
    surfaceMuted,
    surfaceCard,
    onSurface,
    onSurfaceMuted,
    outline,
    primary,
    onPrimary,
    kcalIn,
    kcalOut,
    net,
    moneyIn,
    moneyOut,
    success,
    warn,
    danger,
    radiusScale,
    density,
    fontScale,
    motionScale,
  );

  @override
  String toString() =>
      'SlimcaTheme(surface: $surface, primary: $primary, kcalIn: $kcalIn)';
}

/// §8.3「ThemeExtensionTween 自实现 lerp」：Flutter SDK 未内置该类，
/// 按 [ThemeExtension.lerp] 契约实现的显式动画 tween（供驱动单 token 集过渡时使用）。
class ThemeExtensionTween<T extends ThemeExtension<T>> extends Tween<T?> {
  ThemeExtensionTween({super.begin, super.end});

  @override
  T? lerp(double t) {
    final T? a = begin;
    final T? b = end;
    if (identical(a, b)) return a;
    if (a == null) return b;
    if (b == null) return a;
    return a.lerp(b, t) as T;
  }
}

/// 第 2 层语义 token 读取入口。
/// 宿主主题未挂载时回退内置默认（防御第三方 ThemeData 缺省）。
extension SlimcaThemeBuildContext on BuildContext {
  SlimcaTheme get slimca {
    final ThemeData theme = Theme.of(this);
    return theme.extension<SlimcaTheme>() ??
        SlimcaTheme.defaultFor(theme.brightness);
  }
}
