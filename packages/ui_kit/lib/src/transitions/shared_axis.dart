import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// MD3 共享轴三轴（§4.1「平级用共享轴」；§9.3#2 日切换 = 水平 X 轴）。
enum SlimcaSharedAxisType { x, y, z }

/// 共享轴单侧插值（可复用 transition builder，§9.3#2）。
///
/// [animation] 0→1 为进场形态；离场方（路由 pop 或 AnimatedSwitcher 的旧 child）
/// 传入反向驱动的同一动画即自动呈现退场形态。
/// §9.6：MotionLevel=off 时退化为纯淡入淡出（时长由调用方的 duration 决定）。
class SlimcaSharedAxisTransition extends StatelessWidget {
  const SlimcaSharedAxisTransition({
    super.key,
    required this.animation,
    required this.type,
    required this.motion,
    required this.child,
    this.curve,
  });

  /// 进场进度（0→1）；离场时为反向驱动。
  final Animation<double> animation;

  final SlimcaSharedAxisType type;

  final MotionConfig motion;

  final Widget child;

  /// 未预弯的动画（如路由的线性控制器）在此叠加曲线；
  /// 调用方已弯过（AnimatedSwitcher 的 switchInCurve）则不传，避免双重缓动。
  final Curve? curve;

  // MD3 共享轴的几何常量（位移/缩放为几何量，非 §9.2 动效 token 范畴）
  static const double _enterDistance = 30.0; // 进场位移
  static const double _exitDistance = 24.0; // 被覆盖路由的「层级后退」位移
  static const double _zScaleFrom = 0.92; // Z 轴进场缩放起点

  @override
  Widget build(BuildContext context) {
    if (motion.level == MotionLevel.off) {
      // §9.6 降级：100ms 淡入淡出
      return FadeTransition(opacity: animation, child: child);
    }
    final Curve? c = curve;
    final Animation<double> curved = c == null
        ? animation
        : CurvedAnimation(parent: animation, curve: c);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) {
          final double t = curved.value;
          Widget content = child!;
          switch (type) {
            case SlimcaSharedAxisType.x:
              content = Transform.translate(
                offset: Offset(_enterDistance * (1 - t), 0),
                child: content,
              );
            case SlimcaSharedAxisType.y:
              content = Transform.translate(
                offset: Offset(0, _enterDistance * (1 - t)),
                child: content,
              );
            case SlimcaSharedAxisType.z:
              content = Transform.scale(
                scale: _zScaleFrom + (1 - _zScaleFrom) * t,
                child: content,
              );
          }
          return content;
        },
        child: child,
      ),
    );
  }
}

/// 路由级共享轴转场（§9.3#2 日切换/平级详情；§9.5「路由级转场一律显式 PageRouteBuilder」）。
///
/// 时长 §9.3#2 = durL 280ms（§2.3 切日 ≤280ms 预算）；MotionLevel=off → 100ms 淡入淡出。
/// go_router 路由级转场可直接注入本 Route（§4.3）。
class SlimcaSharedAxisPageRoute<T> extends PageRouteBuilder<T> {
  SlimcaSharedAxisPageRoute({
    required WidgetBuilder builder,
    this.type = SlimcaSharedAxisType.x,
    MotionConfig? motion,
    super.settings,
  }) : motion = motion ?? MotionConfig.forLevel(MotionLevel.full),
       super(
         pageBuilder: (context, animation, secondaryAnimation) =>
             builder(context),
         transitionDuration: _durationFor(motion),
         reverseTransitionDuration: _durationFor(motion),
       );

  final SlimcaSharedAxisType type;
  final MotionConfig motion;

