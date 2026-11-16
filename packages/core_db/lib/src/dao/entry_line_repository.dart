/// EntryLineRepository 的 Drift 实现（§10.4：接口在 core_domain、实现在 core_db）。
///
/// 实现契约：
/// - **supersede 事务语义**（§5.2② correction_of 行、§2.1②）：修正=新增行，
///   同一事务内写入修正行（correction_of 指向旧行）并把旧行 status 置
///   superseded；事件行 confirmed → edited 联动（§5.2① status 行「含修正」）。
///   corrections 审计行由调用方按 §5.6⑮ 落库（本方法无从得知字段级前后值）。
/// - **金额不可变的强制点**（§3.4「不可变性由仓库层强制」、§6.5 money 行）：
///   父事件已确认（confirmed/edited）的 money 行，upsert 只允许刷新 §5.1
///   公共列（updated_at/hlc/revision/deleted_at 等）；任何业务字段（amount/
///   type/direction/ledger/category/currency/status/…）变化即抛
///   [domain.MoneyLineImmutableException]，唯一合法路径是 [supersede]。
///   draft 事件下的行不设防（§6.5：draft 时 AI 字段可被新解析覆盖）。
/// - 投影联动（§5.6）：行变更重算所属事件归属日的 day_summary（§5.1 按
///   entries.date 归日，杜绝 UTC 错日）。
library;

import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/drift.dart';

import '../app_database.dart';
import 'day_summary_projection.dart';

/// 产出行（facet 行）仓库（§5.2② entry_lines）的 Drift 实现。
class DriftEntryLineRepository implements domain.EntryLineRepository {
  DriftEntryLineRepository(this._db, {this.projection});

  final AppDatabase _db;

  /// 非空时：行写后立即 markDirty + 重算所属事件日期投影（§5.6）。
  final DaySummaryProjection? projection;

