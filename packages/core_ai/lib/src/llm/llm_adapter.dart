/// LLM 适配器抽象层（§7.1「LLM adapter（OpenAI 兼容协议，可插拔）」、§10.4）。
///
/// 职责边界：本层只负责「一次补全调用」——消息编排、response_format 两档
/// capability（json_schema / json_object）、超时与重试、HTTP/供应商错误的
/// 分类映射。提示词组装与受约束解码/校验属 parse 层（§7.1-§7.4），本层
/// 不感知业务语义。
///
/// 供应商差异收敛在 [LlmAdapter] 实现内：上层管线只见抽象接口。§7.4 第 4 级
/// 「双供应商 fallback」由上层组合多个 adapter 实现（编排接口预留，见
/// `src/degrade/degrade_hooks.dart`），本层不内置第二供应商逻辑。
library;

import 'dart:async';

/// 消息角色（OpenAI chat/completions 协议）。
enum LlmRole { system, user, assistant }

/// 一条对话消息。
///
/// W3-4 文本通道只走纯文本；照片通道（P1，§3.3）届时以多段 content 扩展
/// 本类（text + image_url），协议结构不变——本层 API 面向前兼容预留。
class LlmMessage {
  const LlmMessage(this.role, this.content);

  final LlmRole role;
  final String content;
}

/// 请求侧期望的受约束输出档位（§7.2 JSON Schema 受约束输出）。
enum LlmJsonIntent {
  /// 不附加 response_format（保留能力位）。
  none,

  /// `response_format={"type":"json_object"}`：模型自行遵循提示词中的
  /// schema 文本（宽档——必须由校验器兜底）。
  jsonObject,

  /// `response_format={"type":"json_schema",...}`：受约束解码最高档
  /// （§7.2，引擎级保证输出合法 JSON）。
  jsonSchema,
}

/// 模型对 response_format 的支持档位（两档 capability 口径：json_schema 与
/// json_object）。请求档位高于模型档位时适配器自动降级（§7.1 校验器始终
/// 是硬闸门，降级只影响引擎级保证、不影响正确性）。
enum LlmJsonCapability { none, jsonObject, jsonSchema }

/// token 单价：微元 / 1M tokens（§5.6⑭ cost 以微元计、成本可审计；
/// §7.5 牌价口径，上线前必须实测复核）。
class LlmPricing {
  const LlmPricing({
    required this.promptMicroPerMillion,
    required this.completionMicroPerMillion,
  });

  /// 输入 token 单价（微元 / 1M tokens）。
  final int promptMicroPerMillion;

  /// 输出 token 单价（微元 / 1M tokens）。
  final int completionMicroPerMillion;
}

/// 一次补全请求。
class LlmRequest {
  const LlmRequest({
    required this.messages,
    this.jsonIntent = LlmJsonIntent.none,
    this.jsonSchema,
    this.temperature,
    this.maxTokens,
    this.timeoutOverride,
  }) : assert(
          jsonIntent != LlmJsonIntent.jsonSchema || jsonSchema != null,
          'jsonIntent=jsonSchema 时必须携带 jsonSchema（§7.2 受约束输出）',
        );

  /// 对话消息（系统提示词在前）。
  final List<LlmMessage> messages;

  /// 期望的受约束输出档位（§7.2）。
  final LlmJsonIntent jsonIntent;

  /// JSON Schema 文档；[LlmJsonIntent.jsonSchema] 时必填。
  final Map<String, Object?>? jsonSchema;

  /// 采样温度；解析任务建议低温（缺省由适配器取 0.2）。
  final double? temperature;

  /// 最大输出 token（缺省由适配器决定）。
  final int? maxTokens;

  /// 单次调用超时覆盖（§7.4 超时口径：文本 5s / 照片 12s——照片 P1 时
  /// 由调用方以本字段放宽，适配器配置里保留文本缺省 5s）。
  final Duration? timeoutOverride;
}

/// 一次补全响应。
class LlmResponse {
  const LlmResponse({
    required this.content,
    required this.provider,
    required this.model,
    required this.latencyMs,
    required this.promptTokens,
    required this.completionTokens,
    required this.costMicro,
    this.finishReason,
    this.rawBody,
  });

  /// 首选输出文本（受约束 JSON 字符串；解码校验由 parse 层负责）。
  final String content;

  /// 供应商标识（ai_parses.provider，§5.6⑭ 可 A/B 对比）。
  final String provider;

  /// 模型名（ai_parses.model）。
  final String model;

