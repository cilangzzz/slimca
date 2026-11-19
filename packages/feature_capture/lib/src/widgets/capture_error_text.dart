/// 表单/提交错误文案（§10.1 NNg 表单错误规则、反模式 D8）。
///
/// 错误呈现纪律：错误信息显示在问题字段下方或旁边；**颜色 + 图标双编码**
/// （红=错误，禁止只靠颜色）；文案平实、不带错误码（P8）。capture 域内
/// 所有错误行（提交失败/降级提示/字段校验）统一经本组件呈现，不再各自手拼。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 错误文案行：error 图标 + 文本（12sp body-small 辅助档，danger 色）。
class CaptureErrorText extends StatelessWidget {
  const CaptureErrorText({
    super.key,
    required this.text,
    this.testKey,
  });

  /// 错误文案（平实语言 + 建设性解决口径，P8）。
  final String text;

  /// 测试锚点（挂到文本上，保持既有 ValueKey 断言兼容）。
  final Key? testKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, size: 16, color: tokens.danger),
        SizedBox(width: context.spacing.space100),
        Expanded(
          child: Text(
            text,
            key: testKey,
            style: TextStyle(fontSize: 12, color: tokens.danger),
          ),
        ),
      ],
    );
  }
}
