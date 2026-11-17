/// 拍照解析管线（§3.3 拍照通道、§7.1 管线总览的拍照支线、§7.4 降级方案
/// 第 4 级「双供应商 fallback（百度菜品识别↔Vision LLM）」、§11.2 W11-12
/// 主线「拍照通道」）。
///
/// 管线（§7.1 口径；「确认卡/落库」属 feature 层，§10.4 分层）：
/// ```
/// 原图（即用即焚） → 端侧压缩（长边 1280、JPEG q80，§3.3）
///   → 规范化 + input_hash（sha256(压缩规范形信封)）
///   → 缓存命中（ai_parses <7 天）→ 直接复用 raw_output 回放
///   → 百度菜品识别先行 → 非空候选 → food_items 草稿组装（§5.2③，联查钩子）
///     → §7.2 受约束校验（校验器为硬闸门）→ ParseSuccess + ai_parses 留痕
///   → 失败/空结果 → Vision LLM 兜底 → 同上
///   → 仍失败 → StructuredFailure（复用既有降级语义：断网→延迟队列、
///     额度→提示、其余→手填，§7.4）
/// ```
/// 失败一律作值返回（[StructuredFailure]），不抛异常——§7.4「健壮性即产品
/// 体验」。双供应商以 [ImageDishAdapter] 列表编排（百度先行顺序由装配方
/// 保证，见 photo_factory.dart）；供应商异常按 LlmException 分类映射失败
/// 原因与降级级别，与文本管线（ai_parser.dart）共用同一张 §7.4 映射表。
///
/// 隐私口径（§3.3 raw_input 上云开关默认关）：原图字节只经内存流转（压缩
/// →识别请求），解析后即焚不落任何表；[StructuredFailure.rawInput] 与
/// ai_parses 只落 `photo:<inputHash>` 描述符（§5.6㉑ attachments「解析后
/// 即焚」同口径）。拍照通道成本按图计价（§7.5），待凭据联调实测——留痕
/// costMicro 暂记 0 不虚报。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:crypto/crypto.dart';

import '../cache/ai_parse_cache.dart';
import '../llm/llm_adapter.dart';
import '../parse/parse_categories.dart';
import '../parse/parse_models.dart';
import '../parse/parse_validator.dart';
import 'image_compressor.dart';
import 'photo_models.dart';

/// 拍照通道提示词/组装版本（ai_parses.prompt_version，§5.6⑭；回放兼容性
/// 闸门——与文本管线 kPromptVersion 分轨，版本变更后旧照片缓存视为未命中）。
const String kPhotoPromptVersion = 'w11-12-photo-v1';

/// 拍照通道缓存键信封版本（算法演进时递增，避免跨算法串键）。
const String _kPhotoHashEnvelopeVersion = 'v1';

/// 拍照缺省分类提示（拍照=餐食场景，§3.3；内置分类枚举，§3.4）。
const String kDefaultPhotoCategoryHint = '餐饮-正餐';

/// 拍照解析请求（W11-12 任务口径）。
class PhotoParseRequest {
  const PhotoParseRequest({
    required this.imageBytes,
    required this.mime,
    required this.date,
  });

  /// 原图字节（即用即焚，§3.3；管线内不出内存）。
  final Uint8List imageBytes;

  /// 原图 MIME（解码提示；压缩产物统一 JPEG）。
  final String mime;

  /// 本地日历日 `yyyy-MM-dd`（§5.1；事件归属日锚点，落库由宿主决定）。
  final String date;
}

/// 食物库联查参考条目（§7.1 管线第 6 步「食物库联查校准」拍照侧的校准
/// 载荷；§5.2③ ref_source/ref_id 联查来源）。
class DishRefEntry {
  const DishRefEntry({
    required this.kcalPer100g,
    required this.refSource,
    this.refId,
    this.defaultPortionG,
  });

  /// 参考热量（每百克 kcal，>0）。
  final double kcalPer100g;

  /// 联查来源（§5.2③：usda/off/baidu/local/llm——联查命中后改写候选标记）。
  final FoodRefSource refSource;

  /// 来源库条目 id（联查命中后回填；无稳定 id 为 null）。
  final String? refId;

  /// 参考库默认份量（克；非空时覆写候选的基准份量）。
  final double? defaultPortionG;
}

