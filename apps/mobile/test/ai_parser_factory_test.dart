// W3-4 dart-define 工厂单测（§11.1 W3-4 任务项 1、§7.1 adapter 可插拔）。
//
// 覆盖：缺省（无 dart-define）→ FakeParser；给了 key → OpenAiCompatAdapter
// 且 base/key/model 配置正确（base/model 缺省回落 §7.5 GPT-4o-mini 口径）。
//
// 装配说明：`String.fromEnvironment` 是编译期常量——集成统一跑
// `flutter test`（不注入 SLIMCA_AI_*），常量均为空串；工厂以显式参数
// 覆盖常量读取（运行期行为与 dart-define 注入后等价，见工厂实现）。
// 全文件零网络调用：adapter 只测配置与纯函数解码，不发真实请求。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/ai_parser.dart';
import 'package:slimca/ai/ai_parser_factory.dart';
import 'package:slimca/ai/fake_parser.dart';
import 'package:slimca/ai/openai_compat_adapter.dart';

void main() {
  group('createAiParser：dart-define 装配工厂（§11.1 W3-4）', () {
    test('缺省（未注入 dart-define）→ FakeParser（默认 mock）', () {
      // 测试环境无 SLIMCA_AI_* 注入 → key 常量为空串 → mock。
      expect(createAiParser(), isA<FakeParser>());
    });

    test('显式空配置（等价 dart-define 全缺省）→ FakeParser', () {
      expect(
        createAiParser(baseUrl: '', apiKey: '', model: ''),
        isA<FakeParser>(),
      );
    });

    test('key 为空串视为未配置 → FakeParser（即使给了 base/model）', () {
      final parser = createAiParser(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        model: 'gpt-4o-mini',
      );
      expect(parser, isA<FakeParser>());
    });

    test('给了 key → OpenAiCompatAdapter，配置按注入值正确装配', () {
      final parser = createAiParser(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test-123',
        model: 'glm-4.6',
      );
      expect(parser, isA<OpenAiCompatAdapter>());
      final adapter = parser as OpenAiCompatAdapter;
      expect(adapter.baseUrl, 'https://api.example.com/v1');
      expect(adapter.apiKey, 'sk-test-123');
      expect(adapter.model, 'glm-4.6');
      // 文本超时按 §7.4 降级方案表：5s。
      expect(adapter.timeout, const Duration(seconds: 5));
    });

    test('只给 key → base/model 缺省回落（§7.5：OpenAI 兼容 + GPT-4o-mini）', () {
      final adapter =
          createAiParser(apiKey: 'sk-only-key') as OpenAiCompatAdapter;
      expect(adapter.baseUrl, kDefaultAiBaseUrl);
      expect(adapter.baseUrl, 'https://api.openai.com/v1');
      expect(adapter.model, kDefaultAiModel);
      expect(adapter.model, 'gpt-4o-mini');
    });
  });

  group('OpenAiCompatAdapter 受约束解码（纯函数，零网络，§7.2）', () {
    /// §7.2 示例：用户输入「中午吃了兰州拉面花了 18」的受约束输出。
    Map<String, Object?> chatResponse(String content) => <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': content},
            },
          ],
        };

    test('§7.2 示例 JSON → canonical 结果（amount_kcal/amount_minor 归一）', () {
      final constrained = jsonEncode(<String, Object?>{
        'title': '兰州拉面',
        'kind': 'mixed',
        'lines': <Object?>[
          <String, Object?>{
            'type': 'calorie',
            'amount_kcal': 550,
            'confidence': 0.62,
            'category_hint': '餐饮-面食',
            'items': <Object?>[
              <String, Object?>{
                'name': '牛肉拉面',
                'portion_g': 450,
                'kcal': 500,
                'protein_g': 25,
                'carb_g': 65,
                'fat_g': 12,
                'ref_source': 'local',
              },
            ],
          },
          <String, Object?>{
            'type': 'money',
            'amount_minor': 1800,
            'currency': 'CNY',
            'confidence': 0.93,
            'ledger_hint': 'default',
            'merchant': null,
          },
        ],
        'parse_notes': '份量按中碗估计；金额来自文本「18」',
      });

      final result = mapOpenAiResponse(
        chatResponse(constrained),
        model: 'gpt-4o-mini',
        latencyMs: 120,
      );

      expect(result.title, '兰州拉面');
      expect(result.firstKcalLine?.amount, 550); // §5.1 存储口径：kcal 整数
      expect(result.firstMoneyLine?.amount, 1800); // 分（§5.1）
      expect(result.firstMoneyLine?.currency, 'CNY');
      expect(result.firstKcalLine?.confidence, 0.62);
      expect(result.firstMoneyLine?.confidence, 0.93);
      expect(result.firstKcalLine?.items.single.name, '牛肉拉面');
      expect(result.parseNotes, isNotNull);
      // 运行元数据注入（§5.6⑭ provider/model/prompt_version/latency_ms）。
      expect(result.provider, 'openai-compat');
      expect(result.model, 'gpt-4o-mini');
      expect(result.promptVersion, OpenAiCompatAdapter.promptVersion);
      expect(result.latencyMs, 120);
    });

    test('缺 choices → AiParserException（协议不符，§7.4 降级口）', () {
      expect(
        () => mapOpenAiResponse(
          const <String, Object?>{'choices': <Object?>[]},
          model: 'gpt-4o-mini',
          latencyMs: 0,
        ),
        throwsA(isA<AiParserException>()),
      );
    });

    test('自由文本 content（拒绝 JSON）→ AiParserException（§7.2 红线）', () {
      expect(
        () => mapOpenAiResponse(
          chatResponse('抱歉，我不能输出 JSON。'),
          model: 'gpt-4o-mini',
          latencyMs: 0,
        ),
        throwsA(isA<AiParserException>()),
      );
    });

    test('kcal 越界（>5000）→ 校验器拒收 AiParserException（§7.1）', () {
      final constrained = jsonEncode(<String, Object?>{
        'title': '大餐',
        'kind': 'food',
        'lines': <Object?>[
          <String, Object?>{'type': 'calorie', 'amount_kcal': 9999, 'confidence': 0.9},
        ],
      });
      expect(
        () => mapOpenAiResponse(
          chatResponse(constrained),
          model: 'gpt-4o-mini',
          latencyMs: 0,
        ),
        throwsA(isA<AiParserException>()),
      );
    });
  });

  group('FakeParser 确定性（默认 mock，§11.1 W3-4）', () {
    const parser = FakeParser();

    test('「午餐 500kcal 花了18」→ 双行产出（同输入恒同结果）', () async {
      final a = await parser.parse(
        const AiParseRequest(inputKind: AiInputKind.text, input: '午餐 500kcal 花了18'),
      );
      final b = await parser.parse(
        const AiParseRequest(inputKind: AiInputKind.text, input: '午餐 500kcal 花了18'),
      );
      expect(a.title, b.title);
      expect(a.firstKcalLine?.amount, 500);
      expect(a.firstMoneyLine?.amount, 1800); // 18 元 → 1800 分（§5.1）
      expect(a.firstKcalLine?.confidence, 0.62);
      expect(a.firstMoneyLine?.confidence, 0.93);
      expect(a.provider, 'fake');
      // 校验器自洽：mock 产出必须过 §7.1 校验器。
      validateAiParseResult(a);
    });

    test('纯描述（无数值）→ note 空 lines，不抛错', () async {
      final result = await parser.parse(
        const AiParseRequest(inputKind: AiInputKind.text, input: '今天心情不错'),
      );
      expect(result.lines, isEmpty);
      expect(result.kindHint, 'note');
      validateAiParseResult(result);
    });
  });
}
