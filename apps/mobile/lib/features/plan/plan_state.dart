/// 计划 Tab 数据流（§4.2「待办 / 健身 / 存钱三卡」、§3.5/§3.6、§5.5⑦⑩⑪⑫）。
///
/// 设计决策（与 dashboard_state.dart 同一纪律）：
/// - 一切围绕仪表盘当前选中日（selectedDateProvider，§3.2「一切围绕日期」）：
///   计划 Tab 的待办/健身会话均按该日展示——切日跨 Tab 一致；
/// - 聚合从明细/真值行 reactive stream 重建（§6.1 原则 3「投影不同步、从明细
///   重建」），任一行变更即重发——「记一笔健身→仪表盘运动条即时更新」的
///   数据底座（§11.1 W5-6 验收线）；
/// - 墓碑行不参与（§5.1 删除行）；存钱目标 W13 上线（§3.6 P1 留存钩子，
///   §11.2 W13）：打卡中目标 + Σ贡献进度 reactive 流直驱存钱卡。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/fitness_service.dart' show kDefaultBodyWeightKg, kSettingBodyWeightKg;
import '../../data/workout_models.dart'
    show WorkoutExercisePlan, parsePlanExercises;

/// 某日待办流（§5.5⑩ todos；未完成在前，TodoDao 排序口径）。
///
/// W5-6 计划 Tab 承载待办基础（§3.6：当日/未来待办、勾选完成）——增删勾选
/// 经 [todoDaoProvider]（done_at 只前进合并，§6.5 todo.done）。
final planTodosProvider =
    StreamProvider.autoDispose.family<List<db.Todo>, String>((ref, date) {
  final dao = ref.watch(todoDaoProvider);
  return dao.watchByDate(date);
});

/// 某日健身会话流（§5.5⑦ fitness_sessions；W5-6 手动记录，计划卡 P1 W14）。
///
/// 墓碑会话不展示（§5.1 删除行）；事件的 burn 行经 dashboard 流聚合进净热量
/// （§3.5「消耗进运动条与净热量（摄入-消耗）」），本流只服务计划 Tab 列表。
final planSessionsProvider =
    StreamProvider.autoDispose.family<List<db.FitnessSession>, String>(
        (ref, date) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.fitnessSessions)
        ..where((t) => t.date.equals(date) & t.deletedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm.desc(t.startAt),
          (t) => OrderingTerm.desc(t.createdAt),
        ]))
      .watch();
});

/// 身体档案体重流（kg）（§3.5 身体档案 P0「体重设置（settings），MET 估算
/// 依赖」、§5.6⑲ settings 本地件）。
///
/// 未设置或缺省回 [kDefaultBodyWeightKg]（60kg 估算基线，仅作估算输入、
/// 不写库）；FitnessLogPage 保存时随会话同事务落 settings（§5.6⑲）。
final bodyWeightKgProvider = StreamProvider<double>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.settings)
        ..where((s) => s.key.equals(kSettingBodyWeightKg)))
      .watchSingleOrNull()
      .map((row) {
    if (row == null) return kDefaultBodyWeightKg;
    final value = double.tryParse(
      row.value.replaceAll('"', '').trim(),
    );
    if (value == null || value <= 0 || value > 500) return kDefaultBodyWeightKg;
    return value;
  });
});

// ── W13 存钱目标流（§3.6 存钱目标 P1、§5.5⑪⑫、§11.2 W13）────────────────

/// 存钱卡目标视图：打卡中目标 + Σ贡献进度（§5.5⑫「进度=贡献行求和」）。
class PlanSavingsGoalView {
  const PlanSavingsGoalView({
    required this.goal,
    required this.contributedMinor,
  });

  /// 目标行（§5.5⑪，status='active' 且未墓碑）。
  final db.SavingsGoal goal;

  /// 已存入金额（分；Σ contributions 未墓碑行，append-only 口径 §6.1）。
  final int contributedMinor;

  /// 进度 0..1（target=0 防御为 0，不除零 §7.4）。
  double get progress {
    if (goal.targetMinor <= 0) return 0;
    return (contributedMinor / goal.targetMinor).clamp(0.0, 1.0).toDouble();
  }
}

