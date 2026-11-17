/// 统计报表页（§3.4「统计报表 P1：周/月/年三档；分类环形占比、趋势折线；
/// 钱-热量双轴联动」、§11.2 W15 主线）。
///
/// 结构：周期三档切换（周/月/年）→ 金额按分类堆叠条形（CustomPainter）→
/// 热量按日折线（in/out/net 三线 CustomPainter）→ 钱-热量双轴联动视图
/// （同一天的花费柱与净热量柱上下并排，点击任一图表的桶，三个面板同时
/// 高亮该桶——「吃得贵的日子热量也高吗」的差异化复盘，§3.4）。
///
/// 数据层：day_summary 直读 + entry_lines 聚合兜底（[ReportRepository]，
/// §5.6⑬）；颜色全部经语义 token 解析后传入画笔（§8.2，画笔无主题依赖）；
/// 交互动画仅微交互口径（§9.2 dur.s/§9.5）；图表命中换算与画笔共用同一
/// 几何常量（[_ChartGeometry]），保证点桶索引与渲染对齐。
library;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ledger_calendar.dart';
import '../ledger_colors.dart';
import '../ledger_format.dart';
import '../report_models.dart';
import '../report_repository.dart';

/// 报表页（构造注入仓库，与账本页同款装配，§10.4）。
class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.repository,
    this.initialPeriod = ReportPeriod.month,
    this.initialAnchor,
    this.onEditEntry,
  });

  /// 报表读取仓库（day_summary 直读 + entry_lines 兜底，§5.6⑬）。
  final ReportRepository repository;

  /// 初始周期档（缺省月档——§3.4 主口径）。
  final ReportPeriod initialPeriod;

  /// 初始锚点日（周/月/年档按其归位）；缺省今天（测试注入固定日）。
  final DateTime? initialAnchor;

  /// 桶明细下钻回调（点图元 morph 下钻到当日记录的壳接线，§3.4 P1；
  /// 桶键：日档=`yyyy-MM-dd`、年档=`yyyy-MM`）。空则不提供下钻入口。
  final void Function(String bucketKey)? onEditEntry;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late ReportPeriod _period = widget.initialPeriod;
  late DateTime _anchor = LedgerCalendar.normalize(
    widget.initialAnchor ?? LedgerCalendar.today(),
  );
  String? _selectedBucket;

  ReportRange get _range => reportRangeFor(_period, _anchor);

  /// 周期标题（周「11月16日 - 11月22日」/ 月「2026年11月」/ 年「2026年」）。
  String get _title {
    final ReportRange range = _range;
    switch (_period) {
      case ReportPeriod.week:
        return LedgerCalendar.weekRangeTitle(range.start, range.endExclusive);
      case ReportPeriod.month:
        return LedgerCalendar.monthTitle(_anchor);
      case ReportPeriod.year:
        return LedgerCalendar.yearTitle(_anchor);
    }
  }

  void _shift(int delta) {
    setState(() {
      switch (_period) {
        case ReportPeriod.week:
          _anchor = LedgerCalendar.shiftWeek(_anchor, delta);
        case ReportPeriod.month:
          _anchor = LedgerCalendar.shiftMonth(_anchor, delta);
        case ReportPeriod.year:
          _anchor = LedgerCalendar.shiftYear(_anchor, delta);
      }
      // 区间变了：旧选中桶可能不在新区间，联动高亮一并失效。
      _selectedBucket = null;
    });
  }

  /// 桶选中（联动本体）：同桶再点=取消选中（两轴高亮同步清除）。
  void _selectBucket(String? bucketKey) {
    setState(() {
      _selectedBucket = _selectedBucket == bucketKey ? null : bucketKey;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final ReportRange range = _range;
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        backgroundColor: tokens.surface,
        title: const Text('统计报表'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          SlimcaStaggerItem(
            index: 0,
            child: _PeriodBar(
              period: _period,
              title: _title,
              onSelect: (ReportPeriod period) => setState(() {
                _period = period;
                _selectedBucket = null;
              }),
              onShift: _shift,
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 1,
            child: _CategoryStackedCard(
              repository: widget.repository,
              range: range,
              selectedBucket: _selectedBucket,
              onSelect: _selectBucket,
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 2,
            child: _KcalLineCard(
              repository: widget.repository,
              range: range,
              selectedBucket: _selectedBucket,
              onSelect: _selectBucket,
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 3,
            child: _DualAxisCard(
              repository: widget.repository,
              range: range,
              selectedBucket: _selectedBucket,
              onSelect: _selectBucket,
              onEditEntry: widget.onEditEntry,
            ),
          ),
        ],
      ),
    );
  }
}

/// 周期三档切换条（§3.4「周/月/年三档」）：档位 chips + ‹ 标题 › 步进。
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.period,
    required this.title,
    required this.onSelect,
    required this.onShift,
  });

  final ReportPeriod period;
  final String title;
  final void Function(ReportPeriod) onSelect;
  final void Function(int delta) onShift;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '上一周期',
                onPressed: () => onShift(-1),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface,
                        ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '下一周期',
                onPressed: () => onShift(1),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              for (final ReportPeriod option in ReportPeriod.values)
                Expanded(
                  child: GestureDetector(
                    key: ValueKey<String>('report_period_${option.name}'),
                    onTap: () => onSelect(option),
                    child: AnimatedContainer(
                      duration: context.motion.durS,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: period == option
                            ? tokens.primary
                            : tokens.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          switch (option) {
                            ReportPeriod.week => '周',
                            ReportPeriod.month => '月',
                            ReportPeriod.year => '年',
                          },
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: period == option
                                    ? tokens.onPrimary
                                    : tokens.onSurface,
                                fontWeight: period == option
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 堆叠条形的分段数据（渲染就绪：色值经 token 解析，画笔不碰主题）。
class _StackSegment {
  const _StackSegment({required this.color, required this.value});

  final Color color;
  final int value;
}

/// 图例条目（amountText 为 null 时不显示金额——纯色标图例）。
class _LegendEntry {
  const _LegendEntry({
    required this.label,
    required this.color,
    this.amountText,
  });

  final String label;
  final Color color;
  final String? amountText;
}

/// 图例小行：色点 + 名称（+ 金额）。
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.entry});

  final _LegendEntry entry;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: entry.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          entry.amountText == null
              ? entry.label
              : '${entry.label} ${entry.amountText}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
        ),
      ],
    );
  }
}