  static Duration _durationFor(MotionConfig? motion) {
    final MotionConfig m = motion ?? MotionConfig.forLevel(MotionLevel.full);
    return m.level == MotionLevel.off ? m.fadeOff : m.sharedAxis;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 进场/退场：本页沿共享轴位移+淡入淡出（曲线在此叠加，路由动画是线性控制器）
    final Widget entered = SlimcaSharedAxisTransition(
      animation: animation,
      type: type,
      motion: motion,
      curve: motion.curveStandard,
      child: child,
    );
    if (motion.level == MotionLevel.off) return entered;

    // 被新路由覆盖时，本页向转场反方向轻微位移（MD3 共享轴的「层级后退」）
    return AnimatedBuilder(
      animation: secondaryAnimation,
      builder: (context, child) {
        final double t = secondaryAnimation.value;
        Widget content = child!;
        switch (type) {
          case SlimcaSharedAxisType.x:
            content = Transform.translate(
              offset: Offset(-SlimcaSharedAxisTransition._exitDistance * t, 0),
              child: content,
            );
          case SlimcaSharedAxisType.y:
            content = Transform.translate(
              offset: Offset(0, -SlimcaSharedAxisTransition._exitDistance * t),
              child: content,
            );
          case SlimcaSharedAxisType.z:
            content = Transform.scale(scale: 1.0 - 0.04 * t, child: content);
        }
        return content;
      },
      child: entered,
    );
  }
}

/// go_router `pageBuilder` 形态的共享轴转场页（§9.5「路由级转场一律显式
/// PageRouteBuilder」的 go_router 接线件）。
///
/// go_router 的 `pageBuilder` 回调契约要求返回 `Page`（不是 Route）——本类
/// 是 [SlimcaSharedAxisPageRoute] 的 Page 包装：`createRoute` 时仍构造路由级
/// PageRouteBuilder，时长/动效档与 §9.3#2 一致（full 档 280ms / off 档 100ms
/// 淡入淡出）。`name/arguments/restorationId` 直通 Page 基类，go_router 的
/// matchedLocation 经 `name` 注入（与 RouteSettings 等价）。
class SlimcaSharedAxisPage<T> extends Page<T> {
  const SlimcaSharedAxisPage({
    required this.builder,
    this.type = SlimcaSharedAxisType.x,
    this.motion,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// 目标页 builder（同 [SlimcaSharedAxisPageRoute] 的 builder）。
  final WidgetBuilder builder;

  /// 共享轴轴别（默认 X 水平轴，§9.3#2）。
  final SlimcaSharedAxisType type;

  /// 动效档（缺省按 MotionLevel=full 解析，§9.3）。
  final MotionConfig? motion;

  @override
  Route<T> createRoute(BuildContext context) {
    return SlimcaSharedAxisPageRoute<T>(
      settings: this,
      type: type,
      motion: motion,
      builder: builder,
    );
  }
}

/// Widget 级共享轴切换器（§9.3#2「AnimatedSwitcher + layout delta」手段）：
/// 换 child（key 不同）即触发，用于仪表盘左右滑切日（§3.2）与平级内容切换（§4.1）。
/// 进场/离场为对称位移（carousel 观感）；FLIP 位置保持由业务列表配合 layout delta 实现。
class SlimcaSharedAxisSwitcher extends StatelessWidget {
  const SlimcaSharedAxisSwitcher({
    super.key,
    required this.child,
    this.type = SlimcaSharedAxisType.x,
    this.duration,
    this.curve,
  });

  final Widget child;
  final SlimcaSharedAxisType type;
  final Duration? duration;
  final Curve? curve;

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = context.motion;
    final Duration d =
        duration ??
        (motion.level == MotionLevel.off ? motion.fadeOff : motion.sharedAxis);
    final Curve c = curve ?? motion.curveStandard;
    return AnimatedSwitcher(
      duration: d,
      reverseDuration: d,
      switchInCurve: c,
      switchOutCurve: c,
      transitionBuilder: (child, animation) => SlimcaSharedAxisTransition(
        animation: animation, // 已被 switchInCurve/switchOutCurve 弯过，不再叠加曲线
        type: type,
        motion: motion,
        child: child,
      ),
      child: child,
    );
  }
}
