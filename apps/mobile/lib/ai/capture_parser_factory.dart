/// CaptureParser 装配工厂（§11.1 W3-4 主线、§10.4「壳负责装配」；三接缝
/// 收敛后壳层仅保留的 AI 装配点——组合 core_ai adapter 与 dart-define）。
///
/// **中文注记（任务要求）**：真实 adapter 待 API key 配置后经
/// `--dart-define=SLIMCA_AI_BASE=... --dart-define=SLIMCA_AI_KEY=...`
/// `--dart-define=SLIMCA_AI_MODEL=...` 切换；读取逻辑在下方常量——
/// **缺省一律装配 HeuristicFakeLlmAdapter（默认 mock）**：经 core_ai
/// [LlmAiParser] 管线产出确定性解析结果，开发与测试零真实网络调用。
///
/// 注意：`String.fromEnvironment` 是编译期常量，运行期/测试不可改写；
/// 工厂参数缺省回落到常量，测试以显式参数注入覆盖
/// （见 test/capture_parser_factory_test.dart）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:feature_capture/feature_capture.dart' show CaptureParser;

import 'capture_parser_bridge.dart';

/// dart-define 读取（§7.1 adapter 可插拔；未注入时为空串）。
const String kSlimcaAiBase = String.fromEnvironment('SLIMCA_AI_BASE');
const String kSlimcaAiKey = String.fromEnvironment('SLIMCA_AI_KEY');
const String kSlimcaAiModel = String.fromEnvironment('SLIMCA_AI_MODEL');

/// 缺省端点（OpenAI 兼容协议根路径）。
const String kDefaultAiBaseUrl = 'https://api.openai.com/v1';

/// 缺省模型（§7.5 成本估算：文本解析默认 GPT-4o-mini）。
const String kDefaultAiModel = 'gpt-4o-mini';

/// 装配解析器（core_ai 管线 → CaptureParser 桥，§10.4）：
/// - key 未配置（空串）→ [HeuristicFakeLlmAdapter]（默认 mock，§11.1 W3-4）；
/// - key 已配置 → [OpenAiCompatibleAdapter]；base/model 缺省时按 §7.5 落
///   `https://api.openai.com/v1` + `gpt-4o-mini`；response_format 档位：
///   缺省模型 json_schema（§7.2 最高档），自定义模型取 json_object 宽档
///   （个别兼容端点不支持 json_schema 信封，正确性由 core_ai 校验器兜底）。
CaptureParser createCaptureParser({String? baseUrl, String? apiKey, String? model}) {
  final key = (apiKey ?? kSlimcaAiKey).trim();
  if (key.isEmpty) {
    // 默认 mock：未配置 API key——经 core_ai 完整管线的确定性离线桩。
    return CoreAiCaptureParser(adapter: const HeuristicFakeLlmAdapter());
  }
  final resolvedBase = (baseUrl ?? kSlimcaAiBase).trim();
  final resolvedModel = (model ?? kSlimcaAiModel).trim();
  final effectiveBase = resolvedBase.isEmpty ? kDefaultAiBaseUrl : resolvedBase;
  final effectiveModel = resolvedModel.isEmpty ? kDefaultAiModel : resolvedModel;
  return CoreAiCaptureParser(
    adapter: OpenAiCompatibleAdapter(
      OpenAiCompatibleConfig(
        baseUrl: effectiveBase,
        apiKey: key,
        model: effectiveModel,
        jsonCapability: effectiveModel == kDefaultAiModel
            ? LlmJsonCapability.jsonSchema
            : LlmJsonCapability.jsonObject,
        // 文本超时按 §7.4 降级方案表：5s。
        timeout: const Duration(seconds: 5),
      ),
    ),
  );
}
