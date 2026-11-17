/// 计划域 Riverpod providers（§10.1：StreamProvider 直驱 reactive 读侧、
/// §10.4 分层）。全部 autoDispose.family（按日/按域自动回收）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'plan_gateway.dart';
import 'plan_models.dart';

/// 某日健身会话流（§3.5「列表可按日查看」）。
final fitnessSessionsProvider = StreamProvider.autoDispose
    .family<List<cdb.FitnessSession>, String>((ref, date) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchSessionsByDate(date);
});

/// 某日 day_summary 投影流（§5.6⑬ 仪表盘快照直出；计划 Tab 卡片摘要用）。
/// 与 apps/mobile 仪表盘同口径，但独立实例（分包不反向依赖壳）。
final planDaySummaryProvider = StreamProvider.autoDispose
    .family<cdb.DaySummary?, String>((ref, date) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.projection.watchDaySummary(date);
});

/// 某日待办流（§3.6 今日待办视图）。
final todayTodosProvider = StreamProvider.autoDispose
    .family<List<cdb.Todo>, String>((ref, date) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchTodosByDate(date);
});

/// 收集箱流（§3.6 收集箱视图；§5.5⑩ date NULL=收集箱）。
final inboxTodosProvider =
    StreamProvider.autoDispose<List<cdb.Todo>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchInboxTodos();
});

/// 存钱目标视图流（§5.5⑪⑫：目标 + Σ贡献进度；W13 打卡写路径上线，
/// 联查 readsFrom 双表 reactive 刷新——见 plan_gateway.watchSavingsGoalViews）。
final savingsGoalsProvider =
    StreamProvider.autoDispose<List<SavingsGoalView>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchSavingsGoalViews();
});

/// 单目标流（W13 目标详情页，§3.6）。
final savingsGoalDetailProvider =
    StreamProvider.autoDispose.family<cdb.SavingsGoal?, String>((ref, id) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchGoalById(id);
});

/// 单目标进度求和流（§5.5⑫「进度=Σ贡献行」；详情页进度环/达成判定）。
final savingsGoalProgressProvider =
    StreamProvider.autoDispose.family<int, String>((ref, goalId) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchGoalProgress(goalId);
});

/// 目标贡献历史流（§3.6 目标详情「贡献历史」，append-only 时间线）。
final savingsGoalContributionsProvider = StreamProvider.autoDispose
    .family<List<cdb.SavingsContribution>, String>((ref, goalId) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchContributionsByGoal(goalId);
});

/// 目标当日人工投币行流（§3.6 投币打卡「状态防重复」：非空=今日已投币）。
/// family key 为 (goalId, date) 记录（结构相等，Dart 3 record 语义）。
final todayManualContributionProvider = StreamProvider.autoDispose
    .family<cdb.SavingsContribution?, (String, String)>((ref, key) {
  final gateway = ref.watch(planGatewayProvider);
  final (goalId, date) = key;
  return gateway.watchTodayManualContribution(goalId: goalId, date: date);
});

/// 某日待办实例流（§3.6 待办完整版 W13：查询时按 anchor 展开当日实例、
/// 不预生成行——[date] null=收集箱基行直出）。
final todoDayInstancesProvider = StreamProvider.autoDispose
    .family<List<TodoDayInstance>, String?>((ref, date) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchTodoDayInstances(date);
});

/// 健身计划流（§5.5⑧；W14 起模板/排期/开练全量接入）。
final fitnessPlansProvider =
    StreamProvider.autoDispose<List<cdb.FitnessPlan>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchFitnessPlans();
});

/// 单计划流（W14 编辑预填/详情；§5.5⑧）。
final fitnessPlanDetailProvider = StreamProvider.autoDispose
    .family<cdb.FitnessPlan?, String>((ref, id) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchPlanById(id);
});

/// 全部会话流（W14 训练历史页数据源；手动记录与计划实例共用行模型，
/// §5.5⑦）。
final allFitnessSessionsProvider =
    StreamProvider.autoDispose<List<cdb.FitnessSession>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchAllSessions();
});

/// 某会话组明细流（W14 开练页「已落组明细」列表，§5.5⑨）。
final exerciseSetsBySessionProvider = StreamProvider.autoDispose
    .family<List<cdb.ExerciseSet>, String>((ref, sessionId) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchSetsBySession(sessionId);
});

/// 会话 → 存活组数映射流（W14 历史页组数徽标；GROUP BY 单查询直驱，
/// §5.5⑨）。
final setCountBySessionProvider =
    StreamProvider.autoDispose<Map<String, int>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchSetCountsBySession();
});
