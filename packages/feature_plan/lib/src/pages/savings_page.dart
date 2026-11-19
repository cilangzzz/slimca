/// 存钱目标页（§3.6 存钱目标 P1 留存钩子、§5.5⑪⑫、§11.2 W13 主线
/// 「存钱目标（留存钩子）：365/52 周/自定义+投币打卡；进度=贡献行求和」）。
///
/// 组成：目标列表（进度环 + 打卡状态 + 投币 CTA，点卡进详情）+ 新建目标
/// 弹簧抽屉（365 天挑战/52 周挑战/自定义）。进度环为 [SlimcaProgressRing]
/// （moneyIn 语义 token，§8.2「暖橘=金额」）；目标金额/已存金额走
/// SlimcaCountUp（§9.3#4，投币后数字递增即打卡动效落点之一）。
///
/// 数据流（§10.1）：[savingsGoalsProvider] reactive 联查（目标 × Σ贡献，
/// 贡献落行即刷新）；打卡经 [PlanGateway.contributeToGoal]（append-only +
/// (goal_id, date, source) 幂等防重复，§5.5⑫），写后同事务重算
/// day_summary.savings_progress（§5.6⑬ W13 实装）。
///
/// 账本联动（§12.2 开放问题 #9）：V1 先不联动——贡献行是纯 append-only
/// 记录，不生成 entries/entry_lines（不双重记账）；是否联动待观察需求后
/// 拍板（注释声明点在 plan_gateway.dart 存钱小节）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_models.dart';
import '../plan_providers.dart';
import '../widgets/progress_ring.dart';
import '../widgets/savings_check_in_button.dart';
import '../widgets/savings_goal_editor_sheet.dart';
import 'savings_goal_detail_page.dart';

/// 新建目标按钮测试锚点。
const Key savingsCreateKey = ValueKey('savings_create');

/// 空态新建按钮测试锚点。
const Key savingsEmptyCreateKey = ValueKey('savings_empty_create');

/// 目标卡测试锚点（`savings_goal_card_$goalId`）。
Key savingsGoalCardKey(String goalId) => ValueKey('savings_goal_card_$goalId');

/// §5.5⑪ method wire → 展示标签（§3.6 三种存钱法）。
String savingsMethodLabel(String method) => switch (method) {
      cdb.kSavingsMethodDaily365 => '365 天挑战',
      cdb.kSavingsMethodWeek52 => '52 周挑战',
      cdb.kSavingsMethodCustom => '自定义',
      _ => method, // 未知枚举防御直显（§7.4）
    };

/// §5.5⑪ status wire → 展示标签。
String savingsStatusLabel(String status) => switch (status) {
      cdb.kSavingsGoalStatusActive => '进行中',
      cdb.kSavingsGoalStatusCompleted => '已达标',
      cdb.kSavingsGoalStatusAbandoned => '已放弃',
      _ => status,
    };

/// 存钱目标页。
class SavingsPage extends ConsumerWidget {
  const SavingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final goals = ref.watch(savingsGoalsProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('存钱目标'),
        actions: [
          IconButton(
            key: savingsCreateKey,
            tooltip: '新建目标',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: goals == null
          ? const Center(child: CircularProgressIndicator())
          : goals.isEmpty
              ? _EmptyState(onCreate: () => _openEditor(context))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: goals.length,
                  itemBuilder: (context, index) {
                    final view = goals[index];
                    return SlimcaStaggerItem(
                      index: index,
                      child: _GoalCard(view: view),
                    );
                  },
                ),
    );
  }

  /// 新建目标弹簧抽屉（§9.3#3 springSnappy，≤280ms 可输入口径）。
  void _openEditor(BuildContext context) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => const SavingsGoalEditorSheet(),
    );
  }
}

/// 空态引导（§3.6 P1 钩子上线文案：三种存钱法 + 投币打卡心智）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.savings_outlined, size: 48, color: tokens.moneyIn),
            const SizedBox(height: 12),
            Text(
              '开始你的第一个存钱目标',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '365 天挑战 / 52 周挑战 / 自定义目标，每天投币打卡；'
              '进度 = Σ贡献行，append-only 免同步冲突',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: savingsEmptyCreateKey,
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('新建目标'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 目标卡：进度环（moneyIn）+ 名称/存钱法/状态 + 金额 count-up + 投币按钮。
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.view});

  final SavingsGoalView view;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final goal = view.goal;
    final percent = (view.progress * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: savingsGoalCardKey(goal.id),
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(
            SlimcaSharedAxisPageRoute<void>(
              builder: (_) => SavingsGoalDetailPage(goalId: goal.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SlimcaProgressRing(
                  progress: view.progress,
                  size: 64,
                  strokeWidth: 7,
                  sweepEntrance: false,
                  center: Text(
                    '$percent%',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: tokens.moneyIn),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: tokens.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                        '${savingsMethodLabel(goal.method)} · '
                        '${savingsStatusLabel(goal.status)}',
                        style: TextStyle(
                            fontSize: 12, color: tokens.onSurfaceMuted),
                      ),
                      const SizedBox(height: 4),
                      SlimcaCountUp(
                        value: view.contributedMinor,
                        format: (minor) =>
                            '${(minor / 100).toStringAsFixed(2)} / '
                            '${view.targetYuan} 元',
                        style: TextStyle(
                            fontSize: 13, color: tokens.moneyIn),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SavingsCheckInButton(goal: goal),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 贡献格子标签（365/52 周存钱法格子号 → 「第 N 天/周」，§5.5⑫ slot）。
String savingsSlotLabel(String method, int? slot) {
  if (slot == null) return '每日存入';
  return switch (method) {
    cdb.kSavingsMethodDaily365 => '第$slot天',
    cdb.kSavingsMethodWeek52 => '第$slot周',
    _ => '格子$slot',
  };
}
