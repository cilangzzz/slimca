/// OpenAI 兼容协议实现（§7.1「LLM adapter（OpenAI 兼容协议，可插拔）」、§7.5）。
///
/// 一套协议覆盖三类供应商（§7.5 牌价表）：GPT-4o-mini（文本双解析主力）、
/// Qwen-VL / GLM-4V（国内已备案通道，拍照 P1 用）。差异只在 baseUrl/model/
/// 档位/价目——见 [LlmModelPreset] 预设清单。
///
/// 行为约定（[LlmAdapter] 契约）：
/// - 超时：文本缺省 5s（§7.4 超时口径；照片 12s 由 [LlmRequest.timeoutOverride] 放宽）；
/// - 重试：仅对可重试分类（超时/网络/限流/5xx）按 [OpenAiCompatibleConfig.maxAttempts]
///   重试，退避线性递增；鉴权/额度/请求非法/响应非法不重试；
/// - 错误分类：HTTP 状态码 + 响应体特征 → [LlmException] 分类体系；
/// - response_format：按模型 capability 两档（json_schema / json_object）
///   自动选档或降级，档位为 none 时不附加（提示词约束 + 校验器兜底）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'llm_adapter.dart';

/// OpenAI 兼容适配器配置。
class OpenAiCompatibleConfig {
  const OpenAiCompatibleConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.jsonCapability = LlmJsonCapability.jsonObject,
    this.timeout = const Duration(seconds: 5),
    this.maxAttempts = 2,
    this.retryBackoff = const Duration(milliseconds: 300),
    this.pricing,
  });

  /// 协议根地址（如 `https://api.openai.com/v1`；末尾 `/` 会归一化）。
  final String baseUrl;

  /// API Key（Bearer 鉴权）。
  final String apiKey;

  /// 模型名（如 gpt-4o-mini）。
  final String model;

  /// 模型 response_format 档位（json_schema / json_object 两档，§7.2）。
  final LlmJsonCapability jsonCapability;

  /// 单次调用超时（§7.4：文本 5s 缺省；照片 12s 经请求覆盖）。
  final Duration timeout;

  /// 最大尝试次数（含首次；1=不重试）。
  final int maxAttempts;

  /// 重试退避基数，第 n 次重试等待 n×[retryBackoff]（测试可注入 0）。
  final Duration retryBackoff;

  /// token 价目（微元/1M tokens，§7.5）；null 时 costMicro=0。
  final LlmPricing? pricing;
}

/// 供应商预设（§7.5 成本估算表，2026-11 牌价口径——上线前必须实测复核）。
class LlmModelPreset {
  const LlmModelPreset({
    required this.id,
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.jsonCapability,
    this.vision = false,
    this.pricing,
  });

  /// 预设标识。
  final String id;

  /// 供应商标识（ai_parses.provider）。
  final String provider;

  /// OpenAI 兼容协议根地址。
  final String baseUrl;

  /// 模型名。
  final String model;

  /// response_format 档位。
  final LlmJsonCapability jsonCapability;

  /// 是否支持图像输入（拍照 P1，§3.3）。
  final bool vision;

  /// token 价目（微元/1M tokens；按图计价的通道为 null）。
  final LlmPricing? pricing;

  /// GPT-4o-mini（文本双解析主力，§7.5）：$0.15/$0.60 per 1M tokens，
  /// 按 7.2 汇率口径折算 ≈ ¥1.08 / ¥4.32 per 1M → 1_080_000 / 4_320_000 微元。
  static const LlmModelPreset gpt4oMini = LlmModelPreset(
    id: 'gpt-4o-mini',
    provider: 'openai',
    baseUrl: 'https://api.openai.com/v1',
    model: 'gpt-4o-mini',
    jsonCapability: LlmJsonCapability.jsonSchema,
    vision: false,
    pricing: LlmPricing(
      promptMicroPerMillion: 1080000,
      completionMicroPerMillion: 4320000,
    ),
  );

