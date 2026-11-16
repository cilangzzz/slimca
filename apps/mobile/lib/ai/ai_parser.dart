/// AI 解析管线抽象与模型（§7.1 管线总览、§10.4 apps/mobile 壳内 AI 装配）。
///
/// 分层边界（§10.4）：解析器抽象与模型放壳内 lib/ai/——W3-4 的 scope 是
/// 「壳装配」，core_ai 目前为占位包；LLM adapter 只做「协议 ↔ 模型」翻译，
/// 禁止携带落库逻辑，落库编排统一在 lib/data/ai_capture_service.dart。
///
/// 管线纪律（§7.1 红线）：
/// - **LLM 直报热量不可信**——adapter 只产出结构化数据；信任设计（置信度
///   三色点 + 一键修正闭环，§2.3 步 3/4）在确认卡交互层完成；
/// - **JSON Schema 受约束解码**：拒绝自由文本（§7.2），输出必须可映射到
///   §7.3 字段映射表；
/// - 一切解析失败（超时/网络/解码/校验不过）都抛 [AiParserException]，
///   由调用方降级手填（§2.4#3「输入页永不卡死」）。
library;

import 'dart:convert';

/// 解析输入通道（§5.6⑭ ai_parses.input_kind：text/voice/photo）。
enum AiInputKind {
  text('text'),
  voice('voice'),
  photo('photo');

  const AiInputKind(this.wire);

  /// 存储用文本（与 §5.6⑭ 枚举值一字不差）。
  final String wire;
}

/// 解析请求（§7.1 输入段：文本/语音转写；W3-4 只通文本，§11.1 W3-4）。
class AiParseRequest {
  const AiParseRequest({required this.inputKind, required this.input});

  final AiInputKind inputKind;

  /// 已规范化的输入文本（规范化见 lib/data/ai_parse_cache.dart，§7.1）。
  final String input;
}

/// 解析器抽象（§7.1「LLM adapter 可插拔」注入点、§10.4 壳负责装配）。
///
/// 实现约定（W3-4 两实现，装配见 lib/ai/ai_parser_factory.dart）：
/// - [FakeParser]（`fake_parser.dart`）：无 dart-define 配置时的确定性
///   mock——零网络、同输入恒同结果，测试与开发缺省；
/// - [OpenAiCompatAdapter]（`openai_compat_adapter.dart`）：API key 配置后
///   启用的 OpenAI 兼容协议 adapter（§7.2 受约束解码 + §7.1 校验器过闸）。
///
/// 失败语义（§7.4）：任何解析失败（超时/网络/协议/校验不过）抛
/// [AiParserException]，由 [AiCaptureService] 调用方 100% 降级手填
/// （§2.4#3「输入页永不卡死」，§11.1 W3-4 验收线）。
abstract interface class AiParser {
  /// 解析一条规范化后的输入；成功返回 [AiParseResult]，失败抛
  /// [AiParserException]（不作值返回，降级语义由调用方统一承接）。
  Future<AiParseResult> parse(AiParseRequest request);
}

/// 解析产出行类型（§7.2 lines[].type；burn 行来自 fitness_sessions，
/// 不经 LLM 产出，故枚举只有两类）。
enum AiLineType {
  calorie('calorie'),
  money('money');

  const AiLineType(this.wire);

  /// 与 §5.2② entry_lines.type 枚举同源（calorie/money）。
  final String wire;

  static AiLineType fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 AiLineType: $value（§7.2）'),
      );
}

/// 单条菜品明细（§7.2 items[]；落库为 entry_lines.payload 菜品摘要，§5.2②）。
class AiParsedItem {
  const AiParsedItem({
    required this.name,
    this.portionG,
    this.kcal,
    this.proteinG,
    this.carbG,
    this.fatG,
    this.refSource,
  });

  final String name;
  final double? portionG;
  final double? kcal;
  final double? proteinG;
  final double? carbG;
  final double? fatG;

  /// 联查来源（local/usda/openfoodfacts，§7.1 食物库联查；W3-4 无联查）。
  final String? refSource;

  /// payload 菜品摘要 JSON（snake_case，与 §7.2 items[] 字段同名）。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'portion_g': portionG,
        'kcal': kcal,
        'protein_g': proteinG,
        'carb_g': carbG,
        'fat_g': fatG,
        'ref_source': refSource,
      };

  /// [toJson] 的逆运算（字段缺失容忍——payload 是摘要非真值）。
  factory AiParsedItem.fromJson(Map<String, Object?> json) => AiParsedItem(
        name: (json['name'] as String?) ?? '',
        portionG: _asDouble(json['portion_g']),
        kcal: _asDouble(json['kcal']),
        proteinG: _asDouble(json['protein_g']),
        carbG: _asDouble(json['carb_g']),
        fatG: _asDouble(json['fat_g']),
        refSource: json['ref_source'] as String?,
      );
}

