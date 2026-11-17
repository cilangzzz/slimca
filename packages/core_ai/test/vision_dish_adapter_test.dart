/// VisionLlmDishAdapter 契约测试（W11-12 任务第 1 项：复用既有
/// OpenAiCompatibleAdapter 的 vision 能力，响应走 §7.2 JSON Schema 口径）。
///
/// 走真实 OpenAiCompatibleAdapter + MockClient——同时覆盖多模态 content
/// 数组（text + image_url）的协议序列化与错误分类透传。全部离线（任务
/// 硬规则：禁止真实网络调用）。
library;

import 'dart:convert';

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'photo_test_support.dart';

/// §7.2 口径的 Vision 响应夹具（单边热量行；菜品级置信度齐备）。
const String kVisionOkJson = '''
{
  "title": "牛肉拉面",
  "kind": "food",
  "lines": [
    { "type": "calorie", "amount_kcal": 500, "confidence": 0.55,
      "category_hint": "餐饮-面食",
      "items": [{ "name": "牛肉拉面", "portion_g": 450, "kcal": 500,
                  "protein_g": 25, "carb_g": 65, "fat_g": 12,
                  "ref_source": "llm", "confidence": 0.55 }] }
  ],
  "parse_notes": "份量按中碗估计"
}
''';

OpenAiCompatibleConfig makeVisionConfig({int maxAttempts = 1}) =>
    OpenAiCompatibleConfig(
      baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
      apiKey: 'sk-vision-test',
      model: 'qwen-vl-plus',
      jsonCapability: LlmJsonCapability.jsonObject,
      maxAttempts: maxAttempts,
      retryBackoff: Duration.zero,
      timeout: const Duration(seconds: 12),
    );

VisionLlmDishAdapter makeAdapter(http.Client client, {int maxDishes = 6}) =>
    VisionLlmDishAdapter(
      adapter: OpenAiCompatibleAdapter(makeVisionConfig(), client: client),
      maxDishes: maxDishes,
    );

CompressedImage makeImage() => CompressedImage(
      bytes: makeJpegFixture(width: 16, height: 12),
      mime: 'image/jpeg',
      widthPx: 16,
      heightPx: 12,
    );

