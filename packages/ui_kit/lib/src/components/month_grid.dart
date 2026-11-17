import 'package:flutter/gestures.dart' show kMinFlingVelocity;
import 'package:flutter/material.dart';

import '../tokens/slimca_sizes.dart';
import '../tokens/slimca_spacing.dart';
import '../tokens/slimca_theme.dart';
import '../transitions/shared_axis.dart';
import 'calendar_utils.dart';

/// 展开月网格（UI-规范与重设计.md §3.1「垂直手势展开月网格」、§3.2/§3.3 定稿）。
///
/// - 头部行=今日锚定簇（§3.2 Notion Calendar 口径）：`[‹] 2026年11月 [›] [今天]`
///   （月份文案经 MaterialLocalizations.formatMonthYear，locale 驱动）；
/// - 水平拖或点箭头=翻月：SharedAxis X（SlimcaSharedAxisSwitcher 既有 token：
///   dur.l 280ms + curveStandard，§3.2 手势阶梯第 1 行）；
/// - 点任意日格=selectedDate ← 该日（[onDaySelected]，与切日同一转场、无第二次
///   选择，§3.1④）；
/// - 月格参数（§3.3 定稿值）：视觉 40×40（material-web date-picker token）、
///   命中 ≥48×48（a11y 页「Touch targets are 48x48dp」）、最多 6 行、行高 48；
/// - 状态色（§3.3）：今天=primary 对比色、选中日=primaryContainer 填充
///   （选中态覆盖今日态色）、有记录日=secondaryContainer 色点；
/// - 信息密度三档（§3.2 Apple 日历）：V1 只做 Compact——每格 ≤3 色点+溢出点
///   （上限 3 为常见实现观察，设计推导项标注非规范）；
/// - 星期标签行不可聚焦（§3.3 M3 modal 解剖）→ ExcludeSemantics。
class SlimcaMonthGrid extends StatelessWidget {
  const SlimcaMonthGrid({
    super.key,
    required this.month,
    required this.selectedDate,
    required this.onDaySelected,
    this.onMonthChanged,
    this.recordCounts = const <DateTime, int>{},
    this.headerTrailing,
    this.today,
    this.weekStart,
  });

  /// 焦点月（当月任意日期；受控——翻月由宿主 setState 更新本值）。
  final DateTime month;

  /// 当前选中日（外部 provider 单一真值，§3.1）。
  final DateTime selectedDate;

  /// 点选某日回调（月网格点格=切日）。
  final ValueChanged<DateTime> onDaySelected;

  /// 翻月回调（箭头点击或网格水平拖；参数=目标月首日）。
  final ValueChanged<DateTime>? onMonthChanged;

  /// 有记录日 → 当日记录条数（月格色点 Compact 档数据源，§3.2；键经本地
  /// 日界归一化匹配）。
  final Map<DateTime, int> recordCounts;

  /// 头部尾部附加件（组合容器注入「收起月历」箭头，§3.2 手势阶梯第 3 行）。
  final Widget? headerTrailing;

  /// 「今天」（缺省取运行当天；测试注入固定值保确定性）。
  final DateTime? today;

  /// 周起始（1=周一..7=周日）；缺省取 MaterialLocalizations.firstDayOfWeekIndex
  /// （0=周日口径 → weekday 口径换算）。
  final int? weekStart;

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSizes sizes = context.sizes;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int weekStartValue = weekStart == null
        ? (localizations.firstDayOfWeekIndex == 0
              ? DateTime.sunday
              : localizations.firstDayOfWeekIndex)
        : weekStart!;
    final DateTime todayDate = slimcaDateOnly(today ?? DateTime.now());
    final DateTime monthFirst = slimcaFirstOfMonth(month);
    final DateTime selected = slimcaDateOnly(selectedDate);
    // 色点数据源按本地日界归一化（§3.2 day_summary 直出口径）
    final Map<DateTime, int> counts = <DateTime, int>{
      for (final MapEntry<DateTime, int> e in recordCounts.entries)
        slimcaDateOnly(e.key): e.value,
    };
    // 网格几何预计算（§1.5：月网格最多 6 行；M3 行高 48、内边距 4px）
    final int firstOffset = (monthFirst.weekday - weekStartValue) % 7;
    final int daysInMonth = slimcaDaysInMonth(
      monthFirst.year,
      monthFirst.month,
    );
    final DateTime utcMonthFirst = slimcaUtcDate(monthFirst);

