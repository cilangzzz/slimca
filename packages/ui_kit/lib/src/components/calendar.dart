import 'dart:ui' show clampDouble, lerpDouble;

import 'package:flutter/gestures.dart' show kMinFlingVelocity;
import 'package:flutter/material.dart';

import '../tokens/motion_config.dart';
import '../tokens/slimca_sizes.dart';
import 'calendar_strip.dart';
import 'calendar_utils.dart';
import 'month_grid.dart';

/// 周条↔月网格组合容器（UI-规范与重设计.md §3.1 定稿：周条＋垂直手势展开
/// 月网格（形变式）＋今日锚定簇；淘汰 M3 modal 弹窗与 TDesign 翻页式）。
///
/// 两轴手势不打架（§3.1③）：水平=切日/翻周/翻月（SharedAxis token 不变），
/// 垂直=展开/收起（高度形变 280ms＋curveExpand/curveCollapse 曲线对，§2.2）：
/// - 折叠态：仅周条（SlimcaCalendarStrip）；下拉或宿主置 expanded=true 展开；
/// - 展开态：月网格（SlimcaMonthGrid，含 [‹ 月份 ›] [今天] 头部簇）；上拉或点
///   「收起月历」箭头收起；
/// - 拖拽阶段跟手（HIG「跟随手势」，§2.3 映射表），松手才补 dur.l 280ms 补间
///   （off 档 100ms 淡入淡出，§9.6）；透明度交叉淡化走 curveEffectsStandard
///   （effects 禁过冲，§2.2）；
/// - 高度形变几何：折叠 72（weekStripHeight）→ 展开 48（头部簇）+40（星期标签
///   行）+48×6（月格行，monthGridMaxRows），全部 token 推导；
/// - 单选中日单一真值（§3.1④）：selectedDate 由外部 provider 持有，本容器不
///   维护日期选中态；焦点月随选中日所在月（切视图不产生第二次日期选择）；
/// - 「再下拉到底=全屏月历」为 P2（§3.2），V1 在展开态钳制。
class SlimcaCalendar extends StatefulWidget {
  const SlimcaCalendar({
    super.key,
    required this.selectedDate,
    required this.onDaySelected,
    this.recordCounts = const <DateTime, int>{},
    this.onWeekChanged,
    this.expanded,
    this.onExpandedChanged,
    this.today,
    this.weekStart,
  });

  /// 当前选中日（外部 provider 单一真值，§3.1）。
  final DateTime selectedDate;

  /// 点选某日回调（周条/月网格共用；卡片墙随选中日 key 切换由宿主承担）。
  final ValueChanged<DateTime> onDaySelected;

  /// 有记录日 → 记录条数（月格 Compact 色点，§3.2）。
  final Map<DateTime, int> recordCounts;

  /// 折叠态周条翻周回调（宿主「今天」pill 浮现逻辑用，§3.2）。
  final ValueChanged<DateTime>? onWeekChanged;

  /// 展开态（受控）：null=非受控（内部自管，初始折叠）；非 null=宿主持有
  /// （如首页头部「月历」图标展开，§3.2「或点月历图标」）。
  final bool? expanded;

  /// 展开态变更回调（非受控模式与拖拽/箭头触发时回发）。
  final ValueChanged<bool>? onExpandedChanged;

  /// 「今天」（缺省取运行当天；测试注入固定值保确定性）。
  final DateTime? today;

  /// 周起始（1=周一..7=周日）；缺省取 MaterialLocalizations.firstDayOfWeek。
  final int? weekStart;

  @override
  State<SlimcaCalendar> createState() => _SlimcaCalendarState();
}

