/// 拍照通道漏斗埋点（§11.2 W11-12 任务 5、§2.3「北极星与漏斗纪律」、
/// §3.9 监控、§12 验收口径）。
///
/// 事件名（任务口径，拍照路径漏斗三步，与 core_domain [dom.TelemetryFunnel]
/// 的文本漏斗并行——拍照路径事件名独立可检索，周报分路径统计）：
/// - photo_capture_open：拍照/相册入口发起（漏斗计时起点）；
/// - photo_parse_result：识别结果（成功/缓存命中/端侧粗估/转人工/失败降级
///   + 耗时标量）；
/// - photo_confirm：确认落库（漏斗终点 + 全程耗时护栏）。
///
/// 护栏口径（§2.3「文字路径打开→确认 ≤8s（P50）、拍照路径 ≤15s」）：
/// [kPhotoPathGuardMs] 与 [photoPathWithinGuard]；metric 复用
/// [dom.TelemetryMetricName.captureOpenToConfirmMs]（tags.path='photo'
/// 区分路径）。
///
/// 隐私口径（§3.9）：只记枚举/布尔/耗时标量；原文、图片字节、识别内容
/// 一律禁入 props（实现方另有 TelemetryPrivacy 闸门兜底）。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 拍照漏斗事件名常量（§11.2 W11-12 任务 5）。
abstract final class CapturePhotoFunnel {
  /// 拍照/相册入口发起（props.from_camera：true=拍照 / false=相册）。
  static const String photoCaptureOpen = 'photo_capture_open';

  /// 识别结果（props.outcome：success=云端识别成功 / cache=input_hash 缓存
  /// 命中 / on_device=端侧粗估 / manual=转人工确认 / fallback=失败降级；
  /// props.latency_ms 耗时、props.code 失败**类型**码——均标量，§3.9）。
  static const String photoParseResult = 'photo_parse_result';

  /// 确认落库（props.total_ms：photo_capture_open→photo_confirm 全程耗时，
  /// props.within_guard：是否达 ≤15s 护栏，§2.3）。
  static const String photoConfirm = 'photo_confirm';
}

/// 拍照路径全程护栏（§2.3「拍照路径 ≤15s」）。
const int kPhotoPathGuardMs = 15000;

/// 护栏判定：photo_capture_open→photo_confirm 耗时是否达 §2.3 口径。
bool photoPathWithinGuard(int totalMs) => totalMs <= kPhotoPathGuardMs;

/// 拍照遥测注入点（§10.4 壳负责装配）：宿主 override 注入 TelemetryService
/// 实现（apps/mobile FileTelemetryService 本地 JSONL，§3.9）；缺省 null=
/// 不发事件（Noop 等价，测试与未装配环境零副作用）。
final Provider<dom.TelemetryService?> capturePhotoTelemetryProvider =
    Provider<dom.TelemetryService?>((ref) => null);
