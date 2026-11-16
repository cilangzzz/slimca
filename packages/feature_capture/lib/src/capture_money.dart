/// 手动记账金额输入模型（§3.4 流水记账「金额整数分存储」、§5.1 金额约定）。
///
/// 键盘输入以纯字符串建模（整数段 + 可选 ≤2 位小数段）；转换为「分」时
/// 全程字符串/整数运算，杜绝 double 浮点参与金额（§5.1：金额一律 INTEGER
/// 最小货币单位「分」——浮点在多端同步与聚合中不可复现）。
library;

/// 金额文本工具集：数字键盘步进 + 「元文本 ↔ 分」互转。
///
/// 输入态（amountText）是用户键入的原始串，如 ""、"18"、"18.5"、"18.50"；
/// 提交态（分）是 [toMinorUnits] 的结果。两者都不经过浮点。
abstract final class CaptureMoney {
  /// 整数段（元）最大位数：¥9,999,999.99 上限（手动记账的合理量程）。
  static const int maxIntegerDigits = 9;

  /// 合法金额文本形态：≤9 位整数 + 可选小数点与 ≤2 位小数。
  static final RegExp _pattern = RegExp(r'^\d{1,9}(\.\d{0,2})?$');

  /// 追加一位数字；违反规则时原样返回（键盘无感，§3.3 写通道）。
  static String appendDigit(String text, String digit) {
    if (digit.length != 1 || int.tryParse(digit) == null) return text;
    final dot = text.indexOf('.');
    if (dot >= 0) {
      // 已有小数点：小数段最多 2 位（分精度，§5.1）。
      if (text.length - dot - 1 >= 2) return text;
      return text + digit;
    }
    // 整数段：前导 0 直接替换（"0" + "5" → "5"）；"0." 分支走上面小数段。
    if (text == '0') return digit;
    if (text.length >= maxIntegerDigits) return text;
    return text + digit;
  }

  /// 追加小数点；空输入视为 "0."，已有小数点时原样返回。
  static String appendDot(String text) {
    if (text.contains('.')) return text;
    return text.isEmpty ? '0.' : '$text.';
  }

  /// 退格：删除末位字符；空输入原样返回。
  static String backspace(String text) =>
      text.isEmpty ? text : text.substring(0, text.length - 1);

  /// 「元文本」→ 分（§5.1）；空/非法返回 null。
  ///
  /// 纯字符串/整数运算：整数段 ×100 + 小数段右补齐 2 位，
  /// 不产生任何 double 中间值。
  static int? toMinorUnits(String text) {
    if (text.isEmpty || !_pattern.hasMatch(text)) return null;
    final dot = text.indexOf('.');
    final yuan = dot < 0 ? text : text.substring(0, dot);
    final frac = dot < 0 ? '' : text.substring(dot + 1);
    final fracPadded = frac.padRight(2, '0');
    return int.parse(yuan) * 100 + int.parse(fracPadded);
  }

  /// 分 → 「元文本」（编辑回填）：1850 → "18.50"（§5.1 整数分口径）。
  static String fromMinorUnits(int minor) {
    assert(minor >= 0, '金额不允许负值，方向由 direction 表达（§5.2②）');
    final yuan = minor ~/ 100;
    final frac = (minor % 100).toString().padLeft(2, '0');
    return '$yuan.$frac';
  }

  /// 展示文本：空输入占位 "0.00"，否则原样（保留输入中的小数点）。
  static String displayText(String text) => text.isEmpty ? '0.00' : text;
}
