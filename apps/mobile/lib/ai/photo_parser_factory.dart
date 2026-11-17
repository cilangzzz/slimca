/// 拍照解析器工厂与双供应商实现（§3.3 拍照通道「百度菜品识别先行 → Vision
/// LLM 兜底」、§7.4 双供应商 fallback、§7.2 受约束输出、§11.2 W11-12 任务
/// 「百度识别与 Vision LLM 均按 dart-define/配置注入，缺省 Fake」）。
///
/// 装配（bootstrap 调 createCapturePhotoParser → capturePhotoParserProvider
/// override 注入；测试注入 FakeCapturePhotoParser 或本文件实现 + mock
/// transport——硬规则：测试禁止真实网络）：
/// - **百度菜品识别**（先行位，§7.5 中文菜品识别 9000+）：token
///   （client_credentials）→ dish detect v2（form-urlencoded base64 图片）；
///   产物只含菜名/概率，热量用内置小快表粗估（W11-12 无食物库接入，
///   remaining：食物库快表/USDA-FF 联查为后续里程碑），置信度按 §7.1 红线
///   「LLM/识别直报不可信」从保守标注（低置信度强制校核，§3.3 同一信任语言）；
/// - **Vision LLM**（兜底位，§7.5 Qwen-VL/GLM-4V）：OpenAI 兼容
///   chat/completions 多段 content（text + image_url data URI），受约束
///   JSON 输出（§7.2）→ CaptureParseResult；
/// - **组合**：feature_capture 的 CapturePhotoParserFallback（primary 结构化
///   失败/超时 → fallback，§7.4 双供应商防单点）；
/// - **缺省（无凭据）**：primary=未配置桩（恒结构化失败）→ fallback=离线
///   确定性桩（零网络、低置信度演示初值）——缺省 Fake，remaining：待凭据
///   联调（真实凭据经 dart-define 注入后即切换真实链路，代码不变）。
///
/// 失败语义（§7.4）：网络失败→CaptureFailureCode.network、HTTP/供应商错误→
/// provider、解码/校验拒绝→schema；超时穿透 TimeoutException（控制器对照片
/// 路径再套 12s 超时，§7.4 照片口径）。失败仅带**类型码与类型化 message**
/// 上抛——原文/图片字节/响应体禁入异常与遥测（§3.9）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:feature_capture/feature_capture.dart';
import 'package:http/http.dart' as http;

// ── dart-define 配置（真实供应商凭据未提供，remaining：待凭据联调；flutter
// run/build --dart-define=SLIMCA_BAIDU_API_KEY=… 注入）────────────────────

/// 百度开放平台 API Key（菜品识别先行位，§7.5）。
const String kSlimcaBaiduApiKey = String.fromEnvironment('SLIMCA_BAIDU_API_KEY');

/// 百度开放平台 Secret Key。
const String kSlimcaBaiduSecretKey =
    String.fromEnvironment('SLIMCA_BAIDU_SECRET_KEY');

/// Vision LLM OpenAI 兼容端点（兜底位，§7.5；如 dashscope/glm 开放平台代理）。
const String kSlimcaVisionBaseUrl =
    String.fromEnvironment('SLIMCA_VISION_BASE_URL');

/// Vision LLM API Key。
const String kSlimcaVisionApiKey = String.fromEnvironment('SLIMCA_VISION_API_KEY');

/// Vision LLM 模型名（缺省 Qwen-VL，§7.5）。
const String kSlimcaVisionModel = String.fromEnvironment(
  'SLIMCA_VISION_MODEL',
  defaultValue: 'qwen-vl-plus',
);

/// Vision 缺省端点（dart-define 未给 BASE_URL 时按 OpenAI 兼容路径拼装）。
const String _kDefaultVisionBaseUrl = 'https://api.openai.com/v1';

