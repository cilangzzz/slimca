/// 端侧小票 OCR 适配器抽象与平台通道协议（§10.1 OCR 行「ML Kit（Android）/
/// Vision（iOS）端侧——不传原图（对比云端 OCR 隐私劣势）」、§3.7 端侧优先
/// 「OCR 全端侧，不自动上云」、§11.2 W16 主线「端侧小票 OCR」）。
///
/// 适配器契约：
/// - **全端侧**（§3.7）：[recognize] 只经平台通道调用端侧识别引擎，实现内
///   禁止任何 HTTP/云端调用——原图字节不出设备（§10.1「不传原图」）；
/// - **空结果是正常业务分支**：识别不出任何文本返回 [ReceiptDraft.hasText]
///   ==false 的草稿（管线据此一级降级手填，§7.4），不抛异常——对称
///   ImageDishAdapter 空清单约定；
/// - 失败抛 llm_adapter.dart 的 [LlmException] 分类异常（复用同一张 §7.4
///   降级映射表；端侧语义上 network/quota 不可达，实际可能：超时→timeout、
///   平台未实现/坏字节→invalidRequest、通道结果坏→badResponse）；
/// - 实现自带超时裁定（骨架口径 [kReceiptOcrTimeout]，真机校准——remaining）。
///
/// 平台通道协议（骨架适配器与 native 侧的共同契约；native handler 由壳层
/// apps/mobile 接线——remaining：真机验收，见 platform_receipt_ocr_adapters.dart）：
/// - 通道名 [kReceiptOcrChannelName]；method [kMethodRecognizeReceipt]；
/// - args：`{imageBytes: Uint8List, mime: String}`；
/// - result：`{textLines: List<String>}`（按阅读序；兼容 `{text: String}`
///   整段文本，由适配器按换行切分）。
library;

import 'receipt_models.dart';

/// 端侧 OCR 单次调用超时（骨架口径；真机实测后校准——remaining）。
const Duration kReceiptOcrTimeout = Duration(seconds: 8);

/// 平台通道名（apps/mobile native 侧 handler 注册同名字符串）。
const String kReceiptOcrChannelName = 'slimca/receipt_ocr';

/// 通道 method：识别一张小票图。
const String kMethodRecognizeReceipt = 'recognizeReceipt';

/// 端侧小票 OCR 适配器抽象（W16 任务「ReceiptOcrAdapter 抽象」）。
abstract interface class ReceiptOcrAdapter {
  /// 供应商标识（诊断/失败 notes 用；端侧识别不经 ai_parses 留痕——无 LLM
  /// 成本，ai_parses 只留文本管线的解析记录，§5.6⑭）。
  String get providerId;

  /// 识别引擎/模型名（诊断用）。
  String get modelId;

  /// 端侧识别一张小票图 → 字段草稿（商户/合计/时间/明细行）。
  Future<ReceiptDraft> recognize(ReceiptImageInput image);
}

/// 平台通道桥抽象（骨架适配器的可注入接缝——W16 任务「平台通道注入」：
/// 测试注入 Fake 通道（禁真实平台通道，任务硬规则），生产注入
/// MethodChannelReceiptOcrChannel，receipt_ocr_channel.dart）。
///
/// 实现约定：平台层错误必须就地包装为 [LlmException] 分类异常（§7.1 分类
/// 表），适配器层不再二次翻译。
abstract interface class ReceiptOcrChannel {
  Future<Object?> invoke(String method, Map<String, Object?> arguments);
}
