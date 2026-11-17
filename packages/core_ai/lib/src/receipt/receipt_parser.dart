/// 小票解析管线（§11.2 W16 任务「小票→AI 解析衔接」「端侧优先口径（§3.7）」）。
///
/// 管线（§7.1 文本管线的上游延伸；OCR 全端侧）：
/// ```
/// 小票原图 → ReceiptOcrAdapter（端侧平台通道，禁止上云，§10.1「不传原图」）
///   → ReceiptDraft（商户/合计/时间/明细；OCR 全文仅端侧内存）
///   → 坏小票（无任何文本）→ StructuredFailure(manualForm) 手填（§7.4）
///   → [cloudParseConfirmed=false] → ReceiptPrefillResult（直接落库路径：
///     确认卡用草稿预填，零上云）
///   → [cloudParseConfirmed=true]（用户确认后宿主传入）
///     → buildReceiptStructuredText → 既有 AiParser 文本管线
///       （单边 money，§3.3 单边开关；kind=text——§5.6⑭ 枚举内，解析输入
///       即文本，OCR 本身端侧无留痕需求）
///     → ReceiptParsedResult / ReceiptParseFailedResult（复用 §7.4 降级）
/// ```
/// 「OCR 全端侧，仅用户确认后才走云解析或直接落库——不自动上云」（§3.7/W16
/// 任务口径）的落点：[ReceiptParseRequest.cloudParseConfirmed] 是宿主侧的
/// 用户确认闸门——core_ai 无法验证 UI 确认事件，契约由宿主遵守（缺省
/// false=只走端侧，无任何云端路径）。云解析阶段复用文本管线 input_hash
/// 缓存（同结构化文本 <7 天命中，§7.1/§5.6⑭）——重复识别同一小票零云端
/// 重复计费；OCR 阶段重跑属预期（端侧廉价）。
///
/// 失败一律作值返回（[ReceiptParseFailedResult]），不抛异常——§7.4「健壮性
/// 即产品体验」；唯一抛点是入口契约违例（非法日历日）。降级映射与文本/
/// 拍照管线共用同一张 §7.4 表（photo_parser.dart 同款）。
library;

import 'dart:typed_data';

import 'package:core_domain/core_domain.dart' as dom;

import '../llm/llm_adapter.dart';
import '../parse/ai_parser.dart';
import '../parse/parse_models.dart';
import 'receipt_models.dart';
import 'receipt_ocr_adapter.dart';
import 'receipt_text_bridge.dart';

/// 小票解析请求。
class ReceiptParseRequest {
  const ReceiptParseRequest({
    required this.imageBytes,
    required this.mime,
    required this.date,
    this.cloudParseConfirmed = false,
  });

  /// 小票原图字节（即用即焚：管线内不出内存，不落库不上云，§3.3 拍照通道
  /// 同款隐私纪律）。
  final Uint8List imageBytes;

  /// 原图 MIME（端侧 OCR 解码提示）。
  final String mime;

  /// 请求锚点日 `yyyy-MM-dd`（§5.1；小票日期缺失/非法时的预填回退日；
  /// 提示词日期锚点）。
  final String date;

  /// 用户确认闸门（§3.7「仅用户确认后才走云解析或直接落库」）：false（缺省）
  /// = 仅端侧 OCR → 草稿预填（直接落库路径，零上云）；true = 宿主已获用户
  /// 确认 → 结构化文本进既有 AiParser 文本管线（云解析）。
  final bool cloudParseConfirmed;
}

/// 小票解析结果（sealed；预填数据源与失败降级语义，§7.4）。
sealed class ReceiptParseResult {
  const ReceiptParseResult();

  /// 端侧 OCR 草稿（可用时）——商户/金额/日期预填的权威来源（OCR 字段比
  /// 云解析 payload 更可信：合计金额来自小票原文字面，LLM 只是转述）。
  ReceiptDraft? get draft => null;

  /// 日期预填（§5.2① entries.date 本地日历日）：小票日期（合法时）> 请求锚点日。
  String get suggestedDate;
}

/// 仅端侧草稿（[ReceiptParseRequest.cloudParseConfirmed]=false 的返回）：
/// 云解析未发生——宿主可直接用 [draft] 预填确认卡后落库（§3.7「或直接落库」，
/// 全程离线），也可在用户确认后再带 cloudParseConfirmed=true 重入管线。
/// 预填可用性以 [ReceiptDraft.hasPrefillFields] 判定（全空的坏小票在云解析
/// 路径才会得到 StructuredFailure，端侧路径如实返回空草稿）。
class ReceiptPrefillResult extends ReceiptParseResult {
  const ReceiptPrefillResult({
    required this.draft,
    required this.suggestedDate,
  });

  @override
  final ReceiptDraft draft;

  @override
  final String suggestedDate;
}

/// 云解析成功：既有文本管线的 [ParseSuccess]（单边 money 行）+ OCR 草稿。
class ReceiptParsedResult extends ReceiptParseResult {
  const ReceiptParsedResult({
    required this.draft,
    required this.parse,
    required this.suggestedDate,
  });

  @override
  final ReceiptDraft draft;

  /// 文本管线成功结果：money 行 amount=金额预填（与 [draft.totalMinor] 同源
  /// 校验）、payload.merchant=商家预填、category_hint→分类建议；ai_parses
  /// 留痕/缓存由文本管线内部完成（§5.6⑭）。
  final ParseSuccess parse;

