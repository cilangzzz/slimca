/// 账本选择器（§5.4④ ledgers；MVP「恒默认账本」所以通常单 chip）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';

/// 账本 chip 组（money 账本；归档/软删账本不出现）。
class CaptureLedgerPicker extends StatelessWidget {
  const CaptureLedgerPicker({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
  });

  final List<CaptureLedgerOption> options;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    if (options.isEmpty) {
      return Text(
        '暂无账本',
        style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          AnimatedContainer(
            duration: context.motion.chipCheck, // §9.2 dur.s chip 微交互
            curve: context.motion.springSnappy.curve,
            decoration: BoxDecoration(
              color: option.id == selectedId
                  ? tokens.primary.withValues(alpha: 0.12)
                  : tokens.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: option.id == selectedId ? tokens.primary : tokens.outline,
                width: option.id == selectedId ? 1.5 : 1,
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                key: ValueKey('capture_ledger_${option.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(option.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '${option.name}（${option.currency}）',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          option.id == selectedId ? FontWeight.w600 : FontWeight.w400,
                      color: option.id == selectedId
                          ? tokens.primary
                          : tokens.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
