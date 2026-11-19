/// 健身手动记录页（§3.5 健身手动记录 P0、§5.5⑦ fitness_sessions、
/// §11.1 W5-6 主线任务 1）。
///
/// 组成：归属日导航 → 表单卡（类型 ChoiceChip 内置 MET 表 / 强度档
/// SegmentedButton / 时长 / 体重 / 估算 count-up ±20% 口径标注 / 备注 /
/// 提交）→ 当日记录列表（按日查看、可删除）。
///
/// 数据流（§10.1）：表单状态机 [FitnessFormController]（AsyncNotifier）；
/// 列表/投影 reactive 直读 [fitnessSessionsProvider]（Drift watch 流）；
/// 提交经 [PlanGateway.submitFitnessSession] 同事务落三行（§5.5⑦）。
///
/// 口径标注（§3.5 误差口径标注 P0）：估算值恒带「±20%」注记，与 AI 置信度
/// 同一信任语言（§2.3 步骤 3）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fitness_form_controller.dart';
import '../fitness_met_table.dart';
import '../plan_gateway.dart';
import '../plan_models.dart';
import '../plan_providers.dart';
import '../widgets/plan_text_field.dart';
import 'fitness_history_page.dart';

/// 提交按钮测试锚点（widget 测试断言提交闭环）。
const Key fitnessSubmitKey = ValueKey('fitness_submit');

/// 时长输入测试锚点。
const Key fitnessDurationFieldKey = ValueKey('fitness_duration_field');

/// 体重输入测试锚点。
const Key fitnessWeightFieldKey = ValueKey('fitness_weight_field');

/// 估算值测试锚点（CountUp 终值文本断言用）。
const Key fitnessEstimateKey = ValueKey('fitness_estimate');

/// 会话删除按钮测试锚点（`fitness_delete_$sessionId`）。
Key fitnessDeleteKey(String sessionId) => ValueKey('fitness_delete_$sessionId');

/// 训练历史入口测试锚点（AppBar 文字按钮；自 FitnessPlanPage 迁入——
/// 历史唯一入口挂在记录页，消灭原「二级页 AppBar 图标暗门」）。
const Key fitnessHistoryKey = ValueKey('fitness_history');

/// 健身手动记录页。
class FitnessLogPage extends ConsumerWidget {
  const FitnessLogPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final form =
        ref.watch(fitnessFormControllerProvider(const FitnessSeed())).value;
    if (form == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('健身记录')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final notifier = ref.read(
        fitnessFormControllerProvider(const FitnessSeed()).notifier);
    final sessionsAsync = ref.watch(fitnessSessionsProvider(form.date));
    return Scaffold(
      appBar: AppBar(
        title: const Text('健身记录'),
        actions: [
          TextButton.icon(
            key: fitnessHistoryKey,
            onPressed: () => Navigator.of(context).push(
              SlimcaSharedAxisPageRoute<void>(
                  builder: (_) => const FitnessHistoryPage()),
            ),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('历史'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DateNavRow(
              date: form.date,
              onPrev: () => notifier.shiftDate(-1),
              onNext: () => notifier.shiftDate(1),
              onPicked: notifier.setDate,
            ),
            const SizedBox(height: 12),
            _FormCard(form: form, notifier: notifier),
            const SizedBox(height: 16),
            _SessionList(date: form.date, sessionsAsync: sessionsAsync),
          ],
        ),
      ),
    );
  }
}

/// 归属日导航（前后一日 + 日期选择器；§5.1 一切聚合按 date 分组）。
class _DateNavRow extends StatelessWidget {
  const _DateNavRow({
    required this.date,
    required this.onPrev,
    required this.onNext,
    required this.onPicked,
  });

  final String date;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final picked = DateTime.tryParse(date) ?? DateTime.now();
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: '前一日',
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final result = await showDatePicker(
                context: context,
                initialDate: picked,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (result != null) onPicked(result);
            },
            child: Text(
              date,
              style: TextStyle(fontSize: 15, color: tokens.onSurface),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: '后一日',
        ),
      ],
    );
  }
}

/// 表单卡（§3.5 交互规格全量：类型/强度/时长/体重/估算/备注/提交）。
class _FormCard extends StatelessWidget {
  const _FormCard({required this.form, required this.notifier});

