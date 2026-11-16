import 'package:flutter/material.dart';

import '../tokens/slimca_theme.dart';
import 'count_up.dart';

/// 金额展示文本工具（§5.1「金额一律 INTEGER 最小货币单位『分』」→ 元展示）。
///
/// 与 feature_capture.CaptureMoney（编辑回填）同口径、与 feature_dashboard
/// 卡片墙金额展示同格式：¥ + 千位分组 + 恒 2 位小数，负值带符号；
/// 全程整数运算，不产生 double 中间值（§5.1 金额禁浮点）。
abstract final class SlimcaMoneyText {
  /// 分 → 展示文本：1850 → "¥18.50"，123456 → "¥1,234.56"，-990 → "-¥9.90"。
  static String format(int minor) {
    final bool negative = minor < 0;
    final int absMinor = negative ? -minor : minor;
    final int yuan = absMinor ~/ 100;
    final String cents = '${absMinor % 100}'.padLeft(2, '0');
    return '${negative ? '-' : ''}¥${_groupThousands(yuan)}.$cents';
  }

  /// 千位分组（仅展示用，不参与存储/同步，§5.1）。
  static String _groupThousands(int value) {
    final String digits = '$value';
    final StringBuffer grouped = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final int remaining = digits.length - i;
      grouped.write(digits[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        grouped.write(',');
      }
    }
    return grouped.toString();
  }
}

/// 金额 count-up（§9.3#4「AI 返回：双数字 count-up……count-up 800ms easeOutExpo」
/// 的金额侧；确认卡金额行确认落库/份量点改联动时滚动，§2.3 步骤 3/4）。
///
/// 复用 [SlimcaCountUp] 的 tween 骨架（时长 MotionConfig.countUp 800ms、
/// 曲线 easeOutExpo、off 档自动降级 100ms 线性淡入淡出，§9.6），本组件只补：
/// 分→元格式化（[SlimcaMoneyText.format]，§5.1）与金额语义 token 取色
/// （收入 moneyIn / 支出 moneyOut，§8.2 双主色锚定「橘是钱」）。
class SlimcaMoneyCountUp extends StatelessWidget {
  const SlimcaMoneyCountUp({
    super.key,
    required this.amountMinor,
    this.income = false,
    this.from = 0,
    this.style,
  });

  /// 目标金额（整数分，§5.1；负值按带符号展示，方向语义由 [income] 表达）。
  final int amountMinor;

  /// 收入侧（moneyIn token 色）；缺省 false = 支出/金额主色 moneyOut。
  final bool income;

  /// 首帧起始值（分）；缺省从 0 扫到目标（§9.3#4 count-up 入场）。
  final int from;

  /// 业务可覆盖字号/字重；未指定 color 时按金额语义 token 取色（§8.2）。
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextStyle base = style ?? const TextStyle();
    final TextStyle effective = base.color == null
        ? base.copyWith(color: income ? tokens.moneyIn : tokens.moneyOut)
        : base;
    return SlimcaCountUp(
      value: amountMinor,
      from: from,
      style: effective,
      format: SlimcaMoneyText.format,
    );
  }
}
