/// 收支方向切换（§5.2② direction：expense=out / income=in）。
///
/// 选中态取金额语义色（支出=暖橘 moneyOut / 收入=moneyIn，§8.2 双主色
/// 锚定），过渡走 MotionConfig token（§9.5：隐式动画仅限微交互）。
library;

import 'package:core_domain/core_domain.dart' show LineDirection;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 支出/收入双 pill 切换。
class CaptureDirectionToggle extends StatelessWidget {
  const CaptureDirectionToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LineDirection value;
  final ValueChanged<LineDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Row(
      children: [
        Expanded(child: _pill(context, tokens, motion, LineDirection.outcome, '支出', tokens.moneyOut)),
        const SizedBox(width: 10),
        Expanded(child: _pill(context, tokens, motion, LineDirection.income, '收入', tokens.moneyIn)),
      ],
    );
  }

  Widget _pill(
    BuildContext context,
    SlimcaTheme tokens,
    MotionConfig motion,
    LineDirection direction,
    String label,
    Color accent,
  ) {
    final selected = value == direction;
    return AnimatedContainer(
      duration: motion.chipCheck, // §9.2 dur.s chip 微交互
      curve: motion.springSnappy.curve,
      decoration: BoxDecoration(
        color: selected ? accent.withValues(alpha: 0.14) : tokens.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? accent : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: direction == LineDirection.outcome
              ? const ValueKey('capture_direction_out')
              : const ValueKey('capture_direction_in'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(direction),
          child: SizedBox(
            height: 44,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? accent : tokens.onSurfaceMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
