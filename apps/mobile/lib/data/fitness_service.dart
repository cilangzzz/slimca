/// 健身手动记录写路径用例（§11.1 W5-6「健身手动记录进仪表盘与净热量」、
/// §3.5 健身记录与热量收支、§5.5⑦ fitness_sessions）。
///
/// 落库规则（逐条对文档）：
/// - 会话与事件同事务联动（§5.5⑦ entry_id 列说明）：fitness_sessions 行 +
///   entries(kind=fitness, source=manual) + entry_lines(type=burn,
///   direction=out) 一个事务落库，burn 行 payload 记 session_id——消耗行与
///   钱/热量行共用同一 facet 行同步模型（§2.2/§5.7）；
/// - kcal = MET × 体重kg × 时长h（§3.5 手动记录估算式；MET 表随类型取
///   简表，UI 按 ±20% 口径标注，§3.5 误差口径标注 P0）；
/// - 业务行 + sync_outbox 同事务写入（§6.2 写路径纪律；W5-6 SyncEngine
///   出队后上送——见 lib/data/drift_repositories.dart 文件头注记）；
/// - 身体档案体重随 settings 本地件落库（§3.5 身体档案 P0「体重设置
///   （settings），MET 估算依赖」；settings 为本地件、永不同步 §5.6⑲）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/providers.dart';

/// settings 键：身体档案体重 kg（§5.6⑲ settings 内容清单「身体档案（体重）」；
/// value 一律 JSON——存 JSON number 文本）。
const String kSettingBodyWeightKg = 'body_weight_kg';

/// 身体档案缺省体重（kg）：未设置时的 MET 估算基线；设置后由 settings 承担
/// （§3.5 身体档案 P0）。缺省值仅作估算输入，不写库——首次保存才落 settings。
const double kDefaultBodyWeightKg = 60;

/// 同步真值表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String _kFitnessSessionsTable = 'fitness_sessions';
const String _kEntriesTable = 'entries';
const String _kEntryLinesTable = 'entry_lines';

/// 健身会话类型 wire 值与中文标签（§5.5⑦ type 列：
/// strength/cardio/hiit/other；template_instance 随 P1 计划接入）。
const Map<String, String> kFitnessTypeLabels = {
  'strength': '力量',
  'cardio': '有氧',
  'hiit': 'HIIT',
  'other': '其他',
};

/// W5-6 初版 MET 简表（§3.5「MET 表消耗估算」；kg/h 口径。数值取 Compendium
/// 常用中位近似，±20% 口径在 UI 标注；P1 动作库落地后按动作细分）。
const Map<String, double> kMetTable = {
  'strength': 5.0, // 力量（中强度阻力训练）
  'cardio': 7.0, // 有氧（慢跑/骑行中位）
  'hiit': 10.0, // HIIT（高强度间歇）
  'other': 4.0, // 其他（快走/拉伸等轻活动）
};

/// MET 估算（§3.5：kcal = MET × 体重kg × 时长h；四舍五入回 INTEGER，§5.1）。
int estimateBurnKcal({
  required String type,
  required double weightKg,
  required int durationMinutes,
}) {
  final met = kMetTable[type] ?? kMetTable['other']!;
  final hours = durationMinutes / 60;
  return (met * weightKg * hours).round();
}

/// 用例服务 provider：主库（事务壳）+ HLC 时钟（§6.3 发号）。
final fitnessServiceProvider = Provider<FitnessService>((ref) {
  return FitnessService(
    ref.watch(appDatabaseProvider),
    ref.watch(hlcClockProvider),
  );
});

/// 健身手动记录入参（§5.5⑦）。
class FitnessSessionInput {
  const FitnessSessionInput({
    required this.date,
    required this.type,
    required this.durationMinutes,
    required this.kcalBurn,
    required this.weightKg,
    this.note,
    this.startAt,
  });

  /// 归属日 `yyyy-MM-dd`（§5.1 本地日历日，一切聚合按 date 分组）。
  final String date;

  /// 类型 wire 值（§5.5⑦ type；kFitnessTypeLabels 的键）。
  final String type;

  /// 时长（分钟，UI 输入口径；落库存秒 §5.5⑦ duration_s）。
  final int durationMinutes;

  /// MET 估算消耗（kcal，[estimateBurnKcal] 产出；§5.1 热量一律 INTEGER）。
  final int kcalBurn;

  /// 身体档案体重（kg）——同事务写入 settings 身体档案（§3.5）。
  final double weightKg;

