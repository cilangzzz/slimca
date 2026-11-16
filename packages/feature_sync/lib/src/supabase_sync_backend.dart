/// SupabaseSyncBackend — [SyncBackend] 的托管 Supabase RPC 实现（W7-8，
/// §11.1「托管 Supabase 接入+RLS+幂等」、§6.2 架构与读写路径）。
///
/// 线协议（与服务端 `0002_sync_rpc.sql` 三个 RPC 一一对应，jsonb 双向）：
///
/// **push_batch**（§6.2 写路径 POST /rpc/sync_push）：
/// ```json
/// { "p_device_id": "…", "p_ops": [ {
///     "outbox_id": "…", "table_name": "…", "row_id": "…",
///     "op": "upsert|delete", "payload": {…行快照…},
///     "hlc": "0001…:000042:…", "base_revision": 12 } ] }
/// ```
/// 服务端幂等（outbox_id 唯一键去重、命中即原回执重放）+ 校验（schema_ver /
/// hlc 单调 / baseRevision / 墓碑拒绝复活 / 父行存在性）+ 签发权威 revision；
/// 逐条回执，rejections 三分类回传（作废/暂缓/幂等完成——处置在引擎
/// [LocalSyncEngine] 的拒绝分类回处理）。
///
/// **pull_changes**（§6.2 读路径 GET /rpc/sync_pull?since_hlc=…）：
/// per-table 游标（客户端 hlc 水位）+ 服务端 per-device 投递水位双轨资格判定，
/// 返回 `{changes:[{table_name,row_id,op,row,hlc,revision,schema_ver}],
/// cursors, has_more}`，含墓碑行（op=delete）。
///
/// **register_device**（§5.6⑰ devices）：幂等注册/刷新 last_seen。
///
/// fetchRow 走 REST 单行直读（RLS 过滤当前用户），供 push 被拒后采纳服务端
/// 现值（§6.5 服务端权威仲裁）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart';

import 'supabase_rpc_transport.dart';
import 'sync_backend.dart';
import 'sync_config.dart';

/// 托管 Supabase RPC 后端（§6.2「可换 PowerSync/CRDT 而不动 schema」的
/// W7-8 落点：对引擎零改动替换 InMemory/Loopback）。
class SupabaseSyncBackend implements SyncBackend {
  /// [transport] 缺省时按 [config] 构建 [SupabaseRpcTransport]；
  /// 契约测试注入 mock transport（禁真实网络，§6.7）。
  SupabaseSyncBackend({
    required SyncConfig config,
    SyncRpcTransport? transport,
    this.maxPullRows = 200,
  }) : _transport = transport ?? SupabaseRpcTransport(config: config);

  final SyncRpcTransport _transport;

  /// 单次 pull 返回上限（服务端分批，调用方按 hasMore 续拉，§6.2）。
  final int maxPullRows;

  /// RPC 函数名（与服务端迁移 `0002_sync_rpc.sql` 冻结命名一致）。
  static const String pushRpcName = 'push_batch';
  static const String pullRpcName = 'pull_changes';
  static const String registerRpcName = 'register_device';

  // ── 写路径（§6.2 POST /rpc/sync_push 半边）────────────────────────────

