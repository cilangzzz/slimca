/// 展示层格式化工具（§5.1 存储口径 ↔ §3.2 展示口径的换算层）。
///
/// 存储纪律（§5.1）：金额一律最小货币单位（分，INTEGER）、热量一律 INTEGER
/// kcal、日期一律本地日历日 `yyyy-MM-dd`——本文件只做「存储值 → 人读文本」
/// 与「人输文本 → 存储值」的换算，不承载业务规则。
library;

/// 分 → `'¥25.50'`（含币符）。
String yuanFromMinor(int minor) => '¥${minorToYuanText(minor)}';

/// 分 → `'25.5'` / `'25.50'` / `'25'`（不含币符；录入预填/表单回显用）。
String minorToYuanText(int minor) {
  final yuan = minor ~/ 100;
  final fen = minor % 100;
  if (fen == 0) return '$yuan';
  return '$yuan.${fen.toString().padLeft(2, '0')}';
}

/// 元字符串 → 分；空串或非法输入返回 null（两位小数上限，避免浮点误差进
/// 存储，§5.1 金额一律 INTEGER 分）。
///
/// 合法形态：`'25'` / `'25.5'` / `'25.50'`。
int? parseYuanToFen(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final yuan = int.parse(m.group(1)!);
  final frac = m.group(2) ?? '';
  final fen = frac.isEmpty
      ? 0
      : (frac.length == 1 ? int.parse(frac) * 10 : int.parse(frac));
  return yuan * 100 + fen;
}

/// `'yyyy-MM-dd'` → `'11月16日'`（非法输入原样返回，展示容错）。
String calendarDayLabel(String yyyyMmDd) {
  final m = RegExp(r'^\d{4}-(\d{2})-(\d{2})$').firstMatch(yyyyMmDd);
  if (m == null) return yyyyMmDd;
  final month = int.parse(m.group(1)!);
  final day = int.parse(m.group(2)!);
  return '$month月$day日';
}
