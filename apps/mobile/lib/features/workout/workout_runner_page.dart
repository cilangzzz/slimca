/// 训练中页（§11.2 W14「组间计时器（锁屏可跑）」骨架的执行面、§3.5 健身
/// 计划 P1、§4.3 /plan/workout）。
///
/// 数据源：workoutSessionProvider（W14 任务 4 同源 Riverpod provider）——
/// 排期卡「开始训练」置态后推入本页；本页只渲染与推进（完成一组/跳过休息/
/// 结束并保存/放弃），不持有任何训练状态（切页不丢进行中训练）。
///
/// 计时纪律（W14 任务 5「禁真实计时器，注入时钟」）：剩余休息秒由控制器以
/// 绝对时刻+注入时钟判定；本页 Timer.periodic(1s) 只做两件事——①调
/// syncRest 探询到点（业务推进）；②展示秒值变化时 setState（渲染节奏）。
/// 测试经注入时钟+tester.pump 推进，无真实计时器断言。
///
/// 副作用（W14 任务 2/3）：完成一组→组间休息常驻通知（原生倒计时）+
/// set_logged；结束并保存→落库（§6.2）+ workout_completed + 常亮 off +
/// 通知 cancel；放弃→仅释放副作用（零落库零漏斗）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../data/workout_models.dart' show WorkoutExercisePlan;
import 'workout_session_controller.dart' show WorkoutSessionState, workoutSessionProvider;

/// 「完成一组」按钮测试锚点。
const Key workoutLogSetKey = ValueKey('workout_log_set');

/// 「跳过休息」按钮测试锚点。
const Key workoutSkipRestKey = ValueKey('workout_skip_rest');

/// 「结束并保存」按钮测试锚点。
const Key workoutEndSaveKey = ValueKey('workout_end_save');

/// 「放弃训练」按钮测试锚点。
const Key workoutDiscardKey = ValueKey('workout_discard');

/// 休息剩余秒测试锚点（训练页大数字）。
const Key workoutRestRemainingKey = ValueKey('workout_rest_remaining');

/// 训练中页。
class WorkoutRunnerPage extends ConsumerStatefulWidget {
  const WorkoutRunnerPage({super.key});

  @override
  ConsumerState<WorkoutRunnerPage> createState() => _WorkoutRunnerPageState();
}

class _WorkoutRunnerPageState extends ConsumerState<WorkoutRunnerPage> {
  Timer? _ticker;
  int _lastRestSeconds = -1;

  @override
  void initState() {
    super.initState();
    // 每秒探询：到点判定经控制器（注入时钟），秒值变化才 setState（§9.5
    // 渲染节奏与业务语义解耦；测试注入静态时钟时本计时器不触发重绘）。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final nowMs = ref.read(workoutClockProvider)().millisecondsSinceEpoch;
    ref.read(workoutSessionProvider.notifier).syncRest(nowMs: nowMs);
    final session = ref.read(workoutSessionProvider);
    final seconds = session?.remainingRestSeconds(nowMs) ?? -1;
    if (seconds != _lastRestSeconds) {
      _lastRestSeconds = seconds;
      if (mounted) setState(() {});
    }
  }

