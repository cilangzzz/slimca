/// 计划域编辑抽屉稳定高度（与 feature_capture captureSheetHeight 同一口径
/// 的包内复刻）。
///
/// 口径来源（用户定稿「弹层高度不随内容缩放」）：中低高度、内容填充、主 CTA
/// 钉底——取视口高的 62%、带限 480–640，横屏/极小屏 `min(·, height)` 防溢出。
/// 各状态（档位/键盘）切换均不改变抽屉外框尺寸；键盘避让由抽屉内容按
/// `MediaQuery.viewInsetsOf(context).bottom` 收缩内容区（外框恒定）。
///
/// 复刻而非引依赖的取舍：captureSheetHeight 在 feature_capture 内（私有于
/// capture_page.dart:62 同源公式），feature_plan 引它将新增包间依赖边
/// （feature_plan → feature_capture）——公式三行、语义同源，包内私有复刻
/// 零耦合；两端后续若调整口径需同步（本注释即同步锚点）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 计划域编辑抽屉统一高度（TodoEditorSheet / SavingsGoalEditorSheet /
/// FitnessPlanEditorSheet 共用；与 capture_page.dart:62 captureSheetHeight
/// 同公式同源）。
double planSheetHeight(BuildContext context) {
  final height = MediaQuery.sizeOf(context).height;
  final bounded = math.min(math.max(height * 0.62, 480.0), 640.0);
  return math.min(bounded, height);
}
