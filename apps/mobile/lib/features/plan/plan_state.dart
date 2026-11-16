/// 计划 Tab 数据流（§4.2「待办 / 健身 / 存钱三卡」、§3.5/§3.6、§5.5⑦⑩）。
///
/// 设计决策（与 dashboard_state.dart 同一纪律）：
/// - 一切围绕仪表盘当前选中日（selectedDateProvider，§3.2「一切围绕日期」）：
///   计划 Tab 的待办/健身会话均按该日展示——切日跨 Tab 一致；
/// - 聚合从明细/真值行 reactive stream 重建（§6.1 原则 3「投影不同步、从明细
///   重建」），任一行变更即重发——「记一笔健身→仪表盘运动条即时更新」的
///   数据底座（§11.1 W5-6 验收线）；
/// - 墓碑行不参与（§5.1 删除行）；存钱目标 P1 未上线（§3.6，卡片渲染占位）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/fitness_service.dart' show kDefaultBodyWeightKg, kSettingBodyWeightKg;

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
