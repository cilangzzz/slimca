/// 单边开关（§3.3「仅记钱 / 仅记热量，schema 中对应 lines 只产出一类」）。
///
/// W2 手动路径只开放「仅记钱」；「仅记热量」选中后展示占位区且不可提交
/// （热量输入区 W3-4 接 AI 双解析，§11.1 W3-4）。state 字段已冻结，
/// schema 侧对应「只产出一类 lines」的约束由提交路径保证。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';

/// 仅记钱/仅记热量双段开关。
class CaptureSideToggle extends StatelessWidget {
  const CaptureSideToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CaptureSide value;
  final ValueChanged<CaptureSide> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Row(
      children: [
        Expanded(child: _segment(context, tokens, motion, CaptureSide.money, '仅记钱')),
        const SizedBox(width: 10),
        Expanded(child: _segment(context, tokens, motion, CaptureSide.calorie, '仅记热量')),
      ],
    );
  }

  Widget _segment(
    BuildContext context,
    SlimcaTheme tokens,
    MotionConfig motion,
    CaptureSide side,
    String label,
  ) {
    final selected = value == side;
    return AnimatedContainer(
      duration: motion.chipCheck, // §9.2 dur.s chip 微交互
      curve: motion.springSnappy.curve,
      decoration: BoxDecoration(
        color: selected ? tokens.primary.withValues(alpha: 0.12) : tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? tokens.primary : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('capture_side_${side.wire}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(side),
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? tokens.primary : tokens.onSurfaceMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