/// 打卡中目标 + 进度流（计划 Tab 存钱卡数据源；§11.2 W13）。
///
/// 触发查询同时 readsFrom 两张真值表（§5.5⑪⑫）：目标增删改或贡献 append
/// 任一变更即重发；每次重发从明细行一次性重建视图（§6.1 原则 3「聚合从
/// 明细行重建」）——目标行取完整行类，贡献按目标分组求和（未墓碑行，与
/// SavingsContributionsDao.sumByGoal 同口径）。
final planSavingsGoalsProvider =
    StreamProvider.autoDispose<List<PlanSavingsGoalView>>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database
      .customSelect(
        'SELECT 1 AS alive',
        readsFrom: {database.savingsGoals, database.savingsContributions},
      )
      .watch()
      .asyncMap((_) async {
    final goals = await (database.select(database.savingsGoals)
          ..where((t) =>
              t.status.equals(db.kSavingsGoalStatusActive) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    final sumRows = await database
        .customSelect(
          'SELECT goal_id, COALESCE(SUM(amount_minor), 0) AS total '
          'FROM savings_contributions WHERE deleted_at IS NULL GROUP BY goal_id',
        )
        .get();
    final contributedByGoal = <String, int>{
      for (final row in sumRows)
        row.read<String>('goal_id'): row.read<int>('total'),
    };
    return <PlanSavingsGoalView>[
      for (final goal in goals)
        PlanSavingsGoalView(
          goal: goal,
          contributedMinor: contributedByGoal[goal.id] ?? 0,
        ),
    ];
  });
});

// ── W14 健身计划流（§3.5 健身计划 P1、§5.5⑧、§11.2 W14 任务 1）────────────

/// 排期视图：计划行 + 宽容解析的模板动作（§5.5⑧ exercises JSON，
/// parsePlanExercises 坏模板回空——排期卡显示「模板待完善」§7.4）。
class FitnessPlanScheduleView {
  const FitnessPlanScheduleView({
    required this.plan,
    required this.exercises,
  });

  /// 计划行（§5.5⑧：name/weekday_mask/exercises/start_date/active）。
  final db.FitnessPlan plan;

  /// 模板动作（训练会话控制器的排期来源）。
  final List<WorkoutExercisePlan> exercises;

  /// 排期日标签（bit0=周一…bit6=周日，§5.5⑧）→「一/三/五」。
  String get weekdaysLabel => fitnessWeekdaysLabel(plan.weekdayMask);
}

/// 排期掩码 → 排期日标签「一/三/五」（bit0=周一…bit6=周日，§5.5⑧）。
String fitnessWeekdaysLabel(int weekdayMask) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  final days = <String>[
    for (var bit = 0; bit < 7; bit++)
      if (weekdayMask & (1 << bit) != 0) labels[bit],
  ];
  return days.isEmpty ? '未排期' : days.join('/');
}

/// 排期掩码判定（§5.5⑧ bit0=周一…bit6=周日）：启用中 + 已开跑（startDate
/// ≤ 指定日，TEXT 日历日字典序=时间序 §5.1）+ 当日掩码位命中。
bool isPlanScheduledOn(db.FitnessPlan plan, String date) {
  if (!plan.active || plan.deletedAt != null) return false;
  if (plan.startDate.compareTo(date) > 0) return false;
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return false;
  final bit = 1 << (parsed.weekday - 1); // Dart weekday: 1=周一…7=周日。
  return plan.weekdayMask & bit != 0;
}

/// 启用中计划流（未删、active；排期卡「计划」列表段数据源）。
final activeFitnessPlansProvider =
    StreamProvider.autoDispose<List<db.FitnessPlan>>((ref) {
  return _watchActivePlans(ref.watch(appDatabaseProvider));
});

/// 启用中计划 watch 流（单一查询源：activeFitnessPlansProvider 与
/// planScheduleProvider 共用，避免组合两层 provider——Riverpod 3 中
/// watch StreamProvider 得 AsyncValue 而非 Stream，§10.1）。
Stream<List<db.FitnessPlan>> _watchActivePlans(db.AppDatabase database) {
  return (database.select(database.fitnessPlans)
        ..where((t) => t.active & t.deletedAt.isNull())
        ..orderBy([
          (t) => OrderingTerm.desc(t.startDate),
          (t) => OrderingTerm.asc(t.createdAt),
        ]))
      .watch();
}

/// 某日排期流（§3.5「训练模板按周排期」：weekday_mask 命中 + 已开跑；
/// 计划 Tab「今日排期卡」数据源，随仪表盘选中日 §3.2 一切围绕日期）。
///
/// 响应式来源 = fitness_plans watch 流（[_watchActivePlans]，与
/// activeFitnessPlansProvider 同源）；计划行变更（编辑器保存/归档）即时
/// 重发（§6.1 原则 3 reactive stream 直驱）。
final planScheduleProvider = StreamProvider.autoDispose
    .family<List<FitnessPlanScheduleView>, String>((ref, date) {
  return _watchActivePlans(ref.watch(appDatabaseProvider)).map((plans) => [
        for (final plan in plans)
          if (isPlanScheduledOn(plan, date))
            FitnessPlanScheduleView(
              plan: plan,
              exercises: parsePlanExercises(plan.exercises),
            ),
      ]);
});
