/// 日期仪表盘真页（§3.2 统一日期仪表盘；§11.1 W2 主线；UI-规范与重设计.md
/// §3 首页日历重设计定稿）。
///
/// 结构（自上而下）：
/// - 日期大字（§3.2）：冷启动 spring 展开只播一次（§9.3#1，包裹在切日
///   Switcher 之外），切日时文字走 SlimcaSharedAxisSwitcher 水平共享轴
///   （§9.3#2）；头部右侧=今日锚定簇折叠形态：横滑离开今天后浮现「今天」
///   pill（§3.2，点击=selectedDate 重置今天+卡片墙滚顶+280ms SharedAxis
///   回位）与「月历图标」（展开月网格的另一入口，§3.2 手势表「或点月历图标」）；
/// - ui_kit 语义组件 SlimcaCalendar（§3 定稿：周条无限横滑翻周＋垂直手势
///   展开月网格（形变式）＋今日锚定簇；本页只接线不复制组件——§10.4 三层
///   分层，组件层归 ui_kit）；与日期大字/卡片墙共享同一选中日单一真值
///   （§3.1：本页 `_selectedDate` 即 provider 语义的唯一持有点）；
/// - 卡片墙（§3.2）：热量环 / 支出+净热量 / 存钱进度占位，[DashboardDayBody]
///   承载（§9.3#1 级联入场、§9.3#2 切日共享轴、§3.2 空态引导）；区域手势
///   「左右滑切日」保留在卡片墙（§3.2，与周条「翻周不切日」双语义不打架）。
///
/// 数据源：构造注入 [DashboardRepository]（§10.4 分层），watch 投影流直驱
/// （§5.6⑬），无 spinner（§3.2 快照直出）。月格色点=watchRecordedDays 直出
/// （§3.3 day_summary 聚合）。本页是唯一首页（§3.2/§4.1）。
library;

import 'dart:async' show Stream;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../calendar.dart';
import '../dashboard_repository.dart';
import 'day_cards.dart';

