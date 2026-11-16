import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';
import '../tokens/slimca_theme.dart';

/// 置信度三色点（§2.3 步骤 3、§7.3：≥0.8 绿 / 0.5-0.8 黄 / <0.5 红）。
///
/// 颜色复用 §8.2 状态 token（success/warn/danger）；AI 返回时 pulse
/// （§9.3#4「置信度点 pulse」），周期取 §9.2 dur.s（chip/勾选档）；
/// MotionLevel=off 或 [SlimcaConfidenceDot.pulse]=false 时为静置圆点。
class SlimcaConfidenceDot extends StatefulWidget {
  const SlimcaConfidenceDot({
    super.key,
    required this.confidence,
    this.size = 8.0,
    this.pulse = true,
    this.motion,
  });

  /// AI 置信度 0-1（entry_lines.confidence，§5.2）。
  final double confidence;

  final double size;

  /// 是否 pulse（确认卡静置后业务可关闭）。
  final bool pulse;

  /// 缺省读主题上的 MotionConfig。
  final MotionConfig? motion;

  @override
  State<SlimcaConfidenceDot> createState() => _SlimcaConfidenceDotState();
}

class _SlimcaConfidenceDotState extends State<SlimcaConfidenceDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 120),
  );

  void _refresh() {
    final MotionConfig motion = widget.motion ?? context.motion;
    _pulse.duration = motion.chipCheck;
    final bool shouldPulse = widget.pulse && motion.level != MotionLevel.off;
    if (shouldPulse && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true); // TickerMode 离屏自动暂停（§9.5）
    } else if (!shouldPulse && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(SlimcaConfidenceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    // §2.3/§7.3 三档：≥0.8 绿 / 0.5-0.8 黄 / <0.5 红
    final Color color = widget.confidence >= 0.8
        ? tokens.success
        : widget.confidence >= 0.5
        ? tokens.warn
        : tokens.danger;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final double scale =
            1.0 + 0.4 * Curves.easeInOut.transform(_pulse.value);
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