// 分段超时（§2.3 拍照路径全程 ≤15s 护栏内：token ≤5s + 识别 ≤8s / Vision
// ≤10s；控制器再套 12s 总闸，§7.4 照片口径）。
const Duration _kBaiduTokenTimeout = Duration(seconds: 5);
const Duration _kBaiduDishTimeout = Duration(seconds: 8);
const Duration _kVisionCallTimeout = Duration(seconds: 10);

/// 组装拍照解析器（§7.4 双供应商 fallback；凭据按 dart-define 注入，缺省
/// 离线桩）。显式参数仅供测试注入（mock transport / 凭据组合断言）。
CapturePhotoParser createCapturePhotoParser({
  String? baiduApiKey,
  String? baiduSecretKey,
  String? visionBaseUrl,
  String? visionApiKey,
  String? visionModel,
  http.Client? client,
}) {
  final baiduKey = baiduApiKey ?? kSlimcaBaiduApiKey;
  final baiduSecret = baiduSecretKey ?? kSlimcaBaiduSecretKey;
  final visionKey = visionApiKey ?? kSlimcaVisionApiKey;
  final visionModelResolved = visionModel ?? kSlimcaVisionModel;
  final visionBaseResolved = visionBaseUrl ?? kSlimcaVisionBaseUrl;

  // 兜底位（§7.4）：有凭据 → Vision LLM；无凭据 → 离线确定性桩（缺省 Fake，
  // remaining：待凭据联调）。
  final CapturePhotoParser fallback = visionKey.isNotEmpty
      ? VisionLlmCapturePhotoParser(
          baseUrl: visionBaseResolved.isEmpty
              ? _kDefaultVisionBaseUrl
              : visionBaseResolved,
          apiKey: visionKey,
          model: visionModelResolved,
          client: client,
        )
      : const OfflineStubVisionCapturePhotoParser();
  // 先行位（§3.3）：有凭据 → 百度菜品识别；无凭据 → 结构化失败桩——组合子
  // 语义（primary 抛 → fallback 兜）保证无凭据装配仍可走 Vision/离线桩。
  final CapturePhotoParser primary = (baiduKey.isNotEmpty && baiduSecret.isNotEmpty)
      ? BaiduDishCapturePhotoParser(
          apiKey: baiduKey,
          secretKey: baiduSecret,
          client: client,
        )
      : const UnconfiguredBaiduCapturePhotoParser();
  return CapturePhotoParserFallback(primary: primary, fallback: fallback);
}

// ── 先行位：百度菜品识别（§3.3、§7.5）────────────────────────────────────

/// 百度菜品识别解析器（token → dish detect v2；热量为内置快表粗估值）。
class BaiduDishCapturePhotoParser implements CapturePhotoParser {
  BaiduDishCapturePhotoParser({
    required this.apiKey,
    required this.secretKey,
    http.Client? client,
  }) : _injectedClient = client;

  /// 百度开放平台 API Key / Secret Key（§7.5）。
  final String apiKey;
  final String secretKey;

  /// 传输层（测试注入 mock transport；生产缺省共用长连接 client）。
  final http.Client? _injectedClient;
  http.Client? _ownedClient;

  http.Client get _client => _injectedClient ?? (_ownedClient ??= http.Client());

