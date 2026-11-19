/// WCAG AA 对比度护栏（§8.1/§8.3/§8.4）。
///
/// 设计文档要求：主题编辑器对「关键前景/背景对（正文、金额、热量数字）」做
/// WCAG AA 实时校验，不达标的主题包禁止保存（§8.4）；运行时 buildTheme 前
/// 校验语义 token 组合，不达标自动降级到最近安全 tone（§8.3 护栏兜底）。
///
/// 算法（两段式）：
/// 1. 校验 [computeContrastRatio]：WCAG 相对亮度
///    L = 0.2126R + 0.7152G + 0.0722B（sRGB 线性化，Flutter `Color.computeLuminance`），
///    对比度 = (L亮+0.05) / (L暗+0.05)，∈ [1, 21]。
/// 2. 降级 [resolveAaSafeColor]：固定前景色的 HCT 色相/饱和度（保双主色锚定 §8.2），
///    以种子色重建 TonalPalette 后沿 tone 轴逐级搜索：
///    - 主方向 = 远离背景明度（浅底压暗 / 深底提亮，维持文本层级语义）；
///    - 逐 tone（步长 1）取候选色测对比度，首个达标 tone 即「最近安全 tone」；
///    - 主方向耗尽仍未达标 → 反方向逐 tone 搜索（应对中明度背景的病态组合）；
///    - 双向耗尽 → 取 tone 0/100 中远离背景者（对比度极限兜底）。
library;

import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

import 'slimca_theme.dart';

/// WCAG AA 正文阈值（§8.3 关键前景/背景对：正文、金额、热量数字）。
const double kAaTextContrast = 4.5;

/// WCAG AA 大号文本/UI 组件阈值（onPrimary/primary 交互锚点对，§8.2）。
const double kAaUiContrast = 3.0;

