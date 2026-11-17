/// 主题包模型（§8.1「主题自定义是用户数据的一部分」、§5.6⑳ theme_profiles
/// 「一等同步实体」、§8.3「主题包 = JSON profile」）。
///
/// 行形状对齐：本文件 `ThemeProfile.toJsonRow()` 的键名与 core_db
/// `theme_profiles` 行（drift `ThemeProfile.fromJson`）的 camelCase 键一一对应
/// ——id / name / tokens / motionLevel / fontId / isPreset / sort；tokens 值为
/// 语义 token 集 JSON 字符串（浅/深种子色 + §8.2 四滑杆 + AMOLED 纯黑开关）。
/// 同步公共列（createdAt/updatedAt/deletedAt/hlc/revision/schemaVer/deviceId，
/// §5.1）不在此携带——由 core_db 同步层补齐，ui_kit 不依赖 drift。
///
/// 滑杆量程：motionScale 按文档 §8.3 固定 0.6x-1.5x；radiusScale/density/
/// fontScale 文档未冻结数值，此处定义编辑器量程并构造时钳制（§8.4 四滑杆）。
library;

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/material.dart';

import 'contrast.dart';
import 'motion_config.dart';
import 'palette.dart';
import 'slimca_theme.dart';

/// 单侧（浅或深）种子色四元组（§8.2 第 1 层入口，经 SlimcaPalette.fromSeeds
/// 生成 HCT tonal palette）。
///
/// 双主色锚定（§8.2）：kcal 色相 150 / money 色相 62 在所有主题包中固定，
/// 本类不强制（校验在 preset 清单与编辑器、测试里做），只承载数据。
class SlimcaSeedSet {
  const SlimcaSeedSet({
    required this.kcal,
    required this.money,
    required this.danger,
    required this.neutral,
  });

  /// 热量语义种子（健康绿锚定，色相 150）。
  final Color kcal;

  /// 金额语义种子（暖橘锚定，色相 62）。
  final Color money;

  /// 危险状态种子。
  final Color danger;

  /// 中性基底种子（背景/正文）。
  final Color neutral;

  /// tokens JSON 内的种子对象形状。
  Map<String, Object?> toJson() => <String, Object?>{
    'kcal': kcal.toARGB32(),
    'money': money.toARGB32(),
    'danger': danger.toARGB32(),
    'neutral': neutral.toARGB32(),
  };

  factory SlimcaSeedSet.fromJson(Map<String, Object?> json) => SlimcaSeedSet(
    kcal: Color((json['kcal'] as num).toInt()),
    money: Color((json['money'] as num).toInt()),
    danger: Color((json['danger'] as num).toInt()),
    neutral: Color((json['neutral'] as num).toInt()),
  );

  SlimcaSeedSet copyWith({
    Color? kcal,
    Color? money,
    Color? danger,
    Color? neutral,
  }) => SlimcaSeedSet(
    kcal: kcal ?? this.kcal,
    money: money ?? this.money,
    danger: danger ?? this.danger,
    neutral: neutral ?? this.neutral,
  );

  /// 主题包切换 morph 的种子插值（§8.3 lerp 口径，HCT 色相随 Color.lerp 在
  /// RGB 空间过渡，成品 token 以 fromSeeds 重推导保证锚定）。
  SlimcaSeedSet lerp(SlimcaSeedSet other, double t) => SlimcaSeedSet(
    kcal: Color.lerp(kcal, other.kcal, t)!,
    money: Color.lerp(money, other.money, t)!,
    danger: Color.lerp(danger, other.danger, t)!,
    neutral: Color.lerp(neutral, other.neutral, t)!,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SlimcaSeedSet &&
          other.kcal == kcal &&
          other.money == money &&
          other.danger == danger &&
          other.neutral == neutral;

  @override
  int get hashCode => Object.hash(kcal, money, danger, neutral);

  @override
  String toString() =>
      'SlimcaSeedSet(kcal: $kcal, money: $money, danger: $danger, neutral: $neutral)';
}

/// 主题包（§5.6⑳ 行形状 + §8.2 四滑杆 + §9.2 MotionLevel）。
class ThemeProfile {
  ThemeProfile({
    required this.id,
    required this.name,
    required this.lightSeeds,
    required this.darkSeeds,
    double radiusScale = 1.0,
    double density = 1.0,
    double fontScale = 1.0,
    double motionScale = 1.0,
    this.motionLevel = MotionLevel.full,
    this.fontId,
    this.isPreset = false,
    this.sort = 0,
    this.pureBlackDark = false,
  })  : radiusScale = clampRadiusScale(radiusScale),
        density = clampDensity(density),
        fontScale = clampFontScale(fontScale),
        motionScale = clampDouble(
          motionScale,
          MotionConfig.motionScaleMin,
          MotionConfig.motionScaleMax,
        );