  @override
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  }) async {
    final ops = <Object?>[
      for (final entry in batch) _encodeOp(entry),
    ];
    final raw = await _transport.call(
      pushRpcName,
      <String, Object?>{
        'p_device_id': deviceId,
        'p_ops': ops,
      },
    );
    final body = _expectObject(raw, 'push_batch 响应必须是 jsonb 对象');
    return SyncPushResult(
      acks: [
        for (final ack in _expectList(body['acks'], 'push_batch acks'))
          _parseAck(ack),
      ],
      rejections: [
        for (final rej in _expectList(body['rejections'], 'push_batch rejections'))
          _parseRejection(rej),
      ],
    );
  }

  /// 出网项 → 线协议 op（§5.6⑯：payload 由 JSON 字符串解包为内嵌 jsonb
  /// 对象——服务端按列同构展开，避免字符串再解析的歧义）。
  Map<String, Object?> _encodeOp(OutboxEntry entry) {
    final Object? payload;
    try {
      payload = jsonDecode(entry.payload);
    } on FormatException {
      throw SyncBackendException(
        'protocol',
        '出网项 ${entry.id} 的 payload 不是合法 JSON（§5.6⑯）',
      );
    }
    return <String, Object?>{
      'outbox_id': entry.id,
      'table_name': entry.tableName,
      'row_id': entry.rowId,
      'op': entry.op.wire,
      'payload': payload,
      'hlc': entry.hlc,
      if (entry.baseRevision != null) 'base_revision': entry.baseRevision,
    };
  }

  SyncPushAck _parseAck(Object? raw) {
    final ack = _expectObject(raw, 'ack 必须是对象');
    return SyncPushAck(
      outboxId: _expectString(ack['outbox_id'], 'ack.outbox_id'),
      revision: _expectInt(ack['revision'], 'ack.revision'),
      ackedAt: _expectInt(ack['acked_at'], 'ack.acked_at'),
    );
  }

  SyncPushRejection _parseRejection(Object? raw) {
    final rej = _expectObject(raw, 'rejection 必须是对象');
    return SyncPushRejection(
      outboxId: _expectString(rej['outbox_id'], 'rejection.outbox_id'),
      reason: _reasonFromWire(
        _expectString(rej['reason'], 'rejection.reason'),
      ),
    );
  }

  /// 线协议 reason → 枚举（§6.2 校验清单六类；未知值兜底 unknown——
  /// 引擎按「保守重试」处置，前向兼容服务端新增类别，§6.4）。
  static SyncRejectionReason _reasonFromWire(String wire) {
    for (final reason in SyncRejectionReason.values) {
      if (reason.wire == wire) {
        return reason;
      }
    }
    return SyncRejectionReason.unknown;
  }

  // ── 读路径（§6.2 GET /rpc/sync_pull 半边）────────────────────────────

  @override
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  }) async {
    final raw = await _transport.call(
      pullRpcName,
      <String, Object?>{
        'p_device_id': deviceId,
        'p_cursors': <String, String>{...since},
        'p_limit': maxPullRows,
      },
    );
    final body = _expectObject(raw, 'pull_changes 响应必须是 jsonb 对象');
    final changes = <RemoteChange>[];
    for (final item in _expectList(body['changes'], 'pull_changes changes')) {
      final change = _expectObject(item, 'change 必须是对象');
      final row = _expectObject(change['row'], 'change.row 必须是对象');
      final hlc = _expectString(change['hlc'], 'change.hlc');
      changes.add(
        RemoteChange(
          tableName: _expectString(change['table_name'], 'change.table_name'),
          rowId: _expectString(change['row_id'], 'change.row_id'),
          op: _opFromWire(_expectString(change['op'], 'change.op')),
          payload: jsonEncode(row),
          hlc: hlc,
          revision: _expectInt(change['revision'], 'change.revision'),
          schemaVer: change['schema_ver'] is int
              ? change['schema_ver'] as int
              : kCurrentSchemaVer,
        ),
      );
    }
    // 游标表逐值守卫：畸形（非文本值）→ protocol 而非裸 cast 抛 TypeError
    //（§6.1 原则 1：协议级失败必须走 SyncBackendException 分类面）。
    final cursorsIn = _expectObject(
      body['cursors'],
      'pull_changes cursors 必须是对象',
    );
    final cursors = <String, String>{
      for (final entry in cursorsIn.entries)
        entry.key: _expectString(
          entry.value,
          'pull_changes cursors.${entry.key}',
        ),
    };
    final hasMore = body['has_more'];
    if (hasMore is! bool) {
      throw SyncBackendException('protocol', 'pull_changes.has_more 必须为布尔');
    }
    return SyncPullResult(
      changes: changes,
      nextCursors: cursors,
      hasMore: hasMore,
    );
  }

  OutboxOp _opFromWire(String wire) {
    try {
      return OutboxOp.fromWire(wire);
    } on ArgumentError {
      throw SyncBackendException('protocol', 'change.op 未知值：$wire');
    }
  }

  // ── 采纳源（push 被拒后的服务端现值读取，§6.5）────────────────────────

  @override
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  }) async {
    final raw = await _transport.readRow(tableName, rowId);
    if (raw == null) {
      return null;
    }
    final row = _expectObject(raw, 'fetch_row 结果必须是对象');
    final hlc = row['hlc'];
    if (hlc is! String) {
      throw SyncBackendException(
        'protocol',
        'fetch_row $tableName/$rowId 缺少定宽 hlc（§5.1 公共列）',
      );
    }
    return RemoteChange(
      tableName: tableName,
      rowId: rowId,
      // 软删墓碑行以 delete op 交付（与 pull 的墓碑语义一致，§6.2）。
      op: row['deleted_at'] != null ? OutboxOp.delete : OutboxOp.upsert,
      payload: jsonEncode(row),
      hlc: hlc,
      revision: row['revision'] is int ? row['revision'] as int : 0,
      schemaVer: row['schema_ver'] is int
          ? row['schema_ver'] as int
          : kCurrentSchemaVer,
    );
  }

  // ── 设备注册（§5.6⑰）────────────────────────────────────────────────

  @override
  Future<void> registerDevice(
    DeviceRegistration registration, {
    required String deviceId,
  }) async {
    await _transport.call(
      registerRpcName,
      <String, Object?>{
        'p_device_id': registration.id,
        'p_name': registration.name,
        'p_platform': registration.platform,
        'p_created_at': registration.createdAt,
      },
    );
    // 服务端幂等（重复注册=刷新 last_seen）；返回体仅含回显/服务器时刻，
    // 注册结果以不抛异常为准（§5.6⑰）。
  }

  // ── 响应结构守卫（协议级畸形 → SyncBackendException('protocol')）──────

  Map<String, Object?> _expectObject(Object? raw, String what) {
    if (raw is Map<String, Object?>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, Object?>.from(raw);
    }
    throw SyncBackendException('protocol', '$what（实际：${raw.runtimeType}）');
  }

  List<Object?> _expectList(Object? raw, String what) {
    if (raw is List<Object?>) {
      return raw;
    }
    if (raw is List) {
      return List<Object?>.from(raw);
    }
    throw SyncBackendException('protocol', '$what 必须是数组');
  }

  String _expectString(Object? raw, String what) {
    if (raw is String) {
      return raw;
    }
    throw SyncBackendException('protocol', '$what 必须是文本');
  }

  int _expectInt(Object? raw, String what) {
    if (raw is int) {
      return raw;
    }
    throw SyncBackendException('protocol', '$what 必须是整数');
  }
}
