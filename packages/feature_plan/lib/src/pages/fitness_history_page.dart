/// 训练历史页（§11.2 W14 主线任务 4「训练历史（按日/按计划维度）」、
/// §3.5 健身记录与热量收支）。
///
/// 双维度视图（同一份 fitness_sessions 真值行，§5.5⑦）：
/// - **按日**：按归属日（date，§5.1 本地日历日）倒序分组——回看「哪天练了什么」；
/// - **按计划**：按 plan_day_id（§5.5⑦ 逻辑引用 fitness_plans）分组——回看
///   「某个计划练了多少次」；手动记录（无 plan_day_id）归入「未关联计划」。
///
/// 数据流（§10.1）：[allFitnessSessionsProvider]（reactive 全量会话流）+
/// [setCountBySessionProvider]（GROUP BY 组数徽标，单查询避免逐会话订阅）+
/// [fitnessPlansProvider]（计划名映射）。瓦片展示时长/消耗（±20% 口径标注，
/// §3.5 误差口径 P0）/组数。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fitness_met_table.dart';
import '../fitness_plan_models.dart';
import '../plan_providers.dart';

/// 历史维度档位（§11.2 W14 任务 4）。
enum _HistoryView { daily, byPlan }

/// 训练历史页。
class FitnessHistoryPage extends ConsumerStatefulWidget {
  const FitnessHistoryPage({super.key});

  @override
  ConsumerState<FitnessHistoryPage> createState() =>
      _FitnessHistoryPageState();
}

class _FitnessHistoryPageState extends ConsumerState<FitnessHistoryPage> {
  _HistoryView _view = _HistoryView.daily;

  /// 分组：按日（date 倒序，ISO 文本字典序即时间序，§5.1）或按计划。
  /// 返回（组头, 组内会话）序列；空列表=无记录。
  List<MapEntry<String, List<cdb.FitnessSession>>> _groups(
    List<cdb.FitnessSession> sessions,
    Map<String, String> planNameById,
  ) {
    final Map<String, List<cdb.FitnessSession>> grouped;
    if (_view == _HistoryView.daily) {
      grouped = <String, List<cdb.FitnessSession>>{};
      for (final session in sessions) {
        grouped.putIfAbsent(session.date, () => []).add(session);
      }
      final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
      return [
        for (final key in keys) MapEntry(key, grouped[key]!),
      ];
    }
    grouped = <String, List<cdb.FitnessSession>>{};
    for (final session in sessions) {
      final planId = session.planDayId;
      final header = planId == null
          ? '未关联计划'
          : (planNameById[planId] ?? '已删除计划');
      grouped.putIfAbsent(header, () => []).add(session);
    }
    final keys = grouped.keys.toList();
    return [for (final key in keys) MapEntry(key, grouped[key]!)];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final sessionsAsync = ref.watch(allFitnessSessionsProvider);
    final counts = ref.watch(setCountBySessionProvider).value;
    final plans = ref.watch(fitnessPlansProvider).value;
    final sessions = sessionsAsync.value;
    final planNameById = <String, String>{
      if (plans != null)
        for (final plan in plans) plan.id: plan.name,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('训练历史')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<_HistoryView>(
              segments: const [
                ButtonSegment(value: _HistoryView.daily, label: Text('按日')),
                ButtonSegment(
                    value: _HistoryView.byPlan, label: Text('按计划')),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
            ),
          ),
          Expanded(
            child: sessions == null || counts == null
                ? const Center(child: CircularProgressIndicator())
                : sessions.isEmpty
                    ? Center(
                        child: Text(
                          '暂无训练记录（§11.2 W14）',
                          style: TextStyle(
                              fontSize: 14, color: tokens.onSurfaceMuted),
                        ),
                      )
                    : Builder(builder: (context) {
                        // 分组一次成型（itemCount 与 itemBuilder 共用，
                        // 避免逐项重算，§9.5 列表纪律）。
                        final groups = _groups(sessions, planNameById);
                        return ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            return _GroupSection(
                              header: group.key,
                              sessions: group.value,
                              counts: counts,
                            );
                          },
                        );
                      }),
          ),
        ],
      ),
    );
  }
}

/// 单组（某日/某计划）小节：组头 + 会话瓦片。
class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.header,
    required this.sessions,
    required this.counts,
  });

  final String header;
  final List<cdb.FitnessSession> sessions;
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(header,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface)),
          const SizedBox(height: 8),
          for (final session in sessions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tokens.surfaceCard,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        session.type == kFitnessSessionTypeTemplateInstance
                            ? Icons.event_repeat
                            : Icons.fitness_center,
                        size: 20,
                        color: tokens.kcalOut,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_typeLabel(session.type)} · '
                              '${session.durationS ~/ 60} 分钟',
                              style: TextStyle(
                                  fontSize: 14, color: tokens.onSurface),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${session.date} ${_hhmmOf(session)} · '
                              '${session.kcalBurn} kcal（MET ±20%）· '
                              '${counts[session.id] ?? 0} 组',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.onSurfaceMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 会话类型标签（§5.5⑦ type 枚举；template_instance=计划训练，其余走
  /// 内置 MET 表类型标签；坏值防御直显，§7.4）。
  String _typeLabel(String wire) {
    if (wire == kFitnessSessionTypeTemplateInstance) return '计划训练';
    try {
      return FitnessType.fromWire(wire).label;
    } on ArgumentError {
      return wire;
    }
  }

  String _hhmmOf(cdb.FitnessSession session) {
    final startAt = session.startAt;
    if (startAt == null) return '—';
    final local = DateTime.fromMillisecondsSinceEpoch(startAt);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
