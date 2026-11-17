/// Vision LLM 菜品识别适配器（§3.3 拍照通道「Vision LLM 兜底（双供应商防
/// 单点）」、§7.4 第 4 级 fallback 兜底侧、§11.2 W11-12 主线）。
///
/// 复用既有 OpenAI 兼容适配器（openai_adapter.dart）的 vision 能力：
/// - 供应商：Qwen-VL / GLM-4V 等已备案兼容端点（LlmModelPreset.vision=true
///   预设，§7.5；GPT-4o-mini 非视觉模型不可用于本通道）；
/// - 请求：多模态 content 数组（text + image_url，data url 内联端侧压缩图
///   ——即用即焚不落档，§3.3）；
/// - 响应：走 §7.2 JSON Schema 受约束口径（schema 用
///   `buildParseJsonSchema(ParseMode.kcalOnly)`，单边热量行；json_object
///   宽档 + 校验器兜底——兼容端点对 json_schema 信封支持参差）；
/// - 错误：底层 adapter 已按 LlmException 分类并完成瞬时重试，本类原样
///   上抛（拍照管线共用一张 §7.4 降级映射表）。
///
/// 红线（§7.1）：LLM 直报热量不可信——模型 kcal 只换算为每百克参考
/// （[DishCandidate.kcalPer100gHint]）随候选带回，落库前必经食物库联查
/// 校准（photo_parser.dart [DishRefLookup] 钩子），未命中则置信度降档。
///
/// 待凭据联调（remaining）：真实 Vision API key 未提供，缺省装配不启用
/// 本适配器（dart-define 工厂缺省 Fake）；联调项=json_object 档在
/// Qwen-VL/GLM-4V 端点的遵循度与按图计价成本实测（§7.5）。
library;

import 'dart:convert';

import '../llm/llm_adapter.dart';
import '../parse/parse_models.dart' show FoodRefSource, ParseMode;
import '../parse/parse_schema.dart' show buildParseJsonSchema, buildPhotoSystemPrompt;
import '../parse/parse_validator.dart'
    show AiValidationException, extractJsonPayload;
import 'photo_models.dart';

/// Vision LLM 菜品识别适配器（[ImageDishAdapter] 兜底侧实现，§7.4）。
class VisionLlmDishAdapter implements ImageDishAdapter {
  VisionLlmDishAdapter({
    required LlmAdapter adapter,
    this.timeout = const Duration(seconds: 12),
    this.maxDishes = 6,
    String? systemPromptOverride,
  })  : _adapter = adapter,
        _systemPrompt = systemPromptOverride ?? buildPhotoSystemPrompt();

  /// 底层 OpenAI 兼容适配器（vision 预设；超时/重试/错误分类由其承担）。
  final LlmAdapter _adapter;

  /// 单次调用超时（§7.4 拍照 12s 口径，经 LlmRequest.timeoutOverride 放宽）。
  final Duration timeout;

  /// 最多返回的候选数（§3.3 确认卡容量口径）。
  final int maxDishes;

  final String _systemPrompt;

  /// 用户侧指令（与图像同段序列）。
  static const String _kUserInstruction =
      '识别这张照片中的所有菜品，按系统提示输出受约束 JSON。';

  @override
  String get providerId => _adapter.providerId;

  @override
  String get modelId => _adapter.modelId;

  @override
  FoodRefSource get dishRefSource => FoodRefSource.llm;

  @override
  Future<List<DishCandidate>> recognize(CompressedImage image) async {
    final response = await _adapter.complete(LlmRequest(
      messages: <LlmMessage>[
        LlmMessage(LlmRole.system, _systemPrompt),
        LlmMessage.parts(LlmRole.user, <LlmContentPart>[
          LlmTextPart(_kUserInstruction),
          // 压缩规范形内联 data url（§3.3 即用即焚：字节不落档，随请求即焚）。
          LlmImageUrlPart(_dataUrl(image)),
        ]),
      ],
      jsonIntent: LlmJsonIntent.jsonSchema,
      // §7.2 受约束口径（单边热量行分支）；capability=json_object 的模型
      // 自动降为宽档，硬闸门在 parse 层校验器（§7.1）。
      jsonSchema: buildParseJsonSchema(ParseMode.kcalOnly),
      temperature: 0.2,
      timeoutOverride: timeout,
    ));
    return extractDishes(response.content, maxDishes: maxDishes);
  }

