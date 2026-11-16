/// 当日卡片墙（§3.2 卡片墙 + §9.3#1 级联入场 + §3.2 空态）。
///
/// 由 watch 投影流驱动（§5.6⑬）：day_summary 直出热量环/支出/存钱快照，
/// 本月累计读投影表逐日求和（§5.6「仪表盘首帧直读本表、零业务查询」）。
/// 卡片清单与 §3.2 一一对应：热量环（摄入/消耗/净+预算余）、今日支出与
/// 本月累计、净热量（「今日还能吃」心智 §2.1③）、存钱进度（P1 自动接入）。
library;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../calendar.dart';
import '../dashboard_models.dart';
import '../dashboard_repository.dart';

/// 当日卡片墙主体（§3.2）。
///
/// 以 [date] 的投影 watch 流为唯一数据源；切换日期时外层以日期为 key 重建
/// 本体（外层 SlimcaSharedAxisSwitcher 承担 §9.3#2 水平共享轴），级联入场
/// 随新一天内容重播——FLIP 位置保持（§9.3#2「layout delta」）为 W2+ 演进项，
/// 与骨架版（apps/mobile W1）同一路径。
class DashboardDayBody extends StatelessWidget {
  const DashboardDayBody({
    super.key,
    required this.date,
    required this.repository,
    this.onStartCapture,
  });

  /// 展示日（本地日历日，§5.1）。
  final DateTime date;

  /// 投影数据源（§5.6⑬）。
  final DashboardRepository repository;

  /// 空态引导 CTA 回调（§3.2）。
  final VoidCallback? onStartCapture;

  @override
  Widget build(BuildContext context) {
    final String dateKey = formatCalendarDay(date);
    return StreamBuilder<DashboardDaySummary?>(
      stream: repository.watchDay(dateKey),
      builder:
          (BuildContext context, AsyncSnapshot<DashboardDaySummary?> snapshot) {
            final DashboardDaySummary? summary = snapshot.data;
            // 投影流发出首值（active）后才做空态判定：等待首值期间按全零直出，
            // 不出现任何加载态（§3.2 快照直出、无 spinner）。
            final bool empty =
                snapshot.connectionState == ConnectionState.active &&
                (summary == null || !summary.hasAnyRecord);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // §9.3#1：卡片墙按 staggerInterval（80ms）级联上浮。
                SlimcaStaggerItem(
                  index: 0,
                  child: _CalorieRingCard(summary: summary),
                ),
                const SizedBox(height: 12),
                SlimcaStaggerItem(
                  index: 1,
                  // 支出/净热量双卡等高并排：IntrinsicHeight 取双卡固有高度作
                  // 有界约束（ListView 子项高度无界，Row 直接 stretch 会拿到
                  // 无限高度崩溃——W1 骨架已踩过并修复，§3.2 卡片墙）。
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(
                          child: _SpendCard(
                            date: date,
                            repository: repository,
                            summary: summary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _NetCalorieCard(summary: summary)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SlimcaStaggerItem(
                  index: 2,
                  child: _SavingsCard(summary: summary),
                ),
                if (empty) ...<Widget>[
                  const SizedBox(height: 12),
                  SlimcaStaggerItem(
                    index: 3,
                    child: _EmptyGuide(onStartCapture: onStartCapture),
                  ),
                ],
              ],
            );
          },
    );
  }
}

/// 热量环卡（§3.2 卡片墙第 1 项「热量环（摄入/消耗/净+预算余）」）。
///
/// 数据来自 day_summary 投影（§5.6⑬ kcal_in/kcal_out/budget_snapshot），
/// SlimcaCalorieRing spring 推进（§9.2 spring.soft「环推进」、§9.3#4/#5）。
/// 预算未设置时以 0 传入（环按满档呈示、文案标注「未设置」）——预算经
/// §3.4 每日目标落库后由 budget_snapshot 驱动（§5.6⑬）。
class _CalorieRingCard extends StatelessWidget {
  const _CalorieRingCard({required this.summary});

