/// Drift 仓库实现（§10.4：接口在 core_domain，Drift 实现随 W2 app 接线落地）。
///
/// 写路径纪律（§6.2/§5.1/§6.5）：
/// - 业务行 + sync_outbox 行**同事务**写入（§6.2 第一步；W5-6 SyncEngine 出队）；
/// - 删除一律软删墓碑，不物理删（§5.1 删除行、§6.5「墓碑拒绝复活」）；
/// - money 行确认后不可变：原地改写必须抛 [MoneyLineImmutableException]，
///   唯一合法路径是 [DriftEntryLineRepository.supersede] 新增 correction 行
///   （§3.4 金额不可变、§6.5 money 行）。
///
/// 注：W5-6 同步层 pull 落库将以 `enqueueOutbox: false` 复用本实现（远端行
/// 回放不再入队，§6.2 读路径）；届时评估整体上移 core_db（§11 W5-6）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// 同步真值表名（§5.6⑯ outbox target_table 列；与 Drift 表 SQL 名一致）。
const String _kEntriesTable = 'entries';
const String _kEntryLinesTable = 'entry_lines';

/// 事件主干仓库（§5.2① entries）。
class DriftEntryRepository implements EntryRepository {
  DriftEntryRepository(this._db, {bool enqueueOutbox = true})
      : _enqueueOutbox = enqueueOutbox;

  final db.AppDatabase _db;

  /// 是否随写随入队 outbox（§6.2）；远端回放路径（W5-6 pull）传 false。
  final bool _enqueueOutbox;

  static const Uuid _uuid = Uuid();

  @override
  Future<Entry?> findById(String id) async {
    // 含墓碑行：调用方以 Entry.isDeleted 判断（§5.1 删除行）。
    final row = await (_db.select(_db.entries)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _entryFromRow(row);
  }

  @override
  Future<List<Entry>> findByDate(String date) async {
    final rows = await (_db.select(_db.entries)
          ..where((t) => t.date.equals(date))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_entryFromRow).toList();
  }

  @override
  Future<List<Entry>> findByDateRange(
    String startDate,
    String endDate, {
    List<EntryKind>? kinds,
  }) async {
    // date 为 TEXT 'yyyy-MM-dd'：字典序=时间序，BETWEEN 即闭区间（§5.1）。
    final rows = await (_db.select(_db.entries)
          ..where((t) {
            Expression<bool> filter = t.date.isBetweenValues(startDate, endDate);
            if (kinds != null && kinds.isNotEmpty) {
              filter = filter &
                  t.kind.isIn(kinds.map((k) => k.wire).toList());
            }
            return filter;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
    return rows.map(_entryFromRow).toList();
  }

  @override
  Future<void> upsert(Entry entry) async {
    await _db.transaction(() async {
      await _db
          .into(_db.entries)
          .insertOnConflictUpdate(_entryCompanion(entry));
      await _enqueue(
        entry.toJson(),
        targetTable: _kEntriesTable,
        rowId: entry.id,
        hlc: entry.meta.hlc,
        baseRevision: entry.meta.revision,
        createdAt: entry.meta.updatedAt,
      );
    });
  }

  @override
  Future<void> softDelete(String id, {required String hlc}) async {
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.entries)..where((t) => t.id.equals(id)))
              .getSingleOrNull();
      if (row == null) return; // 幂等：重复删除无害
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.entries)..where((t) => t.id.equals(id))).write(
        db.EntriesCompanion(
          deletedAt: Value(nowMs),
          updatedAt: Value(nowMs),
          hlc: Value(hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // 墓碑行快照入队（§5.1：deleted_at 置位即墓碑；双端对齐后 90 天物理 GC，
      // GC 先删子行再删父墓碑 §5.2② entry_id FK 说明）。
      final tombstone = _entryFromRow(
        await (_db.select(_db.entries)..where((t) => t.id.equals(id)))
            .getSingle(),
      );
      await _enqueue(
        tombstone.toJson(),
        targetTable: _kEntriesTable,
        rowId: id,
        hlc: hlc,
        baseRevision: tombstone.meta.revision,
        createdAt: tombstone.meta.updatedAt,
      );
    });
  }

  @override
  Stream<List<Entry>> watchByDate(String date) {
    // 响应式按日查询：仪表盘/流水由 reactive stream 直驱（§10.1 Drift 行）。
    return (_db.select(_db.entries)
          ..where((t) => t.date.equals(date) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_entryFromRow).toList());
  }

  Entry _entryFromRow(db.Entry row) => Entry(
        id: row.id,
        date: row.date,
        tzOffsetMin: row.tzOffsetMin,
        occurredAt: row.occurredAt,
        kind: EntryKind.fromWire(row.kind),
        source: EntrySource.fromWire(row.source),
        title: row.title,
        note: row.note,
        status: EntryStatus.fromWire(row.status),
        aiParseId: row.aiParseId,
        meta: SyncMeta(
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          hlc: row.hlc,
          revision: row.revision,
          schemaVer: row.schemaVer,
          deviceId: row.deviceId,
        ),
      );

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

  Future<void> _enqueue(
    Map<String, Object?> snapshot, {
    required String targetTable,
    required String rowId,
    required String hlc,
    required int baseRevision,
    required int createdAt,
  }) async {
    if (!_enqueueOutbox) return;
    await _db.into(_db.syncOutbox).insert(
          db.SyncOutboxCompanion.insert(
            id: _uuid.v7(),
            targetTable: targetTable,
            rowId: rowId,
            op: OutboxOp.upsert.wire,
            payload: jsonEncode(snapshot),
            baseRevision: Value(baseRevision),
            hlc: hlc,
            createdAt: createdAt,
          ),
        );
  }
}

/// 产出行（facet 行）仓库（§5.2② entry_lines；§5.3 拆行同步正确性）。
class DriftEntryLineRepository implements EntryLineRepository {
  DriftEntryLineRepository(this._db, {bool enqueueOutbox = true})
      : _enqueueOutbox = enqueueOutbox;

