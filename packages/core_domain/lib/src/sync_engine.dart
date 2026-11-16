/// 同步层抽象：outbox 模型与 SyncEngine 接口（§6.2 架构与读写路径）。
///
/// 评审胜出点（§6.2）：SyncEngine 抽象成 `push(batch) / pull(since) / resolve()`
/// 三个方法，可整体换成 PowerSync/CRDT 而不动 schema（§12.2 开放问题 #1）。
/// 写路径（§6.2）：UI → Drift 事务提交（业务行 + sync_outbox 同事务写入）
/// → SyncEngine 后台出队 → POST /rpc/sync_push（幂等键 = outbox.id）
/// → 服务端校验（schema_ver / 行存在性 / hlc 单调）→ 签发权威 seq
/// → 本地回写 revision / acked_at。
/// 读路径（§6.2）：GET /rpc/sync_pull?since_hlc=…（per-table 游标）；
/// 触发时机=启动即拉、前台切回、（可选）Realtime 推送、后台 15 分钟兜底——
/// 触发编排属于 feature_sync 的调度层，不在本抽象内。
library;

/// 出网操作类型（§5.6⑯ op 列）。
enum OutboxOp {
  upsert('upsert'),
  delete('delete');

  const OutboxOp(this.wire);

  final String wire;

  static OutboxOp fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 OutboxOp: $value（§5.6⑯）'),
      );
}

/// 出网队列行（§5.6⑯ sync_outbox——「一切出网必经之路」）。
class OutboxEntry {
  /// 幂等键：服务端据此去重，重试不重复入账（§5.6⑯ id 行、§6.2）。
  final String id;

  /// 目标行：同步真值表名 + 行主键（§5.6⑯）。
  final String tableName;
  final String rowId;
  final OutboxOp op;

  /// 行快照 JSON（§5.6⑯ payload 行；结构=对应实体的 toJson）。
  final String payload;

  /// 乐观校验用（§5.6⑯ base_revision 行）。
  final int? baseRevision;

  /// 本条出网事件的 HLC（§5.6⑯ hlc 行，定宽编码 §6.3）。
  final String hlc;
  final int createdAt;

  /// 服务端确认时刻；null=未确认（出队后回写，§6.2 写路径末步）。
  final int? ackedAt;

  const OutboxEntry({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.op,
    required this.payload,
    this.baseRevision,
    required this.hlc,
    required this.createdAt,
    this.ackedAt,
  });

  /// 写路径末步（§6.2）：ack 后回写本行 [ackedAt]；服务端签发的权威
  /// revision 则回写到目标业务行（见 [SyncPushAck.revision]）。
  OutboxEntry copyWith({int? ackedAt}) => OutboxEntry(
        id: id,
        tableName: tableName,
        rowId: rowId,
        op: op,
        payload: payload,
        baseRevision: baseRevision,
        hlc: hlc,
        createdAt: createdAt,
        ackedAt: ackedAt ?? this.ackedAt,
      );

  bool get isAcked => ackedAt != null;

  @override
  String toString() =>
      'OutboxEntry($id, $tableName/$rowId, ${op.wire}, acked=$isAcked)';
}

/// 出网队列的本地存取抽象（§6.2 写路径的队列侧）。
///
/// 关键契约：业务行与 outbox 行必须同事务写入（§6.2 写路径第一步），
/// 因此 enqueue 由实现在业务事务内调用，而不是异步通道。
abstract interface class SyncOutboxStore {
  /// 业务事务内入队（§6.2：业务行 + sync_outbox 同事务写入，同步返回）。
  Future<void> enqueue(OutboxEntry entry);

  /// 出队待发送批次，按 created_at/hlc 序（§6.2 后台出队）。
  Future<List<OutboxEntry>> dequeuePending({int limit = 100});

  /// push 成功后回写 acked_at（§6.2 本地回写步）。
  Future<void> markAcked(String outboxId, {required int ackedAt});

  /// 未确认数量（顶栏小圆点同步状态的数据源，§6.1 原则 1）。
  Future<int> pendingCount();
}

/// 拉取游标：per-table 的 pull_hlc（§5.6⑰ sync_cursors，PK(device_id, table_name)）。
/// 键为同步真值表名，值为该表已拉取到的最大 HLC（定宽编码 §6.3）。
typedef SyncPullCursors = Map<String, String>;

/// 服务端下发的一行变更（pull 结果的原子单元，§6.2 读路径）。
class RemoteChange {
  final String tableName;
  final String rowId;
  final OutboxOp op;

  /// 行快照 JSON（op=delete 时可为墓碑占位，仅 hlc/deleted_at 有效）。
  final String payload;
  final String hlc;
  final int revision;
  final int schemaVer;

  const RemoteChange({
    required this.tableName,
    required this.rowId,
    required this.op,
    required this.payload,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
  });
}

