/// OpenAI 兼容协议 adapter（§7.1「LLM adapter（OpenAI 兼容协议，可插拔）」、
/// §7.5 文本解析默认 GPT-4o-mini）。
///
/// **真实 adapter：待 API key 配置后经
/// `--dart-define=SLIMCA_AI_BASE` / `--dart-define=SLIMCA_AI_KEY` /
/// `--dart-define=SLIMCA_AI_MODEL` 启用**（工厂 lib/ai/ai_parser_factory.dart
/// 按 key 是否配置决定装配；默认仍是 FakeParser mock）。
///
/// 协议要点：
/// - `POST {base}/chat/completions`，Bearer 鉴权；
/// - `response_format=json_schema`（§7.2 受约束输出，strict 拒绝自由文本）；
/// - 文本超时 5s（§7.4 降级方案表）；超时/非 2xx/坏 JSON/校验不过一律抛
///   [AiParserException] → 上层 100% 降级手填（§11.1 W3-4 验收）。
library;

import 'dart:convert';
import 'dart:io';

import 'ai_parser.dart';

/// OpenAI 兼容协议解析 adapter（可插拔实现之一，§7.1）。
class OpenAiCompatAdapter implements AiParser {
  OpenAiCompatAdapter({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 5), // §7.4：文本超时 5s
  });

  /// 兼容端点根（如 `https://api.openai.com/v1`）。
  final String baseUrl;

  /// API key（Bearer）。
  final String apiKey;

  /// 模型名（§7.5 默认 GPT-4o-mini）。
  final String model;

  /// 文本解析超时（§7.4）。
  final Duration timeout;

  /// 提示词版本（§5.6⑭ prompt_version，可 A/B 对比）。
  static const String promptVersion = 'slimca-text-v1';

  @override
  Future<AiParseResult> parse(AiParseRequest request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final responseBody = await _postChatCompletions(request);
      final result = mapOpenAiResponse(
        responseBody,
        model: model,
        latencyMs: stopwatch.elapsedMilliseconds,
      );
      return result;
    } on AiParserException {
      rethrow; // 降级信号原样上抛（§7.4）
    } catch (error) {
      // 一切非预期错误（网络/超时/协议）统一收敛为降级信号。
      throw AiParserException('OpenAI 兼容解析失败：$error');
    }
  }

  Future<Map<String, Object?>> _postChatCompletions(
    AiParseRequest request,
  ) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = timeout;
      final endpoint =
          '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}'
          '/chat/completions';
      final httpRequest = await client
          .postUrl(Uri.parse(endpoint))
          .timeout(timeout);
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      httpRequest.add(utf8.encode(jsonEncode(_chatBody(request))));
      final response = await httpRequest.close().timeout(timeout);
      final bodyText =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiParserException(
          'OpenAI 兼容端点 HTTP ${response.statusCode}（§7.4 失败降级）',
        );
      }
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map) {
        throw AiParserException('OpenAI 兼容端点响应顶层非 JSON 对象');
      }
      return Map<String, Object?>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> _chatBody(AiParseRequest request) =>
      <String, Object?>{
        'model': model,
        'temperature': 0.1,
        // §7.2 JSON Schema 受约束输出（strict：拒绝自由文本）。
        'response_format': <String, Object?>{
          'type': 'json_schema',
          'json_schema': <String, Object?>{
            'name': 'slimca_parse',
            'strict': true,
            'schema': _constrainedSchema(),
          },
        },
        'messages': <Object?>[
          <String, Object?>{'role': 'system', 'content': _systemPrompt},
          <String, Object?>{'role': 'user', 'content': request.input},
        ],
      };

  static const String _systemPrompt =
      '你是记账与热量解析助手。从输入中抽取事件标题（title）、热量行'
      '（type=calorie，amount_kcal∈[0,5000]）与金额行（type=money，'
      'amount_minor=分，>0），以及行级置信度 confidence∈[0,1] 与菜品明细'
      ' items。只输出符合 JSON Schema 的 JSON 对象，不输出任何解释文字。';

  /// §7.2 JSON Schema（受约束输出示例的落点；kind 枚举与 §5.2① 一致）。
  Map<String, Object?> _constrainedSchema() => <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': <String>['title', 'kind', 'lines'],
        'properties': <String, Object?>{
          'title': <String, Object?>{'type': 'string'},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': <String>['food', 'fitness', 'expense', 'mixed', 'note'],
          },
          'parse_notes': <String, Object?>{'type': 'string'},
          'lines': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'additionalProperties': false,
              'required': <String>['type'],
              'properties': <String, Object?>{
                'type': <String, Object?>{
                  'type': 'string',
                  'enum': <String>['calorie', 'money'],
                },
                'amount_kcal': <String, Object?>{
                  'type': 'integer',
                  'minimum': 0,
                  'maximum': 5000,
                },
                'amount_minor': <String, Object?>{
                  'type': 'integer',
                  'minimum': 1,
                },
                'currency': <String, Object?>{'type': 'string'},
                'confidence': <String, Object?>{
                  'type': 'number',
                  'minimum': 0,
                  'maximum': 1,
                },
                'category_hint': <String, Object?>{'type': 'string'},
                'ledger_hint': <String, Object?>{'type': 'string'},
                'merchant': <String, Object?>{
                  'type': <String>['string', 'null'],
                },
                'items': <String, Object?>{
                  'type': 'array',
                  'items': <String, Object?>{
                    'type': 'object',
                    'additionalProperties': false,
                    'properties': <String, Object?>{
                      'name': <String, Object?>{'type': 'string'},
                      'portion_g': <String, Object?>{'type': 'number'},
                      'kcal': <String, Object?>{'type': 'number'},
                      'protein_g': <String, Object?>{'type': 'number'},
                      'carb_g': <String, Object?>{'type': 'number'},
                      'fat_g': <String, Object?>{'type': 'number'},
                      'ref_source': <String, Object?>{'type': 'string'},
                    },
                  },
                },
              },
            },
          },
        },
      };
}

