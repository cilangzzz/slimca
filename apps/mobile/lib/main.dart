import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'sync/sync_coordinator.dart';
import 'telemetry/frame_telemetry.dart';

Future<void> main() async {
  // §11 W2 接线：runApp 前完成异步装配（开库、device_id、内置账本种子），
  // 以 overrides 注入 ProviderScope——运行期依赖全同步可读、页面零等待
  // （§2.3 步 0 无 spinner 冷启动；装配细节见 lib/app/bootstrap.dart）。
  final bootStart = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  final runtime = await bootstrap();

  // ── W7-8 崩溃上报钩子（§3.9 监控；只记错误类型，内容禁入）。
  // 装配期（bootstrap 之前）的异常不在钩子覆盖内——装配失败即不可启动，
  // 由 Flutter 默认错误呈现兜底。
  final previousFlutterOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(runtime.telemetry.crash(
      details.exception,
      details.stack,
      source: 'flutter_framework',
    ));
    previousFlutterOnError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(runtime.telemetry.crash(error, stackTrace,
        source: 'platform_dispatcher'));
    return false; // 交回引擎默认处理（崩溃日志照常）。
  };

  runApp(ProviderScope(overrides: runtime.overrides, child: const SlimcaApp()));

  // ── W7-8 冷启动完成漏斗（§12 验收口径：首帧栅格化=可交互基线，§2.3 步 0
  // ≤1.2s 的实测数据源；props 仅 boot_ms 标量，§3.9 隐私口径）。
  unawaited(WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
    return runtime.telemetry.funnel(
      TelemetryFunnel.coldStartComplete,
      props: <String, Object?>{
        'boot_ms': DateTime.now().difference(bootStart).inMilliseconds,
      },
    );
  }));

  // ── W9-10 真机帧率埋点（§9.4 帧预算、§11.1 W9-10「北极星实测·真机帧率」）：
  // 引擎按批回送真实 FrameTiming → 聚合 frame_raster_ms/frame_dropped 落
  // JSONL（§3.9 标量口径）。debug 不采（JIT+断言开销失真）——实测口径=
  // 真机 profile/release；本机无真机，帧率数字待真机实测（M2 闸门口径）。
  if (!kDebugMode) {
    FrameTelemetry.attach(runtime.telemetry);
  }

  // ── W7-8 同步启动（§6.2 同步时机：启动后一轮 + 周期定时 + 前台切回）。
  // 本地优先：start() 内部吞掉分区异常，绝不阻塞 UI（§6.1 原则 1）。
  WidgetsBinding.instance.addObserver(SyncLifecycleObserver(runtime.syncCoordinator));
  unawaited(runtime.syncCoordinator.start());

  // ── W13 提醒调度启动（§11.2 W13 任务 3）：订阅 todos（remind_at 非空）
  // watch 流，按展开实例调度本地通知（重复待办逐实例一条；Android 13+
  // POST_NOTIFICATIONS 运行时请求在适配器 start 内一次性发起）。对账失败
  // 静默自愈（§6.1 本地优先，绝不阻塞 UI）。
  unawaited(runtime.reminderCoordinator.start());
}

/// 应用根：ProviderScope + MaterialApp.router（§10.1 技术选型）。
///
/// 设计决策：
/// - 路由全部交给 go_router（§4.3 路由表），壳不持有任何页面状态；
/// - 深浅色跟随系统（§8.3），浅深两套 ThemeData 均来自 ui_kit `buildTheme`
///   （语义 token + MotionConfig 挂进主题，§8.2/§9.2）；
/// - 无 spinner 的冷启动承诺（§2.3 步 0）由仪表盘快照直出实现，壳层零加载屏。
class SlimcaApp extends StatelessWidget {
  const SlimcaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Slimca',
      debugShowCheckedModeBanner: false,
      routerConfig: slimcaRouter,
      theme: slimcaLightTheme(),
      darkTheme: slimcaDarkTheme(),
      // 主题模式下行为统一：Material 3（§8/§9 的动效与主题体系基于 M3）。
      themeMode: ThemeMode.system,
    );
  }
}