/// 解析产出行（§7.2 lines[] → §7.3 字段映射表的行级中间形态）。
///
/// [amount] 已归一到 §5.1 存储口径：calorie=kcal 整数、money=分整数——
/// 落库零换算，校验器（§7.1）直接约束本字段。
class AiParsedLine {
  const AiParsedLine({
    required this.type,
    required this.amount,
    required this.confidence,
    this.currency,
    this.categoryHint,
    this.ledgerHint,
    this.merchant,
    this.items = const [],
  });

  final AiLineType type;

  /// calorie=kcal / money=分（§5.1 存储口径）。
  final int amount;

  /// money 行币种（§5.2②，默认 CNY）。
  final String? currency;

  /// 行级置信度 0-1（§7.3：三色点 ≥0.8 绿 / 0.5-0.8 黄 / <0.5 红）。
  final double confidence;

  /// 分类建议（§7.3 category_hint → category_id，W5-6 接分类体系）。
  final String? categoryHint;

  /// 账本建议（§7.2 ledger_hint，MVP 恒默认账本 §3.4）。
  final String? ledgerHint;

  /// 商户（§7.2 merchant，可空）。
  final String? merchant;

  /// calorie 行菜品明细（§7.2 items[]）。
  final List<AiParsedItem> items;

  /// canonical JSON（snake_case；兼容 §7.2 原文键 amount_kcal/amount_minor，
  /// 便于缓存回放与排查）。
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type.wire,
        'amount': amount,
        'currency': currency,
        'confidence': confidence,
        'category_hint': categoryHint,
        'ledger_hint': ledgerHint,
        'merchant': merchant,
        'items': [for (final item in items) item.toJson()],
      };

  /// [toJson] 的逆运算；type 不认识/amount 缺失即抛 FormatException
  /// （坏行不进管线，调用方按「缓存未命中/解析失败」处理，§7.1）。
  factory AiParsedLine.fromJson(Map<String, Object?> json) {
    final typeWire = (json['type'] as String?)?.trim() ?? '';
    // amount：canonical 'amount' 优先，兼容 §7.2 原文键（§7.2 示例）。
    final amountRaw = json['amount'] ?? json['amount_kcal'] ?? json['amount_minor'];
    return AiParsedLine(
      type: AiLineType.fromWire(typeWire),
      amount: amountRaw is num ? amountRaw.round() : 0,
      currency: json['currency'] as String?,
      confidence: _clamp01(_asDouble(json['confidence']) ?? 0),
      categoryHint: json['category_hint'] as String?,
      ledgerHint: json['ledger_hint'] as String?,
      merchant: json['merchant'] as String?,
      items: [
        for (final raw in (json['items'] as List? ?? const []))
          if (raw is Map) AiParsedItem.fromJson(Map<String, Object?>.from(raw)),
      ],
    );
  }
}

/// 解析结果（§7.2 顶层结构 + 运行元数据）。
///
/// 实例即 §5.6⑭ ai_parses.raw_output 的持久化内容（canonical JSON，可回放
/// 排查）：缓存命中时经 [tryDecode] 从库内原文解回同构对象。
class AiParseResult {
  const AiParseResult({
    required this.title,
    required this.kindHint,
    required this.lines,
    this.parseNotes,
    required this.confidence,
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.latencyMs,
    required this.costMicro,
  });

  /// 事件标题建议（§7.3 title → entries.title）。
  final String title;

  /// kind 建议（§5.2① food/fitness/expense/mixed/note；落库 kind 由确认值
  /// 重新推导，本字段仅作确认卡展示参考）。
  final String kindHint;

  /// 产出行（calorie/money，§7.2 lines[]）。
  final List<AiParsedLine> lines;

  /// 解析备注（§7.2 parse_notes → entries.note 追加，可关 §3.3）。
  final String? parseNotes;

  /// 整体置信度（行缺失时行级取本值兜底）。
  final double confidence;

  /// 供应商（§5.6⑭ provider，可 A/B 对比）。
  final String provider;

  /// 模型名（§5.6⑭ model）。
  final String model;

  /// 提示词版本（§5.6⑭ prompt_version）。
  final String promptVersion;

  /// 延迟毫秒（§5.6⑭ latency_ms；管线层实测，缓存回放行保留原值）。
  final int latencyMs;