  /// 本次调用墙钟延迟（毫秒，ai_parses.latency_ms）。
  final int latencyMs;

  /// 输入 token 数（usage.prompt_tokens；缺省 0）。
  final int promptTokens;

  /// 输出 token 数（usage.completion_tokens；缺省 0）。
  final int completionTokens;

  /// 成本估算（微元，ai_parses.cost；§7.5 牌价口径，无价目时为 0）。
  final int costMicro;

  /// 供应商返回的结束原因（如 stop/length）。
  final String? finishReason;

  /// 原始响应体（排查用，不落库）。
  final String? rawBody;
}

/// LLM 调用异常基类（§7.1 错误分类、§7.4 降级映射的源头）。
///
/// [retryable] 供适配器/编排层判定是否值得重试；parse 层据此映射
/// [StructuredFailure]（ai_parser.dart）。sealed：全部分类同库枚举，
/// switch 穷尽由编译器保证，新增分类必然显式接入降级映射。
sealed class LlmException implements Exception {
  const LlmException(this.message, {this.cause});

  /// 人读错误摘要。
  final String message;

  /// 原始异常（排查用）。
  final Object? cause;

  /// 是否值得重试（§7.4：超时/瞬时故障重试；鉴权/额度类不重试）。
  bool get retryable;

  @override
  String toString() => '$runtimeType: $message';
}

/// 超时（§7.4 一级降级触发源之一：超时 → 降级手填）。
final class LlmTimeoutException extends LlmException {
  const LlmTimeoutException(super.message, {super.cause});

  @override
  bool get retryable => true;
}

/// 网络不可达（断网 → §7.4 二级降级：draft + 延迟解析队列，§3.3 离线延迟解析）。
final class LlmNetworkException extends LlmException {
  const LlmNetworkException(super.message, {super.cause});

  @override
  bool get retryable => true;
}

/// 服务端瞬时故障（4xx 之外的网关/5xx，可重试）。
final class LlmServerException extends LlmException {
  const LlmServerException(super.message, {this.statusCode, super.cause});

  /// HTTP 状态码（诊断用）。
  final int? statusCode;

  @override
  bool get retryable => true;
}

/// 限流（429 且非额度耗尽，可重试）。
final class LlmRateLimitException extends LlmException {
  const LlmRateLimitException(super.message, {super.cause});

  @override
  bool get retryable => true;
}

/// 免费额度耗尽（§7.4 三级降级：明确提示当日剩余额度与升级入口，
/// 手填不受限）。不可重试——重试只会继续失败。
final class LlmQuotaException extends LlmException {
  const LlmQuotaException(super.message, {super.cause});

  @override
  bool get retryable => false;
}

/// 鉴权失败（401/403）。不可重试。
final class LlmAuthException extends LlmException {
  const LlmAuthException(super.message, {this.statusCode, super.cause});

  /// HTTP 状态码（诊断用）。
  final int? statusCode;

  @override
  bool get retryable => false;
}

/// 请求本身非法（400/404/413/422 等：提示词超长、模型名错误等）。不可重试。
final class LlmInvalidRequestException extends LlmException {
  const LlmInvalidRequestException(super.message, {this.statusCode, super.cause});

  /// HTTP 状态码（诊断用）。
  final int? statusCode;

  @override
  bool get retryable => false;
}

/// 响应体非法（2xx 但缺 choices/content 或 body 非 JSON）。不可重试——
/// 内容级失败由 parse 层的重试（带纠错反馈）处理，适配器层重试无意义。
final class LlmBadResponseException extends LlmException {
  const LlmBadResponseException(super.message, {super.cause});

  @override
  bool get retryable => false;
}

/// LLM 适配器抽象（§7.1「可插拔」；§10.4 core_ai 职责之一）。
///
/// 实现约定：
/// - [complete] 必须自带「超时 + 瞬时错误重试」（次数/退避由实现配置决定），
///   抛出的异常一律是 [LlmException] 及其子类（错误分类已完成）；
/// - [jsonCapability] 声明模型档位：请求档位高于声明时实现必须自动降级
///   （§7.2：两档 capability；降级后正确性由 parse 层校验器兜底）。
abstract interface class LlmAdapter {
  /// 供应商标识（ai_parses.provider，§5.6⑭）。
  String get providerId;

  /// 模型名（ai_parses.model）。
  String get modelId;

  /// 模型支持的 response_format 档位（json_schema / json_object 两档口径）。
  LlmJsonCapability get jsonCapability;

  /// 执行一次补全调用。
  Future<LlmResponse> complete(LlmRequest request);
}