class _SlimcaCalendarState extends State<SlimcaCalendar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  /// 松手补间（当前形变分数 → 目标；曲线对按方向取 curveExpand/curveCollapse）。
  Animation<double>? _settle;

  bool _dragging = false;
  double _dragFraction = 0.0;

  late bool _expanded = widget.expanded ?? false;
  late DateTime _focusedMonth = slimcaFirstOfMonth(widget.selectedDate);

  /// 当前形变分数（0=折叠周条，1=展开月网格）。
  double get _currentFraction {
    if (_dragging) return _dragFraction;
    final Animation<double>? settle = _settle;
    if (settle != null && _controller.isAnimating) return settle.value;
    return _expanded ? 1.0 : 0.0;
  }

  /// 朝目标补间：展开段 curveExpand（进场 ease-out）、收起段 curveCollapse
  /// （出场 ease-in）——不对称纪律以 Tween 端点+方向曲线实现（§2.2/§9.1）。
  void _settleTo(bool target, {bool notify = true}) {
    final MotionConfig motion = context.motion;
    _controller
      ..duration = motion.level == MotionLevel.off
          ? motion
                .fadeOff // §9.6 off 档：100ms
          : motion
                .durL // §3.2：高度形变 280ms（=dur.l）
      ..stop();
    if (target) {
      // 展开时焦点月回到选中日所在月（今日锚定簇语义，§3.2）
      _focusedMonth = slimcaFirstOfMonth(widget.selectedDate);
    }
    _settle =
        Tween<double>(
          begin: clampDouble(_currentFraction, 0.0, 1.0),
          end: target ? 1.0 : 0.0,
        ).animate(
          CurvedAnimation(
            parent: _controller,
            curve: target ? motion.curveExpand : motion.curveCollapse,
          ),
        );
    setState(() {
      _expanded = target;
      // 松手/受控切换即退出跟手态：否则 _currentFraction 恒返回 _dragFraction，
      // settle 补间永不生效（形变冻结在松手位置）
      _dragging = false;
    });
    _controller.forward(from: 0.0);
    if (notify) widget.onExpandedChanged?.call(target);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    // 冻结当前形变分数（须在 stop 前读：停走补间后 isAnimating=false）
    final double current = clampDouble(_currentFraction, 0.0, 1.0);
    _controller.stop();
    setState(() {
      _dragging = true;
      _dragFraction = current;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final SlimcaSizes sizes = context.sizes;
    final double total = _expandedHeight(sizes) - sizes.weekStripHeight; // 总形变量
    if (total <= 0) return;
    setState(() {
      // 拖拽跟手（HIG，§2.3）：按下为原点，增量线性映射形变分数
      _dragFraction = clampDouble(
        _dragFraction + details.delta.dy / total,
        0.0,
        1.0,
      );
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final double velocity = details.velocity.pixelsPerSecond.dy;
    final bool target;
    if (velocity > kMinFlingVelocity) {
      target = true; // 下拉展开
    } else if (velocity < -kMinFlingVelocity) {
      target = false; // 上拉收起
    } else {
      target = _dragFraction > 0.5; // 无明显速度：过半展开
    }
    _settleTo(target);
  }

  void _onVerticalDragCancel() {
    // 手势被 arena 拒绝（含未起手的落败指针：日格/按钮点按等）都会触发本回调；
    // 仅在真实拖拽跟手中被抢占时回当前展开态补间，且不回发事件（防幽灵通知）。
    if (!_dragging) return;
    _settleTo(_expanded, notify: false);
  }

  /// 展开态总高度（token 推导：头部簇 48 + 星期标签行 40 + 月格 48×6）。
  double _expandedHeight(SlimcaSizes sizes) =>
      sizes.minTouchTarget +
      sizes.dayCellVisual +
      sizes.minTouchTarget * sizes.monthGridMaxRows;

  @override
  void didUpdateWidget(covariant SlimcaCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 受控展开态同步（宿主驱动；不回发 onExpandedChanged 防环）
    if (widget.expanded != null && widget.expanded != _expanded) {
      _settleTo(widget.expanded!, notify: false);
    }
    // 单选中日驱动一切（§3.1④）：选中日跨月 → 焦点月跟随（展开态下网格随
    // SharedAxis 切月；折叠态仅缓存，展开时按选中月呈现）
    final DateTime month = slimcaFirstOfMonth(widget.selectedDate);
    if (month != _focusedMonth) {
      setState(() => _focusedMonth = month);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final MotionConfig motion = context.motion;
        final SlimcaSizes sizes = context.sizes;
        final double stripHeight = sizes.weekStripHeight;
        final double gridHeight = _expandedHeight(sizes);
        final double t = clampDouble(_currentFraction, 0.0, 1.0);
        // 透明度交叉淡化走 effects 曲线（颜色/透明度禁过冲判定线，§2.2）
        final double effectsT = clampDouble(
          motion.curveEffectsStandard.transform(t),
          0.0,
          1.0,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
          child: ClipRect(
            child: SizedBox(
              // 高度形变：spatial 曲线对在 settle 补间内生效（拖拽阶段线性跟手）
              height: lerpDouble(stripHeight, gridHeight, t),
              child: Stack(
                children: <Widget>[
                  // 两层均按自然高度 top 锚定，超出 SizedBox 的部分由 ClipRect
                  // 剪裁（形变=自上而下的露出/收拢，跟手阶段即所见）
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: t > 0.5,
                      child: Opacity(
                        opacity: 1.0 - effectsT,
                        child: SlimcaCalendarStrip(
                          selectedDate: widget.selectedDate,
                          onDaySelected: widget.onDaySelected,
                          onWeekChanged: widget.onWeekChanged,
                          today: widget.today,
                          weekStart: widget.weekStart,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: t < 0.5,
                      child: Opacity(
                        opacity: effectsT,
                        child: SlimcaMonthGrid(
                          month: _focusedMonth,
                          selectedDate: widget.selectedDate,
                          onDaySelected: widget.onDaySelected,
                          onMonthChanged: (DateTime month) => setState(
                            () => _focusedMonth = slimcaFirstOfMonth(month),
                          ),
                          recordCounts: widget.recordCounts,
                          headerTrailing: IconButton(
                            icon: Icon(
                              Icons.keyboard_arrow_up,
                              size: sizes.iconVisual,
                            ),
                            tooltip: '收起月历',
                            onPressed: () => _settleTo(false), // §3.2 点收起箭头
                          ),
                          today: widget.today,
                          weekStart: widget.weekStart,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
