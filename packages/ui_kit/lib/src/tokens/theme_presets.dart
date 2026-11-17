/// 6 套内置主题包（§8.3「6 套内置包：墨 / 纸 / 霓虹 / 奶油 / 森野 / 曜黑
/// （AMOLED 纯黑独立开关）」）。
///
/// 双主色锚定（§8.2）：全部包的 kcal 种子色相固定 150（健康绿=热量）、
/// money 种子色相固定 62（暖橘=金额），只允许调饱和度/明度（chroma/tone）；
/// neutral / danger 色相可在包间变化（中性基底与状态色不参与锚定）。
/// 种子色一律由 Hct.from(色相, 饱和度, 明度) 生成，保证包定义即锚定自证。
///
/// 浅/深种子差异：浅色侧取中低明度（tone 40±5）、深色侧取高明度（tone 80±5），
/// 与 M3 双模式主色惯例一致；tonal palette 覆盖 0-100 全色阶，token 推导
/// （SlimcaTheme.fromPalette）按亮度自动选 tone。
library;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'theme_profile.dart';

/// 由 HCT 三要素构造种子色（编辑器色轮/预设共用口径，§8.4）。
Color seedFromHct(double hue, double chroma, double tone) =>
    Color(Hct.from(hue, chroma, tone).toInt());

/// §8.2 双主色锚定色相（与 SlimcaPalette 常量同源，勿漂移）。
const double kKcalAnchorHue = 150; // 健康绿（热量）
const double kMoneyAnchorHue = 62; // 暖橘（金额）

/// 内置 6 主题包清单（§8.3；id 稳定、随 theme_profiles 同步真值入库）。
///
/// 命名：mo=墨（默认冷灰基底）、zhi=纸（暖纸底）、neon=霓虹（高饱和深底）、
/// cream=奶油（低饱和暖底）、senye=森野（绿调基底）、yaohei=曜黑（AMOLED 纯黑）。
final List<ThemeProfile> kSlimcaPresetThemeProfiles = <ThemeProfile>[
  _preset(
    id: 'preset-mo',
    name: '墨',
    sort: 0,
    neutralHue: 250,
    neutralChroma: 8,
    kcalChroma: 55,
    moneyChroma: 68,
    dangerChroma: 72,
  ),
  _preset(
    id: 'preset-zhi',
    name: '纸',
    sort: 1,
    neutralHue: 80,
    neutralChroma: 6,
    kcalChroma: 48,
    moneyChroma: 60,
    dangerChroma: 64,
  ),
  _preset(
    id: 'preset-neon',
    name: '霓虹',
    sort: 2,
    neutralHue: 265,
    neutralChroma: 12,
    kcalChroma: 70,
    moneyChroma: 80,
    dangerChroma: 80,
  ),
  _preset(
    id: 'preset-cream',
    name: '奶油',
    sort: 3,
    neutralHue: 70,
    neutralChroma: 10,
    kcalChroma: 45,
    moneyChroma: 55,
    dangerChroma: 60,
  ),
  _preset(
    id: 'preset-senye',
    name: '森野',
    sort: 4,
    neutralHue: 145,
    neutralChroma: 7,
    kcalChroma: 60,
    moneyChroma: 65,
    dangerChroma: 70,
  ),
  _preset(
    id: 'preset-yaohei',
    name: '曜黑',
    sort: 5,
    neutralHue: 250,
    neutralChroma: 4,
    kcalChroma: 60,
    moneyChroma: 75,
    dangerChroma: 72,
    pureBlackDark: true, // §8.3 AMOLED 纯黑独立开关
  ),
];

/// 按 §8.2 锚定规则组装单个内置包（浅/深种子只差 tone，色相/饱和度同侧共享）。
ThemeProfile _preset({
  required String id,
  required String name,
  required int sort,
  required double neutralHue,
  required double neutralChroma,
  required double kcalChroma,
  required double moneyChroma,
  required double dangerChroma,
  bool pureBlackDark = false,
}) {
  final SlimcaSeedSet light = SlimcaSeedSet(
    kcal: seedFromHct(kKcalAnchorHue, kcalChroma, 40),
    money: seedFromHct(kMoneyAnchorHue, moneyChroma, 45),
    danger: seedFromHct(27, dangerChroma, 45),
    neutral: seedFromHct(neutralHue, neutralChroma, 40),
  );
  final SlimcaSeedSet dark = SlimcaSeedSet(
    kcal: seedFromHct(kKcalAnchorHue, kcalChroma, 80),
    money: seedFromHct(kMoneyAnchorHue, moneyChroma, 80),
    danger: seedFromHct(27, dangerChroma, 80),
    neutral: seedFromHct(neutralHue, neutralChroma, 80),
  );
  return ThemeProfile(
    id: id,
    name: name,
    lightSeeds: light,
    darkSeeds: dark,
    isPreset: true,
    sort: sort,
    pureBlackDark: pureBlackDark,
  );
}

/// 按 id 查内置包（找不到返回 null——自定义包不在内置清单）。
ThemeProfile? presetThemeProfileById(String id) {
  for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
    if (p.id == id) return p;
  }
  return null;
}