/// 食物库联查钩子（§7.1 第 6 步拍照侧接缝；W11-12 任务「source 联查钩子
/// 留接口」）。
///
/// W11-12 不接库（USDA CC0 + OpenFoodFacts ODbL 快表与百度菜品库镜像为
/// 后续里程碑项）：缺省 [PassthroughDishRefLookup] 全部未命中——est_kcal
/// 走本地估计基准并降置信度（红线 §7.1）；接入快表后由宿主注入实现。
abstract interface class DishRefLookup {
  /// 按菜品名联查参考条目；未命中返回 null。
  DishRefEntry? lookup(String dishName);
}

/// 透传联查（W11-12 缺省：全部未命中）。
class PassthroughDishRefLookup implements DishRefLookup {
  const PassthroughDishRefLookup();

  @override
  DishRefEntry? lookup(String dishName) => null;
}

/// 计算拍照缓存键（§7.1「input_hash（sha256）」、§5.6⑭）。
///
/// 信封 = `slimca-ai-parse-photo|<版本>|<mime>|<字节数>` + 压缩规范形字节：
/// - 拍照的「规范化」即端侧压缩（§3.3 规范形长边 1280/JPEG q80）——同一
///   原图重复拍摄经同一压缩参数得到同一规范形方可命中（跨设备/跨机型
///   像素级重复概率低，缓存命中以复拍/重发同一张图为主，§7.5）；
/// - 信封含 mime 与长度：杜绝不同 mime/截断字节碰撞。
String computePhotoInputHash(Uint8List compressedBytes, String mime) {
  final prefix = utf8.encode(
    'slimca-ai-parse-photo'
    '\x1f$_kPhotoHashEnvelopeVersion'
    '\x1f$mime'
    '\x1f${compressedBytes.length}',
  );
  return sha256.convert(<int>[...prefix, ...compressedBytes]).toString();
}

/// food_items 草稿组装（W11-12 任务第 4 项；§5.2③ 字段口径：
/// name/grams/est_kcal/source，联查钩子改写）。
///
/// 产出 §7.2 受约束 JSON（单边热量行）——随后的受约束校验/§7.3 映射一律
/// 走既有校验器（validateAndMap，硬闸门 §7.1），与文本管线共用同一映射
/// 权威，缓存回放（raw_output 复用）也因此在两条管线间语义一致。
///
/// 组装规则：
/// - grams：联查命中且参考库给默认份量 → 覆写；否则候选基准份量；非法
///   （≤0）→ [kDefaultDishPortionG] 兜底；
/// - est_kcal：每百克口径 = 联查命中 kcalPer100g > 候选直报 hint（红线：
///   LLM 直报不可信，仅联查未命中时作初值）> [kFallbackKcalPer100g] 本地
///   估计；est_kcal = kcalPer100g × grams / 100，四舍五入取整；
/// - ref_source：联查命中 → 参考条目来源；未命中 → 供应商标记
///   （百度识别=baidu / Vision 识别=llm，§5.2③）；
/// - confidence：联查未命中 → 候选置信度 × [kUncalibratedConfidencePenalty]
///   降档（§7.1 红线「未联查的热量须低置信标注」→ 确认卡强制高亮，§3.3）。
String assembleDishParseJson({
  required List<DishCandidate> dishes,
  required DishRefLookup refLookup,
  required FoodRefSource fallbackRefSource,
  String? parseNotes,
}) {
  var calibratedCount = 0;
  final itemMaps = <Map<String, Object?>>[];
  var lineKcal = 0;
  var lineConfidence = 1.0;
  final titleParts = <String>[];
  String? categoryHint;

  for (final dish in dishes) {
    final name = dish.name.trim();
    if (name.isEmpty) {
      continue;
    }
    final refEntry = refLookup.lookup(name);
    if (refEntry != null) {
      calibratedCount++;
    }

    // 份量（克）：联查默认份量 > 候选基准 > [kDefaultDishPortionG]。
    final rawGrams = refEntry?.defaultPortionG ?? dish.grams;
    final grams = rawGrams > 0 ? rawGrams : kDefaultDishPortionG;

    // 每百克热量：联查 > 模型直报 hint > 本地估计基准（红线 §7.1）。
    final hint = dish.kcalPer100gHint;
    final kcalPer100g = (refEntry?.kcalPer100g ??
            (hint != null && hint > 0 ? hint : null) ??
            kFallbackKcalPer100g)
        .clamp(0.1, 5000.0);

    // est_kcal（整数 kcal，[0,5000]，§7.1 校验器口径）。
    final kcal = ((kcalPer100g * grams / 100).round()).clamp(0, 5000);

    // 置信度：未联查校准 → 降档（§7.1 红线）；截断 [0,1]。
    final confidence = (refEntry == null
            ? dish.confidence * kUncalibratedConfidencePenalty
            : dish.confidence)
        .clamp(0.0, 1.0);
    if (confidence < lineConfidence) {
      lineConfidence = confidence;
    }

    itemMaps.add(<String, Object?>{
      'name': name,
      'portion_g': grams,
      'kcal': kcal,
      'protein_g': 0,
      'carb_g': 0,
      'fat_g': 0,
      'ref_source': (refEntry?.refSource ?? fallbackRefSource).wire,
      if (refEntry?.refId != null) 'ref_id': refEntry!.refId,
      'confidence': confidence,
    });
    lineKcal = (lineKcal + kcal).clamp(0, 5000);
    titleParts.add(name);
    categoryHint ??= dish.categoryHint;
  }

  // 行级热量：菜品 kcal 之和（§7.2 示例口径：行=Σitems）；超 5000 截断
  // （校验器上限；确认卡滑杆/修正闭环承接，§3.3）。
  final title = _buildTitle(titleParts);
  final resolvedNotes = parseNotes ??
      '拍照识别 ${titleParts.length} 道菜品；联查校准命中 $calibratedCount 项；'
      '未命中项 est_kcal 为本地估计初值（§7.1 联查口径）';
  return jsonEncode(<String, Object?>{
    'title': title,
    'kind': 'food',
    'lines': <Object?>[
      <String, Object?>{
        'type': 'calorie',
        'amount_kcal': lineKcal,
        'confidence': lineConfidence.clamp(0.0, 1.0),
        'category_hint': categoryHint ?? kDefaultPhotoCategoryHint,
        'items': itemMaps,
      },
    ],
    'parse_notes': resolvedNotes,
  });
}

