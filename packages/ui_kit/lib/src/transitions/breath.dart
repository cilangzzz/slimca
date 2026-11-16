import 'dart:ui' show clampDouble;

import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// 解析中呼吸态容器（§2.3 步骤 3「输入气泡立即上浮不等 AI；抽屉原地转为确认卡」，
/// §9.4「AI 等待骨架出现 ≤100ms」——AI 返回前的等待区以呼吸态呈现，零 spinner）。
///
/// opacity/scale 双通道循环呼吸（一吸一呼），周期与幅度全部由 MotionConfig 推导：
/// - 整周期 = 4 × [MotionConfig.drawer]（§9.2 dur.l：一吸一呼各 2 × 280ms），
///   off/reduced 档随 token 自动降速；
/// - 幅度为几何常量（非动效 token，先例见 [SlimcaStaggerItem.floatDistance]）。
///
/// 降级（§9.2 MotionLevel=off / §9.6）：呼吸循环退化为 [MotionConfig.fadeOff]
/// 100ms 单次淡入，静置呈现；[SlimcaBreath.breathing]=false 时业务可主动停息。
class SlimcaBreath extends StatefulWidget {
  const SlimcaBreath({
    super.key,
    required this.child,
    this.breathing = true,
    this.scaleAmplitude = 0.04,
    this.opacityFloor = 0.55,
    this.motion,
  }) : assert(
         scaleAmplitude >= 0 && scaleAmplitude <= 0.2,
         '呼吸缩放幅度限 [0, 0.2]，过大变成抖动',
       ),
       assert(
         opacityFloor >= 0 && opacityFloor < 1,
         '呼吸透明度下限限 [0, 1)',
       );

  /// 呼吸内容（骨架/占位图标/输入气泡等，由业务组装）。
  final Widget child;

  /// 是否呼吸（确认卡替换等待区后业务关闭呼吸，§2.3 步骤 3「原地转为确认卡」）。
  final bool breathing;

  /// 缩放呼吸幅度（峰值偏离 1.0 的比例，几何常量）。
  final double scaleAmplitude;

  /// 透明度呼吸下限（峰值恒为 1.0）。
  final double opacityFloor;

  /// 缺省读主题上的 MotionConfig（与 SlimcaConfidenceDot.motion 同约定）。
  final MotionConfig? motion;

  @override
  State<SlimcaBreath> createState() => _SlimcaBreathState();
}

class _SlimcaBreathState extends State<SlimcaBreath>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this);

  /// 一吸一呼各 2 × dur.l → 整周期 4 × dur.l（§9.2 token 推导，无裸时长）。
  Duration _period(MotionConfig motion) => motion.drawer * 4;

  void _refresh() {
    final MotionConfig motion = widget.motion ?? context.motion;
    final bool shouldBreath =
        widget.breathing && motion.level != MotionLevel.off;
    if (shouldBreath) {
      _breath.duration = _period(motion);
      if (!_breath.isAnimating) {
        // TickerMode 离屏自动暂停（§9.5「TickerMode 离屏暂停」）
        _breath.repeat(reverse: true);
      }
    } else if (_breath.isAnimating) {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(SlimcaBreath oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = widget.motion ?? context.motion;
    final Widget child = widget.child;
    // §9.6：MotionLevel=off → 100ms 单次淡入后静置（无循环呼吸）
    if (motion.level == MotionLevel.off || !widget.breathing) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: motion.fadeOff,
        curve: Curves.linear,
        builder: (context, t, child) =>
            Opacity(opacity: clampDouble(t, 0.0, 1.0), child: child),
        child: child, // §9.5：静态子树只 build 一次
      );
    }
    return RepaintBoundary(
      // §9.5：RepaintBoundary 隔离呼吸重绘区域，不波及抽屉其余部分
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          // easeInOut 让一吸一呼在相位端点自然停顿，接近正弦呼吸节奏
          final double phase = Curves.easeInOut.transform(_breath.value);
          final double scale = 1.0 + widget.scaleAmplitude * phase;
          final double opacity =
              widget.opacityFloor +
              (1.0 - widget.opacityFloor) * phase;
          return Opacity(
            opacity: clampDouble(opacity, 0.0, 1.0),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: child,
      ),
    );
  }
}
