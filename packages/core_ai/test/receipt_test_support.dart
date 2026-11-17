/// 小票通道测试支撑：fixture 小票文本行、fixture 图片字节、脚本化通道桥、
/// 缺省装配构造器。
///
/// 全部离线：OCR 经 FakeReceiptOcrAdapter（脚本化草稿/异常）或脚本化
/// ReceiptOcrChannel，文本管线经 LlmAiParser+HeuristicFakeLlmAdapter 或
/// FakeLlmAdapter / FakeAiParser（脚本化），缓存经 InMemoryAiParseCache，
/// 平台通道经 TestDefaultBinaryMessenger 的 mock handler——禁止真实平台
/// 通道与网络（任务硬规则）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:image/image.dart' as img;

import 'test_support.dart';

/// fixture 小票文本行（便利店小票样张；字段抽取/管线/冒烟共用基准）：
/// - 行 1 商户「全家便利店」；行 2 小票时间；行 3 会员噪声（无行尾金额，
///   不入明细；含于 rawText、不入结构化文本——上云最小化断言锚点）；
/// - 行 4-5 明细（可乐 3.50 元 x1、饭团 9.00 元）；行 6 实收合计 12.50 元
///   （高优先级关键词）。
const List<String> kFixtureReceiptLines = <String>[
  '全家便利店',
  '2026-03-05 12:31',
  '扫码积分送好礼',
  '可乐 x1 3.50',
  '饭团 9.00',
  '实收 12.50',
];

/// fixture 小票图字节（package:image 现场编码；OCR Fake/通道对字节内容不
/// 敏感——字节只用于即用即焚/输入口径断言）。
Uint8List makeReceiptJpegFixture({int width = 48, int height = 64}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, (x * 5) % 256, (y * 3) % 256, 200, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// 垃圾小票文本行（非小票图/识别全噪声；无任何可用字段 → 文本管线
/// emptyResult → 手填，§7.4）。
const List<String> kGarbageReceiptLines = <String>[
  '&&&%%%???',
  '）））（（',
];

/// 构造小票解析请求（锚点日取测试基准日；cloudParseConfirmed 可覆写）。
ReceiptParseRequest makeReceiptRequest(
  Uint8List bytes, {
  String mime = 'image/jpeg',
  String date = kTestDate,
  bool cloudParseConfirmed = false,
}) =>
    ReceiptParseRequest(
      imageBytes: bytes,
      mime: mime,
      date: date,
      cloudParseConfirmed: cloudParseConfirmed,
    );

/// 缺省装配的文本管线（默认 mock 全链：HeuristicFakeLlmAdapter + 内存缓存，
/// 注入确定性时钟/序列 id——与生产 LlmAiParser 行为同构）。
LlmAiParser makeDefaultAiParser({AiParseCache? cache}) => LlmAiParser(
      adapter: const HeuristicFakeLlmAdapter(),
      cache: cache ?? InMemoryAiParseCache(),
      nowMs: fakeNowMs,
      newParseId: makeIdSeq(),
    );

/// 构造小票解析器（注入 OCR 侧与文本管线侧）。
ReceiptParser makeReceiptParser({
  required ReceiptOcrAdapter ocrAdapter,
  AiParser? aiParser,
}) =>
    ReceiptParser(
      ocrAdapter: ocrAdapter,
      aiParser: aiParser ?? makeDefaultAiParser(),
    );

/// 脚本化通道桥（测试专用）：脚本项为结果对象（Map/List/String 等，返回）、
/// [LlmException] 或 `Exception`/`Error`（抛出）。调用记录在 [calls]。
class FakeReceiptOcrChannel implements ReceiptOcrChannel {
  FakeReceiptOcrChannel._(
    Object? Function(int callIndex, String method, Map<String, Object?> args)
        next,
  ) : _next = next;

  /// 顺序脚本工厂；脚本耗尽抛 StateError（显式暴露意外调用）。
  factory FakeReceiptOcrChannel.scripted(List<Object> script) {
    final items = List<Object>.unmodifiable(script);
    return FakeReceiptOcrChannel._((index, _, __) {
      if (index >= items.length) {
        throw StateError(
          'FakeReceiptOcrChannel 脚本耗尽（第 $index 次调用，脚本共 '
          '${items.length} 项）',
        );
      }
      return items[index];
    });
  }

  /// 永不完成工厂（适配器超时裁定测试用）。
  factory FakeReceiptOcrChannel.hang() =>
      FakeReceiptOcrChannel._((_, __, ___) => Completer<Object?>().future);

  final Object? Function(int, String, Map<String, Object?>) _next;

  /// 调用记录（method, arguments）——断言通道协议（method 名/args 键）用。
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  int _callIndex = 0;

  @override
  Future<Object?> invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    calls.add((method, Map<String, Object?>.of(arguments)));
    final item = _next(_callIndex++, method, arguments);
    if (item is Exception) {
      throw item;
    }
    if (item is Error) {
      throw item;
    }
    return item;
  }
}

/// Money 行受约束 JSON 夹具（缓存回放测试用——FakeLlmAdapter 脚本响应，
/// 经既有校验器 moneyOnly 分支：金额 1250 分、商户「全家便利店」、内置
/// 分类「购物」命中）。
const String kReceiptMoneyParseJson = '''
{
  "title": "全家便利店",
  "kind": "expense",
  "lines": [
    { "type": "money", "amount_minor": 1250, "income": false, "currency": "CNY",
      "confidence": 0.9, "ledger_hint": "default", "category_hint": "购物",
      "merchant": "全家便利店" }
  ],
  "parse_notes": "小票合计 12.50 元"
}
''';
