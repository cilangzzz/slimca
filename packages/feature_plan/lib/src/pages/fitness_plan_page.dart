/// 健身计划页（§3.5 健身计划 P1 留存钩子、§5.5⑧⑨、§11.2 W14 主线任务 1/2）。
///
/// 组成：模板列表（周排期条高亮 + 今日排期态 + 动作摘要）→ 一键开练
/// （startWorkoutSession → [FitnessWorkoutPage]）/ 编辑/删除；新建/编辑走
/// 弹簧抽屉 [FitnessPlanEditorSheet]；AppBar 历史入口进 [FitnessHistoryPage]。
///
/// 排期口径取舍（§3.5「计划日自动生成会话」）：W14 收敛为「排期日一键开练」
/// ——不预生成空会话行（未训练日不留垃圾行），与 W13 重复待办「查询时展开、
/// 不预生成行」同一取向；计划会话 type=template_instance、source=plan
/// （§5.5⑦），entry/burn 联动与手动记录共用同一落库链路（§5.5⑦/§11.2 W14）。
///
/// 计划日历高亮（§11.2 W14 验收）：周排期条按 weekday_mask 高亮排期日
/// （kcalOut 底）并标注今日（描边+「今」角标）——模板即排期日历的周视图。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fitness_plan_models.dart';
import '../plan_gateway.dart';
import '../plan_providers.dart';
import '../widgets/fitness_plan_editor_sheet.dart';
import 'fitness_history_page.dart';
import 'fitness_workout_page.dart';

/// 新建计划按钮测试锚点（AppBar）。
const Key fitnessPlanCreateKey = ValueKey('fitness_plan_create');

/// 空态新建按钮测试锚点。
const Key fitnessPlanEmptyCreateKey = ValueKey('fitness_plan_empty_create');

/// 训练历史入口测试锚点（AppBar）。
const Key fitnessHistoryKey = ValueKey('fitness_history');

/// 开练按钮测试锚点（`fitness_plan_start_$planId`）。
Key fitnessPlanStartKey(String planId) =>
    ValueKey('fitness_plan_start_$planId');

/// 编辑按钮测试锚点（`fitness_plan_edit_$planId`）。
Key fitnessPlanEditKey(String planId) => ValueKey('fitness_plan_edit_$planId');

/// 删除按钮测试锚点（`fitness_plan_delete_$planId`）。
Key fitnessPlanDeleteKey(String planId) =>
    ValueKey('fitness_plan_delete_$planId');

/// 周排期条单日 chip 测试锚点（`fitness_plan_day_${planId}_$bitIndex`；
/// 测试读 Container.decoration 断言排期日高亮，§11.2 W14 日历高亮验收）。
Key fitnessPlanDayChipKey(String planId, int bitIndex) =>
    ValueKey('fitness_plan_day_${planId}_$bitIndex');

/// 健身计划页。
class FitnessPlanPage extends ConsumerWidget {
  const FitnessPlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final plans = ref.watch(fitnessPlansProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('健身计划'),
        actions: [
          IconButton(
            key: fitnessHistoryKey,
            tooltip: '训练历史',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).push(
              SlimcaSharedAxisPageRoute<void>(
                  builder: (_) => const FitnessHistoryPage()),
            ),
          ),
          IconButton(
            key: fitnessPlanCreateKey,
            tooltip: '新建计划',
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
      body: plans == null
          ? const Center(child: CircularProgressIndicator())
          : plans.isEmpty
              ? _EmptyState(onCreate: () => _openEditor(context))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: plans.length,
                  itemBuilder: (context, index) {
                    final plan = plans[index];
                    return SlimcaStaggerItem(
                      index: index,
                      child: _PlanCard(plan: plan),
                    );
                  },
                ),
    );
  }

  /// 新建/编辑弹簧抽屉（§9.3#3 springSnappy，≤280ms 可输入口径）。
  void _openEditor(BuildContext context, {cdb.FitnessPlan? plan}) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => FitnessPlanEditorSheet(plan: plan),
    );
  }
}