  final db.AppDatabase _db;

  /// 是否随写随入队 outbox（§6.2）；远端回放路径（W5-6 pull）传 false。
  final bool _enqueueOutbox;

  static const Uuid _uuid = Uuid();

  @override
  Future<EntryLine?> findById(String id) async {
    final row =
        await (_db.select(_db.entryLines)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _lineFromRow(row);
  }

  @override
  Future<List<EntryLine>> findByEntryId(String entryId) async {
    // 索引 (entry_id)（§5.2②）；含墓碑/被修正行，调用方按 status 过滤。
    final rows = await (_db.select(_db.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get();
    return rows.map(_lineFromRow).toList();
  }

  @override
  Future<List<EntryLine>> findByDate(String date) async {
    // 经 entries.date 关联（§5.6⑬ day_summary 重算入口）。
    final query = _db.select(_db.entryLines).join([
      innerJoin(_db.entries, _db.entries.id.equalsExp(_db.entryLines.entryId)),
    ])..where(_db.entries.date.equals(date));
    final rows = await query.get();
    return rows
        .map((row) => _lineFromRow(row.readTable(_db.entryLines)))
        .toList();
  }

  @override
  Future<List<EntryLine>> findActiveByLedger(String ledgerId) async {
    // 索引 (ledger_id, updated_at)（§5.2②）；kcal 与钱账本共用本入口（§2.1③）。
    final rows = await (_db.select(_db.entryLines)
          ..where((t) =>
              t.ledgerId.equals(ledgerId) &
              t.status.equals(LineStatus.active.wire) &
              t.deletedAt.isNull()))
        .get();
    return rows.map(_lineFromRow).toList();
  }

  @override
  Future<List<EntryLine>> findByCorrectionOf(String originalLineId) async {
    // 修正链查询：谁引用了旧行（索引 (correction_of)，§5.2②）。
    final rows = await (_db.select(_db.entryLines)
          ..where((t) => t.correctionOf.equals(originalLineId)))
        .get();
    return rows.map(_lineFromRow).toList();
  }

  @override
  Future<void> upsert(EntryLine line) async {
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.entryLines)..where((t) => t.id.equals(line.id)))
              .getSingleOrNull();
      if (existing != null) {
        _guardMoneyImmutability(await _parentStatus(existing.entryId), existing, line);
      }
      await _db
          .into(_db.entryLines)
          .insertOnConflictUpdate(_lineCompanion(line));
      await _enqueue(
        line.toJson(),
        targetTable: _kEntryLinesTable,
        rowId: line.id,
        hlc: line.meta.hlc,
        baseRevision: line.meta.revision,
        createdAt: line.meta.updatedAt,
      );
    });
  }

