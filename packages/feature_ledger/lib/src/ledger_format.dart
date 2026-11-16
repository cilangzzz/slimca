/// 账本域展示格式化与解析（§5.1 金额口径：金额一律 INTEGER 分，
/// kcal 一律 INTEGER——展示层做格式化/解析，全程不引入 double 浮点）。
library;

/// 金额/热量格式化助手（§5.1 金额=分、kcal=整数；§2.1② 金额四位精度
/// 交给解析层，展示恒两位小数）。
abstract final class LedgerFormat {
  /// 金额文本 `¥18.50`（千分位分组 `¥1,234.50`；负数 `-¥8.50`，
  /// 用于"预算余"为负前的差额展示场景）。
  static String moneyMinor(int minor) {
    final bool negative = minor < 0;
    final int abs = negative ? -minor : minor;
    final int yuan = abs ~/ 100;
    final String cents = '${abs % 100}'.padLeft(2, '0');
    return '${negative ? '-' : ''}¥${_groupThousands(yuan)}.$cents';
  }

  /// 带符号金额 `+¥5,000.00`（收入行用；负数原样带负号）。
  static String signedMoneyMinor(int minor) =>
      minor > 0 ? '+${moneyMinor(minor)}' : moneyMinor(minor);

  /// 热量文本 `650 kcal`。
  static String kcal(int value) => '$value kcal';

  /// 用户输入的人民币元文本 → 分（§3.4 目标/金额录入口径）。接受
  /// `10` / `10.5` / `10.50`（最多两位小数）；非法或负数返回 null——
  /// 由调用方展示错误，不做静默截断。
  static int? parseYuanToMinor(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final RegExpMatch? match =
        RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text);
    if (match == null) {
      return null;
    }
    final int yuan = int.parse(match.group(1)!);
    final String fraction = match.group(2) ?? '';
    final int cents = fraction.isEmpty
        ? 0
        : fraction.length == 1
            ? int.parse(fraction) * 10
            : int.parse(fraction);
    return yuan * 100 + cents;
  }

  /// 分 → 可被 [parseYuanToMinor] 原样解析回的输入框回填文本（去掉
  /// `¥` 与千分位：1000→`10`、1050→`10.5`、1055→`10.55`）。
  static String yuanInputText(int minor) {
    final int yuan = minor ~/ 100;
    final int cents = minor % 100;
    if (cents == 0) {
      return '$yuan';
    }
    if (cents % 10 == 0) {
      return '$yuan.${cents ~/ 10}';
    }
    return '$yuan.${cents.toString().padLeft(2, '0')}';
  }


  /// 用户输入的热量 kcal 文本 → 整数（正整数上限 99999，§3.4 每日目标
  /// 口径；非法/越界返回 null 由调用方展示错误）。
  static int? parseKcal(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) {
      return null;
    }
    final int? value = int.tryParse(text);
    if (value == null || value <= 0 || value > 99999) {
      return null;
    }
    return value;
  }

  /// 整数千分位分组（展示用，避免正则逐字符拼接的开销——直接位数分组）。
  static String _groupThousands(int value) {
    final String digits = value.toString();
    if (digits.length <= 3) {
      return digits;
    }
    final StringBuffer buffer = StringBuffer();
    final int headLength = digits.length % 3;
    if (headLength > 0) {
      buffer.write(digits.substring(0, headLength));
    }
    for (int index = headLength; index < digits.length; index += 3) {
      if (buffer.isNotEmpty) {
        buffer.write(',');
      }
      buffer.write(digits.substring(index, index + 3));
    }
    return buffer.toString();
  }
}
