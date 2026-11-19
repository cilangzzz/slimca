/// 存钱目标详情页（§3.6 目标详情：进度环 + 投币打卡 + 贡献历史；§5.5⑪⑫、
/// §11.2 W13 主线）。
///
/// 数据流（§10.1 reactive 直读，零业务查询 §3.2）：
/// - 目标行 [savingsGoalDetailProvider]（§5.5⑪）；
/// - 进度求和 [savingsGoalProgressProvider]（§5.5⑫「进度=Σ贡献行」）；
/// - 贡献历史 [savingsGoalContributionsProvider]（append-only 时间线，
///   含远端墓碑行 → 渲染「已撤销」痕迹，§6.5）。
///
/// 达成判定（§5.5⑪ status）：Σ贡献 ≥ 目标金额 → 显示「标记达成」，由上层
/// 决策后经 updateDetails 写回（DAO 读路径零副作用，savings_dao.dart 口径）。
/// 归档（删除）= 软删墓碑（§5.1），写后同事务联动 day_summary.savings_progress
/// 重算（§5.6⑬）。
///
/// 账本联动（§12.2 开放问题 #9）：V1 先不联动（纯贡献行，不双重记账），
/// 待拍板——声明点见 plan_gateway.dart 存钱小节注释。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../plan_providers.dart';
import '../widgets/progress_ring.dart';
import '../widgets/savings_check_in_button.dart';
import 'savings_page.dart'
    show savingsMethodLabel, savingsSlotLabel, savingsStatusLabel;

/// 标记达成按钮测试锚点（`savings_complete_$goalId`）。
Key savingsCompleteKey(String goalId) =>
    ValueKey('savings_complete_$goalId');

/// 删除目标按钮测试锚点（`savings_delete_$goalId`）。
Key savingsDeleteKey(String goalId) => ValueKey('savings_delete_$goalId');

/// 贡献历史瓦片测试锚点（`savings_contrib_$id`）。
Key savingsContributionKey(String id) => ValueKey('savings_contrib_$id');

/// 目标详情页。
class SavingsGoalDetailPage extends ConsumerWidget {
  const SavingsGoalDetailPage({super.key, required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateway = ref.watch(planGatewayProvider);
    final goal = ref.watch(savingsGoalDetailProvider(goalId)).value;
    final contributed = ref.watch(savingsGoalProgressProvider(goalId)).value;
    final contributions =
        ref.watch(savingsGoalContributionsProvider(goalId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(goal?.name ?? '目标详情'),
        actions: [
          IconButton(
            key: savingsDeleteKey(goalId),
            tooltip: '删除目标',
            icon: const Icon(Icons.delete_outline),
            onPressed: goal == null
                ? null
                : () => _confirmDelete(context, ref, gateway, goal),
          ),
        ],
      ),
      body: goal == null || contributed == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProgressHeader(goal: goal, contributedMinor: contributed),
                  const SizedBox(height: 16),
                  SavingsCheckInButton(goal: goal, expanded: true),
                  const SizedBox(height: 12),
                  // 达成（§5.5⑪ status active→completed）：Σ贡献 ≥ 目标，
                  // 上层决策写回；仅进行中且已达标时出现。
                  if (goal.status == cdb.kSavingsGoalStatusActive &&
                      contributed >= goal.targetMinor)
                    OutlinedButton.icon(
                      key: savingsCompleteKey(goalId),
                      onPressed: () => gateway.markGoalCompleted(goalId),
                      icon: const Icon(Icons.emoji_events_outlined),
                      label: const Text('标记达成'),
                    ),
                  const SizedBox(height: 20),
                  _ContributionHistory(
                    method: goal.method,
                    contributions: contributions,
                  ),
                ],
              ),
            ),
    );
  }

  /// 归档确认（§5.1 删除行软删墓碑；§6.5 墓碑拒绝复活）。
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PlanGateway gateway,
    cdb.SavingsGoal goal,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除目标？'),
        content: const Text(
          '已投币贡献随目标一并隐藏（append-only 贡献行保留，可整库导出回溯）；'
          '删除后各设备同步一致。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await gateway.deleteSavingsGoal(goal.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

/// 进度区：大环（moneyIn）+ 目标信息（存钱法/状态/起始/截止）。
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.goal,
    required this.contributedMinor,
  });

  final cdb.SavingsGoal goal;
  final int contributedMinor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final double progress =
        goal.targetMinor <= 0 ? 0 : contributedMinor / goal.targetMinor;
    final double clamped = progress < 0
        ? 0
        : (progress > 1 ? 1 : progress);
    final percent = (clamped * 100).round();
    return Column(
      children: [
        SlimcaProgressRing(
          progress: clamped,
          size: 140,
          strokeWidth: 14,
          center: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SlimcaCountUp(
                value: percent,
                format: (p) => '$p%',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: tokens.moneyIn),
              ),
              Text(
                '已存 ${(contributedMinor / 100).toStringAsFixed(2)} / '
                '${(goal.targetMinor / 100).toStringAsFixed(2)} 元',
                style: TextStyle(
                    fontSize: 12, color: tokens.onSurfaceMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${savingsMethodLabel(goal.method)} · ${savingsStatusLabel(goal.status)}',
          style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
        ),
        const SizedBox(height: 4),
        Text(
          goal.deadline == null
              ? '起始 ${goal.startedOn}'
              : '起始 ${goal.startedOn} · 截止 ${goal.deadline}',
          style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
        ),
      ],
    );
  }
}

/// 贡献历史（§3.6 目标详情；append-only 时间线只增不改，§5.5⑫）。
class _ContributionHistory extends StatelessWidget {
  const _ContributionHistory({
    required this.method,
    required this.contributions,
  });

  /// 目标存钱法（§5.5⑪ method）：格子号 → 「第 N 天/周」文案。
  final String method;

  final List<cdb.SavingsContribution>? contributions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('贡献历史',
                style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted)),
            const SizedBox(height: 8),
            if (contributions == null)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (contributions!.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('还没有投币记录，今天开始',
                    style: TextStyle(
                        fontSize: 14, color: tokens.onSurfaceMuted)),
              )
            else
              for (final c in contributions!)
                _ContributionTile(c: c, method: method),
          ],
        ),
      ),
    );
  }
}

/// 单条贡献瓦片：金额 + 打卡日/格子号；墓碑行渲染「已撤销」痕迹（§6.5）。
class _ContributionTile extends StatelessWidget {
  const _ContributionTile({required this.c, required this.method});

  final cdb.SavingsContribution c;
  final String method;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final tombstoned = c.deletedAt != null;
    final slot = savingsSlotLabel(method, c.slot);
    final source = c.source == cdb.kSavingsSourceTodo ? ' · 待办打卡' : '';
    return ListTile(
      key: savingsContributionKey(c.id),
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        tombstoned ? Icons.undo : Icons.paid_outlined,
        size: 20,
        color: tombstoned ? tokens.onSurfaceMuted : tokens.moneyIn,
      ),
      title: Text(
        '${(c.amountMinor / 100).toStringAsFixed(2)} 元'
        '${tombstoned ? '（已撤销）' : ''}',
        style: TextStyle(
          fontSize: 14,
          color: tombstoned ? tokens.onSurfaceMuted : tokens.onSurface,
          decoration: tombstoned ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        '$slot · ${c.date}$source',
        style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
      ),
    );
  }
}