  @override
  Future<void> supersede(String oldLineId, EntryLine correction) async {
    await _db.transaction(() async {
      final old =
          await (_db.select(_db.entryLines)..where((t) => t.id.equals(oldLineId)))
              .getSingleOrNull();
      if (old == null) {
        throw StateError(
          'supersede：被修正行 $oldLineId 不存在（§5.2② correction_of）',
        );
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // 旧行只翻转状态列，金额事实不改写（§6.5 money 行不可变）；同一逻辑
      // 事件共用 correction 的 HLC（§6.3 一次发号可覆盖同事件多行）。
      await (_db.update(_db.entryLines)
            ..where((t) => t.id.equals(oldLineId)))
          .write(
        db.EntryLinesCompanion(
          status: const Value('superseded'),
          updatedAt: Value(nowMs),
          hlc: Value(correction.meta.hlc),
          revision: Value(old.revision + 1),
        ),
      );
      // 修正=新增行（§2.1②/§5.2②）：correction_of 指向旧行，历史永不改写。
      await _db
          .into(_db.entryLines)
          .insertOnConflictUpdate(_lineCompanion(correction));
      await _enqueue(
        correction.toJson(),
        targetTable: _kEntryLinesTable,
        rowId: correction.id,
        hlc: correction.meta.hlc,
        baseRevision: correction.meta.revision,
        createdAt: correction.meta.updatedAt,
      );
      final flipped = _lineFromRow(
        await (_db.select(_db.entryLines)..where((t) => t.id.equals(oldLineId)))
            .getSingle(),
      );
      await _enqueue(
        flipped.toJson(),
        targetTable: _kEntryLinesTable,
        rowId: flipped.id,
        hlc: correction.meta.hlc,
        baseRevision: flipped.meta.revision,
        createdAt: flipped.meta.updatedAt,
      );
    });
  }

  /// 金额不可变闸门（§3.4/§6.5）：目标为已确认的 money 行（父事件非 draft）
  /// 时，禁止经 upsert 改写 type/amount/direction/status——唯一合法路径是
  /// supersede 新增 correction 行。同值刷新（同步层 LWW 回写）放行。
  void _guardMoneyImmutability(
    String? parentStatus,
    db.EntryLine existing,
    EntryLine next,
  ) {
    if (existing.type != LineType.money.wire) return;
    final factChanged = next.type.wire != existing.type ||
        next.amount != existing.amount ||
        next.direction.wire != existing.direction ||
        next.status.wire != existing.status;
    if (!factChanged) return;
    // 父行缺失视为已确认（pull 依赖序场景从严，§6.2）。
    final confirmed = parentStatus == null || parentStatus != EntryStatus.draft.wire;
    if (confirmed) {
      throw MoneyLineImmutableException(next.id);
    }
  }

  Future<String?> _parentStatus(String entryId) async {
    final parent =
        await (_db.select(_db.entries)..where((t) => t.id.equals(entryId)))
            .getSingleOrNull();
    return parent?.status;
  }

  EntryLine _lineFromRow(db.EntryLine row) => EntryLine(
        id: row.id,
        entryId: row.entryId,
        type: LineType.fromWire(row.type),
        amount: row.amount,
        direction: LineDirection.fromWire(row.direction),
        ledgerId: row.ledgerId,
        categoryId: row.categoryId,
        currency: row.currency,
        confidence: row.confidence,
        payload: row.payload,
        correctionOf: row.correctionOf,
        status: LineStatus.fromWire(row.status),
        meta: SyncMeta(
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          hlc: row.hlc,
          revision: row.revision,
          schemaVer: row.schemaVer,
          deviceId: row.deviceId,
        ),
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

  Future<void> _enqueue(
    Map<String, Object?> snapshot, {
    required String targetTable,
    required String rowId,
    required String hlc,
    required int baseRevision,
    required int createdAt,
  }) async {
    if (!_enqueueOutbox) return;
    await _db.into(_db.syncOutbox).insert(
          db.SyncOutboxCompanion.insert(
            id: _uuid.v7(),
            targetTable: targetTable,
            rowId: rowId,
            op: OutboxOp.upsert.wire,
            payload: jsonEncode(snapshot),
            baseRevision: Value(baseRevision),
            hlc: hlc,
            createdAt: createdAt,
          ),
        );
  }
}
