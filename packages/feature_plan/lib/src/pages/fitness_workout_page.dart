/// 开练页（§11.2 W14 主线任务 2/3「开练流 + 组明细 + 汇总联动」、§4.3
/// /plan/fitness/:id 路由、§3.5「组间计时器」）。
///
/// 组成：会话头卡（计划名/开始时刻/进度）→ 组间计时器面板（rest 态直驱）
/// → 当前目标卡（模板目标预填次数/重量、可改 →「完成一组」落 exercise_sets
/// 行）→ 完成训练 CTA（汇总时长/MET 消耗 + entry/burn 行联动，复用 W5-6
/// 链路）→ 已落组明细列表（reactive 直读）。
///
/// 退出口径（§11.2 W14）：PopScope 拦截返回手势——
/// - 已汇总（finished）：直接返回；
/// - 无组明细：空会话不入历史（软删墓碑清理，§5.1）；
/// - 已有组明细未汇总：按已练时长自动汇总入账（真实训练照常进净热量，
///   §3.5「消耗进运动条与净热量」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fitness_plan_models.dart';
import '../fitness_workout_controller.dart';
import '../plan_gateway.dart';
import '../plan_providers.dart';
import '../widgets/plan_text_field.dart';
import '../widgets/rest_timer.dart';

/// 完成一组按钮测试锚点。
const Key fitnessWorkoutCompleteKey = ValueKey('fitness_workout_complete');

/// 完成训练按钮测试锚点。
const Key fitnessWorkoutFinishKey = ValueKey('fitness_workout_finish');

/// 实际次数输入测试锚点。
const Key fitnessWorkoutRepsFieldKey = ValueKey('fitness_workout_reps_field');

/// 实际重量输入测试锚点。
const Key fitnessWorkoutWeightFieldKey =
    ValueKey('fitness_workout_weight_field');

/// 开练页（§4.3 /plan/fitness/:id 路由目标；开练入口已建会话行）。
class FitnessWorkoutPage extends ConsumerStatefulWidget {
  const FitnessWorkoutPage({super.key, required this.sessionId});

  /// 会话行 id（fitness_sessions.id，§5.5⑦）。
  final String sessionId;

  @override
  ConsumerState<FitnessWorkoutPage> createState() =>
      _FitnessWorkoutPageState();
}

class _FitnessWorkoutPageState extends ConsumerState<FitnessWorkoutPage> {
  late final FitnessWorkoutSeed _seed =
      FitnessWorkoutSeed(sessionId: widget.sessionId);

  /// 实际次数/重量输入中态（空=沿用模板目标，PlanTextField initial 预填）。
  String _repsText = '';
  String _weightText = '';

  /// 实际次数：输入优先，空/非法回退模板目标（§11.2 W14「目标次数预填可改」）。
  int _effectiveReps(PlanExercise exercise) =>
      int.tryParse(_repsText.trim()) ?? exercise.targetReps;

  /// 实际重量 ×10 定点：输入优先，空/非法回退模板目标（§5.5⑨ 定点口径）。
  int _effectiveWeightKgX10(PlanExercise exercise) =>
      (double.tryParse(_weightText.trim()) ?? exercise.targetWeightKg * 10)
          .round();

  /// 完成一组（§11.2 W14 任务 3）：落组明细行 → 有下一组且模板 rest_s>0
  /// 时启动组间计时器（rest 秒数从模板读，§3.5 组间计时器）。
  Future<void> _completeSet() async {
    final state = ref.read(fitnessWorkoutControllerProvider(_seed)).value;
    if (state == null) return;
    final target = state.currentTarget;
    if (target == null) return;
    final row = await ref
        .read(fitnessWorkoutControllerProvider(_seed).notifier)
        .completeCurrentSet(
          reps: _effectiveReps(target.exercise),
          weightKgX10: _effectiveWeightKgX10(target.exercise),
        );
    if (row == null || !mounted) return;
    // 组间休息：休息秒数取自「刚完成的动作」的模板 rest_s（§5.5⑧）；无下一组
    // 不计时（训练收尾直接见完成 CTA）。
    final next =
        ref.read(fitnessWorkoutControllerProvider(_seed)).value?.currentTarget;
    if (next != null && target.exercise.restS > 0) {
      ref.read(restTimerProvider.notifier).start(target.exercise.restS);
    }
    // 输入中态复位 → 下一组字段由模板目标重新预填（initial 变化自动回写）。
    setState(() {
      _repsText = '';
      _weightText = '';
    });
  }