  /// 端侧压缩规范形 → data url（image_url 段载荷）。
  String _dataUrl(CompressedImage image) =>
      'data:${image.mime};base64,${base64Encode(image.bytes)}';
}

/// 从 Vision 模型响应文本提取菜品候选（§7.2 受约束 JSON → DishCandidate）。
///
/// 宽容入口（§7.1「拒绝自由文本」的对称面）：经 extractJsonPayload 剥离
/// markdown 围栏/前后缀；行级菜品字段缺失/非法逐项跳过；全部不可用或无
/// 菜品 → 空列表（编排层据此切换兜底，§7.4）。顶层不是合法受约束 JSON →
/// LlmBadResponseException。
List<DishCandidate> extractDishes(String rawOutput, {int maxDishes = 6}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(extractJsonPayload(rawOutput));
  } on FormatException catch (error) {
    throw LlmBadResponseException(
      'Vision 响应不是合法 JSON：${_snippet(rawOutput)}',
      cause: error,
    );
  } on AiValidationException catch (error) {
    // 受约束解码失败（无 JSON 对象）→ 响应非法分类，交拍照管线降级映射。
    throw LlmBadResponseException(
      'Vision 响应未含受约束 JSON：${error.errors.join('；')}',
      cause: error,
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw LlmBadResponseException('Vision 响应顶层不是 JSON 对象');
  }
  final lines = decoded['lines'];
  if (lines is! List) {
    throw LlmBadResponseException('Vision 响应缺少 lines（§7.2 受约束口径）');
  }

  final candidates = <DishCandidate>[];
  for (final line in lines) {
    if (line is! Map<String, Object?>) continue;
    // 字段容错读取（is 检查代替硬 cast——坏类型逐项跳过而非崩溃）。
    // 菜品级置信度缺失 → 继承行级（§7.2 示例口径）；行级也缺 → 0.5 保守值。
    final lineConfidence = _clamp01(_numOr(line['confidence'], 0.5));
    final hintValue = line['category_hint'];
    final lineHint = hintValue is String ? hintValue.trim() : null;
    final items = line['items'];
    if (items is! List) continue;
    for (final item in items) {
      if (item is! Map<String, Object?>) continue;
      final nameValue = item['name'];
      final name = nameValue is String ? nameValue.trim() : null;
      if (name == null || name.isEmpty) continue;
      final portionRaw = _numOrNull(item['portion_g']);
      if (portionRaw == null || portionRaw <= 0) continue;
      final kcalRaw = item['kcal'] is num ? (item['kcal'] as num).toInt() : null;
      final confidence = _clamp01(_numOr(item['confidence'], lineConfidence));
      candidates.add(DishCandidate(
        name: name,
        grams: portionRaw,
        confidence: confidence,
        categoryHint: (lineHint == null || lineHint.isEmpty) ? null : lineHint,
        // 红线（§7.1）：模型直报 kcal 只换算每百克参考随行，不直接落库。
        kcalPer100gHint: kcalRaw == null
            ? null
            : (kcalRaw / portionRaw * 100).clamp(0.0, 5000.0).toDouble(),
      ));
    }
  }
  return candidates.length <= maxDishes
      ? candidates
      : candidates.sublist(0, maxDishes);
}

/// num 容错读取：类型不符 → fallback（不硬 cast 抛 TypeError）。
double _numOr(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

double? _numOrNull(Object? value) =>
    value is num ? value.toDouble() : null;

double _clamp01(double value) => value.clamp(0.0, 1.0).toDouble();

String _snippet(String body) =>
    body.length > 300 ? body.substring(0, 300) : body;
