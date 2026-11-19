import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// M3 modal bottom sheet 容器口径（§8.1 大厂设计规范.md）：
/// - 拖拽把手 32×4dp（onSurfaceVariant 色）；
/// - 顶部圆角 28dp（M3 extraLarge）；
/// - modal 内容最大宽 640dp；
/// - elevation 沿框架默认（1）。
/// 全部经本路由统一生效（存量弹层随路由自动对齐，§8.2#7）。
const double kSlimcaSheetHandleWidth = 32;
const double kSlimcaSheetHandleHeight = 4;
const double kSlimcaSheetHandleTopGap = 10;
const double kSlimcaSheetCornerRadius = 28;
const double kSlimcaSheetModalMaxWidth = 640;

/// 弹层拖拽把手（M3 bottom sheet 拖拽把手 32×4dp，onSurfaceVariant 色）。
class SlimcaSheetGrabber extends StatelessWidget {
  const SlimcaSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kSlimcaSheetHandleWidth,
      height: kSlimcaSheetHandleHeight,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        borderRadius: BorderRadius.circular(kSlimcaSheetHandleHeight / 2),
      ),
    );
  }
}

/// 录入抽屉路由：弹簧 bottomSheet（§9.3#3、§4.2「capture 非路由页面语义、任意 Tab 可唤起」）。
///
/// - 弹簧规格 springSnappy（§9.2：220ms 整定、阻尼比 1.0 不回弹，交互跟随），
///   满足 §2.3「打开到可输入 ≤280ms」预算；
/// - 通过 Flutter 3.32 `TransitionRoute.createSimulation` 钩子驱动：控制器曲线/时长被忽略，
///   进场 0→1、退场 1→0 均走弹簧（§9.5「路由级转场显式 PageRouteBuilder」精神）；
/// - MotionLevel=off → 退化为线性 100ms 淡入淡出（§9.6）；
/// - 容器按 M3 modal bottom sheet 口径：把手 + 顶圆角 28 + 内容最大宽 640（§8.1）。
class SlimcaSpringSheetRoute<T> extends PopupRoute<T> {
  SlimcaSpringSheetRoute({
    required this.builder,
    MotionConfig? motion,
    this.backgroundColor,
    Color? barrierColor,
    bool barrierDismissible = true,
    String? barrierLabel,
    super.settings,
  }) : motion = motion ?? MotionConfig.forLevel(MotionLevel.full),
       _barrierColor = barrierColor ?? const Color(0x80000000),
       _barrierDismissible = barrierDismissible,
       _barrierLabel = barrierLabel;

  /// 抽屉内容（写/说/拍三通道 Tab + 最近 chip，§3.3）。
  final WidgetBuilder builder;

  final MotionConfig motion;

  /// 抽屉容器底色；缺省用主题 surface。
  final Color? backgroundColor;

  final Color _barrierColor;
  final bool _barrierDismissible;
  final String? _barrierLabel;

  /// 拖拽关闭时的速度继承入口（动画值域速度，正值 = 向打开方向）。
  /// §9.3#3「速度继承、可拖拽中途反向」：W2 录入抽屉接线拖拽手势时，
  /// 在 pop 前写入该字段，createSimulation 会带初速度重开弹簧。
  double dismissVelocity = 0;

  @override
  Color? get barrierColor => _barrierColor;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  String? get barrierLabel => _barrierLabel ?? '关闭抽屉';

  @override
  Duration get transitionDuration => motion.level == MotionLevel.off
      ? motion.fadeOff
      : motion.springSnappy.settleDuration;

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Simulation? createSimulation({required bool forward}) {
    // §9.6 降级：off 档返回 null → 线性 100ms 淡入淡出
    if (motion.level == MotionLevel.off) return null;
    final SlimcaSpring spring = motion.springSnappy;
    return forward
        ? spring.simulation(start: 0, end: 1)
        : spring.simulation(start: 1, end: 0, velocity: dismissVelocity);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // M3 modal bottom sheet 容器（§8.1）：顶圆角 28 + 把手 + 内容最大宽 640。
    // 圆角/把手在本路由统一生效（存量弹层随路由对齐，§8.2#7 不做专项回改）。
    final Widget sheet = Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: kSlimcaSheetModalMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Material(
            color: backgroundColor ?? Theme.of(context).colorScheme.surface,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(kSlimcaSheetCornerRadius),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: kSlimcaSheetHandleTopGap,
                  ),
                  child: const SlimcaSheetGrabber(),
                ),
                SafeArea(top: false, child: builder(context)),
              ],
            ),
          ),
        ),
      ),
    );
    return sheet;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (motion.level == MotionLevel.off) {
      return FadeTransition(opacity: animation, child: child);
    }
    // 动画值本身即弹簧响应（createSimulation 驱动），不再叠加曲线。
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    );
  }
}

/// 唤起录入抽屉（§9.3#3 弹簧 bottomSheet；键盘同步避让由抽屉内容自理）。
Future<T?> showSlimcaSpringSheet<T extends Object?>({
  required BuildContext context,
  required WidgetBuilder builder,
  MotionConfig? motion,
  Color? backgroundColor,
  Color? barrierColor,
  bool barrierDismissible = true,
  String? barrierLabel,
  RouteSettings? settings,
  bool useRootNavigator = true,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    SlimcaSpringSheetRoute<T>(
      builder: builder,
      motion: motion,
      backgroundColor: backgroundColor,
      barrierColor: barrierColor,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      settings: settings,
    ),
  );
}
