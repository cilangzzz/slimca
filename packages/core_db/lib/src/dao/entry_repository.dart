/// EntryRepository 的 Drift 实现（§10.4：接口在 core_domain、实现在 core_db）。
///
/// 实现契约（§5.2① 接口文档、§5.1、§6.3、§6.5）：
/// - 删除一律软删墓碑，不物理删；墓碑拒绝复活：upsert 命中已删行时保留
///   deleted_at（§6.5 删除行「删后编辑保持删除胜出」）；
/// - 写入携带 §5.1 公共列与定宽 HLC；读侧以 `Hlc.parse` 校验编码，坏数据
///   不进领域层（§6.3 字典序=全序是 LWW 与同步游标的基石）；
/// - 查询形态对齐索引：findByDateRange 的 kinds 过滤生成
///   `kind IN (…) AND date BETWEEN …`，命中 (kind, date) 复合索引（§5.2①）；
/// - 行级 LWW 冲突仲裁属于 SyncEngine.resolve（§6.5），本仓库不做新旧快照
///   裁决，只保证落库语义；
/// - 可选注入 [DaySummaryProjection]：写后同事务重算受影响日期的投影，
///   支撑 W2 验收「手动记一笔→仪表盘环/支出卡即时更新」（§11.1 W2、§5.6
///   重建规则）；未注入时由上层编排。
library;

import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/drift.dart';

import '../app_database.dart';
import 'day_summary_projection.dart';

/// 事件主干仓库（§5.2① entries）的 Drift 实现。
class DriftEntryRepository implements domain.EntryRepository {
  DriftEntryRepository(this._db, {this.projection});

  final AppDatabase _db;

  /// 非空时：写后立即 markDirty + 重算受影响日期投影（§5.6 重建规则）。
  final DaySummaryProjection? projection;

  @override
  Future<domain.Entry?> findById(String id) async {
    final row = await (_db.select(_db.entries)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToDomain(row);
  }

  @override
  Future<List<domain.Entry>> findByDate(String date) async {
    // 排除墓碑：业务列表不展示已删事件（墓碑仅供同步对齐与 GC，§5.1）。
    final query = _db.select(_db.entries)
      ..where((t) => t.date.equals(date) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row)];
  }

  @override
  Future<List<domain.Entry>> findByDateRange(
    String startDate,
    String endDate, {
    List<domain.EntryKind>? kinds,
  }) async {
    // kinds 过滤走 (kind, date) 复合索引（§5.2① 索引声明）：谓词形如
    // `kind IN (…) AND date BETWEEN ? AND ?`，查询计划器可两段命中索引。
    final kindWires = kinds?.map((k) => k.wire).toList();
    final query = _db.select(_db.entries)
      ..where((t) {
        var predicate =
            t.date.isBetweenValues(startDate, endDate) & t.deletedAt.isNull();
        if (kindWires != null && kindWires.isNotEmpty) {
          predicate = predicate & t.kind.isIn(kindWires);
        }
        return predicate;
      })
      ..orderBy([
        (t) => OrderingTerm.asc(t.date),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    final rows = await query.get();
    return [for (final row in rows) _rowToDomain(row)];
  }

  @override
  Future<void> upsert(domain.Entry entry) {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.entries)
            ..where((t) => t.id.equals(entry.id)))
          .getSingleOrNull();
      var effective = entry;
      if (existing != null &&
          existing.deletedAt != null &&
          entry.meta.deletedAt == null) {
        // 墓碑拒绝复活（§6.5 删除行）：删后编辑保持删除胜出，保留原墓碑时刻。
        effective =
            entry.copyWith(meta: entry.meta.copyWith(deletedAt: existing.deletedAt));
      }
      await _db
          .into(_db.entries)
          .insertOnConflictUpdate(_toCompanion(effective));

      // 投影联动（§5.6 重建规则）：事件归属日变更时新旧两日均需重算。
      final affected = <String>{effective.date};
      if (existing != null && existing.date != effective.date) {
        affected.add(existing.date);
      }
      await _recomputeDays(affected);
    });
  }

  @override
  Future<void> softDelete(String id, {required String hlc}) {
    return _db.transaction(() async {
      final row = await (_db.select(_db.entries)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('softDelete: entries 无此行 $id（§5.1 删除行）');
      }
      // [hlc] 为本次删除操作的时间戳（接口契约）：定宽校验、物理段作 updated_at，
      // 保持 hlc 与 updated_at 同源单调（§5.1/§6.3，同步游标依赖该一致性）。
      final stamp = domain.Hlc.parse(hlc);
      await (_db.update(_db.entries)..where((t) => t.id.equals(id))).write(
        EntriesCompanion(
          deletedAt: Value(row.deletedAt ?? stamp.physicalMs),
          updatedAt: Value(stamp.physicalMs),
          hlc: Value(stamp.format()),
          revision: Value(row.revision + 1),
        ),
      );
      await _recomputeDays([row.date]);
    });
  }

  @override
  Stream<List<domain.Entry>> watchByDate(String date) {
    final query = _db.select(_db.entries)
      ..where((t) => t.date.equals(date) & t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    return query
        .watch()
        .map((rows) => [for (final row in rows) _rowToDomain(row)]);
  }

  // ── 内部实现 ──────────────────────────────────────────────────────────

  /// 写后投影联动：先标 dirty 再重算（重算成功即清 dirty；失败则保留
  /// dirty 供 recomputeDirtyDays 自愈，§5.6 重建规则）。
  Future<void> _recomputeDays(Iterable<String> dates) async {
    final target = projection;
    if (target == null) {
      return;
    }
    for (final date in dates) {
      await target.markDayDirty(date);
      await target.recomputeDaySummary(date);
    }
  }

  /// Drift 行 → 领域实体（读侧校验：HLC 定宽编码不合法直接抛 FormatException）。
  domain.Entry _rowToDomain(Entry row) => domain.Entry(
        id: row.id,
        date: row.date,
        tzOffsetMin: row.tzOffsetMin,
        occurredAt: row.occurredAt,
        kind: domain.EntryKind.fromWire(row.kind),
        source: domain.EntrySource.fromWire(row.source),
        title: row.title,
        note: row.note,
        status: domain.EntryStatus.fromWire(row.status),
        aiParseId: row.aiParseId,
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

  /// 领域实体 → Drift 行；hlc 规范化为定宽编码（节点段大写，§6.3）。
  EntriesCompanion _toCompanion(domain.Entry e) => EntriesCompanion.insert(
        createdAt: e.meta.createdAt,
        updatedAt: e.meta.updatedAt,
        deletedAt: Value(e.meta.deletedAt),
        hlc: domain.Hlc.parse(e.meta.hlc).format(),
        revision: e.meta.revision,
        schemaVer: Value(e.meta.schemaVer),
        deviceId: e.meta.deviceId,
        id: e.id,
        date: e.date,
        tzOffsetMin: e.tzOffsetMin,
        occurredAt: Value(e.occurredAt),
        kind: e.kind.wire,
        source: e.source.wire,
        title: e.title,
        note: Value(e.note),
        status: e.status.wire,
        aiParseId: Value(e.aiParseId),
      );
}
