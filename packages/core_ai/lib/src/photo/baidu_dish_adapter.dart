/// 百度菜品识别适配器（§3.3 拍照通道「百度菜品识别先行」、§7.1 管线第 6 步
/// 「拍照 P1 百度菜品识别 9000+ 中文菜品」、§7.4 双供应商 fallback 先行侧、
/// §11.2 W11-12 主线）。
///
/// OpenAI 风格无关的 HTTP 协议形状（百度 AIP）：
/// - 鉴权：`access_token` 直接注入（编译期 dart-define 可带短效 token）或
///   AK/SK 经 OAuth2 `client_credentials` 端点在线换取（进程内缓存至到期
///   前 60s，到期自动重取）；
/// - 识别：`POST {base}/rest/2.0/image-classify/v2/dish?access_token=…`，
///   表单 `image=<urlencode(base64(图片字节))>`（≤4MB 基准，
///   Content-Type: application/x-www-form-urlencoded）；
/// - 成功响应：`{"log_id":…,"result_num":N,"result":[{"name":…,
///   "probability":…,…}]}`；
/// - 业务错误：HTTP 200 + `{"error_code":…,"error_msg":…}`（百度惯例）。
///
/// 错误分类：复用 llm_adapter.dart 的 LlmException 分类体系（sealed 家族
/// ——百度侧不新增分类），拍照管线据此映射 §7.4 降级语义，与文本管线共用
/// 一张映射表。行为约定（LlmAdapter 同款纪律）：超时 + 可重试分类按
/// [BaiduDishConfig.maxAttempts] 线性退避重试；额度/鉴权/请求非法/响应
/// 非法不重试。
///
/// 份量口径：百度菜品识别无份量输出 → [DishCandidate.grams] 统一填
/// [BaiduDishConfig.defaultPortionG] 基准份量（确认卡滑杆联动重算的初值，
/// §3.3；联查库可覆写，见 photo_parser.dart 草稿组装）。
///
/// 待凭据联调（remaining）：真实 AK/SK 未提供，本适配器联调项=真实端点
/// 换取 token 的 expires_in 刷新节奏、result 排序与 baike_info 字段。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../llm/llm_adapter.dart';
import '../parse/parse_models.dart' show FoodRefSource;
import 'photo_models.dart';

/// 百度菜品识别配置。
class BaiduDishConfig {
  const BaiduDishConfig({
    this.accessToken = '',
    this.apiKey = '',
    this.secretKey = '',
    this.baseUrl = 'https://aip.baidubce.com',
    this.timeout = const Duration(seconds: 10),
    this.maxAttempts = 2,
    this.retryBackoff = const Duration(milliseconds: 300),
    this.defaultPortionG = kDefaultDishPortionG,
    this.maxDishes = 5,
  });

  /// 已换取的 access_token（非空时跳过 AK/SK 换取流程）。
  final String accessToken;

  /// API Key（AK；与 [secretKey] 成对使用，经 OAuth2 换取 token）。
  final String apiKey;

  /// Secret Key（SK；与 [apiKey] 成对使用）。
  final String secretKey;

  /// 服务根地址（无尾路径；末尾 `/` 会归一化）。
  final String baseUrl;

  /// 单次调用超时（拍照通道内部分配：百度先行先败先切，§7.4 照片总口径 12s）。
  final Duration timeout;

  /// 最大尝试次数（含首次；1=不重试）。
  final int maxAttempts;

  /// 重试退避基数，第 n 次重试等待 n×[retryBackoff]（测试可注入 0）。
  final Duration retryBackoff;

  /// 识别候选的缺省份量（克；§3.3 滑杆重算初值）。
  final double defaultPortionG;

  /// 最多返回的候选数（百度 result 按置信度降序截取）。
  final int maxDishes;
}

/// 百度菜品识别适配器（[ImageDishAdapter] 先行侧实现，§7.4）。
///
/// [client] 可注入（测试用 `package:http/testing.dart` 的 MockClient——
/// 任务硬规则：测试一律离线，禁止真实网络调用）。
class BaiduDishAdapter implements ImageDishAdapter {
  BaiduDishAdapter(this.config, {http.Client? client, int Function()? nowMs})
      : _client = client ?? http.Client(),
        _nowMs = nowMs ?? _defaultNowMs {
    if (config.accessToken.isEmpty &&
        (config.apiKey.isEmpty || config.secretKey.isEmpty)) {
      throw ArgumentError(
        '百度菜品识别凭据未配置：需 accessToken 或 apiKey+secretKey '
        '（--dart-define=SLIMCA_BAIDU_*，§3.3 拍照通道）',
      );
    }
  }

  final BaiduDishConfig config;
  final http.Client _client;
  final int Function() _nowMs;

  @override
  String get providerId => 'baidu_dish';

