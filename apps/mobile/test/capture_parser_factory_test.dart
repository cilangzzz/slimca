// W3-4 收敛后壳层解析器装配单测（§11.1 W3-4 任务项 1、§10.4「壳负责装配」）。
//
// 三接缝收敛后的装配链（§10.4）：dart-define 工厂 createCaptureParser →
// LlmAdapter（缺省 HeuristicFakeLlmAdapter / 配 key 后 OpenAiCompatibleAdapter）
// → core_ai LlmAiParser 管线 → CoreAiCaptureParser 桥 → feature_capture
// CaptureParser 注入点。覆盖：
// - createCaptureParser：缺省（无 dart-define）→ 确定性离线桩桥（默认 mock）；
//   给了 key → OpenAiCompatibleAdapter 且 base/key/model/档位/超时正确
//   （base/model 缺省回落 §7.5 口径；自定义模型降 json_object 宽档）；
// - HeuristicFakeLlmAdapter：确定性抽取（同输入恒同输出）；
// - core_ai 管线（缺省装配路径）：成功 → ParseSuccess（缓存回放命中）；
//   纯描述 → emptyResult → StructuredFailure（重试 1 次后仍失败）；
// - CoreAiCaptureParser 桥：ParseSuccess → CaptureParseResult（checkUsable
//   通过、字段映射）→ StructuredFailure → CaptureStructuredFailure(schema)。
//
// 装配说明：`String.fromEnvironment` 是编译期常量——集成统一跑
// `flutter test`（不注入 SLIMCA_AI_*），常量均为空串；工厂以显式参数
// 覆盖常量读取（运行期行为与 dart-define 注入后等价）。
// 全文件零网络调用：OpenAI adapter 只测配置，不发起真实请求。

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:feature_capture/feature_capture.dart'
    show CaptureFailureCode, CaptureParseRequest, CaptureStructuredFailure;
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/capture_parser_bridge.dart';
import 'package:slimca/ai/capture_parser_factory.dart';

ParseInput _input(String text) => ParseInput(
      rawText: text,
      context: ParseContext(date: dom.formatCalendarDay(DateTime.now())),
    );