  static const String _kTokenUrl = 'https://aip.baidubce.com/oauth/2.0/token';
  static const String _kDishUrl =
      'https://aip.baidubce.com/rest/2.0/image-classify/v2/dish';

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    final sw = Stopwatch()..start();
    try {
      final token = await _fetchAccessToken();
      final dishes = await _detectDishes(token, request.bytes);
      if (dishes.isEmpty) {
        throw const CaptureStructuredFailure(
          code: CaptureFailureCode.schema,
          message: '百度未识别出菜品',
        );
      }
      // 菜品 → 结构化初值：热量用内置快表粗估（§3.3 识别先行位只给菜名；
      // W11-12 无食物库接入，remaining：食物库快表/USDA-FF 联查为后续里程碑）。
      // 置信度按 §7.1 红线从保守标注（0.35=红点低置信度，强制校核，§3.3）。
      var totalKcal = 0;
      final items = <CaptureParsedItem>[];
      for (final dish in dishes) {
        final kcal = _estimateKcal(dish.$1);
        totalKcal += kcal;
        items.add(CaptureParsedItem(
          name: dish.$1,
          portionG: 150,
          kcal: kcal,
          confidence: dish.$2.clamp(0.0, 1.0).toDouble(),
          refSource: 'baidu',
        ));
      }
      return CaptureParseResult(
        title: dishes.map((d) => d.$1).take(3).join('加'),
        parseNotes: '百度菜品识别先行：热量为内置快表估计值，请校核份量（§3.3）',
        lines: [
          CaptureParsedLine(
            typeWire: 'calorie',
            amountKcal:
                totalKcal > kMaxParseKcal ? kMaxParseKcal : totalKcal,
            confidence: 0.35,
            categoryHint: '餐饮',
            items: items,
          ),
        ],
        provider: 'baidu',
        model: 'dish_detection_v2',
        promptVersion: 'baidu-dish-w11-12',
        latencyMs: sw.elapsedMilliseconds,
        costMicro: 0,
        confidence: 0.35,
      );
    } on CaptureStructuredFailure {
      rethrow;
    } on TimeoutException {
      // 超时穿透（控制器照片路径对 TimeoutException 有专属降级文案，§7.4）。
      rethrow;
    } on Object catch (error) {
      throw CaptureStructuredFailure(
        code: CaptureFailureCode.network,
        message: '百度菜品识别请求失败',
        cause: error,
      );
    }
  }

  Future<String> _fetchAccessToken() async {
    final response = await _client
        .post(
          Uri.parse(_kTokenUrl),
          // http 对 Map body 自动按 form-urlencoded 编码（百度 token 契约）。
          body: <String, String>{
            'grant_type': 'client_credentials',
            'client_id': apiKey,
            'client_secret': secretKey,
          },
        )
        .timeout(_kBaiduTokenTimeout);
    if (response.statusCode != 200) {
      throw CaptureStructuredFailure(
        code: CaptureFailureCode.provider,
        message: '百度令牌获取失败 HTTP ${response.statusCode}',
      );
    }
    final map = jsonDecode(utf8.decode(response.bodyBytes));
    final token = map is Map<String, Object?> ? map['access_token'] : null;
    if (token is! String || token.isEmpty) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: '百度令牌响应缺少 access_token',
      );
    }
    return token;
  }

  Future<List<(String, double)>> _detectDishes(
    String token,
    Uint8List bytes,
  ) async {
    final response = await _client
        .post(
          Uri.parse('$_kDishUrl?access_token=$token'),
          headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          // 百度 dish detect v2 契约：form 字段 image=base64（URL 编码）。
          body: 'image=${Uri.encodeComponent(base64Encode(bytes))}&top_num=5',
        )
        .timeout(_kBaiduDishTimeout);
    if (response.statusCode != 200) {
      throw CaptureStructuredFailure(
        code: CaptureFailureCode.provider,
        message: '百度菜品识别失败 HTTP ${response.statusCode}',
      );
    }
    final map = jsonDecode(utf8.decode(response.bodyBytes));
    if (map is! Map<String, Object?>) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: '百度响应非 JSON 对象',
      );
    }
    if (map['error_code'] != null) {
      // 供应商侧错误码（QPS/额度/图片非法等）：只上抛类型化信息，响应体禁入
      // 异常（§3.9）。
      throw CaptureStructuredFailure(
        code: CaptureFailureCode.provider,
        message: '百度识别错误 ${map['error_code']}',
      );
    }
    final results = map['result'];
    if (results is! List<Object?>) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: '百度响应缺少 result',
      );
    }
    final dishes = <(String, double)>[];
    for (final row in results) {
      if (row is Map<String, Object?> && row['name'] is String) {
        final probability = row['probability'];
        dishes.add((
          row['name'] as String,
          probability is num ? probability.toDouble() : 0.3,
        ));
      }
    }
    return dishes;
  }

  /// 内置菜品热量快表（按名包含匹配；缺省 200 kcal 粗估）。粗估值恒走确认卡
  /// 低置信度校核（§3.3），不是最终记账值。
  int _estimateKcal(String dishName) {
    for (final entry in _kBaiduDishKcalTable.entries) {
      if (dishName.contains(entry.key)) {
        return entry.value;
      }
    }
    return 200;
  }
}