  /// 成本（微元计，§5.6⑭ cost 可审计；计量 W7-8 埋点接入前为 0）。
  final int costMicro;

  /// 第一条 calorie 行（确认卡热量区数据源；无则 null）。
  AiParsedLine? get firstKcalLine {
    for (final line in lines) {
      if (line.type == AiLineType.calorie) return line;
    }
    return null;
  }

  /// 第一条 money 行（确认卡金额区数据源；无则 null）。
  AiParsedLine? get firstMoneyLine {
    for (final line in lines) {
      if (line.type == AiLineType.money) return line;
    }
    return null;
  }

  /// canonical JSON（§5.6⑭ raw_output 持久化形态，snake_case 与 §7.2 同名）。
  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'kind': kindHint,
        'lines': [for (final line in lines) line.toJson()],
        'parse_notes': parseNotes,
        'confidence': confidence,
        'provider': provider,
        'model': model,
        'prompt_version': promptVersion,
        'latency_ms': latencyMs,
        'cost_micro': costMicro,
      };

  /// [toJson] 的逆运算；结构坏损抛 FormatException（调用方 tryDecode）。
  /// 整体置信度缺省时取行置信度最小值兜底（§7.3 行级置信度为准绳）。
  factory AiParseResult.fromJson(Map<String, Object?> json) {
    final lines = <AiParsedLine>[
      for (final raw in (json['lines'] as List? ?? const []))
        if (raw is Map) AiParsedLine.fromJson(Map<String, Object?>.from(raw)),
    ];
    double? overall = _asDouble(json['confidence']);
    if (overall == null) {
      double? min;
      for (final line in lines) {
        if (min == null || line.confidence < min) min = line.confidence;
      }
      overall = min;
    }
    return AiParseResult(
      title: ((json['title'] as String?) ?? '').trim(),
      kindHint: (json['kind'] as String?) ?? 'note',
      lines: lines,
      parseNotes: json['parse_notes'] as String?,
      confidence: _clamp01(overall ?? 0),
      provider: (json['provider'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      promptVersion: (json['prompt_version'] as String?) ?? 'unknown',
      latencyMs: _asInt(json['latency_ms']) ?? 0,
      costMicro: _asInt(json['cost_micro']) ?? 0,
    );
  }

  /// 宽松解码：缓存 raw_output / 任意来源 JSON → 结果；坏损返回 null
  /// （调用方按未命中处理，管线自愈）。
  static AiParseResult? tryDecode(String rawJson) {
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      return AiParseResult.fromJson(Map<String, Object?>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}

/// 解析失败信号（§7.4 降级方案：超时/失败/校验不过 → 调用方降级手填）。
///
/// 管线约定：任何失败都收敛为本异常原样上抛，不做静默兜底——
/// 「失败 100% 降级」的可见性由调用方保证（§11.1 W3-4 验收线）。
class AiParserException implements Exception {
  const AiParserException(this.message);

  final String message;

  @override
  String toString() => 'AiParserException: $message';
}

/// 校验器（§7.1「校验器（金额>0、kcal∈[0,5000]、分类枚举内、必需字段齐）」）。
///
/// 管线里 adapter 出口与缓存回放两处都要过闸：坏结果一律
/// [AiParserException] → 上层降级，绝不落库。
void validateAiParseResult(AiParseResult result) {
  if (result.title.isEmpty) {
    throw const AiParserException('校验失败：title 必填（§7.1 校验器）');
  }
  for (final line in result.lines) {
    if (line.type == AiLineType.calorie &&
        (line.amount < 0 || line.amount > 5000)) {
      throw AiParserException(
        '校验失败：kcal ${line.amount} 越界 [0,5000]（§7.1 校验器）',
      );
    }
    if (line.type == AiLineType.money && line.amount <= 0) {
      throw AiParserException(
        '校验失败：金额 ${line.amount} 分必须 >0（§7.1 校验器）',
      );
    }
    if (line.confidence < 0 || line.confidence > 1) {
      throw AiParserException(
        '校验失败：置信度越界 [0,1]（§5.2② AI 产出行必填）',
      );
    }
  }
  if (result.confidence < 0 || result.confidence > 1) {
    throw const AiParserException('校验失败：整体置信度越界 [0,1]（§5.2②）');
  }
}

double? _asDouble(Object? value) => value is num ? value.toDouble() : null;

int? _asInt(Object? value) => value is int ? value : (value is num ? value.round() : null);

double _clamp01(double value) => value < 0 ? 0 : (value > 1 ? 1 : value);
