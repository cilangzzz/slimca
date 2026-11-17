// 本文件仅做纯日期算术（DateTime 为 dart:core 类型，无 Flutter 依赖）。

// 日历组件族（SlimcaCalendarStrip / SlimcaMonthGrid / SlimcaCalendar）内部共用
// 的日期工具；不进 ui_kit 公开 API。
//
// 约定：所有算术在 UTC 域进行（UTC 无夏令时，`Duration` 天数精确），
// 展示/回调仅在本地日界（y/m/d）转换——与宿主 `SelectedDate.normalizeDate`
// 的「本地 y/m/d 日界」口径一致。

/// 本地日界归一化（剥离时刻，保留 y/m/d）。
DateTime slimcaDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// UTC 日界（同 y/m/d 的 UTC 午夜；后续算术用，防 DST 漂移）。
DateTime slimcaUtcDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// UTC 日期 → 本地日界（展示/回调出口）。
DateTime slimcaLocalFromUtc(DateTime utcDate) =>
    DateTime(utcDate.year, utcDate.month, utcDate.day);

/// 周起始（[weekStart]：1=周一..7=周日，DateTime.weekday 口径；宿主缺省取
/// MaterialLocalizations.firstDayOfWeekIndex 换算）。入参/出参均在同一时区域
/// （建议 UTC）。
DateTime slimcaStartOfWeek(DateTime d, int weekStart) {
  assert(
    weekStart >= DateTime.monday && weekStart <= DateTime.sunday,
    'weekStart 限 DateTime.weekday 口径 1-7',
  );
  final int offset = (d.weekday - weekStart) % 7;
  return d.subtract(Duration(days: offset));
}

/// 加 n 天（建议在 UTC 域调用，Duration 精确）。
DateTime slimcaAddDays(DateTime d, int days) => d.add(Duration(days: days));

/// 当月天数（本地 y/m 入参；公历规则，无时区依赖）。
int slimcaDaysInMonth(int year, int month) {
  // 「下月 0 日」= 本月最后一日（DateTime 构造器自动归一化，无 Duration 算术）
  return DateTime(year, month + 1, 0).day;
}

/// 加 n 月（日超出目标月长度时钳制到月末，如 1/31 + 1 月 → 2/28）。
DateTime slimcaAddMonths(DateTime d, int months) {
  final int total = d.year * 12 + (d.month - 1) + months;
  final int year = total ~/ 12;
  final int month = total % 12 + 1;
  final int day = d.day > slimcaDaysInMonth(year, month)
      ? slimcaDaysInMonth(year, month)
      : d.day;
  return DateTime(year, month, day);
}

/// 当月首日（本地域）。
DateTime slimcaFirstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
