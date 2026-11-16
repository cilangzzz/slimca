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

/// 存钱目标视图流（§5.5⑪⑫：目标 + Σ贡献进度；W13 前恒空列表）。
final savingsGoalsProvider =
    StreamProvider.autoDispose<List<SavingsGoalView>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchSavingsGoalViews();
});

/// 健身计划流（§5.5⑧；W14 前恒空列表）。
final fitnessPlansProvider =
    StreamProvider.autoDispose<List<cdb.FitnessPlan>>((ref) {
  final gateway = ref.watch(planGatewayProvider);
  return gateway.watchFitnessPlans();
});
