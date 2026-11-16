/// FakeAdapter / FakeParser 行为测试（测试基建自身的确定性契约——
/// 全部离线脚本化，禁止真实网络调用）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('FakeLlmAdapter.scripted（顺序脚本）', () {
    test('按次序弹出响应文本，请求被完整记录', () async {
      final adapter = FakeLlmAdapter.scripted(
        [kLanzhouParseJson, '{"title":"咖啡","kind":"expense","lines":[]}'],
        providerId: 'fake-a',
        modelId: 'fake-model-a',
      );
      final r1 = await adapter.complete(
        LlmRequest(messages: const [LlmMessage(LlmRole.user, '第一句')],
            jsonIntent: LlmJsonIntent.jsonSchema, jsonSchema: const {'type': 'object'}),
      );
      final r2 = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, '第二句')]),
      );
      expect(r1.content, contains('兰州拉面'));
      expect(r2.content, contains('咖啡'));
      expect(r1.provider, 'fake-a');
      expect(r1.model, 'fake-model-a');
      expect(r1.latencyMs, 0, reason: '假适配器零延迟、离线确定');
      expect(r1.costMicro, 0, reason: '未配价目时成本为 0');
      expect(adapter.requests, hasLength(2));
      expect(adapter.lastRequest!.messages.first.content, '第二句');
    });

    test('脚本项为 LlmException 时原样抛出', () async {
      final adapter = FakeLlmAdapter.scripted([
        const LlmTimeoutException('超时'),
      ]);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmTimeoutException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('脚本耗尽 → StateError（脚本与预期调用次数不符显式暴露）', () async {
      final adapter = FakeLlmAdapter.scripted(['only-once']);
      await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'y')]),
        ),
        throwsStateError,
      );
    });

    test('配置价目时按固定 usage 折算 costMicro（§5.6⑭ 可审计）', () async {
      final adapter = FakeLlmAdapter.scripted(
        ['ok'],
        pricing: const LlmPricing(
          promptMicroPerMillion: 1080000,
          completionMicroPerMillion: 4320000,
        ),
      );
      final response = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      // 固定 usage：prompt=1000、completion=200 → 1080 + 864 = 1944 微元。
      expect(response.promptTokens, 1000);
      expect(response.completionTokens, 200);
      expect(response.costMicro, 1944);
    });
  });

  group('FakeLlmAdapter.keyed（关键字路由）', () {
    test('按 user 消息关键字路由，未命中走 fallback', () async {
      final adapter = FakeLlmAdapter.keyed(
        {'拉面': '{"title":"拉面"}', '咖啡': '{"title":"咖啡"}'},
        fallback: '{"title":"其他"}',
      );
      final ramen = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, '中午吃了兰州拉面花了 18')]),
      );
      final coffee = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, '买了杯咖啡')]),
      );
      final other = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, '打车上班')]),
      );
      expect(ramen.content, '{"title":"拉面"}');
      expect(coffee.content, '{"title":"咖啡"}');
      expect(other.content, '{"title":"其他"}');
    });

    test('未命中且无 fallback → StateError', () async {
      final adapter = FakeLlmAdapter.keyed({'拉面': 'a'});
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, '无关输入')]),
        ),
        throwsStateError,
      );
    });
  });

  group('FakeAiParser（脚本化解析器）', () {
    test('按次序返回 ParseResult，输入被完整记录', () async {
      final success = ParseSuccess(
        title: '拉面',
        kind: dom.EntryKind.expense,
        lines: const [],
        inputHash: 'hash-x',
        record: AiParseRecord(
          id: '0196a7e0-7e1f-7000-8000-3f8a12c0b7d4',
          inputKind: 'text',
          inputHash: 'hash-x',
          provider: 'fake',
          model: 'fake-model',
          rawOutput: '{}',
          latencyMs: 0,
          costMicro: 0,
          confidence: 0.9,
          promptVersion: kPromptVersion,
        ),
        fromCache: false,
      );
      final parser = FakeAiParser([success]);
      final result = await parser.parse(makeParseInput());
      expect(identical(result, success), isTrue);
      expect(parser.inputs, hasLength(1));
      expect(parser.lastInput!.context.mode, ParseMode.both);
      expect(parser.lastInput!.context.date, kTestDate);
    });

    test('脚本项为异常时抛出；脚本耗尽抛 StateError', () async {
      final parser = FakeAiParser([
        FakeAiParserScriptedException(),
      ]);
      await expectLater(
        parser.parse(makeParseInput()),
        throwsA(isA<FakeAiParserScriptedException>()),
      );
      await expectLater(
        parser.parse(makeParseInput()),
        throwsStateError,
      );
    });
  });
}

/// 测试专用异常（脚本注入用）。
class FakeAiParserScriptedException implements Exception {}
