/// AiParser 管线编排（§7.1 管线总览、§7.4 降级、§3.3 单边开关）。
///
/// 管线（§7.1，W3-4 文本范围；「食物库联查校准」以 [AiRefCalibrator] 钩子
/// 预留、缺省透传；「确认卡/落库」属 feature 层）：
/// ```
/// 输入 → 规范化 + input_hash → 缓存命中(<7 天)→回放
///      → LLM adapter（受约束请求）→ 受约束 JSON 解码
///      → 校验器（§7.1 硬闸门）→ 联查校准钩子 → ParseSuccess
/// 校验失败 → 带纠错回喂重试 1 次 → 仍失败 → StructuredFailure（一级降级）
/// ```
/// 失败一律作值返回（[StructuredFailure]），不抛异常——§7.4「健壮性即产品
/// 体验」：降级是正常业务分支。适配器异常按 §7.1 错误分类映射为失败原因
/// 与降级级别（超时→手填；断网→延迟队列；额度→提示；其余→手填）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;

import '../cache/ai_parse_cache.dart';
import '../llm/llm_adapter.dart';
import 'parse_categories.dart';
import 'parse_models.dart';
import 'parse_schema.dart';
import 'parse_validator.dart';

/// 解析器抽象（feature 层依赖此接口；测试注入 [FakeAiParser]）。
abstract interface class AiParser {
  /// 解析一条输入；成功/失败都以 [ParseResult] 值返回。
  Future<ParseResult> parse(ParseInput input);
}

/// 食物库联查校准钩子（§7.1 管线第 6 步「食物库联查校准」的接缝）。
///
/// W3-4 文本闭环不接库（USDA CC0 + OpenFoodFacts ODbL 本地快表为后续
/// 里程碑项）：缺省 [PassthroughRefCalibrator] 透传；接入快表后由宿主
/// 注入实现，改写 item 的 kcal/ref_source/ref_id（是否回写行级金额由
/// 实现自行决定并在 parse_notes 说明）。
abstract interface class AiRefCalibrator {
  ParsedFoodItemDraft calibrate(ParsedFoodItemDraft item);
}

/// 透传校准（W3-4 缺省：LLM 直报不校准，ref_source 保持 llm/local）。
class PassthroughRefCalibrator implements AiRefCalibrator {
  const PassthroughRefCalibrator();

  @override
  ParsedFoodItemDraft calibrate(ParsedFoodItemDraft item) => item;
}

/// 基于 LLM adapter 的解析器实现（§7.1 管线编排）。
///
/// [nowMs]/[newParseId] 可注入（测试确定性）；缺省墙钟 + core_db
/// UUIDv7（§5.1，id 内嵌时间 → 缓存 7 天时效判定依据，§5.6⑭）。
class LlmAiParser implements AiParser {
  LlmAiParser({
    required this.adapter,
    required this.cache,
    CategoryResolver? categoryResolver,
    this.refCalibrator = const PassthroughRefCalibrator(),
    int Function()? nowMs,
    String Function()? newParseId,
    this.cacheTtl = kAiParseCacheTtl,
    this.maxValidationAttempts = 2,
  })  : categoryResolver = categoryResolver ?? const PresetCategoryResolver(),
        _nowMs = nowMs ?? _defaultNowMs,
        _newParseId =
            newParseId ?? (() => cdb.generateUuidV7());

  final LlmAdapter adapter;
  final AiParseCache cache;
  final CategoryResolver categoryResolver;
  final AiRefCalibrator refCalibrator;

  /// 缓存时效（§5.6⑭：<7 天）。
  final Duration cacheTtl;

  /// 校验尝试上限（=1 次首发 + 1 次纠错重试，§7.1「校验失败重试 1 次」）。
  final int maxValidationAttempts;

