/// 文本输入（标题/备注/解析输入/金额点改共用）：内部持有 controller，
/// initial 外部变化时才回写，避免逐帧重建导致光标跳动。
///
/// 自 W2 页面私有实现提取为公用（W3-4 确认卡/降级表单复用，§3.3）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 语义化文本输入框（样式引用 §8.2 语义 token，组件层禁裸色值）。
class CaptureTextField extends StatefulWidget {
  const CaptureTextField({
    super.key,
    required this.initial,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
    this.keyboardType,
    this.expands = false,
    this.obscureText = false,
  });

  /// 外部初始值/预填值（AI 初值、chip 预填、降级原文回填）。
  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final TextInputType? keyboardType;

  /// 是否纵向扩展吃满父级（composer 输入面口径，写通道 AI 输入区用）：
  /// true 时 [maxLines] 失效（TextField expands 契约要求 lines 均为 null），
  /// 文本顶端对齐。
  final bool expands;

  /// 凭据遮蔽（AI API Key 等敏感输入；配合 autocorrect 关闭）。
  final bool obscureText;

  @override
  State<CaptureTextField> createState() => _CaptureTextFieldState();
}

class _CaptureTextFieldState extends State<CaptureTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(CaptureTextField oldWidget) {
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
      expands: widget.expands,
      maxLines: widget.expands ? null : widget.maxLines,
      textAlignVertical: widget.expands ? TextAlignVertical.top : null,
      keyboardType: widget.keyboardType,
      obscureText: widget.obscureText,
      autocorrect: !widget.obscureText,
      enableSuggestions: !widget.obscureText,
      style: TextStyle(fontSize: 16, color: tokens.onSurface), // §7.3 input 16
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
        filled: true,
        fillColor: tokens.surfaceCard,
        // §7.3 M3 文本框容器 56dp：单行态（16×~1.4 + 上下 16）≈56；多行态
        // 随内容增长。
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
    );
  }
}
