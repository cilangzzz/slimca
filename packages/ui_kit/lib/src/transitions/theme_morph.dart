import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';

/// 主题切换全屏 morph（§9.3#10、§8.3）：
/// 「主题切换 = ColorScheme.lerp + ThemeExtensionTween」，300ms 无闪跳。
///
/// 实现落在 SDK 的 ThemeData.lerp——它内部对 ColorScheme 走 ColorScheme.lerp、
/// 对 extensions（SlimcaTheme/MotionConfig）调用各自的 ThemeExtension.lerp；
/// 因此业务只需在主题源（settings 流）变化时更新 [data]。
class SlimcaThemeMorph extends StatelessWidget {
  const SlimcaThemeMorph({
    super.key,
    required this.data,
    required this.child,
    this.duration,
    this.curve,
  });

  /// 目标主题（buildTheme 产物，含语义 token 与 MotionConfig 两个扩展）。
  final ThemeData data;

  final Widget child;

  final Duration? duration;

  final Curve? curve;

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = context.motion;
    final Duration d =
        duration ??
        (motion.level == MotionLevel.off ? motion.fadeOff : motion.themeMorph);
    final Curve c = curve ?? motion.curveStandard;
    return AnimatedTheme(data: data, duration: d, curve: c, child: child);
  }
}
