/// 确定性脚本化 LLM 假适配器（测试专用——任务硬规则：测试一律注入
/// Fake/Mock 解析器，禁止真实网络调用；亦可用于预览/开发期桩）。
///
/// 两种脚本形态：
/// - [FakeLlmAdapter.scripted]：按调用次序依次弹出脚本项；脚本项为
///   `String`（该次响应文本）或 [LlmException]（该次抛出的分类异常）；
/// - [FakeLlmAdapter.keyed]：按「最新 user 消息内容包含关键字」路由到
///   固定响应文本（模拟常吃常花的确定性回放）。
///
/// [requests] 记录每次收到的请求（断言 prompt/schema/jsonIntent 用）；
/// 响应延迟恒 0、usage 固定值、costMicro 由可选 pricing 计算——不引入
/// 真实时钟/网络，测试完全离线且确定。
library;

import '../llm/llm_adapter.dart';

class FakeLlmAdapter implements LlmAdapter {
  FakeLlmAdapter._({
    required Object? Function(int callIndex, String? lastUserContent) next,
    this.providerId = 'fake',
    this.modelId = 'fake-model',
    this.jsonCapability = LlmJsonCapability.jsonSchema,
    this.pricing,
  }) : _next = next;

  /// 顺序脚本工厂：脚本项为 `String`（响应文本）或 [LlmException]（抛出）。
  ///
  /// 脚本耗尽即抛 StateError（测试脚本不足应显式暴露，而非静默重复）。
  factory FakeLlmAdapter.scripted(
    List<Object> script, {
    String providerId = 'fake',
    String modelId = 'fake-model',
    LlmJsonCapability jsonCapability = LlmJsonCapability.jsonSchema,
    LlmPricing? pricing,
  }) {
    final items = List<Object>.unmodifiable(script);
    return FakeLlmAdapter._(
      next: (callIndex, _) {
        if (callIndex >= items.length) {
          throw StateError(
            'FakeLlmAdapter 脚本耗尽（第 $callIndex 次调用，脚本共 '
            '${items.length} 项）——测试脚本与预期调用次数不符',
          );
        }
        return items[callIndex];
      },
      providerId: providerId,
      modelId: modelId,
      jsonCapability: jsonCapability,
      pricing: pricing,
    );
  }

  /// 关键字路由工厂：最新 user 消息包含某键 → 固定响应文本；
  /// 未命中任何键 → [fallback]（null 则抛 StateError）。
  factory FakeLlmAdapter.keyed(
    Map<String, String> responsesBySubstring, {
    String? fallback,
    String providerId = 'fake',
    String modelId = 'fake-model',
    LlmJsonCapability jsonCapability = LlmJsonCapability.jsonSchema,
    LlmPricing? pricing,
  }) =>
      FakeLlmAdapter._(
        next: (callIndex, lastUserContent) {
          if (lastUserContent != null) {
            for (final entry in responsesBySubstring.entries) {
              if (lastUserContent.contains(entry.key)) {
                return entry.value;
              }
            }
          }
          if (fallback == null) {
            throw StateError('FakeLlmAdapter.keyed：无关键字命中且未配置 fallback');
          }
          return fallback;
        },
        providerId: providerId,
        modelId: modelId,
        jsonCapability: jsonCapability,
        pricing: pricing,
      );

  final Object? Function(int callIndex, String? lastUserContent) _next;

  @override
  final String providerId;

  @override
  final String modelId;

  @override
  final LlmJsonCapability jsonCapability;

  final LlmPricing? pricing;

  /// 收到的请求日志（按调用序；断言 prompt/schema/单边约束用）。
  final List<LlmRequest> requests = <LlmRequest>[];

  int _callIndex = 0;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    requests.add(request);
    final index = _callIndex++;
    final lastUser = _lastUserContent(request);
    final item = _next(index, lastUser);
    if (item is LlmException) {
      throw item;
    }
    if (item is! String) {
      throw StateError('FakeLlmAdapter 脚本项必须是 String 或 LlmException，'
          '实际 ${item.runtimeType}');
    }
    var promptTokens = 0;
    var completionTokens = 0;
    if (pricing != null) {
      promptTokens = 1000;
      completionTokens = 200;
    }
    return LlmResponse(
      content: item,
      provider: providerId,
      model: modelId,
      latencyMs: 0,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      costMicro: pricing == null
          ? 0
          : ((promptTokens * pricing!.promptMicroPerMillion +
                      completionTokens * pricing!.completionMicroPerMillion) /
                  1000000)
              .round(),
      finishReason: 'stop',
    );
  }

  /// 最近一条 user 消息内容（keyed 路由与断言用）。
  static String? _lastUserContent(LlmRequest request) {
    for (final message in request.messages.reversed) {
      if (message.role == LlmRole.user) {
        return message.content;
      }
    }
    return null;
  }

  /// 最近一次请求（便捷断言）。
  LlmRequest? get lastRequest => requests.isEmpty ? null : requests.last;
}
