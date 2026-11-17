import 'dart:math' as math;
import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

// 本库公开 API（MotionConfig 的曲线 token、SlimcaSpring.curve）引用 flutter 的
// [Curve]：随库导出，使调用方可直接引用该类型而无需自行 import material。
export 'package:flutter/animation.dart' show Curve;

/// 用户可调动效档位（§9.2 MotionLevel）。
enum MotionLevel {
  /// 全部转场降为 100ms 淡入淡出（§9.2/§9.6），尊重系统「减弱动态效果」。
  off,

  /// 减弱档：全部时长按 0.6x 缩放（§8.3 可及性）。
  reduced,

  /// 完整动效（§9.2 token 表原值）。
  full,
}

/// MotionLevel → 动效强度系数（§8.3：系统减弱动态效果自动降至 0.6x；
/// off 不走系数缩放，由 [MotionConfig.off] 直接给出 100ms 淡入淡出）。
extension MotionLevelScale on MotionLevel {
  double get scale => switch (this) {
    MotionLevel.off => 0.0,
    MotionLevel.reduced => 0.6,
    MotionLevel.full => 1.0,
  };
}

/// 单自由度弹簧（§10.1「自研单自由度弹簧（参数入 MotionConfig）」）。
///
/// 以「整定时长 + 阻尼比」表达（§9.2 spring.* 规格：snappy 220ms ζ=1.0 不回弹、
/// soft 400ms ζ=0.85 容器变形/环推进），物理参数按整定残差推导：
/// ζ·ωn·T = 2π ⇒ T 时刻残差 ≈ e^(-2π) ≈ 0.19%，即整定时长内收敛。
final class SlimcaSpring {
  const SlimcaSpring({
    required this.settleDuration,
    required this.dampingRatio,
    this.mass = 1.0,
  }) : assert(
         dampingRatio > 0 && dampingRatio <= 1.0,
         '阻尼比限 (0, 1]：轻阻尼回弹到临界阻尼',
       ),
       assert(mass > 0);
  // settleDuration 必须为正：该约束放在 [_settleSeconds] 内断言——
  // const 构造里对 Duration 的运算/取属性都不是常量表达式，
  // 而 token 表（static const MotionConfig.full 等）必须 const 构造。

  /// 约 2% 整定时长（§9.2 spring.* 的时长规格）。
  final Duration settleDuration;

  /// 阻尼比 ζ：1.0 临界（不回弹），<1 欠阻尼（轻微回弹）。
  final double dampingRatio;

  final double mass;

  double get _settleSeconds {
    assert(settleDuration > Duration.zero, '整定时长必须为正（§9.2 spring.* 规格）');
    return settleDuration.inMicroseconds / Duration.microsecondsPerSecond;
  }

  /// 无阻尼角频率 ωn。
  double get omegaN => 2 * math.pi / (dampingRatio * _settleSeconds);

  double get stiffness => omegaN * omegaN * mass;

  double get damping => 2 * dampingRatio * math.sqrt(stiffness * mass);

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: mass,
    stiffness: stiffness,
    ratio: dampingRatio,
  );

  /// 弹簧模拟（控制器驱动的场景，如拖拽速度继承 §9.3#3）。
  SpringSimulation simulation({
    required double start,
    required double end,
    double velocity = 0.0,
    Tolerance tolerance = Tolerance.defaultTolerance,
  }) =>
      SpringSimulation(description, start, end, velocity, tolerance: tolerance);

  /// 弹簧的 [Curve] 形态：把 [0,1] 的动画 t 映射到整定时长的解析响应。
  /// 用于路由/隐式动画（不便直接跑 Simulation 的场景），与 [simulation] 数值一致。
  Curve get curve => SpringCurve(this);

  SlimcaSpring scaled(double factor) => SlimcaSpring(
    settleDuration: Duration(
      microseconds: (settleDuration.inMicroseconds * factor).round(),
    ),
    dampingRatio: dampingRatio,
    mass: mass,
  );

  SlimcaSpring lerp(SlimcaSpring other, double t) => SlimcaSpring(
    settleDuration: Duration(
      microseconds: lerpDouble(
        settleDuration.inMicroseconds,
        other.settleDuration.inMicroseconds,
        t,
      )!.round(),
    ),
    dampingRatio: lerpDouble(dampingRatio, other.dampingRatio, t)!,
    mass: lerpDouble(mass, other.mass, t)!,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SlimcaSpring &&
        other.settleDuration == settleDuration &&
        other.dampingRatio == dampingRatio &&
        other.mass == mass;
  }

  @override
  int get hashCode => Object.hash(settleDuration, dampingRatio, mass);
}

