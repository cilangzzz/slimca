import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';
import '../tokens/slimca_sizes.dart';
import '../tokens/slimca_spacing.dart';
import '../tokens/slimca_theme.dart';
import 'calendar_utils.dart';

/// 无限双向横滑周条 v2（UI-规范与重设计.md §3 定稿：淘汰「固定七天」横条）。
///
/// - 无限翻周：PageView 以初始选中周为锚定原点，双向各 5000 周（≈±96 年）近似
///   无界横滑；横滑=**翻周不切日**（§3.2 设计决策：避免与卡片墙切日手势在同一
///   屏幕双重语义打架，标注为本文件设计决策项）；
/// - 点格=切日（[onDaySelected]，§3.2 手势阶梯第 1 行）；
/// - 今日锚定簇（§3.2）：外部把选中日切到别的周（如宿主「今天」pill 回位）时，
///   周条以 SharedAxis token（dur.l 280ms + curveStandard，§3.2/§9.3#2）锚定回
///   目标周；off 档降级 100ms 淡入淡出时长（§9.6）；
/// - 日格约束（§3.3）：命中 ≥48×48（竖向由 72dp 折叠高度与格宽保证）、格间距
///   8dp（两侧各 SlimcaSpacing.space50，修正 §5#2 的 3px 违规）、折叠态高度
///   72dp（weekStripHeight，推导值）；
/// - 视觉（§3.3）：选中日=primaryContainer 填充、今天=primary 对比色文字+今日点
///   （沿现周条结构）；选中态变色动画=durM + curveEffectsStandard（effects 类
///   禁过冲，§5#2/§2.2）。
///
/// 三视图单一真值（§3.1）：选中日由外部 provider 持有，本组件不维护日期选中态。
class SlimcaCalendarStrip extends StatefulWidget {
  const SlimcaCalendarStrip({
    super.key,
    required this.selectedDate,
    required this.onDaySelected,
    this.onWeekChanged,
    this.today,
    this.weekStart,
  });

  /// 当前选中日（外部 provider 单一真值，§3.1）。
  final DateTime selectedDate;

  /// 点选某日回调（周条点格=切日，§3.2）。
  final ValueChanged<DateTime> onDaySelected;

  /// 翻周回调（横滑翻周不切日；参数=新周的周起始日，§3.2 设计决策）。
  final ValueChanged<DateTime>? onWeekChanged;

  /// 「今天」（缺省取运行当天；测试注入固定值保确定性）。
  final DateTime? today;

  /// 周起始（1=周一..7=周日，DateTime.weekday 口径）；缺省取
  /// MaterialLocalizations.firstDayOfWeekIndex（0=周日口径 → weekday 口径
  /// 换算，locale 驱动，不发明取值）。
  final int? weekStart;

  @override
  State<SlimcaCalendarStrip> createState() => _SlimcaCalendarStripState();
}

class _SlimcaCalendarStripState extends State<SlimcaCalendarStrip> {
  /// 双向各 5000 周 ≈ ±96 年：以页码近似无限双向（PageView 页数有界但远超
  /// 产品生命周期；无限滑动分页 §3 定稿）。
  static const int _kMaxWeekPages = 10000;
  static const int _kCenterPage = _kMaxWeekPages ~/ 2;

  PageController? _pageController;

  /// 页码↔周映射的固定锚定周（初始选中周的 UTC 周起始；UTC 域运算防 DST）。
  late DateTime _anchorWeekUtc;

  /// 周起始口径（首次装配时按 prop/localizations 冻结）。
  late int _weekStart;

  /// 外部 selectedDate 追踪（驱动今日锚定回位）。
  ///
  /// 须在 initState 急切初始化：`late ... = widget.selectedDate` 声明初始化器
  /// 会在首次读取（didUpdateWidget，此时 widget 已换新）才求值，导致首帧
  /// 外部选中变更与初始值恒等、锚定回位永不触发。
  late DateTime _lastSelected;

