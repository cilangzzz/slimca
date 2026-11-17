/// 存钱进度环（§3.6 存钱目标 P1「进度环」、§8.2 语义 token、§9.2 动效 token）。
///
/// [SlimcaCalorieRing]（ui_kit，§3.2 热量环）的单环变体：ui_kit 为全仓共享
/// 组件层、热量语义专用（kcalIn/kcalOut 双弧），存钱进度属计划域语义
/// （moneyIn，§8.2「暖橘=金额」），故本域内落变体组件——只引用 ui_kit 既有
/// token（颜色语义 token + MotionConfig），禁裸色值/裸时长（§8.2 第 3 层）。
///
/// 动效（§9.2/§9.3#4 精神）：进度推进走 springSoft 续播；[sweepEntrance]=true
/// 首挂载从 0 扫到目标值（详情页入场），false 首帧直达（列表级联入场已承担
/// 入场动效的场景）；MotionLevel=off 退化为 100ms 直达（§9.6）。
library;

import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 单环进度环（存钱目标进度，§3.6；颜色缺省语义 token moneyIn）。
class SlimcaProgressRing extends StatelessWidget {
  const SlimcaProgressRing({
    super.key,
    required this.progress,
    this.size = 72,
    this.strokeWidth = 8,
    this.color,
    this.trackColor,
    this.sweepEntrance = true,
    this.center,
  });

  /// 进度 0-1（调用方钳制；超 1 部分不渲染——存钱超额即满环，§3.6）。
  final double progress;

  final double size;
  final double strokeWidth;

  /// 环色；缺省语义 token moneyIn（§8.2 金额语义「存入」侧）。
  final Color? color;

  /// 底环色；缺省 surfaceMuted。
  final Color? trackColor;

  /// sweep 入场开关（§9.3#4 口径，与 SlimcaCalorieRing.sweepEntrance 同语义）。
  final bool sweepEntrance;

  /// 环心内容（百分比/金额，由业务组装）。
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final MotionConfig motion = context.motion;
    final double fraction = clampDouble(progress, 0.0, 1.0);
    final bool off = motion.level == MotionLevel.off;
    return TweenAnimationBuilder<double>(
      // sweep 入场（§9.3#4）：true 从 0 扫到目标；false 首帧直达；目标变化
      // 后 TweenAnimationBuilder 从当前值 spring 续播（§9.2 spring.soft）。
      tween: Tween<double>(begin: sweepEntrance ? 0.0 : fraction, end: fraction),
      duration: off ? motion.fadeOff : motion.springSoft.settleDuration,
      curve: off ? Curves.linear : motion.springSoft.curve,
      builder: (context, value, child) {
        return RepaintBoundary(
          // §9.5：RepaintBoundary 隔离重绘区域
          child: CustomPaint(
            size: Size.square(size),
            painter: _ProgressRingPainter(
              progress: clampDouble(value, 0.0, 1.0),
              trackColor: trackColor ?? tokens.surfaceMuted,
              progressColor: color ?? tokens.moneyIn,
              strokeWidth: strokeWidth,
            ),
            child: child,
          ),
        );
      },
      child: center == null
          ? null
          : SizedBox.square(
              dimension: size,
              child: Center(child: center),
            ),
    );
  }
}

/// 进度环画笔（与 SlimcaCalorieRing 同规格的参数化单环，12 点方向起笔）。
class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );
    final double sweep = 2 * math.pi * progress;
    if (sweep > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // 12 点方向起笔（§3.2 热量环同口径）
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = progressColor,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