/// [SlimcaSpring.curve] 的实现：解析二阶响应（欠阻尼含轻微回弹，临界阻尼无回弹）。
class SpringCurve extends Curve {
  const SpringCurve(this.spring);

  final SlimcaSpring spring;

  @override
  double transform(double t) {
    final double time = clampDouble(t, 0.0, 1.0) * spring._settleSeconds;
    final double z = spring.dampingRatio;
    final double wn = spring.omegaN;
    if (z < 1.0) {
      // 欠阻尼：x(t) = 1 − e^(−ζωn·t)·(cos(ωd·t) + (ζ/√(1−ζ²))·sin(ωd·t))
      final double wd = wn * math.sqrt(1 - z * z);
      return 1 -
          math.exp(-z * wn * time) *
              (math.cos(wd * time) +
                  (z / math.sqrt(1 - z * z)) * math.sin(wd * time));
    }
    // 临界阻尼：x(t) = 1 − e^(−ωn·t)·(1 + ωn·t)
    return 1 - math.exp(-wn * time) * (1 + wn * time);
  }
}

/// 动效 token（§9.2「MotionConfig（动效 token 挂进主题）」）。
///
/// 所有动效只引用 token 不写裸值（§9.2 lint 约束）：业务层通过 [MotionConfigBuildContext.motion]
/// 读取本扩展，禁止裸时长/裸曲线；隐式动画仅限微交互（§9.5）。
class MotionConfig extends ThemeExtension<MotionConfig> {
  const MotionConfig({
    required this.level,
    required this.durXs,
    required this.durS,
    required this.durM,
    required this.durL,
    required this.durXl,
    required this.staggerInterval,
    required this.countUpDuration,
    required this.themeMorphDuration,
    required this.offFadeDuration,
    required this.springSnappy,
    required this.springSoft,
    required this.curveEaseOutExpo,
    required this.curveStandard,
    required this.curveEmphasized,
    // W17 插曲（UI-规范 §2.2 新增 token 表）：展开/收起曲线对 + effects 曲线
    required this.curveExpand,
    required this.curveCollapse,
    required this.curveEffectsStandard,
  });

  /// 动效档位（§9.2 MotionLevel）：off/reduced/full。
  final MotionLevel level;

  /// dur.xs：微反馈（按压涟漪，§9.2 token 表）。
  final Duration durXs;

  /// dur.s：chip / 勾选。
  final Duration durS;

  /// dur.m：卡片上浮（级联间隔另见 [staggerInterval]）。
  final Duration durM;

  /// dur.l：抽屉 / 页面 / 共享轴。
  final Duration durL;

  /// dur.xl：落库飞入 / 容器变换。
  final Duration durXl;

  /// §2.3/§9.3#1：卡片墙 80ms 级联上浮的级联间隔。
  final Duration staggerInterval;

  /// §9.3#4：AI count-up 时长。
  final Duration countUpDuration;

  /// §9.3#10：主题切换全屏 morph 时长。
  final Duration themeMorphDuration;

  /// §9.2 MotionLevel=off / §9.6：降级淡入淡出时长。
  final Duration offFadeDuration;

  /// spring.snappy：交互跟随（不回弹）。
  final SlimcaSpring springSnappy;

  /// spring.soft：容器变形 / 环推进。
  final SlimcaSpring springSoft;

  /// §9.3#4：count-up 曲线 easeOutExpo。
  final Curve curveEaseOutExpo;

  /// 共享轴 / 页面级转场标准曲线（§9.3#2）。
  final Curve curveStandard;

  /// 容器变换曲线（§9.3#6 P1）。
  final Curve curveEmphasized;

