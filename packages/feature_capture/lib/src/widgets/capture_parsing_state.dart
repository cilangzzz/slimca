/// 解析中呼吸态（§2.3 步骤 3「AI 解析：输入气泡立即上浮不等 AI；抽屉原地
/// 转为确认卡」的等待帧；§9.4「AI 等待骨架出现 ≤100ms」）。
///
/// 呼吸复用 ui_kit [SlimcaBreath]（§9.3#4 等待区零 spinner：opacity/scale
/// 双通道循环，周期 = 4 × dur.l 由 token 推导；MotionLevel=off 自动退化为
/// 100ms 淡入静置，§9.6）。本组件只组装骨架内容。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 呼吸态测试锚点。
const Key captureParsingStateKey = ValueKey('capture_parsing_state');

/// 解析中骨架（呼吸态）：环形占位 + 提示语，经 [SlimcaBreath] 一吸一呼。
class CaptureParsingState extends StatelessWidget {
  const CaptureParsingState({super.key, this.label = 'AI 解析中…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return SlimcaBreath(
      child: Container(
        key: captureParsingStateKey,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: tokens.surfaceCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: CircularProgressIndicator(
                      strokeWidth: 6,
                      color: tokens.kcalIn,
                    ),
                  ),
                  Icon(Icons.auto_awesome, size: 26, color: tokens.kcalIn),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '热量与金额将经置信度标注返回（§7.1）',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
          ],
        ),
      ),
    );
  }
}