  @override
  void initState() {
    super.initState();
    _lastSelected = slimcaDateOnly(widget.selectedDate);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pageController != null) return;
    _weekStart = widget.weekStart ?? _weekdayFromLocalizations(context);
    _anchorWeekUtc = slimcaStartOfWeek(
      slimcaUtcDate(widget.selectedDate),
      _weekStart,
    );
    _pageController = PageController(initialPage: _kCenterPage);
  }

  @override
  void didUpdateWidget(covariant SlimcaCalendarStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final DateTime selected = slimcaDateOnly(widget.selectedDate);
    if (selected != _lastSelected) {
      // 今日锚定簇（§3.2）：外部选中日变更 → 锚定回目标周（SharedAxis token）。
      final DateTime newWeek = slimcaStartOfWeek(
        slimcaUtcDate(selected),
        _weekStart,
      );
      final int currentPage = _pageController?.hasClients == true
          ? (_pageController!.page?.round() ?? _kCenterPage)
          : _kCenterPage;
      if (_weekStartForPage(currentPage) != newWeek) {
        final MotionConfig motion = context.motion;
        _pageController?.animateToPage(
          _pageFor(newWeek),
          duration: motion.level == MotionLevel.off
              ? motion.fadeOff
              : motion.sharedAxis, // §3.2：SharedAxis X，dur.l 280ms
          curve: motion.curveStandard, // §9.3#2 token 不变
        );
      }
      _lastSelected = selected;
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  /// 页码 → 周起始（UTC 域）。
  DateTime _weekStartForPage(int page) =>
      slimcaAddDays(_anchorWeekUtc, 7 * (page - _kCenterPage));

  /// MaterialLocalizations（firstDayOfWeekIndex：0=周日..6=周六，narrowWeekdays
  /// 索引口径）→ DateTime.weekday 口径（1=周一..7=周日）。
  static int _weekdayFromLocalizations(BuildContext context) {
    final int index = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    return index == 0 ? DateTime.sunday : index;
  }

  /// 周起始 → 页码（UTC 域天数差恰为 7 的整数倍）。
  int _pageFor(DateTime weekStartUtc) =>
      _kCenterPage + weekStartUtc.difference(_anchorWeekUtc).inDays ~/ 7;

  @override
  Widget build(BuildContext context) {
    final SlimcaSizes sizes = context.sizes;
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final DateTime selected = slimcaDateOnly(widget.selectedDate);
    final DateTime today = slimcaDateOnly(widget.today ?? DateTime.now());

    return SizedBox(
      // 折叠态高度 72dp（§3.3 推导值：星期标签+日期号+今日点）
      height: sizes.weekStripHeight,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (int page) => widget.onWeekChanged?.call(
          slimcaLocalFromUtc(_weekStartForPage(page)),
        ),
        itemBuilder: (BuildContext context, int page) {
          final DateTime weekStartUtc = _weekStartForPage(page);
          return Row(
            children: <Widget>[
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: _StripCell(
                    day: slimcaLocalFromUtc(slimcaAddDays(weekStartUtc, i)),
                    selectedDate: selected,
                    today: today,
                    onSelected: widget.onDaySelected,
                    localizations: localizations,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 周条日格（星期标签+日期号+今日点，现周条结构沿承；§3.3 约束落地）。
class _StripCell extends StatelessWidget {
  const _StripCell({
    required this.day,
    required this.selectedDate,
    required this.today,
    required this.onSelected,
    required this.localizations,
  });

  final DateTime day;
  final DateTime selectedDate;
  final DateTime today;
  final ValueChanged<DateTime> onSelected;
  final MaterialLocalizations localizations;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSizes sizes = context.sizes;
    final SlimcaSpacing spacing = context.spacing;
    final MotionConfig motion = context.motion;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    final bool isSelected = day == selectedDate;
    final bool isToday = day == today;

    return Semantics(
      // 无障碍标签：完整日期语义（§1.6；星期标签行不可聚焦约束见月网格）
      label: localizations.formatFullDate(day),
      // 命中区=整格（360dp 宽度下 7 列物理上无法同时满足 48 命中与 8dp 命中间
      // 距——取命中优先，命中留白由相邻命中区连排承担，与 M3 date-picker 网格
      // 「行高 48、内边距 4px」口径同构，§1.5/§3.3）；视觉间距 8dp 由装饰 margin
      // 承担（§3.3「格间距 ≥8dp」，修正 §5#2 的 3px 违规）。
      child: InkWell(
        onTap: () => onSelected(day),
        // 涟漪剪裁跟随视觉圆角（命中区仍为整格，customBorder 只影响 ink 形状）
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sizes.radiusGroupCard),
        ),
        child: AnimatedContainer(
          // 选中态=颜色变化（effects 类禁过冲，§5#2）：时长 dur.m 180ms +
          // curveEffectsStandard（UI-规范 §2.2 新 token，替代裸 easeOutCubic）
          duration: motion.durM,
          curve: motion.curveEffectsStandard,
          margin: EdgeInsets.symmetric(horizontal: spacing.space100),
          padding: EdgeInsets.symmetric(vertical: spacing.space100),
          decoration: BoxDecoration(
            // 选中日=primaryContainer 填充（§3.3，沿现 primaryContainer 语义）；
            // 未选中为 null——BoxDecoration.lerp 对 null 做 alpha 淡出，平滑变色
            color: isSelected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(sizes.radiusGroupCard),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                // 星期标签（locale 驱动 narrowWeekdays，Sunday 索引 0）
                localizations.narrowWeekdays[day.weekday % 7],
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
              SizedBox(height: spacing.space50),
              Text(
                '${day.day}',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  // 今天=primary 对比色（§3.3）；选中态取 onPrimaryContainer
                  color: isSelected
                      ? scheme.onPrimaryContainer
                      : isToday
                      ? tokens.primary
                      : null,
                ),
              ),
              SizedBox(height: spacing.space50),
              // 今日点（现周条结构沿承；直径 4dp=space50；今日点为 primary）
              Opacity(
                opacity: isToday ? 1.0 : 0.0,
                child: SizedBox(
                  width: spacing.space50,
                  height: spacing.space50,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tokens.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
