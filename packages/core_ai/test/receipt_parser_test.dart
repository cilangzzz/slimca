/// ReceiptParser 管线测试（§11.2 W16 任务第 2/3/4 项）：
/// - 端侧预填（cloudParseConfirmed=false → 零上云、文本管线零调用）；
/// - 全链字段映射（Fake OCR → 结构化文本 → 既有 AiParser 文本管线 →
///   金额/商家/日期预填，单边 money）；
/// - 坏小票降级手填、OCR 异常 §7.4 降级映射、缓存回放、fixture 冒烟。
///
/// 全部离线（任务硬规则）：OCR 经 FakeReceiptOcrAdapter（脚本化），文本
/// 管线经 LlmAiParser+HeuristicFakeLlmAdapter / FakeAiParser / FakeLlmAdapter，
/// 缓存经 InMemoryAiParseCache——禁止真实平台通道与网络。
library;

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_test/flutter_test.dart';

import 'receipt_test_support.dart';
import 'test_support.dart';

void main() {
  group('端侧预填（§3.7「不自动上云」：cloudParseConfirmed=false 缺省路径）', () {
    test('只走端侧 OCR → ReceiptPrefillResult；文本管线零调用', () async {
      final fakeAiParser = FakeAiParser(<Object>[]); // 被调用即抛 StateError
      final ocr = FakeReceiptOcrAdapter.fixed();
      final parser = makeReceiptParser(
        ocrAdapter: ocr,
        aiParser: fakeAiParser,
      );

      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture()),
      );

      expect(result, isA<ReceiptPrefillResult>());
      final prefill = result as ReceiptPrefillResult;
      expect(prefill.draft.merchant, '全家便利店');
      expect(prefill.draft.totalMinor, 1250);
      expect(prefill.suggestedDate, '2026-03-05',
          reason: '小票日期（合法日历日）优先于请求锚点日（§5.2① 预填）');
      expect(fakeAiParser.inputs, isEmpty,
          reason: '未确认 → 云解析不发生（§3.7 不自动上云）');
      expect(ocr.lastImage!.mime, 'image/jpeg',
          reason: '端侧 OCR 收到原图字节（即用即焚）');
    });

    test('非法锚点日 → ArgumentError（§5.1 日历日契约）', () async {
      final parser = makeReceiptParser(ocrAdapter: FakeReceiptOcrAdapter.fixed());
      await expectLater(
        parser.parse(makeReceiptRequest(
          makeReceiptJpegFixture(),
          date: '2026/11/30',
        )),
        throwsArgumentError,
      );
    });
  });

  group('全链字段映射（W16 任务第 2 项：Fake OCR → 文本管线 → 预填）', () {
    test('衔接契约：单边 money 模式 + kind=text + 结构化文本进管线', () async {
      final fakeAiParser =
          FakeAiParser(<Object>[_scriptedSuccess()]); // 脚本 1 项，恰好承接一次
      final parser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.repeating(),
        aiParser: fakeAiParser,
      );

      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture(),
            cloudParseConfirmed: true),
      );

      expect(result, isA<ReceiptParsedResult>());
      expect(fakeAiParser.inputs, hasLength(1));
      final input = fakeAiParser.inputs.single;
      // 结构化文本（最小字段集）：上云最小化口径（§3.7）。
      expect(input.rawText, buildReceiptStructuredText(kDefaultReceiptDraft));
      expect(
        input.rawText,
        '在小票「全家便利店」消费 12.50 元；小票时间 2026-03-05 12:31；'
        '购买明细：可乐、饭团',
      );
      expect(input.context.mode, ParseMode.moneyOnly,
          reason: '小票=消费凭据，恒单边 money（§3.3 单边开关）');
      expect(input.kind, AiInputKind.text,
          reason: '§5.6⑭ 枚举内：云解析的输入即文本，OCR 端侧无留痕需求');
      expect(input.context.date, kTestDate, reason: '提示词锚点=请求锚点日');
    });

    test('fixture 冒烟：图片字节 → 端侧 OCR → 文本管线 → money 行预填', () async {
      final bytes = makeReceiptJpegFixture();
      final parser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.fromTextLines(kFixtureReceiptLines),
      );

      final result = await parser.parse(
        makeReceiptRequest(bytes, cloudParseConfirmed: true),
      );

      expect(result, isA<ReceiptParsedResult>());
      final parsed = result as ReceiptParsedResult;

      // 金额预填：money 行 == OCR 合计（同源校验，§7.3 amount_minor）。
      final money = parsed.parse.lines.single;
      expect(money.type, dom.LineType.money);
      expect(money.amount, 1250);
      expect(money.amount, parsed.draft.totalMinor);
      expect(money.direction, dom.LineDirection.outcome,
          reason: '小票恒支出方向（§5.2② money 缺省 expense=out）');
      expect(money.currency, 'CNY');

      // 商家预填：payload.merchant == OCR 商户（§5.2② payload 行级明细）。
      expect(money.payload!['merchant'], '全家便利店');
      expect(money.payload!['merchant'], parsed.draft.merchant);

      // 日期预填与 occurred_at（§5.2①）。
      expect(parsed.suggestedDate, '2026-03-05');
      expect(
        parsed.draft.datetime!.occurredAtMsUtc(480),
        DateTime.utc(2026, 3, 5, 12, 31).millisecondsSinceEpoch -
            480 * 60000,
      );

      // ai_parses 留痕（§5.6⑭）：kind=text、默认 mock 供应商。
      expect(parsed.parse.record.inputKind, AiInputKind.text.wire);
      expect(parsed.parse.record.provider, 'fake');
      expect(parsed.parse.record.confidence, closeTo(0.93, 1e-9));
      expect(parsed.parse.fromCache, isFalse);

      // 上云最小化（§3.7）：OCR 全文噪声行不出端。
      expect(parsed.parse.record.rawOutput, isNot(contains('扫码积分送好礼')));
      // OCR 全文仅端侧内存留存（原文字面在草稿内，不进结构化文本/留痕）。
      expect(parsed.draft.rawText, kFixtureReceiptLines.join('\n'));
    });

    test('默认 mock 商家抽取：HeuristicFakeLlmAdapter 「X」→ merchant/title',
        () async {
      final parser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.repeating(),
      );
      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture(),
            cloudParseConfirmed: true),
      ) as ReceiptParsedResult;

      expect(result.parse.title, '全家便利店');
      expect(result.parse.lines.single.categoryHint, '餐饮-正餐');
      expect(result.parse.lines.single.band, ConfidenceBand.green,
          reason: '金额 0.93 ≥ 0.8（§7.3 三色点）');
    });
  });

  group('坏小票降级手填（W16 任务第 4 项，§7.4）', () {
    test('OCR 空文本（坏小票/非小票图）→ emptyResult + manualForm，管线零调用',
        () async {
      final fakeAiParser = FakeAiParser(<Object>[]);
      final parser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.fixed(draft: const ReceiptDraft()),
        aiParser: fakeAiParser,
      );

      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture(), cloudParseConfirmed: true),
      );

      expect(result, isA<ReceiptParseFailedResult>());
      final failed = result as ReceiptParseFailedResult;
      expect(failed.draft, isNull);
      expect(failed.failure.reason, AiFailureReason.emptyResult);
      expect(failed.failure.degradeLevel, AiDegradeLevel.manualForm);
      expect(failed.failure.rawInput, startsWith('receipt:ocr-empty'),
          reason: '原图即用即焚，raw_input 只落描述符');
      expect(failed.suggestedDate, kTestDate,
          reason: '无小票日期 → 回退请求锚点日');
      expect(fakeAiParser.inputs, isEmpty);
    });

    test('OCR 有文本但全噪声 → 云解析 emptyResult → 手填（草稿保留预填）',
        () async {
      final parser = makeReceiptParser(
        ocrAdapter:
            FakeReceiptOcrAdapter.fromTextLines(kGarbageReceiptLines),
      );

      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture(), cloudParseConfirmed: true),
      );

      expect(result, isA<ReceiptParseFailedResult>());
      final failed = result as ReceiptParseFailedResult;
      expect(failed.draft, isNotNull,
          reason: '云解析失败 → 草稿保留（手填表单仍可预填 OCR 字段）');
      expect(failed.failure.reason, AiFailureReason.emptyResult,
          reason: '无金额语义 → 文本管线 emptyResult（§7.4 一级降级）');
      expect(failed.failure.degradeLevel, AiDegradeLevel.manualForm);
    });

    test('OCR 适配器异常（平台未实现）→ invalidRequest + manualForm', () async {
      final parser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.scripted(<Object>[
          const LlmInvalidRequestException(
              '端侧 OCR 平台通道未实现（native handler 待壳层接线，remaining）'),
        ]),
      );

      final result = await parser.parse(
        makeReceiptRequest(makeReceiptJpegFixture(), cloudParseConfirmed: true),
      ) as ReceiptParseFailedResult;

      expect(result.draft, isNull);
      expect(result.failure.reason, AiFailureReason.invalidRequest);
      expect(result.failure.degradeLevel, AiDegradeLevel.manualForm);
      expect(result.failure.errors.single, contains('[fake_receipt_ocr]'));
      expect(result.failure.cause, isA<LlmInvalidRequestException>());
    });

    test('§7.4 降级映射表与文本/拍照管线同源：超时→手填、断网→延迟队列', () async {
      final timeoutParser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.scripted(
          <Object>[const LlmTimeoutException('端侧 OCR 超时（测试）')],
        ),
      );
      final timeoutResult = await timeoutParser.parse(
        makeReceiptRequest(makeReceiptJpegFixture()),
      ) as ReceiptParseFailedResult;
      expect(timeoutResult.failure.degradeLevel, AiDegradeLevel.manualForm);

      final networkParser = makeReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.scripted(
          <Object>[const LlmNetworkException('通道桥误报断网（测试）')],
        ),
      );
      final networkResult = await networkParser.parse(
        makeReceiptRequest(makeReceiptJpegFixture()),
      ) as ReceiptParseFailedResult;
      expect(networkResult.failure.degradeLevel, AiDegradeLevel.deferredQueue,
          reason: '同一张 §7.4 映射表（端侧语义上不可达，契约一致性仍成立）');
    });
  });

  group('缓存回放（§7.1/§5.6⑭：复用文本管线 input_hash，同结构化文本命中）', () {
    test('二次解析命中缓存：文本 adapter 零调用、fromCache=true、record 复用', () async {
      final cache = InMemoryAiParseCache();
      final firstAi = LlmAiParser(
        adapter: FakeLlmAdapter.scripted(<Object>[kReceiptMoneyParseJson],
            providerId: 'fake_llm_test'),
        cache: cache,
        nowMs: fakeNowMs,
        newParseId: makeIdSeq(),
      );
      final firstParser = ReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.repeating(),
        aiParser: firstAi,
      );
      final request =
          makeReceiptRequest(makeReceiptJpegFixture(), cloudParseConfirmed: true);

      final first = await firstParser.parse(request) as ReceiptParsedResult;
      expect(first.parse.fromCache, isFalse);

      // 二次解析：脚本为空——文本 adapter 一旦被调用即抛 StateError（显式
      // 暴露意外云端调用）；OCR 端侧重跑属预期（端侧廉价，§3.7）。
      final secondParser = ReceiptParser(
        ocrAdapter: FakeReceiptOcrAdapter.repeating(),
        aiParser: LlmAiParser(
          adapter: FakeLlmAdapter.scripted(<Object>[]),
          cache: cache,
          nowMs: fakeNowMs,
          newParseId: makeIdSeq(),
        ),
      );
      final second = await secondParser.parse(request) as ReceiptParsedResult;

      expect(second.parse.fromCache, isTrue);
      expect(second.parse.record.id, first.parse.record.id,
          reason: '回放携带原 ai_parses 行（§7.1 复用 raw_output）');
      expect(second.parse.lines.single.amount, first.parse.lines.single.amount);
    });
  });
}

/// 脚本化文本管线成功项（衔接契约测试用；字段口径与本套件夹具一致）。
ParseSuccess _scriptedSuccess() {
  final lines = <ParsedLineDraft>[
    ParsedLineDraft(
      type: dom.LineType.money,
      direction: dom.LineDirection.outcome,
      amount: 1250,
      confidence: 0.93,
      currency: 'CNY',
      payload: const {'merchant': '全家便利店'},
    ),
  ];
  final record = AiParseRecord(
    id: makeIdSeq()(),
    inputKind: AiInputKind.text.wire,
    inputHash: 'hash-receipt-test',
    provider: 'fake',
    model: 'fake-model',
    rawOutput: '{"lines":[{"type":"money","amount_minor":1250}]}',
    latencyMs: 0,
    costMicro: 0,
    confidence: 0.93,
    promptVersion: kPromptVersion,
  );
  return ParseSuccess(
    title: '全家便利店',
    kind: dom.EntryKind.expense,
    lines: lines,
    inputHash: 'hash-receipt-test',
    record: record,
    fromCache: false,
  );
}