  Future<void> _endWorkout({required bool save}) async {
    await ref.read(workoutSessionProvider.notifier).endWorkout(save: save);
    if (mounted && context.mounted) {
      // 回排期卡所在计划页（分支栈内 pop 一层）。
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final session = ref.watch(workoutSessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(session == null ? '训练' : '训练中 · ${session.planName}'),
      ),
      body: session == null
          ? _EmptyBody(onBack: () => Navigator.of(context).maybePop())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  // 组间休息倒计时横幅（§3.5「组间计时器」；剩余秒=注入时钟
                  // 对 rest_ends_at 绝对时刻的即时重算——锁屏恢复即正确）。
                  if (session.isResting) ...[
                    _RestBanner(
                      remainingS: session.remainingRestSeconds(
                        ref.watch(workoutClockProvider)().millisecondsSinceEpoch,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (session.allDone) ...[
                    _AllDoneBanner(completed: session.sets.length),
                    const SizedBox(height: 12),
                  ],
                  // 动作进度（§5.5⑧ 模板；§5.5⑨ 组序=动作内第 N 组）。
                  for (var i = 0; i < session.exercises.length; i++) ...[
                    _ExerciseRow(
                      exercise: session.exercises[i],
                      isCurrent: i == session.exerciseIndex && !session.allDone,
                      doneSetsOfCurrent: i == session.exerciseIndex
                          ? session.setNo - 1
                          : null,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (session.exercises.isEmpty) ...[
                    Text(
                      '该计划模板为空（动作/组数/休息秒待维护，§5.5⑧）——'
                      '可直接结束并保存（不产生组明细）',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '已完成 ${session.sets.length}/${session.totalSets} 组'
                    ' · 用时 ${_elapsedText(session)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 完成一组（休息中/全部完成置灰——控制器内同样 no-op 防御）。
                  FilledButton(
                    key: workoutLogSetKey,
                    onPressed:
                        (session.isResting || session.allDone || session.exercises.isEmpty)
                            ? null
                            : () => ref
                                .read(workoutSessionProvider.notifier)
                                .logCurrentSet(),
                    style: FilledButton.styleFrom(
                      backgroundColor: tokens.primary,
                      foregroundColor: tokens.onPrimary,
                      disabledBackgroundColor: tokens.surfaceMuted,
                      disabledForegroundColor: tokens.onSurfaceMuted,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      session.allDone
                          ? '全部组完成'
                          : session.isResting
                              ? '休息中（可跳过）'
                              : '完成一组 · ${session.currentExercise.name}'
                                  ' 第 ${session.setNo}/${session.currentExercise.sets} 组',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 结束并保存：会话+组明细同事务落库（§6.2）+ workout_completed
                  // + 常亮 off（W14 任务 5 断言）。
                  FilledButton.tonal(
                    key: workoutEndSaveKey,
                    onPressed: () => _endWorkout(save: true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('结束并保存'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: workoutDiscardKey,
                    onPressed: () => _endWorkout(save: false),
                    child: const Text('放弃训练（不落库）'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '锁屏/切后台后休息倒计时照走（常驻通知挂原生倒计时）；'
                    '回到本页按当前时刻即时重算（§3.5 组间计时 锁屏可跑）',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 已用时长 mm:ss（结束时刻由「结束并保存」落库时取注入时钟）。
  String _elapsedText(WorkoutSessionState session) {
    final nowMs = ref.read(workoutClockProvider)().millisecondsSinceEpoch;
    final seconds = ((nowMs - session.startedAtMs) / 1000).floor();
    final safe = seconds < 0 ? 0 : seconds;
    final mm = safe ~/ 60;
    final ss = safe % 60;
    return '$mm:${ss.toString().padLeft(2, '0')}';
  }
}

/// 无进行中训练态（直接进路由的防御分支；训练中态由排期卡「开始训练」创建）。
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.fitness_center_outlined, size: 48, color: tokens.kcalOut),
          const SizedBox(height: 12),
          const Text('没有进行中的训练'),
          const SizedBox(height: 8),
          Text(
            '去「计划」页排期卡开始一次训练（§3.5 健身计划）',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onBack, child: const Text('返回')),
        ],
      ),
    );
  }
}

/// 组间休息横幅：大数字剩余秒 + 跳过（§3.5 组间计时器）。
class _RestBanner extends ConsumerWidget {
  const _RestBanner({required this.remainingS});

  final int remainingS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.kcalOut.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('组间休息', style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$remainingS',
                      key: workoutRestRemainingKey,
                      style: textTheme.displaySmall?.copyWith(
                        color: tokens.kcalOut,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '秒后开始下一组',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton(
            key: workoutSkipRestKey,
            onPressed: () =>
                ref.read(workoutSessionProvider.notifier).skipRest(),
            child: const Text('跳过休息'),
          ),
        ],
      ),
    );
  }
}

/// 全部完成横幅（引导「结束并保存」落库，§5.5⑦ 会话入账）。
class _AllDoneBanner extends StatelessWidget {
  const _AllDoneBanner({required this.completed});

  final int completed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '全部组完成，共 $completed 组——点「结束并保存」入账'
        '（消耗计入运动条与净热量，MET ±20% 口径 §3.5）',
        style: textTheme.bodyMedium?.copyWith(color: tokens.success),
      ),
    );
  }
}

/// 动作行：名称 + 组数/次数/重量/休息秒（§5.5⑧ 模板口径）；当前动作高亮。
class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.isCurrent,
    required this.doneSetsOfCurrent,
  });

  final WorkoutExercisePlan exercise;

  /// 是否当前动作（高亮）。
  final bool isCurrent;

  /// 当前动作已完成组数（仅当前动作传入；null=不显示）。
  final int? doneSetsOfCurrent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final weight = exercise.weightKg == null
        ? '自重'
        : '${exercise.weightKg}kg';
    final rest = (exercise.restS ?? 0) > 0 ? ' · 休 ${exercise.restS}s' : '';
    final detail = '${exercise.sets} 组 × ${exercise.reps} 次 · $weight$rest';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? tokens.primary.withValues(alpha: 0.10)
            : tokens.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? tokens.primary : tokens.outline,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: tokens.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ),
          if (doneSetsOfCurrent != null)
            Text(
              '$doneSetsOfCurrent/${exercise.sets} 组',
              style: textTheme.labelMedium?.copyWith(
                color: isCurrent ? tokens.primary : tokens.onSurfaceMuted,
              ),
            ),
        ],
      ),
    );
  }
}