/// push 结果：逐条回执，成功与被拒分离（§6.2 服务端校验）。
class SyncPushResult {
  /// 确认条目：回写 revision / acked_at（§6.2 写路径末步）。
  final List<SyncPushAck> acks;

  /// 被拒条目：schema_ver / 行存在性 / hlc 单调失败（§6.2 校验清单）。
  final List<SyncPushRejection> rejections;

  const SyncPushResult({required this.acks, required this.rejections});
}

class SyncPushAck {
  final String outboxId;

  /// 服务端签发的权威版本（§6.2「签发权威 seq」；§5.1 revision 行）。
  final int revision;
  final int ackedAt;

  const SyncPushAck({
    required this.outboxId,
    required this.revision,
    required this.ackedAt,
  });
}

/// 拒绝原因枚举，逐条对应 §6.2 服务端校验项。
enum SyncRejectionReason {
  schemaVerRejected('schema_ver'),
  rowMissing('row_missing'),
  hlcNonMonotonic('hlc_non_monotonic'),
  unknown('unknown');

  const SyncRejectionReason(this.wire);

  final String wire;
}

class SyncPushRejection {
  final String outboxId;
  final SyncRejectionReason reason;

  const SyncPushRejection({required this.outboxId, required this.reason});
}

/// pull 结果：一批远端变更 + 每表新游标（§6.2 读路径、§5.6⑰）。
class SyncPullResult {
  final List<RemoteChange> changes;

  /// 各表推进后的 pull_hlc；落库成功后写回 sync_cursors（§5.6⑰）。
  /// 注意：游标只在整批变更成功落库后才推进，失败则保持原游标重拉。
  final SyncPullCursors nextCursors;

  /// 还有更多数据未拉取（调用方应循环拉取直到 false）。
  final bool hasMore;

  const SyncPullResult({
    required this.changes,
    required this.nextCursors,
    required this.hasMore,
  });
}

/// 冲突归属类别：§6.5 冲突解决矩阵的行标签。
/// SyncEngine 实现按此类分发到对应策略，而不是按表名硬编码。
enum ConflictClass {
  /// 标量配置（settings / theme_profiles）：行级 LWW，后写者胜（§6.5 第 1 行）。
  scalarLww,

  /// entries 事件主干：行级 LWW + 字段保留集（§6.5 第 2 行）。
  entryLww,

  /// entry_lines 产出行同 facet 行同字段并发：hlc LWW（§6.5 第 3 行；
  /// 不同 facet 行的结构性免冲突发生在拆行层，不进入 resolve）。
  facetRowLww,

  /// money 行 confirmed 后：不可变，并发合并=并集（§6.5 第 4 行）。
  immutableMoney,

  /// corrections / savings_contributions：append-only 并集（§6.5 第 5 行）。
  appendOnly,

  /// todo.done：完成事件只前进，set 胜（§6.5 第 6 行）。
  todoDoneForward,

  /// 删除墓碑：拒绝复活（§6.5 第 7 行）。
  tombstone,
}

/// 服务端/对端与本地同行冲突时的仲裁请求（§6.5）。
class SyncConflict {
  final String tableName;
  final String rowId;
  final ConflictClass conflictClass;

  /// 双方定宽 HLC（字典序即全序，§6.3）。
  final String localHlc;
  final String remoteHlc;

  /// 双方行快照 JSON（§5.6⑯ payload 结构）。
  final String localPayload;
  final String remotePayload;

  const SyncConflict({
    required this.tableName,
    required this.rowId,
    required this.conflictClass,
    required this.localHlc,
    required this.remoteHlc,
    required this.localPayload,
    required this.remotePayload,
  });
}

/// 仲裁结论。
class SyncConflictResolution {
  final ConflictWinner winner;

  /// winner=merged 时的合并快照 JSON（如 corrections 并集、todo.done set 胜）。
  final String? mergedPayload;

  const SyncConflictResolution({required this.winner, this.mergedPayload});
}

enum ConflictWinner { local, remote, merged }

/// 同步引擎抽象（§6.2 客户端三方法，评审胜出点）。
///
/// 实现约束：
/// - 本地优先：同步失败只影响顶栏小圆点状态，永不阻塞 UI（§6.1 原则 1）；
/// - push 幂等：幂等键 = outbox.id，重试不重复入账（§6.2、§10.1 Supabase 行）；
/// - pull 游标 per-table（§5.6⑰），落库成功后才推进；
/// - 冲突按 [ConflictClass] 分级仲裁，语义边界以 §6.5 矩阵为准。
abstract interface class SyncEngine {
  /// 写路径：出队批次上送（§6.2 POST /rpc/sync_push）。
  Future<SyncPushResult> push(List<OutboxEntry> batch);

  /// 读路径：增量拉取（§6.2 GET /rpc/sync_pull?since_hlc=…）。
  Future<SyncPullResult> pull(SyncPullCursors since);

  /// 冲突仲裁（§6.5 冲突解决矩阵）。
  Future<SyncConflictResolution> resolve(SyncConflict conflict);
}
