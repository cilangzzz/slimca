/// 开练流控制器（§11.2 W14 主线任务 2/3「开练流 + 组明细」、§5.5⑦⑧⑨、
/// §10.1 Riverpod 3 AsyncNotifier）。
///
/// 编排口径：
/// - family key = 会话 id（开练入口先经 PlanGateway.startWorkoutSession 建行
///   再进页——页面可安全重建/续挂，控制器不重复建会话）；
/// - 「当前目标」由模板前缀和 + 已完成组数**纯推导**（不落任何游标状态）：
///   完成组只 append（§5.5⑨ append-only），断点续挂凭组明细行数恢复游标；
/// - 每完成一组经 [PlanGateway.logExerciseSet] 落 exercise_sets 行（真值行 +
///   outbox 同事务，§6.2）；「完成训练」经 [PlanGateway.finishWorkoutSession]
///   汇总时长/MET 消耗并联动 entry+burn 行（复用 W5-6 链路）；
/// - 组间计时不属本控制器：rest 秒数从模板读、由页面驱动 restTimerProvider
///   （见 widgets/rest_timer.dart，§11.2 W14 注入心跳）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_plan_models.dart';
import 'plan_gateway.dart';

/// 开练流种子（family key，§10.1：须实现 ==/hashCode）。
class FitnessWorkoutSeed {
  const FitnessWorkoutSeed({required this.sessionId});

  /// 会话行 id（fitness_sessions.id，开练入口已建行，§5.5⑦）。
  final String sessionId;

  @override
  bool operator ==(Object other) =>
      other is FitnessWorkoutSeed && other.sessionId == sessionId;

  @override
  int get hashCode => sessionId.hashCode;

  @override
  String toString() => 'FitnessWorkoutSeed(sessionId: $sessionId)';
}

/// 开练流状态（§11.2 W14）。
class FitnessWorkoutState {
  const FitnessWorkoutState({
    required this.session,
    required this.plan,
    required this.template,
    required this.weightKg,
    required this.completedCount,
    this.finishing = false,
    this.finished = false,
    this.errorText,
  });

  /// 会话行（§5.5⑦；start_at 为开练时刻）。
  final cdb.FitnessSession session;

  /// 计划行（§5.5⑧，会话 plan_day_id 逻辑引用）。
  final cdb.FitnessPlan plan;

  /// 模板动作列表（exercises JSON 解析，§5.5⑧；坏 JSON 防御为空列表 §7.4）。
  final List<PlanExercise> template;

  /// 身体档案体重 kg（MET 估算输入，§3.5；完成训练时随网关落估算）。
  final double weightKg;

  /// 已完成组数（控制器口径：本会话存活组明细行数；完成一组 +1）。
  final int completedCount;

  /// 汇总进行中（防重复提交）。
  final bool finishing;

  /// 已汇总完成（entry+burn 行已联动，§5.5⑦）。
  final bool finished;

  /// 汇总失败文案；null=无错误。
  final String? errorText;

  /// 模板总组数（「共 N 组」；Σ 动作组数，与 FitnessPlanTemplate.totalSets
  /// 同口径——template 为裸 List，此处折叠）。
  int get totalSets => template.fold(0, (acc, e) => acc + e.sets);

  /// 全部组完成（无剩余目标 → 展示「完成训练」主 CTA）。
  bool get allCompleted => template.isNotEmpty && completedCount >= totalSets;

  /// 当前目标（第 setNo 组）：模板前缀和 + [completedCount] 纯推导——
  /// 全部完成返回 null。
  ({PlanExercise exercise, int setNo})? get currentTarget {
    var remaining = completedCount;
    for (final exercise in template) {
      if (remaining < exercise.sets) {
        return (exercise: exercise, setNo: remaining + 1);
      }
      remaining -= exercise.sets;
    }
    return null;
  }

  /// 「不改动」哨兵（errorText 可空字段清除口径，与 FitnessFormState 同法）。
  static const Object _unchanged = Object();

  FitnessWorkoutState copyWith({
    cdb.FitnessSession? session,
    int? completedCount,
    bool? finishing,
    bool? finished,
    Object? errorText = _unchanged,
  }) =>
      FitnessWorkoutState(
        session: session ?? this.session,
        plan: plan,
        template: template,
        weightKg: weightKg,
        completedCount: completedCount ?? this.completedCount,
        finishing: finishing ?? this.finishing,
        finished: finished ?? this.finished,
        errorText: identical(errorText, _unchanged)
            ? this.errorText
            : errorText as String?,
      );
}

