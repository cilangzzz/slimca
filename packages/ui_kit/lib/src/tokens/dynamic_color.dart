/// dynamic_color 适配层（§8.3「dynamic_color（Android 12+ Material You）：
/// 仅映射 primary/seed 两源（不整体套用系统色，保品牌识别与双主色锚定）；
/// iOS/旧机型回退手动种子色」）。
///
/// 集成口径：使用 dynamic_color 插件的 `DynamicColorPlugin.getCorePalette()`
/// 通道（`DynamicColorBuilder` widget 的底层取色源）——系统 ColorScheme 整体
/// 套用会破坏双主色锚定与语义 token 架构（§8.2），因此只取 CorePalette 的
/// 两源 tonal palette 做映射：
/// - 源 1 accent（`CorePalette.primary`）→ primary/onPrimary 品牌交互锚点；
/// - 源 2 neutral（`CorePalette.neutral`/`neutralVariant`）→ 背景层级/正文/描边；
/// - kcal/money/success/warn/danger 一律不映射（健康绿=热量、暖橘=金额的
///   认知锚定不变，§8.2「换主题不换认知」）。
/// 平台取色完成后仍过 WCAG AA 护栏（§8.3，见 [SlimcaDynamicThemeMapper.map]）。
library;

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'build_theme.dart';
import 'contrast.dart';
import 'slimca_theme.dart';
import 'theme_profile.dart';

/// 平台动态色 → 语义 token 的映射器（§8.3 两源映射 + 护栏校验）。
abstract final class SlimcaDynamicThemeMapper {
  /// 把平台 [palette] 映射到以 [base]（手动种子色包的语义 token）为底的
  /// SlimcaTheme；[palette] 为 null（不支持/通道异常）→ 原样返回 [base]
  /// （§8.3「iOS/旧机型回退手动种子色」）。
  ///
  /// 映射规则（§8.3 仅两源）：
  /// - accent：primary = accent tone 40（浅）/ 80（深），onPrimary 取反差 tone；
  /// - neutral：surface/surfaceMuted/surfaceCard/onSurface/onSurfaceMuted
  ///   取 neutral 对应 tone，outline 取 neutralVariant tone 50；
  /// - 其余语义 token（kcal/money/success/warn/danger/滑杆）保持 [base]；
  /// - 出口过 [enforceSlimcaAa]（平台取色不保证达 AA）。
  static SlimcaTheme map({
    required CorePalette? palette,
    required SlimcaTheme base,
    required Brightness brightness,
  }) {
    if (palette == null) return base;
    final bool dark = brightness == Brightness.dark;
    final TonalPalette accent = palette.primary;
    final TonalPalette neutral = palette.neutral;
    final TonalPalette neutralVariant = palette.neutralVariant;
    final SlimcaTheme mapped = base.copyWith(
      // 源 1：accent（品牌交互锚点；M3 明度惯例浅 40 / 深 80）
      primary: Color(accent.get(dark ? 80 : 40)),
      onPrimary: Color(accent.get(dark ? 20 : 100)),
      // 源 2：neutral（背景层级/正文/描边）
      surface: Color(neutral.get(dark ? 6 : 98)),
      surfaceMuted: Color(neutral.get(dark ? 12 : 94)),
      surfaceCard: Color(neutral.get(dark ? 16 : 100)),
      onSurface: Color(neutral.get(dark ? 90 : 10)),
      onSurfaceMuted: Color(neutral.get(dark ? 70 : 40)),
      outline: Color(neutralVariant.get(50)),
      // kcal/money/success/warn/danger 不映射（双主色锚定，§8.2/§8.3）
    );
    return enforceSlimcaAa(mapped);
  }
}

/// 平台动态色加载器（可注入 Fake 供单测——测试禁止真实平台通道）。
typedef CorePaletteLoader = Future<CorePalette?> Function();

/// 默认实现：dynamic_color 插件通道（Android 12+ Material You / macOS）；
/// 不支持的平台或通道异常一律吞掉返回 null（§8.3 回退手动种子色，不阻断启动）。
Future<CorePalette?> loadPlatformCorePalette() async {
  try {
    return await DynamicColorPlugin.getCorePalette();
  } catch (_) {
    return null;
  }
}

/// dynamic_color 集成层（§8.3）：异步取平台 CorePalette，映射进主题包种子
/// 体系后按深浅各装配一套 ThemeData；加载中/不支持时直接使用 [profile]
/// 手动种子色（回退路径），主题源变化仍由 SlimcaThemeMorph 承担 morph（§9.3#10）。
class SlimcaDynamicColorBuilder extends StatefulWidget {
  const SlimcaDynamicColorBuilder({
    super.key,
    required this.profile,
    required this.builder,
    this.loader,
  });

  /// 基准主题包（手动种子色；动态色仅按 §8.3 两源覆写其中部分槽位）。
  final ThemeProfile profile;

  /// 装配回调：light/dark 两套 ThemeData（已挂 MotionConfig 与语义 token）。
  final Widget Function(
    BuildContext context,
    ThemeData lightTheme,
    ThemeData darkTheme,
  )
  builder;

  /// 动态色加载器（缺省走 [loadPlatformCorePalette]；测试注入 Fake）。
  final CorePaletteLoader? loader;

  @override
  State<SlimcaDynamicColorBuilder> createState() =>
      _SlimcaDynamicColorBuilderState();
}

class _SlimcaDynamicColorBuilderState extends State<SlimcaDynamicColorBuilder> {
  late Future<CorePalette?> _paletteFuture;

  @override
  void initState() {
    super.initState();
    _paletteFuture = widget.loader?.call() ?? loadPlatformCorePalette();
  }

  ThemeData _buildTheme(CorePalette? palette, Brightness brightness) {
    final SlimcaTheme base = widget.profile.toSlimcaTheme(brightness);
    final SlimcaTheme tokens = SlimcaDynamicThemeMapper.map(
      palette: palette,
      base: base,
      brightness: brightness,
    );
    return buildTheme(
      brightness: brightness,
      semantic: tokens,
      motion: widget.profile.toMotionConfig(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CorePalette?>(
      future: _paletteFuture,
      builder: (BuildContext context, AsyncSnapshot<CorePalette?> snapshot) {
        // 加载中/失败/不支持 → null → 手动种子色回退（§8.3）。
        final CorePalette? palette =
            snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null;
        return widget.builder(
          context,
          _buildTheme(palette, Brightness.light),
          _buildTheme(palette, Brightness.dark),
        );
      },
    );
  }
}
