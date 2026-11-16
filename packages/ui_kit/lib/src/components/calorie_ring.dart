import 'dart:math' as math;
import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';
import '../tokens/slimca_theme.dart';

/// 今日热量环（§3.2 卡片墙核心视觉：「热量环（摄入/消耗/净+预算余）」）。
///
/// W1 占位实现：单环 + 摄入弧 + 消耗内弧 + 超支段红色（§3.2 预算状态色），
/// 环推进走 springSoft（§9.2 spring.soft「环推进」、§9.3#4/#5）；份量滑杆联动重算时
/// TweenAnimationBuilder 从当前 sweep 续播（§2.3 步骤 4）。中心内容由 [center] 自定义。
///
/// sweep 入场变体（§9.3#4「热量环 sweep 填充」，W3-4）：[sweepEntrance]=true
/// （缺省，仪表盘 W2 口径不变）时首挂载从 0 扫到目标值、springSoft 整定；
/// false 时首帧直接呈现目标值——仪表盘切日重建等「入场已有级联承担」的场景
/// （§9.3#1）避免环二次 sweep。两种档位下目标值变化均从当前值 spring 续播。
class SlimcaCalorieRing extends StatelessWidget {
  const SlimcaCalorieRing({
    super.key,
    required this.kcalIn,
    required this.kcalOut,
    required this.budget,
    this.size = 160,
    this.strokeWidth = 12,
    this.sweepEntrance = true,
    this.center,
  });

  /// 今日摄入 kcal。
  final int kcalIn;

  /// 今日消耗 kcal（burn 行，§2.2）。
  final int kcalOut;

  /// 热量预算 kcal（kcal 账本「预算=收入」心智，§2.1③）。
  final int budget;

  final double size;
  final double strokeWidth;

  /// sweep 入场开关（§9.3#4「热量环 sweep 填充」）：true=首挂载从 0 扫到目标值；
  /// false=首帧直达目标值（入场动效已由级联承担的场景），后续目标变化仍 spring 续播。
  final bool sweepEntrance;

  /// 环心内容（净热量/「今日还能吃」数字等，由业务组装）。
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final MotionConfig motion = context.motion;
    final int net = kcalIn - kcalOut;
    final int target = budget > 0 ? budget : 1;
    // 1.0 以内为预算内弧段，超出部分单独用 danger 呈现（§3.2「超支/超额即时反馈」）
    final double fraction = clampDouble(net / target, 0.0, 1.6);
    final double burnRatio = kcalIn > 0
        ? clampDouble(kcalOut / kcalIn, 0.0, 1.0)
        : 0.0;
    final bool off = motion.level == MotionLevel.off;
    return TweenAnimationBuilder<double>(
      // sweep 入场（§9.3#4）：true 从 0 扫到目标；false 首帧直达目标值
      // （begin 仅作用于首挂载，目标变化后 TweenAnimationBuilder 从当前值续播）
      tween: Tween<double>(
        begin: sweepEntrance ? 0.0 : fraction,
        end: fraction,
      ),
      duration: off ? motion.fadeOff : motion.springSoft.settleDuration,
      curve: off ? Curves.linear : motion.springSoft.curve,
      builder: (context, value, child) {
        return RepaintBoundary(
          // §9.5：RepaintBoundary 隔离重绘区域
          child: CustomPaint(
            size: Size.square(size),
            painter: _CalorieRingPainter(
              progress: clampDouble(value, 0.0, 1.0),
              overProgress: clampDouble(value - 1.0, 0.0, 0.6),
              burnRatio: burnRatio,
              trackColor: tokens.surfaceMuted,
              progressColor: tokens.kcalIn,
              burnColor: tokens.kcalOut,
              overColor: tokens.danger,
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

/// 热量环画笔：参数化占位（完整视觉打磨随主题包 golden 基线推进，§8.3/§9.6）。
class _CalorieRingPainter extends CustomPainter {
  _CalorieRingPainter({
    required this.progress,
    required this.overProgress,
    required this.burnRatio,
    required this.trackColor,
    required this.progressColor,
    required this.burnColor,
    required this.overColor,
    required this.strokeWidth,
  });

  /// 预算内弧段进度 0-1。
  final double progress;

  /// 超支段进度（progress 满后的延伸，0-0.6）。
  final double overProgress;

  /// 消耗占摄入比例（内弧）。
  final double burnRatio;

  final Color trackColor;
  final Color progressColor;
  final Color burnColor;
  final Color overColor;
  final double strokeWidth;

  Paint _arcPaint(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..color = color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Paint track = _arcPaint(trackColor, strokeWidth);
    canvas.drawCircle(center, radius, track);

    final Rect arcRect = Rect.fromCircle(center: center, radius: radius);
    const double startAngle = -math.pi / 2; // 12 点方向起笔
    final double sweep = 2 * math.pi * progress;
    if (sweep > 0.001) {
      canvas.drawArc(
        arcRect,
        startAngle,
        sweep,
        false,
        _arcPaint(progressColor, strokeWidth),
      );
    }
    final double overSweep = 2 * math.pi * overProgress;
    if (overSweep > 0.001) {
      // 超支段：从预算满格处继续，红色警示（§3.2 预算状态色）
      canvas.drawArc(
        arcRect,
        startAngle + sweep,
        overSweep,
        false,
        _arcPaint(overColor, strokeWidth),
      );
    }
    final double burnSweep = 2 * math.pi * burnRatio;
    if (burnSweep > 0.001) {
      final double innerRadius = radius - strokeWidth * 1.1;
      if (innerRadius > 0) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: innerRadius),
          startAngle,
          burnSweep,
          false,
          _arcPaint(burnColor, strokeWidth * 0.45),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CalorieRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.overProgress != overProgress ||
      oldDelegate.burnRatio != burnRatio ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.burnColor != burnColor ||
      oldDelegate.overColor != overColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
