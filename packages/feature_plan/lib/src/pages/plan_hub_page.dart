/// 计划域组合页（§4.2「计划 Tab：待办/健身/存钱三卡」+ 健身计划，§3.5/
/// §3.6）。
///
/// 宿主接线（§10.4）：apps/mobile 的 PlanPage（计划 Tab 根）可整页委托给
/// [PlanHubPage]，或按卡拆嵌（各子页均可独立路由）。卡片摘要直读
/// day_summary 投影（§5.6⑬ 快照直出）与各 reactive 流。
///
/// 动效（§9.2/§9.3）：卡片入场级联 SlimcaStaggerItem（#1）、页面跳转共享轴
/// SlimcaSharedAxisPageRoute（#2，280ms）——只引用 ui_kit 既有 token/转场。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'fitness_log_page.dart';
import 'fitness_plan_page.dart';
import 'savings_page.dart';
import 'todo_page.dart';
import '../plan_providers.dart';

/// 计划域组合页（计划 Tab 壳的默认实现）。
class PlanHubPage extends ConsumerWidget {
  const PlanHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    // 今日摘要：投影直读（§5.6⑬ 冷启动首帧零业务查询）。
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 兜底。
    final today = dom.formatCalendarDay(DateTime.now());
    final summary = ref.watch(planDaySummaryProvider(today)).value;
    final goals = ref.watch(savingsGoalsProvider).value;
    final plans = ref.watch(fitnessPlansProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('计划')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SlimcaStaggerItem(
            index: 0,
            child: _HubCard(
              icon: Icons.check_circle_outline,
              accent: tokens.success,
              title: '今日待办',
              subtitle: summary == null
                  ? '安排今天的事（§3.6）'
                  : '已完成 ${summary.todoDone}/${summary.todoTotal}',
              onTap: () => _push(context, const TodoPage()),
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 1,
            child: _HubCard(
              icon: Icons.fitness_center,
              accent: tokens.kcalOut,
              title: '健身手动记录',
              subtitle: summary == null
                  ? '时长 × 类型 × 强度，MET 估算消耗（§3.5）'
                  : '今日消耗 ${summary.kcalOut} kcal',
              onTap: () => _push(context, const FitnessLogPage()),
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 2,
            child: _HubCard(
              icon: Icons.savings_outlined,
              accent: tokens.moneyIn,
              title: '存钱目标',
              subtitle: (goals == null || goals.isEmpty)
                  ? '365/52 周/自定义 + 投币打卡（§3.6）'
                  : '${goals.length} 个目标进行中',
              onTap: () => _push(context, const SavingsPage()),
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 3,
            child: _HubCard(
              icon: Icons.calendar_month_outlined,
              accent: tokens.kcalIn,
              title: '健身计划',
              subtitle: (plans == null || plans.isEmpty)
                  ? 'W14 上线（§3.5 P1）'
                  : '${plans.length} 个计划',
              onTap: () => _push(context, const FitnessPlanPage()),
            ),
          ),
        ],
      ),
    );
  }

  /// 页面跳转：共享轴 X 轴（§9.3#2 平级详情，280ms 预算）。
  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      SlimcaSharedAxisPageRoute<void>(builder: (_) => page),
    );
  }
}

/// 计划卡（样式引用 §8.2 语义 token；几何常量与仪表盘卡同规格）。
class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.onSurface)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.onSurfaceMuted),
            ],
          ),
        ),
      ),
    );
  }
}
