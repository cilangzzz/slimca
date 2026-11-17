/// 训练完成落库用例（§11.2 W14「组明细」、§3.5 健身计划、§5.5⑦⑨、§6.2）。
///
/// 复用抽象纪律（§10.4）：不重写任何持久化语义——
/// - outbox 复用 core_db `SyncOutboxWriter.enqueueRow`（业务行写后**同事务**
///   读回快照入队，§6.2 写路径纪律「一切出网必经之路」）；
/// - 投影复用 core_db `DaySummaryProjection`（burn 行入账后同事务重算当日
///   kcal_out/net_kcal，§5.6 重建规则）；
/// - MET 估算复用壳层 `estimateBurnKcal`（§3.5 估算式，±20% 口径标注在
///   UI 层承担）。
///
/// 行语义（§5.5⑦⑨）：会话 type=template_instance、source=plan（§5.5⑦ source
/// 枚举 manual/timer/plan）；entries.source 的 §5.2① 枚举（text/voice/photo/
/// receipt/chip/manual）无 plan → manual（「怎么来的=手填域」，计划来源由
/// 会话行 source 承载）；burn 行 payload 记 session_id + 模板参数（§5.2②）。
///
/// 骨架边界（remaining，诚实声明）：组记录训练中内存累积，结束时**单事务**
/// 整体落库（会话+事件+burn 行+N 组明细+outbox 全量同生共死，无半程孤儿行）；
/// 训练中进程被杀 → 进行中会话丢弃不落库——训练中逐组实时落库随前台服务
/// （后台长跑）接入后一并评估。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'fitness_service.dart' show estimateBurnKcal;
import 'workout_models.dart' show WorkoutSetEntry;

/// 同步真值表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String _kFitnessSessionsTable = 'fitness_sessions';
const String _kEntriesTable = 'entries';
const String _kEntryLinesTable = 'entry_lines';
const String _kExerciseSetsTable = 'exercise_sets';

/// 训练完成入参（控制器在 endWorkout 时构造；组记录为训练中累积快照）。
class WorkoutCompletionInput {
  const WorkoutCompletionInput({
    required this.planId,
    required this.planName,
    required this.date,
    required this.tzOffsetMin,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.weightKg,
    required this.sets,
  });

  /// 计划 id（§5.5⑦ plan_day_id 溯源：v1 无独立排期日表（§5.5⑦ 注），
  /// 暂存 plan id——排期日实体化后平移，remaining）。
  final String planId;

  /// 计划名（事件标题成分：『<计划名> 训练 N 分钟』，§5.2①）。
  final String planName;

  /// 归属日 `yyyy-MM-dd`（§5.1；取训练开始日）。
  final String date;

  /// 本地时区偏移（分钟，§5.1）。
  final int tzOffsetMin;

  /// 开始时刻 UTC ms（§5.5⑦ start_at）。
  final int startedAtMs;

  /// 结束时刻 UTC ms。
  final int endedAtMs;

  /// 身体档案体重 kg（§3.5 MET 估算输入；随会话落 settings 本地件）。
  final double weightKg;

  /// 已完成组（§5.5⑨ exercise_sets；空=未记组）。
  final List<WorkoutSetEntry> sets;

  /// 时长秒（≥1 防御；§5.5⑦ duration_s）。
  int get durationS {
    final seconds = ((endedAtMs - startedAtMs) / 1000).floor();
    return seconds < 1 ? 1 : seconds;
  }

  /// 时长分钟（向上取整；MET 估算口径，§3.5 kcal = MET × 体重kg × 时长h）。
  int get durationMinutes {
    final minutes = (durationS / 60).ceil();
    return minutes < 1 ? 1 : minutes;
  }
}

/// 训练完成落库用例（providers.dart 装配；训练会话控制器只经它写）。
class WorkoutLogService {
  WorkoutLogService({
    required db.AppDatabase database,
    required HlcClock clock,
    required db.DaySummaryProjection projection,
  })  : _db = database,
        _clock = clock,
        _projection = projection,
        _outbox = db.SyncOutboxWriter(database);

  final db.AppDatabase _db;
  final HlcClock _clock;
  final db.DaySummaryProjection _projection;
  final db.SyncOutboxWriter _outbox;

  static const Uuid _uuid = Uuid();

