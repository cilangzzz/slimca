/// AI 文本输入区（§3.3 写通道「文本输入区 → 解析」、§2.3 步骤 2）。
///
/// 一句话描述 → 「解析」按钮触发 [CaptureController.startParse]；语音/拍照
/// 通道 W5-6/W11-12 接入（§11.1），此处仅文本。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_models.dart';
import 'capture_text_field.dart';

/// 解析按钮测试锚点。
const Key captureParseButtonKey = ValueKey('capture_parse_button');

/// 文本输入区测试锚点。
const Key captureAiInputKey = ValueKey('capture_ai_input');

/// AI 文本输入区：多行输入 + 解析按钮 + 单边模式提示。
class CaptureAiInput extends StatelessWidget {
  const CaptureAiInput({
    super.key,
    required this.text,
    required this.onChanged,
    required this.onParse,
    required this.side,
    this.errorText,
  });

  final String text;
  final ValueChanged<String> onChanged;
  final VoidCallback onParse;

  /// 决定提示文案（kcal-only 模式明确「只解析热量」，§3.3 单边开关）。
  final CaptureSide side;
  final String? errorText;

  String get _hint => side == CaptureSide.calorie
      ? '如：喝了一杯黑咖啡（仅解析热量，§3.3）'
      : '例：中午吃了兰州拉面花了 18（§7.2）';

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaptureTextField(
          key: captureAiInputKey,
          initial: text,
          hint: _hint,
          maxLines: 3,
          onChanged: onChanged,
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: captureParseButtonKey,
          onPressed: text.trim().isEmpty ? null : onParse,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.primary,
            foregroundColor: tokens.onPrimary,
            disabledBackgroundColor: tokens.surfaceMuted,
            disabledForegroundColor: tokens.onSurfaceMuted,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            '解析',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              errorText!,
              key: const ValueKey('capture_error_text'),
              style: TextStyle(fontSize: 13, color: tokens.danger),
            ),
          ),
      ],
    );
  }
}
