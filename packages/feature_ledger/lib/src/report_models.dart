/// 统计报表域模型（§3.4「统计报表 P1：周/月/年三档；分类环形占比、趋势
/// 折线；钱-热量双轴联动」、§11.2 W15 主线）。
///
/// 全部为不可变值对象；bucket 键为固定宽度 TEXT（日=`yyyy-MM-dd`、月=
/// `yyyy-MM`，字典序即时间序，§5.1）；金额=分、kcal=整数（§5.1）。
library;

import 'ledger_calendar.dart';

/// 报表周期三档（§3.4「周/月/年三档」）。
enum ReportPeriod {
  /// 周档：[周一, 次周一)，按日分桶。
  week,

  /// 月档：[月初, 次月初)，按日分桶。
  month,

  /// 年档：[1月1日, 次年1月1日)，按月分桶（365 桶不可读，年视图按月聚合）。
  year,
}

/// 已解析的报表查询区间（§5.1 半开区间 `[start, endExclusive)`，与
/// core_db 投影/账单仓库同款日期口径）。
class ReportRange {
  const ReportRange({
    required this.period,
    required this.start,
    required this.endExclusive,
    required this.byMonth,
  });

  /// 周期档（决定标题/切换步进）。
  final ReportPeriod period;

  /// 区间起点（含）`yyyy-MM-dd`。
  final String start;

  /// 区间终点（不含）`yyyy-MM-dd`。
  final String endExclusive;

  /// 是否按月分桶（年档=true；周/月档按日分桶）。
  final bool byMonth;
}

/// 由周期档 + 锚点日解析查询区间（§3.4 三档口径经 LedgerCalendar 复用）。
ReportRange reportRangeFor(ReportPeriod period, DateTime anchor) {
  switch (period) {
    case ReportPeriod.week:
      final range = LedgerCalendar.weekRange(anchor);
      return ReportRange(
        period: period,
        start: range.start,
        endExclusive: range.end,
        byMonth: false,
      );
    case ReportPeriod.month:
      final range = LedgerCalendar.monthRange(
        LedgerCalendar.monthPrefix(LedgerCalendar.monthAnchor(anchor)),
      );
      return ReportRange(
        period: period,
        start: range.start,
        endExclusive: range.end,
        byMonth: false,
      );
    case ReportPeriod.year:
      final range = LedgerCalendar.yearRange(anchor);
      return ReportRange(
        period: period,
        start: range.start,
        endExclusive: range.end,
        byMonth: true,
      );
  }
}

/// 枚举区间内全部桶键（日桶=`yyyy-MM-dd`、月桶=`yyyy-MM`；升序）。
///
/// 零填充的桶轴：图表 x 轴恒展示完整区间（无数据桶画零值），选中态与
/// 数据桶对齐（双轴联动按索引寻址的前提）。
List<String> reportBucketKeys(ReportRange range) {
  final List<String> keys = <String>[];
  if (range.byMonth) {
    final int startYear = int.parse(range.start.substring(0, 4));
    int month = int.parse(range.start.substring(5, 7));
    final int endYear = int.parse(range.endExclusive.substring(0, 4));
    final int endMonth = int.parse(range.endExclusive.substring(5, 7));
    var year = startYear;
    while (year < endYear || (year == endYear && month < endMonth)) {
      keys.add('$year-${month.toString().padLeft(2, '0')}');
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
    return keys;
  }
  DateTime day = DateTime.parse(range.start);
  final DateTime end = DateTime.parse(range.endExclusive);
  while (day.isBefore(end)) {
    keys.add(LedgerCalendar.dayText(day));
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return keys;
}

/// 一个桶（日/月）的钱+热量聚合点（§3.4 双轴联动数据源；口径与
/// day_summary 投影一致——kcal_in/out、spend/income_minor）。
class ReportBucketPoint {
  const ReportBucketPoint({
    required this.bucketKey,
    required this.spendMinor,
    required this.incomeMinor,
    required this.kcalIn,
    required this.kcalOut,
  });

  /// 桶键：日桶 `yyyy-MM-dd` / 月桶 `yyyy-MM`。
  final String bucketKey;

  /// 支出（分）/收入（分）。
  final int spendMinor;
  final int incomeMinor;

  /// 摄入/消耗 kcal。
  final int kcalIn;
  final int kcalOut;

  /// 净热量（摄入-消耗，§3.5）。
  int get netKcal => kcalIn - kcalOut;
}

/// 桶 × 分类支出切片（§3.4「金额按分类堆叠条形」数据源；money-out 行）。
class ReportCategoryStack {
  const ReportCategoryStack({
    required this.bucketKey,
    required this.categoryId,
    required this.categoryName,
    required this.colorToken,
    required this.spendMinor,
  });

  /// 桶键（同 [ReportBucketPoint.bucketKey]）。
  final String bucketKey;

  /// 分类 id；null=未分类行（category_id IS NULL，§5.2②）。
  final String? categoryId;
  final String? categoryName;

  /// 语义色 token 名（§8.2；渲染经 ledgerColorFromToken 解析）。
  final String? colorToken;

  /// 该桶该分类支出合计（分）。
  final int spendMinor;
}