  /// 训练完成落库（§5.5⑦⑨、§6.2），返回会话 id。
  ///
  /// 单事务写：fitness_sessions（type=template_instance, source=plan）+
  /// entries(kind=fitness) + entry_lines(type=burn,out) + N×exercise_sets，
  /// 每行独立 HLC（行级同步 §5.7）并经 [db.SyncOutboxWriter.enqueueRow]
  /// 同事务读回入队；末尾投影重算当日（§5.6）。任一步失败整事务回滚
  /// （无半途 outbox，§6.2）。
  Future<String> completeWorkout(WorkoutCompletionInput input) async {
    final durationS = input.durationS;
    // template_instance 的 MET 口径：按力量训练中位 5.0 估算（§3.5 MET 表；
    // ±20% 口径标注由展示层承担）。
    final kcal = estimateBurnKcal(
      type: 'strength',
      weightKg: input.weightKg,
      durationMinutes: input.durationMinutes,
    );
    final ledgerId = await _kcalLedgerId();
    final sessionId = _uuid.v7();
    final entryId = _uuid.v7();
    final sessionMeta = _newMeta();
    final entryMeta = _newMeta();
    final lineMeta = _newMeta();

    final title = '${input.planName} 训练 ${input.durationMinutes} 分钟';
    final burnPayload = jsonEncode(<String, Object?>{
      'session_id': sessionId,
      'plan_id': input.planId,
      'source': 'plan',
      'type': 'template_instance',
      'met': 5.0,
      'weight_kg': input.weightKg,
      'duration_minutes': input.durationMinutes,
      'sets_count': input.sets.length,
    }..removeWhere((k, v) => v == null));

    await _db.transaction(() async {
      // ── fitness_sessions（§5.5⑦）──────────────────────────────────
      await _db.into(_db.fitnessSessions).insert(
            db.FitnessSession(
              id: sessionId,
              date: input.date,
              tzOffsetMin: input.tzOffsetMin,
              startAt: input.startedAtMs,
              durationS: durationS,
              type: 'template_instance',
              kcalBurn: kcal,
              entryId: entryId,
              source: 'plan',
              planDayId: input.planId,
              note: null,
              createdAt: sessionMeta.createdAt,
              updatedAt: sessionMeta.updatedAt,
              deletedAt: null,
              hlc: sessionMeta.hlc,
              revision: sessionMeta.revision,
              schemaVer: sessionMeta.schemaVer,
              deviceId: sessionMeta.deviceId,
            ),
          );
      await _outbox.enqueueRow(_kFitnessSessionsTable, sessionId);

      // ── entries（§5.2① kind=fitness、手动域 confirmed）─────────────
      // Companion.insert 口径：非空无默认列（id/date/kind/source/title/
      // status/公共列）为必填裸值；可空列为 Value 包装（§5.2①）。
      await _db.into(_db.entries).insertOnConflictUpdate(
            db.EntriesCompanion.insert(
              id: entryId,
              date: input.date,
              tzOffsetMin: input.tzOffsetMin,
              occurredAt: Value(input.startedAtMs),
              kind: 'fitness',
              source: 'manual',
              title: title,
              status: 'confirmed',
              createdAt: entryMeta.createdAt,
              updatedAt: entryMeta.updatedAt,
              hlc: entryMeta.hlc,
              revision: entryMeta.revision,
              schemaVer: Value(entryMeta.schemaVer),
              deviceId: entryMeta.deviceId,
            ),
          );
      await _outbox.enqueueRow(_kEntriesTable, entryId);

      // ── entry_lines（§5.2② burn=out；confidence 人工行空，§5.2②）───
      final lineId = _uuid.v7();
      await _db.into(_db.entryLines).insertOnConflictUpdate(
            db.EntryLinesCompanion.insert(
              id: lineId,
              entryId: entryId,
              type: 'burn',
              amount: kcal,
              direction: 'out',
              ledgerId: Value(ledgerId),
              payload: Value(burnPayload),
              status: 'active',
              createdAt: lineMeta.createdAt,
              updatedAt: lineMeta.updatedAt,
              hlc: lineMeta.hlc,
              revision: lineMeta.revision,
              schemaVer: Value(lineMeta.schemaVer),
              deviceId: lineMeta.deviceId,
            ),
          );
      await _outbox.enqueueRow(_kEntryLinesTable, lineId);

      // ── exercise_sets（§5.5⑨：weight ×10 定点；sort 全局组序）──────
      for (var i = 0; i < input.sets.length; i++) {
        final set = input.sets[i];
        final setMeta = _newMeta();
        final setId = _uuid.v7();
        await _db.into(_db.exerciseSets).insert(
              db.ExerciseSet(
                id: setId,
                sessionId: sessionId,
                exerciseRef: set.exerciseRef,
                weightKgX10:
                    set.weightKg == null ? 0 : (set.weightKg! * 10).round(),
                reps: set.reps,
                rpe: null,
                restS: set.restS > 0 ? set.restS : null,
                doneAt: set.doneAtMs,
                // sort=会话内全局组序，1 起（§5.5⑨「第几组」语义；与
                // feature_plan PlanGateway.logExerciseSet 的
                // sort=completedCount+1 同口径，两写路径一致）。
                sort: i + 1,
                createdAt: setMeta.createdAt,
                updatedAt: setMeta.updatedAt,
                deletedAt: null,
                hlc: setMeta.hlc,
                revision: setMeta.revision,
                schemaVer: setMeta.schemaVer,
                deviceId: setMeta.deviceId,
              ),
            );
        await _outbox.enqueueRow(_kExerciseSetsTable, setId);
      }

      // ── 投影联动（§5.6 重建规则）：burn 行入账后重算当日 ──────────────
      await _projection.recomputeDaySummary(input.date);
    });
    return sessionId;
  }

  // ── 内部辅助（与 FitnessService/PlanGateway 同口径）─────────────────

  /// 新行公共列（§5.1）：每行独立 HLC 发号（§6.3/§5.7 行级同步）、revision
  /// 本地自增起步=1。
  SyncMeta _newMeta() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return SyncMeta(
      createdAt: nowMs,
      updatedAt: nowMs,
      hlc: _clock.now().format(),
      revision: 1,
      schemaVer: kCurrentSchemaVer,
      deviceId: _clock.deviceId,
    );
  }

  /// 内置 kcal 账本 id（§5.4④ seed 保证恰一个；缺失返回 null——ledger_id
  /// 可空列，burn 行仍落账但聚合口径以行类型为准）。
  Future<String?> _kcalLedgerId() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals('kcal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first.id;
  }
}
