/// AI 解析器抽象与受约束输出模型（§7.1 AI 解析管线、§7.2 JSON Schema 受约束输出）。
///
/// 分层边界（§10.4）：LLM adapter 与 JSON Schema 解码在 core_ai；本包只定义
/// feature 层消费的解析器接口 [CaptureParser] 与注入点 [captureParserProvider]，
/// 宿主装配时将 adapter 桥接为 [CaptureParser] override 注入（§10.4「壳负责
/// 装配」）。测试一律注入 Fake 解析器，禁止真实网络调用（§3.3 离线优先）。
///
/// 红线（§7.1）：LLM 直报热量不可信——解析结果必须携带逐行置信度，并走
/// 「确认卡 + 修正闭环」管线把信任设计做成一等交互（§3.3、§2.3 步骤 3-4）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 文本解析超时（§7.4 降级方案：文本 5s 超时 → 原输入保留、降级手填）。
const Duration kCaptureParseTimeout = Duration(seconds: 5);

/// kcal 可信区间上限（§7.1 校验器「kcal∈[0,5000]」）。
const int kMaxParseKcal = 5000;

/// 解析器注入点（§10.4 壳负责装配）：宿主必须 override，
/// `captureParserProvider.overrideWithValue(adapterBridge)`。
final Provider<CaptureParser> captureParserProvider = Provider<CaptureParser>(
  (ref) => throw UnimplementedError(
    '宿主必须 override captureParserProvider（§10.4 壳负责装配）：'
    'core_ai LLM adapter 落地后桥接为 CaptureParser 注入',
  ),
);

/// AI 解析器抽象（§7.1 管线「LLM adapter → JSON Schema 受约束解码」）。
///
/// 实现方负责：受约束解码（拒绝自由文本）、字段校验、把 provider/model/
/// latency/cost 等留痕字段一并带回（§5.6⑭ ai_parses 留痕与缓存）。
abstract class CaptureParser {
  /// 解析一段规范化后的输入；失败抛 [CaptureStructuredFailure]（§7.4）。
  Future<CaptureParseResult> parse(CaptureParseRequest request);
}

/// 解析请求（§7.1「规范化 + input_hash」后的 adapter 载荷）。
class CaptureParseRequest {
  const CaptureParseRequest({
    required this.rawText,
    required this.normalizedText,
    required this.inputHash,
    required this.inputKind,
  });

  /// 用户原文（raw_input 上云开关默认关=即用即焚，§3.3；adapter 不留档）。
  final String rawText;

  /// 规范化文本（[CaptureInputNormalizer.normalize]）。
  final String normalizedText;

  /// sha256(规范化输入)=缓存键（§7.1、§5.6⑭）。
  final String inputHash;

  /// 输入通道：text / voice / photo（§5.6⑭ input_kind）。
  final String inputKind;
}

/// 菜品明细（§7.2 lines[].items、§5.2③ food_items 字段口径）。
class CaptureParsedItem {
  const CaptureParsedItem({
    required this.name,
    required this.portionG,
    required this.kcal,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.refSource = 'local',
    this.refId,
    required this.confidence,
  });

  final String name;

  /// 份量（克）——滑杆联动重算的基准（§5.2③）。
  final double portionG;
  final int kcal;
  final double proteinG;
  final double carbG;
  final double fatG;

  /// 联查来源：usda / off / baidu / local / llm（§5.2③ ref_source）。
  final String refSource;
  final String? refId;
  final double confidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'portion_g': portionG,
        'kcal': kcal,
        'protein_g': proteinG,
        'carb_g': carbG,
        'fat_g': fatG,
        'ref_source': refSource,
        'ref_id': refId,
        'confidence': confidence,
      };

  static CaptureParsedItem fromJson(Map<String, Object?> json) =>
      CaptureParsedItem(
        name: json['name'] as String,
        portionG: (json['portion_g'] as num).toDouble(),
        kcal: json['kcal'] as int,
        proteinG: ((json['protein_g'] as num?) ?? 0).toDouble(),
        carbG: ((json['carb_g'] as num?) ?? 0).toDouble(),
        fatG: ((json['fat_g'] as num?) ?? 0).toDouble(),
        refSource: (json['ref_source'] as String?) ?? 'local',
        refId: json['ref_id'] as String?,
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// 解析产出行（§7.2 lines[]：calorie=热量行 / money=金额行）。
class CaptureParsedLine {
  const CaptureParsedLine({
    required this.typeWire,
    required this.confidence,
    this.amountKcal,
    this.amountMinor,
    this.categoryHint,
    this.currency,
    this.ledgerHint,
    this.merchant,
    this.items = const [],
  });

  /// `calorie` / `money`（§5.2② type；wire 文本与 LineType 枚举同构）。
  final String typeWire;

  bool get isCalorie => typeWire == 'calorie';
  bool get isMoney => typeWire == 'money';

  /// 热量行：kcal（§7.2 amount_kcal）。
  final int? amountKcal;

  /// 金额行：分（§7.2 amount_minor）。
  final int? amountMinor;

  /// AI 置信度 0-1（§7.3 lines[].confidence → entry_lines.confidence）。
  final double confidence;

  /// 分类建议（§7.3 category_hint → category_id）。
  final String? categoryHint;
  final String? currency;
  final String? ledgerHint;
  final String? merchant;

  /// 菜品明细（calorie 行携带，§7.2）。
  final List<CaptureParsedItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': typeWire,
        'amount_kcal': amountKcal,
        'amount_minor': amountMinor,
        'confidence': confidence,
        'category_hint': categoryHint,
        'currency': currency,
        'ledger_hint': ledgerHint,
        'merchant': merchant,
        'items': [for (final item in items) item.toJson()],
      };

  static CaptureParsedLine fromJson(Map<String, Object?> json) =>
      CaptureParsedLine(
        typeWire: json['type'] as String,
        amountKcal: json['amount_kcal'] as int?,
        amountMinor: json['amount_minor'] as int?,
        confidence: (json['confidence'] as num).toDouble(),
        categoryHint: json['category_hint'] as String?,
        currency: json['currency'] as String?,
        ledgerHint: json['ledger_hint'] as String?,
        merchant: json['merchant'] as String?,
        items: [
          for (final item in (json['items'] as List<Object?>? ?? const []))
            CaptureParsedItem.fromJson((item as Map).cast<String, Object?>()),
        ],
      );
}

