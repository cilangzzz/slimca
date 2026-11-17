/// 平台通道桥的 MethodChannel 实现（§10.1 OCR 端侧通道；flutter/services）。
///
/// 职责极薄：invokeMethod + 平台错误就地包装为 LlmException 分类（§7.1
/// 分类表，适配器层与管线层共用同一张 §7.4 降级映射表）：
/// - MissingPluginException（native 未实现）→ LlmInvalidRequestException
///   ——W16 骨架期 native handler 待壳层接线（remaining：真机验收）；未
///   接线平台的用户路径为一级降级手填（不崩、不静默造假）；
/// - PlatformException（端侧引擎异常）→ LlmBadResponseException；
/// - 超时不在本层裁定——由适配器统一 `.timeout`（platform_receipt_ocr_
///   adapters.dart），避免双处计时口径漂移。
///
/// 测试纪律（任务硬规则：测试禁止真实平台通道，用 Fake）：单元测试经
/// TestDefaultBinaryMessenger 的 mock handler 验证本类包装行为（见
/// test/receipt_ocr_adapters_test.dart），或在适配器层注入 FakeReceiptOcrChannel。
library;

import 'package:flutter/services.dart';

import '../llm/llm_adapter.dart';
import 'receipt_ocr_adapter.dart';

/// MethodChannel 桥（缺省通道名 [kReceiptOcrChannelName]；测试可注入自定义
/// MethodChannel 以 mock handler 验证）。
class MethodChannelReceiptOcrChannel implements ReceiptOcrChannel {
  MethodChannelReceiptOcrChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(kReceiptOcrChannelName);

  final MethodChannel _channel;

  @override
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException catch (error) {
      throw LlmInvalidRequestException(
        '端侧 OCR 平台通道未实现（native handler 待壳层接线，remaining）',
        cause: error,
      );
    } on PlatformException catch (error) {
      throw LlmBadResponseException(
        '端侧 OCR 平台异常（${error.code}）：${error.message ?? ''}',
        cause: error,
      );
    }
  }
}
