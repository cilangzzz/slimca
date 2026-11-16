/// FrameTelemetry — 真机帧率埋点（§9.4 性能预算硬指标、§11.1 W9-10
/// 「北极星实测·真机帧率」）。
///
/// 口径（§9.4 预算表）：
/// - widget build 单帧 ≤8ms；raster 帧 ≤16ms（120Hz 设备 ≤8ms）；
/// - 满动效丢帧 <1%（Helio G99 级，W5-6/W9-10 真机验收线）。
///
/// 数据源：`SchedulerBinding.addTimingsCallback`——引擎按批（约每秒一批）
/// 回送真实 [FrameTiming]。**真机 profile/release 实测口径**：debug 模式
/// （JIT+断言开销）数字失真，main() 仅在非 debug 装配本类；本机无真机时
/// 帧率数字一律「待真机实测」（M2 闸门口径：代码与素材就绪）。
///
/// 丢帧判定：`totalSpan`（vsync→raster 完成）> [kFrameBudgetMs]
/// （1/60s≈16.67ms）即记一帧丢失——与 DevTools 帧率统计同口径；G99 级
/// 60Hz 屏预算下 raster ≤16ms（§9.4）。
///
/// 隐私口径（§3.9）：只记毫秒/帧数标量与枚举 tag，无任何内容字段。
///
/// 上报粒度：每批回送聚合一次——恒发 [TelemetryMetricName.frameRasterMs]
/// （批内最大 raster ms + 帧数/超预算计数 tag），批内有丢帧才追加
/// [TelemetryMetricName.frameDropped]，避免 JSONL 膨胀（逐帧落盘无必要，
/// 周报口径是聚合值）。
library;

import 'dart:async';

import 'package:core_domain/core_domain.dart';
import 'package:flutter/scheduler.dart';

/// 60Hz 帧预算（§9.4 raster ≤16ms 的丢帧判定线，1/60s≈16.67ms）。
const double kFrameBudgetMs = 1000 / 60;

/// widget build 单帧预算（§9.4：≤8ms）。
const double kBuildBudgetMs = 8;

/// raster 单帧预算（§9.4：≤16ms；120Hz 设备 ≤8ms 由设备侧自行换算）。
const double kRasterBudgetMs = 16;

/// 帧率遥测装配器（main() 在非 debug 模式调用 [FrameTelemetry.attach]）。
abstract final class FrameTelemetry {
  /// 挂接引擎帧回送（幂等安全：重复挂接=重复计数，调用方保证只挂一次）。
  static void attach(TelemetryService telemetry) {
    SchedulerBinding.instance.addTimingsCallback(
      (timings) => unawaited(reportBatch(telemetry, timings)),
    );
  }

  /// 一批帧 → 聚合 metric 落盘（attach 的回调体；独立公开供测试直接喂
  /// 合成 FrameTiming——引擎在 widget test 环境不回送 timings）。
  ///
  /// §3.9 遥测永不阻塞：telemetry 实现自身吞异常，这里不额外 try。
  static Future<void> reportBatch(
    TelemetryService telemetry,
    List<FrameTiming> timings,
  ) async {
    final stats = FrameStats.of(timings);
    if (stats.totalFrames == 0) return;
    await telemetry.metric(
      TelemetryMetricName.frameRasterMs,
      value: stats.maxRasterMs,
      unit: 'ms',
      tags: <String, Object?>{
        'frames': stats.totalFrames,
        'dropped': stats.droppedFrames,
        'max_build_ms': stats.maxBuildMs,
        'raster_over_budget': stats.rasterOverBudgetFrames,
        'build_over_budget': stats.buildOverBudgetFrames,
      },
    );
    if (stats.droppedFrames > 0) {
      await telemetry.metric(
        TelemetryMetricName.frameDropped,
        value: stats.droppedFrames,
        unit: 'frames',
        tags: <String, Object?>{'frames': stats.totalFrames},
      );
    }
  }
}

/// 一批帧的聚合统计（纯函数口径，测试可直接喂合成 FrameTiming）。
///
/// §9.4 三个预算各记一行：丢帧（totalSpan 超 1/60s）、build 超 8ms、
/// raster 超 16ms——周报按此三分量看满动效质量（W9-10 帧预算周报口径）。
class FrameStats {
  FrameStats.of(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
      if (buildMs > maxBuildMs) maxBuildMs = buildMs;
      if (rasterMs > maxRasterMs) maxRasterMs = rasterMs;
      if (totalMs > kFrameBudgetMs) droppedFrames += 1;
      if (buildMs > kBuildBudgetMs) buildOverBudgetFrames += 1;
      if (rasterMs > kRasterBudgetMs) rasterOverBudgetFrames += 1;
      totalFrames += 1;
    }
  }

  /// 批内总帧数。
  int totalFrames = 0;

  /// 批内最大 build 耗时 ms（§9.4：单帧 ≤8ms）。
  double maxBuildMs = 0;

  /// 批内最大 raster 耗时 ms（§9.4：单帧 ≤16ms）。
  double maxRasterMs = 0;

  /// 批内丢帧数（totalSpan > 1/60s，DevTools 同口径）。
  int droppedFrames = 0;

  /// 批内 build 超 8ms 的帧数。
  int buildOverBudgetFrames = 0;

  /// 批内 raster 超 16ms 的帧数。
  int rasterOverBudgetFrames = 0;
}
