/// LocalLoopbackBackend — 本地回环后端（无服务端时的缺省装配）。
///
/// §6.1 原则 1「本地优先」：设备在没有任何服务端（未登录/未配置/演示模式）
/// 时也必须全功能可用。本实现把 §6.2 的两个 RPC 就地闭合：
/// - push：逐条立即签发本地递增 revision 的回执（语义=「本设备即远端」，
///   出网队列照常清空，幂等键照常生效）；
/// - pull：恒返回空批次（一切数据已在本地，无增量可拉）；
/// - registerDevice：登记进内存设备表（§5.6⑰）。
///
/// W7-8 接入托管 Supabase 时整体替换为 RPC 实现（§6.2 评审胜出点：
/// 「抽象成可换 PowerSync/CRDT 而不动 schema」），LocalSyncEngine 无感知。
library;

import 'package:core_domain/core_domain.dart';

import 'sync_backend.dart';

/// 本地回环后端（§6.1）。
class LocalLoopbackBackend implements SyncBackend {
  LocalLoopbackBackend({int Function()? nowMs})
      : _nowMs = nowMs ?? _defaultNow;

  static int _defaultNow() => DateTime.now().millisecondsSinceEpoch;

  final int Function() _nowMs;

  /// 本地签发的权威 revision 序（BIGSERIAL 的单机模拟，§6.2）。
  int _seq = 0;

  /// 幂等登记：outbox.id → 首次回执（重试重放，§6.2 幂等键）。
  final Map<String, SyncPushAck> _acks = {};

  /// 本地登记的设备（§5.6⑰）。
  final Map<String, DeviceRegistration> devices = {};

  @override
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  }) async {
    final acks = <SyncPushAck>[];
    for (final entry in batch) {
      final replayed = _acks[entry.id];
      if (replayed != null) {
        acks.add(replayed);
        continue;
      }
      _seq += 1;
      final ack = SyncPushAck(
        outboxId: entry.id,
        revision: _seq,
        ackedAt: _nowMs(),
      );
      _acks[entry.id] = ack;
      acks.add(ack);
    }
    return SyncPushResult(acks: acks, rejections: const []);
  }

  @override
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  }) async {
    // 本地回环：一切数据已在本地，无增量（§6.1 本地优先）。
    return const SyncPullResult(
      changes: [],
      nextCursors: {},
      hasMore: false,
    );
  }

  @override
  Future<void> registerDevice(
    DeviceRegistration registration, {
    required String deviceId,
  }) async {
    devices[registration.id] = registration;
  }

  @override
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  }) async {
    // 本地回环无远端现值可采纳（§6.1 本地优先）：push 不会被本后端拒绝
    // （恒回 ack），本方法仅在引擎的通用采纳链路上被调用、返回 null 即无操作。
    return null;
  }
}
