/// 本地日历日工具（§5.1「date = 本地日历日 yyyy-MM-dd，一切聚合按 date 分组，
/// 杜绝 UTC 错日」；§3.2「一切记录围绕日期组织」）。
///
/// 全部基于本地时区的年月日运算；日期与月份的 TEXT 口径经
/// core_domain 的 `formatCalendarDay`/`validateCalendarDay` 往返一致（§5.1）。
library;

/// 仪表盘日历助手：归一化/周历条/月份前缀/展示文案。
abstract final class DashboardCalendar {
  /// 归一化：丢弃时分秒，保留本地年月日（§5.1）。
  static DateTime normalize(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 今天的本地日历日。
  static DateTime today() => normalize(DateTime.now());

  /// [d] 所在周的周一（周一为一周起点——§11.1 成文口径 2026-11-16 周一）。
  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// [d] 所在周的 7 天（周一…周日）——周历条数据源（§3.2 周历条）。
  static List<DateTime> weekOf(DateTime d) {
    final DateTime monday = startOfWeek(d);
    return List<DateTime>.generate(
      7,
      (int i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }

  /// 相邻日平移（周历点选/左右滑切日共用，§3.2）。
  static DateTime shift(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// 月份前缀 `yyyy-MM`（DashboardRepository.watchMonthSpendMinor 入参口径，
  /// 与 day_summaries.date 的 TEXT 前缀一致，§5.6⑬）。
  static String monthPrefix(DateTime d) {
    final String m = d.month.toString().padLeft(2, '0');
    return '${d.year}-$m';
  }

  /// 日期大字文案（§3.2「日期大字」）：`11月16日`。
  static String dayTitle(DateTime d) => '${d.month}月${d.day}日';

  /// 周几长标签（日期大字旁注，下标 = weekday-1，周一为 0）。
  static const List<String> weekdayLong = <String>[
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  /// 周历条短标签（下标同上）。
  static const List<String> weekdayShort = <String>[
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '日',
  ];
}
