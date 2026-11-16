/// AiParser 装配工厂（§11.1 W3-4 主线、§10.4「壳负责装配」）。
///
/// **中文注记（任务要求）**：真实 adapter 待 API key 配置后经
/// `--dart-define=SLIMCA_AI_BASE=... --dart-define=SLIMCA_AI_KEY=...`
/// `--dart-define=SLIMCA_AI_MODEL=...` 切换；读取逻辑已写好（下方常量），
/// **缺省一律返回 FakeParser mock**——开发与测试零真实网络调用。
///
/// 注意：`String.fromEnvironment` 是编译期常量，运行期/测试不可改写；
/// 工厂参数缺省回落到常量，测试以显式参数注入覆盖
/// （见 test/ai_parser_factory_test.dart）。
library;

import 'ai_parser.dart';
import 'fake_parser.dart';
import 'openai_compat_adapter.dart';

/// dart-define 读取（§7.1 adapter 可插拔；未注入时为空串）。
const String kSlimcaAiBase = String.fromEnvironment('SLIMCA_AI_BASE');
const String kSlimcaAiKey = String.fromEnvironment('SLIMCA_AI_KEY');
const String kSlimcaAiModel = String.fromEnvironment('SLIMCA_AI_MODEL');

/// 缺省端点（OpenAI 兼容协议根路径）。
const String kDefaultAiBaseUrl = 'https://api.openai.com/v1';

/// 缺省模型（§7.5 成本估算：文本解析默认 GPT-4o-mini）。
const String kDefaultAiModel = 'gpt-4o-mini';

/// 装配解析器：
/// - key 未配置（空串）→ [FakeParser]（默认 mock，§11.1 W3-4）；
/// - key 已配置 → [OpenAiCompatAdapter]；base/model 缺省时按 §7.5 落
///   `https://api.openai.com/v1` + `gpt-4o-mini`。
AiParser createAiParser({String? baseUrl, String? apiKey, String? model}) {
  final key = apiKey ?? kSlimcaAiKey;
  if (key.isEmpty) {
    return const FakeParser(); // 默认 mock：未配置 API key（§11.1 W3-4）
  }
  final resolvedBase = (baseUrl ?? kSlimcaAiBase).trim();
  final resolvedModel = (model ?? kSlimcaAiModel).trim();
  return OpenAiCompatAdapter(
    baseUrl: resolvedBase.isEmpty ? kDefaultAiBaseUrl : resolvedBase,
    apiKey: key,
    model: resolvedModel.isEmpty ? kDefaultAiModel : resolvedModel,
  );
}