  final int Function() _nowMs;
  final String Function() _newParseId;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<ParseResult> parse(ParseInput input) async {
    // 入口契约：日期必须是本地日历日（§5.1，提示词锚点）。
    dom.validateCalendarDay(input.context.date, name: 'context.date');

    final normalized = normalizeParseInput(input.rawText);
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        input.rawText,
        'rawText',
        '规范化后为空，无法解析（调用方应在 UI 层拦截空输入）',
      );
    }
    final inputHash = computeInputHash(normalized, input.context.mode);

    // ── 缓存命中（§7.1：ai_parses <7 天 → 直接复用 raw_output 回放）──
    // prompt_version 不同的历史记录视为未命中（提示词语义已变，§5.6⑭）。
    final cached = await cache.find(inputHash);
    if (cached != null &&
        cached.promptVersion == kPromptVersion &&
        cached.isFreshAt(_nowMs(), ttl: cacheTtl)) {
      try {
        final replay = _validated(cached.rawOutput, input.context.mode);
        return _successFrom(
          replay,
          inputHash: inputHash,
          record: cached,
          fromCache: true,
          extraNotes: const ['input_hash 缓存命中（<7 天，§5.6⑭）'],
        );
      } on AiValidationException {
        // 缓存行损坏（不应发生）：视为未命中，走实时管线。
      }
    }

    // ── 实时管线：组 prompt → 受约束请求 → 解码/校验（§7.1-§7.2）──
    final messages = <LlmMessage>[
      LlmMessage(
        LlmRole.system,
        buildSystemPrompt(
          mode: input.context.mode,
          date: input.context.date,
          presetCategories: categoryResolver.knownCategoryNames,
        ),
      ),
      LlmMessage(LlmRole.user, normalized),
    ];
    final request = LlmRequest(
      messages: messages,
      jsonIntent: LlmJsonIntent.jsonSchema,
      jsonSchema: buildParseJsonSchema(input.context.mode),
      temperature: 0.2,
    );

    var latencyMs = 0;
    var costMicro = 0;
    String? lastRawOutput;
    List<String> lastErrors = const [];
    var lastReason = AiFailureReason.validationFailed;
    // 校验尝试（=1 首发 + 1 纠错重试，§7.1「校验失败重试 1 次」）。
    for (var attempt = 1; attempt <= maxValidationAttempts; attempt++) {
      LlmResponse response;
      try {
        response = await adapter.complete(request);
      } on LlmException catch (error) {
        // 适配器已完成错误分类（§7.1）与瞬时重试：这里映射为失败原因 +
        // 降级级别（§7.4），不再叠加解析级重试。
        return _failureFromAdapter(error, input, attempts: attempt);
      }
      latencyMs += response.latencyMs;
      costMicro += response.costMicro;
      lastRawOutput = response.content;

      try {
        final validated = _validated(response.content, input.context.mode);
        // 成功收尾：写 ai_parses 留痕（§5.6⑭）→ ParseSuccess。
        return await _finishFresh(
          validated: validated,
          rawOutput: response.content,
          input: input,
          inputHash: inputHash,
          latencyMs: latencyMs,
          costMicro: costMicro,
        );
      } on AiValidationException catch (validationError) {
        lastErrors = validationError.errors;
        lastReason = validationError.reason;
        if (attempt < maxValidationAttempts) {
          // 纠错回喂（§7.1：校验失败重试 1 次）：附上轮输出与错误清单。
          messages
            ..add(LlmMessage(LlmRole.assistant, response.content))
            ..add(LlmMessage(LlmRole.user, buildRetryInstruction(lastErrors)));
        }
      }
    }
    // 重试后仍失败 → StructuredFailure（§7.4 一级降级：原输入保留 → 手填）。
    return StructuredFailure(
      reason: lastReason,
      degradeLevel: AiDegradeLevel.manualForm,
      rawInput: input.rawText,
      context: input.context,
      attempts: maxValidationAttempts,
      errors: lastErrors,
      lastRawOutput: lastRawOutput,
    );
  }

  // ── 内部辅助 ────────────────────────────────────────────────────

  /// 校验 + §7.3 映射 + 联查校准钩子（§7.1 第 5-6 步）；
  /// 字段级违例抛 [AiValidationException]（交重试/失败分支）。
  ValidatedParse _validated(String rawOutput, ParseMode mode) {
    final validated = validateAndMap(
      rawOutput: rawOutput,
      mode: mode,
      categoryResolver: categoryResolver,
    );
    return _calibrated(validated);
  }

  /// 应用联查校准钩子（W3-4 缺省透传，§7.1 第 6 步接缝）。
  ValidatedParse _calibrated(ValidatedParse validated) {
    if (refCalibrator is PassthroughRefCalibrator) {
      return validated;
    }
    final lines = [
      for (final line in validated.lines)
        line.items.isEmpty
            ? line
            : ParsedLineDraft(
                type: line.type,
                direction: line.direction,
                amount: line.amount,
                confidence: line.confidence,
                ledgerHint: line.ledgerHint,
                categoryId: line.categoryId,
                categoryHint: line.categoryHint,
                categorySuggestNew: line.categorySuggestNew,
                currency: line.currency,
                items: [
                  for (final item in line.items) refCalibrator.calibrate(item),
                ],
                payload: line.payload,
              ),
    ];
    return ValidatedParse(
      title: validated.title,
      kind: validated.kind,
      lines: lines,
      parseNotes: validated.parseNotes,
      notes: validated.notes,
    );
  }

  /// 写缓存留痕（§5.6⑭）并组装成功结果。
  Future<ParseSuccess> _finishFresh({
    required ValidatedParse validated,
    required String rawOutput,
    required ParseInput input,
    required String inputHash,
    required int latencyMs,
    required int costMicro,
  }) async {
    final record = AiParseRecord(
      id: _newParseId(),
      inputKind: input.kind.wire,
      inputHash: inputHash,
      provider: adapter.providerId,
      model: adapter.modelId,
      rawOutput: rawOutput,
      latencyMs: latencyMs,
      costMicro: costMicro,
      confidence: _minConfidence(validated.lines),
      promptVersion: kPromptVersion,
    );
    await cache.save(record);
    return _successFrom(
      validated,
      inputHash: inputHash,
      record: record,
      fromCache: false,
    );
  }

  ParseSuccess _successFrom(
    ValidatedParse validated, {
    required String inputHash,
    required AiParseRecord record,
    required bool fromCache,
    List<String> extraNotes = const [],
  }) =>
      ParseSuccess(
        title: validated.title,
        kind: validated.kind,
        lines: validated.lines,
        parseNotes: validated.parseNotes,
        inputHash: inputHash,
        record: record,
        fromCache: fromCache,
        notes: [...validated.notes, ...extraNotes],
      );

  /// 适配器异常 → 失败原因 + 降级级别（§7.4 降级映射）：
  /// 超时/解析失败 → 一级手填（内建）；断网 → 二级延迟队列（接口预留）；
  /// 额度耗尽 → 三级额度提示（接口预留）；四级双供应商 fallback 由编排层
  /// 组合多个 adapter 实现（接口预留），单 adapter 管线内不产出该级别。
  StructuredFailure _failureFromAdapter(
    LlmException error,
    ParseInput input, {
    required int attempts,
  }) {
    final (reason, level) = switch (error) {
      LlmServerException() => (
        AiFailureReason.providerError,
        AiDegradeLevel.manualForm
      ),
      LlmTimeoutException() => (
        AiFailureReason.timeout,
        AiDegradeLevel.manualForm
      ),
      LlmNetworkException() => (
        AiFailureReason.network,
        AiDegradeLevel.deferredQueue
      ),
      LlmQuotaException() => (AiFailureReason.quota, AiDegradeLevel.quotaNotice),
      LlmRateLimitException() => (
        AiFailureReason.rateLimit,
        AiDegradeLevel.manualForm
      ),
      LlmAuthException() => (AiFailureReason.auth, AiDegradeLevel.manualForm),
      LlmInvalidRequestException() => (
        AiFailureReason.invalidRequest,
        AiDegradeLevel.manualForm
      ),
      LlmBadResponseException() => (
        AiFailureReason.badResponse,
        AiDegradeLevel.manualForm
      ),
    };
    return StructuredFailure(
      reason: reason,
      degradeLevel: level,
      rawInput: input.rawText,
      context: input.context,
      attempts: attempts,
      errors: [error.message],
      lastRawOutput: null,
      cause: error,
    );
  }

  /// 全行最小置信度（最弱 facet 决定 ai_parses.confidence 与确认卡高亮档）。
  static double _minConfidence(List<ParsedLineDraft> lines) {
    var min = 1.0;
    for (final line in lines) {
      if (line.confidence < min) {
        min = line.confidence;
      }
    }
    return min;
  }
}
