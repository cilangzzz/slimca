/// 日期仪表盘真页（§3.2 统一日期仪表盘；§11.1 W2 主线）。
///
/// 结构（自上而下）：
/// - 日期大字（§3.2）：冷启动 spring 展开只播一次（§9.3#1，包裹在切日
///   Switcher 之外），切日时文字走 SlimcaSharedAxisSwitcher 水平共享轴（§9.3#2）；
/// - 周历条（§3.2）：7 日可点选 + 今日锚点圆点；
/// - 卡片墙（§3.2）：热量环 / 支出+净热量 / 存钱进度占位，[DashboardDayBody]
///   承载（§9.3#1 级联入场、§9.3#2 切日共享轴、§3.2 空态引导）。
///
/// 数据源：构造注入 [DashboardRepository]（§10.4 分层），watch 投影流直驱
/// （§5.6⑬），无 spinner（§3.2 快照直出）。本页是唯一首页（§3.2/§4.1）。
library;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../calendar.dart';
import '../dashboard_repository.dart';
import 'day_cards.dart';

/// 日期仪表盘页（§3.2）。
///
/// [repository] 由宿主（Riverpod/组合根）注入；[initialDate] 缺省取今天；
/// [onStartCapture] 为空态引导 CTA 的录入入口回调（缺省只展示文案提示，
/// §3.2 空态、§2.3 步 1）。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    this.initialDate,
    this.onStartCapture,
  });

  /// 投影数据源（§5.6⑬ watch 流 + §5.6 重建规则）。
  final DashboardRepository repository;

  /// 初始选中日（缺省今天，§3.2 日期大字）。
  final DateTime? initialDate;

  /// 空态引导的「开始录入」回调（§3.2 空态引导首次录入）。
  final VoidCallback? onStartCapture;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// 左右滑切日的速度阈值（px/s，交互几何阈值，非动效 token）。
  static const double _dragVelocityThreshold = 120;

  late DateTime _selectedDate = DashboardCalendar.normalize(
    widget.initialDate ?? DateTime.now(),
  );

  void _selectDay(DateTime day) {
    setState(() => _selectedDate = DashboardCalendar.normalize(day));
  }

  void _shiftDay(int days) {
    setState(
      () => _selectedDate = DashboardCalendar.shift(_selectedDate, days),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final String dateKey = formatCalendarDay(_selectedDate);
    return Scaffold(
      backgroundColor: tokens.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            _DateHeader(date: _selectedDate),
            const SizedBox(height: 12),
            _WeekStrip(selected: _selectedDate, onSelect: _selectDay),
            const SizedBox(height: 20),
            // 左右滑切日（§3.2「左右滑切日（共享轴转场）」）：右滑=前一天、
            // 左滑=后一天。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (DragEndDetails details) {
                final double v = details.primaryVelocity ?? 0;
                if (v > _dragVelocityThreshold) {
                  _shiftDay(-1);
                } else if (v < -_dragVelocityThreshold) {
                  _shiftDay(1);
                }
              },
              // 切日：SlimcaSharedAxisSwitcher 水平共享轴（§9.3#2，280ms ≤
              // 切日 ≤280ms 预算）。key 只放在内层 DayBody 上——Switcher 本体
              // 重挂载会吞掉 AnimatedSwitcher 的转场。
              child: SlimcaSharedAxisSwitcher(
                child: DashboardDayBody(
                  key: ValueKey<String>(dateKey),
                  date: _selectedDate,
                  repository: widget.repository,
                  onStartCapture: widget.onStartCapture,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期大字（§3.2「日期大字」）。
///
/// 冷启动 spring 展开（§9.3#1 ≤400ms）包裹在切日 Switcher **之外**——只在
/// 页面挂载时播一次；切日由内层 [SlimcaSharedAxisSwitcher] 承担水平共享轴
/// （§9.3#2），大字随切日滑动而不重播 spring。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return _ColdStartSpring(
      child: SlimcaSharedAxisSwitcher(
        child: Row(
          key: ValueKey<String>(
            'date-header-${DashboardCalendar.dayTitle(date)}',
          ),
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              DashboardCalendar.dayTitle(date),
              style: textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: tokens.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              DashboardCalendar.weekdayLong[date.weekday - 1],
              style: textTheme.titleMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 冷启动展开（§9.3#1「快照直出+日期大字 spring」，≤400ms）：scale 0.92→1
/// + 淡入，spring.soft（§9.2「容器变形/环推进」同源弹簧）；MotionLevel=off
/// 退化为 100ms 淡入淡出（§9.6）。无日期依赖、不随切日重建 → 只播一次。
class _ColdStartSpring extends StatelessWidget {
  const _ColdStartSpring({required this.child});

  final Widget child;

  /// 起始缩放（几何常量，与 ui_kit 共享轴 z 轴起点一致，非动效 token）。
  static const double _scaleFrom = 0.92;

  @override
  Widget build(BuildContext context) {
    final MotionConfig motion = context.motion;
    final bool off = motion.level == MotionLevel.off;
    return TweenAnimationBuilder<double>(
      // Flutter 3.32 起 Tween 构造不再 const，故不加 const（冷启动 spring）。
      tween: Tween<double>(begin: 0, end: 1),
      duration: off ? motion.fadeOff : motion.springSoft.settleDuration,
      curve: off ? Curves.linear : motion.springSoft.curve,
      builder: (BuildContext context, double t, Widget? child) {
        final double v = t.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.scale(
            scale: _scaleFrom + (1 - _scaleFrom) * v,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// 周历条：横滑选日（§3.2「日期大字+周历条」）。展示选中日所在周（周一为
/// 起点），7 日可点选；今日带锚点圆点。无限翻周与月历下钻（§3.2，Container
/// Transform P1）随 W2+ 接入。
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final List<DateTime> days = DashboardCalendar.weekOf(selected);
    return Row(
      children: <Widget>[
        for (int i = 0; i < days.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == days.length - 1 ? 0 : 6),
              child: _WeekDayChip(
                day: days[i],
                weekdayLabel: DashboardCalendar.weekdayShort[i],
                selected: days[i] == selected,
                isToday: days[i] == DashboardCalendar.today(),
                onTap: () => onSelect(days[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// 周历单日 chip（§3.2）：选中态填 tokens.primary（§8.2 交互锚点），
/// 今日带锚点圆点；选中过渡为 dur.m 隐式动画（§9.5「隐式动画仅限微交互」）。
class _WeekDayChip extends StatelessWidget {
  const _WeekDayChip({
    required this.day,
    required this.weekdayLabel,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final String weekdayLabel;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final MotionConfig motion = context.motion;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: motion.durM, // §9.2 dur.m：chip/微交互
        curve: motion.curveEaseOutExpo,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Text(
              weekdayLabel,
              style: textTheme.labelSmall?.copyWith(
                color: selected ? tokens.onPrimary : tokens.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? tokens.onPrimary : tokens.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 4,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isToday
                      ? (selected ? tokens.onPrimary : tokens.primary)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
