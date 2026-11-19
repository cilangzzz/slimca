/// 计划 Tab 数据流（IA 重设计收敛后：L0 今日卡读侧——会话/排期/身体档案）。
///
/// 设计决策（与 dashboard_state.dart 同一纪律）：
/// - 一切围绕仪表盘当前选中日（selectedDateProvider，§3.2「一切围绕日期」）：
///   计划 Tab 的健身会话/排期均按该日展示——切日跨 Tab 一致；
/// - 聚合从明细/真值行 reactive stream 重建（§6.1 原则 3「投影不同步、从明细
///   重建」），任一行变更即重发——「记一笔健身→仪表盘运动条即时更新」的
///   数据底座（§11.1 W5-6 验收线）；
/// - 墓碑行不参与（§5.1 删除行）；待办实例/收集箱/存钱目标视图读侧已收敛到
///   feature_plan providers（planGatewayProvider 装配，§10.4）——本文件不再
///   重复定义（双实现收敛）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart';
import 'package:feature_plan/feature_plan.dart'
    show kDefaultBodyWeightKg, kSettingBodyWeightKg;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/workout_models.dart'
    show WorkoutExercisePlan, parsePlanExercises;

/// 某日健身会话流（§5.5⑦ fitness_sessions；手动记录与计划实例共用行模型）。
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
/// 未设置或缺省回 [kDefaultBodyWeightKg]（70kg 估算基线，与 feature_plan
/// 网关同一常量——双基线已收敛；仅作估算输入、不写库）；健身记录页保存时
/// 经网关同事务落 settings（§5.6⑲）。
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

// ── 健身计划排期流（§3.5 健身计划 P1、§5.5⑧）────────────────────────────

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

/// 启用中计划 watch 流（单一查询源：planScheduleProvider 唯一消费）。
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
/// 计划 Tab「今日健身」卡排期态数据源，随仪表盘选中日 §3.2 一切围绕日期）。
///
/// 响应式来源 = fitness_plans watch 流（[_watchActivePlans]）；计划行变更
/// （编辑器保存/归档）即时重发（§6.1 原则 3 reactive stream 直驱）。
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