  /// W17 插曲新增（UI-规范 §2.2/§1.2）：展开/进场段曲线 = M3 emphasized-decelerate
  /// `Cubic(0.05, 0.7, 0.1, 1.0)`（MotionTokens.kt 源码值）。语义：进场 ease-out、
  /// 出场 ease-in 的不对称规则（TDesign motion）的 M3 官方实现；首批使用方＝
  /// 周条→月网格展开、条目级联进场收尾（§5#13）。
  final Curve curveExpand;

  /// W17 插曲新增（UI-规范 §2.2/§1.2）：收起/出场段曲线 = M3 emphasized-accelerate
  /// `Cubic(0.3, 0.0, 0.8, 0.15)`（MotionTokens.kt 源码值）。
  final Curve curveCollapse;

  /// W17 插曲新增（UI-规范 §2.2/§1.2）：颜色/透明度类动画专用曲线 = M3 Expressive
  /// default effects `Cubic(0.34, 0.80, 0.34, 1.00)`（m3 motion/overview/specs
  /// 原表；200ms 档配对）。这是「effects 禁过冲 / spatial 可过冲」官方判定线的
  /// 实现载体：选中态变色、展开交叉淡化等透明度动画一律引用本曲线。
  final Curve curveEffectsStandard;

  /// 从宿主 [ThemeData] 取 MotionConfig；未挂载时回退 full 档（§9.2）。
  ///
  /// W1 约定签名（apps/mobile/lib/app/theme.dart 依赖）：宿主层读取
  /// `MotionConfig.of(context)` 取 token，语义与 [MotionConfigBuildContext.motion]
  /// 一致、二者共用同一回退逻辑。
  static MotionConfig of(BuildContext context) =>
      Theme.of(context).extension<MotionConfig>() ??
      MotionConfig.forLevel(MotionLevel.full);

  /// §9.2 token 表原值（MotionLevel=full）。
  static const MotionConfig full = MotionConfig(
    level: MotionLevel.full,
    // dur.xs 微反馈（按压涟漪）
    durXs: Duration(milliseconds: 60),
    // dur.s chip / 勾选
    durS: Duration(milliseconds: 120),
    // dur.m 卡片上浮（§9.3#1 的级联间隔另见 staggerInterval）
    durM: Duration(milliseconds: 180),
    // dur.l 抽屉 / 页面 / 共享轴（§2.3 切日 ≤280ms）
    durL: Duration(milliseconds: 280),
    // dur.xl 落库飞入 / 容器变换（§9.3#5 ≤450ms）
    durXl: Duration(milliseconds: 450),
    // §2.3/§9.3#1：卡片墙 80ms 级联上浮的级联间隔（§9.2 dur.m 为单卡上浮时长）
    staggerInterval: Duration(milliseconds: 80),
    // §9.3#4：AI count-up 800ms
    countUpDuration: Duration(milliseconds: 800),
    // §9.3#10：主题切换全屏 morph 300ms
    themeMorphDuration: Duration(milliseconds: 300),
    // §9.2 MotionLevel=off / §9.6：降级淡入淡出时长
    offFadeDuration: Duration(milliseconds: 100),
    // spring.snappy：交互跟随（不回弹），整定 220ms ≤ §2.3 抽屉 280ms 预算
    springSnappy: SlimcaSpring(
      settleDuration: Duration(milliseconds: 220),
      dampingRatio: 1.0,
    ),
    // spring.soft：容器变形 / 环推进（§9.3#4 环 sweep、§9.3#10 morph）
    springSoft: SlimcaSpring(
      settleDuration: Duration(milliseconds: 400),
      dampingRatio: 0.85,
    ),
    // §9.3#4：count-up 曲线 easeOutExpo
    curveEaseOutExpo: Curves.easeOutExpo,
    // 共享轴 / 页面级转场标准曲线（§9.3#2）
    curveStandard: Curves.easeInOutCubic,
    // 容器变换曲线（§9.3#6 P1）
    curveEmphasized: Curves.easeInOutCubicEmphasized,
    // W17 插曲（UI-规范 §2.2）：展开/进场 = emphasized-decelerate、
    // 收起/出场 = emphasized-accelerate（MotionTokens.kt 源码值，const 构造）
    curveExpand: Cubic(0.05, 0.7, 0.1, 1.0),
    curveCollapse: Cubic(0.3, 0.0, 0.8, 0.15),
    // W17 插曲（UI-规范 §2.2）：颜色/透明度专用 effects 曲线（禁过冲判定线）
    curveEffectsStandard: Cubic(0.34, 0.80, 0.34, 1.00),
  );