  /// 主键（应用层生成 UUIDv7，§5.1；ui_kit 不生成，由调用方赋值）。
  final String id;

  /// 包名（内置 6 套：墨/纸/霓虹/奶油/森野/曜黑，§8.3）。
  final String name;

  /// 浅色种子色四元组。
  final SlimcaSeedSet lightSeeds;

  /// 深色种子色四元组。
  final SlimcaSeedSet darkSeeds;

  // ── §8.2 四滑杆（形状/密度/字重/动效强度）─────────────────────────
  /// 圆角系数（编辑器量程 [radiusScaleMin, radiusScaleMax]，默认 1.0）。
  final double radiusScale;

  /// 密度系数（默认 1.0）。
  final double density;

  /// 字重系数（默认 1.0）。
  final double fontScale;

  /// 动效强度系数（§8.3 量程 0.6x-1.5x，构造时钳制）。
  final double motionScale;

  /// 动效档位（§9.2 MotionLevel：off/reduced/full）。
  final MotionLevel motionLevel;

  /// 字体 id（可空，§5.6⑳ font_id）。
  final String? fontId;

  /// 内置包不可删（§5.6⑳ is_preset）。
  final bool isPreset;

  /// 排序（§5.6⑳ sort）。
  final int sort;

  /// 曜黑 AMOLED 纯黑独立开关（§8.3）：深色下 surface=纯黑。
  final bool pureBlackDark;

  // ── 滑杆量程（§8.4 编辑器滑杆绑定用；motionScale 量程复用 §8.3 冻结值）──
  static const double radiusScaleMin = 0.0;
  static const double radiusScaleMax = 2.0;
  static const double densityMin = 0.8;
  static const double densityMax = 1.2;
  static const double fontScaleMin = 0.85;
  static const double fontScaleMax = 1.3;
  static double clampRadiusScale(double v) =>
      clampDouble(v, radiusScaleMin, radiusScaleMax);
  static double clampDensity(double v) =>
      clampDouble(v, densityMin, densityMax);
  static double clampFontScale(double v) =>
      clampDouble(v, fontScaleMin, fontScaleMax);
  static double clampMotionScale(double v) =>
      clampDouble(v, MotionConfig.motionScaleMin, MotionConfig.motionScaleMax);

