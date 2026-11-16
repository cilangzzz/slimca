/// SyncCoordinator — 同步生命周期编排（§6.2「后台出队/前台切回时增量拉取」、
/// §11.1 W7-8 接线、§10.4 壳层装配）。
///
/// 触发时机（§6.2 同步时机矩阵）：
/// - 启动后一次（bootstrap 装配完成后 start()）；
/// - 前台周期定时（[backgroundInterval] 缺省 15 分钟）；
/// - 前台切回（[SyncLifecycleObserver] didChangeAppLifecycleState=resumed）。
///
/// 本地优先纪律（§6.1 原则 1）：engine.syncOnce 自身捕获分区异常只记
/// report.error、永不抛出；协调器再做防御性兜底（意外异常 → telemetry.crash），
/// 绝不让同步异常冒泡到 UI。重入合并：上一轮未完成时跳过本次触发。
library;

import 'dart:async';
import 'dart:io';

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart，
// 经公开路径引用（见 core_domain.dart「W7-8」注）。
import 'package:core_domain/core_domain.dart';
import 'package:feature_sync/feature_sync.dart';
import 'package:flutter/widgets.dart';

/// 同步生命周期协调器。
class SyncCoordinator {
  SyncCoordinator({
    required LocalSyncEngine engine,
    required DeviceRegistry registry,
    TelemetryService? telemetry,
    this.backgroundInterval = const Duration(minutes: 15),
  })  : _engine = engine,
        _registry = registry,
        _telemetry = telemetry;

  final LocalSyncEngine _engine;
  final DeviceRegistry _registry;
  final TelemetryService? _telemetry;

  /// 前台周期同步间隔（§6.2「后台周期定时」的移动端缺省档）。
  final Duration backgroundInterval;

  Timer? _timer;
  bool _started = false;
  bool _syncing = false;

  /// 是否已 start（幂等保护；测试断言用）。
  bool get isStarted => _started;

  /// 启动：设备注册（§5.6⑰，幂等）→ 立即一轮同步 → 周期定时。
  /// 可重复调用（幂等）；注册失败不阻断同步（本地优先，§6.1）。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      await _registry.ensureRegistered(
        name: 'Slimca 移动端',
        platform: Platform.operatingSystem,
      );
    } on Object catch (error, stackTrace) {
      // 注册意外失败只降级记录（registry 内部已捕 SyncBackendException）；
      // 本地 devices 引用行照常落库（§6.1 本地优先）。
      await _telemetry?.crash(error, stackTrace, source: 'sync_register_device');
    }
    await syncNow();
    _timer = Timer.periodic(backgroundInterval, (_) {
      unawaited(syncNow());
    });
  }

  /// 触发一轮同步（push/pull/落库/游标推进，§6.2 全链路）。
  ///
  /// 重入合并：进行中则跳过本次触发（Timer/lifecycle/手动三源并发安全）。
  /// engine.syncOnce 永不抛（§6.1）；此处兜底意外异常 → crash 上报。
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    final stopwatch = Stopwatch()..start();
    try {
      await _engine.syncOnce();
    } on Object catch (error, stackTrace) {
      await _telemetry?.crash(error, stackTrace, source: 'sync_coordinator');
    } finally {
      stopwatch.stop();
      _syncing = false;
    }
    // 性能指标（§3.9：同步耗时为允许的标量口径）。
    await _telemetry?.metric(
      'sync_cycle_ms',
      value: stopwatch.elapsedMilliseconds,
      unit: 'ms',
    );
  }

  /// 停止周期定时（进程退出/测试清理用；已触发的轮次自然完成）。
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}

/// 前台切回触发器（§6.2「前台切回时增量拉取」；挂到 WidgetsBinding）。
class SyncLifecycleObserver with WidgetsBindingObserver {
  SyncLifecycleObserver(this._coordinator);

  final SyncCoordinator _coordinator;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_coordinator.syncNow());
    }
  }
}