  /// 减弱档（§8.3）：全部时长 ×0.6。
  static const MotionConfig reduced = MotionConfig(
    level: MotionLevel.reduced,
    durXs: Duration(milliseconds: 36),
    durS: Duration(milliseconds: 72),
    durM: Duration(milliseconds: 108),
    durL: Duration(milliseconds: 168),
    durXl: Duration(milliseconds: 270),
    staggerInterval: Duration(milliseconds: 48),
    countUpDuration: Duration(milliseconds: 480),
    themeMorphDuration: Duration(milliseconds: 180),
    offFadeDuration: Duration(milliseconds: 100),
    springSnappy: SlimcaSpring(
      settleDuration: Duration(milliseconds: 132),
      dampingRatio: 1.0,
    ),
    springSoft: SlimcaSpring(
      settleDuration: Duration(milliseconds: 240),
      dampingRatio: 0.85,
    ),
    curveEaseOutExpo: Curves.easeOutExpo,
    curveStandard: Curves.easeInOutCubic,
    curveEmphasized: Curves.easeInOutCubicEmphasized,
    // 曲线不随 0.6x 缩放（缩放的是时长；UI-规范 §2.2「新增曲线对在 reduced 下
    // 随 0.6x 时长照常缩放」即时长缩放、曲线本体不变）
    curveExpand: Cubic(0.05, 0.7, 0.1, 1.0),
    curveCollapse: Cubic(0.3, 0.0, 0.8, 0.15),
    curveEffectsStandard: Cubic(0.34, 0.80, 0.34, 1.00),
  );

  /// 降级档（§9.2 MotionLevel=off / §9.6）：全部转场 100ms 淡入淡出。
  static const MotionConfig off = MotionConfig(
    level: MotionLevel.off,
    durXs: Duration(milliseconds: 100),
    durS: Duration(milliseconds: 100),
    durM: Duration(milliseconds: 100),
    durL: Duration(milliseconds: 100),
    durXl: Duration(milliseconds: 100),
    staggerInterval: Duration(milliseconds: 100),
    countUpDuration: Duration(milliseconds: 100),
    themeMorphDuration: Duration(milliseconds: 100),
    offFadeDuration: Duration(milliseconds: 100),
    springSnappy: SlimcaSpring(
      settleDuration: Duration(milliseconds: 100),
      dampingRatio: 1.0,
    ),
    springSoft: SlimcaSpring(
      settleDuration: Duration(milliseconds: 100),
      dampingRatio: 1.0,
    ),
    curveEaseOutExpo: Curves.linear,
    curveStandard: Curves.linear,
    curveEmphasized: Curves.linear,
    // 新增曲线对在 off 档照既有惯例线性化为 Curves.linear（UI-规范 §2.2，
    // 不改 offFadeDuration=100ms 语义）
    curveExpand: Curves.linear,
    curveCollapse: Curves.linear,
    curveEffectsStandard: Curves.linear,
  );

  /// 动效强度滑杆量程（§8.3：0.6x-1.5x，并尊重系统「减弱动态效果」）。
  static const double motionScaleMin = 0.6;
  static const double motionScaleMax = 1.5;

  /// §8.2 motionScale 滑杆与 §9.2 MotionLevel 的合成入口。
  ///
  /// App 启动时按 settings（§5.6「动效等级」）构造并传入 [buildTheme] 挂进主题；
  /// 转场 builder 只读 Theme 上的 [MotionConfig]，保持单一真值。
  static MotionConfig forLevel(MotionLevel level, {double motionScale = 1.0}) {
    switch (level) {
      // off 直接降级，不叠加滑杆（§9.6）
      case MotionLevel.off:
        return off;
      case MotionLevel.reduced:
        return reduced.scaled(motionScale);
      case MotionLevel.full:
        return full.scaled(motionScale);
    }
  }