  final FitnessFormState form;
  final FitnessFormController notifier;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final estimate = form.estimatedKcal;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('运动类型',
                style: TextStyle(
                    fontSize: 13, color: tokens.onSurfaceMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final activity in kFitnessActivities)
                  ChoiceChip(
                    key: ValueKey('fitness_type_${activity.id}'),
                    label: Text(activity.name),
                    selected: form.activity.id == activity.id,
                    onSelected: (_) => notifier.selectActivity(activity),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('强度档',
                style: TextStyle(
                    fontSize: 13, color: tokens.onSurfaceMuted)),
            const SizedBox(height: 8),
            SegmentedButton<FitnessIntensity>(
              segments: [
                for (final intensity in FitnessIntensity.values)
                  ButtonSegment(value: intensity, label: Text(intensity.label)),
              ],
              selected: {form.intensity},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  notifier.selectIntensity(selection.first);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('时长（分钟）',
                          style: TextStyle(
                              fontSize: 13, color: tokens.onSurfaceMuted)),
                      const SizedBox(height: 8),
                      PlanTextField(
                        key: fitnessDurationFieldKey,
                        initial: form.durationText,
                        hint: '如 30',
                        keyboardType: TextInputType.number,
                        onChanged: notifier.setDurationText,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('体重（kg）',
                          style: TextStyle(
                              fontSize: 13, color: tokens.onSurfaceMuted)),
                      const SizedBox(height: 8),
                      PlanTextField(
                        key: fitnessWeightFieldKey,
                        initial: form.weightText,
                        hint: '身体档案',
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        onChanged: notifier.setWeightText,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 估算区（§3.5：kcal = MET × 体重 × 时长；±20% 口径标注 P0）。
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('预计消耗',
                    style: TextStyle(
                        fontSize: 13, color: tokens.onSurfaceMuted)),
                const SizedBox(width: 8),
                SlimcaCountUp(
                  key: fitnessEstimateKey,
                  value: estimate ?? 0,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: tokens.kcalOut),
                ),
                const SizedBox(width: 4),
                Text('kcal',
                    style: TextStyle(
                        fontSize: 13, color: tokens.onSurfaceMuted)),
                const Spacer(),
                Text('MET 估算 ±20%',
                    style: TextStyle(
                        fontSize: 12, color: tokens.onSurfaceMuted)),
              ],
            ),
            const SizedBox(height: 12),
            PlanTextField(
              initial: form.note,
              hint: '备注（可选）',
              maxLines: 2,
              onChanged: notifier.setNote,
            ),
            if (form.errorText != null) ...[
              const SizedBox(height: 8),
              Text(form.errorText!,
                  style: TextStyle(fontSize: 13, color: tokens.danger)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: fitnessSubmitKey,
              onPressed: form.canSubmit ? () => notifier.submit() : null,
              child: Text(form.submitting ? '记录中…' : '记录'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 当日会话列表（§3.5「列表可按日查看、可删除」；删除=软删墓碑 §5.1，
/// kcal_out 投影即时回落 §5.6）。
class _SessionList extends StatelessWidget {
  const _SessionList({required this.date, required this.sessionsAsync});

  final String date;
  final AsyncValue<List<cdb.FitnessSession>> sessionsAsync;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定：.value + null 骨架帧（流首帧 loading）。
    final sessions = sessionsAsync.value;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当日记录（$date）',
                style: TextStyle(
                    fontSize: 13, color: tokens.onSurfaceMuted)),
            if (sessions == null)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('当日暂无记录',
                    style: TextStyle(
                        fontSize: 14, color: tokens.onSurfaceMuted)),
              )
            else
              Column(
                children: [
                  for (final session in sessions) _SessionTile(session: session),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 单条会话瓦片。
class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session});

  final cdb.FitnessSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final FitnessType type = _typeFromWire(session.type);
    final minutes = session.durationS ~/ 60;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.fitness_center, color: tokens.kcalOut),
      title: Text('${type.label} · $minutes 分钟',
          style: TextStyle(fontSize: 15, color: tokens.onSurface)),
      subtitle: Text(
        '消耗 ${session.kcalBurn} kcal（MET 估算 ±20%）',
        style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
      ),
      trailing: IconButton(
        key: fitnessDeleteKey(session.id),
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除',
        onPressed: () async {
          // 删除=软删墓碑（§5.1）：会话行 + 关联事件同事务打墓碑，
          // 归属日投影即时回落（kcal_out 扣除，§5.6）。
          final gateway = ref.read(planGatewayProvider);
          await gateway.deleteFitnessSession(session.id);
        },
      ),
    );
  }
}

/// wire → 枚举解析（坏值防御回退 other，§7.4 健壮性）。
/// 独立函数避免 final 在 try/catch 双赋值被 Dart 流分析误判。
FitnessType _typeFromWire(String wire) {
  try {
    return FitnessType.fromWire(wire);
  } on ArgumentError {
    return FitnessType.other;
  }
}