/// 内置快表（§5.2③ ref_source=baidu 的粗估口径；非食物库，remaining：食物库
/// 快表/USDA-FF 联查为后续里程碑）。
const Map<String, int> _kBaiduDishKcalTable = <String, int>{
  '米饭': 200,
  '红烧肉': 500,
  '牛肉面': 450,
  '番茄炒蛋': 250,
  '西红柿炒鸡蛋': 250,
  '清炒': 120,
  '沙拉': 150,
  '饺子': 350,
  '汉堡': 550,
  '披萨': 600,
};

/// 未配置百度凭据时的先行位桩：恒结构化失败（§7.4 双供应商组合语义——
/// primary 抛 → fallback 兜底供应商接手；缺省装配即走离线桩）。
class UnconfiguredBaiduCapturePhotoParser implements CapturePhotoParser {
  const UnconfiguredBaiduCapturePhotoParser();

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    throw const CaptureStructuredFailure(
      code: CaptureFailureCode.provider,
      message: '百度菜品识别凭据未配置（SLIMCA_BAIDU_API_KEY/SECRET_KEY）',
    );
  }
}

// ── 兜底位：Vision LLM（OpenAI 兼容 chat/completions，§7.2/§7.5）─────────

/// Vision LLM 解析器（多段 content：text + image_url data URI；受约束 JSON）。
class VisionLlmCapturePhotoParser implements CapturePhotoParser {
  VisionLlmCapturePhotoParser({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _injectedClient = client;

  /// OpenAI 兼容端点基址（如 https://dashscope.aliyuncs.com/compatible-mode/v1）。
  final String baseUrl;
  final String apiKey;

  /// 模型名（§7.5 Qwen-VL / GLM-4V）。
  final String model;

  /// 传输层（测试注入 mock transport）。
  final http.Client? _injectedClient;
  http.Client? _ownedClient;

  http.Client get _client => _injectedClient ?? (_ownedClient ??= http.Client());

  /// 系统提示（§7.2 受约束 JSON Schema 口径——与文本管线同款「只输出 JSON」
  /// 纪律；照片路径的 raw_output 同落 ai_parses 留痕，§5.6⑭）。
  static const String _kSystemPrompt =
      '你是 Slimca 的食物照片记账助手。只输出一个 JSON 对象，不输出任何其他'
      '文本，不使用 Markdown 代码块。JSON 形如：'
      '{"title":"一句话标题","parse_notes":"备注或null","confidence":0.6,'
      '"lines":[{"type":"calorie","amount_kcal":600,"confidence":0.55,'
      '"category_hint":"餐饮","items":[{"name":"菜名","portion_g":150,'
      '"kcal":200,"confidence":0.5}]},{"type":"money","amount_minor":2500,'
      '"confidence":0.5,"category_hint":"餐饮","currency":"CNY",'
      '"merchant":"商家或null"}]}。'
      '硬约束：amount_kcal 与 kcal 为 [0,5000] 的整数；amount_minor 为人民币'
      '分的整数且大于 0；识别不出的行整行省略；禁止输出 JSON 以外的任何内容。';

  static const String _kUserPrompt = '识别这张食物照片，按系统约束输出 JSON'
      '（拍照通道识别，热量请保守估计）。';

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint()),
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'model': model,
              'temperature': 0,
              'messages': <Object?>[
                <String, Object?>{'role': 'system', 'content': _kSystemPrompt},
                <String, Object?>{
                  'role': 'user',
                  'content': <Object?>[
                    <String, Object?>{'type': 'text', 'text': _kUserPrompt},
                    <String, Object?>{
                      'type': 'image_url',
                      'image_url': <String, Object?>{
                        // 原图经 raw_input 上云闸门放行才会走到此处（§3.7：
                        // 开关关闭时控制器根本不进云解析路径）。
                        'url':
                            'data:${request.mime};base64,${base64Encode(request.bytes)}',
                      },
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(_kVisionCallTimeout);
      if (response.statusCode != 200) {
        throw CaptureStructuredFailure(
          code: CaptureFailureCode.provider,
          message: 'Vision 识别失败 HTTP ${response.statusCode}',
        );
      }
      final map = jsonDecode(utf8.decode(response.bodyBytes));
      if (map is! Map<String, Object?>) {
        throw const CaptureStructuredFailure(
          code: CaptureFailureCode.schema,
          message: 'Vision 响应非 JSON 对象',
        );
      }
      final content = _extractContent(map);
      final payload = jsonDecode(_extractJson(content));
      if (payload is! Map<String, Object?>) {
        throw const CaptureStructuredFailure(
          code: CaptureFailureCode.schema,
          message: 'Vision 输出非 JSON 对象',
        );
      }
      return _resultFromJson(payload, sw.elapsedMilliseconds);
    } on CaptureStructuredFailure {
      rethrow;
    } on TimeoutException {
      rethrow;
    } on Object catch (error) {
      throw CaptureStructuredFailure(
        code: CaptureFailureCode.network,
        message: 'Vision 识别请求失败',
        cause: error,
      );
    }
  }

  String _endpoint() {
    final base =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/chat/completions';
  }

  /// choices[0].message.content 提取（OpenAI 兼容响应形状）。
  String _extractContent(Map<String, Object?> map) {
    final choices = map['choices'];
    if (choices is! List<Object?> || choices.isEmpty) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: 'Vision 响应缺少 choices',
      );
    }
    final first = choices.first;
    final message =
        first is Map<String, Object?> ? first['message'] : null;
    final content =
        message is Map<String, Object?> ? message['content'] : null;
    if (content is! String || content.isEmpty) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: 'Vision 响应缺少 content',
      );
    }
    return content;
  }

  /// 剥离可能的 Markdown 围栏/前缀散文，取首尾大括号间的 JSON 主体。
  String _extractJson(String content) {
    final start = content.indexOf('{');
    final end = content.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: 'Vision 输出不含 JSON 对象',
      );
    }
    return content.substring(start, end + 1);
  }

  /// 受约束 JSON → CaptureParseResult（§7.2；非法行整行跳过，全空行 = schema
  /// 失败——坏输出不留痕，§7.1 校验器同向）。
  CaptureParseResult _resultFromJson(
    Map<String, Object?> json,
    int latencyMs,
  ) {
    final title = ((json['title'] as String?) ?? '').trim();
    if (title.isEmpty) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: 'Vision 输出缺少标题',
      );
    }
    final lines = <CaptureParsedLine>[];
    final rawLines = json['lines'];
    if (rawLines is List<Object?>) {
      for (final row in rawLines) {
        if (row is! Map<String, Object?>) continue;
        final confidence = ((row['confidence'] as num?) ?? 0.35).toDouble();
        final categoryHint = row['category_hint'] as String?;
        if (row['type'] == 'calorie') {
          final amountKcal = (row['amount_kcal'] as num?)?.toInt();
          if (amountKcal == null ||
              amountKcal < 0 ||
              amountKcal > kMaxParseKcal) {
            continue; // 非法行整行跳过（§7.1 校验器同向）。
          }
          lines.add(CaptureParsedLine(
            typeWire: 'calorie',
            amountKcal: amountKcal,
            confidence: confidence.clamp(0.0, 1.0).toDouble(),
            categoryHint: categoryHint,
            items: _itemsFromJson(row['items']),
          ));
        } else if (row['type'] == 'money') {
          final amountMinor = (row['amount_minor'] as num?)?.toInt();
          if (amountMinor == null || amountMinor <= 0) {
            continue;
          }
          lines.add(CaptureParsedLine(
            typeWire: 'money',
            amountMinor: amountMinor,
            confidence: confidence.clamp(0.0, 1.0).toDouble(),
            categoryHint: categoryHint,
            currency: (row['currency'] as String?) ?? 'CNY',
            merchant: row['merchant'] as String?,
          ));
        }
      }
    }
    if (lines.isEmpty) {
      throw const CaptureStructuredFailure(
        code: CaptureFailureCode.schema,
        message: 'Vision 输出没有合法产出行',
      );
    }
    return CaptureParseResult(
      title: title,
      parseNotes: json['parse_notes'] as String?,
      lines: lines,
      provider: 'openai-vision',
      model: model,
      promptVersion: 'photo-w11-12',
      latencyMs: latencyMs,
      costMicro: 0,
      confidence: ((json['confidence'] as num?) ?? 0.35)
          .toDouble()
          .clamp(0.0, 1.0)
          .toDouble(),
    );
  }

  List<CaptureParsedItem> _itemsFromJson(Object? rawItems) {
    final items = <CaptureParsedItem>[];
    if (rawItems is! List<Object?>) return items;
    for (final row in rawItems) {
      if (row is! Map<String, Object?>) continue;
      final name = row['name'] as String?;
      final kcal = (row['kcal'] as num?)?.toInt();
      if (name == null || name.isEmpty || kcal == null) continue;
      items.add(CaptureParsedItem(
        name: name,
        portionG: ((row['portion_g'] as num?) ?? 150).toDouble(),
        kcal: kcal,
        confidence: ((row['confidence'] as num?) ?? 0.35).toDouble(),
        refSource: 'llm',
      ));
    }
    return items;
  }
}

