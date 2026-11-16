/// SyncBackend — 同步引擎的远端对端抽象（§6.2 架构与读写路径）。
///
/// §6.2 的评审胜出点：SyncEngine 抽象成 push/pull/resolve 三方法、
/// 「可换 PowerSync/CRDT 而不动 schema」。[SyncBackend] 把这一抽象再下探
/// 到传输对端：LocalSyncEngine 只认本接口，后端可以是
/// - [InMemorySyncBackend]：内存模拟远端（测试/开发；可注入延迟与分区）；
/// - [LocalLoopbackBackend]：本地回环（无服务端时的缺省装配，§6.1 本地优先）；
/// - W7-8 的 Supabase RPC 实现（POST /rpc/sync_push、GET /rpc/sync_pull，
///   §6.2、§11.1 W7-8）。
///
/// 协议字段（§5.1 公共列 hlc/schema_ver/deleted_at/revision、§5.6⑯⑰）
/// 在本抽象内即冻结，与 Drift schema 同构（§6.2 单侧定义双侧生成）。
library;

import 'package:core_domain/core_domain.dart';

/// 设备注册请求（§5.6⑰ devices——服务端为主件，本地引用登记）。
class DeviceRegistration {
  /// = device_id（12 位定长 hex，§6.3 节点段；与 §5.1 公共列 device_id 同域）。
  final String id;

  /// 设备展示名。
  final String name;

  /// 平台（ios/android/macos/windows/linux，§5.6⑰ platform）。
  final String platform;

  /// 注册时刻 UTC ms。
  final int createdAt;

  const DeviceRegistration({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'platform': platform,
        'created_at': createdAt,
      };

  static DeviceRegistration fromJson(Map<String, Object?> json) =>
      DeviceRegistration(
        id: json['id'] as String,
        name: json['name'] as String,
        platform: json['platform'] as String,
        createdAt: json['created_at'] as int,
      );
}

/// 远端对端抽象：幂等 push（幂等键=outbox.id，§6.2）、per-table 游标 pull
/// （§6.2 GET /rpc/sync_pull?since_hlc=…）、设备注册（§5.6⑰）。
abstract interface class SyncBackend {
  /// 写路径（§6.2 POST /rpc/sync_push）：服务端校验
  /// （schema_ver / 行存在性 / hlc 单调 / baseRevision 乐观校验 / 墓碑拒绝
  /// 复活）→ 签发权威 revision → 逐条回执（[SyncPushResult]）。
  ///
  /// [deviceId] 供服务端做设备级隔离与分区判定（RLS 按 user_id 行级隔离
  /// 是 W7-8 Supabase 侧职责，§6.2）。
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  });

  /// 读路径（§6.2 GET /rpc/sync_pull?since_hlc=…）：按 per-table 游标增量
  /// 返回变更（含墓碑行），hlc 升序；[SyncPullResult.hasMore] 为 true 时
  /// 调用方应携带 nextCursors 续拉。
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  });

  /// 读单行现值（push 被拒后的采纳源）。
  ///
  /// 语义（§6.2「服务端校验」+ §6.5）：hlc 单调/baseRevision/墓碑拒绝复活
  /// 被拒即「服务端已仲裁、本条出网作废」——引擎随即采纳服务端现值覆盖
  /// 本地行，保证双端收敛到同一裁决结果；行不存在（已 GC 等）返回 null。
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  });

  /// 设备注册（§5.6⑰ devices；幂等：重复注册=刷新 last_seen，服务端实现）。
  Future<void> registerDevice(DeviceRegistration registration, {
    required String deviceId,
  });
}

/// 远端不可达（分区/断网）或协议级失败（§6.1 原则 1：同步失败仅顶栏小圆点
/// 提示、永不阻塞——调用方捕获本异常后保持 outbox 待发、状态降级）。
class SyncBackendException implements Exception {
  /// 机器可读原因：`partitioned`（设备被分区）/ `protocol`（协议层错误）。
  final String code;
  final String message;

  const SyncBackendException(this.code, this.message);

  @override
  String toString() => 'SyncBackendException($code): $message';
}
