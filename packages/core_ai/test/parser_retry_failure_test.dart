/// 失败重试与 StructuredFailure 测试（§7.1「校验失败重试 1 次」、
/// §7.4 四级降级映射）。
///
/// 全部经 FakeLlmAdapter 脚本化离线执行，禁止真实网络调用。
library;

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

LlmAiParser makeParser(List<Object> script, {AiParseCache? cache}) {
  final adapter = FakeLlmAdapter.scripted(script);
  return LlmAiParser(
    adapter: adapter,
    cache: cache ?? InMemoryAiParseCache(),
    nowMs: fakeNowMs,
    newParseId: makeIdSeq(),
  );
}

void main() {
  group('校验失败重试 1 次（§7.1）', () {
    test('首发校验失败 → 纠错回喂重试 → 第二次成功', () async {
      final parser = makeParser([
        '{"title":"拉面","kind":"expense","lines":[]}',
        kLanzhouParseJson,
      ]);
      final result = await parser.parse(makeParseInput());

      final adapter = parser.adapter as FakeLlmAdapter;
      expect(adapter.requests, hasLength(2), reason: '1 次首发 + 1 次纠错重试');

      // 重试请求携带上一轮输出与错误清单（纠错回喂）。
      final retryMessages = adapter.requests[1].messages;
      expect(retryMessages, hasLength(4));
      expect(retryMessages[2].role, LlmRole.assistant);
      expect(retryMessages[2].content, '{"title":"拉面","kind":"expense","lines":[]}');
      expect(retryMessages[3].role, LlmRole.user);
      expect(retryMessages[3].content, contains('未通过校验'));
      expect(retryMessages[3].content, contains('lines 为空'));

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      expect(success.title, '兰州拉面');
      expect(success.fromCache, isFalse);
      expect(success.record.latencyMs, 0);
    });

    test('invalidJson（自由文本）→ 重试一次后成功', () async {
      final parser = makeParser([
        '我猜你中午吃了兰州拉面，大概花了 18 块钱。',
        kLanzhouParseJson,
      ]);
      final result = await parser.parse(makeParseInput());
      expect(result, isA<ParseSuccess>());
      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(2));
    });

    test('两次校验都失败 → StructuredFailure（validationFailed）', () async {
      final badJson =
          '{"title":"x","kind":"expense","lines":[{"type":"money","amount_minor":0,"confidence":0.9}]}';
      final parser = makeParser([
        '完全不是 JSON 的自由文本输出',
        badJson,
      ]);
      final result = await parser.parse(makeParseInput());

      expect(result, isA<StructuredFailure>());
      final failure = result as StructuredFailure;
      expect(failure.reason, AiFailureReason.validationFailed);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm,
          reason: '§7.4 一级降级：原输入保留 → 自动降级手填表单');
      expect(failure.attempts, 2);
      expect(failure.errors, isNotEmpty);
      expect(failure.errors.first, contains('金额>0'),
          reason: '第二次的错误覆盖首试错误');
      expect(failure.lastRawOutput, badJson, reason: '末次原始输出供排查');
      expect(failure.rawInput, kLanzhouInputText,
          reason: '§7.4「原输入保留」——手填表单预填');
      expect(failure.context.mode, ParseMode.both);
      expect(failure.context.date, kTestDate);
    });

    test('lines 为空两次 → StructuredFailure（emptyResult）', () async {
      final parser = makeParser([
        '{"title":"x","kind":"expense","lines":[]}',
        '{"title":"x","kind":"expense","lines":[]}',
      ]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.emptyResult);
      expect(failure.attempts, 2);
    });
  });

  group('适配器错误 → StructuredFailure（§7.1 错误分类 × §7.4 降级映射）', () {
    test('超时 → 一级降级手填（timeout/manualForm），且不再叠加解析级重试', () async {
      final parser = makeParser([
        const LlmTimeoutException('LLM 调用超时（5000ms，§7.4 超时口径）'),
        kLanzhouParseJson,
      ]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.timeout);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
      expect(failure.cause, isA<LlmTimeoutException>());
      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1),
          reason: '瞬时重试属适配器内部职责，解析层不叠加');
    });

    test('断网 → 二级降级延迟队列（network/deferredQueue，§7.4 二级）', () async {
      final parser = makeParser([const LlmNetworkException('连接被拒')]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.network);
      expect(failure.degradeLevel, AiDegradeLevel.deferredQueue);
      expect(failure.rawInput, kLanzhouInputText);
    });

    test('额度耗尽 → 三级降级额度提示（quota/quotaNotice，§7.4 三级）', () async {
      final parser = makeParser([const LlmQuotaException('insufficient_quota')]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.quota);
      expect(failure.degradeLevel, AiDegradeLevel.quotaNotice);
    });

    test('限流 → 一级降级手填（rateLimit/manualForm）', () async {
      final parser = makeParser([const LlmRateLimitException('429')]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.rateLimit);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
    });

    test('鉴权失败 → 一级降级手填（auth/manualForm）', () async {
      final parser = makeParser([const LlmAuthException('401')]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.auth);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
    });

    test('响应非法 → 一级降级手填（badResponse/manualForm）', () async {
      final parser = makeParser([const LlmBadResponseException('缺 content')]);
      final failure = await parser.parse(makeParseInput()) as StructuredFailure;
      expect(failure.reason, AiFailureReason.badResponse);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
    });

    test('四级 providerFallback 在单 adapter 管线中不产出（接口预留，§7.4）', () async {
      // 双供应商 fallback 由编排层组合多个 LlmAdapter 实现（degrade_hooks 注释）；
      // 单 adapter 的任何错误都只落到 1-3 级。
      for (final script in <Object>[
        const LlmServerException('500'),
        const LlmInvalidRequestException('400'),
      ]) {
        final parser = makeParser([script]);
        final failure = await parser.parse(makeParseInput()) as StructuredFailure;
        expect(failure.degradeLevel, isNot(AiDegradeLevel.providerFallback));
      }
    });
  });

  group('入口契约', () {
    test('date 非 yyyy-MM-dd → ArgumentError（§5.1 日历日口径）', () async {
      final parser = makeParser([kLanzhouParseJson]);
      await expectLater(
        parser.parse(makeParseInput(date: '2026/11/30')),
        throwsArgumentError,
      );
      expect((parser.adapter as FakeLlmAdapter).requests, isEmpty,
          reason: '契约失败不产生任何 LLM 调用');
    });

    test('rawText 规范化后为空 → ArgumentError（UI 层应拦截空输入）', () async {
      final parser = makeParser([kLanzhouParseJson]);
      await expectLater(
        parser.parse(makeParseInput(rawText: '   \n　')),
        throwsArgumentError,
      );
    });
  });
}
