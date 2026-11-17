/// RRULE（RFC5545）v1 子集 + 提醒时刻换算（§3.6 待办完整版 P1、§5.5⑩
/// repeat_rule / rrule_anchor_date / remind_at、§11.2 W13 主线）。
///
/// 展开策略取舍（任务口径，§3.6/§11.2 W13）：**查询时按 anchor 展开当日实例，
/// 不预生成行**——todos 表只存规则基行（repeat_rule=RRULE 文本 +
/// rrule_anchor_date=DTSTART 展开锚点日），某日待办清单 =
/// 非重复行（date=当日）∪ 重复基行展开命中当日的虚拟实例。取舍理由：
/// - 不物化实例行 → 同步行数 O(规则数) 而非 O(实例数)，出网/游标压力小
///   （§6.1 append-first）；
/// - 勾选/编辑/删除始终作用于基行，done_at 只前进合并（§6.5）不受实例化
///   干扰，无「实例行合并歧义」；
/// - 代价：实例完成状态只能挂在基行单列 done_at 上——本域以「done_at 落在
///   实例日」判定当日实例完成（见 plan_gateway.watchTodoDayInstances），
///   历史多实例的完成痕迹不逐日回溯（§5.5⑩ 冻结列清单无逐实例状态列，
///   v1 接受；升级路径是逐实例物化行，届时走 §6.4 只加表演进）。
///
/// 支持的规则子集（§3.6 W13 编辑器档位）：DAILY（含 INTERVAL=N 自定义间隔）、
/// WEEKLY（BYDAY 单值）、MONTHLY（BYMONTHDAY 单值）。解析对未知键/坏值
/// 防御回退 null（§7.4 健壮性：坏规则不展开、不当重复处理，不抛错打断渲染）。
library;

import 'package:core_domain/core_domain.dart' as dom;

/// 支持的规则形态（编辑器结构化档位，§3.6 W13）。
enum TodoRepeatKind {
  /// 不重复（repeat_rule 落 NULL）。
  none,

  /// 每天（FREQ=DAILY;INTERVAL=1）。
  daily,

  /// 每周 [TodoRepeatSpec.weekday]（FREQ=WEEKLY;BYDAY=…）。
  weekly,

  /// 每月 [TodoRepeatSpec.monthDay] 日（FREQ=MONTHLY;BYMONTHDAY=…）。
  monthly,

  /// 自定义间隔 [TodoRepeatSpec.intervalDays] 天（FREQ=DAILY;INTERVAL=N，N≥2）。
  everyNDays,
}

/// 结构化重复规则（编辑器 UI 形态）：落库前经 [toRrule] 转 RFC5545 文本，
/// 读侧经 [fromRrule] 还原为结构化摘要。
class TodoRepeatSpec {
  const TodoRepeatSpec._(
    this.kind, {
    this.weekday = 1,
    this.monthDay = 1,
    this.intervalDays = 2,
  });

  /// 不重复。
  const TodoRepeatSpec.none() : this._(TodoRepeatKind.none);

  /// 每天。
  const TodoRepeatSpec.daily() : this._(TodoRepeatKind.daily);

  /// 每周 [weekday]（1=周一…7=周日）。
  const TodoRepeatSpec.weekly(int weekday)
      : this._(TodoRepeatKind.weekly, weekday: weekday);

  /// 每月 [monthDay] 日（1-31；小月无该日则当月跳过，RFC5545 语义）。
  const TodoRepeatSpec.monthly(int monthDay)
      : this._(TodoRepeatKind.monthly, monthDay: monthDay);

  /// 每 [intervalDays] 天（N≥2；N=1 等价 daily，编辑器归一为 daily）。
  const TodoRepeatSpec.everyNDays(int intervalDays)
      : this._(TodoRepeatKind.everyNDays, intervalDays: intervalDays);

  final TodoRepeatKind kind;

  /// weekly 档：1=周一…7=周日（DateTime.weekday 同口径）。
  final int weekday;

  /// monthly 档：月内日 1-31。
  final int monthDay;

  /// everyNDays 档：间隔天数（≥2）。
  final int intervalDays;

