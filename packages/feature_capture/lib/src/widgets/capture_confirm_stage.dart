/// 确认卡阶段区（§3.3「先拍后改确认卡」、§2.3 步骤 3-5；统一抽屉高度口径）。
///
/// 统一抽屉高度（[captureSheetHeight]）下，确认卡内容高于可视区时
/// 「确认落库」CTA 不得滚走：本组件以「卡面滚动 + 动作页脚钉底」组装——
/// 卡面（标题/热量环/金额/分类/账本/日期）在 [SingleChildScrollView] 内
/// 滚动，[CaptureConfirmActions] 页脚钉底恒可见。写/说/拍三处 AI 面板
/// 共用（§10.4 收敛，不复制组装逻辑）。
library;

import 'package:flutter/material.dart';

import '../capture_controller.dart';
import '../capture_models.dart';
import 'capture_confirm_card.dart';
import 'capture_error_text.dart';

/// 确认卡阶段区：卡面滚动 + 动作页脚钉底。
class CaptureConfirmStage extends StatelessWidget {
  const CaptureConfirmStage({
    super.key,
    required this.form,
    required this.controller,
    required this.onConfirm,
    this.scrollPadding = const EdgeInsets.fromLTRB(20, 12, 20, 12),
    this.footerPadding = const EdgeInsets.fromLTRB(20, 4, 20, 12),
    this.errorText,
  });

  final CaptureFormState form;
  final CaptureController controller;
  final Future<void> Function() onConfirm;

  /// 卡面滚动区内边距（与宿主面板的滚动区对齐；缺省与 CapturePage 同口径）。
  final EdgeInsetsGeometry scrollPadding;

  /// 动作页脚内边距（横向与卡面对齐）。
  final EdgeInsetsGeometry footerPadding;

  /// 阶段级错误文案（钉底动作区上方展示）。控制器 errorText 只收口
  /// submitPendingCapture 路径；面板自管提交（如语音通道直调网关）经此
  /// 传入失败文案，保证「失败就地提示可重试」（§2.4-3）。
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: scrollPadding,
            child: CaptureConfirmCard(
              form: form,
              controller: controller,
              onConfirm: onConfirm,
              showActions: false,
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: CaptureErrorText(text: errorText!),
          ),
        Padding(
          padding: footerPadding,
          child: CaptureConfirmActions(
            form: form,
            controller: controller,
            onConfirm: onConfirm,
          ),
        ),
      ],
    );
  }
}