/// 空态引导（§3.5 P1 钩子上线文案：模板/排期/组间计时/组明细心智）。
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
            Icon(Icons.fitness_center, size: 48, color: tokens.kcalOut),
            const SizedBox(height: 12),
            Text(
              '开始你的第一个健身计划',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '训练模板（动作/组数/目标次数/目标重量/组间休息秒）+ 按周排期'
              '（§5.5⑧）；排期日一键开练，每完成一组落 exercise_sets，训练结束'
              '汇总 fitness_sessions 并联动消耗行（§5.5⑦⑨）',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: fitnessPlanEmptyCreateKey,
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('新建计划'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 计划卡：名称/起始日/动作摘要 + 周排期条（高亮排期日与今日）+ 开练/编辑/删除。
class _PlanCard extends ConsumerWidget {
  const _PlanCard({required this.plan});

  final cdb.FitnessPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final template = FitnessPlanTemplate.decode(plan.exercises);
    final today = DateTime.now();
    final scheduledToday = planMaskCovers(plan.weekdayMask, today);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () =>
              _openEditor(context, ref, plan: plan), // 点卡进编辑抽屉
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        plan.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.onSurface),
                      ),
                    ),
                    if (!plan.active)
                      Text('已停用',
                          style: TextStyle(
                              fontSize: 12, color: tokens.onSurfaceMuted)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '起始 ${plan.startDate} · ${template.exercises.length} 个动作'
                  ' · 共 ${template.totalSets} 组'
                  '${planMaskSummary(plan.weekdayMask) == null ? '' : ' · ${planMaskSummary(plan.weekdayMask)}'}',
                  style: TextStyle(
                      fontSize: 13, color: tokens.onSurfaceMuted),
                ),
                const SizedBox(height: 12),
                _ScheduleStrip(plan: plan),
                const SizedBox(height: 8),
                Text(
                  scheduledToday ? '今日已排 · 可开练' : '今日无排期',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheduledToday
                        ? tokens.kcalOut
                        : tokens.onSurfaceMuted,
                    fontWeight: scheduledToday ? FontWeight.w600 : null,
                  ),
                ),
                const SizedBox(height: 10),
                // 动作摘要（前 3 个动作一行式，§5.5⑧ exercises JSON 解析）。
                for (final exercise
                    in template.exercises.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      exercise.summaryLine,
                      style: TextStyle(
                          fontSize: 13, color: tokens.onSurface),
                    ),
                  ),
                if (template.exercises.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      '…共 ${template.exercises.length} 个动作',
                      style: TextStyle(
                          fontSize: 13, color: tokens.onSurfaceMuted),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton.icon(
                      key: fitnessPlanStartKey(plan.id),
                      onPressed: template.isStartable
                          ? () => _startWorkout(context, ref)
                          : null,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('开练'),
                    ),
                    const Spacer(),
                    IconButton(
                      key: fitnessPlanEditKey(plan.id),
                      tooltip: '编辑计划',
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => _openEditor(context, ref, plan: plan),
                    ),
                    IconButton(
                      key: fitnessPlanDeleteKey(plan.id),
                      tooltip: '删除计划',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () =>
                          ref.read(planGatewayProvider).deleteFitnessPlan(plan.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEditor(
      BuildContext context, WidgetRef ref, {required cdb.FitnessPlan plan}) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => FitnessPlanEditorSheet(plan: plan),
    );
  }

  /// 一键开练（§11.2 W14 任务 2）：先建会话行（§5.5⑦ type=template_instance、
  /// source=plan、start_at=开练时刻，§6.2 outbox 同事务），再进开练页。
  Future<void> _startWorkout(BuildContext context, WidgetRef ref) async {
    final gateway = ref.read(planGatewayProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final session = await gateway.startWorkoutSession(
        planId: plan.id,
        date: dom.formatCalendarDay(DateTime.now()),
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        // §4.3 /plan/fitness/:id 共享轴（§9.3#2 平级详情）。
        SlimcaSharedAxisPageRoute<void>(
          builder: (_) => FitnessWorkoutPage(sessionId: session.id),
        ),
      );
    } catch (_) {
      // 开练失败不打断计划页（§3.7 本地优先：错误仅提示）。
      messenger.showSnackBar(
        const SnackBar(content: Text('开练失败，请重试')),
      );
    }
  }
}

/// 周排期条（计划日历高亮，§11.2 W14）：bit0=周一…bit6=周日（§5.5⑧）——
/// 排期日 kcalOut 高亮；今日描边 + 「今」角标（无论是否排期）。
class _ScheduleStrip extends StatelessWidget {
  const _ScheduleStrip({required this.plan});

  final cdb.FitnessPlan plan;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final today = DateTime.now();
    final todayBit = planWeekdayBitOf(today);
    return Row(
      children: [
        for (var i = 0; i < kPlanWeekdayLabels.length; i++)
          Expanded(
            child: Container(
              key: fitnessPlanDayChipKey(plan.id, i),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                // 排期日高亮（kcalOut 底；语义 token，§8.2 双主色锚定）。
                color: (plan.weekdayMask >> i) & 1 == 1
                    ? tokens.kcalOut
                    : tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: (todayBit >> i) & 1 == 1
                    ? Border.all(color: tokens.kcalOut, width: 2)
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    kPlanWeekdayLabels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          (plan.weekdayMask >> i) & 1 == 1 ? FontWeight.w600 : null,
                      color: (plan.weekdayMask >> i) & 1 == 1
                          ? tokens.onPrimary
                          : tokens.onSurfaceMuted,
                    ),
                  ),
                  if ((todayBit >> i) & 1 == 1)
                    Text(
                      '今',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9,
                        color: (plan.weekdayMask >> i) & 1 == 1
                            ? tokens.onPrimary
                            : tokens.kcalOut,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