/// 解析结果（§7.2 受约束输出；可 JSON 序列化以落 ai_parses.raw_output 缓存，
/// §5.6⑭「命中且 <7 天直接复用」）。
class CaptureParseResult {
  const CaptureParseResult({
    required this.title,
    required this.lines,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.latencyMs,
    required this.costMicro,
    required this.confidence,
    this.parseNotes,
  });

  /// 事件标题建议（§7.3 title → entries.title）。
  final String title;
  final List<CaptureParsedLine> lines;

  /// 解析备注（§7.3 parse_notes → entries.note）。
  final String? parseNotes;

  /// 留痕字段（§5.6⑭ provider / model / prompt_version / latency_ms / cost）。
  final String provider;
  final String model;
  final String promptVersion;

  /// 延迟（毫秒）。
  final int latencyMs;

  /// 成本（微元计，可审计，§5.6⑭）。
  final int costMicro;

  /// 解析整体置信度（§5.6⑭ confidence）。
  final double confidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'parse_notes': parseNotes,
        'provider': provider,
        'model': model,
        'prompt_version': promptVersion,
        'latency_ms': latencyMs,
        'cost_micro': costMicro,
        'confidence': confidence,
        'lines': [for (final line in lines) line.toJson()],
      };

  static CaptureParseResult fromJson(Map<String, Object?> json) =>
      CaptureParseResult(
        title: json['title'] as String,
        parseNotes: json['parse_notes'] as String?,
        provider: (json['provider'] as String?) ?? 'unknown',
        model: (json['model'] as String?) ?? 'unknown',
        promptVersion: (json['prompt_version'] as String?) ?? 'v0',
        latencyMs: (json['latency_ms'] as int?) ?? 0,
        costMicro: (json['cost_micro'] as int?) ?? 0,
        confidence: ((json['confidence'] as num?) ?? 0).toDouble(),
        lines: [
          for (final line in (json['lines'] as List<Object?>? ?? const []))
            CaptureParsedLine.fromJson((line as Map).cast<String, Object?>()),
        ],
      );

  /// 校验器（§7.1「金额>0、kcal∈[0,5000]、必需字段齐」）。
  ///
  /// 返回 null=可用；非 null=结构化失败原因（→ 自动降级手填，§7.4）。
  String? checkUsable() {
    if (title.trim().isEmpty) return '解析结果缺少标题';
    if (lines.isEmpty) return '解析结果没有产出行';
    for (final line in lines) {
      if (line.confidence < 0 || line.confidence > 1) {
        return '解析置信度超出 [0,1]';
      }
      if (line.isCalorie) {
        final kcal = line.amountKcal;
        if (kcal == null || kcal < 0 || kcal > kMaxParseKcal) {
          return '热量超出可信区间 [0, $kMaxParseKcal]';
        }
      } else if (line.isMoney) {
        final minor = line.amountMinor;
        if (minor == null || minor <= 0) return '金额必须大于 0';
      }
    }
    return null;
  }
}

/// 结构化解析失败（§7.4 降级方案：超时/失败 → 原输入保留 → 自动降级手填，
/// 输入页永不卡死——AI 是增强而非依赖，§2.4-3）。
class CaptureStructuredFailure implements Exception {
  const CaptureStructuredFailure({
    required this.code,
    required this.message,
    this.cause,
  });

  final CaptureFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'CaptureStructuredFailure(${code.name}, $message)';
}

/// 失败分类（§7.4 降级方案场景列）。
enum CaptureFailureCode {
  /// 文本 5s 超时（§7.4）。
  timeout,

  /// 断网/网络不可达。
  network,

  /// JSON Schema 受约束解码/校验器拒绝（§7.1）。
  schema,

  /// 供应商单点故障（§7.4 双供应商 fallback 之外的最后兜底）。
  provider,
}

/// 输入规范化与 input_hash（§7.1「规范化 + input_hash（sha256）」）。
abstract final class CaptureInputNormalizer {
  /// 输入通道常量：文本（§5.6⑭ input_kind）。
  static const String kindText = 'text';

  /// 规范化：去首尾空白 + 连续空白折叠为单空格（缓存命中口径，§7.1）。
  static String normalize(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// sha256(规范化输入)=缓存键（§5.6⑭ input_hash）。
  static String inputHash(String normalized) =>
      sha256.convert(utf8.encode(normalized)).toString();
}
