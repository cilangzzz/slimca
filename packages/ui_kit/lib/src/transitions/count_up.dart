import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// 数字 count-up（§9.3#4「AI 返回：双数字 count-up，count-up 800ms easeOutExpo」）。
///
/// 金额一律整数分、热量一律整数 kcal（§5.1），统一 int 驱动；
/// 份量滑杆/金额点改联动重算时，TweenAnimationBuilder 从当前值续播到新目标（§2.3 步骤 4）。
///
/// 数字排版强制 tabular figures（§5.4 双账数字等宽对齐纪律，拍板 + M2/HIG）——
/// count-up 跳动时位数宽度不抖动。
class SlimcaCountUp extends StatelessWidget {
  const SlimcaCountUp({
    super.key,
    required this.value,
    this.from = 0,
    this.style,
    this.format,
  });

  /// 目标值（kcal 或分）。
  final int value;

  /// 首帧起始值。
  final int from;

  final TextStyle? style;

  /// 展示格式化（如金额分→元）；缺省直接 toString。
  final String Function(int value)? format;

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = context.motion;
    final bool off = motion.level == MotionLevel.off;
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: from, end: value),
      duration: off ? motion.fadeOff : motion.countUp, // §9.3#4 800ms
      curve: off
          ? Curves.linear
          : motion.curveEaseOutExpo, // §9.3#4 easeOutExpo
      builder: (context, v, _) => Text(
        format?.call(v) ?? '$v',
        style: (style ?? const TextStyle())
            .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}
