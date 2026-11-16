/// core_ai 管线 → feature_capture `CaptureParser` 桥接（§10.4「壳负责装配」）。
///
/// 三接缝收敛的唯一实现路径（§10.4 分层）：
/// ```
/// dart-define 工厂（capture_parser_factory.dart）
///   → LlmAdapter（HeuristicFakeLlmAdapter 缺省 / OpenAiCompatibleAdapter 配 key）
///   → core_ai LlmAiParser 管线（规范化 → input_hash 缓存 → 受约束解码 →
///     校验/§7.3 映射 → 重试 1 次 → ParseSuccess / StructuredFailure）
///   → 本桥接映射为 feature_capture 的 CaptureParseResult / CaptureStructuredFailure
///   → captureControllerProvider（确认卡 / 降级手填）。
/// ```
/// 缓存归属说明：core_ai 内部缓存注入内存实现（进程内 memo）；持久
/// ai_parses 留痕与 7 天 input_hash 缓存由 feature_capture 的
/// CaptureGateway.saveAiParse/findCachedParse 落库承担（§5.6⑭ 同事务留痕）
/// ——避免同一输入双写 ai_parses 两行（两套 raw_output 格式、两套 hash
/// 命名空间）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:feature_capture/feature_capture.dart';

/// core_ai 解析管线桥（[CaptureParser] 的壳层唯一实现）。
class CoreAiCaptureParser implements CaptureParser {
  CoreAiCaptureParser({required LlmAdapter adapter, AiParseCache? cache})
      : _parser = LlmAiParser(
          adapter: adapter,
          // 进程内 memo：持久缓存/留痕由 CaptureGateway 承担（见文件头说明）。
          cache: cache ?? InMemoryAiParseCache(),
        );

  final LlmAiParser _parser;

  /// 底层 adapter（工厂测试断言装配配置用）。
  LlmAdapter get adapter => _parser.adapter;

  @override
  Future<CaptureParseResult> parse(CaptureParseRequest request) async {
    // CaptureParseRequest 不携带归属日：解析输出的日期锚点取装配时刻的
    // 本地日历日（§5.1），事件归属日由控制器落库时决定。
    final result = await _parser.parse(ParseInput(
      rawText: request.rawText,
      context: ParseContext(date: dom.formatCalendarDay(DateTime.now())),
      kind: _kind(request.inputKind),
    ));
    return switch (result) {
      ParseSuccess() => _toCaptureResult(result),
      StructuredFailure() => throw CaptureStructuredFailure(
          code: _failureCode(result.reason),
          // 控制器降级横幅已带「AI 解析失败：」前缀，此处只给原因本体。
          message: result.errors.isEmpty
              ? '解析失败（${result.reason.wire}）'
              : result.errors.first,
          cause: result.cause ?? result,
        ),
    };
  }

  // ── ParseSuccess → CaptureParseResult（§7.3 字段映射表）────────────

  CaptureParseResult _toCaptureResult(ParseSuccess success) {
    final record = success.record;
    return CaptureParseResult(
      title: success.title,
      parseNotes: success.parseNotes,
      provider: record.provider,
      model: record.model,
      promptVersion: record.promptVersion,
      latencyMs: record.latencyMs,
      costMicro: record.costMicro,
      confidence: record.confidence,
      lines: [for (final line in success.lines) _toCaptureLine(line)],
    );
  }

  CaptureParsedLine _toCaptureLine(ParsedLineDraft line) => CaptureParsedLine(
        typeWire: line.type.wire,
        amountKcal: line.type == dom.LineType.calorie ? line.amount : null,
        amountMinor: line.type == dom.LineType.money ? line.amount : null,
        confidence: line.confidence,
        categoryHint: line.categoryHint,
        currency: line.currency,
        ledgerHint: line.ledgerHint,
        merchant: line.payload?['merchant'] is String
            ? line.payload!['merchant'] as String
            : null,
        items: [
          for (final item in line.items)
            CaptureParsedItem(
              name: item.name,
              portionG: item.portionG,
              kcal: item.kcal,
              proteinG: item.proteinG,
              carbG: item.carbG,
              fatG: item.fatG,
              refSource: item.refSource.wire,
              refId: item.refId,
              confidence: item.confidence,
            ),
        ],
      );

  // ── 通道与失败原因映射（§5.6⑭ input_kind、§7.4 降级方案）──────────

  AiInputKind _kind(String inputKind) {
    for (final kind in AiInputKind.values) {
      if (kind.wire == inputKind) return kind;
    }
    return AiInputKind.text;
  }

  /// 失败原因 → 降级方案场景列（§7.4）：超时/网络/受约束失败/供应商故障。
  CaptureFailureCode _failureCode(AiFailureReason reason) => switch (reason) {
        AiFailureReason.timeout => CaptureFailureCode.timeout,
        AiFailureReason.network => CaptureFailureCode.network,
        AiFailureReason.invalidJson ||
        AiFailureReason.validationFailed ||
        AiFailureReason.emptyResult ||
        AiFailureReason.badResponse ||
        AiFailureReason.invalidRequest =>
          CaptureFailureCode.schema,
        AiFailureReason.rateLimit ||
        AiFailureReason.quota ||
        AiFailureReason.auth ||
        AiFailureReason.providerError =>
          CaptureFailureCode.provider,
      };
}
