/// 账本域日历与月口径助手（§5.1 日期约定：date = 本地自然日 TEXT
/// `yyyy-MM-dd`；月前缀 = `yyyy-MM`，固定宽度 TEXT 字典序即时间序）。
///
/// 全部为纯函数（无 I/O、无时钟副作用，测试可全量覆盖）；唯一一处
/// `DateTime.now()` 读数是 [today]，供页面缺省选中"本月"。
library;

/// 月份/日期口径助手（§5.1 日期约定 + §3.4 按日分组/按月求和）。
abstract final class LedgerCalendar {
  /// 月前缀形态校验（§5.1：`yyyy-MM`，月份两位补零，固定宽度保证
  /// TEXT 字典序=时间序）。
  static final RegExp monthPattern = RegExp(r'^\d{4}-\d{2}$');

  /// 自然日形态校验（§5.1：`yyyy-MM-dd`；三个捕获组供 dayGroupTitle/
  /// dayLabel 解析年月日，校验用途不受影响）。
  static final RegExp dayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// 中文长星期（§3.4 日分组头「11月16日 周一」）；DateTime.weekday
  /// 1=周一 … 7=周日，减 1 对位。
  static const List<String> weekdayLong = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 抹掉时分秒，落回本地自然日 0 点（§5.1 date 为本地自然日）。
  static DateTime normalize(DateTime source) =>
      DateTime(source.year, source.month, source.day);

  /// 归位到所在月的 1 号 0 点（月锚点，切月/月标题共用）。
  static DateTime monthAnchor(DateTime source) =>
      DateTime(source.year, source.month);

  /// "今天"（缺省选中月与日简报缺省日期；唯一时钟读数）。
  static DateTime today() => normalize(DateTime.now());

  /// 月前缀 `yyyy-MM`（月份两位补零，§5.1 固定宽度）。
  static String monthPrefix(DateTime source) =>
      '${source.year}-${source.month.toString().padLeft(2, '0')}';

  /// 月锚点平移 [delta] 个月（delta 可负；经 1..12 归一化，跨年安全）。
  static DateTime shiftMonth(DateTime anchor, int delta) {
    var year = anchor.year;
    var month = anchor.month + delta;
    while (month > 12) {
      month -= 12;
      year++;
    }
    while (month < 1) {
      month += 12;
      year--;
    }
    return DateTime(year, month);
  }

  /// 月标题「2026年11月」（§3.4 月份切换条）。
  static String monthTitle(DateTime anchor) =>
      '${anchor.year}年${anchor.month}月';

  /// 月前缀 → 半开区间 `[月初, 次月初)`（§5.1 日期口径；查询
  /// `date >= start AND date < end` 与 core_db 投影/仓库同款）。
  ///
  /// 月前缀非法（非 `yyyy-MM`）时抛 ArgumentError——固定宽度被破坏会
  /// 使 TEXT 字典序失去时间语义，必须硬失败而非静默错查。
  static ({String start, String end}) monthRange(String month) {
    if (!monthPattern.hasMatch(month)) {
      throw ArgumentError.value(
        month,
        'month',
        '必须为 yyyy-MM 月前缀（§5.1 日期口径）',
      );
    }
    final int year = int.parse(month.substring(0, 4));
    final int monthNumber = int.parse(month.substring(5, 7));
    final int nextYear = monthNumber == 12 ? year + 1 : year;
    final int nextMonth = monthNumber == 12 ? 1 : monthNumber + 1;
    final String end =
        '$nextYear-${nextMonth.toString().padLeft(2, '0')}-01';
    return (start: '$month-01', end: end);
  }

  // ── W15 统计报表周期口径（§3.4「周/月/年三档」、§11.2 W15） ────────────

  /// DateTime → `yyyy-MM-dd`（§5.1 固定宽度 TEXT 日期；月份两位补零）。
  static String dayText(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// 周半开区间 `[周一, 次周一)`（§3.4 周档；周起始=周一，与 [weekdayLong]
  /// 「1=周一」口径一致）。
  static ({String start, String end}) weekRange(DateTime day) {
    final DateTime normalized = normalize(day);
    final DateTime monday =
        normalized.subtract(Duration(days: normalized.weekday - 1));
    final DateTime nextMonday =
        DateTime(monday.year, monday.month, monday.day + 7);
    return (start: dayText(monday), end: dayText(nextMonday));
  }

  /// 年半开区间 `[1月1日, 次年1月1日)`（§3.4 年档）。
  static ({String start, String end}) yearRange(DateTime anchor) =>
      (
        start: '${anchor.year}-01-01',
        end: '${anchor.year + 1}-01-01',
      );

  /// 周锚点平移 [delta] 周（锚点恒落回周一 0 点，切周共用）。
  static DateTime shiftWeek(DateTime anchor, int delta) {
    final DateTime normalized = normalize(anchor);
    final DateTime monday =
        normalized.subtract(Duration(days: normalized.weekday - 1));
    final DateTime moved = monday.add(Duration(days: 7 * delta));
    return DateTime(moved.year, moved.month, moved.day);
  }

  /// 年锚点平移 [delta] 年（归位当年 1 月 1 日，切年共用）。
  static DateTime shiftYear(DateTime anchor, int delta) =>
      DateTime(anchor.year + delta);

  /// 周档标题「11月16日 - 11月22日」（区间含首尾；非法日期原样返回）。
  static String weekRangeTitle(String start, String endExclusive) {
    final RegExpMatch? startMatch = dayPattern.firstMatch(start);
    final RegExpMatch? endMatch = dayPattern.firstMatch(endExclusive);
    if (startMatch == null || endMatch == null) {
      return '$start ~ $endExclusive';
    }
    final DateTime endDay = DateTime(
      int.parse(endMatch.group(1)!),
      int.parse(endMatch.group(2)!),
      int.parse(endMatch.group(3)!),
    ).subtract(const Duration(days: 1));
    return '${int.parse(startMatch.group(2)!)}月${int.parse(startMatch.group(3)!)}日'
        ' - ${endDay.month}月${endDay.day}日';
  }

  /// 年档标题「2026年」。
  static String yearTitle(DateTime anchor) => '${anchor.year}年';

  /// 图表 x 轴日桶标签「16日」（非自然日形态原样返回，防御脏数据）。
  static String dayAxisLabel(String date) {
    final RegExpMatch? match = dayPattern.firstMatch(date);
    if (match == null) {
      return date;
    }
    return '${int.parse(match.group(3)!)}日';
  }

  /// 图表 x 轴月桶标签「11月」（非月前缀形态原样返回，防御脏数据）。
  static String monthAxisLabel(String month) {
    if (!monthPattern.hasMatch(month)) {
      return month;
    }
    return '${int.parse(month.substring(5, 7))}月';
  }

  /// 日分组头标题「11月16日 周一」（§3.4 按日分组；非自然日形态原样
  /// 返回，防御脏数据不抛异常影响整页渲染）。
  static String dayGroupTitle(String date) {
    final RegExpMatch? match = dayPattern.firstMatch(date);
    if (match == null) {
      return date;
    }
    final DateTime day = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
    return '${day.month}月${day.day}日 ${weekdayLong[day.weekday - 1]}';
  }

  /// 日简报卡右上角日期标签「11月16日」。
  static String dayLabel(String date) {
    final RegExpMatch? match = dayPattern.firstMatch(date);
    if (match == null) {
      return date;
    }
    return '${int.parse(match.group(2)!)}月${int.parse(match.group(3)!)}日';
  }
}