/// 标题：候选菜名以「、」连接（entries.title 一句话描述口径，截 20 字）。
String _buildTitle(List<String> names) {
  if (names.isEmpty) {
    return '拍照餐食';
  }
  final joined = names.join('、');
  return joined.length <= 20 ? joined : '${joined.substring(0, 20)}…';
}

/// 拍照解析器：双供应商 fallback 编排（W11-12 任务第 2 项；§7.4 第 4 级）。
///
/// [providers] 为按优先级排列的识别供应商（百度先行 → Vision LLM 兜底，
/// 装配见 photo_factory.dart）；成功即短路。失败（异常/空候选/校验拒绝）
/// 记账后切换下一个；全部失败 → [StructuredFailure]（复用既有降级语义）。
class PhotoParser {
  PhotoParser({
    required List<ImageDishAdapter> providers,
    required this.compressor,
    required this.cache,
    this.refLookup = const PassthroughDishRefLookup(),
    CategoryResolver? categoryResolver,
    int Function()? nowMs,
    String Function()? newParseId,
    this.cacheTtl = kAiParseCacheTtl,
  })  : providers = List<ImageDishAdapter>.unmodifiable(providers),
        categoryResolver = categoryResolver ?? const PresetCategoryResolver(),
        _nowMs = nowMs ?? _defaultNowMs,
        _newParseId = newParseId ?? (() => cdb.generateUuidV7());

  /// 识别供应商优先级清单（§7.4：百度先行，Vision LLM 兜底）。
  final List<ImageDishAdapter> providers;

  /// 端侧压缩（§3.3 第一步）。
  final ImageCompressor compressor;

  /// input_hash 缓存（§5.6⑭ ai_parses）。
  final AiParseCache cache;

  /// 食物库联查钩子（§7.1 第 6 步拍照侧）。
  final DishRefLookup refLookup;

  /// 分类解析器（category_hint → 内置分类，§7.3）。
  final CategoryResolver categoryResolver;

  /// 缓存时效（§5.6⑭：<7 天）。
  final Duration cacheTtl;