void main() {
  group('createCaptureParser：dart-define 装配工厂（§11.1 W3-4）', () {
    test('缺省（未注入 dart-define）→ core_ai 确定性离线桩桥（默认 mock）', () {
      // 测试环境无 SLIMCA_AI_* 注入 → key 常量为空串 → 离线桩。
      final parser = createCaptureParser();
      expect(parser, isA<CoreAiCaptureParser>());
      expect(
        (parser as CoreAiCaptureParser).adapter,
        isA<HeuristicFakeLlmAdapter>(),
      );
    });

    test('显式空配置（等价 dart-define 全缺省）→ 离线桩桥', () {
      final parser = createCaptureParser(baseUrl: '', apiKey: '', model: '');
      expect(
        (parser as CoreAiCaptureParser).adapter,
        isA<HeuristicFakeLlmAdapter>(),
      );
    });

    test('key 为空串视为未配置 → 离线桩桥（即使给了 base/model）', () {
      final parser = createCaptureParser(
        baseUrl: 'https://api.example.com/v1',
        apiKey: '',
        model: 'gpt-4o-mini',
      );
      expect(
        (parser as CoreAiCaptureParser).adapter,
        isA<HeuristicFakeLlmAdapter>(),
      );
    });

    test('给了 key → OpenAiCompatibleAdapter，配置按注入值正确装配', () {
      final parser = createCaptureParser(
        baseUrl: 'https://api.example.com/v1',
        apiKey: 'sk-test-123',
        model: 'glm-4.6',
      );
      final adapter =
          (parser as CoreAiCaptureParser).adapter as OpenAiCompatibleAdapter;
      expect(adapter.config.baseUrl, 'https://api.example.com/v1');
      expect(adapter.config.apiKey, 'sk-test-123');
      expect(adapter.config.model, 'glm-4.6');
      // 文本超时按 §7.4 降级方案表：5s。
      expect(adapter.config.timeout, const Duration(seconds: 5));
      // 自定义模型：json_object 宽档（兼容端点未必支持 json_schema 信封，
      // 正确性由 core_ai 校验器兜底）。
      expect(adapter.config.jsonCapability, LlmJsonCapability.jsonObject);
    });

    test('只给 key → base/model 缺省回落（§7.5：OpenAI 兼容 + GPT-4o-mini）', () {
      final parser = createCaptureParser(apiKey: 'sk-only-key');
      final adapter =
          (parser as CoreAiCaptureParser).adapter as OpenAiCompatibleAdapter;
      expect(adapter.config.baseUrl, kDefaultAiBaseUrl);
      expect(adapter.config.baseUrl, 'https://api.openai.com/v1');
      expect(adapter.config.model, kDefaultAiModel);
      expect(adapter.config.model, 'gpt-4o-mini');
      // 缺省模型：json_schema 受约束输出最高档（§7.2）。
      expect(adapter.config.jsonCapability, LlmJsonCapability.jsonSchema);
    });
  });

  group('core_ai LlmAiParser 管线（缺省装配路径，§7.1-§7.4）', () {
    test('「午餐 500kcal 花了18」→ 双行产出；同输入二次解析命中缓存回放', () async {
      final parser = LlmAiParser(
        adapter: const HeuristicFakeLlmAdapter(),
        cache: InMemoryAiParseCache(),
      );

      final fresh = await parser.parse(_input('午餐 500kcal 花了18'));
      fresh as ParseSuccess;
      expect(fresh.title, '午餐 500kcal 花了18');
      expect(fresh.kind, dom.EntryKind.mixed);
      expect(fresh.fromCache, isFalse);
      // 热量行（§5.1 整数 kcal）+ 金额行（分，§5.1）。
      final kcalLine = fresh.lines
          .where((l) => l.type == dom.LineType.calorie)
          .toList(growable: false);
      final moneyLine = fresh.lines
          .where((l) => l.type == dom.LineType.money)
          .toList(growable: false);
      expect(kcalLine, hasLength(1));
      expect(kcalLine.single.amount, 500);
      expect(kcalLine.single.confidence, 0.62);
      expect(kcalLine.single.categoryHint, '餐饮-正餐');
      expect(moneyLine, hasLength(1));
      expect(moneyLine.single.amount, 1800, reason: '18 元 → 1800 分（§5.1）');
      expect(moneyLine.single.confidence, 0.93);
      expect(moneyLine.single.currency, 'CNY');
      expect(moneyLine.single.ledgerHint, 'default');
      // 留痕（§5.6⑭）：provider/model/prompt_version/latency/cost。
      expect(fresh.record.provider, 'fake');
      expect(fresh.record.model, 'fake-deterministic-v1');
      expect(fresh.record.promptVersion, kPromptVersion);
      expect(fresh.record.latencyMs, 0);
      expect(fresh.record.costMicro, 0);
      expect(fresh.record.confidence, 0.62, reason: '全行最小置信度');
      expect(fresh.inputHash, isNotEmpty);

      // 同输入二次解析 → input_hash 缓存命中（<7 天，§7.1/§5.6⑭）。
      final replay = await parser.parse(_input('午餐 500kcal 花了18'));
      replay as ParseSuccess;
      expect(replay.fromCache, isTrue);
      expect(replay.record.id, fresh.record.id);
    });

    test('纯描述（无数值可抽取）→ emptyResult → StructuredFailure（重试 1 次）',
        () async {
      final parser = LlmAiParser(
        adapter: const HeuristicFakeLlmAdapter(),
        cache: InMemoryAiParseCache(),
      );
      final result = await parser.parse(_input('今天心情不错'));
      expect(result, isA<StructuredFailure>());
      final failure = result as StructuredFailure;
      expect(failure.reason, AiFailureReason.emptyResult);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm,
          reason: '§7.4 一级降级：原输入保留 → 手填');
      expect(failure.attempts, 2, reason: '1 次首发 + 1 次纠错重试');
      expect(failure.rawInput, '今天心情不错', reason: '§7.4 原输入保留');
    });
  });

  group('CoreAiCaptureParser 桥（core_ai → feature_capture，§10.4）', () {
    CaptureParseRequest request(String text) => CaptureParseRequest(
          rawText: text,
          normalizedText: text,
          inputHash: 'bridge-test-hash',
          inputKind: 'text',
        );

    test('ParseSuccess → CaptureParseResult（checkUsable 通过、字段映射）',
        () async {
      final parser = CoreAiCaptureParser(adapter: const HeuristicFakeLlmAdapter());
      final result = await parser.parse(request('午餐 500kcal 花了18'));

      expect(result.checkUsable(), isNull, reason: '§7.1 校验器同构产出必过');
      expect(result.title, '午餐 500kcal 花了18');
      expect(result.provider, 'fake');
      expect(result.model, 'fake-deterministic-v1');
      expect(result.promptVersion, kPromptVersion);
      expect(result.confidence, 0.62);
      expect(result.parseNotes, isNotNull);

      final kcalLine = result.lines.where((l) => l.isCalorie).single;
      expect(kcalLine.amountKcal, 500);
      expect(kcalLine.amountMinor, isNull);
      expect(kcalLine.confidence, 0.62);
      expect(kcalLine.categoryHint, '餐饮-正餐');
      final moneyLine = result.lines.where((l) => l.isMoney).single;
      expect(moneyLine.amountMinor, 1800);
      expect(moneyLine.amountKcal, isNull);
      expect(moneyLine.currency, 'CNY');
      expect(moneyLine.ledgerHint, 'default');
    });

    test('StructuredFailure → CaptureStructuredFailure（schema 类，§7.4）',
        () async {
      final parser = CoreAiCaptureParser(adapter: const HeuristicFakeLlmAdapter());
      expect(
        () => parser.parse(request('今天心情不错')),
        throwsA(isA<CaptureStructuredFailure>()),
      );
      try {
        await parser.parse(request('今天心情不错'));
      } on CaptureStructuredFailure catch (failure) {
        expect(failure.code, CaptureFailureCode.schema,
            reason: 'emptyResult 归受约束失败（§7.4 降级方案）');
        expect(failure.message, isNotEmpty);
      }
    });
  });
}
