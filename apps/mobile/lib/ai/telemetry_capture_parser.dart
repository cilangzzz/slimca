/// TelemetryCaptureParser — 解析漏斗埋点装饰器（§12 验收口径、§3.9 监控）。
///
/// 漏斗段（§2.3「打开→输入→解析→确认」）：解析请求发出 / 解析成功 /
/// 失败降级。本装饰器只记录**标量口径**（input_kind、开关位、latency_ms、
/// 失败**类型**码）——原文、规范化文本、解析结果内容一律禁入（§3.9 隐私），
/// props 再经 TelemetryPrivacy 闸门兜底。
///
/// 装配次序（bootstrap）：TelemetryCaptureParser(inner:
/// RawInputGateCaptureParser(inner: createCaptureParser(), policy)) ——
/// 埋点在最外层，`raw_input_cloud` 读的是当次请求真实经过的闸门状态。
///
/// 超时口径：外层控制器已对 parse 施加 kCaptureParseTimeout 超时（§7.4），
/// 本装饰器**不再叠加**自身 timeout（否则超时事件比控制器晚一拍）；adapter
/// 内部超时抛出的 CaptureStructuredFailure(code=timeout) 与控制器超时的
/// TimeoutException 都会归入 parse_fallback。
library;

import 'dart:async';

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart，
// 经公开路径引用（见 core_domain.dart「W7-8」注）。
import 'package:core_domain/core_domain.dart';
import 'package:feature_capture/feature_capture.dart';

/// 解析漏斗埋点装饰器（壳层装配，§10.4）。
class TelemetryCaptureParser implements CaptureParser {
  const TelemetryCaptureParser({
    required CaptureParser inner,
    required TelemetryService telemetry,
    bool Function()? rawInputCloud,
  })  : _inner = inner,
        _telemetry = telemetry,
        _rawInputCloud = rawInputCloud;

  final CaptureParser _inner;
  final TelemetryService _telemetry;

  /// 读取当次 raw_input 上云开关位（bootstrap 传 () => policy.enabled；
  /// 缺省=未装配开关，记 0）。
  final bool Function()? _rawInputCloud;

  @override
  Future<CaptureParseResult> parse(CaptureParseRequest request) async {
    // 解析请求（§12 漏斗「解析请求」；props 仅枚举/开关位标量，§3.9）。
    await _telemetry.funnel(
      TelemetryFunnel.parseRequest,
      props: <String, Object?>{
        'input_kind': request.inputKind,
        'raw_input_cloud': (_rawInputCloud?.call() ?? false) ? 1 : 0,
      },
    );
    try {
      final result = await _inner.parse(request);
      // 解析成功（含缓存命中复用；latency 为标量耗时，§3.9 允许口径）。
      await _telemetry.funnel(
        TelemetryFunnel.parseSuccess,
        props: <String, Object?>{'latency_ms': result.latencyMs},
      );
      return result;
    } on CaptureStructuredFailure catch (failure) {
      // 失败降级（§7.4：失败 100% 降级不卡死；只记失败**类型**码）。
      await _telemetry.funnel(
        TelemetryFunnel.parseFallback,
        props: <String, Object?>{'code': failure.code.name},
      );
      rethrow;
    } on TimeoutException {
      // 控制器层超时穿透到装饰器的兜底路径（§7.4 文本 5s 超时）。
      await _telemetry.funnel(
        TelemetryFunnel.parseFallback,
        props: <String, Object?>{'code': 'timeout'},
      );
      rethrow;
    } on Object {
      // 未分类异常（网络栈其他错误等）：只记 'error'，内容禁入（§3.9）。
      await _telemetry.funnel(
        TelemetryFunnel.parseFallback,
        props: <String, Object?>{'code': 'error'},
      );
      rethrow;
    }
  }
}
