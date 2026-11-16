/// 账本 Tab 真页（§3.4 流水列表、§4.2「流水列表+分类管理+预算入口+统计
/// 入口」、§4.3 /ledger、§11.1 W5-6「记账完整化」）。
///
/// 结构：按日分组的流水列表（ledgerDayGroupsProvider，date 倒序、日内
/// created_at 升序）；日头展示「n月n日 + 支出/收入合计」（§3.4「按日分组
/// 的支出列表」）；点条目进编辑抽屉（feature_capture CapturePage 编辑态，
/// §3.4 修正=新增行、§10.4 唯一录入 UI 纪律）。空态一句话引导（§2.3 步 1）。
/// 分类管理/预算设置/统计入口（§4.2 其余三项）随 W5-6 后续任务接入，
/// AppBar 提供入口位（W5-6 主线先落流水真页）。
library;

import 'package:feature_capture/feature_capture.dart' show CaptureSeed, showCaptureSheet;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../common/format.dart';
import 'ledger_state.dart';

/// 账本 Tab。
class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncGroups = ref.watch(ledgerDayGroupsProvider);
    final groups = asyncGroups.value ?? const <LedgerDayGroup>[];

    return Scaffold(
      appBar: AppBar(title: const Text('账本')),
      body: SafeArea(
        child: groups.isEmpty
            ? _LedgerEmptyHint(hasData: asyncGroups.hasValue)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final group in groups) ...[
                    _LedgerDayHeader(group: group),
                    const SizedBox(height: 4),
                    _LedgerCard(
                      child: Column(
                        children: [
                          for (final view in group.entries)
                            _LedgerEntryTile(
                              key: ValueKey('ledger_entry_${view.entryId}'),
                              view: view,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
      ),
    );
  }
}

/// 日头：n月n日 + 支出/收入合计（§3.4 按日分组）。
class _LedgerDayHeader extends StatelessWidget {
  const _LedgerDayHeader({required this.group});

  final LedgerDayGroup group;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final parts = <String>[
      if (group.spendMinor > 0) '支出 ${yuanFromMinor(group.spendMinor)}',
      if (group.incomeMinor > 0) '收入 ${yuanFromMinor(group.incomeMinor)}',
      if (group.kcalOut > 0) '消耗 ${group.kcalOut} kcal',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            calendarDayLabel(group.date),
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: tokens.onSurface,
            ),
          ),
          const Spacer(),
          if (parts.isNotEmpty)
            Text(
              parts.join(' · '),
              style: textTheme.labelMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// 账本卡容器（与仪表盘/计划卡同形：surfaceCard + r16，§3.2/§8.2）。
class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.slimca.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: child,
      ),
    );
  }
}

/// 单条流水行：kind 图标 + 标题 + 摘要（摄入/消耗/支出/收入），点击进编辑。
class _LedgerEntryTile extends StatelessWidget {
  const _LedgerEntryTile({super.key, required this.view});

  final LedgerEntryView view;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    // 摘要的金额/热量着色（语义 token，§8.2）。
    final summaryParts = <String, Color>{
      if (view.kcalIn > 0) '摄入 ${view.kcalIn} kcal': tokens.kcalIn,
      if (view.kcalOut > 0) '消耗 ${view.kcalOut} kcal': tokens.kcalOut,
      if (view.spendMinor > 0)
        '支出 ${yuanFromMinor(view.spendMinor)}': tokens.moneyOut,
      if (view.incomeMinor > 0)
        '收入 ${yuanFromMinor(view.incomeMinor)}': tokens.moneyIn,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        _kindIcon(view.kind),
        color: tokens.onSurfaceMuted,
      ),
      title: Text(
        view.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium,
      ),
      subtitle: summaryParts.isEmpty
          ? Text(
              '仅记录描述',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                for (final entry in summaryParts.entries)
                  Text(
                    entry.key,
                    style: textTheme.bodySmall?.copyWith(
                      color: entry.value,
                    ),
                  ),
              ],
            ),
      // 编辑：弹簧抽屉编辑态（预填+修正链落库，§3.4/§6.5 金额不可变）。
      onTap: () => showCaptureSheet(
        context,
        seed: CaptureSeed(editEntryId: view.entryId),
      ),
    );
  }

  IconData _kindIcon(String kindWire) {
    return switch (kindWire) {
      'food' => Icons.restaurant_outlined,
      'expense' => Icons.payments_outlined,
      'mixed' => Icons.restaurant_menu_outlined,
      'fitness' => Icons.fitness_center,
      'note' => Icons.sticky_note_2_outlined,
      _ => Icons.edit_note_outlined,
    };
  }
}

/// 空态引导：一句话定位 + 录入入口提示（§1.2、§2.3 步 1）。
class _LedgerEmptyHint extends StatelessWidget {
  const _LedgerEmptyHint({required this.hasData});

  /// 流已装载但确无数据=true；装载中=false（不显示「还没有记录」误导）。
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: tokens.onSurfaceMuted,
          ),
          const SizedBox(height: 12),
          Text(
            hasData ? '还没有记录' : '正在装载流水…',
            style: textTheme.bodyLarge?.copyWith(color: tokens.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            hasData
                ? '点击底部「+」记第一笔，钱和卡路里一起入账（§3.4）'
                : '§2.3 零等待空屏：流水装载即现，无 spinner 打断',
            style: textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