  @override
  final String suggestedDate;
}

/// 失败（复用既有 [StructuredFailure] 降级语义，§7.4）：OCR 失败/坏小票
/// （[draft]=null → 纯手填）或云解析失败（[draft] 保留 → 手填表单仍可用
/// OCR 字段预填——「原输入保留」在金额/商家/日期上的对应物）。
class ReceiptParseFailedResult extends ReceiptParseResult {
  const ReceiptParseFailedResult({
    required this.failure,
    required this.suggestedDate,
    this.draft,
  });

  @override
  final ReceiptDraft? draft;

  /// 失败（reason/degradeLevel/errors 与文本管线同一张 §7.4 映射表）。
  final StructuredFailure failure;

  @override
  final String suggestedDate;
}

/// 小票解析器（端侧 OCR 阶段 + 确认闸门后的云解析阶段编排）。
class ReceiptParser {
  ReceiptParser({
    required this.ocrAdapter,
    required this.aiParser,
  });

  /// 端侧 OCR 适配器（§3.7 全端侧；缺省装配见 receipt_factory.dart）。
  final ReceiptOcrAdapter ocrAdapter;

  /// 既有文本解析管线（复用——与文本通道同一实例/同一缓存/同一提示词
  /// 版本，§7.1；缺省装配为 LlmAiParser+HeuristicFakeLlmAdapter 默认 mock）。
  final AiParser aiParser;

  /// 执行小票解析；预填/成功/失败都以 [ReceiptParseResult] 值返回（失败不
  /// 抛异常——§7.4；唯一抛点是入口契约违例）。
  Future<ReceiptParseResult> parse(ReceiptParseRequest request) async {
    // 入口契约：锚点日必须是本地日历日（§5.1，提示词/落库锚点）。
    dom.validateCalendarDay(request.date, name: 'date');

    // ── ① 端侧 OCR（§3.7 全端侧；原图即用即焚，字节不出适配器内存）──
    final ReceiptDraft draft;
    try {
      draft = await ocrAdapter.recognize(
        ReceiptImageInput(bytes: request.imageBytes, mime: request.mime),
      );
    } on LlmException catch (error) {
      // 通道/平台异常（§7.1 已分类）→ §7.4 降级映射 → 手填。
      return _failureFromAdapter(error, request);
    }

    // ── ② 坏小票（无任何文本）→ 一级降级手填（W16 任务口径）──
    if (!draft.hasText) {
      return ReceiptParseFailedResult(
        draft: null,
        suggestedDate: request.date,
        failure: StructuredFailure(
          reason: AiFailureReason.emptyResult,
          degradeLevel: AiDegradeLevel.manualForm,
          // rawInput 只落描述符——原图即用即焚（§3.3 同款口径）。
          rawInput: 'receipt:ocr-empty;len=${request.imageBytes.length}',
          context: ParseContext(date: request.date, mode: ParseMode.moneyOnly),
          attempts: 0,
          errors: const ['端侧 OCR 未识别到任何文本（坏小票/非小票图片，降级手填）'],
        ),
      );
    }

    // ── ③ 端侧优先闸门（§3.7）：未确认 → 只回草稿预填（直接落库路径）──
    final suggestedDate = resolveReceiptSuggestedDate(draft, request.date);
    if (!request.cloudParseConfirmed) {
      return ReceiptPrefillResult(draft: draft, suggestedDate: suggestedDate);
    }

    // ── ④ 云解析（用户已确认）：结构化文本 → 既有 AiParser 文本管线 ──
    // 单边 money 模式（§3.3；小票=消费凭据，恒支出方向）。
    final structuredText = buildReceiptStructuredText(draft);
    final parseResult = await aiParser.parse(ParseInput(
      rawText: structuredText,
      context: ParseContext(date: request.date, mode: ParseMode.moneyOnly),
      kind: AiInputKind.text,
    ));
    // sealed ParseResult 穷尽分支（编译器保证）——云解析失败也是正常业务
    // 分支（§7.4）：原结构化文本/草稿保留 → 手填预填。
    final ReceiptParseResult outcome;
    switch (parseResult) {
      case ParseSuccess success:
        outcome = ReceiptParsedResult(
          draft: draft,
          parse: success,
          suggestedDate: suggestedDate,
        );
      case StructuredFailure failure:
        outcome = ReceiptParseFailedResult(
          draft: draft,
          failure: failure,
          suggestedDate: suggestedDate,
        );
    }
    return outcome;
  }

  /// OCR 适配器异常 → §7.4 降级映射（与 ai_parser._failureFromAdapter /
  /// photo_parser._reasonFromAdapter 同一张分类表——sealed switch 穷尽由
  /// 编译器保证）。
  ReceiptParseFailedResult _failureFromAdapter(
    LlmException error,
    ReceiptParseRequest request,
  ) {
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
    return ReceiptParseFailedResult(
      draft: null,
      suggestedDate: request.date,
      failure: StructuredFailure(
        reason: reason,
        degradeLevel: level,
        rawInput: 'receipt:ocr-error;len=${request.imageBytes.length}',
        context: ParseContext(date: request.date, mode: ParseMode.moneyOnly),
        attempts: 1,
        errors: ['[${ocrAdapter.providerId}] ${error.message}'],
        cause: error,
      ),
    );
  }
}
