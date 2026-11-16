/// InMemorySyncBackend — 内存模拟远端（§6.2 服务端职责的 Fake 实现）。
///
/// 测试/开发用 Fake（禁真实网络，§6.7 验收自动化的服务端替身），逐条实现
/// §6.2 服务端校验清单与 §6.5 矩阵的服务端半边：
/// - 幂等（幂等键 = outbox.id，§5.6⑯/§6.2：重试不重复入账，原回执重放）；
/// - schema_ver 校验（超档拒绝，§6.2/§6.4）；
/// - 行存在性校验（子表父行缺失拒绝；corrections 永可插入，§5.6⑮）；
/// - hlc 单调校验（stale 写拒绝，§6.2/§6.3 定宽字典序=全序）；
/// - baseRevision 乐观校验（§5.6⑯ base_revision 行）；
/// - 墓碑拒绝复活（§6.5 删除行——必须在服务端强制，否则删端与活端分叉）；
/// - 签发权威 revision（§6.2「签发权威 seq」——全局 BIGSERIAL 模拟）；
/// - per-table 游标增量 pull（hlc 升序、含墓碑行、分批 hasMore，§6.2）；
/// - 可注入延迟（latency）与设备级分区（partition/restore，模拟断网，
///   §6.1 原则 1「同步失败仅顶栏小圆点提示」）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart';

import 'sync_backend.dart';
import 'sync_table_catalog.dart';

/// 服务端单行状态（行快照 + 定宽 hlc + 权威 revision，§6.2）。
class ServerRowState {
  /// 行快照（平铺 snake_case，与 §5.6⑯ payload 同构）。
  final Map<String, Object?> payload;

  /// 该行当前版本的定宽 HLC（§6.3）。
  final String hlc;

  /// 权威 revision（全局 seq 签发，§6.2）。
  final int revision;

  /// 行级 schema_ver（§5.1/§6.4）。
  final int schemaVer;

  /// 软删墓碑时刻；null=存活（§5.1）。
  final int? deletedAt;

  const ServerRowState({
    required this.payload,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    this.deletedAt,
  });

  bool get isTombstone => deletedAt != null;
}

/// §6.2 服务端的内存实现（模拟远端）。
class InMemorySyncBackend implements SyncBackend {
  InMemorySyncBackend({
    this.latency = Duration.zero,
    int Function()? nowMs,
    this.maxPullRows = 200,
  }) : _nowMs = nowMs ?? _defaultNow;

  static int _defaultNow() => DateTime.now().millisecondsSinceEpoch;

  /// 可注入延迟：每个 RPC 前等待（模拟网络 RTT；测试传 Duration.zero）。
  final Duration latency;

  /// 服务端墙钟（ack.ackedAt / delete 兜底墓碑时刻）。
  final int Function() _nowMs;

  /// 单次 pull 返回上限（分批拉取 hasMore，§6.2 游标续拉）。
  final int maxPullRows;

  /// 「op seq（BIGSERIAL）」（§6.2）：全局单调序号，接受即签发。
  int _seq = 0;

  /// 表 → 行 id → 服务端行状态。墓碑行保留（90 天 GC 属服务端职责，
  /// §5.1 删除行；模拟实现不做 GC）。
  final Map<String, Map<String, ServerRowState>> _tables = {};

  /// 幂等去重：outbox.id → 首次回执（仅缓存 ack；拒绝不缓存——同一
  /// outbox.id 的重试必须重新校验，父行补上后 rowMissing 重试应转正）。
  final Map<String, _EntryOutcome> _idempotency = {};

  /// 投递簿：deviceId → 表 → 已投递行 id 集合。hlc 水位游标的补漏半边：
  /// 他端在本端游标推进**之后**才上送的低水位行（hlc ≤ 游标），若只按
  /// 「hlc > 游标」过滤将永远不可见，§6.7「双端各 100 条一致率 100%」
  /// 被打破——故未投递过的行投递一次，投递过的行仍走 hlc 增量（重投递
  /// 幂等：远端行经 LWW 仲裁安全去重，§6.2）。
  final Map<String, Map<String, Set<String>>> _delivered = {};

  /// 已注册设备（§5.6⑰ devices）。
  final Map<String, DeviceRegistration> devices = {};

  /// 处于分区的设备集合（模拟断网：push/pull/register 一律不可达）。
  final Set<String> _partitioned = {};

  // ── 测试/装配辅助 ─────────────────────────────────────────────────────

  /// 设备进入分区（§6.1 离线场景）。
  void partition(String deviceId) => _partitioned.add(deviceId);

  /// 设备恢复联网。
  void restore(String deviceId) => _partitioned.remove(deviceId);

  bool isPartitioned(String deviceId) => _partitioned.contains(deviceId);

  /// 读服务端单行（测试断言用）。
  ServerRowState? rowState(String tableName, String rowId) =>
      _tables[tableName]?[rowId];

  /// 某表行数（含墓碑）。
  int rowCount(String tableName) => _tables[tableName]?.length ?? 0;

