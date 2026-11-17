/// 训练会话控制器（§11.2 W14「组间计时器（锁屏可跑）」骨架、§3.5 健身计划
/// P1、W14 任务 2/3/4）。
///
/// 状态模型（Riverpod 3 Notifier，§10.1）：null=无进行中训练；计划 Tab 排期
/// 卡「开始训练」（W14 任务 1）、训练中页与仪表盘「训练中」卡（W14 任务 4，
/// 读 Riverpod provider）共读本 provider——默认 keepAlive（非 autoDispose），
/// 切 Tab/关页不丢进行中训练。
///
/// 计时纪律（W14 任务 5「测试禁止真实计时器，用注入时钟」）：剩余休息秒一律
/// 以**绝对时刻**计算（rest_ends_at = now + rest_s，时钟注入
/// workoutClockProvider）——锁屏/进程冻结恢复后按时钟即时重算，秒值语义与
/// 展示节奏解耦（UI 的每秒 Timer 只做渲染刷新与到点探询，§9.5 隐式动画/
/// 计时仅限微交互）。业务推进（到点回落/通知还原）由 [WorkoutSessionController
/// .syncRest] 以注入时钟判定，测试 pump 可控。
///
/// 副作用编排（W14 任务 2/3）：
/// - 开练 → KeepAwake.enable（W14 任务 5 断言 on）+ 常驻通知 + workout_started；
/// - 记组 → 组间休息通知（原生倒计时）+ set_logged；
/// - 结束 → 落库（WorkoutLogService，§5.5⑦⑨/§6.2 单事务 outbox+投影）+
///   workout_completed + KeepAwake.disable（W14 任务 5 断言 off）+ 通知 cancel。
library;

import 'dart:async';

import 'package:core_db/core_db.dart' as db;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/fitness_service.dart' show kDefaultBodyWeightKg;
import '../../data/workout_log_service.dart';
import '../../data/workout_models.dart';
import '../../telemetry/w14_funnel_events.dart';
import '../../workout/rest_timer_notifier.dart';
import '../plan/plan_state.dart' show bodyWeightKgProvider;

/// 进行中训练态（null=无训练；结束/放弃后回到 null）。
class WorkoutSessionState {
  const WorkoutSessionState({
    required this.planId,
    required this.planName,
    required this.date,
    required this.tzOffsetMin,
    required this.exercises,
    required this.exerciseIndex,
    required this.setNo,
    required this.sets,
    required this.startedAtMs,
    required this.allDone,
    required this.restEndsAtMs,
    required this.restTotalS,
  });

  /// 计划 id（§5.5⑧；落库 plan_day_id 溯源）。
  final String planId;

  /// 计划名（通知正文/事件标题成分）。
  final String planName;

  /// 训练归属日 `yyyy-MM-dd`（§5.1；=排期卡选中日）。
  final String date;

  /// 本地时区偏移（分钟，§5.1）。
  final int tzOffsetMin;

  /// 模板动作（§5.5⑧ exercises 宽容解析，坏模板可为空列表）。
  final List<WorkoutExercisePlan> exercises;

  /// 当前动作下标（0 起；全部完成时停在末动作）。
  final int exerciseIndex;

  /// 当前动作第几组（1 起）。
  final int setNo;

  /// 已完成组（内存累积，结束时同事务落库 §5.5⑨/§6.2）。
  final List<WorkoutSetEntry> sets;

  /// 开始时刻 UTC ms。
  final int startedAtMs;

  /// 全部组完成（§3.5 计划日训练走完）。
  final bool allDone;

  /// 组间休息截止时刻 UTC ms（null=非休息中；绝对时刻=锁屏可跑的正确性
  /// 来源，恢复后按时钟重算）。
  final int? restEndsAtMs;

  /// 本次休息总秒数（剩余秒上限，防时钟回拨长显）。
  final int? restTotalS;

  /// 当前动作（下标钳制防御）。
  WorkoutExercisePlan get currentExercise =>
      exercises.isEmpty
          ? const WorkoutExercisePlan(name: '待完善', sets: 1, reps: 0)
          : exercises[exerciseIndex.clamp(0, exercises.length - 1)];

  /// 是否休息中。
  bool get isResting => restEndsAtMs != null;

  /// 模板总组数（Σ动作组数）。
  int get totalSets =>
      exercises.fold(0, (sum, e) => sum + e.sets);