  /// 转 RFC5545 文本（§5.5⑩ repeat_rule）；none 档返回 null（落 NULL）。
  String? toRrule() => switch (kind) {
        TodoRepeatKind.none => null,
        TodoRepeatKind.daily => 'FREQ=DAILY;INTERVAL=1',
        TodoRepeatKind.weekly =>
          'FREQ=WEEKLY;INTERVAL=1;BYDAY=${weekdayCode(weekday)}',
        TodoRepeatKind.monthly =>
          'FREQ=MONTHLY;INTERVAL=1;BYMONTHDAY=$monthDay',
        TodoRepeatKind.everyNDays => 'FREQ=DAILY;INTERVAL=$intervalDays',
      };

  /// RFC5545 文本 → 结构化规则；空文本/无法识别的子集返回 none/不可展开形态。
  ///
  /// 防御口径（§7.4）：解析失败的文本返回 null（调用方按非重复基行处理），
  /// 不抛错——远端可写入本端未支持的扩展规则。
  static TodoRepeatSpec? fromRrule(String? text) {
    final rule = parseRrule(text);
    if (rule == null) return null;
    switch (rule.freq) {
      case 'DAILY':
        if (rule.interval > 1) return TodoRepeatSpec.everyNDays(rule.interval);
        return const TodoRepeatSpec.daily();
      case 'WEEKLY':
        if (rule.byDay.length == 1) {
          return TodoRepeatSpec.weekly(rule.byDay.first);
        }
        return null; // 多 BYDAY 等扩展子集：编辑器不映射，读侧仅展开
      case 'MONTHLY':
        final monthDay = rule.byMonthDay;
        if (monthDay != null) return TodoRepeatSpec.monthly(monthDay);
        return null;
      default:
        return null;
    }
  }

  /// 编辑器展示摘要（§3.6 中文文案）。
  String get label => switch (kind) {
        TodoRepeatKind.none => '不重复',
        TodoRepeatKind.daily => '每天',
        TodoRepeatKind.weekly => '每周${weekdayLabel(weekday)}',
        TodoRepeatKind.monthly => '每月$monthDay日',
        TodoRepeatKind.everyNDays => '每$intervalDays天',
      };

  @override
  bool operator ==(Object other) =>
      other is TodoRepeatSpec &&
      other.kind == kind &&
      other.weekday == weekday &&
      other.monthDay == monthDay &&
      other.intervalDays == intervalDays;

  @override
  int get hashCode => Object.hash(kind, weekday, monthDay, intervalDays);
}

/// weekday（1=周一…7=周日）→ RFC5545 BYDAY 两字母码。
String weekdayCode(int weekday) => switch (weekday) {
      1 => 'MO',
      2 => 'TU',
      3 => 'WE',
      4 => 'TH',
      5 => 'FR',
      6 => 'SA',
      7 => 'SU',
      _ => 'MO', // 越界防御回退周一（§7.4）
    };

/// weekday（1=周一…7=周日）→ 中文标签（§3.6 编辑器/瓦片摘要）。
String weekdayLabel(int weekday) => switch (weekday) {
      1 => '一',
      2 => '二',
      3 => '三',
      4 => '四',
      5 => '五',
      6 => '六',
      7 => '日',
      _ => '一',
    };

/// RFC5545 文本 → BYDAY 两字母码。
int? _weekdayFromCode(String code) => switch (code) {
      'MO' => 1,
      'TU' => 2,
      'WE' => 3,
      'TH' => 4,
      'FR' => 5,
      'SA' => 6,
      'SU' => 7,
      _ => null,
    };

/// 已解析的 RRULE 子集（§5.5⑩ repeat_rule）。
class RrulePattern {
  const RrulePattern({
    required this.freq,
    this.interval = 1,
    this.byDay = const {},
    this.byMonthDay,
  });

  /// DAILY / WEEKLY / MONTHLY（其他 FREQ 解析失败 → null）。
  final String freq;

  /// INTERVAL（≥1）。
  final int interval;

  /// WEEKLY BYDAY（1=周一…7=周日）。
  final Set<int> byDay;

  /// MONTHLY BYMONTHDAY（1-31）。
  final int? byMonthDay;
}

