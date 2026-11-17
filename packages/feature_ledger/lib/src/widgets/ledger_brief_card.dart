/// 日简报卡片（§3.4「今日收支/热量摘要」；数据走 day_summary 投影直读，
/// §3.2 首帧直读本表、零业务查询；§5.6⑬ budget_snapshot 口径）。
library;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ledger_calendar.dart';
import '../ledger_format.dart';
import '../ledger_models.dart';
import '../ledger_repository.dart';

/// 日简报卡：当日 支出/收入/净热量 三指标 + 预算达成行（超支标红）。
///
/// - 投影行未建（当日尚无记录）→ 零值 + 引导文案，不造假数据（§5.6⑬
///   本地件只读）；
/// - budgets 快照缺失 → 「每日目标未设置」提示（§3.4 每日目标）；
/// - 预算行颜色遵守语义 token：预算余=success、超支=danger（§8.2）。
class LedgerDayBriefingCard extends StatelessWidget {
  const LedgerDayBriefingCard({
    super.key,
    required this.repository,
    required this.date,
  });

  final LedgerRepository repository;

  /// 简报日（缺省今天由 [LedgerPage] 决定；测试可注入固定日保证确定性）。
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final bool isToday =
        LedgerCalendar.normalize(date) == LedgerCalendar.today();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StreamBuilder<LedgerDayBriefing?>(
        stream: repository.watchDayBriefing(formatCalendarDay(date)),
        builder: (
          BuildContext context,
          AsyncSnapshot<LedgerDayBriefing?> snapshot,
        ) {
          final LedgerDayBriefing? summary = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '日简报',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${isToday ? '今日 · ' : ''}${LedgerCalendar.dayLabel(formatCalendarDay(date))}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _BriefingMetric(
                      label: '支出',
                      value: LedgerFormat.moneyMinor(summary?.spendMinor ?? 0),
                      color: tokens.moneyOut,
                    ),
                  ),
                  Expanded(
                    child: _BriefingMetric(
                      label: '收入',
                      value: LedgerFormat.signedMoneyMinor(
                        summary?.incomeMinor ?? 0,
                      ),
                      color: tokens.moneyIn,
                    ),
                  ),
                  Expanded(
                    child: _BriefingMetric(
                      label: '净热量',
                      value: LedgerFormat.kcal(summary?.netKcal ?? 0),
                      color: tokens.net,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (summary == null)
                Text(
                  '当日暂无记录',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                )
              else if (summary.budgets.isEmpty)
                Text(
                  '每日目标未设置 · 到分类管理可设置每日目标',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                )
              else
                // 分类名经 options 流回填（快照只带 category_id，§5.6⑬）。
                // W15：日简报卡只渲染 daily 周期预算（月度预算属「月度目标」
                // 口径，§5.4⑥ 周期语义，不混入每日目标行）。
                StreamBuilder<List<LedgerCategoryOption>>(
                  stream: repository.watchCategoryOptions(),
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<List<LedgerCategoryOption>> catSnapshot,
                  ) {
                    final Map<String, String> namesById = <String, String>{
                      for (final LedgerCategoryOption option
                          in catSnapshot.data ?? const <LedgerCategoryOption>[])
                        option.id: option.name,
                    };
                    final List<LedgerBudgetItem> dailyBudgets = summary
                        .budgets
                        .where((LedgerBudgetItem item) =>
                            item.periodType == kBudgetPeriodDaily)
                        .toList();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (final LedgerBudgetItem item in dailyBudgets)
                          _BudgetLine(item: item, namesById: namesById),
                      ],
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 单个摘要指标（label 上、value 下的紧凑列）。
class _BriefingMetric extends StatelessWidget {
  const _BriefingMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
        ),
      ],
    );
  }
}

/// 一条预算达成行：`热量目标 2000 kcal · 还能吃 1350 kcal` /
/// `支出目标 ¥10.00 · 超支 ¥8.50`（§5.6⑬ used/remaining 口径）。
class _BudgetLine extends StatelessWidget {
  const _BudgetLine({required this.item, required this.namesById});

  final LedgerBudgetItem item;
  final Map<String, String> namesById;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final String label;
    if (item.isKcal) {
      label = '热量目标 ${LedgerFormat.kcal(item.amount)}';
    } else if (item.categoryId == null) {
      label = '支出目标 ${LedgerFormat.moneyMinor(item.amount)}';
    } else {
      // 分类级目标（§5.4⑥ category_id 非空）；分类已删时给可读兜底名。
      final String? name = namesById[item.categoryId];
      label =
          '「${name ?? '已删分类'}」目标 ${LedgerFormat.moneyMinor(item.amount)}';
    }
    final bool over = item.remaining < 0;
    final String status;
    if (item.remaining >= 0) {
      status = item.isKcal
          ? '还能吃 ${LedgerFormat.kcal(item.remaining)}'
          : '预算余 ${LedgerFormat.moneyMinor(item.remaining)}';
    } else {
      status = item.isKcal
          ? '超支 ${LedgerFormat.kcal(-item.remaining)}'
          : '超支 ${LedgerFormat.moneyMinor(-item.remaining)}';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
            ),
          ),
          Text(
            status,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: over ? tokens.danger : tokens.success,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
