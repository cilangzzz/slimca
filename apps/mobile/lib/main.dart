import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart' show SlimcaThemeMorph;

import 'app/bootstrap.dart';
import 'app/router.dart';
import 'sync/sync_coordinator.dart';
import 'telemetry/frame_telemetry.dart';
import 'theme/theme_providers.dart'
    show
        slimcaDarkThemeProvider,
        slimcaLightThemeProvider,
        slimcaThemeModeProvider;

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
/// - W16（§11.2 任务 2）：浅深两套 ThemeData 来自 theme_profiles 当前包
///   （slimcaLight/DarkThemeProvider → ui_kit buildTheme，§8.2/§9.2），
///   浅深跟随系统 + 手动覆盖（slimcaThemeModeProvider，§8.3）；
/// - **主题切换全屏 morph（§9.3#10、§8.3）**：builder 内 SlimcaThemeMorph
///   以目标 ThemeData（按当前生效亮度取 light/dark resolved）驱动
///   AnimatedTheme——主题源变化时 ColorScheme.lerp + ThemeExtension lerp
///   300ms（MotionLevel=off 降级 100ms 淡入淡出，§9.6），无闪跳；
///   morph 包裹在 Navigator 之上，覆盖全部页面（「全屏」语义）；
/// - 无 spinner 的冷启动承诺（§2.3 步 0）由仪表盘快照直出实现，壳层零加载屏
///   （主题初值由 bootstrap 预载 override，首帧即正确包，零闪跳）。
class SlimcaApp extends ConsumerWidget {
  const SlimcaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData lightTheme = ref.watch(slimcaLightThemeProvider);
    final ThemeData darkTheme = ref.watch(slimcaDarkThemeProvider);
    final ThemeMode themeMode = ref.watch(slimcaThemeModeProvider);
    return MaterialApp.router(
      title: 'Slimca',
      debugShowCheckedModeBanner: false,
      routerConfig: slimcaRouter,
      theme: lightTheme,
      darkTheme: darkTheme,
      // 深浅色：跟随系统 + 手动覆盖（§8.3；W16 手动覆盖半边落地）。
      themeMode: themeMode,
      builder: (context, child) {
        // morph 目标 = 当前生效亮度的 resolved 主题（与 theme/darkTheme 参数
        // 同一实例）；MaterialApp 内部已按 themeMode/platformBrightness 换向，
        // 此处对齐同一判定（§8.3），morph 由 SlimcaThemeMorph 按 MotionConfig
        // token 取时长（300ms / off 100ms，§9.3#10/§9.6）。
        final Brightness effective = switch (themeMode) {
          ThemeMode.system => MediaQuery.platformBrightnessOf(context),
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
        };
        return SlimcaThemeMorph(
          data: effective == Brightness.dark ? darkTheme : lightTheme,
          child: child!,
        );
      },
    );
  }
}