/// OpenAI chat.completions 响应 → [AiParseResult]。
///
/// 纯函数、无网络：从响应体剥出 content → JSON 解码 → canonical 归一
/// （amount_kcal/amount_minor → amount，§5.1 存储口径）→ §7.1 校验器过闸。
/// 独立导出便于无网络单测（§7.2 示例直解）。
AiParseResult mapOpenAiResponse(
  Map<String, Object?> responseBody, {
  required String model,
  required int latencyMs,
  String provider = 'openai-compat',
}) {
  final choices = responseBody['choices'];
  if (choices is! List || choices.isEmpty) {
    throw const AiParserException('OpenAI 响应缺 choices（协议不符，§7.4 降级）');
  }
  final first = choices.first;
  if (first is! Map) {
    throw const AiParserException('OpenAI choices[0] 非对象（协议不符）');
  }
  final message = first['message'];
  if (message is! Map) {
    throw const AiParserException('OpenAI choices[0].message 非对象（协议不符）');
  }
  final content = message['content'];
  if (content is! String || content.trim().isEmpty) {
    throw const AiParserException('OpenAI content 为空（受约束解码失败，§7.2）');
  }
  final Object? payload;
  try {
    payload = jsonDecode(content);
  } catch (_) {
    throw const AiParserException('受约束解码失败：content 非 JSON（§7.2）');
  }
  if (payload is! Map) {
    throw const AiParserException('受约束解码失败：content 顶层非 JSON 对象（§7.2）');
  }
  // 注入运行元数据（§5.6⑭ provider/model/prompt_version/latency_ms/cost）。
  final canonical = Map<String, Object?>.from(payload);
  canonical['provider'] = provider;
  canonical['model'] = model;
  canonical['prompt_version'] = OpenAiCompatAdapter.promptVersion;
  canonical['latency_ms'] = latencyMs;
  // 成本计量 W7-8 埋点接入（§5.6⑭ cost 微元可审计）；W3-4 记 0。
  canonical['cost_micro'] = 0;
  final result = AiParseResult.fromJson(canonical);
  validateAiParseResult(result); // §7.1 校验器：坏结果一律拒收 → 降级
  return result;
}
