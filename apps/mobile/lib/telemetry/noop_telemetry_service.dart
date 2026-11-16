/// NoopTelemetryService — 空遥测实现（测试与未装配兜底，§3.9 监控）。
///
/// 用途：
/// - 单元/契约测试注入（禁真实 IO，所有方法立即完成的 Future）；
/// - bootstrap 装配失败（path_provider 不可用等）时的降级兜底——遥测缺失
///   只损失监控数据，不影响任何业务功能（§6.1 原则 1 同款纪律）。
library;

import 'dart:async';

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart，
// 经公开路径引用（见 core_domain.dart「W7-8」注）。
import 'package:core_domain/core_domain.dart';

/// 空实现：所有调用立即完成、零副作用。
class NoopTelemetryService implements TelemetryService {
  const NoopTelemetryService();

  @override
  Future<void> funnel(String name, {Map<String, Object?>? props}) =>
      Future<void>.value();

  @override
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  }) =>
      Future<void>.value();

  @override
  Future<void> crash(Object error, StackTrace? stackTrace, {String? source}) =>
      Future<void>.value();

  @override
  Future<void> flush() => Future<void>.value();
}