  /// 时长/弹簧按系数缩放（曲线不变）；factor 被钳制到 §8.3 滑杆量程。
  MotionConfig scaled(double factor) {
    final double f = clampDouble(factor, motionScaleMin, motionScaleMax);
    if (f == 1.0) return this;
    return MotionConfig(
      level: level,
      durXs: _scale(durXs, f),
      durS: _scale(durS, f),
      durM: _scale(durM, f),
      durL: _scale(durL, f),
      durXl: _scale(durXl, f),
      staggerInterval: _scale(staggerInterval, f),
      countUpDuration: _scale(countUpDuration, f),
      themeMorphDuration: _scale(themeMorphDuration, f),
      offFadeDuration: offFadeDuration, // 降级淡入淡出固定 100ms
      springSnappy: springSnappy.scaled(f),
      springSoft: springSoft.scaled(f),
      curveEaseOutExpo: curveEaseOutExpo,
      curveStandard: curveStandard,
      curveEmphasized: curveEmphasized,
      // 曲线随 token 整体保留，不参与缩放（缩放仅作用于时长/弹簧）
      curveExpand: curveExpand,
      curveCollapse: curveCollapse,
      curveEffectsStandard: curveEffectsStandard,
    );
  }

  /// 缩放后按毫秒粒度取整（§9.2 时长 token 以整毫秒冻结；滑杆系数可为
  /// 小数——168ms × 1.3 = 218.4 → 218ms，保证装配出的时长仍落在表值粒度）。
  static Duration _scale(Duration d, double f) =>
      Duration(milliseconds: (d.inMicroseconds * f / 1000).round());

  /// §9.2「用途」列 → token 的具名映射：业务按用途取值，防止错用时长档。
  Duration get microFeedback => durXs; // 微反馈（按压涟漪）
  Duration get chipCheck => durS; // chip / 勾选
  Duration get cardFloat => durM; // 卡片上浮
  Duration get drawer => durL; // 抽屉（§9.3#3）
  Duration get page => durL; // 页面
  Duration get sharedAxis => durL; // 共享轴（§9.3#2，280ms）
  Duration get containerTransform => durXl; // 容器变换（§9.3#6 P1）
  Duration get heroFlight => durXl; // 落库飞入（§9.3#5，≤450ms）
  Duration get cascadeInterval => staggerInterval; // 冷启动级联间隔（§9.3#1）
  Duration get countUp => countUpDuration; // AI count-up（§9.3#4）
  Duration get themeMorph => themeMorphDuration; // 主题 morph（§9.3#10）

  /// MotionLevel=off 时的统一淡入淡出时长（§9.6）。
  Duration get fadeOff => offFadeDuration;

  /// 拷贝并替换字段（ThemeExtension 契约）。
  @override
  MotionConfig copyWith({
    MotionLevel? level,
    Duration? durXs,
    Duration? durS,
    Duration? durM,
    Duration? durL,
    Duration? durXl,
    Duration? staggerInterval,
    Duration? countUpDuration,
    Duration? themeMorphDuration,
    Duration? offFadeDuration,
    SlimcaSpring? springSnappy,
    SlimcaSpring? springSoft,
    Curve? curveEaseOutExpo,
    Curve? curveStandard,
    Curve? curveEmphasized,
    Curve? curveExpand,
    Curve? curveCollapse,
    Curve? curveEffectsStandard,
  }) => MotionConfig(
    level: level ?? this.level,
    durXs: durXs ?? this.durXs,
    durS: durS ?? this.durS,
    durM: durM ?? this.durM,
    durL: durL ?? this.durL,
    durXl: durXl ?? this.durXl,
    staggerInterval: staggerInterval ?? this.staggerInterval,
    countUpDuration: countUpDuration ?? this.countUpDuration,
    themeMorphDuration: themeMorphDuration ?? this.themeMorphDuration,
    offFadeDuration: offFadeDuration ?? this.offFadeDuration,
    springSnappy: springSnappy ?? this.springSnappy,
    springSoft: springSoft ?? this.springSoft,
    curveEaseOutExpo: curveEaseOutExpo ?? this.curveEaseOutExpo,
    curveStandard: curveStandard ?? this.curveStandard,
    curveEmphasized: curveEmphasized ?? this.curveEmphasized,
    curveExpand: curveExpand ?? this.curveExpand,
    curveCollapse: curveCollapse ?? this.curveCollapse,
    curveEffectsStandard: curveEffectsStandard ?? this.curveEffectsStandard,
  );