  /// 剩余休息秒（注入时钟 nowMs 判定；ceil 起显整数、到点 0、回拨钳上限）。
  int remainingRestSeconds(int nowMs) {
    final endsAt = restEndsAtMs;
    if (endsAt == null) return 0;
    final remainMs = endsAt - nowMs;
    if (remainMs <= 0) return 0;
    final remainS = (remainMs / 1000).ceil();
    final total = restTotalS ?? 0;
    return remainS > total ? total : remainS;
  }

  /// 休息态副本（到点/跳过时清空；非休息 no-op 语义由调用方保证）。
  WorkoutSessionState withRest({int? endsAtMs, int? totalS}) =>
      WorkoutSessionState(
        planId: planId,
        planName: planName,
        date: date,
        tzOffsetMin: tzOffsetMin,
        exercises: exercises,
        exerciseIndex: exerciseIndex,
        setNo: setNo,
        sets: sets,
        startedAtMs: startedAtMs,
        allDone: allDone,
        restEndsAtMs: endsAtMs,
        restTotalS: totalS,
      );
}

/// 进行中训练 provider（W14 任务 4 仪表盘卡数据源；默认 keepAlive）。
final workoutSessionProvider =
    NotifierProvider<WorkoutSessionController, WorkoutSessionState?>(
  WorkoutSessionController.new,
);

/// 训练会话控制器（副作用编排见文件头；状态变更全部同步写 state）。
class WorkoutSessionController extends Notifier<WorkoutSessionState?> {
  @override
  WorkoutSessionState? build() => null;

  /// 注入时钟（W14 任务 5：测试 override 可控时钟，禁真实计时器断言）。
  int _nowMs() => ref.read(workoutClockProvider)().millisecondsSinceEpoch;

  /// 开练（排期卡「开始训练」，§3.5 计划日训练）：置态 → 常亮 → 常驻通知
  /// → workout_started。已有进行中训练为幂等 no-op（UI 入口同时防重）。
  Future<void> startFromPlan(
    db.FitnessPlan plan, {
    required String date,
  }) async {
    if (state != null) return;
    final exercises = parsePlanExercises(plan.exercises);
    final totalSets = exercises.fold(0, (sum, e) => sum + e.sets);
    state = WorkoutSessionState(
      planId: plan.id,
      planName: plan.name,
      date: date,
      tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
      exercises: exercises,
      exerciseIndex: 0,
      setNo: 1,
      sets: const [],
      startedAtMs: _nowMs(),
      allDone: false,
      restEndsAtMs: null,
      restTotalS: null,
    );
    // W14 任务 2：开练 → 屏幕常亮（Fake 断言 enable）。
    await ref.read(keepAwakeProvider).enable();
    // W14 任务 2：常驻通知（训练中底条；结束时统一 cancel）。
    await ref.read(workoutTimerNotifierProvider).show(WorkoutTimerNotice(
          notificationId: kWorkoutTimerNotificationId,
          title: '训练进行中',
          body: exercises.isEmpty
              ? '${plan.name} · 模板待完善'
              : '${plan.name} · ${exercises.length} 个动作 · $totalSets 组',
        ));
    // W14 任务 3：漏斗起点（props 只带枚举标签，§3.9）。
    await ref
        .read(telemetryServiceProvider)
        .funnel(W14TelemetryFunnel.workoutStarted,
            props: <String, Object?>{'source': 'plan'});
  }