  final int Function() _nowMs;
  final String Function() _newParseId;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 执行拍照解析；成功/失败都以 [ParseResult] 值返回。
  Future<ParseResult> parse(PhotoParseRequest request) async {
    // 入口契约：日期必须是本地日历日（§5.1，落库锚点）。
    dom.validateCalendarDay(request.date, name: 'date');
    // 拍照通道恒单边热量口径（§3.3 拍照=餐食，无金额语义）。
    final context = ParseContext(date: request.date, mode: ParseMode.kcalOnly);

    // ── ① 端侧压缩（§3.3「端侧压缩（长边 1280、JPEG q80）」）──
    final CompressedImage compressed;
    try {
      compressed = await compressor
          .compress(PhotoImageInput(bytes: request.imageBytes, mime: request.mime));
    } on PhotoCompressionException catch (error) {
      // 坏字节/不支持格式 → 请求本身非法，一级降级手填（§7.4）。
      return StructuredFailure(
        reason: AiFailureReason.invalidRequest,
        degradeLevel: AiDegradeLevel.manualForm,
        rawInput: 'photo:${request.mime};len=${request.imageBytes.length}',
        context: context,
        attempts: 0,
        errors: [error.message],
        cause: error,
      );
    }

    // ── ② 规范化 + input_hash（§7.1；拍照规范化=端侧压缩规范形）──
    final inputHash = computePhotoInputHash(compressed.bytes, compressed.mime);
    final rawInputDescriptor = 'photo:$inputHash';

    // ── ③ 缓存命中（§7.1/§5.6⑭：命中且 <7 天 → 直接复用 raw_output）──
    // prompt_version 不同视为未命中（回放兼容性闸门，§5.6⑭）。
    final cached = await cache.find(inputHash);
    if (cached != null &&
        cached.promptVersion == kPhotoPromptVersion &&
        cached.isFreshAt(_nowMs(), ttl: cacheTtl)) {
      try {
        final validated = validateAndMap(
          rawOutput: cached.rawOutput,
          mode: ParseMode.kcalOnly,
          categoryResolver: categoryResolver,
        );
        return ParseSuccess(
          title: validated.title,
          kind: validated.kind,
          lines: validated.lines,
          parseNotes: validated.parseNotes,
          inputHash: inputHash,
          record: cached,
          fromCache: true,
          notes: [...validated.notes, 'input_hash 缓存命中（<7 天，§5.6⑭）'],
        );
      } on AiValidationException {
        // 缓存行损坏（不应发生）：视为未命中，走实时管线。
      }
    }

    // ── ④⑤ 双供应商 fallback（§7.4 第 4 级落地）──
    var attempts = 0;
    var lastReason = AiFailureReason.emptyResult;
    // 降级级别取全程最重档（§7.4；合并规则见 [_maxLevel]）。
    var worstLevel = AiDegradeLevel.manualForm;
    final errors = <String>[];
    String? lastRawOutput;
    Object? lastCause;

    for (final provider in providers) {
      attempts++;
      final stopwatch = Stopwatch()..start();
      List<DishCandidate> dishes;
      try {
        dishes = await provider.recognize(compressed);
      } on LlmException catch (error) {
        // 供应商异常（§7.1 已分类）：记账 → 切换兜底供应商。
        stopwatch.stop();
        lastReason = _reasonFromAdapter(error);
        worstLevel = _maxLevel(worstLevel, _levelFromReason(lastReason));
        lastCause = error;
        errors.add('[${provider.providerId}] ${error.message}');
        continue;
      }
      if (dishes.isEmpty ||
          !dishes.any((dish) => dish.name.trim().isNotEmpty)) {
        // 空结果（非菜品照片/识别不出）= 正常业务分支 → 切换兜底（§7.4）。
        stopwatch.stop();
        lastReason = AiFailureReason.emptyResult;
        errors.add('[${provider.providerId}] 未识别到菜品候选（空结果，§7.4 兜底）');
        continue;
      }

      // food_items 草稿组装（§5.2③，联查钩子）→ §7.2 受约束校验（硬闸门）。
      final rawOutput = assembleDishParseJson(
        dishes: dishes,
        refLookup: refLookup,
        fallbackRefSource: provider.dishRefSource,
      );
      lastRawOutput = rawOutput;
      try {
        final validated = validateAndMap(
          rawOutput: rawOutput,
          mode: ParseMode.kcalOnly,
          categoryResolver: categoryResolver,
        );
        stopwatch.stop();
        // 成功收尾：写 ai_parses 留痕（§5.6⑭）→ ParseSuccess。
        final record = AiParseRecord(
          id: _newParseId(),
          inputKind: AiInputKind.photo.wire,
          inputHash: inputHash,
          provider: provider.providerId,
          model: provider.modelId,
          rawOutput: rawOutput,
          latencyMs: stopwatch.elapsedMilliseconds,
          // 按图计价通道成本待凭据联调实测（§7.5），暂记 0 不虚报。
          costMicro: 0,
          confidence: _minConfidence(validated.lines),
          promptVersion: kPhotoPromptVersion,
        );
        await cache.save(record);
        return ParseSuccess(
          title: validated.title,
          kind: validated.kind,
          lines: validated.lines,
          parseNotes: validated.parseNotes,
          inputHash: inputHash,
          record: record,
          fromCache: false,
          notes: [
            ...validated.notes,
            '拍照通道：${provider.providerId} 先行成功（§7.4 双供应商 fallback）',
            '原图即用即焚，仅落结构化结果（§3.3 raw_input 上云开关默认关）',
          ],
        );
      } on AiValidationException catch (validationError) {
        // 自产受约束 JSON 被校验拒绝（供应商候选字段越界）：同视为该供应
        // 商失败 → 切换兜底（§7.1 校验器为硬闸门，无一例外）。
        lastReason = validationError.reason;
        worstLevel = _maxLevel(worstLevel, _levelFromReason(lastReason));
        lastCause = validationError;
        errors.add(
            '[${provider.providerId}] ${validationError.errors.join('；')}');
        continue;
      }
    }

    // ── ⑥ 全部供应商失败 → StructuredFailure（复用既有降级语义，§7.4）──
    // 降级级别取全程最重档：额度耗尽/断网是持续性信号，不因后续供应商的
    // 瞬时失败而丢失（失败原因 reason 取末次尝试，如实反映最后一次错）。
    if (providers.isEmpty) {
      lastReason = AiFailureReason.invalidRequest;
      errors.add('未装配任何识别供应商（装配遗漏，photo_factory.dart）');
    }
    return StructuredFailure(
      reason: lastReason,
      degradeLevel: worstLevel,
      rawInput: rawInputDescriptor,
      context: context,
      attempts: attempts,
      errors: errors,
      lastRawOutput: lastRawOutput,
      cause: lastCause,
    );
  }