  final DashboardDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int kcalIn = summary?.kcalIn ?? 0;
    final int kcalOut = summary?.kcalOut ?? 0;
    final int net = summary?.netKcal ?? 0;
    final int? budget = summary?.budget.kcalBudget;
    return _DashboardCard(
      child: Row(
        children: <Widget>[
          SlimcaCalorieRing(
            kcalIn: kcalIn,
            kcalOut: kcalOut,
            budget: budget ?? 0,
            size: 108,
            strokeWidth: 10,
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$net',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: tokens.net,
                  ),
                ),
                Text(
                  '净 kcal',
                  style: textTheme.labelSmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '热量',
                  style: textTheme.titleMedium?.copyWith(
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                _MetricLine(
                  label: '摄入',
                  value: '$kcalIn kcal',
                  valueColor: tokens.kcalIn,
                ),
                _MetricLine(
                  label: '消耗',
                  value: '$kcalOut kcal',
                  valueColor: tokens.kcalOut,
                ),
                _MetricLine(
                  label: '预算',
                  value: budget == null ? '未设置' : '$budget kcal',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日支出卡（§3.2 卡片墙第 2 项「今日支出与预算余」）。
///
/// 今日 = day_summary.spend_minor（§5.6⑬）；本月累计 = watch 投影表逐日
/// 求和（DashboardRepository.watchMonthSpendMinor）。金额语义色暖橘
/// （§8.2 双主色锚定：橘=钱）；预算余随 budget_snapshot 驱动（§3.2 预算
/// 状态色，超支 danger）。
class _SpendCard extends StatelessWidget {
  const _SpendCard({
    required this.date,
    required this.repository,
    required this.summary,
  });

  final DateTime date;
  final DashboardRepository repository;
  final DashboardDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int todayMinor = summary?.spendMinor ?? 0;
    final int? spendBudget = summary?.budget.spendBudgetMinor;
    final bool overBudget = spendBudget != null && todayMinor > spendBudget;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '今日支出',
            style: textTheme.labelMedium?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatMoneyMinor(todayMinor),
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.moneyOut,
            ),
          ),
          const SizedBox(height: 4),
          // 本月累计：watch 投影表（§5.6「首帧直读本表、零业务查询」）。
          StreamBuilder<int>(
            stream: repository.watchMonthSpendMinor(
              DashboardCalendar.monthPrefix(date),
            ),
            initialData: 0,
            builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
              return Text(
                '本月累计 ${_formatMoneyMinor(snapshot.data ?? 0)}',
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              );
            },
          ),
          Text(
            spendBudget == null
                ? '预算余：先设置每日支出目标'
                : '预算余 ${_formatMoneyMinor(spendBudget - todayMinor)}',
            style: textTheme.bodySmall?.copyWith(
              color: overBudget ? tokens.danger : tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 净热量卡（§3.2「摄入/消耗/净+预算余」、§2.1③ kcal 账本「今日还能吃」心智）。
///
/// 预算已设 → 「今日还能吃 x kcal」（success）/「超预算 x kcal」（danger，
/// §3.2 预算状态色）；未设置 → 引导设置每日目标（§3.4）。
class _NetCalorieCard extends StatelessWidget {
  const _NetCalorieCard({required this.summary});

  final DashboardDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final int net = summary?.netKcal ?? 0;
    final int? budget = summary?.budget.kcalBudget;
    final String statusText;
    final Color statusColor;
    if (budget == null) {
      statusText = '设置热量预算后看「今日还能吃」';
      statusColor = tokens.onSurfaceMuted;
    } else if (net > budget) {
      statusText = '超预算 ${net - budget} kcal';
      statusColor = tokens.danger;
    } else {
      statusText = '今日还能吃 ${budget - net} kcal';
      statusColor = tokens.success;
    }
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '净热量',
            style: textTheme.labelMedium?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$net kcal',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: tokens.net,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '摄入 ${summary?.kcalIn ?? 0} − 消耗 ${summary?.kcalOut ?? 0}',
            style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 4),
          Text(
            statusText,
            style: textTheme.bodySmall?.copyWith(color: statusColor),
          ),
        ],
      ),
    );
  }
}

/// 存钱进度卡（§3.2 卡片墙第 5 项「上线后自动接入」、§3.6 存钱目标 P1）。
///
/// 读 day_summary.savings_progress（§5.6⑬ goal_id→{contributed_minor,
/// target_minor}）；为空 → 占位空态（W2 v1 尚无存钱目标）。
class _SavingsCard extends StatelessWidget {
  const _SavingsCard({required this.summary});

  final DashboardDaySummary? summary;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Map<String, DashboardSavingsProgress>? savings = summary?.savings;
    if (savings == null || savings.isEmpty) {
      return _DashboardCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.savings_outlined, color: tokens.onSurfaceMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '存钱目标上线后自动接入卡片墙（P1，§3.6）',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final List<DashboardSavingsProgress> goals = savings.values.toList();
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < goals.length; i++) {
      final DashboardSavingsProgress progress = goals[i];
      if (i > 0) {
        rows.add(const SizedBox(height: 12));
      }
      rows.add(
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '存钱目标',
                style: textTheme.titleSmall?.copyWith(color: tokens.onSurface),
              ),
            ),
            Text(
              '${_formatMoneyMinor(progress.contributedMinor)}'
              ' / ${_formatMoneyMinor(progress.targetMinor)}',
              style: textTheme.labelMedium?.copyWith(color: tokens.moneyIn),
            ),
          ],
        ),
      );
      rows.add(const SizedBox(height: 6));
      rows.add(
        SizedBox(
          height: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress.fraction,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.moneyIn,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }
}

/// 空态引导（§3.2「还没有记录时引导首次录入」；§2.3 步 1 一句话定位）。
class _EmptyGuide extends StatelessWidget {
  const _EmptyGuide({this.onStartCapture});

  final VoidCallback? onStartCapture;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        children: <Widget>[
          Icon(Icons.add_circle_outline, size: 32, color: tokens.primary),
          const SizedBox(height: 8),
          Text(
            '今天还没有记录',
            style: textTheme.titleMedium?.copyWith(color: tokens.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '记一件事，钱和热量一起入账',
            style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
          ),
          if (onStartCapture != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onStartCapture,
              child: const Text('立即记录'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 仪表盘卡片容器（§3.2 卡片墙视觉一致性）：surfaceCard 语义 token（§8.2）；
/// 圆角 16 为几何常量（radiusScale 滑杆随 P1 主题编辑器接线，§8.3）。
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

/// 卡片内指标行。
class _MetricLine extends StatelessWidget {
  const _MetricLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: tokens.onSurface),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: valueColor ?? tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 金额展示（§5.1 金额行：整数分存储 → 元展示，负值带符号）。
String _formatMoneyMinor(int minor) {
  final bool negative = minor < 0;
  final int absMinor = negative ? -minor : minor;
  final int yuan = absMinor ~/ 100;
  final String cents = '${absMinor % 100}'.padLeft(2, '0');
  return '${negative ? '-' : ''}¥${_groupThousands(yuan)}.$cents';
}

/// 千位分组（展示用，不参与存储/同步，§5.1）。
String _groupThousands(int value) {
  final String digits = '$value';
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    final int remaining = digits.length - i;
    grouped.write(digits[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      grouped.write(',');
    }
  }
  return grouped.toString();
}