  @override
  MotionConfig lerp(covariant ThemeExtension<MotionConfig>? other, double t) {
    if (identical(this, other) || other == null) return this;
    final MotionConfig o = other as MotionConfig;
    Duration lerpDur(Duration a, Duration b) => Duration(
      microseconds: lerpDouble(a.inMicroseconds, b.inMicroseconds, t)!.round(),
    );
    // 曲线与档位不可插值，按惯例前半程（t ≤ 0.5）取 a、后半程取 b。
    return MotionConfig(
      level: t <= 0.5 ? level : o.level,
      durXs: lerpDur(durXs, o.durXs),
      durS: lerpDur(durS, o.durS),
      durM: lerpDur(durM, o.durM),
      durL: lerpDur(durL, o.durL),
      durXl: lerpDur(durXl, o.durXl),
      staggerInterval: lerpDur(staggerInterval, o.staggerInterval),
      countUpDuration: lerpDur(countUpDuration, o.countUpDuration),
      themeMorphDuration: lerpDur(themeMorphDuration, o.themeMorphDuration),
      offFadeDuration: lerpDur(offFadeDuration, o.offFadeDuration),
      springSnappy: springSnappy.lerp(o.springSnappy, t),
      springSoft: springSoft.lerp(o.springSoft, t),
      curveEaseOutExpo: t <= 0.5 ? curveEaseOutExpo : o.curveEaseOutExpo,
      curveStandard: t <= 0.5 ? curveStandard : o.curveStandard,
      curveEmphasized: t <= 0.5 ? curveEmphasized : o.curveEmphasized,
      curveExpand: t <= 0.5 ? curveExpand : o.curveExpand,
      curveCollapse: t <= 0.5 ? curveCollapse : o.curveCollapse,
      curveEffectsStandard: t <= 0.5
          ? curveEffectsStandard
          : o.curveEffectsStandard,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MotionConfig &&
        other.level == level &&
        other.durXs == durXs &&
        other.durS == durS &&
        other.durM == durM &&
        other.durL == durL &&
        other.durXl == durXl &&
        other.staggerInterval == staggerInterval &&
        other.countUpDuration == countUpDuration &&
        other.themeMorphDuration == themeMorphDuration &&
        other.offFadeDuration == offFadeDuration &&
        other.springSnappy == springSnappy &&
        other.springSoft == springSoft &&
        other.curveEaseOutExpo == curveEaseOutExpo &&
        other.curveStandard == curveStandard &&
        other.curveEmphasized == curveEmphasized &&
        other.curveExpand == curveExpand &&
        other.curveCollapse == curveCollapse &&
        other.curveEffectsStandard == curveEffectsStandard;
  }

  @override
  int get hashCode => Object.hash(
    level,
    durXs,
    durS,
    durM,
    durL,
    durXl,
    staggerInterval,
    countUpDuration,
    themeMorphDuration,
    offFadeDuration,
    springSnappy,
    springSoft,
    curveEaseOutExpo,
    curveStandard,
    curveEmphasized,
    curveExpand,
    curveCollapse,
    curveEffectsStandard,
  );

  @override
  String toString() =>
      'MotionConfig(level: $level, durL: $durL, durXl: $durXl)';
}

/// 动效 token 读取入口（§9.2「动效 token 挂进主题」）。
/// 宿主主题未挂载时回退 full 档（§9.2 表值），保证组件在任意 ThemeData 下可用。
extension MotionConfigBuildContext on BuildContext {
  MotionConfig get motion =>
      Theme.of(this).extension<MotionConfig>() ??
      MotionConfig.forLevel(MotionLevel.full);
}