  /// 接口名（ai_parses.model 口径；菜品识别 v2 接口）。
  @override
  String get modelId => 'dish_v2';

  @override
  FoodRefSource get dishRefSource => FoodRefSource.baidu;

  // ── access_token 缓存（OAuth2 client_credentials 换取）────────────

  String? _cachedToken;
  int _tokenExpiresAtMs = 0;

  /// 到期前提前量（毫秒）：避免临界点拿到已失效 token。
  static const int _kTokenRefreshMarginMs = 60 * 1000;

  /// expires_in 缺失时的保守时效（秒）。
  static const int _kTokenFallbackTtlS = 86400;

  /// 清空缓存 token（测试隔离用）。
  void clearCachedToken() {
    _cachedToken = null;
    _tokenExpiresAtMs = 0;
  }

  Future<String> _accessToken() async {
    final direct = config.accessToken.trim();
    if (direct.isNotEmpty) {
      return direct;
    }
    final now = _nowMs();
    final cached = _cachedToken;
    if (cached != null && now < _tokenExpiresAtMs) {
      return cached;
    }
    final uri = Uri.parse('${_normalizeBaseUrl(config.baseUrl)}/')
        .resolve('oauth/2.0/token')
        .replace(queryParameters: <String, String>{
      'grant_type': 'client_credentials',
      'client_id': config.apiKey,
      'client_secret': config.secretKey,
    });
    http.Response response;
    try {
      response = await _client
          .post(uri, headers: const <String, String>{
            'Content-Type': 'application/x-www-form-urlencoded',
          })
          .timeout(config.timeout,
              onTimeout: () => throw LlmTimeoutException(
                  '百度 token 换取超时（§7.4 拍照通道超时口径）'));
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw const LlmTimeoutException('百度 token 换取超时（§7.4 一级降级触发源）');
    } catch (error) {
      throw LlmNetworkException('百度 token 换取网络错误：$error', cause: error);
    }
    if (response.statusCode != 200) {
      throw _classifyHttpError(response.statusCode, _snippet(response.body));
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw LlmBadResponseException(
        '百度 token 响应不是合法 JSON：${_snippet(response.body)}',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw LlmBadResponseException(
        '百度 token 响应顶层不是 JSON 对象：${_snippet(response.body)}',
      );
    }
    final token = decoded['access_token'];
    if (token is! String || token.isEmpty) {
      // OAuth2 失败体形如 {"error":"invalid_client",...}——鉴权失败分类。
      throw LlmAuthException(
        '百度 token 换取失败（AK/SK 无效或额度关闭）：${_snippet(response.body)}',
      );
    }
    final expiresInRaw = decoded['expires_in'];
    // 容错：expires_in 规范为数字，个别网关返回字符串——不硬 cast（坏类型
    // 会以 TypeError 逃出 LlmException 分类体系，绕过降级映射）。
    final expiresInS = expiresInRaw is num
        ? expiresInRaw.toInt()
        : int.tryParse('${expiresInRaw ?? ''}');
    final ttlS = expiresInS == null || expiresInS <= 0
        ? _kTokenFallbackTtlS
        : expiresInS;
    _cachedToken = token;
    _tokenExpiresAtMs =
        now + (ttlS * 1000 - _kTokenRefreshMarginMs).clamp(1000, ttlS * 1000);
    return token;
  }

  // ── 菜品识别（§7.1 第 6 步拍照侧联查）─────────────────────────────

  @override
  Future<List<DishCandidate>> recognize(CompressedImage image) async {
    final token = await _accessToken();
    final uri = Uri.parse('${_normalizeBaseUrl(config.baseUrl)}/')
        .resolve('rest/2.0/image-classify/v2/dish')
        .replace(queryParameters: <String, String>{'access_token': token});
    // 表单：image=urlencode(base64(图片字节))（百度 AIP 惯例；无 data: 前缀）。
    final body =
        'image=${Uri.encodeQueryComponent(base64Encode(image.bytes))}';

    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _attemptOnce(uri, body);
      } on LlmException catch (error) {
        // 重试纪律（§7.4）：仅超时/网络/限流/服务端瞬时故障可重试。
        if (!error.retryable || attempt >= config.maxAttempts) {
          rethrow;
        }
      }
      await Future<void>.delayed(config.retryBackoff * attempt);
    }
  }

  Future<List<DishCandidate>> _attemptOnce(
    Uri uri,
    String formBody,
  ) async {
    http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            // formBody 已自行 urlencode（纯 ASCII），http 包按字符集原样发送。
            body: formBody,
          )
          .timeout(
            config.timeout,
            onTimeout: () => throw LlmTimeoutException(
              '百度菜品识别超时（${config.timeout.inMilliseconds}ms，§7.4 拍照口径）',
            ),
          );
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw const LlmTimeoutException('百度菜品识别超时（§7.4 一级降级触发源）');
    } catch (error) {
      throw LlmNetworkException('百度菜品识别网络错误：$error', cause: error);
    }

    if (response.statusCode != 200) {
      throw _classifyHttpError(response.statusCode, _snippet(response.body));
    }

    // ── 业务解析：先查 error_code（百度惯例 HTTP 200 + 业务错误体）──
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw LlmBadResponseException(
        '百度响应不是合法 JSON：${_snippet(response.body)}',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw LlmBadResponseException(
        '百度响应顶层不是 JSON 对象：${_snippet(response.body)}',
      );
    }
    final errorCode = decoded['error_code'];
    if (errorCode is num) {
      // error_msg 容错取字符串（不硬 cast，理由同上）。
      throw _classifyBaiduCode(
        errorCode.toInt(),
        decoded['error_msg']?.toString() ?? '',
      );
    }

    final result = decoded['result'];
    if (result == null) {
      // 无 result 且无 error_code：识别为空（非菜品照片）→ 空候选。
      return const <DishCandidate>[];
    }
    if (result is! List) {
      throw LlmBadResponseException(
        '百度响应 result 不是数组：${_snippet(response.body)}',
      );
    }

    final candidates = <DishCandidate>[];
    for (final item in result) {
      if (item is! Map<String, Object?>) {
        continue;
      }
      // 字段容错读取（name/probability 类型异常 → 跳过该项而非崩溃）。
      final nameValue = item['name'];
      final name = nameValue is String ? nameValue.trim() : null;
      if (name == null || name.isEmpty) {
        continue;
      }
      final probability =
          item['probability'] is num ? (item['probability'] as num).toDouble() : null;
      candidates.add(DishCandidate(
        name: name,
        grams: config.defaultPortionG,
        // 百度 probability ∈ [0,1]；越界防御性截断（§5.2③ 置信度口径）。
        confidence:
            probability == null ? 0.0 : probability.clamp(0.0, 1.0).toDouble(),
      ));
    }
    // 按置信度降序截取（§3.3 确认卡按候选置信度排布）。
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));
    return candidates.length <= config.maxDishes
        ? candidates
        : candidates.sublist(0, config.maxDishes);
  }

  // ── 错误分类（复用 LlmException 体系；§7.4 同一张降级映射表）──────

  /// HTTP 状态码分类（与 openai_adapter.dart 同口径：鉴权/限流/5xx/请求非法）。
  LlmException _classifyHttpError(int statusCode, String bodySnippet) {
    if (statusCode == 401 || statusCode == 403) {
      return LlmAuthException('百度鉴权失败（HTTP $statusCode）：$bodySnippet',
          statusCode: statusCode);
    }
    if (statusCode == 429) {
      return LlmRateLimitException('百度限流（HTTP 429）');
    }
    if (statusCode >= 500 || statusCode == 408) {
      return LlmServerException(
        '百度服务端瞬时故障（HTTP $statusCode）：$bodySnippet',
        statusCode: statusCode,
      );
    }
    return LlmInvalidRequestException(
      '百度请求被拒绝（HTTP $statusCode）：$bodySnippet',
      statusCode: statusCode,
    );
  }

  /// 百度业务错误码分类（百度 AIP 通用错误码口径）：
  /// - 17/19：每日/累计请求限额耗尽 → 免费额度耗尽（§7.4 三级降级）；
  /// - 18：QPS 限流（可重试）；
  /// - 6/100/110/111：无权限 / token 无效或过期 → 鉴权失败（不重试）；
  /// - 216201/216202：图片格式/大小非法 → 请求非法（不重试）；
  /// - 1/2 及未知码：按服务端瞬时故障处理（兜底侧接管，§7.4 双供应商）。
  LlmException _classifyBaiduCode(int code, String message) {
    if (code == 17 || code == 19) {
      return LlmQuotaException('百度免费额度耗尽（error_code=$code：$message，'
          '§7.4 三级降级）');
    }
    if (code == 18) {
      return LlmRateLimitException('百度 QPS 限流（error_code=18：$message）');
    }
    if (code == 6 || code == 100 || code == 110 || code == 111) {
      return LlmAuthException(
        '百度鉴权失败（error_code=$code：$message）',
        statusCode: null,
      );
    }
    if (code == 216201 || code == 216202) {
      return LlmInvalidRequestException(
        '百度请求非法（error_code=$code：$message；图片格式/大小超限）',
      );
    }
    return LlmServerException(
      '百度服务端故障（error_code=$code：$message）',
      statusCode: null,
    );
  }

  static String _snippet(String body) =>
      body.length > 300 ? body.substring(0, 300) : body;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  static String _normalizeBaseUrl(String baseUrl) =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}
