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
