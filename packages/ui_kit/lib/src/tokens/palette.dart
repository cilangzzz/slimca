import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// 第 1 层：原始色板（§8.2）。
///
/// 种子色 → material_color_utilities HCT tonal palette，自动生成 0-100 色阶。
/// 组件层（第 3 层）禁止直接引用本层，只允许引用第 2 层语义 token（§8.2 第 3 层约束）。
///
/// 双主色锚定规则（§8.2）：健康绿（热量）与暖橘（金额）的色相在所有主题包中固定，
/// 只允许调明度/饱和度——「绿是吃、橘是钱」的认知不随换肤改变（§8.1）。
final class SlimcaPalette {
  SlimcaPalette._(this.kcal, this.money, this.danger, this.neutral);

  /// 双主色锚定的 HCT 色相/饱和度（§8.2）。
  /// 内置 6 主题包（§8.3：墨/纸/霓虹/奶油/森野/曜黑）换肤时只允许在此锚点上
  /// 调整明度/饱和度，不允许跨色相；neutral 色相为中性蓝灰基底。
  static const double kcalHue = 150; // 健康绿（热量语义锚定）
  static const double kcalChroma = 55;
  static const double moneyHue = 62; // 暖橘（金额语义锚定）
  static const double moneyChroma = 68;
  static const double dangerHue = 27; // 危险红
  static const double dangerChroma = 72;
  static const double neutralHue = 250; // 中性基底
  static const double neutralChroma = 8;

  /// 内置默认色板（浅/深默认语义 token 的推导来源，§8.3 主题包仅覆盖第 2 层）。
  static final SlimcaPalette defaults = SlimcaPalette._(
    TonalPalette.of(kcalHue, kcalChroma),
    TonalPalette.of(moneyHue, moneyChroma),
    TonalPalette.of(dangerHue, dangerChroma),
    TonalPalette.of(neutralHue, neutralChroma),
  );

  final TonalPalette kcal; // 热量语义色阶（健康绿锚定）
  final TonalPalette money; // 金额语义色阶（暖橘锚定）
  final TonalPalette danger; // 危险状态色阶
  final TonalPalette neutral; // 中性背景/文字色阶

  /// 从种子色生成色板（主题编辑器照片取色/色轮入口，§8.4 P1）。
  SlimcaPalette.fromSeeds({
    required Color kcalSeed,
    required Color moneySeed,
    required Color dangerSeed,
    required Color neutralSeed,
  }) : this._(
         TonalPalette.fromHct(Hct.fromInt(kcalSeed.toARGB32())),
         TonalPalette.fromHct(Hct.fromInt(moneySeed.toARGB32())),
         TonalPalette.fromHct(Hct.fromInt(dangerSeed.toARGB32())),
         TonalPalette.fromHct(Hct.fromInt(neutralSeed.toARGB32())),
       );

  Color kcalTone(int tone) => Color(kcal.get(tone));

  Color moneyTone(int tone) => Color(money.get(tone));

  Color dangerTone(int tone) => Color(danger.get(tone));

  Color neutralTone(int tone) => Color(neutral.get(tone));
}