  /// 派生指定亮度的语义 token 集（§8.2 三层架构第 1→2 层）：
  /// 种子 → SlimcaPalette.fromSeeds → SlimcaTheme.fromPalette（W1 基线推导表）
  /// → §8.3 WCAG AA 护栏降级（关键前景/背景对不达标自动降级到最近安全 tone）；
  /// 曜黑（[pureBlackDark]）在深色下覆写 surface 为 AMOLED 纯黑；
  /// 四滑杆写入 token 供组件层消费。
  ///
  /// [enforceAa]=false 时返回护栏降级前的原始推导（§8.4 编辑器实时审计用：
  /// 展示用户草稿的真实对比度，不达标红字提示且禁止保存——护栏兜底降级只
  /// 发生在装配层，编辑器必须如实反映草稿本身）。
  SlimcaTheme toSlimcaTheme(Brightness brightness, {bool enforceAa = true}) {
    final SlimcaSeedSet seeds = brightness == Brightness.dark
        ? darkSeeds
        : lightSeeds;
    final SlimcaPalette palette = SlimcaPalette.fromSeeds(
      kcalSeed: seeds.kcal,
      moneySeed: seeds.money,
      dangerSeed: seeds.danger,
      neutralSeed: seeds.neutral,
    );
    SlimcaTheme tokens = SlimcaTheme.fromPalette(palette, brightness);
    if (enforceAa) {
      tokens = enforceSlimcaAa(tokens);
    }
    if (brightness == Brightness.dark && pureBlackDark) {
      // §8.3「曜黑（AMOLED 纯黑独立开关）」：surface 纯黑，次级/卡面取
      // 极低 tone；背景为底色非前景，不参与 AA 护栏校验。
      tokens = tokens.copyWith(
        surface: const Color(0xFF000000),
        surfaceMuted: palette.neutralTone(8),
        surfaceCard: palette.neutralTone(12),
      );
    }
    return tokens.copyWith(
      radiusScale: radiusScale,
      density: density,
      fontScale: fontScale,
      motionScale: motionScale,
    );
  }

  /// 派生动效 token（§9.2 MotionConfig.forLevel，滑杆系数叠加）。
  MotionConfig toMotionConfig() =>
      MotionConfig.forLevel(motionLevel, motionScale: motionScale);

  // ── 序列化：tokens JSON（语义 token 集，§5.6⑳ tokens 列）────────────

  /// tokens 列 JSON（浅/深种子色 + 四滑杆 + AMOLED 开关）。
  Map<String, Object?> toTokensJson() => <String, Object?>{
    'light': lightSeeds.toJson(),
    'dark': darkSeeds.toJson(),
    'radiusScale': radiusScale,
    'density': density,
    'fontScale': fontScale,
    'motionScale': motionScale,
    'pureBlackDark': pureBlackDark,
  };

  factory ThemeProfile.fromTokensJson(
    Map<String, Object?> json, {
    required String id,
    required String name,
    MotionLevel motionLevel = MotionLevel.full,
    String? fontId,
    bool isPreset = false,
    int sort = 0,
  }) => ThemeProfile(
    id: id,
    name: name,
    lightSeeds: SlimcaSeedSet.fromJson(
      (json['light'] as Map<String, Object?>?) ?? const <String, Object?>{},
    ),
    darkSeeds: SlimcaSeedSet.fromJson(
      (json['dark'] as Map<String, Object?>?) ?? const <String, Object?>{},
    ),
    radiusScale: clampRadiusScale(
      (json['radiusScale'] as num?)?.toDouble() ?? 1.0,
    ),
    density: clampDensity((json['density'] as num?)?.toDouble() ?? 1.0),
    fontScale: clampFontScale((json['fontScale'] as num?)?.toDouble() ?? 1.0),
    motionScale: (json['motionScale'] as num?)?.toDouble() ?? 1.0,
    motionLevel: motionLevel,
    fontId: fontId,
    isPreset: isPreset,
    sort: sort,
    pureBlackDark: (json['pureBlackDark'] as bool?) ?? false,
  );

  // ── 序列化：theme_profiles 行形状（§5.6⑳，键名与 drift 行 JSON 对齐）──

  /// 行快照 JSON：键名对齐 core_db `ThemeProfile.fromJson`（camelCase）。
  /// sync 公共列不携带（由 core_db/同步层补齐，§5.1）。
  Map<String, Object?> toJsonRow() => <String, Object?>{
    'id': id,
    'name': name,
    'tokens': jsonEncode(toTokensJson()),
    'motionLevel': motionLevel.name,
    'fontId': fontId,
    'isPreset': isPreset,
    'sort': sort,
  };