/// 日期仪表盘页（§3.2）。
///
/// [repository] 由宿主（Riverpod/组合根）注入；[initialDate] 缺省取今天；
/// [today]/[weekStart] 供测试与宿主固定口径（缺省运行当天/locale 周起始）；
/// [onStartCapture] 为空态引导 CTA 的录入入口回调（缺省只展示文案提示，
/// §3.2 空态、§2.3 步 1）。
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    this.initialDate,
    this.today,
    this.weekStart,
    this.onStartCapture,
  });

  /// 投影数据源（§5.6⑬ watch 流 + §5.6 重建规则）。
  final DashboardRepository repository;

  /// 初始选中日（缺省今天，§3.2 日期大字）。
  final DateTime? initialDate;

  /// 「今天」锚点（缺省本地今天；测试可注入冻结，§3.2 今日锚定簇）。
  final DateTime? today;

  /// 周起始（1=周一..7=周日，§11.1 成文口径周一；缺省 locale 驱动）。
  final int? weekStart;

  /// 空态引导的「开始录入」回调（§3.2 空态引导首次录入）。
  final VoidCallback? onStartCapture;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  /// 左右滑切日的速度阈值（px/s，交互几何阈值，非动效 token）。
  static const double _dragVelocityThreshold = 120;

  /// 选中日单一真值（§3.1）：日期大字 / SlimcaCalendar / 卡片墙三视图共享。
  late DateTime _selectedDate = DashboardCalendar.normalize(
    widget.initialDate ?? DateTime.now(),
  );

  /// 「今天」锚点（§3.2 今日锚定簇；缺省本地今天，可注入冻结）。
  late final DateTime _today = widget.today == null
      ? DashboardCalendar.today()
      : DashboardCalendar.normalize(widget.today!);

  /// 月网格展开态（受控）：页头「月历图标」与组件内手势/收起箭头共用
  /// （§3.2 手势阶梯；受控值变更不回发防环，ui_kit 组合容器契约）。
  bool _calendarExpanded = false;

  /// 月格色点流（§3.3 watchRecordedDays；State 级缓存——避免每次 build
  /// 重订阅导致色点闪烁，数据随投影表变更自动重发）。
  late final Stream<Set<String>> _recordedDays = widget.repository
      .watchRecordedDays();

  final ScrollController _scrollController = ScrollController();

  void _selectDay(DateTime day) {
    setState(() => _selectedDate = DashboardCalendar.normalize(day));
  }

  void _shiftDay(int days) {
    setState(
      () => _selectedDate = DashboardCalendar.shift(_selectedDate, days),
    );
  }

  /// 回今日（§3.2 今日锚定簇）：selectedDate 重置到今天 + 卡片墙滚顶 +
  /// 280ms SharedAxis 回位（与转场 #2 同 token）。
  void _goToToday() {
    _selectDay(_today);
    final MotionConfig motion = context.motion;
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: motion.durL,
        curve: motion.curveStandard,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSpacing spacing = context.spacing;
    final String dateKey = formatCalendarDay(_selectedDate);
    return Scaffold(
      backgroundColor: tokens.surface,
      body: SafeArea(
        // 页边距按区块自持（§1.3 落点「页边 16-24」）：周条/月网格全幅出血
        // 保 7 列命中 ≥48dp（M3 date grid 结构 §1.5），大字与卡片墙 16dp。
        child: ListView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(0, spacing.space100, 0, 96),
          children: <Widget>[
            _DateHeader(
              date: _selectedDate,
              today: _today,
              onGoToday: _goToToday,
              calendarExpanded: _calendarExpanded,
              onToggleMonthGrid: () =>
                  setState(() => _calendarExpanded = !_calendarExpanded),
            ),
            SizedBox(height: spacing.cardInner),
            // 首页日历（§3 定稿组合容器）：受控展开 + 月格色点直出。
            StreamBuilder<Set<String>>(
              stream: _recordedDays,
              builder:
                  (BuildContext context, AsyncSnapshot<Set<String>> snapshot) {
                    final Set<String> recorded =
                        snapshot.data ?? const <String>{};
                    return SlimcaCalendar(
                      // 选中日单一真值（§3.1）：本页持有、组件无日期选中态。
                      selectedDate: _selectedDate,
                      onDaySelected: _selectDay,
                      // 月格 Compact 色点（§3.2）：V1 一点=有记录；点数映射
                      // 随 W17 记录条数投影扩展。
                      recordCounts: <DateTime, int>{
                        for (final String date in recorded)
                          DashboardCalendar.parse(date): 1,
                      },
                      expanded: _calendarExpanded,
                      onExpandedChanged: (bool expanded) =>
                          setState(() => _calendarExpanded = expanded),
                      today: _today,
                      weekStart: widget.weekStart,
                    );
                  },
            ),
            SizedBox(height: spacing.space250),
            // 左右滑切日（§3.2「左右滑切日（共享轴转场）」，保留在卡片墙区域）：
            // 右滑=前一天、左滑=后一天。
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.inline),
              child: GestureDetector(
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期大字 + 今日锚定簇折叠形态（§3.2「周条折叠态头部=现 _DateHeader 大字
/// 右侧追加「今天」pill，横滑离开今天后浮现」）+ 月历图标（§3.2 手势表
/// 「或点月历图标」）。
///
/// 冷启动 spring 展开（§9.3#1 ≤400ms）包裹在切日 Switcher **之外**——只在
/// 页面挂载时播一次；切日由内层 [SlimcaSharedAxisSwitcher] 承担水平共享轴
/// （§9.3#2），大字随切日滑动而不重播 spring。pill 与图标不参与切日转场
/// （常驻操作区，位置稳定不随大字滑动）。
class _DateHeader extends StatelessWidget {
  const _DateHeader({
    required this.date,
    required this.today,
    required this.onGoToday,
    required this.calendarExpanded,
    required this.onToggleMonthGrid,
  });

  final DateTime date;
  final DateTime today;
  final VoidCallback onGoToday;
  final bool calendarExpanded;
  final VoidCallback onToggleMonthGrid;

  /// pill 常驻占位宽（避免出现/消失时大字回流；几何常量非 token）。
  static const double _pillSlotWidth = 72;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSpacing spacing = context.spacing;
    final SlimcaSizes sizes = context.sizes;
    final MotionConfig motion = context.motion;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool showTodayPill = date != today;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.inline),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _ColdStartSpring(
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
                    SizedBox(width: spacing.space100),
                    Text(
                      DashboardCalendar.weekdayLong[date.weekday - 1],
                      style: textTheme.titleMedium?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 「今天」pill（§3.2）：命中=整槽 72×48 ≥48dp（§1.4
          // sizes.minTouchTarget；视觉 pill ~28dp 居中）；轻量可见性（出现
          // ≤800ms 内，取 durS 微交互档）。
          SizedBox(
            width: _pillSlotWidth,
            height: sizes.minTouchTarget,
            child: AnimatedOpacity(
              duration: motion.durS,
              curve: motion.curveEffectsStandard,
              opacity: showTodayPill ? 1 : 0,
              child: IgnorePointer(
                ignoring: !showTodayPill,
                child: InkWell(
                  key: const ValueKey('dashboard_today_pill'),
                  onTap: onGoToday,
                  customBorder: const StadiumBorder(),
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: spacing.cardInner,
                        vertical: spacing.space100,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surfaceMuted,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '今天',
                        style: textTheme.labelMedium?.copyWith(
                          color: tokens.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 月历图标（§3.2 手势表「或点月历图标」）：框架默认 48dp 命中（§1.4）。
          IconButton(
            tooltip: '展开月历',
            icon: Icon(
              calendarExpanded ? Icons.expand_less : Icons.calendar_month,
              size: sizes.iconVisual,
            ),
            onPressed: onToggleMonthGrid,
          ),
        ],
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
