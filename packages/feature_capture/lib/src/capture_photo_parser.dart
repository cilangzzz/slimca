/// 拍照解析器抽象与双供应商 fallback（§3.3 拍照通道、§7.1 管线照片路径、
/// §7.4「双供应商 fallback（百度菜品识别↔Vision LLM）」、§11.2 W11-12）。
///
/// 分层边界（§10.4）：
/// - 百度菜品识别 / Vision LLM 的真实供应商凭据未提供——实现按 dart-define/
///   配置注入，缺省 Fake（remaining：待凭据联调）；
/// - core_ai 侧照片多段 content（text + image_url，LlmMessage 注记）扩展后，
///   由壳参照文本桥接（apps/mobile CoreAiCaptureParser）桥接 LlmAiParser；
/// - 解析结果复用文本管线的 [CaptureParseResult] 模型与校验器
///   （[CaptureParseResult.checkUsable]，§7.1「金额>0、kcal∈[0,5000]、必需
///   字段齐」），留痕复用 CaptureGateway.saveAiParse/findCachedParse
///   （input_kind=photo，§5.6⑭）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_parser.dart'
    show CaptureParseResult, CaptureStructuredFailure;
import 'capture_photo_models.dart';

/// 照片解析超时（§7.4 降级方案「照片 12s」——文本 5s 见
/// kCaptureParseTimeout；§2.3 拍照路径全程 ≤15s 护栏内含压缩与确认）。
const Duration kCapturePhotoParseTimeout = Duration(seconds: 12);

/// 拍照解析器抽象（§3.3「百度菜品识别先行 → Vision LLM 兜底」）。
///
/// 双供应商 fallback 的组合语义由实现承担（本包提供
/// [CapturePhotoParserFallback] 组合子）；实现收到 [CapturePhotoParseRequest]
/// 时 raw_input 上云闸门已放行（§3.7：开关关闭时控制器根本不会走到云端
/// 解析路径）。
abstract interface class CapturePhotoParser {
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request);
}

/// 双供应商 fallback 组合子（§7.4 第 4 级降级「供应商单点故障/涨价 → 双供应商
/// fallback：百度菜品识别↔Vision LLM」的照片路径实现）。
///
/// primary（百度菜品识别）结构化失败/超时 → fallback（Vision LLM）；兜底
/// 自身失败向上抛（两级都失败 = 控制器降级手填，§7.4，绝不丢已拍数据）。
class CapturePhotoParserFallback implements CapturePhotoParser {
  const CapturePhotoParserFallback({
    required this.primary,
    required this.fallback,
  });

  /// 先行供应商（百度菜品识别，§7.5 中文菜品识别 9000+）。
  final CapturePhotoParser primary;

  /// 兜底供应商（Vision LLM：Qwen-VL / GLM-4V，§7.5）。
  final CapturePhotoParser fallback;

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    try {
      return await primary.parse(request);
    } on CaptureStructuredFailure {
      // 结构化失败 → 兜底供应商（§7.4 双供应商防单点）。
      return fallback.parse(request);
    } on TimeoutException {
      // 先行供应商超时 → 兜底供应商重试识别。
      return fallback.parse(request);
    }
  }
}

/// 注入点（§10.4 壳负责装配）：真实供应商凭据未提供，宿主注入 dart-define
/// 配置的组合实现或降级桩；测试注入 FakeCapturePhotoParser。
final Provider<CapturePhotoParser> capturePhotoParserProvider =
    Provider<CapturePhotoParser>(
  (ref) => throw UnimplementedError(
    '宿主必须 override capturePhotoParserProvider（§10.4 壳负责装配）：'
    '注入百度菜品识别→Vision LLM 组合（真实凭据待联调，缺省 Fake）；'
    '测试注入 FakeCapturePhotoParser',
  ),
);
