/// 小票 OCR dart-define 装配工厂（§11.2 W16 主线、§10.4「壳负责装配」的
/// core_ai 侧落点；与 photo_factory.dart 同一装配模式）。
///
/// **中文注记（任务口径）**：端侧识别的 native handler 待壳层接线（真机
/// 验收项，remaining 见 platform_receipt_ocr_adapters.dart）——装配缺省
/// 一律确定性 Fake/离线桩（默认 mock），绝不以半成品通道造假：
/// - `--dart-define=SLIMCA_RECEIPT_OCR=mlkit|vision|fake` 显式指定端侧
///   OCR 侧（通道桥经 [ReceiptOcrChannel] 注入，缺省 MethodChannel）；
/// - 未显式指定时按运行平台选择：Android→mlkit、iOS→vision、其余（桌面/
///   测试宿主）→[FakeReceiptOcrAdapter.fixed]；
/// - [aiParser] 缺省 [LlmAiParser]+[HeuristicFakeLlmAdapter]（默认 mock，
///   离线确定性）；宿主生产装配注入与文本通道同一实例（input_hash 缓存与
///   提示词版本共用，§7.1）——小票云解析与文本通道共享缓存，同结构化文本
///   <7 天命中零重复计费。
///
/// 注意：`String.fromEnvironment` 是编译期常量，运行期/测试不可改写；
/// 工厂参数缺省回落到常量，测试以显式参数注入覆盖。
library;

import 'dart:io' show Platform;

import '../cache/ai_parse_cache.dart';
import '../fake/fake_receipt_ocr_adapter.dart';
import '../fake/heuristic_fake_adapter.dart';
import '../parse/ai_parser.dart';
import 'platform_receipt_ocr_adapters.dart';
import 'receipt_ocr_adapter.dart';
import 'receipt_ocr_channel.dart';
import 'receipt_parser.dart';

/// dart-define 键（W16 任务口径）。
const String kSlimcaReceiptOcrDefine = 'SLIMCA_RECEIPT_OCR';

/// dart-define 读取（未注入时空串 → 按平台选择）。
const String kSlimcaReceiptOcr =
    String.fromEnvironment(kSlimcaReceiptOcrDefine);

/// 装配小票解析器（端侧 OCR 侧 + 文本管线侧）。
///
/// [ocrAdapter] 显式注入优先（测试/灰度）；缺省按 [defaultReceiptOcrAdapter]
/// 平台规则装配。[aiParser] 缺省默认 mock（见 library 文档）。
ReceiptParser createReceiptParser({
  ReceiptOcrAdapter? ocrAdapter,
  ReceiptOcrChannel? channel,
  AiParser? aiParser,
}) {
  return ReceiptParser(
    ocrAdapter:
        ocrAdapter ?? defaultReceiptOcrAdapter(channel: channel),
    aiParser: aiParser ?? _defaultAiParser(),
  );
}

/// 缺省端侧 OCR 适配器（平台选择规则见 library 文档；§1.3 Android 优先，
/// iOS 真机走 Codemagic 云 Mac 验收 §10.3；桌面/测试宿主回 Fake 离线桩）。
ReceiptOcrAdapter defaultReceiptOcrAdapter({ReceiptOcrChannel? channel}) {
  switch (kSlimcaReceiptOcr.trim().toLowerCase()) {
    case 'mlkit':
      return MlKitReceiptOcrAdapter(
          channel: channel ?? MethodChannelReceiptOcrChannel());
    case 'vision':
      return VisionReceiptOcrAdapter(
          channel: channel ?? MethodChannelReceiptOcrChannel());
    case 'fake':
      return FakeReceiptOcrAdapter.fixed();
  }
  if (Platform.isAndroid) {
    return MlKitReceiptOcrAdapter(
        channel: channel ?? MethodChannelReceiptOcrChannel());
  }
  if (Platform.isIOS) {
    return VisionReceiptOcrAdapter(
        channel: channel ?? MethodChannelReceiptOcrChannel());
  }
  // 桌面/测试宿主：端侧引擎不在场——离线桩（不以半成品通道造假）。
  return FakeReceiptOcrAdapter.fixed();
}

/// 默认 mock 文本管线（离线确定性；宿主生产装配应注入与文本通道同一实例）。
AiParser _defaultAiParser() => LlmAiParser(
      adapter: const HeuristicFakeLlmAdapter(),
      cache: InMemoryAiParseCache(),
    );
