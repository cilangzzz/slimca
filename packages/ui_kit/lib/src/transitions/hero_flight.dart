import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// 确认落库的卡片 Hero 飞入（§9.3#5：卡片 Hero 飞入仪表盘槽位，≤450ms，Hero + spring）。
///
/// 飞行时长跟随路由 transitionDuration——承载确认→仪表盘的路由请使用 durXl 档时长
/// （见 [MotionConfig.heroFlight]，§9.3#5 ≤450ms）；轨迹用 springSoft 弹簧插值（阻尼比 0.85）。
/// 配套的「热量环 spring 推进 / 当日结余滚动」分别由 SlimcaCalorieRing / SlimcaCountUp 承担。
class SlimcaHero extends StatelessWidget {
  const SlimcaHero({
    super.key,
    required this.tag,
    required this.child,
    this.motion,
  });

  final Object tag;

  final Widget child;

  /// 缺省读主题上的 MotionConfig。
  final MotionConfig? motion;

  @override
  Widget build(BuildContext context) {
    final MotionConfig m = motion ?? context.motion;
    if (m.level == MotionLevel.off) {
      // §9.6 降级：线性插值（时长随路由的 100ms fade 档）
      return Hero(tag: tag, child: child);
    }
    return Hero(
      tag: tag,
      createRectTween: (Rect? begin, Rect? end) =>
          SlimcaSpringRectTween(begin: begin, end: end, spring: m.springSoft),
      child: child,
    );
  }
}

/// 弹簧 [RectTween]：Hero 飞行轨迹走弹簧插值（§9.3#5「Hero + spring」）。
class SlimcaSpringRectTween extends RectTween {
  SlimcaSpringRectTween({super.begin, super.end, required this.spring});

  final SlimcaSpring spring;

  @override
  Rect? lerp(double t) => Rect.lerp(begin, end, spring.curve.transform(t));
}
