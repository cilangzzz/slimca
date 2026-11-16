/// apps/mobile 遥测装配库（§3.9 监控 W7-8 接入；§10.4 壳负责装配）。
///
/// re-export 面板：
/// - core_domain 的遥测接口与值对象（§3.9 抽象：crash/metric/funnel +
///   隐私闸门 + §12 漏斗事件名）；
/// - 壳层实现：[NoopTelemetryService]（测试/未装配兜底）与
///   [FileTelemetryService]（本地 JSONL 落盘，§3.9 隐私口径）。
///
/// **导出注记（W7-8 集成收敛）**：core_domain 包级 barrel 已补上
/// `export 'src/telemetry.dart'`（见 core_domain.dart「W7-8」注），本库
/// 与各实现文件的 src 实现路径引用已一并收敛为公开路径，ignore 移除。
library;

export 'file_telemetry_service.dart' show FileTelemetryService;
export 'frame_telemetry.dart' show FrameStats, FrameTelemetry;
export 'noop_telemetry_service.dart' show NoopTelemetryService;
export 'package:core_domain/core_domain.dart'
    show
        TelemetryEvent,
        TelemetryFunnel,
        TelemetryKind,
        TelemetryMetricName,
        TelemetryPrivacy,
        TelemetryService;
