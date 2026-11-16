/// 设备注册（§5.6⑰ devices、§3.7「同步一期…+设备注册」、W5-6 任务项 5）。
///
/// devices 是「服务端为主」件（§5.1 表分组）：本注册器
/// 1. 经 core_db [LocalWriteClock] 取本设备标识（12 位定长 hex，§6.3 节点段；
///    settings 持久化、全库复用——与业务行的 device_id 同源，§5.1 公共列）；
/// 2. 在本地 devices 表登记引用行（幂等 upsert：重复注册只刷新 last_seen）；
/// 3. 调用 [SyncBackend.registerDevice] 完成服务端注册（幂等）。
/// 分区/断网时本地登记照常生效（本地优先，§6.1），服务端侧由调用方重试。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/drift.dart';

import 'sync_backend.dart';

/// 注册结果（调用方据此决定是否提示/重试服务端侧）。
class DeviceRegistrationResult {
  /// 本设备标识（与 devices.id、HLC 节点段同域，§6.3）。
  final String deviceId;

  /// 本地 devices 引用行已落库（恒 true）。
  final bool registeredLocally;

  /// 服务端已确认注册（分区时为 false）。
  final bool ackedByServer;

  const DeviceRegistrationResult({
    required this.deviceId,
    required this.registeredLocally,
    required this.ackedByServer,
  });
}

/// 设备注册器（§5.6⑰）。
class DeviceRegistry {
  DeviceRegistry(this._db, this._backend, {LocalWriteClock? clock})
      : _clock = clock ?? LocalWriteClock(_db);

  final AppDatabase _db;
  final SyncBackend _backend;
  final LocalWriteClock _clock;

  /// 确保本设备已注册（幂等；重复调用=刷新 last_seen，§5.6⑰）。
  ///
  /// [name]/[platform] 缺省值仅作演示兜底；生产装配点应传真实值
  /// （device_info_plus 等，W7-8）。
  Future<DeviceRegistrationResult> ensureRegistered({
    String name = 'Slimca Device',
    String platform = 'unknown',
  }) async {
    final deviceId = await _clock.deviceId();
    final now = DateTime.now().millisecondsSinceEpoch;

    // 本地引用登记（§5.6⑰「服务端为主，本地引用登记」）：
    // 已有行保留 createdAt 只刷新 last_seen；吊销行不复活（revoked_at 不动）。
    final existing = await (_db.select(_db.devices)
          ..where((t) => t.id.equals(deviceId)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.devices).insert(
            DevicesCompanion.insert(
              id: deviceId,
              name: name,
              platform: platform,
              createdAt: now,
              lastSeenAt: now,
            ),
          );
    } else {
      await (_db.update(_db.devices)..where((t) => t.id.equals(deviceId)))
          .write(DevicesCompanion(lastSeenAt: Value(now)));
    }

    // 服务端注册（幂等；分区抛 SyncBackendException 由调用方按 §6.1 降级）。
    var acked = false;
    try {
      await _backend.registerDevice(
        DeviceRegistration(
          id: deviceId,
          name: name,
          platform: platform,
          createdAt: existing?.createdAt ?? now,
        ),
        deviceId: deviceId,
      );
      acked = true;
    } on SyncBackendException {
      // 分区：本地已登记，服务端侧留待复网重试（§6.1 原则 1）。
    }
    return DeviceRegistrationResult(
      deviceId: deviceId,
      registeredLocally: true,
      ackedByServer: acked,
    );
  }

  /// 读本地登记的设备行（P1/P2 设备管理页数据源，§5.6⑰）。
  Future<List<Device>> listDevices() => _db.select(_db.devices).get();
}
