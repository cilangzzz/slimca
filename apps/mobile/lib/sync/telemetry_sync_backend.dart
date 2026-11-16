/// TelemetrySyncBackend — 同步成败漏斗埋点装饰器（§12 验收口径、§3.9 监控）。
///
/// 漏斗段：同步 push/pull 成败。装饰 [SyncBackend]，在 push/pull 返回/抛出
/// 处记事件（§6.1 原则 1：失败原样上抛，由 LocalSyncEngine 捕获降级——
/// 装饰器只旁观不吞异常）；props 仅批次规模与错误**类型**（§3.9 隐私：
/// 不含任何行内容）。
library;

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart（见
// core_domain.dart「W7-8」注）——同步契约类型（SyncBackend 面）与遥测抽象
// 均经公开路径引用，属主收敛后 ignore 已移除。
import 'package:core_domain/core_domain.dart';
import 'package:feature_sync/feature_sync.dart';

/// 同步成败漏斗装饰器（壳层装配，§10.4）。
class TelemetrySyncBackend implements SyncBackend {
  const TelemetrySyncBackend({
    required SyncBackend inner,
    required TelemetryService telemetry,
  })  : _inner = inner,
        _telemetry = telemetry;

  final SyncBackend _inner;
  final TelemetryService _telemetry;

  @override
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  }) async {
    try {
      final result = await _inner.push(batch, deviceId: deviceId);
      // push 成功（batch=送出条数、acked=确认条数，均为计数口径，§3.9）。
      await _telemetry.funnel(
        TelemetryFunnel.syncPushOk,
        props: <String, Object?>{
          'batch': batch.length,
          'acked': result.acks.length,
        },
      );
      return result;
    } on Object catch (error) {
      // push 失败（分区/超时/协议；只记错误类型，消息禁入，§3.9）。
      await _telemetry.funnel(
        TelemetryFunnel.syncPushFail,
        props: <String, Object?>{'error_type': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  }) async {
    try {
      final result = await _inner.pull(since, deviceId: deviceId);
      // pull 成功（changes=交付行数计数）。
      await _telemetry.funnel(
        TelemetryFunnel.syncPullOk,
        props: <String, Object?>{'changes': result.changes.length},
      );
      return result;
    } on Object catch (error) {
      await _telemetry.funnel(
        TelemetryFunnel.syncPullFail,
        props: <String, Object?>{'error_type': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  }) =>
      _inner.fetchRow(tableName: tableName, rowId: rowId);

  @override
  Future<void> registerDevice(
    DeviceRegistration registration, {
    required String deviceId,
  }) =>
      _inner.registerDevice(registration, deviceId: deviceId);
}