  /// Qwen-VL（DashScope 兼容模式；拍照 P1，§7.5 ~¥0.008-0.02/图按图计价，
  /// token 级价目 P1 接入时实测补齐——成本暂记 0 不虚报）。
  static const LlmModelPreset qwenVl = LlmModelPreset(
    id: 'qwen-vl',
    provider: 'dashscope',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-vl-plus',
    jsonCapability: LlmJsonCapability.jsonObject,
    vision: true,
  );

  /// GLM-4V（智谱 OpenAI 兼容端点；拍照 P1，§7.5 按图计价，同上待实测）。
  static const LlmModelPreset glm4v = LlmModelPreset(
    id: 'glm-4v',
    provider: 'zhipu',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4v-plus',
    jsonCapability: LlmJsonCapability.jsonObject,
    vision: true,
  );

  /// 全部预设（宿主做双供应商 fallback 编排时遍历，§7.4 第 4 级）。
  static const List<LlmModelPreset> all = [gpt4oMini, qwenVl, glm4v];
}

/// OpenAI 兼容协议适配器（§7.1 可插拔接口的实现；§7.4 双供应商 fallback
/// 时由上层以两个本类实例组合编排）。
///
/// [client] 可注入（测试用 `package:http/testing.dart` 的 MockClient——
/// 任务硬规则：测试一律离线，禁止真实网络调用）。
class OpenAiCompatibleAdapter implements LlmAdapter {
  OpenAiCompatibleAdapter(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final OpenAiCompatibleConfig config;
  final http.Client _client;

  @override
  String get providerId => 'openai_compatible';

  @override
  String get modelId => config.model;

  @override
  LlmJsonCapability get jsonCapability => config.jsonCapability;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        return await _attemptOnce(request);
      } on LlmException catch (error) {
        // 重试纪律（§7.4）：仅超时/网络/限流/服务端瞬时故障可重试；
        // 鉴权、额度、请求非法、响应非法一律立即上抛交降级映射。
        if (!error.retryable || attempt >= config.maxAttempts) {
          rethrow;
        }
      }
      await Future<void>.delayed(config.retryBackoff * attempt);
    }
  }

  Future<LlmResponse> _attemptOnce(LlmRequest request) async {
    final effectiveTimeout = request.timeoutOverride ?? config.timeout;
    // 尾部补 '/' 再 resolve：Uri.resolve 以「目录」语义拼接相对路径，
    // 不补斜杠时最后一段（如 /v1）会被相对路径替换掉。
    final uri = Uri.parse('${_normalizeBaseUrl(config.baseUrl)}/')
        .resolve('chat/completions');
    final body = _buildBody(request);

    http.Response response;
    final stopwatch = Stopwatch()..start();
    try {
      response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer ${config.apiKey}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(
            effectiveTimeout,
            onTimeout: () => throw LlmTimeoutException(
              'LLM 调用超时（${effectiveTimeout.inMilliseconds}ms，§7.4 超时口径）',
            ),
          );
    } on LlmException {
      rethrow;
    } on TimeoutException {
      throw LlmTimeoutException('LLM 调用超时（§7.4：超时 → 一级降级手填）');
    } catch (error) {
      // http.ClientException / SocketException 等传输层错误 → 网络分类
      // （§7.4：断网 → 二级降级 draft+延迟队列，§3.3 离线延迟解析）。
      throw LlmNetworkException('LLM 网络错误：$error', cause: error);
    }
    stopwatch.stop();

    final snippet = response.body.length > 300
        ? response.body.substring(0, 300)
        : response.body;
    if (response.statusCode != 200) {
      throw _classifyHttpError(response.statusCode, snippet);
    }

    // ── 2xx 响应解析：choices[0].message.content + usage ──
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw LlmBadResponseException('响应体不是合法 JSON：$snippet', cause: error);
    }
    if (decoded is! Map<String, Object?>) {
      throw LlmBadResponseException('响应体顶层不是 JSON 对象：$snippet');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw LlmBadResponseException('响应缺少 choices：$snippet');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, Object?>) {
      throw LlmBadResponseException('choices[0] 不是对象：$snippet');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, Object?>) {
      throw LlmBadResponseException('choices[0].message 不是对象：$snippet');
    }
    final contentRaw = message['content'];
    if (contentRaw is! String || contentRaw.isEmpty) {
      throw LlmBadResponseException(
        '响应缺少 content（finish_reason=${firstChoice['finish_reason']}）',
      );
    }

    final usage = decoded['usage'];
    final promptTokens = usage is Map<String, Object?>
        ? (usage['prompt_tokens'] as num?)?.toInt() ?? 0
        : 0;
    final completionTokens = usage is Map<String, Object?>
        ? (usage['completion_tokens'] as num?)?.toInt() ?? 0
        : 0;

    return LlmResponse(
      content: contentRaw,
      provider: providerId,
      model: config.model,
      latencyMs: stopwatch.elapsedMilliseconds,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      costMicro: _estimateCostMicro(promptTokens, completionTokens),
      finishReason: firstChoice['finish_reason'] as String?,
      rawBody: response.body,
    );
  }

  /// 组装 OpenAI 兼容请求体；response_format 按模型 capability 两档选位：
  /// json_schema 为最高档（§7.2），json_object 为宽档，模型不支持时不附加
  /// （约束由提示词承载、正确性由 parse 层校验器兜底）。
  Map<String, Object?> _buildBody(LlmRequest request) {
    final responseFormat = _responseFormat(request);
    return <String, Object?>{
      'model': config.model,
      'messages': <Map<String, String>>[
        for (final message in request.messages)
          <String, String>{'role': message.role.name, 'content': message.content},
      ],
      'temperature': request.temperature ?? 0.2,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (responseFormat != null) 'response_format': responseFormat,
    };
  }

  Map<String, Object?>? _responseFormat(LlmRequest request) {
    switch (request.jsonIntent) {
      case LlmJsonIntent.none:
        return null;
      case LlmJsonIntent.jsonObject:
        return config.jsonCapability == LlmJsonCapability.none
            ? null
            : const <String, Object?>{'type': 'json_object'};
      case LlmJsonIntent.jsonSchema:
        switch (config.jsonCapability) {
          case LlmJsonCapability.jsonSchema:
            return <String, Object?>{
              'type': 'json_schema',
              // strict 不强制开启：个别兼容端点不支持 strict 模式；schema
              // 是引导性约束，硬闸门在 parse 层校验器（§7.1）。
              'json_schema': <String, Object?>{
                'name': 'slimca_parse',
                'schema': request.jsonSchema,
              },
            };
          case LlmJsonCapability.jsonObject:
            return const <String, Object?>{'type': 'json_object'};
          case LlmJsonCapability.none:
            return null;
        }
    }
  }

  /// HTTP 状态码 → 错误分类（§7.1 错误分类；429 按响应体特征区分
  /// 额度耗尽与普通限流：OpenAI 额度耗尽体特征为 insufficient_quota）。
  LlmException _classifyHttpError(int statusCode, String bodySnippet) {
    if (statusCode == 401 || statusCode == 403) {
      return LlmAuthException('鉴权失败（HTTP $statusCode）：$bodySnippet',
          statusCode: statusCode);
    }
    if (statusCode == 402) {
      return LlmQuotaException('额度耗尽（HTTP 402，§7.4 三级降级）');
    }
    if (statusCode == 429) {
      if (bodySnippet.contains('insufficient_quota')) {
        return const LlmQuotaException('额度耗尽（insufficient_quota，§7.4 三级降级）');
      }
      return LlmRateLimitException('限流（HTTP 429）');
    }
    if (statusCode >= 500 || statusCode == 408) {
      return LlmServerException('服务端瞬时故障（HTTP $statusCode）：$bodySnippet',
          statusCode: statusCode);
    }
    return LlmInvalidRequestException('请求被拒绝（HTTP $statusCode）：$bodySnippet',
        statusCode: statusCode);
  }

  /// 成本估算（微元，§5.6⑭ cost 可审计；§7.5 牌价口径，无价目 → 0）。
  int _estimateCostMicro(int promptTokens, int completionTokens) {
    final pricing = config.pricing;
    if (pricing == null) {
      return 0;
    }
    final micro = promptTokens * pricing.promptMicroPerMillion +
        completionTokens * pricing.completionMicroPerMillion;
    return (micro / 1000000).round();
  }

  static String _normalizeBaseUrl(String baseUrl) =>
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
}
