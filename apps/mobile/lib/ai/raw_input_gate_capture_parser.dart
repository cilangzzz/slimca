/// RawInputGateCaptureParser — raw_input 上云闸门（§3.7 数据主权、§3.3）。
///
/// 装饰 [CaptureParser]：开关**关（默认）**时，AI 请求只携带「结构化最小集」
/// ——规范化文本（§7.1 管线实际消费的形态），原文全息内容不出设备；开关开时
/// 原文随请求上传（原文留档便于云端排查）。
///
/// 不变式（任务口径「关闭时仅发结构化最小集 + 本地留痕照旧」）：
/// - normalizedText / inputHash / inputKind 原样透传（缓存键与通道不变，
///   §5.6⑭）——关闭开关不改变解析结果与缓存命中；
/// - 本地留痕照旧：ai_parses 只落结构化 raw_output（§5.6⑭），raw_input 本就
///   不落库，闸门不影响留痕路径。
library;

import 'package:feature_capture/feature_capture.dart';

import '../settings/raw_input_setting.dart';

/// raw_input 上云闸门解析器（壳层装配，§10.4）。
class RawInputGateCaptureParser implements CaptureParser {
  const RawInputGateCaptureParser({
    required CaptureParser inner,
    required RawInputPolicy policy,
  })  : _inner = inner,
        _policy = policy;

  final CaptureParser _inner;
  final RawInputPolicy _policy;

  @override
  Future<CaptureParseResult> parse(CaptureParseRequest request) {
    final effective = _policy.enabled
        ? request // 开：原文随请求上传（原文留档，§3.3）。
        : CaptureParseRequest(
            // 关（默认）：仅发结构化最小集——规范化文本是管线实际消费形态，
            // 原文全息内容不出设备（§3.7 数据主权）。
            rawText: request.normalizedText,
            normalizedText: request.normalizedText,
            inputHash: request.inputHash,
            inputKind: request.inputKind,
          );
    return _inner.parse(effective);
  }
}