  /// [toJsonRow] 的逆运算；tokens 兼容字符串（行形状）与 Map（直传 payload）。
  factory ThemeProfile.fromJsonRow(Map<String, Object?> json) {
    final Object? tokensRaw = json['tokens'];
    final Map<String, Object?> tokensJson = tokensRaw is String
        ? (jsonDecode(tokensRaw) as Map<String, Object?>)
        : (tokensRaw as Map<String, Object?>?) ?? const <String, Object?>{};
    return ThemeProfile.fromTokensJson(
      tokensJson,
      id: json['id'] as String,
      name: json['name'] as String,
      motionLevel: _parseMotionLevel(json['motionLevel'] as String?),
      fontId: json['fontId'] as String?,
      isPreset: (json['isPreset'] as bool?) ?? false,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
    );
  }

  static MotionLevel _parseMotionLevel(String? wire) =>
      MotionLevel.values.asNameMap()[wire] ?? MotionLevel.full;

  /// 拷贝（滑杆经量程钳制）。
  ThemeProfile copyWith({
    String? id,
    String? name,
    SlimcaSeedSet? lightSeeds,
    SlimcaSeedSet? darkSeeds,
    double? radiusScale,
    double? density,
    double? fontScale,
    double? motionScale,
    MotionLevel? motionLevel,
    String? fontId,
    bool? isPreset,
    int? sort,
    bool? pureBlackDark,
  }) => ThemeProfile(
    id: id ?? this.id,
    name: name ?? this.name,
    lightSeeds: lightSeeds ?? this.lightSeeds,
    darkSeeds: darkSeeds ?? this.darkSeeds,
    radiusScale: radiusScale != null
        ? clampRadiusScale(radiusScale)
        : this.radiusScale,
    density: density != null ? clampDensity(density) : this.density,
    fontScale: fontScale != null ? clampFontScale(fontScale) : this.fontScale,
    motionScale: motionScale ?? this.motionScale,
    motionLevel: motionLevel ?? this.motionLevel,
    fontId: fontId ?? this.fontId,
    isPreset: isPreset ?? this.isPreset,
    sort: sort ?? this.sort,
    pureBlackDark: pureBlackDark ?? this.pureBlackDark,
  );

  /// 主题包切换插值（§8.3 lerp 口径；名称/档位等离散字段按惯例前半程取 a、
  /// 后半程取 b，与 MotionConfig.lerp 同规则）。种子插值仅供过渡展示，
  /// 终态 token 由 [toSlimcaTheme] 重推导。
  ThemeProfile lerp(ThemeProfile other, double t) => ThemeProfile(
    id: t <= 0.5 ? id : other.id,
    name: t <= 0.5 ? name : other.name,
    lightSeeds: lightSeeds.lerp(other.lightSeeds, t),
    darkSeeds: darkSeeds.lerp(other.darkSeeds, t),
    radiusScale: lerpDouble(radiusScale, other.radiusScale, t)!,
    density: lerpDouble(density, other.density, t)!,
    fontScale: lerpDouble(fontScale, other.fontScale, t)!,
    motionScale: lerpDouble(motionScale, other.motionScale, t)!,
    motionLevel: t <= 0.5 ? motionLevel : other.motionLevel,
    fontId: t <= 0.5 ? fontId : other.fontId,
    isPreset: t <= 0.5 ? isPreset : other.isPreset,
    sort: t <= 0.5 ? sort : other.sort,
    pureBlackDark: t <= 0.5 ? pureBlackDark : other.pureBlackDark,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThemeProfile &&
          other.id == id &&
          other.name == name &&
          other.lightSeeds == lightSeeds &&
          other.darkSeeds == darkSeeds &&
          other.radiusScale == radiusScale &&
          other.density == density &&
          other.fontScale == fontScale &&
          other.motionScale == motionScale &&
          other.motionLevel == motionLevel &&
          other.fontId == fontId &&
          other.isPreset == isPreset &&
          other.sort == sort &&
          other.pureBlackDark == pureBlackDark;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    lightSeeds,
    darkSeeds,
    radiusScale,
    density,
    fontScale,
    motionScale,
    motionLevel,
    fontId,
    isPreset,
    sort,
    pureBlackDark,
  );

  @override
  String toString() => 'ThemeProfile($id, $name, motionLevel: $motionLevel)';
}
