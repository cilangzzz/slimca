/// OpenAI 兼容适配器测试（§7.1 LLM adapter：协议形状、两档 capability、
/// 超时/重试/错误分类、成本估算）。
///
/// 全部经 `package:http/testing.dart` 的 MockClient 离线执行——禁止真实
/// 网络调用（任务硬规则）。
library;

import 'dart:convert';

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 200 响应体（choices + usage）。
String okBody(String content) => jsonEncode(<String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'content': content},
          'finish_reason': 'stop',
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 1000,
        'completion_tokens': 500,
      },
    });

OpenAiCompatibleConfig makeConfig({
  LlmJsonCapability capability = LlmJsonCapability.jsonSchema,
  int maxAttempts = 2,
  Duration timeout = const Duration(seconds: 5),
  LlmPricing? pricing,
  String baseUrl = 'https://api.openai.com/v1',
}) =>
    OpenAiCompatibleConfig(
      baseUrl: baseUrl,
      apiKey: 'sk-test',
      model: 'gpt-4o-mini',
      jsonCapability: capability,
      maxAttempts: maxAttempts,
      retryBackoff: Duration.zero,
      timeout: timeout,
      pricing: pricing,
    );

void main() {
  group('请求形状（协议层，§7.1 OpenAI 兼容协议）', () {
    test('POST 到 baseUrl/chat/completions，Bearer 鉴权，消息与 schema 透传', () async {
      final captured = <http.Request>[];
      final client = MockClient((request) async {
        captured.add(request);
        return http.Response(okBody('{}'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);

      const schema = <String, Object?>{'type': 'object'};
      await adapter.complete(const LlmRequest(
        messages: <LlmMessage>[
          LlmMessage(LlmRole.system, '系统提示'),
          LlmMessage(LlmRole.user, '中午吃了兰州拉面花了 18'),
        ],
        jsonIntent: LlmJsonIntent.jsonSchema,
        jsonSchema: schema,
      ));

      final request = captured.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer sk-test');
      expect(request.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['model'], 'gpt-4o-mini');
      expect(body['temperature'], 0.2, reason: '解析任务低温（缺省 0.2）');
      final messages = body['messages'] as List<Object?>;
      expect((messages[0] as Map<String, Object?>)['role'], 'system');
      expect((messages[0] as Map<String, Object?>)['content'], '系统提示');
      expect((messages[1] as Map<String, Object?>)['role'], 'user');
      // json_schema 最高档（§7.2）
      final responseFormat = body['response_format'] as Map<String, Object?>;
      expect(responseFormat['type'], 'json_schema');
      final jsonSchema = responseFormat['json_schema'] as Map<String, Object?>;
      expect(jsonSchema['name'], 'slimca_parse');
      // schema 原样透传（请求体经 JSON 编解码，断言值相等而非引用）。
      expect(jsonSchema['schema'], equals(schema));
    });

    test('json_object 档：模型 capability=object 时 json_schema 请求自动降级', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(okBody('{}'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(
        makeConfig(capability: LlmJsonCapability.jsonObject),
        client: client,
      );
      await adapter.complete(const LlmRequest(
        messages: [LlmMessage(LlmRole.user, 'x')],
        jsonIntent: LlmJsonIntent.jsonSchema,
        jsonSchema: {'type': 'object'},
      ));
      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      final format = body['response_format'] as Map<String, Object?>;
      expect(format['type'], 'json_object',
          reason: '§7.2：请求档位高于模型档位 → 降级为宽档，校验器兜底');
    });

    test('capability=none 时不附加 response_format（提示词约束 + 校验器兜底）', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(okBody('{}'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(
        makeConfig(capability: LlmJsonCapability.none),
        client: client,
      );
      await adapter.complete(LlmRequest(
        messages: const [LlmMessage(LlmRole.user, 'x')],
        jsonIntent: LlmJsonIntent.jsonSchema,
        jsonSchema: const {'type': 'object'},
      ));
      final body = jsonDecode(captured!.body) as Map<String, Object?>;
      expect(body.containsKey('response_format'), isFalse);
    });

    test('baseUrl 带尾斜杠时归一化拼接', () async {
      http.Request? captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(okBody('{}'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(
        makeConfig(baseUrl: 'https://api.openai.com/v1/'),
        client: client,
      );
      await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      expect(captured!.url.toString(), 'https://api.openai.com/v1/chat/completions');
    });
  });

  group('响应解析与成本估算（§5.6⑭ cost 微元、§7.5 牌价）', () {
    test('200：提取 content/usage/finish_reason，按价目折算微元', () async {
      final client = MockClient((request) async => http.Response(okBody('{"a":1}'), 200));
      final adapter = OpenAiCompatibleAdapter(
        makeConfig(pricing: LlmModelPreset.gpt4oMini.pricing),
        client: client,
      );
      final response = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      expect(response.content, '{"a":1}');
      expect(response.promptTokens, 1000);
      expect(response.completionTokens, 500);
      expect(response.finishReason, 'stop');
      expect(response.provider, 'openai_compatible');
      expect(response.model, 'gpt-4o-mini');
      // (1000×1.08 + 500×4.32) 微元 = 1080 + 2160 = 3240 微元。
      expect(response.costMicro, 3240);
    });

    test('无价目时 costMicro=0（按图计价通道，§7.5 Qwen/GLM 口径）', () async {
      final client = MockClient((request) async => http.Response(okBody('x'), 200));
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      final response = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      expect(response.costMicro, 0);
    });

    test('缺 content（截断等）→ LlmBadResponseException（不可重试）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{},
                'finish_reason': 'length',
              },
            ],
          }),
          200,
        );
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmBadResponseException>()),
      );
      expect(calls, 1, reason: '内容级失败不重试（解析级重试在管线层）');
    });
  });

  group('错误分类与重试（§7.1 错误分类、§7.4 降级触发源）', () {
    test('401 → LlmAuthException，不重试', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"error":"unauthorized"}', 401);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmAuthException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
      expect(calls, 1);
    });

    test('500 → LlmServerException，重试 1 次后仍失败（maxAttempts=2）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('boom', 500);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmServerException>()
            .having((e) => e.statusCode, 'statusCode', 500)),
      );
      expect(calls, 2);
    });

    test('500 后 200 → 重试成功', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response('boom', 500);
        }
        return http.Response(okBody('ok'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      final response = await adapter.complete(
        const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
      );
      expect(response.content, 'ok');
      expect(calls, 2);
    });

    test('429 → LlmRateLimitException（可重试）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('{"error":"rate limited"}', 429);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(maxAttempts: 1), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmRateLimitException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
      expect(calls, 1);
    });

    test('429 + insufficient_quota → LlmQuotaException（额度耗尽，不重试）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{'code': 'insufficient_quota'},
          }),
          429,
        );
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmQuotaException>()
            .having((e) => e.retryable, 'retryable', isFalse)),
      );
      expect(calls, 1);
    });

    test('402 → LlmQuotaException（§7.4 三级降级触发源）', () async {
      final client = MockClient((request) async => http.Response('paid', 402));
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmQuotaException>()),
      );
    });

    test('400 → LlmInvalidRequestException（不可重试）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response('bad request', 400);
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmInvalidRequestException>()),
      );
      expect(calls, 1);
    });

    test('传输层错误 → LlmNetworkException（断网 → §7.4 二级降级触发源）', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        throw http.ClientException('connection refused');
      });
      final adapter = OpenAiCompatibleAdapter(makeConfig(maxAttempts: 1), client: client);
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmNetworkException>()
            .having((e) => e.retryable, 'retryable', isTrue)),
      );
      expect(calls, 1);
    });

    test('超时 → LlmTimeoutException（§7.4 文本 5s 口径，此处注入短超时）', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        return http.Response(okBody('late'), 200);
      });
      final adapter = OpenAiCompatibleAdapter(
        makeConfig(maxAttempts: 1, timeout: const Duration(milliseconds: 50)),
        client: client,
      );
      await expectLater(
        adapter.complete(
          const LlmRequest(messages: [LlmMessage(LlmRole.user, 'x')]),
        ),
        throwsA(isA<LlmTimeoutException>()),
      );
    });
  });

  group('预设清单（§7.5：GPT-4o-mini / Qwen-VL / GLM-4V / DeepSeek）', () {
    test('四预设齐备且字段口径正确', () {
      expect(LlmModelPreset.all, hasLength(4));
      expect(LlmModelPreset.gpt4oMini.model, 'gpt-4o-mini');
      expect(LlmModelPreset.gpt4oMini.jsonCapability, LlmJsonCapability.jsonSchema);
      expect(LlmModelPreset.gpt4oMini.pricing, isNotNull);
      // $0.15/1M tokens × 7.2 汇率 ≈ ¥1.08 → 1_080_000 微元（§7.5 口径）。
      expect(LlmModelPreset.gpt4oMini.pricing!.promptMicroPerMillion, 1080000);

      expect(LlmModelPreset.qwenVl.vision, isTrue, reason: '拍照 P1 通道');
      expect(LlmModelPreset.glm4v.vision, isTrue);
      expect(LlmModelPreset.qwenVl.jsonCapability, LlmJsonCapability.jsonObject);
      expect(LlmModelPreset.glm4v.jsonCapability, LlmJsonCapability.jsonObject);

      // DeepSeek：2026-11-17 真实联调通过（文本双解析+多模态格式）；
      // API id 与展示名不同（展示名 DeepSeek-V4.1-Flash-1017 → API id
      // deepseek-flash）；价目待实测故 pricing 为 null 不虚报。
      expect(LlmModelPreset.deepseek.baseUrl, 'https://api.deepseek.com/v1');
      expect(LlmModelPreset.deepseek.model, 'deepseek-flash');
      expect(LlmModelPreset.deepseek.vision, isTrue);
      expect(LlmModelPreset.deepseek.jsonCapability, LlmJsonCapability.jsonObject);
      expect(LlmModelPreset.deepseek.pricing, isNull, reason: '价目未实测不虚报（§7.5 口径）');
    });
  });
}