/// 图表共用几何常量（画笔与命中换算同源，保证点桶索引一致）。
abstract final class _ChartGeometry {
  /// 图表左右留白。
  static const double padding = 12;

  /// 选中高亮带的圆角。
  static const double bandRadius = 6;

  /// 由图表宽与桶数求点桶索引（LayoutBuilder 约束宽，画笔同式布桶）。
  /// clamp 语义手写比较——`num.clamp` 返回 num，避免隐式下转型。
  static int bucketIndexAt(double chartWidth, double localDx, int count) {
    if (count == 0) {
      return -1;
    }
    final double plotWidth = chartWidth - padding * 2;
    final double slot = plotWidth / count;
    final int index = ((localDx - padding) / slot).floor();
    if (index < 0) {
      return 0;
    }
    if (index > count - 1) {
      return count - 1;
    }
    return index;
  }
}

/// 堆叠条形卡的数据准备产物。
class _StackedChartData {
  const _StackedChartData({required this.segments, required this.legend});

  /// 桶键 → 堆叠段（桶键=完整 x 轴键集的子集；零数据桶无段）。
  final Map<String, List<_StackSegment>> segments;

  final List<_LegendEntry> legend;
}

/// 金额分类堆叠条形卡（§3.4「金额按分类堆叠条形」）：每桶一段堆叠柱，
/// 分类取全区间 topN + 「其他」；点桶联动双轴高亮。
class _CategoryStackedCard extends StatelessWidget {
  static const int _topCategories = 5;

  const _CategoryStackedCard({
    required this.repository,
    required this.range,
    required this.selectedBucket,
    required this.onSelect,
  });