  /// 服务端已签发的最大 seq（权威 revision 单调性断言用）。
  int get lastSeq => _seq;

  /// 直接种入服务端行（测试装配：pull 侧边界场景，如超档 schema_ver 行、
  /// 未知列前瞻行，§6.4）。不占用 seq、不做校验——仅组装拉取侧输入。
  void seedServerRow(String tableName, ServerRowState state) {
    _tables.putIfAbsent(tableName, () => {})[state.payload['id'] as String] =
        state;
  }

  // ── SyncBackend 实现 ──────────────────────────────────────────────────

  @override
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  }) async {
    await _beforeRpc(deviceId);
    final acks = <SyncPushAck>[];
    final rejections = <SyncPushRejection>[];
    for (final entry in batch) {
      // 幂等键命中：原回执重放（重试不重复入账，§5.6⑯ id/§6.2）。
      final replayed = _idempotency[entry.id];
      _EntryOutcome outcome;
      if (replayed != null) {
        outcome = replayed;
      } else {
        outcome = _validateAndApply(entry);
        // 幂等只缓存回执（ack）：拒绝不缓存——同一 outbox.id 的重试必须
        // 重新走校验（如 rowMissing 的父行随后被补上，重试应转正，§6.2
        // 「重试」语义；否则过期拒绝被永久重放，出网队列无法收敛）。
        if (outcome.ack != null) {
          _idempotency[entry.id] = outcome;
        }
      }
      if (outcome.ack != null) {
        acks.add(outcome.ack!);
      } else {
        rejections.add(outcome.rejection!);
      }
    }
    return SyncPushResult(acks: acks, rejections: rejections);
  }

  @override
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  }) async {
    await _beforeRpc(deviceId);
    final changes = <RemoteChange>[];
    final nextCursors = <String, String>{};
    // 表序=落库依赖序（§6.2 per-table 游标 + 父表先于子表）；
    // 表内按 hlc 升序（定宽字典序=全序，§6.3）。
    for (final spec in syncTablesInApplyOrder) {
      final rows = _tables[spec.name];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      final cursor = since[spec.name] ?? '';
      final seen =
          _delivered.putIfAbsent(deviceId, () => {})[spec.name] ??= <String>{};
      final delivered = <ServerRowState>[];
      for (final entry in rows.entries) {
        final state = entry.value;
        // 增量条件（§6.2 游标 + 投递簿补漏）：水位之后的行照常投递；
        // 水位之下但从未向本设备投递过的行补投一次（他端迟到的低水位
        // 写入，否则双端永不收敛，§6.7）。
        if (state.hlc.compareTo(cursor) > 0 || !seen.contains(entry.key)) {
          delivered.add(state);
        }
      }
      if (delivered.isEmpty) {
        continue;
      }
      delivered.sort((a, b) => a.hlc.compareTo(b.hlc));
      for (final state in delivered) {
        if (changes.length >= maxPullRows) {
          break;
        }
        final rowId = state.payload['id'] as String;
        changes.add(
          RemoteChange(
            tableName: spec.name,
            rowId: rowId,
            op: state.isTombstone ? OutboxOp.delete : OutboxOp.upsert,
            payload: jsonEncode(state.payload),
            hlc: state.hlc,
            revision: state.revision,
            schemaVer: state.schemaVer,
          ),
        );
        seen.add(rowId); // 实际投递的行记入投递簿（未投出的行下轮补投）。
        final prev = nextCursors[spec.name];
        if (prev == null || state.hlc.compareTo(prev) > 0) {
          nextCursors[spec.name] = state.hlc;
        }
      }
      if (changes.length >= maxPullRows) {
        break;
      }
    }
    return SyncPullResult(
      changes: changes,
      nextCursors: nextCursors,
      hasMore: changes.length >= maxPullRows,
    );
  }

  @override
  Future<void> registerDevice(
    DeviceRegistration registration, {
    required String deviceId,
  }) async {
    await _beforeRpc(deviceId);
    // 幂等：重复注册视为刷新（last_seen 语义，§5.6⑰）。
    devices[registration.id] = registration;
  }

  @override
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  }) async {
    // 采纳源读取（§6.2 push 被拒后采纳服务端现值）。不做分区判定：采纳
    // 只发生在「push 刚被服务端拒绝」的可达链路上，链路必然畅通。
    final state = _tables[tableName]?[rowId];
    if (state == null) {
      return null;
    }
    return RemoteChange(
      tableName: tableName,
      rowId: state.payload['id'] as String? ?? rowId,
      op: state.isTombstone ? OutboxOp.delete : OutboxOp.upsert,
      payload: jsonEncode(state.payload),
      hlc: state.hlc,
      revision: state.revision,
      schemaVer: state.schemaVer,
    );
  }

  // ── 服务端校验与入账（§6.2 校验清单）──────────────────────────────────

  /// 校验+入账单条出网项。
  _EntryOutcome _validateAndApply(OutboxEntry entry) {
    // ① schema_ver 协商（§6.2/§6.4）：超档拒绝——payload 无法被当前协议理解。
    Map<String, Object?> payload;
    try {
      payload = jsonDecode(entry.payload) as Map<String, Object?>;
    } on FormatException {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.unknown,
        ),
      );
    }
    final schemaVer = (payload['schema_ver'] as int?) ?? kCurrentSchemaVer;
    if (schemaVer > kCurrentSchemaVer) {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.schemaVerRejected,
        ),
      );
    }
    final hlc = payload['hlc'];
    if (hlc is! String) {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.unknown,
        ),
      );
    }

    // 表登记（延迟建表；目录外表名直接拒绝——同步协议表集 W1 冻结，§5.1）。
    final SyncTableSpec spec;
    try {
      spec = syncTableSpec(entry.tableName);
    } on ArgumentError {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.unknown,
        ),
      );
    }
    final rows = _tables.putIfAbsent(entry.tableName, () => {});
    final existing = rows[entry.rowId];

    // ② hlc 单调（§6.2「hlc 单调」/§6.3）：已有行的 (物理毫秒, counter)
    //    必须严格小于本次写入——stale 写拒绝（LWW 后写者胜的服务端半边，
    //    §6.5）。定宽编码 device 段的「同刻 device_id 决胜」是 §6.5 LWW
    //    仲裁规则，不参与服务端单调准入：同刻异端写一律拒绝（严格递增）。
    final incomingStamp = Hlc.parse(hlc);
    if (existing != null) {
      final existingStamp = Hlc.parse(existing.hlc);
      final strictlyNewer = incomingStamp.physicalMs > existingStamp.physicalMs ||
          (incomingStamp.physicalMs == existingStamp.physicalMs &&
              incomingStamp.counter > existingStamp.counter);
      if (!strictlyNewer) {
        return _EntryOutcome(
          rejection: SyncPushRejection(
            outboxId: entry.id,
            reason: SyncRejectionReason.hlcNonMonotonic,
          ),
        );
      }
    }

    // ③ baseRevision 乐观校验（§5.6⑯ base_revision）：期间有他端写入。
    if (existing != null &&
        entry.baseRevision != null &&
        entry.baseRevision != existing.revision) {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.baseRevisionConflict,
        ),
      );
    }

    // ④ 墓碑拒绝复活（§6.5 删除行）：服务端行已是墓碑、本次为存活 upsert。
    final payloadDeletedAt = payload['deleted_at'] as int?;
    final isAliveUpsert =
        entry.op == OutboxOp.upsert && payloadDeletedAt == null;
    if (existing != null && existing.isTombstone && isAliveUpsert) {
      return _EntryOutcome(
        rejection: SyncPushRejection(
          outboxId: entry.id,
          reason: SyncRejectionReason.tombstoneConflict,
        ),
      );
    }

    // ⑤ 行存在性（§6.2）：子表父行缺失拒绝（corrections 无父检查——审计
    //    日志永可插入、不受跨表顺序影响，§5.6⑮）。
    final parentKey = spec.parentKey;
    if (spec.parentTable != null && parentKey != null) {
      final parentId = payload[parentKey];
      if (parentId is String &&
          _tables[spec.parentTable]?[parentId] == null) {
        return _EntryOutcome(
          rejection: SyncPushRejection(
            outboxId: entry.id,
            reason: SyncRejectionReason.rowMissing,
          ),
        );
      }
    }

    // ⑥ 接受：签发权威 revision（§6.2「签发权威 seq」）并落服务端状态。
    //    payload 内的 revision 是入网时的本地快照，回写权威 seq 覆盖——
    //    pull/fetchRow 下发的行必须带服务端 revision，否则对端以后续编辑
    //    （baseRevision=权威值）上送会被误判 baseRevisionConflict（§6.2）。
    _seq += 1;
    final revision = _seq;
    payload['revision'] = revision;
    rows[entry.rowId] = ServerRowState(
      payload: payload,
      hlc: hlc,
      revision: revision,
      schemaVer: schemaVer,
      deletedAt: entry.op == OutboxOp.delete
          ? (payloadDeletedAt ?? _nowMs())
          : payloadDeletedAt,
    );
    return _EntryOutcome(
      ack: SyncPushAck(
        outboxId: entry.id,
        revision: revision,
        ackedAt: _nowMs(),
      ),
    );
  }

  /// RPC 前置：延迟注入 + 分区判定（§6.1 原则 1）。
  Future<void> _beforeRpc(String deviceId) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (isPartitioned(deviceId)) {
      throw SyncBackendException(
        'partitioned',
        '设备 $deviceId 处于网络分区（§6.1：同步失败不阻塞本地）',
      );
    }
  }
}

/// 单条出网项的服务端处理结论（成功回执或拒绝）。
class _EntryOutcome {
  final SyncPushAck? ack;
  final SyncPushRejection? rejection;
  const _EntryOutcome({this.ack, this.rejection})
      : assert(
          (ack == null) != (rejection == null),
          '回执与拒绝互斥且必有其一',
        );
}
