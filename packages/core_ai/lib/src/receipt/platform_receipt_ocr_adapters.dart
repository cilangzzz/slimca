/// ML Kit（Android）/ Vision（iOS）端侧小票 OCR 适配器骨架（§10.1 OCR 行、
/// §11.2 W16 任务「MlKit/Vision 适配器骨架（平台通道注入，真实识别真机验收，
/// remaining 注明）」）。
///
/// 两平台共用同一通道协议（receipt_ocr_adapter.dart）与同一字段理解逻辑
/// （receipt_field_extractor.dart）——骨架差异只在 providerId/modelId：
/// - [MlKitReceiptOcrAdapter]：Android 端 ML Kit Text Recognition v2
///   （中文 script 变体由 native 侧装配）；
/// - [VisionReceiptOcrAdapter]：iOS 端 Vision VNRecognizeTextRequest
///   （recognitionLanguages 首选 zh-Hans，native 侧装配）。
///
/// **remaining（真机验收项，W16 任务口径「真实识别真机验收」）**：
/// 1. native handler（Kotlin/Swift）由壳层 apps/mobile 接线——core_ai 侧
///    仅约定通道协议（receipt_ocr_adapter.dart），本骨架编译可用、行为经
///    FakeReceiptOcrChannel / mock MethodHandler 单测覆盖；
/// 2. 真实识别精度（中文小票/连拍/反光）与 [kReceiptOcrTimeout] 校准待真机
///    验收；Android 无 Java / iOS 无 Mac 的真机路径见 §10.3（Codemagic 云 Mac）；
/// 3. ML Kit textBlock 置信度、Vision observation confidence 未接入
///    ReceiptDraft（W16 骨架不猜置信度，字段级 confidence 留后续里程碑）。
library;

import '../llm/llm_adapter.dart';
import 'receipt_field_extractor.dart';
import 'receipt_models.dart';
import 'receipt_ocr_adapter.dart';

/// 平台通道骨架基类（协议：method=[kMethodRecognizeReceipt]，args=
/// `{imageBytes, mime}`，result=`{textLines:[...]}`；结果经
/// [extractReceiptFields] 端侧理解为字段草稿）。
class PlatformChannelReceiptOcrAdapter implements ReceiptOcrAdapter {
  PlatformChannelReceiptOcrAdapter({
    required this.providerId,
    required this.modelId,
    required ReceiptOcrChannel channel,
    this.timeout = kReceiptOcrTimeout,
  }) : _channel = channel;

  @override
  final String providerId;

  @override
  final String modelId;

  /// 单次调用超时（骨架口径 [kReceiptOcrTimeout]；超时 → LlmTimeoutException
  /// → §7.4 一级降级手填）。
  final Duration timeout;

  final ReceiptOcrChannel _channel;

  @override
  Future<ReceiptDraft> recognize(ReceiptImageInput image) async {
    if (image.bytes.isEmpty) {
      // 请求本身非法（§7.1）：端侧引擎无从识别 → 一级降级手填。
      throw const LlmInvalidRequestException('小票图片字节为空，无法识别');
    }
    final Object? raw = await _channel
        .invoke(kMethodRecognizeReceipt, <String, Object?>{
          'imageBytes': image.bytes,
          'mime': image.mime,
        })
        .timeout(
          timeout,
          onTimeout: () => throw const LlmTimeoutException(
              '端侧 OCR 超时（骨架口径 8s，真机校准——remaining）'),
        );
    // 字段理解全端侧纯 Dart（§3.7）；通道只回文本行，无任何网络路径。
    return extractReceiptFields(_textLinesFrom(raw));
  }

  /// 通道结果 → 文本行（协议容错：textLines 数组优先；兼容整段 text 按换行
  /// 切分；其余形状=协议违约 → LlmBadResponseException 交 §7.4 映射）。
  static List<String> _textLinesFrom(Object? raw) {
    if (raw is Map) {
      final lines = raw['textLines'];
      if (lines is List) {
        return <String>[
          for (final line in lines)
            if (line is String) line,
        ];
      }
      final text = raw['text'];
      if (text is String) {
        return text.split(RegExp(r'\r?\n'));
      }
    }
    throw const LlmBadResponseException(
        '端侧 OCR 通道结果缺 textLines/text（协议违约，§7.1）');
  }
}

/// Android 端侧 ML Kit Text Recognition v2 骨架（remaining：native 接线 +
/// 真机验收，见 library 文档）。
class MlKitReceiptOcrAdapter extends PlatformChannelReceiptOcrAdapter {
  MlKitReceiptOcrAdapter({
    required super.channel,
    super.timeout,
  }) : super(
          providerId: 'mlkit',
          modelId: 'mlkit-text-recognition-v2',
        );
}

/// iOS 端侧 Vision VNRecognizeTextRequest 骨架（remaining：Codemagic 云 Mac
/// 真机验收，§10.3；见 library 文档）。
class VisionReceiptOcrAdapter extends PlatformChannelReceiptOcrAdapter {
  VisionReceiptOcrAdapter({
    required super.channel,
    super.timeout,
  }) : super(
          providerId: 'vision',
          modelId: 'vision-recognize-text-v2',
        );
}