/// 开练流控制器 provider（§10.4；用法同 fitnessFormControllerProvider）。
final fitnessWorkoutControllerProvider = AsyncNotifierProvider.family
    .autoDispose<FitnessWorkoutController, FitnessWorkoutState,
        FitnessWorkoutSeed>(FitnessWorkoutController.new);

/// 开练流控制器：装载会话/计划/模板 → 逐组落行 → 完成汇总。
class FitnessWorkoutController
    extends AsyncNotifier<FitnessWorkoutState> {
  FitnessWorkoutController(this.seed);

  /// 开练参数（会话 id）。
  final FitnessWorkoutSeed seed;

  /// 完成一组在途标记（防双击重复落组——比 state 标志轻，控制器实例内闭环）。
  bool _completing = false;

  @override
  Future<FitnessWorkoutState> build() async {
    final gateway = ref.watch(planGatewayProvider);
    final session = await gateway.findSessionById(seed.sessionId);
    if (session == null) {
      throw StateError(
          '开练流：fitness_sessions 无此行 ${seed.sessionId}（§5.5⑦）');
    }
    final planId = session.planDayId;
    if (planId == null) {
      throw StateError(
          '开练流：会话 ${seed.sessionId} 缺 plan_day_id（§11.2 W14 计划实例口径）');
    }
    final plan = await gateway.findPlanById(planId);
    if (plan == null) {
      throw StateError('开练流：fitness_plans 无此行 $planId（§5.5⑧）');
    }
    final weight = await gateway.loadBodyWeightKg();
    // 断点续挂：已完成组从组明细行数恢复（append-only 口径，§5.5⑨）。
    final sets = await gateway.setsForSession(seed.sessionId);
    return FitnessWorkoutState(
      session: session,
      plan: plan,
      template: FitnessPlanTemplate.decode(plan.exercises).exercises,
      weightKg: weight,
      completedCount: sets.length,
    );
  }

  /// 完成当前组（§11.2 W14 任务 3）：次数/重量由调用方传入（UI 预填模板目标、
  /// 可改）；组序=已完成数+1；休息秒随模板动作落列（§5.5⑨ rest_s）。
  ///
  /// 返回落库行；无可练目标/在途/失败返回 null（UI 不打断，§3.7 本地优先）。
  /// 成功后控制器游标前移（completedCount+1 → currentTarget 纯推导推进）。
  Future<cdb.ExerciseSet?> completeCurrentSet({
    required int reps,
    required int weightKgX10,
  }) async {
    final current = state.value;
    if (current == null || current.finished || _completing) return null;
    final target = current.currentTarget;
    if (target == null) return null;
    _completing = true;
    try {
      final gateway = ref.read(planGatewayProvider);
      final row = await gateway.logExerciseSet(
        sessionId: seed.sessionId,
        exerciseRef: target.exercise.name,
        reps: reps,
        weightKgX10: weightKgX10,
        restS: target.exercise.restS,
        sort: current.completedCount + 1,
      );
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
            latest.copyWith(completedCount: latest.completedCount + 1));
      }
      return row;
    } finally {
      _completing = false;
    }
  }

  /// 完成训练（§11.2 W14 任务 3「训练结束汇总」）：经网关单事务汇总时长/
  /// MET 消耗并联动 entry+burn 行（复用 W5-6 链路）。幂等（已汇总直接返回
  /// 既有会话）；无组明细返回 null（空会话由退出清理路径软删，UI 口径）。
  Future<cdb.FitnessSession?> finish() async {
    final current = state.value;
    if (current == null) return null;
    if (current.finished) return current.session;
    if (current.finishing || current.completedCount == 0) return null;
    state = AsyncData(current.copyWith(finishing: true, errorText: null));
    try {
      final gateway = ref.read(planGatewayProvider);
      final session = await gateway.finishWorkoutSession(
        sessionId: seed.sessionId,
        weightKg: current.weightKg,
      );
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(latest.copyWith(
          session: session,
          finishing: false,
          finished: true,
        ));
      }
      return session;
    } catch (_) {
      final latest = state.value;
      if (latest != null) {
        state = AsyncData(
            latest.copyWith(finishing: false, errorText: '汇总失败，请重试'));
      }
      return null;
    }
  }
}
