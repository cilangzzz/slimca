/// SyncOutboxStore 的 Drift 实现（§5.6⑯ sync_outbox——「一切出网必经之路」）。
///
/// core_domain 只定义接口（§6.2 写路径的队列侧），落库实现随 core_db 的
/// schema 在此装配（§10.4「仓库接口在 core_domain、实现在数据层」）。
/// 契约（§6.2）：业务行与 outbox 行必须同事务写入——[enqueue] 由写入方在
/// 其 Drift 事务内调用；引擎侧只做 [dequeuePending]/[markAcked]/[drop]。
library;

import 'package:core_db/core_db.dart';
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';

/// sync_outbox 的 Drift 实现（§5.6⑯）。
class DriftSyncOutboxStore implements SyncOutboxStore {
  DriftSyncOutboxStore(this._db);

  final AppDatabase _db;

  @override
  Future<void> enqueue(OutboxEntry entry) {
    // id 即幂等键（§5.6⑯）：同 id 重复入队=覆盖（同事务重放安全）。
    return _db.into(_db.syncOutbox).insertOnConflictUpdate(
          SyncOutboxCompanion.insert(
            id: entry.id,
            targetTable: entry.tableName,
            rowId: entry.rowId,
            op: entry.op.wire,
            payload: entry.payload,
            baseRevision: Value(entry.baseRevision),
            hlc: entry.hlc,
            createdAt: entry.createdAt,
            ackedAt: Value(entry.ackedAt),
          ),
        );
  }

  @override
  Future<List<OutboxEntry>> dequeuePending({int limit = 100}) async {
    // 出队序：created_at → hlc（§6.2「后台出队」；hlc 定宽字典序=全序，
    // 同刻多行时保证与事件时序一致，§6.3）。
    final rows = await (_db.select(_db.syncOutbox)
          ..where((t) => t.ackedAt.isNull())
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.hlc),
          ])
          ..limit(limit))
        .get();
    return [for (final row in rows) _rowToEntry(row)];
  }

  @override
  Future<void> markAcked(String outboxId, {required int ackedAt}) {
    return (_db.update(_db.syncOutbox)
          ..where((t) => t.id.equals(outboxId)))
        .write(SyncOutboxCompanion(ackedAt: Value(ackedAt)));
  }

  @override
  Future<void> drop(String outboxId) {
    return (_db.delete(_db.syncOutbox)
          ..where((t) => t.id.equals(outboxId)))
        .go();
  }

  @override
  Future<int> pendingCount() async {
    final count = await _db.syncOutbox
        .count(where: (t) => t.ackedAt.isNull())
        .getSingle();
    return count;
  }

  OutboxEntry _rowToEntry(SyncOutboxItem row) => OutboxEntry(
        id: row.id,
        tableName: row.targetTable,
        rowId: row.rowId,
        op: OutboxOp.fromWire(row.op),
        payload: row.payload,
        baseRevision: row.baseRevision,
        hlc: row.hlc,
        createdAt: row.createdAt,
        ackedAt: row.ackedAt,
      );
}
