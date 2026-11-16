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