  // ── 内部辅助 ────────────────────────────────────────────────────

  /// LlmException 分类 → 失败原因（与 ai_parser._failureFromAdapter 同一张
  /// §7.1 分类表；sealed switch 穷尽由编译器保证）。
  static AiFailureReason _reasonFromAdapter(LlmException error) =>
      switch (error) {
        LlmServerException() => AiFailureReason.providerError,
        LlmTimeoutException() => AiFailureReason.timeout,
        LlmNetworkException() => AiFailureReason.network,
        LlmQuotaException() => AiFailureReason.quota,
        LlmRateLimitException() => AiFailureReason.rateLimit,
        LlmAuthException() => AiFailureReason.auth,
        LlmInvalidRequestException() => AiFailureReason.invalidRequest,
        LlmBadResponseException() => AiFailureReason.badResponse,
      };

  /// 失败原因 → 降级级别（§7.4 降级映射：断网→二级延迟队列；额度耗尽→
  /// 三级额度提示；其余→一级手填；与文本管线同表）。
  static AiDegradeLevel _levelFromReason(AiFailureReason reason) =>
      switch (reason) {
        AiFailureReason.network => AiDegradeLevel.deferredQueue,
        AiFailureReason.quota => AiDegradeLevel.quotaNotice,
        _ => AiDegradeLevel.manualForm,
      };

  /// 多供应商失败时的降级级别合并：取最高档（§7.4——额度耗尽/断网等持续
  /// 性信号不因后续供应商的瞬时失败而丢失；双供应商双双失败时，UI 须如实
  /// 告知最重情形，如「额度耗尽」优先于「手填建议」）。[AiDegradeLevel.level]
  /// 数字越大档位越重（1 手填 < 2 延迟队列 < 3 额度提示）。
  static AiDegradeLevel _maxLevel(AiDegradeLevel a, AiDegradeLevel b) =>
      a.level >= b.level ? a : b;

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