/// WCAG 对比度（§8.3）：(L亮+0.05)/(L暗+0.05)。
double computeContrastRatio(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double lighter = la > lb ? la : lb;
  final double darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 把前景色沿 tone 轴移动到相对 [bg] 达标 [threshold] 的最近安全 tone；
/// 已达标则原样返回。色相/饱和度由 TonalPalette 全程保持（§8.2 双主色锚定）。
Color resolveAaSafeColor(
  Color fg,
  Color bg, {
  double threshold = kAaTextContrast,
}) {
  if (computeContrastRatio(fg, bg) >= threshold) return fg;

  final Hct fgHct = Hct.fromInt(fg.toARGB32());
  final TonalPalette palette = TonalPalette.fromHct(fgHct);
  final int baseTone = fgHct.tone.round().clamp(0, 100);
  final double bgLum = bg.computeLuminance();

  // 主方向：前景明度远离背景明度（浅底压暗 / 深底提亮）。
  final int primaryStep =
      Color(palette.get(baseTone)).computeLuminance() < bgLum ? 1 : -1;
  final int secondaryStep = -primaryStep;

  Color? walk(int step) {
    for (int k = 1; k <= 100; k++) {
      final int tone = baseTone + step * k;
      if (tone < 0 || tone > 100) return null; // 该方向耗尽
      final Color candidate = Color(palette.get(tone));
      if (computeContrastRatio(candidate, bg) >= threshold) return candidate;
    }
    return null;
  }

  final Color? primary = walk(primaryStep);
  if (primary != null) return primary;
  final Color? secondary = walk(secondaryStep);
  if (secondary != null) return secondary;
  // 双向耗尽（理论上仅背景中明度且前景色域极窄时出现）：取远离背景的极值 tone。
  return Color(palette.get(bgLum >= 0.5 ? 0 : 100));
}

/// 关键前景/背景对清单（§8.3「正文、金额、热量数字」+ 交互锚点）。
///
/// [fg]/[bg] 从语义 token 取值；[apply] 输出降级后的新 token 集（仅替换 fg）。
/// warn/success 为置信度三色点/图标语义（非正文），不进护栏清单。
class SlimcaAaPairSpec {
  const SlimcaAaPairSpec({
    required this.label,
    required this.threshold,
    required this.fg,
    required this.bg,
    required this.apply,
  });

  /// 展示用对名（编辑器 AA 反馈条直接呈现，§8.4）。
  final String label;

  /// 该对的达标阈值（正文 4.5 / UI 3.0）。
  final double threshold;

  final Color Function(SlimcaTheme tokens) fg;

  final Color Function(SlimcaTheme tokens) bg;

  final SlimcaTheme Function(SlimcaTheme tokens, Color safe) apply;
}

/// §8.3 关键对：正文（全屏底 + 卡面底）、金额、热量数字、危险提示，
/// 以及 onPrimary/primary 交互锚点（UI 阈值）。
final List<SlimcaAaPairSpec> kSlimcaAaPairSpecs = <SlimcaAaPairSpec>[
  SlimcaAaPairSpec(
    label: '正文 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.onSurface,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(onSurface: c),
  ),
  SlimcaAaPairSpec(
    label: '正文 / 页面底',
    threshold: kAaTextContrast,
    fg: (t) => t.onSurface,
    bg: (t) => t.surface,
    apply: (t, c) => t.copyWith(onSurface: c),
  ),
  SlimcaAaPairSpec(
    label: '次级正文 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.onSurfaceMuted,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(onSurfaceMuted: c),
  ),
  SlimcaAaPairSpec(
    label: '支出金额 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.moneyOut,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(moneyOut: c),
  ),
  SlimcaAaPairSpec(
    label: '收入金额 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.moneyIn,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(moneyIn: c),
  ),
  SlimcaAaPairSpec(
    label: '摄入热量 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.kcalIn,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(kcalIn: c),
  ),
  SlimcaAaPairSpec(
    label: '消耗热量 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.kcalOut,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(kcalOut: c),
  ),
  SlimcaAaPairSpec(
    label: '净热量 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.net,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(net: c),
  ),
  SlimcaAaPairSpec(
    label: '危险提示 / 卡面',
    threshold: kAaTextContrast,
    fg: (t) => t.danger,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(danger: c),
  ),
  // 底栏重设计拍板（定型条目《UI-规范与重设计》§5 #14、§2.2 增补段）：
  // 中央按钮由「独立突出元素（FAB 可豁免）」转入凹槽承接容器语境，其与
  // 栏面（surfaceCard）按 M3 color-contrast 容器类 3:1 校验；outline 对
  // 守卫卡面语境的描边通用色（输入框/分隔线），并为底栏 P2 描边兜底
  // （Material shape side）预留色源——描边当前未接线，仅口径预留。
  // 放在 onPrimary/primary 锚点对之前——primary 若被降级，onPrimary 随新
  // primary 复检（顺序敏感，勿后移）。
  SlimcaAaPairSpec(
    label: '主色钮面 / 底栏卡面',
    threshold: kAaUiContrast,
    fg: (t) => t.primary,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(primary: c),
  ),
  SlimcaAaPairSpec(
    label: '底栏描边 / 底栏卡面',
    threshold: kAaUiContrast,
    fg: (t) => t.outline,
    bg: (t) => t.surfaceCard,
    apply: (t, c) => t.copyWith(outline: c),
  ),
  SlimcaAaPairSpec(
    label: '主色按钮前景 / 主色',
    threshold: kAaUiContrast,
    fg: (t) => t.onPrimary,
    bg: (t) => t.primary,
    apply: (t, c) => t.copyWith(onPrimary: c),
  ),
];

/// 单对校验结果（§8.4 编辑器 AA 反馈条的数据模型）。
class SlimcaAaPairResult {
  const SlimcaAaPairResult({
    required this.label,
    required this.ratio,
    required this.threshold,
    required this.pass,
    required this.fg,
    required this.bg,
  });

  final String label;
  final double ratio;
  final double threshold;
  final bool pass;
  final Color fg;
  final Color bg;

  @override
  String toString() =>
      'SlimcaAaPairResult($label, ${ratio.toStringAsFixed(2)}/${threshold.toStringAsFixed(1)}, '
      'pass: $pass)';
}

/// 对语义 token 集做 AA 审计（只读，§8.4 实时校验入口）。
/// 顺序同 [kSlimcaAaPairSpecs]；对内不改动 token。
List<SlimcaAaPairResult> auditSlimcaAa(SlimcaTheme tokens) => kSlimcaAaPairSpecs
    .map(
      (SlimcaAaPairSpec spec) => SlimcaAaPairResult(
        label: spec.label,
        ratio: computeContrastRatio(spec.fg(tokens), spec.bg(tokens)),
        threshold: spec.threshold,
        pass:
            computeContrastRatio(spec.fg(tokens), spec.bg(tokens)) >=
            spec.threshold,
        fg: spec.fg(tokens),
        bg: spec.bg(tokens),
      ),
    )
    .toList(growable: false);

/// 护栏执行：不达标对的前景自动降级到最近安全 tone（§8.3），返回新 token 集。
///
/// 幂等：已达标 token 原样返回，反复执行结果稳定。调用点为装配出口——
/// buildTheme（semantic 参数兜底）、ThemeProfile.toSlimcaTheme（主题包派生）、
/// SlimcaDynamicThemeMapper.map（平台动态色）——SlimcaTheme.light/dark 静态
/// 基线保持 W1 零漂移，不在此回写。bg 取自当前 token 集，
/// 曜黑纯黑等特殊表面天然参与校验。
SlimcaTheme enforceSlimcaAa(SlimcaTheme tokens) {
  SlimcaTheme current = tokens;
  for (final SlimcaAaPairSpec spec in kSlimcaAaPairSpecs) {
    final Color fg = spec.fg(current);
    final Color bg = spec.bg(current);
    if (computeContrastRatio(fg, bg) >= spec.threshold) continue;
    current = spec.apply(
      current,
      resolveAaSafeColor(fg, bg, threshold: spec.threshold),
    );
  }
  return current;
}