  final ReportRepository repository;
  final ReportRange range;
  final String? selectedBucket;
  final void Function(String? bucketKey) onSelect;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final List<String> keys = reportBucketKeys(range);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '支出构成',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '金额按分类堆叠 · 点图元联动两轴高亮（§3.4）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ReportCategoryStack>>(
            stream: repository.watchCategoryStacks(range: range),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<ReportCategoryStack>> snapshot,
            ) {
              final List<ReportCategoryStack> stacks =
                  snapshot.data ?? const <ReportCategoryStack>[];
              final _StackedChartData data = _buildChartData(stacks, tokens);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    key: const ValueKey<String>('report_stacked_chart'),
                    height: 180,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints box) {
                        final double chartWidth = box.maxWidth;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (TapUpDetails details) {
                            final int index = _ChartGeometry.bucketIndexAt(
                              chartWidth,
                              details.localPosition.dx,
                              keys.length,
                            );
                            if (index >= 0) {
                              onSelect(keys[index]);
                            }
                          },
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _CategoryStackedPainter(
                              keys: keys,
                              segments: data.segments,
                              selectedBucket: selectedBucket,
                              trackColor: tokens.surfaceMuted,
                              axisColor: tokens.outline,
                              selectedColor: tokens.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // x 轴标签行（首/中/尾稀疏标注，防拥挤）。
                  Row(
                    children: <Widget>[
                      for (final (int index, String key) in keys.indexed)
                        Expanded(
                          child: Center(
                            child: Text(
                              _shouldLabel(index, keys.length)
                                  ? (range.byMonth
                                      ? LedgerCalendar.monthAxisLabel(key)
                                      : LedgerCalendar.dayAxisLabel(key))
                                  : '',
                              maxLines: 1,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: tokens.onSurfaceMuted),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final _LegendEntry entry in data.legend)
                        _LegendDot(entry: entry),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// x 轴稀疏标注策略：≤12 桶全标；更多时标首、尾与四分位。
  bool _shouldLabel(int index, int length) {
    if (length <= 12) {
      return true;
    }
    return index == 0 ||
        index == length - 1 ||
        index == length ~/ 4 ||
        index == length ~/ 2 ||
        index == length * 3 ~/ 4;
  }

  /// 切片 → 分段桶 + 图例（topN 分类按全区间金额降序；其余归「其他」；
  /// 分类层序全区间一致，堆叠不随桶跳变）。
  _StackedChartData _buildChartData(
    List<ReportCategoryStack> stacks,
    SlimcaTheme tokens,
  ) {
    final Map<String?, int> totals = <String?, int>{};
    for (final ReportCategoryStack slice in stacks) {
      totals[slice.categoryId] =
          (totals[slice.categoryId] ?? 0) + slice.spendMinor;
    }
    final List<String?> ordered = <String?>[...totals.keys]
      ..sort((String? a, String? b) =>
          (totals[b] ?? 0).compareTo(totals[a] ?? 0));
    final Set<String?> top = <String?>{
      for (final String? id in ordered.take(_topCategories)) id,
    };

    final Map<String, List<_StackSegment>> segments = <String,
        List<_StackSegment>>{};
    final Map<String, int> otherTotals = <String, int>{};
    for (final ReportCategoryStack slice in stacks) {
      final bool isTop = top.contains(slice.categoryId);
      final Color color = isTop
          ? (ledgerColorFromToken(tokens, slice.colorToken) ??
              tokens.onSurfaceMuted)
          : tokens.onSurfaceMuted;
      segments
          .putIfAbsent(slice.bucketKey, () => <_StackSegment>[])
          .add(_StackSegment(color: color, value: slice.spendMinor));
      if (!isTop) {
        otherTotals[slice.bucketKey] =
            (otherTotals[slice.bucketKey] ?? 0) + slice.spendMinor;
      }
    }
    for (final MapEntry<String, int> entry in otherTotals.entries) {
      if (entry.value > 0) {
        segments[entry.key]!.add(
          _StackSegment(color: tokens.onSurfaceMuted, value: entry.value),
        );
      }
    }

    final List<_LegendEntry> legend = <_LegendEntry>[];
    for (final String? id in ordered.take(_topCategories)) {
      final ReportCategoryStack sample = stacks.firstWhere(
        (ReportCategoryStack s) => s.categoryId == id,
      );
      legend.add(_LegendEntry(
        label: sample.categoryName ?? '未分类',
        color: ledgerColorFromToken(tokens, sample.colorToken) ??
            tokens.onSurfaceMuted,
        amountText: LedgerFormat.moneyMinor(totals[id] ?? 0),
      ));
    }
    final int otherTotal = <String?, int>{
      for (final String? id in ordered.skip(_topCategories))
        id: totals[id] ?? 0,
    }.values.fold(0, (int sum, int v) => sum + v);
    if (otherTotal > 0) {
      legend.add(_LegendEntry(
        label: '其他',
        color: tokens.onSurfaceMuted,
        amountText: LedgerFormat.moneyMinor(otherTotal),
      ));
    }
    return _StackedChartData(segments: segments, legend: legend);
  }
}

/// 堆叠条形画笔（§3.4；颜色由调用方经 token 解析后传入，画笔无主题依赖）。
/// x 轴恒按 [keys] 全量布桶（与命中换算同源），零数据桶画基线短柱。
class _CategoryStackedPainter extends CustomPainter {
  _CategoryStackedPainter({
    required this.keys,
    required this.segments,
    required this.selectedBucket,
    required this.trackColor,
    required this.axisColor,
    required this.selectedColor,
  });

  final List<String> keys;
  final Map<String, List<_StackSegment>> segments;
  final String? selectedBucket;
  final Color trackColor;
  final Color axisColor;
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (keys.isEmpty) {
      return;
    }
    const double padding = _ChartGeometry.padding;
    final double plotWidth = size.width - padding * 2;
    final double slot = plotWidth / keys.length;
    // 柱宽上限 28（clamp 语义手写比较——num.clamp 返回 num，避免隐式下转型）。
    final double rawBar = slot * 0.62;
    final double barWidth = rawBar < 2.0 ? 2.0 : (rawBar > 28.0 ? 28.0 : rawBar);
    final double plotHeight = size.height - 24;
    final double baseline = size.height - 12;

    // 基线（§8.2：outline token）。
    canvas.drawLine(
      Offset(padding, baseline),
      Offset(size.width - padding, baseline),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    double maxTotal = 0;
    for (final List<_StackSegment> list in segments.values) {
      final int total = list.fold(0, (int sum, _StackSegment s) => sum + s.value);
      if (total > maxTotal) {
        maxTotal = total.toDouble();
      }
    }

    for (int i = 0; i < keys.length; i++) {
      final String key = keys[i];
      final double center = padding + slot * i + slot / 2;
      if (key == selectedBucket) {
        // 选中高亮带（双轴联动：三个面板同色高亮，§3.4/§11.2）。
        final RRect band = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            padding + slot * i + 1,
            4,
            slot - 2,
            baseline - 4,
          ),
          const Radius.circular(_ChartGeometry.bandRadius),
        );
        canvas.drawRRect(
          band,
          Paint()..color = selectedColor.withValues(alpha: 0.12),
        );
        canvas.drawRRect(
          band,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = selectedColor
            ..strokeWidth = 1,
        );
      }
      double yCursor = baseline;
      final List<_StackSegment>? list = segments[key];
      if (list == null || maxTotal <= 0) {
        continue;
      }
      for (final _StackSegment segment in list) {
        if (segment.value <= 0) {
          continue;
        }
        final double segmentHeight =
            (segment.value / maxTotal) * plotHeight;
        canvas.drawRect(
          Rect.fromLTWH(
            center - barWidth / 2,
            yCursor - segmentHeight,
            barWidth,
            segmentHeight,
          ),
          Paint()..color = segment.color,
        );
        yCursor -= segmentHeight;
      }
    }
  }

  @override
  bool shouldRepaint(_CategoryStackedPainter oldDelegate) =>
      oldDelegate.selectedBucket != selectedBucket ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.selectedColor != selectedColor ||
      oldDelegate.keys != keys ||
      oldDelegate.segments != segments;
}

/// 热量折线卡（§3.4「热量按日折线（in/out/net 三线）」）。
class _KcalLineCard extends StatelessWidget {
  const _KcalLineCard({
    required this.repository,
    required this.range,
    required this.selectedBucket,
    required this.onSelect,
  });

  final ReportRepository repository;
  final ReportRange range;
  final String? selectedBucket;
  final void Function(String? bucketKey) onSelect;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '热量趋势',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '摄入 / 消耗 / 净三线 · 点图元联动两轴高亮（§3.4）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ReportBucketPoint>>(
            stream: repository.watchBucketSeries(range: range),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<ReportBucketPoint>> snapshot,
            ) {
              final List<ReportBucketPoint> points =
                  snapshot.data ?? const <ReportBucketPoint>[];
              return SizedBox(
                key: const ValueKey<String>('report_kcal_chart'),
                height: 160,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints box) {
                    final double chartWidth = box.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) {
                        final int index = _ChartGeometry.bucketIndexAt(
                          chartWidth,
                          details.localPosition.dx,
                          points.length,
                        );
                        if (index >= 0) {
                          onSelect(points[index].bucketKey);
                        }
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _KcalLinePainter(
                          points: points,
                          selectedBucket: selectedBucket,
                          inColor: tokens.kcalIn,
                          outColor: tokens.kcalOut,
                          netColor: tokens.net,
                          axisColor: tokens.outline,
                          selectedColor: tokens.primary,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: <Widget>[
              _LegendDot(
                entry: _LegendEntry(label: '摄入', color: tokens.kcalIn),
              ),
              _LegendDot(
                entry: _LegendEntry(label: '消耗', color: tokens.kcalOut),
              ),
              _LegendDot(entry: _LegendEntry(label: '净', color: tokens.net)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 热量折线画笔（in/out/net 三线 + 选中桶三色圆点；零基线居中——净可为负）。
class _KcalLinePainter extends CustomPainter {
  _KcalLinePainter({
    required this.points,
    required this.selectedBucket,
    required this.inColor,
    required this.outColor,
    required this.netColor,
    required this.axisColor,
    required this.selectedColor,
  });

  final List<ReportBucketPoint> points;
  final String? selectedBucket;
  final Color inColor;
  final Color outColor;
  final Color netColor;
  final Color axisColor;
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    const double padding = _ChartGeometry.padding;
    final double plotWidth = size.width - padding * 2;
    final double slot = plotWidth / points.length;
    final double midY = size.height / 2;
    final double halfPlot = size.height / 2 - 8;

    // 零基线（净热量可为负：中轴为 0，§8.2 outline token）。
    canvas.drawLine(
      Offset(padding, midY),
      Offset(size.width - padding, midY),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    double maxValue = 1;
    for (final ReportBucketPoint point in points) {
      for (final int v in <int>[
        point.kcalIn,
        point.kcalOut,
        point.netKcal.abs(),
      ]) {
        if (v > maxValue) {
          maxValue = v.toDouble();
        }
      }
    }

    Offset pointOf(int index, int value) => Offset(
          padding + slot * index + slot / 2,
          midY - (value / maxValue) * halfPlot,
        );

    void drawLine(int Function(ReportBucketPoint) pick, Color color) {
      final Path path = Path();
      var started = false;
      for (int i = 0; i < points.length; i++) {
        final Offset p = pointOf(i, pick(points[i]));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    drawLine((ReportBucketPoint p) => p.kcalIn, inColor);
    drawLine((ReportBucketPoint p) => p.kcalOut, outColor);
    drawLine((ReportBucketPoint p) => p.netKcal, netColor);

    // 选中桶：高亮带 + 三线圆点（双轴联动，§3.4/§11.2）。
    for (int i = 0; i < points.length; i++) {
      if (points[i].bucketKey != selectedBucket) {
        continue;
      }
      final RRect band = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          padding + slot * i + 1,
          4,
          slot - 2,
          size.height - 8,
        ),
        const Radius.circular(_ChartGeometry.bandRadius),
      );
      canvas.drawRRect(
        band,
        Paint()..color = selectedColor.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        band,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = selectedColor
          ..strokeWidth = 1,
      );
      final ReportBucketPoint point = points[i];
      for (final (int value, Color color) in <(int, Color)>[
        (point.kcalIn, inColor),
        (point.kcalOut, outColor),
        (point.netKcal, netColor),
      ]) {
        canvas.drawCircle(pointOf(i, value), 4, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(_KcalLinePainter oldDelegate) =>
      oldDelegate.selectedBucket != selectedBucket ||
      oldDelegate.points != points;
}

/// 钱-热量双轴联动卡（§3.4/§11.2 W15：同一桶的花费柱（上轴）与净热量柱
/// （下轴）上下并排；点桶后三个面板同步高亮 + 详情条显示该桶钱/热量数字，
/// 「吃得贵的日子热量也高吗」一屏对齐复盘）。
class _DualAxisCard extends StatelessWidget {
  const _DualAxisCard({
    required this.repository,
    required this.range,
    required this.selectedBucket,
    required this.onSelect,
    required this.onEditEntry,
  });

  final ReportRepository repository;
  final ReportRange range;
  final String? selectedBucket;
  final void Function(String? bucketKey) onSelect;
  final void Function(String bucketKey)? onEditEntry;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '钱-热量联动',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '上轴花费 · 下轴净热量 · 点日期两轴高亮（§11.2）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<ReportBucketPoint>>(
            stream: repository.watchBucketSeries(range: range),
            builder: (
              BuildContext context,
              AsyncSnapshot<List<ReportBucketPoint>> snapshot,
            ) {
              final List<ReportBucketPoint> points =
                  snapshot.data ?? const <ReportBucketPoint>[];
              final ReportBucketPoint? selected = points
                  .where(
                    (ReportBucketPoint p) => p.bucketKey == selectedBucket,
                  )
                  .firstOrNull;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    key: const ValueKey<String>('report_dual_axis'),
                    height: 140,
                    width: double.infinity,
                    child: LayoutBuilder(
                      builder: (BuildContext context, BoxConstraints box) {
                        final double chartWidth = box.maxWidth;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (TapUpDetails details) {
                            final int index = _ChartGeometry.bucketIndexAt(
                              chartWidth,
                              details.localPosition.dx,
                              points.length,
                            );
                            if (index >= 0) {
                              onSelect(points[index].bucketKey);
                            }
                          },
                          child: CustomPaint(
                            size: Size.infinite,
                            painter: _DualAxisPainter(
                              points: points,
                              selectedBucket: selectedBucket,
                              spendColor: tokens.moneyOut,
                              kcalInColor: tokens.kcalIn,
                              kcalOutColor: tokens.kcalOut,
                              axisColor: tokens.outline,
                              selectedColor: tokens.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SelectedDetailStrip(
                    range: range,
                    selected: selected,
                    onEditEntry: onEditEntry,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 双轴画笔：中轴为 0——上轴支出柱（moneyOut），下轴净热量柱（净>0 用
/// kcalIn 色「吃多了」、净<0 用 kcalOut 色「练回来了」，§2.1③ 口径）。
class _DualAxisPainter extends CustomPainter {
  _DualAxisPainter({
    required this.points,
    required this.selectedBucket,
    required this.spendColor,
    required this.kcalInColor,
    required this.kcalOutColor,
    required this.axisColor,
    required this.selectedColor,
  });

  final List<ReportBucketPoint> points;
  final String? selectedBucket;
  final Color spendColor;
  final Color kcalInColor;
  final Color kcalOutColor;
  final Color axisColor;
  final Color selectedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }
    const double padding = _ChartGeometry.padding;
    final double plotWidth = size.width - padding * 2;
    final double slot = plotWidth / points.length;
    // 柱宽上限 26（clamp 语义手写比较——num.clamp 返回 num，避免隐式下转型）。
    final double rawBar = slot * 0.6;
    final double barWidth = rawBar < 2.0 ? 2.0 : (rawBar > 26.0 ? 26.0 : rawBar);
    final double midY = size.height / 2;
    final double halfHeight = size.height / 2 - 10;

    // 中轴（0 线，§8.2 outline token）。
    canvas.drawLine(
      Offset(padding, midY),
      Offset(size.width - padding, midY),
      Paint()
        ..color = axisColor
        ..strokeWidth = 1,
    );

    double maxSpend = 1;
    double maxKcal = 1;
    for (final ReportBucketPoint point in points) {
      if (point.spendMinor > maxSpend) {
        maxSpend = point.spendMinor.toDouble();
      }
      if (point.netKcal.abs() > maxKcal) {
        maxKcal = point.netKcal.abs().toDouble();
      }
    }

    for (int i = 0; i < points.length; i++) {
      final ReportBucketPoint point = points[i];
      final double center = padding + slot * i + slot / 2;
      if (point.bucketKey == selectedBucket) {
        // 选中高亮带（上下两轴一并高亮——联动语义本体，§11.2）。
        final RRect band = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            padding + slot * i + 1,
            4,
            slot - 2,
            size.height - 8,
          ),
          const Radius.circular(_ChartGeometry.bandRadius),
        );
        canvas.drawRRect(
          band,
          Paint()..color = selectedColor.withValues(alpha: 0.12),
        );
        canvas.drawRRect(
          band,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = selectedColor
            ..strokeWidth = 1,
        );
      }
      // 上轴：花费柱（moneyOut，§8.2 双主色锚定）。
      if (point.spendMinor > 0) {
        final double h = (point.spendMinor / maxSpend) * (halfHeight - 6);
        canvas.drawRect(
          Rect.fromLTWH(center - barWidth / 2, midY - 6 - h, barWidth, h),
          Paint()..color = spendColor,
        );
      }
      // 下轴：净热量柱（净>0=kcalIn「吃多了」，净<0=kcalOut「练回来」）。
      final int net = point.netKcal;
      if (net != 0) {
        final double h = (net.abs() / maxKcal) * (halfHeight - 6);
        canvas.drawRect(
          Rect.fromLTWH(center - barWidth / 2, midY + 6, barWidth, h),
          Paint()..color = net > 0 ? kcalInColor : kcalOutColor,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DualAxisPainter oldDelegate) =>
      oldDelegate.selectedBucket != selectedBucket ||
      oldDelegate.points != points;
}

/// 选中桶详情条（联动高亮的数字面：日期 + 支出/收入/摄入/消耗/净；
/// 未选中时展示引导文案）。
class _SelectedDetailStrip extends StatelessWidget {
  const _SelectedDetailStrip({
    required this.range,
    required this.selected,
    required this.onEditEntry,
  });

  final ReportRange range;
  final ReportBucketPoint? selected;
  final void Function(String bucketKey)? onEditEntry;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final Widget child;
    if (selected == null) {
      child = Text(
        '点任一图元选中日期，两轴同步高亮（§11.2 双轴联动）',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
      );
    } else {
      final String dateLabel = range.byMonth
          ? LedgerCalendar.monthAxisLabel(selected!.bucketKey)
          : LedgerCalendar.dayLabel(formatCalendarDay(_bucketDate(selected!.bucketKey)));
      child = Row(
        children: <Widget>[
          Text(
            dateLabel,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            '支出 ${LedgerFormat.moneyMinor(selected!.spendMinor)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.moneyOut,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            '摄入 ${selected!.kcalIn} · 消耗 ${selected!.kcalOut} · 净 ${selected!.netKcal} kcal',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.net,
                ),
          ),
          const Spacer(),
          if (onEditEntry != null)
            TextButton(
              key: const ValueKey<String>('report_detail_drill'),
              onPressed: () => onEditEntry!(selected!.bucketKey),
              child: const Text('看当日'),
            ),
        ],
      );
    }
    return Container(
      key: const ValueKey<String>('report_detail_strip'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  /// 桶键 → 归属日（年档月桶取当月 1 日，仅供日标签展示）。
  DateTime _bucketDate(String bucketKey) {
    if (range.byMonth) {
      final int year = int.parse(bucketKey.substring(0, 4));
      final int month = int.parse(bucketKey.substring(5, 7));
      return DateTime(year, month);
    }
    return DateTime.parse(bucketKey);
  }
}