  /// 备注（§5.5⑦ note；非空时兼作事件标题）。
  final String? note;

  /// 开始时刻 UTC ms（缺省=保存时刻，§5.5⑦ start_at 可空列）。
  final int? startAt;
}

/// 健身手动记录用例（§3.5/§5.5⑦：记一笔健身 → 仪表盘运动条与净热量即时更新）。
class FitnessService {
  FitnessService(this._db, this._clock);

  final db.AppDatabase _db;
  final HlcClock _clock;

  static const Uuid _uuid = Uuid();

  /// 新建健身手动记录，返回事件 id（entries.id）。
  Future<String> saveSession(FitnessSessionInput input) async {
    final sessionMeta = _newMeta();
    final session = db.FitnessSession(
      id: _uuid.v7(),
      date: input.date,
      tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
      startAt: input.startAt ?? DateTime.now().millisecondsSinceEpoch,
      durationS: input.durationMinutes * 60,
      type: input.type,
      kcalBurn: input.kcalBurn,
      // entryId 先置 null，事务前由 copyWith 回填 linkedSession（§5.5⑦ 联动）。
      entryId: null,
      source: 'manual',
      planDayId: null,
      note: input.note,
      createdAt: sessionMeta.createdAt,
      updatedAt: sessionMeta.updatedAt,
      deletedAt: null,
      hlc: sessionMeta.hlc,
      revision: sessionMeta.revision,
      schemaVer: sessionMeta.schemaVer,
      deviceId: sessionMeta.deviceId,
    );

    // 事件主干（§5.2① kind=fitness、source=manual、手动路径 status=confirmed）。
    final title = _deriveTitle(input);
    final entry = Entry(
      id: _uuid.v7(),
      date: input.date,
      tzOffsetMin: session.tzOffsetMin,
      occurredAt: session.startAt,
      kind: EntryKind.fitness,
      source: EntrySource.manual,
      title: title,
      note: input.note,
      status: EntryStatus.confirmed,
      aiParseId: null,
      meta: _newMeta(),
    );

    // 消耗行（§5.2② burn=out；payload 记 session_id 与 MET 参数，§5.5⑦）。
    final line = EntryLine(
      id: _uuid.v7(),
      entryId: entry.id,
      type: LineType.burn,
      amount: input.kcalBurn,
      direction: LineDirection.outcome,
      ledgerId: await _kcalLedgerId(),
      categoryId: null,
      currency: null,
      // 人工估算行无 AI 置信度（§5.2② confidence AI 产出行必填，人工行空）。
      confidence: null,
      payload: jsonEncode(<String, Object?>{
        'session_id': session.id,
        'type': input.type,
        'met': kMetTable[input.type] ?? kMetTable['other'],
        'weight_kg': input.weightKg,
        'duration_minutes': input.durationMinutes,
      }),
      correctionOf: null,
      status: LineStatus.active,
      meta: _newMeta(),
    );

    final linkedSession = session.copyWith(entryId: Value(entry.id));

    // 单事务：会话 + 主干 + burn 行 + 三表 outbox + 身体档案 settings
    // （§6.2 写路径纪律；§5.5⑦ 会话落库同事务生成 entry+burn 行）。
    await _db.transaction(() async {
      await _db.into(_db.fitnessSessions).insert(linkedSession);
      await _db.into(_db.entries).insertOnConflictUpdate(
            _entryCompanion(entry),
          );
      await _db.into(_db.entryLines).insertOnConflictUpdate(
            _lineCompanion(line),
          );
      await _enqueueSession(linkedSession);
      await _enqueueRow(
        entry.toJson(),
        table: _kEntriesTable,
        rowId: entry.id,
        meta: entry.meta,
      );
      await _enqueueRow(
        line.toJson(),
        table: _kEntryLinesTable,
        rowId: line.id,
        meta: line.meta,
      );
      await _db.into(_db.settings).insertOnConflictUpdate(
            db.Setting(
              key: kSettingBodyWeightKg,
              value: jsonEncode(input.weightKg),
            ),
          );
    });
    return entry.id;
  }

  // ── 内部装配 ────────────────────────────────────────────────────

  /// 事件标题（§5.2① title 一句话描述）：备注优先，缺省「类型 + 时长」。
  String _deriveTitle(FitnessSessionInput input) {
    final note = input.note?.trim();
    if (note != null && note.isNotEmpty) return note;
    final label = kFitnessTypeLabels[input.type] ?? '健身';
    return '$label ${input.durationMinutes} 分钟';
  }