  /// 完成当前组（§3.5 组间计时器、§5.5⑨ 组明细累积）：记录 → 推进指针 →
  /// 按模板休息秒启动绝对时刻倒计时（通知挂原生倒计时）→ set_logged。
  ///
  /// 休息中/全部完成/空模板时为 no-op（UI 按钮同时置灰；空模板无可记组）。
  Future<void> logCurrentSet() async {
    final s = state;
    if (s == null || s.isResting || s.allDone || s.exercises.isEmpty) return;
    final exercise = s.currentExercise;
    final nowMs = _nowMs();
    final restS = exercise.restS ?? 0;
    final sets = [
      ...s.sets,
      WorkoutSetEntry(
        exerciseRef: exercise.name,
        exerciseIndex: s.exerciseIndex,
        setNo: s.setNo,
        reps: exercise.reps,
        weightKg: exercise.weightKg,
        restS: restS,
        doneAtMs: nowMs,
      ),
    ];

    // 指针推进：本动作组满 → 下一动作第 1 组；末动作组满 → 全部完成（停在
    // 末组，等「结束并保存」）。
    var exerciseIndex = s.exerciseIndex;
    var setNo = s.setNo + 1;
    var allDone = false;
    if (setNo > exercise.sets) {
      if (s.exerciseIndex < s.exercises.length - 1) {
        exerciseIndex = s.exerciseIndex + 1;
        setNo = 1;
      } else {
        exerciseIndex = s.exerciseIndex;
        setNo = s.setNo;
        allDone = true;
      }
    }

    // 组间休息（§3.5）：有休息秒且未全部完成 → 绝对时刻倒计时（锁屏可跑）。
    final resting = restS > 0 && !allDone;
    state = WorkoutSessionState(
      planId: s.planId,
      planName: s.planName,
      date: s.date,
      tzOffsetMin: s.tzOffsetMin,
      exercises: s.exercises,
      exerciseIndex: exerciseIndex,
      setNo: setNo,
      sets: sets,
      startedAtMs: s.startedAtMs,
      allDone: allDone,
      restEndsAtMs: resting ? nowMs + restS * 1000 : null,
      restTotalS: resting ? restS : null,
    );
    if (resting) {
      await ref.read(workoutTimerNotifierProvider).show(WorkoutTimerNotice(
            notificationId: kWorkoutTimerNotificationId,
            title: '组间休息',
            body: '${exercise.name} 第 ${s.setNo}/${exercise.sets} 组完成'
                ' · 休息 $restS 秒',
            chronometerEndsAtMs: nowMs + restS * 1000,
          ));
    }
    // W14 任务 3：记组漏斗（rest_s=休息时长标量，§3.9）。
    await ref
        .read(telemetryServiceProvider)
        .funnel(W14TelemetryFunnel.setLogged,
            props: <String, Object?>{'rest_s': restS});
  }

  /// 跳过组间休息（提前开下一组）。
  Future<void> skipRest() async {
    final s = state;
    if (s == null || !s.isResting) return;
    state = s.withRest(endsAtMs: null, totalS: null);
    await _showWorkoutNotice(s);
  }

  /// 到点探询（UI 每秒 tick 调用；W14 任务 4「训练中态卡显示剩余休息秒」的
  /// 状态推进半边）：注入时钟判定 rest_ends_at 已过 → 清休息态 + 通知还原。
  /// 未到点为 no-op（不写状态，避免每秒无谓重发）。
  void syncRest({int? nowMs}) {
    final s = state;
    if (s == null || !s.isResting) return;
    final ms = nowMs ?? _nowMs();
    if (ms < s.restEndsAtMs!) return;
    state = s.withRest(endsAtMs: null, totalS: null);
    unawaited(_showWorkoutNotice(s));
  }

  /// 结束训练：save=true 且有已记组 → 落库（§6.2 单事务）+ workout_completed；
  /// save=false（放弃）零落库零漏斗。finally 里一律释放常亮（W14 任务 5
  /// 断言 off）与取消常驻通知（§6.1 收尾纪律：落库异常也不悬挂副作用）。
  Future<void> endWorkout({required bool save}) async {
    final s = state;
    if (s == null) return;
    state = null;
    try {
      if (save && s.sets.isNotEmpty) {
        // 身体档案体重（§3.5；流未就绪回默认基线，仅作估算输入）。
        final weightKg =
            ref.read(bodyWeightKgProvider).value ?? kDefaultBodyWeightKg;
        await ref
            .read(workoutLogServiceProvider)
            .completeWorkout(WorkoutCompletionInput(
              planId: s.planId,
              planName: s.planName,
              date: s.date,
              tzOffsetMin: s.tzOffsetMin,
              startedAtMs: s.startedAtMs,
              endedAtMs: _nowMs(),
              weightKg: weightKg,
              sets: s.sets,
            ));
        await ref
            .read(telemetryServiceProvider)
            .funnel(W14TelemetryFunnel.workoutCompleted,
                props: <String, Object?>{
              'source': 'plan',
              'sets': s.sets.length,
            });
      }
    } finally {
      await ref.read(keepAwakeProvider).disable();
      await ref
          .read(workoutTimerNotifierProvider)
          .cancel(notificationId: kWorkoutTimerNotificationId);
    }
  }

  /// 常驻通知还原为「训练进行中」底条（休息结束/跳过时调用；通知内容属
  /// 本地通知内容，不入遥测，§3.9）。
  Future<void> _showWorkoutNotice(WorkoutSessionState s) async {
    await ref.read(workoutTimerNotifierProvider).show(WorkoutTimerNotice(
          notificationId: kWorkoutTimerNotificationId,
          title: '训练进行中',
          body: '${s.planName} · 已完成 ${s.sets.length} 组',
        ));
  }
}