// ── 缺省兜底：离线确定性桩（无凭据装配；缺省 Fake，remaining：待凭据联调）──

/// 离线确定性桩（§11.2「缺省 Fake」口径）：零网络、零平台通道，恒定产出
/// 低置信度演示初值（0.35=红点，强制用户校核——§3.3 信任设计缺省最不信任）。
/// 与文本管线 HeuristicFakeLlmAdapter 同款「离线桩」纪律。
class OfflineStubVisionCapturePhotoParser implements CapturePhotoParser {
  const OfflineStubVisionCapturePhotoParser();

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    return const CaptureParseResult(
      title: '红烧肉套餐',
      parseNotes: '离线识别桩（未配置 Vision 凭据）：数值为演示初值，请校核',
      lines: [
        CaptureParsedLine(
          typeWire: 'calorie',
          amountKcal: 800,
          confidence: 0.35,
          categoryHint: '餐饮',
          items: [
            CaptureParsedItem(
              name: '红烧肉',
              portionG: 200,
              kcal: 500,
              confidence: 0.35,
              refSource: 'baidu',
            ),
            CaptureParsedItem(
              name: '米饭',
              portionG: 150,
              kcal: 300,
              confidence: 0.35,
              refSource: 'baidu',
            ),
          ],
        ),
        CaptureParsedLine(
          typeWire: 'money',
          amountMinor: 2800,
          confidence: 0.35,
          categoryHint: '餐饮',
          currency: 'CNY',
        ),
      ],
      provider: 'fake-vision',
      model: 'offline-stub-v1',
      promptVersion: 'photo-w11-12',
      latencyMs: 800,
      costMicro: 0,
      confidence: 0.35,
    );
  }
}