    Widget buildCell(int index) {
      final DateTime day = slimcaLocalFromUtc(
        slimcaAddDays(utcMonthFirst, index - firstOffset),
      );
      return _MonthCell(
        day: day,
        inMonth: index >= 0 && index < daysInMonth,
        selectedDate: selected,
        today: todayDate,
        recordCount: counts[day] ?? 0,
        onSelected: onDaySelected,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── 头部行：[‹] 月份 [›] [今天]（§3.2 今日锚定簇）────────────────
        Row(
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.chevron_left, size: sizes.iconVisual),
              tooltip: '上一月',
              onPressed: onMonthChanged == null
                  ? null
                  : () => onMonthChanged!(slimcaAddMonths(monthFirst, -1)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  localizations.formatMonthYear(monthFirst),
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.chevron_right, size: sizes.iconVisual),
              tooltip: '下一月',
              onPressed: onMonthChanged == null
                  ? null
                  : () => onMonthChanged!(slimcaAddMonths(monthFirst, 1)),
            ),
            TextButton(
              onPressed: () => onDaySelected(todayDate),
              child: const Text('今天'),
            ),
            if (headerTrailing != null) headerTrailing!,
          ],
        ),
        // ── 星期标签行：不可聚焦（§3.3）→ ExcludeSemantics ────────────────
        ExcludeSemantics(
          child: SizedBox(
            // 标签行高与月格视觉同尺度（40，推导值非规范原文）
            height: sizes.dayCellVisual,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: Text(
                        // narrowWeekdays 为周日开头数组（索引=weekday%7）；
                        // 列 i 的星期 = weekStart + i（weekday 1-7 口径取模）
                        localizations.narrowWeekdays[(weekStartValue + i) % 7],
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        // ── 网格主体：翻月 SharedAxis（§3.2 水平=翻月）────────────────────
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragEnd: (DragEndDetails details) {
            if (onMonthChanged == null) return;
            final double velocity = details.velocity.pixelsPerSecond.dx;
            // 左滑（负速度）= 下月、右滑 = 上月；阈值取框架 kMinFlingVelocity
            if (velocity < -kMinFlingVelocity) {
              onMonthChanged!(slimcaAddMonths(monthFirst, 1));
            } else if (velocity > kMinFlingVelocity) {
              onMonthChanged!(slimcaAddMonths(monthFirst, -1));
            }
          },
          child: SlimcaSharedAxisSwitcher(
            child: Column(
              // 月变更触发 SharedAxis 切换（AnimatedSwitcher 按 key 换 child）
              key: ValueKey<String>('${monthFirst.year}-${monthFirst.month}'),
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int row = 0; row < sizes.monthGridMaxRows; row++)
                  Row(
                    children: <Widget>[
                      for (int col = 0; col < 7; col++)
                        Expanded(child: buildCell(row * 7 + col)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 月格（视觉 40 / 命中 48、选中态/今日态/Compact 色点，§3.3 定稿）。
class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.selectedDate,
    required this.today,
    required this.recordCount,
    required this.onSelected,
  });

  final DateTime day;
  final bool inMonth;
  final DateTime selectedDate;
  final DateTime today;
  final int recordCount;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSizes sizes = context.sizes;
    final SlimcaSpacing spacing = context.spacing;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final bool isSelected = day == selectedDate;
    final bool isToday = day == today;

    // 日期文字对比度 ≥4.5:1（§3.3 M3 date-pickers/accessibility；域外日淡化）：
    // 域外=onSurfaceMuted、今天=primary、选中=onPrimaryContainer、其余继承 onSurface。
    final Color? numberColor = isSelected
        ? scheme.onPrimaryContainer
        : isToday
        ? tokens.primary
        : inMonth
        ? null // 继承默认正文色（M3 textTheme → onSurface）
        : tokens.onSurfaceMuted;

    return InkWell(
      onTap: () => onSelected(day),
      // 涟漪剪裁为圆角方（视觉圆 40，命中为整格 ≥48，§3.3）
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(sizes.dayCellVisual),
      ),
      child: SizedBox(
        // 命中 48×48（§3.3 a11y 硬指标；竖向即行高 48，§1.5 M3 行高）
        height: sizes.minTouchTarget,
        child: Center(
          child: Container(
            // 视觉 40×40（§3.3 material-web date-picker token）；40 视觉外缘
            // 到 48 命中边缘的 4px 即 M3「内边距 4px」（§1.5）
            width: sizes.dayCellVisual,
            height: sizes.dayCellVisual,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // 选中日=primaryContainer 填充（§3.3）；未选中 null → alpha 淡变
              color: isSelected ? scheme.primaryContainer : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '${day.day}',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: numberColor,
                  ),
                ),
                if (recordCount > 0) ...<Widget>[
                  SizedBox(height: spacing.space50),
                  SizedBox(
                    height: spacing.space50,
                    child: _RecordDots(
                      count: recordCount,
                      dotColor: scheme.secondaryContainer, // §3.3 色点色
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact 档色点（§3.2）：≤3 实心点 + 溢出点（空心环，推导视觉非规范原文）。
class _RecordDots extends StatelessWidget {
  const _RecordDots({required this.count, required this.dotColor});

  final int count;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    final SlimcaSpacing spacing = context.spacing;
    final List<Widget> dots = <Widget>[];
    final int shown = count > 3 ? 3 : count;
    for (int i = 0; i < shown; i++) {
      if (dots.isNotEmpty) dots.add(SizedBox(width: spacing.space50));
      dots.add(
        Container(
          width: spacing.space50,
          height: spacing.space50,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
      );
    }
    if (count > 3) {
      dots.add(SizedBox(width: spacing.space50));
      dots.add(
        Container(
          width: spacing.space50,
          height: spacing.space50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: dotColor), // 1px 描边环=溢出点
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}
