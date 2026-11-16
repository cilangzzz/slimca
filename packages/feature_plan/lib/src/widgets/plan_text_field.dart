/// 计划域文本输入（与 feature_capture 的 CaptureTextField 同构样式，§8.2
/// 语义 token 上色；组件层禁裸色值/裸时长）。
///
/// 内部持有 controller，initial 外部变化时才回写，避免逐帧重建导致光标跳动。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 语义化文本输入框。
class PlanTextField extends StatefulWidget {
  const PlanTextField({
    super.key,
    required this.initial,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
  });

  /// 外部初始值/回填值。
  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  @override
  State<PlanTextField> createState() => _PlanTextFieldState();
}

class _PlanTextFieldState extends State<PlanTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(PlanTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial &&
        widget.initial != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initial,
        selection:
            TextSelection.collapsed(offset: widget.initial.characters.length),
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
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      style: TextStyle(fontSize: 15, color: tokens.onSurface),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
        filled: true,
        fillColor: tokens.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.primary, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
