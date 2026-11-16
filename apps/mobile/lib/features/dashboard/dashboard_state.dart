import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 仪表盘当前选中日期状态（§3.2「一切围绕日期」）。
///
/// 设计决策：
/// - 日期一律归一化为本地日历日（时分秒清零），杜绝 UTC 错日——与 §5.1
///   「date = 本地日历日 yyyy-MM-dd，一切聚合按 date 分组」同一纪律；
/// - Riverpod 3 用 NotifierProvider（§10.1 状态选型），W2 接入 day_summary
///   投影流后，本 provider 只保留日期，聚合数据走 core_db stream（§5.6 ⑬）。
final selectedDateProvider =
    NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() => normalizeDate(DateTime.now());

  /// 选中周历条上的某一天。
  void select(DateTime date) => state = normalizeDate(date);

  /// 左右滑切日（§3.2 周历条，共享轴转场 ≤280ms，§2.3 步 7）。
  void shiftByDays(int days) {
    final d = state;
    state = DateTime(d.year, d.month, d.day + days);
  }

  /// 归一化：丢弃时分秒，保留本地年月日。
  static DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 给定日期所在周的周一（周一为一周起点，与文档成文口径 2026-11-16 周一一致）。
  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// 返回 [d] 所在周的 7 天（周一…周日）。
  static List<DateTime> weekOf(DateTime d) {
    final monday = startOfWeek(d);
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }
}
