/// RRULE 实例展开（RFC5545 子集；§11.2 W13「待办完整版（RRULE+提醒）」、
/// §3.6 待办完整版 P1「重复（RRULE RFC5545）」）。
///
/// W13 基础档覆盖（与计划 Tab 重复选择器产出一致）：
/// - `FREQ=DAILY / WEEKLY / MONTHLY`；
/// - `INTERVAL=n`（缺省 1）；
/// - `COUNT=n` / `UNTIL=日期`（含 DTSTART 本体；COUNT 语义自锚点起计——
///   展开窗口 [rangeStart, rangeEnd) 之外的实例也计入次数）；
/// - `BYDAY=MO,TU,…`（仅 WEEKLY；缺省=锚点星期）。
///
/// 其余 RRULE 部件（BYSETPOS/BYMONTHDAY/FREQ=YEARLY 等）**不做**——按基础档
/// 降级（未知部件忽略、按主频展开），不抛错：重复待办展示与提醒宁缺勿炸
/// （§6.1 降级纪律）。展开为纯本地计算、确定性可测（fake clock 注入由调用方
/// 承担，本文件只吃日期入参）。
library;

/// `RRULE:` 前缀容忍（存量/手工数据可能带前缀）。
final RegExp _rrulePrefix = RegExp('^RRULE:', caseSensitive: false);

/// RFC5545 星期码 → DateTime.weekday（周一=1 … 周日=7）。
const Map<String, int> _weekdayByCode = <String, int>{
  'MO': DateTime.monday,
  'TU': DateTime.tuesday,
  'WE': DateTime.wednesday,
  'TH': DateTime.thursday,
  'FR': DateTime.friday,
  'SA': DateTime.saturday,
  'SU': DateTime.sunday,
};

/// 展开一条 RRULE 在 `[rangeStart, rangeEnd)`（日期语义，含起不含终）内的
/// 实例日列表（升序、去重、全部为当日 00:00 本地时间）。
///
/// - [anchor]：展开锚点日（§5.5⑩ rrule_anchor_date，DTSTART 语义）；
/// - [rangeStart]/[rangeEnd]：调度窗口（提醒调度用「今天 → 今天+horizon」；
///   展示层可传更长窗口）；
/// - [maxInstances]：防御上限（病态规则不炸调度器，§6.1）。
///
/// 空 RRULE / 无法解析 FREQ → 返回空列表（调用方按无实例处理）。
List<DateTime> expandRruleInstances({
  required String rrule,
  required DateTime anchor,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  int maxInstances = 64,
}) {
  final parts = _parseRrule(rrule);
  final freq = parts['FREQ']?.toUpperCase();
  if (freq == null) {
    return const <DateTime>[];
  }
  final interval = _parsePositiveInt(parts['INTERVAL']) ?? 1;
  final count = _parsePositiveInt(parts['COUNT']);
  final untilEnd = _parseUntilEndOfDay(parts['UNTIL']);

  final anchorDay = _dateOnly(anchor);
  final startDay = _dateOnly(rangeStart);
  final endDay = _dateOnly(rangeEnd);

  final instances = <DateTime>[];
  var emitted = 0; // 自锚点起的实例计数（COUNT 口径，含窗口外）。

  void consider(DateTime candidate) {
    final day = _dateOnly(candidate);
    // COUNT/UNTIL 边界：自锚点起逐个计数，超界即止（RFC 语义）。
    emitted++;
    if (count != null && emitted > count) {
      return;
    }
    if (untilEnd != null && day.isAfter(untilEnd)) {
      return;
    }
    if (!day.isBefore(startDay) && day.isBefore(endDay)) {
      instances.add(day);
    }
  }

  // 生成器统一走「自锚点顺序枚举 + consider」，保证 COUNT 计数口径一致。
  switch (freq) {
    case 'DAILY':
      for (var k = 0; k < maxInstances * interval + interval; k++) {
        final day = anchorDay.add(Duration(days: k * interval));
        if (count == null &&
            untilEnd == null &&
            day.isAfter(endDay.add(const Duration(days: 1)))) {
          break;
        }
        if (instances.length >= maxInstances) break;
        consider(day);
        if (count != null && emitted > count) break;
        if (untilEnd != null && day.isAfter(untilEnd)) break;
      }
    case 'WEEKLY':
      final bydays = _parseByday(parts['BYDAY']);
      final weekAnchorMonday = _mondayOf(anchorDay);
      outer:
      for (var w = 0;; w++) {
        final weekMonday = weekAnchorMonday.add(Duration(days: w * interval * 7));
        final daysInWeek = (bydays.isEmpty
                ? <int>[anchorDay.weekday]
                : (bydays.toList()..sort()))
            .map((weekday) => weekMonday.add(Duration(days: weekday - 1)))
            .where((day) => !day.isBefore(anchorDay))
            .toList();
        if (daysInWeek.isEmpty && bydays.isNotEmpty) {
          continue; // 本周候选全早于锚点：推进下周（COUNT 不计）。
        }
        for (final day in daysInWeek) {
          consider(day);
          if (count != null && emitted > count) break outer;
          if (untilEnd != null && day.isAfter(untilEnd)) break outer;
          if (instances.length >= maxInstances) break outer;
          if (day.isAfter(endDay.add(const Duration(days: 1)))) break outer;
        }
        if (w > 520) break; // ~10 年防御上限。
      }
    case 'MONTHLY':
      outer:
      for (var m = 0;; m++) {
        final monthIndex = anchorDay.year * 12 + (anchorDay.month - 1) + m * interval;
        final year = monthIndex ~/ 12;
        final month = monthIndex % 12 + 1;
        final day = _safeDate(year, month, anchorDay.day);
        if (day != null) {
          consider(day);
          if (count != null && emitted > count) break outer;
          if (untilEnd != null && day.isAfter(untilEnd)) break outer;
          if (instances.length >= maxInstances) break outer;
        }
        // 无效日（如 2 月 30 日）跳过当月但不终止；推进终止条件：
        if (day != null && day.isAfter(endDay.add(const Duration(days: 1)))) {
          break outer;
        }
        if (m > 240) break; // ~20 年防御上限。
      }
    default:
      return const <DateTime>[]; // 未知 FREQ：降级为无实例（§6.1）。
  }
  return instances;
}

