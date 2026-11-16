import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// 冷启动展开的单卡入场（§9.3#1、§2.3 步骤 0）：
/// 快照直出 + 日期大字 spring + 卡片墙按 [index] 以 cascadeInterval 级联上浮，全程无 spinner。
///
/// 手段 §9.3#1「TweenAnimationBuilder stagger」：每张卡独立 [TweenAnimationBuilder]，
/// 时长 = 级联延迟 + 单卡上浮时长（§9.2 dur.m），级联窗口内再按曲线重映射。
/// MotionLevel=off → 退化为 100ms 淡入淡出、无位移（§9.6）。
class SlimcaStaggerItem extends StatelessWidget {
  const SlimcaStaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.floatDistance = 24.0,
  });

  /// 级联序号（0 起）：第 index 张卡延迟 index × cascadeInterval 后开始上浮。
  final int index;

  final Widget child;

  /// 上浮距离（几何常量，非动效 token）。
  final double floatDistance;

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = context.motion;
    final Widget child = this.child;
    if (motion.level == MotionLevel.off) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: motion.fadeOff,
        builder: (context, t, child) =>
            Opacity(opacity: clampDouble(t, 0.0, 1.0), child: child),
        child: child,
      );
    }
    final int itemMs = motion.cardFloat.inMilliseconds; // §9.2 dur.m 单卡上浮时长
    final int delayMs =
        motion.cascadeInterval.inMilliseconds * index; // §9.3#1 80ms 级联
    final int totalMs = delayMs + itemMs;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: totalMs),
      curve: Curves.linear, // 级联窗口在 builder 内按曲线重映射
      builder: (context, t, child) {
        final double local = clampDouble(
          (t * totalMs - delayMs) / itemMs,
          0.0,
          1.0,
        );
        final double curved = motion.curveStandard.transform(local);
        return Opacity(
          opacity: clampDouble(curved, 0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - curved) * floatDistance),
            child: child,
          ),
        );
      },
      child: child, // §9.5：静态子树只 build 一次
    );
  }
}
