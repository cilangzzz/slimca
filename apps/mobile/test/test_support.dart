/// 测试支撑（§3.9 监控 W7-8）：RecordingTelemetryService —— 漏斗/指标/崩溃
/// 埋点的内存记录实现（禁真实 IO/网络；断言经 events 列表）。
library;

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart，
// 经公开路径引用（见 core_domain.dart「W7-8」注）。
import 'package:core_domain/core_domain.dart';

/// 记录式遥测（测试断言用；零副作用、立即完成）。
class RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  /// 按事件名过滤（漏斗断言辅助）。
  List<TelemetryEvent> byName(String name) =>
      events.where((e) => e.name == name).toList();

  @override
  Future<void> funnel(String name, {Map<String, Object?>? props}) async {
    events.add(TelemetryEvent(
      kind: TelemetryKind.funnel,
      name: name,
      atMs: 0,
      props: props ?? const {},
    ));
  }

  @override
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  }) async {
    events.add(TelemetryEvent(
      kind: TelemetryKind.metric,
      name: name,
      atMs: 0,
      props: <String, Object?>{
        'value': value,
        if (unit != null) 'unit': unit,
        ...?tags,
      },
    ));
  }

  @override
  Future<void> crash(
    Object error,
    StackTrace? stackTrace, {
    String? source,
  }) async {
    events.add(TelemetryEvent(
      kind: TelemetryKind.crash,
      name: 'crash',
      atMs: 0,
      props: <String, Object?>{
        'error_type': error.runtimeType.toString(),
        if (source != null) 'source': source,
      },
    ));
  }

  @override
  Future<void> flush() => Future<void>.value();
}