  /// 完成训练（§11.2 W14 任务 3 汇总）：成功即出栈回计划页（历史页可看）。
  Future<void> _finishTapped() async {
    final session = await ref
        .read(fitnessWorkoutControllerProvider(_seed).notifier)
        .finish();
    if (session != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 退出守卫（PopScope 返回手势）：见文件头退出口径。
  Future<void> _exit() async {
    final state = ref.read(fitnessWorkoutControllerProvider(_seed)).value;
    final gateway = ref.read(planGatewayProvider);
    if (state == null || state.completedCount == 0) {
      // 零组明细：空会话不入历史（软删墓碑，§5.1；幂等 no-op 安全）。
      await gateway.deleteFitnessSession(widget.sessionId);
    } else if (!state.finished) {
      // 已有真实组明细未汇总：自动汇总入账（§3.5 消耗进净热量）。
      await ref
          .read(fitnessWorkoutControllerProvider(_seed).notifier)
          .finish();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final stateAsync = ref.watch(fitnessWorkoutControllerProvider(_seed));
    final state = stateAsync.value;
    return PopScope(
      // 返回手势/系统返回统一走 _exit 退出守卫（文件头口径）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('训练中')),
        body: stateAsync.hasError
            ? Center(
                child: Text(
                  '会话装载失败（${stateAsync.error}）',
                  style:
                      TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
                ),
              )
            : state == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeaderCard(state: state),
                        const RestTimerPanel(),
                        _TargetCard(
                          state: state,
                          repsText: _repsText,
                          weightText: _weightText,
                          // 输入中态随输入重建（initial 与内显文本保持一致，
                          // 完成后复位预填不残留旧输入，§11.2 W14）。
                          onRepsChanged: (v) => setState(() => _repsText = v),
                          onWeightChanged: (v) =>
                              setState(() => _weightText = v),
                          onComplete: _completeSet,
                          onFinish: _finishTapped,
                        ),
                        const SizedBox(height: 16),
                        _SetsList(sessionId: widget.sessionId),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// 会话头卡：计划名 + 开始时刻 + 组进度（count-up，§9.3#4）。
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.state});

  final FitnessWorkoutState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final startAt = state.session.startAt;
    final hhmm = startAt == null
        ? '—'
        : _hhmm(DateTime.fromMillisecondsSinceEpoch(startAt));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.fitness_center, color: tokens.kcalOut),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.plan.name,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.onSurface)),
                    const SizedBox(height: 2),
                    Text('$hhmm 开始 · ${state.plan.startDate}',
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      SlimcaCountUp(
                        value: state.completedCount,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: tokens.kcalOut),
                      ),
                      Text(
                        ' / ${state.totalSets} 组',
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前目标卡（§11.2 W14）：模板目标预填次数/重量、可改 →「完成一组」；
/// 全部完成/提前结束 →「完成训练」汇总 CTA。
class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.state,
    required this.repsText,
    required this.weightText,
    required this.onRepsChanged,
    required this.onWeightChanged,
    required this.onComplete,
    required this.onFinish,
  });

  final FitnessWorkoutState state;
  final String repsText;
  final String weightText;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<String> onWeightChanged;
  final VoidCallback onComplete;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final target = state.currentTarget;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (target != null) ...[
              Text('当前动作',
                  style: TextStyle(
                      fontSize: 13, color: tokens.onSurfaceMuted)),
              const SizedBox(height: 4),
              Text(target.exercise.name,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: tokens.onSurface)),
              const SizedBox(height: 4),
              Text(
                '第 ${target.setNo}/${target.exercise.sets} 组 · '
                '目标 ${target.exercise.targetReps} 次 × '
                '${_weightLabel(target.exercise)} · '
                '组间休息 ${target.exercise.restS} 秒',
                style: TextStyle(
                    fontSize: 13, color: tokens.onSurfaceMuted),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('实际次数',
                            style: TextStyle(
                                fontSize: 13,
                                color: tokens.onSurfaceMuted)),
                        const SizedBox(height: 8),
                        PlanTextField(
                          key: fitnessWorkoutRepsFieldKey,
                          // 预填模板目标（空输入沿用目标，§11.2 W14）。
                          initial: repsText.isEmpty
                              ? '${target.exercise.targetReps}'
                              : repsText,
                          hint: '${target.exercise.targetReps}',
                          keyboardType: TextInputType.number,
                          onChanged: onRepsChanged,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('实际重量（kg）',
                            style: TextStyle(
                                fontSize: 13,
                                color: tokens.onSurfaceMuted)),
                        const SizedBox(height: 8),
                        PlanTextField(
                          key: fitnessWorkoutWeightFieldKey,
                          initial: weightText.isEmpty
                              ? _weightLabel(target.exercise)
                              : weightText,
                          hint: _weightLabel(target.exercise),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          onChanged: onWeightChanged,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: fitnessWorkoutCompleteKey,
                onPressed: onComplete,
                child: Text(state.finishing ? '汇总中…' : '完成一组'),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: tokens.success),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('全部组完成',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.onSurface)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('训练结束将按真实时长做 MET 估算入账（±20% 口径，§3.5）',
                  style: TextStyle(
                      fontSize: 13, color: tokens.onSurfaceMuted)),
            ],
            if (state.errorText != null) ...[
              const SizedBox(height: 8),
              Text(state.errorText!,
                  style: TextStyle(fontSize: 13, color: tokens.danger)),
            ],
            const SizedBox(height: 12),
            // 完成训练 CTA：全部完成=主 CTA；未完成=提前结束（自动汇总已练组，
            // §11.2 W14 退出口径）。0 组不可汇总（空会话由退出清理，§5.1）。
            FilledButton(
              key: fitnessWorkoutFinishKey,
              onPressed: (state.completedCount > 0 && !state.finishing)
                  ? onFinish
                  : null,
              child: Text(
                state.finishing
                    ? '汇总中…'
                    : state.allCompleted
                        ? '完成训练'
                        : '提前结束（汇总已练 ${state.completedCount} 组）',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 目标重量展示（×10 定点还原；自重 0 显示「自重」）。
  String _weightLabel(PlanExercise exercise) =>
      exercise.targetWeightKgX10 == 0
          ? '自重'
          : exercise.targetWeightKgX10 % 10 == 0
              ? '${exercise.targetWeightKgX10 ~/ 10}'
              : exercise.targetWeightKg.toStringAsFixed(1);
}

/// 已落组明细列表（§5.5⑨；reactive 直读，§10.1）。
class _SetsList extends ConsumerWidget {
  const _SetsList({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final setsAsync = ref.watch(exerciseSetsBySessionProvider(sessionId));
    final sets = setsAsync.value;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('组明细（${sets?.length ?? '…'}）',
                style: TextStyle(
                    fontSize: 13, color: tokens.onSurfaceMuted)),
            if (sets == null)
              const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (sets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('暂无组明细：完成一组即落一行（§5.5⑨）',
                    style: TextStyle(
                        fontSize: 14, color: tokens.onSurfaceMuted)),
              )
            else
              Column(
                children: [
                  for (final set in sets)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.check,
                          size: 18, color: tokens.kcalOut),
                      title: Text(
                        '#${set.sort} ${set.exerciseRef} · '
                        '${set.reps}次 × ${_kgLabel(set.weightKgX10)}kg',
                        style: TextStyle(
                            fontSize: 14, color: tokens.onSurface),
                      ),
                      subtitle: Text(
                        '休 ${set.restS ?? 0}s · ${_hhmm(DateTime.fromMillisecondsSinceEpoch(set.doneAt))} 完成',
                        style: TextStyle(
                            fontSize: 12, color: tokens.onSurfaceMuted),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _kgLabel(int weightKgX10) => weightKgX10 % 10 == 0
      ? '${weightKgX10 ~/ 10}'
      : (weightKgX10 / 10).toStringAsFixed(1);
}

/// HH:mm 展示（本地时刻，组明细/开始时刻用）。
String _hhmm(DateTime local) =>
    '${local.hour.toString().padLeft(2, '0')}:'
    '${local.minute.toString().padLeft(2, '0')}';