/// 解析 RRULE 文本（v1 子集；未知键忽略、坏值整体返回 null，§7.4）。
RrulePattern? parseRrule(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  String? freq;
  int interval = 1;
  final byDay = <int>{};
  int? byMonthDay;
  for (final part in text.trim().toUpperCase().split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final key = part.substring(0, i).trim();
    final value = part.substring(i + 1).trim();
    switch (key) {
      case 'FREQ':
        freq = value;
      case 'INTERVAL':
        final n = int.tryParse(value);
        if (n == null || n < 1) return null;
        interval = n;
      case 'BYDAY':
        for (final code in value.split(',')) {
          final weekday = _weekdayFromCode(code.trim());
          if (weekday == null) return null;
          byDay.add(weekday);
        }
      case 'BYMONTHDAY':
        final n = int.tryParse(value);
        if (n == null || n < 1 || n > 31) return null;
        byMonthDay = n;
      default:
        break; // UNTIL/COUNT/WKST 等扩展键：忽略（v1 子集口径）
    }
  }
  if (freq == null ||
      (freq != 'DAILY' && freq != 'WEEKLY' && freq != 'MONTHLY')) {
    return null;
  }
  return RrulePattern(
    freq: freq,
    interval: interval,
    byDay: byDay,
    byMonthDay: byMonthDay,
  );
}

/// 规则是否在 [day]（yyyy-MM-dd）产生实例：自 [anchorDay]（DTSTART，
/// §5.5⑩ rrule_anchor_date）起按 RFC5545 子集展开，**闭区间含锚点日当天**
/// （重复待办自起始日即首次出现）。
///
/// 前置校验（调用方口径）：day < anchor → false；坏日期文本 → false。
bool rruleOccursOn({
  required String anchorDay,
  required RrulePattern rule,
  required String day,
}) {
  final anchor = DateTime.tryParse(anchorDay);
  final d = DateTime.tryParse(day);
  if (anchor == null || d == null) return false;
  if (d.isBefore(anchor)) return false;
  final days = dayDiff(anchorDay, day);
  switch (rule.freq) {
    case 'DAILY':
      return days % rule.interval == 0;
    case 'WEEKLY':
      if (rule.byDay.isEmpty) {
        // 无 BYDAY：按锚点星期展开（DTSTART 星期语义）。
        return d.weekday == anchor.weekday &&
            (rule.interval <= 1 || (days ~/ 7) % rule.interval == 0);
      }
      if (!rule.byDay.contains(d.weekday)) return false;
      // 周桶对齐（interval>1 时按整周推进；v1 编辑器只产 interval=1）。
      return rule.interval <= 1 || (days ~/ 7) % rule.interval == 0;
    case 'MONTHLY':
      final monthDay = rule.byMonthDay ?? anchor.day;
      if (d.day != monthDay) return false;
      if (rule.interval <= 1) return true;
      final months = (d.year - anchor.year) * 12 + d.month - anchor.month;
      return months % rule.interval == 0;
    default:
      return false;
  }
}

/// 两个本地日历日之间的整天数（DST 安全：按小时差四舍五入，±1h 夏令时
/// 抖动不产生错日；§5.1 日期口径）。
int dayDiff(String fromDay, String toDay) {
  final a = DateTime.tryParse(fromDay);
  final b = DateTime.tryParse(toDay);
  if (a == null || b == null) return 0;
  return (b.difference(a).inHours / 24).round();
}

/// 本地日历日 + 时:分 → 提醒时刻 UTC ms（§5.5⑩ remind_at INTEGER，§5.1
/// 公共列时刻口径均为 UTC ms）。真实通知调度由壳层负责（§3.6 P1 提醒：
/// feature 层只落字段，apps/mobile 后续接本地通知插件后按本字段重排）。
int remindAtMsFor({
  required String day,
  required int hour,
  required int minute,
}) {
  final d = DateTime.tryParse(day) ?? DateTime.now();
  return DateTime(d.year, d.month, d.day, hour, minute)
      .millisecondsSinceEpoch;
}

/// remind_at UTC ms → 本地时:分（编辑器回显与壳层重排共用口径：以设备本地
/// 时区解包；跨时区 travel 后回显的时:分随之偏移——v1 接受，见 todo_dao
/// remind_at 列注释）。
({int hour, int minute}) localTimeOfDay(int remindAtMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(remindAtMs);
  return (hour: t.hour, minute: t.minute);
}

/// 时刻展示文本（HH:mm，零填充）。
String formatTimeOfDay({required int hour, required int minute}) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// 设备本地今日（yyyy-MM-dd，§5.1；与 savings_dao._localToday 同源口径——
/// feature 层需要「今日」做实例展开/打卡日时统一走这里，不各自取 now）。
String featureLocalToday() => dom.formatCalendarDay(DateTime.now());