  /// 新行公共列（§5.1）：HLC 新发号（§6.3 单调）、revision 本地自增起步=1。
  SyncMeta _newMeta() {
    final hlc = _clock.now();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return SyncMeta(
      createdAt: nowMs,
      updatedAt: nowMs,
      hlc: hlc.format(),
      revision: 1,
      schemaVer: kCurrentSchemaVer,
      deviceId: _clock.deviceId,
    );
  }

  /// 内置 kcal 账本 id（§5.2② kcal 行归集内置 kcal 账本；burn 行同族挂同一
  /// 账本。seed 保证恰一个；防御路径下缺失返回 null——ledger_id 可空列）。
  Future<String?> _kcalLedgerId() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals('kcal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first.id;
  }

  db.EntriesCompanion _entryCompanion(Entry e) => db.EntriesCompanion(
        id: Value(e.id),
        date: Value(e.date),
        tzOffsetMin: Value(e.tzOffsetMin),
        occurredAt: Value(e.occurredAt),
        kind: Value(e.kind.wire),
        source: Value(e.source.wire),
        title: Value(e.title),
        note: Value(e.note),
        status: Value(e.status.wire),
        aiParseId: Value(e.aiParseId),
        createdAt: Value(e.meta.createdAt),
        updatedAt: Value(e.meta.updatedAt),
        deletedAt: Value(e.meta.deletedAt),
        hlc: Value(e.meta.hlc),
        revision: Value(e.meta.revision),
        schemaVer: Value(e.meta.schemaVer),
        deviceId: Value(e.meta.deviceId),
      );

  db.EntryLinesCompanion _lineCompanion(EntryLine l) => db.EntryLinesCompanion(
        id: Value(l.id),
        entryId: Value(l.entryId),
        type: Value(l.type.wire),
        amount: Value(l.amount),
        direction: Value(l.direction.wire),
        ledgerId: Value(l.ledgerId),
        categoryId: Value(l.categoryId),
        currency: Value(l.currency),
        confidence: Value(l.confidence),
        payload: Value(l.payload),
        correctionOf: Value(l.correctionOf),
        status: Value(l.status.wire),
        createdAt: Value(l.meta.createdAt),
        updatedAt: Value(l.meta.updatedAt),
        deletedAt: Value(l.meta.deletedAt),
        hlc: Value(l.meta.hlc),
        revision: Value(l.meta.revision),
        schemaVer: Value(l.meta.schemaVer),
        deviceId: Value(l.meta.deviceId),
      );

  /// 会话行快照入队（§5.6⑯ payload=行快照 JSON；字段名与 §5.5⑦ 列清单同构）。
  Future<void> _enqueueSession(db.FitnessSession session) async {
    await _db.into(_db.syncOutbox).insert(
          db.SyncOutboxCompanion.insert(
            id: _uuid.v7(),
            targetTable: _kFitnessSessionsTable,
            rowId: session.id,
            op: OutboxOp.upsert.wire,
            payload: jsonEncode(<String, Object?>{
              'id': session.id,
              'date': session.date,
              'tz_offset_min': session.tzOffsetMin,
              'start_at': session.startAt,
              'duration_s': session.durationS,
              'type': session.type,
              'kcal_burn': session.kcalBurn,
              'entry_id': session.entryId,
              'source': session.source,
              'plan_day_id': session.planDayId,
              'note': session.note,
              'created_at': session.createdAt,
              'updated_at': session.updatedAt,
              'deleted_at': session.deletedAt,
              'hlc': session.hlc,
              'revision': session.revision,
              'schema_ver': session.schemaVer,
              'device_id': session.deviceId,
            }),
            hlc: session.hlc,
            createdAt: session.updatedAt,
          ),
        );
  }

  /// entries / entry_lines 行快照入队（§6.2；payload=实体 toJson 同构快照）。
  Future<void> _enqueueRow(
    Map<String, Object?> snapshot, {
    required String table,
    required String rowId,
    required SyncMeta meta,
  }) async {
    await _db.into(_db.syncOutbox).insert(
          db.SyncOutboxCompanion.insert(
            id: _uuid.v7(),
            targetTable: table,
            rowId: rowId,
            op: OutboxOp.upsert.wire,
            payload: jsonEncode(snapshot),
            baseRevision: Value(meta.revision),
            hlc: meta.hlc,
            createdAt: meta.updatedAt,
          ),
        );
  }
}