/// 解析 RRULE 文本为键值表（容忍 `RRULE:` 前缀；键名统一大写）。
Map<String, String> _parseRrule(String rrule) {
  final result = <String, String>{};
  final body = rrule.trim().replaceFirst(_rrulePrefix, '');
  for (final segment in body.split(';')) {
    final s = segment.trim();
    if (s.isEmpty) continue;
    final eq = s.indexOf('=');
    if (eq <= 0) continue;
    result[s.substring(0, eq).trim().toUpperCase()] =
        s.substring(eq + 1).trim();
  }
  return result;
}

List<int> _parseByday(String? byday) {
  if (byday == null || byday.isEmpty) return const <int>[];
  final result = <int>[];
  for (final token in byday.toUpperCase().split(',')) {
    final weekday = _weekdayByCode[token.trim()];
    if (weekday != null) result.add(weekday);
  }
  return result;
}

int? _parsePositiveInt(String? raw) {
  if (raw == null) return null;
  final v = int.tryParse(raw.trim());
  return (v != null && v > 0) ? v : null;
}

/// `UNTIL` 值 → 当日 23:59:59.999（含当日；`yyyy-MM-dd` 或 `yyyyMMdd[THH…[Z]]`
/// 的日期段都取前 8 位数字口径）。
DateTime? _parseUntilEndOfDay(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 8) return null;
  final y = int.parse(digits.substring(0, 4));
  final m = int.parse(digits.substring(4, 6));
  final d = int.parse(digits.substring(6, 8));
  return DateTime(y, m, d, 23, 59, 59, 999);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOf(DateTime day) =>
    day.subtract(Duration(days: day.weekday - 1));

/// 当月无此日（如 2 月 30）返回 null（MONTHLY 跳过当月）。
DateTime? _safeDate(int year, int month, int day) {
  final candidate = DateTime(year, month, day);
  if (candidate.year == year && candidate.month == month && candidate.day == day) {
    return candidate;
  }
  return null;
}
