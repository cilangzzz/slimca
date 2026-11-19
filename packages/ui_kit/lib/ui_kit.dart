/// Slimca UI 基建（§10.4 packages/ui_kit）：
/// 三层设计 token（§8.2）+ MotionConfig（§9.2）+ P0 关键转场库（§9.3）+ 语义组件。
///
/// 约束（§8.2 第 3 层 / §9.2）：上层包只允许从本库导出的语义 token、MotionConfig
/// 与语义组件取样式，禁止裸色值/裸时长；隐式动画仅限微交互（§9.5）。
library;

// ── 三层设计 token（§8.1-§8.4）────────────────────────────────────
export 'src/tokens/palette.dart';
export 'src/tokens/slimca_theme.dart';
export 'src/tokens/motion_config.dart';
export 'src/tokens/build_theme.dart';
// W16（§11.2）：WCAG AA 护栏 / 主题包模型与 6 内置包 / dynamic_color 适配
export 'src/tokens/contrast.dart';
export 'src/tokens/theme_profile.dart';
export 'src/tokens/theme_presets.dart';
export 'src/tokens/dynamic_color.dart';
// W17 插曲（UI-规范与重设计.md §2.2）：约束 token 层——间距尺度 + 尺寸/命中/
// 行高/圆角/状态层
export 'src/tokens/slimca_spacing.dart';
export 'src/tokens/slimca_sizes.dart';

// ── P0 关键转场（§9.3 清单：#1 级联 / #2 共享轴 / #3 弹簧抽屉 /
//    #4 count-up+环 sweep+置信度 pulse / #5 Hero 飞入 / #10 主题 morph）
export 'src/transitions/shared_axis.dart';
export 'src/transitions/spring_sheet.dart';
export 'src/transitions/stagger.dart';
export 'src/transitions/count_up.dart';
export 'src/transitions/breath.dart';
export 'src/transitions/hero_flight.dart';
export 'src/transitions/theme_morph.dart';
export 'src/transitions/confidence_dot.dart';
export 'src/transitions/money_count_up.dart';

// ── 语义组件（§3.2 核心视觉）─────────────────────────────────────
export 'src/components/calorie_ring.dart';
export 'src/components/confirm_card.dart';
// W16（§8.4）：主题编辑器面板
export 'src/components/theme_editor_panel.dart';
// W17 插曲（UI-规范与重设计.md §3/§4）：日历组件族 + 菜单组件族
export 'src/components/calendar_strip.dart';
export 'src/components/month_grid.dart';
export 'src/components/calendar.dart';
export 'src/components/menu.dart';
// W17 插曲第二波（底栏重设计拍板，定型条目见《UI-规范与重设计》§2.2 增补段）：
// 花瓣形 FAB ShapeBorder（M3 Expressive cookie，拍板推导）——凹槽 cradle
// 一体化底栏的中央按钮形态
export 'src/components/cookie_fab_shape.dart';