void main() {
  group('请求形状（多模态 content 数组，§3.3 拍照通道）', () {
    test('POST chat/completions：text + image_url(data url) 段、json_object 档',
        () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        return utf8Response(okBody(kVisionOkJson), 200);
      });
      final adapter = makeAdapter(client);
      final image = makeImage();

      await adapter.recognize(image);

      final request = captured.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
      );
      expect(request.headers['Authorization'], 'Bearer sk-vision-test');

      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'qwen-vl-plus');
      // 兼容端点 json_object 宽档（§7.2：硬闸门在 parse 层校验器）。
      final responseFormat = body['response_format'] as Map<String, Object?>;
      expect(responseFormat['type'], 'json_object');

      final messages = body['messages'] as List<Object?>;
      expect((messages[0] as Map<String, Object?>)['role'], 'system');
      expect((messages[0] as Map<String, Object?>)['content'],
          contains('拍照识别引擎'));

      // 多模态 user 消息：content 数组 [text, image_url]。
      final userMessage = messages[1] as Map<String, Object?>;
      expect(userMessage['role'], 'user');
      final content = userMessage['content'] as List<Object?>;
      expect(content, hasLength(2));
      final textPart = content[0] as Map<String, Object?>;
      expect(textPart['type'], 'text');
      final imagePart = content[1] as Map<String, Object?>;
      expect(imagePart['type'], 'image_url');
      final url = ((imagePart['image_url'] as Map<String, Object?>)['url'])
          as String;
      expect(url, startsWith('data:image/jpeg;base64,'));
      expect(
        url.endsWith(base64Encode(image.bytes)),
        isTrue,
        reason: '端侧压缩规范形内联（即用即焚，§3.3）',
      );
    });

    test('providerId/modelId 透传底层 adapter（ai_parses 留痕口径，§5.6⑭）',
        () {
      final adapter = makeAdapter(
          MockClient((request) async => utf8Response(okBody('{}'), 200)));
      expect(adapter.providerId, 'openai_compatible');
      expect(adapter.modelId, 'qwen-vl-plus');
      expect(adapter.dishRefSource, FoodRefSource.llm);
    });
  });

  group('响应解析（§7.2 受约束口径 → DishCandidate）', () {
    test('成功：菜品级字段与每百克换算（kcal/portion×100）', () async {
      final client =
          MockClient((request) async => utf8Response(okBody(kVisionOkJson), 200));
      final dishes = await makeAdapter(client).recognize(makeImage());

      expect(dishes, hasLength(1));
      final dish = dishes.single;
      expect(dish.name, '牛肉拉面');
      expect(dish.grams, 450);
      expect(dish.confidence, 0.55);
      expect(dish.categoryHint, '餐饮-面食');
      expect(dish.kcalPer100gHint, closeTo(500 / 450 * 100, 0.01),
          reason: '红线 §7.1：模型直报 kcal 只换算每百克参考随行，不直接落库');
    });

    test('菜品级 confidence 缺失 → 继承行级（§7.2 示例口径）', () async {
      const json = '''
{"title":"x","kind":"food","lines":[{"type":"calorie","amount_kcal":300,"confidence":0.5,"items":[{"name":"米饭","portion_g":200,"kcal":232}]}]}
''';
      final client =
          MockClient((request) async => utf8Response(okBody(json), 200));
      final dishes = await makeAdapter(client).recognize(makeImage());
      expect(dishes.single.confidence, 0.5);
      expect(dishes.single.kcalPer100gHint, closeTo(232 / 200 * 100, 0.01));
    });

    test('非法项逐项跳过（缺 name/portion），全非法 → 空候选', () async {
      const json = '''
{"title":"x","kind":"food","lines":[{"type":"calorie","amount_kcal":0,"confidence":0.4,"items":[
  {"name":"  ","portion_g":100,"kcal":10},
  {"portion_g":100,"kcal":10},
  {"name":"没份量","kcal":10},
  {"name":"米饭","portion_g":200,"kcal":232}
]}]}
''';
      final client =
          MockClient((request) async => utf8Response(okBody(json), 200));
      final dishes = await makeAdapter(client).recognize(makeImage());
      expect(dishes.map((d) => d.name).toList(), ['米饭']);
    });

    test('空菜品（items=[]）→ 空候选（§7.4 兜底分支）', () async {
      const json = '''
{"title":"x","kind":"food","lines":[{"type":"calorie","amount_kcal":0,"confidence":0.2,"items":[]}]}
''';
      final client =
          MockClient((request) async => utf8Response(okBody(json), 200));
      final dishes = await makeAdapter(client).recognize(makeImage());
      expect(dishes, isEmpty);
    });

    test('maxDishes 截断', () async {
      const json = '''
{"title":"x","kind":"food","lines":[{"type":"calorie","amount_kcal":0,"confidence":0.5,"items":[
  {"name":"甲","portion_g":100,"kcal":100},
  {"name":"乙","portion_g":100,"kcal":100},
  {"name":"丙","portion_g":100,"kcal":100}
]}]}
''';
      final client =
          MockClient((request) async => utf8Response(okBody(json), 200));
      final adapter = VisionLlmDishAdapter(
        adapter: OpenAiCompatibleAdapter(makeVisionConfig(), client: client),
        maxDishes: 2,
      );
      final dishes = await adapter.recognize(makeImage());
      expect(dishes.map((d) => d.name).toList(), ['甲', '乙']);
    });

    test('markdown 围栏/前后缀文字宽容剥离（§7.1 宽容入口对称面）', () async {
      const wrapped = '好的，识别结果如下：\n```json\n$kVisionOkJson\n```\n以上。';
      final client =
          MockClient((request) async => utf8Response(okBody(wrapped), 200));
      final dishes = await makeAdapter(client).recognize(makeImage());
      expect(dishes, hasLength(1));
    });
  });

  group('错误分类透传（底层 LlmException 原样上抛，§7.4 同一张降级映射表）', () {
    test('响应不是合法 JSON → LlmBadResponseException', () async {
      final client = MockClient((request) async =>
          utf8Response(okBody('这不是 JSON 输出'), 200));
      await expectLater(
        makeAdapter(client).recognize(makeImage()),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('响应缺 lines → LlmBadResponseException', () async {
      final client = MockClient(
          (request) async => utf8Response(okBody('{"title":"x"}'), 200));
      await expectLater(
        makeAdapter(client).recognize(makeImage()),
        throwsA(isA<LlmBadResponseException>()),
      );
    });

    test('429 → LlmRateLimitException（底层分类透传，不二次包装）', () async {
      final client = MockClient((request) async => utf8Response('{"error":"rate"}', 429));
      await expectLater(
        makeAdapter(client).recognize(makeImage()),
        throwsA(isA<LlmRateLimitException>()),
      );
    });

    test('401 → LlmAuthException', () async {
      final client = MockClient((request) async => utf8Response('{"error":"unauthorized"}', 401));
      await expectLater(
        makeAdapter(client).recognize(makeImage()),
        throwsA(isA<LlmAuthException>()),
      );
    });

    test('底层网络错误 → LlmNetworkException', () async {
      final client = MockClient((request) async {
        throw http.ClientException('offline');
      });
      await expectLater(
        makeAdapter(client).recognize(makeImage()),
        throwsA(isA<LlmNetworkException>()),
      );
    });
  });
}

/// MockClient 响应体（choices + usage，与 openai_adapter_test 同款 200 形状）。
String okBody(String content) => jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'content': content},
          'finish_reason': 'stop',
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 1200,
        'completion_tokens': 300,
      },
    });
