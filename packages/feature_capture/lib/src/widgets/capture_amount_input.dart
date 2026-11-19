/// 金额输入字段（§3.3 录入抽屉写通道「金额输入组件：分存储」）。
///
/// 键盘输入是纯字符串（`capture_money.dart` 分转换），提交时转换为整数分，
/// 杜绝浮点（§3.4 流水记账、§5.1 金额一律 INTEGER 最小货币单位）。
///
/// 统一高度抽屉内不再使用自绘数字键盘钉底（挤占滚动区）——金额经
/// [TextField] 直输（numeric+decimal 键盘、两位小数 formatter，§7.3
/// 「键盘类型匹配任务」），与其余字段同滚动区；数字排版 tabular figures
/// （§5.4），方向语义色（§8.2）。
library;

import 'package:core_domain/core_domain.dart' show LineDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_money.dart';

/// 金额输入字段：¥ 前缀大字居中 + 两位小数 formatter + 方向语义色。
class CaptureAmountField extends StatefulWidget {
  const CaptureAmountField({
    super.key,
    required this.amountText,
    required this.direction,
    required this.onChanged,
    this.originalAmountMinor,
  });

  /// 当前输入串（原始键入文本；分转换在提交侧，§5.1）。
  final String amountText;

  /// 决定金额显示色：out=暖橘 moneyOut / in=moneyIn（§8.2 双主色锚定）。
  final LineDirection direction;

  /// 输入回调（控制器 setAmountText 直写，合法性延迟到提交判定）。
  final ValueChanged<String> onChanged;

  /// 编辑模式的旧金额（分）：展示「原金额」对照（§3.4 修正=新增行）。
  final int? originalAmountMinor;

  @override
  State<CaptureAmountField> createState() => _CaptureAmountFieldState();
}

class _CaptureAmountFieldState extends State<CaptureAmountField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.amountText);

  @override
  void didUpdateWidget(CaptureAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部回填（编辑模式预填）仅在外部值变化且与当前不一致时回写，
    // 避免逐帧重建导致光标跳动（与 CaptureTextField 同口径）。
    if (widget.amountText != oldWidget.amountText &&
        widget.amountText != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.amountText,
        selection: TextSelection.collapsed(
          offset: widget.amountText.characters.length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final accent = widget.direction == LineDirection.outcome
        ? tokens.moneyOut
        : tokens.moneyIn;
    final original = widget.originalAmountMinor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('capture_amount_display'),
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // 两位小数上限（§5.1「最多两位小数」）：formatter 端拦截，
          // 合法性（>0）仍在提交判定（amountMinor）。
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
          ],
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: widget.amountText.isEmpty ? tokens.onSurfaceMuted : accent,
            fontFeatures: const [FontFeature.tabularFigures()], // §5.4
          ),
          decoration: InputDecoration(
            hintText: '0.00',
            hintStyle: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: tokens.onSurfaceMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            prefixText: '¥',
            prefixStyle: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.amountText.isEmpty
                  ? tokens.onSurfaceMuted
                  : accent,
            ),
            filled: true,
            fillColor: tokens.surfaceCard,
            contentPadding: EdgeInsets.symmetric(
              horizontal: context.spacing.space200,
              vertical: context.spacing.space200,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
              borderSide: BorderSide(color: tokens.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
              borderSide: BorderSide(color: tokens.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
              borderSide: BorderSide(color: tokens.primary, width: 1.5),
            ),
          ),
          onChanged: widget.onChanged,
        ),
        if (original != null)
          Padding(
            padding: EdgeInsets.only(top: context.spacing.space100),
            child: Text(
              '原金额 ¥${CaptureMoney.fromMinorUnits(original)}，保存将新增修正行（§3.4）',
              key: const ValueKey('capture_original_amount'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
          ),
      ],
    );
  }
}
