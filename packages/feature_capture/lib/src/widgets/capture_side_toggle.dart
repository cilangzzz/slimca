/// 单边开关（§3.3「仅记钱 / 仅记热量，schema 中对应 lines 只产出一类」）。
///
/// W3-4 三段语义：
/// - 钱+热量（默认）：AI 双解析，确认卡按解析结果产 calorie+money 行；
/// - 仅记钱：W2 手动记账表单（纯记账用户不被热量字段骚扰，§2.4-2）；
/// - 仅记热量：AI 双解析 kcal-only 模式——确认卡只产 calorie 行
///   （W3-4 主线「单边开关接仅记热量」）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';

/// 钱+热量/仅记钱/仅记热量三段开关。
class CaptureSideToggle extends StatelessWidget {
  const CaptureSideToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CaptureSide value;
  final ValueChanged<CaptureSide> onChanged;

  /// 三段标签（§3.3 单边开关 + W3-4 双解析默认档）。
  static const Map<CaptureSide, String> _labels = {
    CaptureSide.both: '钱+热量',
    CaptureSide.money: '仅记钱',
    CaptureSide.calorie: '仅记热量',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Row(
      children: [
        for (final side in CaptureSide.values) ...[
          if (side != CaptureSide.both) const SizedBox(width: 8),
          Expanded(child: _segment(context, tokens, motion, side)),
        ],
      ],
    );
  }

  Widget _segment(
    BuildContext context,
    SlimcaTheme tokens,
    MotionConfig motion,
    CaptureSide side,
  ) {
    final selected = value == side;
    return AnimatedContainer(
      duration: motion.chipCheck, // §9.2 dur.s chip 微交互
      curve: motion.springSnappy.curve,
      decoration: BoxDecoration(
        color: selected ? tokens.primary.withValues(alpha: 0.12) : tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
        border: Border.all(
          color: selected ? tokens.primary : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('capture_side_${side.wire}'),
          borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
          onTap: () => onChanged(side),
          child: SizedBox(
            // §6.3/§13.2 触控目标 ≥48（SlimcaSizes.minTouchTarget 已定稿）。
            height: context.sizes.minTouchTarget,
            child: Center(
              child: Text(
                _labels[side]!,
                style: TextStyle(
                  fontSize: 14, // §5 Label Large 14/20/500 口径
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
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