  @override
  Future<domain.EntryLine?> findById(String id) async {
    final row = await (_db.select(_db.entryLines)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  @override
  Future<List<domain.EntryLine>> findByEntryId(String entryId) async {
    // 「一件事的全部产出行」：含 active/superseded/void 全状态（修正链
    // 展示需要历史），仅排除行自身墓碑（§5.2② id 行 + §5.1 公共列）。
    final query = _db.select(_db.entryLines)
      ..where((t) => t.entryId.equals(entryId) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row)];
  }

  @override
  Future<List<domain.EntryLine>> findByDate(String date) async {
    // §5.2② 接口注明本方法是「day_summary 重算入口」：只返回计入聚合的行
    // ——active 且行/事件均未软删，经 entries.date 关联归日（§5.1）。
    final query = _selectCountingLines()
      ..where(_db.entries.date.equals(date))
      ..orderBy([
        OrderingTerm.asc(_db.entryLines.createdAt),
        OrderingTerm.asc(_db.entryLines.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row.readTable(_db.entryLines))];
  }

  @override
  Future<List<domain.EntryLine>> findActiveByLedger(String ledgerId) async {
    // 账本视角的活跃行（索引 (ledger_id, updated_at)，§5.2②）：kcal 账本与
    // 钱账本共用入口（§2.1③）。所属事件已软删的行不再计入（§5.1 墓碑语义）。
    final query = _selectCountingLines()
      ..where(_db.entryLines.ledgerId.equals(ledgerId))
      ..orderBy([
        OrderingTerm.asc(_db.entryLines.updatedAt),
        OrderingTerm.asc(_db.entryLines.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row.readTable(_db.entryLines))];
  }

  @override
  Future<List<domain.EntryLine>> findByCorrectionOf(String originalLineId) async {
    // 修正链查询（索引 (correction_of)，§5.2②）：谁引用了旧行。
    final query = _db.select(_db.entryLines)
      ..where((t) => t.correctionOf.equals(originalLineId))
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row)];
  }

  @override
  Future<void> upsert(domain.EntryLine line) {
    return _db.transaction(() async {
      final parent = await _requireParent(line.entryId);
      final existing = await (_db.select(_db.entryLines)
            ..where((t) => t.id.equals(line.id)))
          .getSingleOrNull();
      if (existing != null) {
        _guardMoneyImmutability(line, existing, parent);
      }
      await _db.into(_db.entryLines).insertOnConflictUpdate(_toCompanion(line));
      // 投影联动（§5.6）：传事件 id（_requireParent 解析归属日），与 supersede
      // 同口径——勿传 date，否则 _requireParent 会拿日期查 entries.id。
      await _recomputeDay(line.entryId);
    });
  }

  @override
  Future<void> supersede(String oldLineId, domain.EntryLine correction) {
    return _db.transaction(() async {
      final old = await (_db.select(_db.entryLines)
            ..where((t) => t.id.equals(oldLineId)))
          .getSingleOrNull();
      if (old == null) {
        throw StateError('supersede: 被修正行不存在 $oldLineId（§5.2② correction_of）');
      }
      if (old.status != 'active') {
        // 修正链线性：每条修正引用紧邻的上一版（§5.2②）。
        throw StateError('supersede: 仅 active 行可被修正，$oldLineId 当前为 ${old.status}');
      }
      var corrected = correction;
      if (corrected.correctionOf == null) {
        corrected = corrected.copyWith(correctionOf: oldLineId);
      }
      if (corrected.correctionOf != oldLineId) {
        throw ArgumentError.value(
          corrected.correctionOf,
          'correction.correctionOf',
          '必须指向被修正行 $oldLineId（§5.2② correction_of）',
        );
      }
      if (corrected.entryId != old.entryId) {
        throw ArgumentError(
          '修正行必须属于同一事件 ${old.entryId}（§5.2② entry_id）',
        );
      }
      if (corrected.status != domain.LineStatus.active) {
        throw ArgumentError.value(
          corrected.status,
          'correction.status',
          '修正新行必须为 active（§5.2② status 行）',
        );
      }
      if (corrected.isDeleted) {
        throw ArgumentError('修正新行不允许携带软删墓碑（§5.1 删除行）');
      }

      // 同一事务两步（§5.2②「修正=新增行，旧行 status→superseded」）：
      // ① 旧行置 superseded，戳取修正行的 hlc/updated_at（同一次用户操作）；
      // ② 新修正行落库。
      await (_db.update(_db.entryLines)
            ..where((t) => t.id.equals(oldLineId)))
          .write(EntryLinesCompanion(
        status: const Value('superseded'),
        updatedAt: Value(corrected.meta.updatedAt),
        hlc: Value(_canonicalHlc(corrected.meta.hlc)),
        revision: Value(old.revision + 1),
      ));
      await _db.into(_db.entryLines).insertOnConflictUpdate(_toCompanion(corrected));

      // 事件状态联动：confirmed → edited（含修正，§5.2① status 行）。
      // draft 保持 draft（AI 字段仍可被新解析覆盖，§6.5）；edited 保持 edited。
      final parent = await (_db.select(_db.entries)
            ..where((t) => t.id.equals(old.entryId)))
          .getSingleOrNull();
      if (parent != null && parent.status == 'confirmed') {
        await (_db.update(_db.entries)
              ..where((t) => t.id.equals(old.entryId)))
            .write(EntriesCompanion(
          status: const Value('edited'),
          updatedAt: Value(corrected.meta.updatedAt),
          hlc: Value(_canonicalHlc(corrected.meta.hlc)),
          revision: Value(parent.revision + 1),
        ));
      }

      await _recomputeDay(old.entryId);
    });
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────

  /// 计入聚合口径的行查询骨架（active + 行/事件未删；join 供 date/账本过滤）。
  JoinedSelectStatement _selectCountingLines() {
    return _db.select(_db.entryLines).join([
      innerJoin(
        _db.entries,
        _db.entries.id.equalsExp(_db.entryLines.entryId),
        useColumns: false,
      ),
    ])
      ..where(_db.entryLines.status.equals('active') &
          _db.entryLines.deletedAt.isNull() &
          _db.entries.deletedAt.isNull());
  }

  Future<Entry> _requireParent(String entryId) async {
    final parent = await (_db.select(_db.entries)
          ..where((t) => t.id.equals(entryId)))
        .getSingleOrNull();
    if (parent == null) {
      // entry_lines.entry_id FK（§5.2②）：数据库层也会拦截，这里给出可读错误。
      throw StateError('entry_lines 的父事件不存在：$entryId（§5.2② entry_id FK）');
    }
    return parent;
  }

  /// 金额不可变守卫（§3.4/§6.5）：父事件已确认的 money 行禁止原地改业务
  /// 字段；仅 §5.1 公共列刷新（同步回写 revision/acked 回执等）放行。
  void _guardMoneyImmutability(
    domain.EntryLine incoming,
    EntryLine existing,
    Entry parent,
  ) {
    if (existing.type != 'money') {
      return; // 仅 money 行受保护（§6.5 money 行）
    }
    if (parent.status == 'draft') {
      return; // draft：AI 字段可被新解析覆盖（§6.5 entries 行）
    }
    final factsDiffer =
        incoming.entryId != existing.entryId ||
            incoming.type.wire != existing.type ||
            incoming.amount != existing.amount ||
            incoming.direction.wire != existing.direction ||
            incoming.ledgerId != existing.ledgerId ||
            incoming.categoryId != existing.categoryId ||
            incoming.currency != existing.currency ||
            incoming.confidence != existing.confidence ||
            incoming.payload != existing.payload ||
            incoming.correctionOf != existing.correctionOf ||
            incoming.status.wire != existing.status;
    if (factsDiffer) {
      throw domain.MoneyLineImmutableException(existing.id);
    }
  }

  Future<void> _recomputeDay(String entryId) async {
    final target = projection;
    if (target == null) {
      return;
    }
    final parent = await _requireParent(entryId);
    await target.markDayDirty(parent.date);
    await target.recomputeDaySummary(parent.date);
  }

  domain.EntryLine _rowToDomain(EntryLine row) => domain.EntryLine(
        id: row.id,
        entryId: row.entryId,
        type: domain.LineType.fromWire(row.type),
        amount: row.amount,
        direction: domain.LineDirection.fromWire(row.direction),
        ledgerId: row.ledgerId,
        categoryId: row.categoryId,
        currency: row.currency,
        confidence: row.confidence,
        payload: row.payload,
        correctionOf: row.correctionOf,
        status: domain.LineStatus.fromWire(row.status),
        meta: domain.SyncMeta(
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
          deletedAt: row.deletedAt,
          hlc: domain.Hlc.parse(row.hlc).format(),
          revision: row.revision,
          schemaVer: row.schemaVer,
          deviceId: row.deviceId,
        ),
      );

  EntryLinesCompanion _toCompanion(domain.EntryLine l) =>
      EntryLinesCompanion.insert(
        createdAt: l.meta.createdAt,
        updatedAt: l.meta.updatedAt,
        deletedAt: Value(l.meta.deletedAt),
        hlc: _canonicalHlc(l.meta.hlc),
        revision: l.meta.revision,
        schemaVer: Value(l.meta.schemaVer),
        deviceId: l.meta.deviceId,
        id: l.id,
        entryId: l.entryId,
        type: l.type.wire,
        amount: l.amount,
        direction: l.direction.wire,
        ledgerId: Value(l.ledgerId),
        categoryId: Value(l.categoryId),
        currency: Value(l.currency),
        confidence: Value(l.confidence),
        payload: Value(l.payload),
        correctionOf: Value(l.correctionOf),
        status: l.status.wire,
      );

  /// hlc 规范化（§6.3）：定宽校验 + 节点段大写，保证字典序=全序不被大小写破坏。
  String _canonicalHlc(String raw) => domain.Hlc.parse(raw).format();
}
