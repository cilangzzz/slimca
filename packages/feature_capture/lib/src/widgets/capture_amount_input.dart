/// 金额输入区（§3.3 录入抽屉写通道「金额输入组件：数字键盘样式、分存储」）。
///
/// 键盘输入是纯字符串步进（`capture_money.dart`），提交时转换为整数分，
/// 杜绝浮点（§3.4 流水记账、§5.1 金额一律 INTEGER 最小货币单位）。
library;

import 'package:core_domain/core_domain.dart' show LineDirection;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_money.dart';

/// 大字金额显示 + 自绘数字键盘。
class CaptureAmountInput extends StatelessWidget {
  const CaptureAmountInput({
    super.key,
    required this.amountText,
    required this.direction,
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
    this.originalAmountMinor,
  });

  /// 当前输入串（原始键入文本）。
  final String amountText;

  /// 决定金额显示色：out=暖橘 moneyOut / in=moneyIn（§8.2 双主色锚定）。
  final LineDirection direction;

  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;

  /// 编辑模式的旧金额（分）：展示「原金额」对照（§3.4 修正=新增行）。
  final int? originalAmountMinor;

  Color _amountColor(SlimcaTheme tokens) =>
      direction == LineDirection.outcome ? tokens.moneyOut : tokens.moneyIn;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final accent = _amountColor(tokens);
    final original = originalAmountMinor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 大字金额（方向语义色，§8.2）
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('¥', style: TextStyle(fontSize: 22, color: accent)),
              const SizedBox(width: 4),
              Text(
                CaptureMoney.displayText(amountText),
                key: const ValueKey('capture_amount_display'),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color:
                      amountText.isEmpty ? tokens.onSurfaceMuted : accent,
                ),
              ),
            ],
          ),
        ),
        if (original != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '原金额 ¥${CaptureMoney.fromMinorUnits(original)}，保存将新增修正行（§3.4）',
              key: const ValueKey('capture_original_amount'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
          ),
        const SizedBox(height: 16),
        _Keypad(onDigit: onDigit, onDot: onDot, onBackspace: onBackspace),
      ],
    );
  }
}

/// 自绘数字键盘（数字键盘样式，§3.3）：4×3 网格，数字 + 小数点 + 退格。
class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onDot,
    required this.onBackspace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDot;
  final VoidCallback onBackspace;

  static const List<List<String>> _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', 'backspace'],
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Material(
                      color: tokens.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('capture_key_$key'),
                        onTap: key == '.'
                            ? onDot
                            : key == 'backspace'
                                ? onBackspace
                                : () => onDigit(key),
                        child: SizedBox(
                          height: 56,
                          child: Center(
                            child: key == 'backspace'
                                ? Icon(
                                    Icons.backspace_outlined,
                                    size: 22,
                                    color: tokens.onSurface,
                                  )
                                : Text(
                                    key,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                      color: tokens.onSurface,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
