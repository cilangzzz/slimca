/// 拍照通道 dart-define 装配工厂（§11.2 W11-12 主线「拍照通道」、§10.4
/// 「壳负责装配」的 core_ai 侧落点；与文本通道 capture_parser_factory
/// 同一装配模式）。
///
/// **中文注记（任务口径）**：真实供应商凭据未提供——百度识别与 Vision LLM
/// 均按 dart-define/配置注入，**缺省一律确定性 Fake**（默认 mock）：
/// - `--dart-define=SLIMCA_BAIDU_ACCESS_TOKEN=…`（短效 token 直注入）或
///   `--dart-define=SLIMCA_BAIDU_API_KEY=… --dart-define=SLIMCA_BAIDU_SECRET_KEY=…`
///   （AK/SK 在线换取 token，推荐编译期注入形态）→ 百度菜品识别先行侧；
/// - `--dart-define=SLIMCA_AI_BASE=… --dart-define=SLIMCA_AI_KEY=…`
///   `--dart-define=SLIMCA_AI_MODEL=…` → Vision LLM 兜底侧（与文本通道同
///   一组 SLIMCA_AI_* 口径；须为视觉模型——Qwen-VL/GLM-4V 预设，§7.5；
///   文本缺省模型 gpt-4o-mini 非视觉，注入它会导致兜底侧不可用）；
/// - API Key 不入仓库（docs/ops 算法备案材料同口径）。
///
/// 装配规则（§7.4「双供应商 fallback（百度菜品识别↔Vision LLM）」，百度
/// 先行）：
/// - 双配 → [BaiduDishAdapter, VisionLlmDishAdapter]；
/// - 仅百度 → [BaiduDishAdapter]（兜底缺位：百度失败即 StructuredFailure
///   降级手填——**不以 Fake 充数**，Fake 结果不可信，宁降级不造假）；
/// - 仅 AI → [VisionLlmDishAdapter]；
/// - 全缺省 → [FakeDishAdapter.fixed()]（确定性离线桩，默认 mock）。
///
/// 注意：`String.fromEnvironment` 是编译期常量，运行期/测试不可改写；
/// 工厂参数缺省回落到常量，测试以显式参数注入覆盖（运行期行为与
/// dart-define 注入后等价，见 test/photo_factory_test.dart）。
library;

import '../cache/ai_parse_cache.dart';
import '../fake/fake_dish_adapter.dart';
import '../llm/llm_adapter.dart';
import '../llm/openai_adapter.dart';
import '../photo/baidu_dish_adapter.dart';
import '../photo/image_compressor.dart';
import '../photo/photo_models.dart';
import '../photo/photo_parser.dart';
import '../photo/vision_dish_adapter.dart';

/// dart-define 键名（W11-12 任务口径：SLIMCA_BAIDU_* / SLIMCA_AI_*）。
const String kSlimcaBaiduAccessTokenDefine = 'SLIMCA_BAIDU_ACCESS_TOKEN';
const String kSlimcaBaiduApiKeyDefine = 'SLIMCA_BAIDU_API_KEY';
const String kSlimcaBaiduSecretKeyDefine = 'SLIMCA_BAIDU_SECRET_KEY';
const String kSlimcaAiBaseDefine = 'SLIMCA_AI_BASE';
const String kSlimcaAiKeyDefine = 'SLIMCA_AI_KEY';
const String kSlimcaAiModelDefine = 'SLIMCA_AI_MODEL';

/// dart-define 读取（§7.1 adapter 可插拔；未注入时为空串）。
const String kSlimcaBaiduAccessToken =
    String.fromEnvironment(kSlimcaBaiduAccessTokenDefine);
const String kSlimcaBaiduApiKey =
    String.fromEnvironment(kSlimcaBaiduApiKeyDefine);
const String kSlimcaBaiduSecretKey =
    String.fromEnvironment(kSlimcaBaiduSecretKeyDefine);
const String kSlimcaAiBase = String.fromEnvironment(kSlimcaAiBaseDefine);
const String kSlimcaAiKey = String.fromEnvironment(kSlimcaAiKeyDefine);
const String kSlimcaAiModel = String.fromEnvironment(kSlimcaAiModelDefine);

/// Vision 兜底缺省端点/模型（§7.5 预设：Qwen-VL DashScope 兼容模式——
/// 国内已备案、按图计价；GLM-4V 由 SLIMCA_AI_BASE/MODEL 注入切换）。
const String kDefaultVisionBaseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
const String kDefaultVisionModel = 'qwen-vl-plus';

/// §7.4 拍照通道超时口径（照片 12s；百度先行侧内部分配 10s，先败先切）。
const Duration kPhotoBaiduTimeout = Duration(seconds: 10);
const Duration kPhotoVisionTimeout = Duration(seconds: 12);

/// 装配拍照解析器（W11-12 任务第 5 项）。
///
/// [cache] 缺省内存实现（进程内 memo）；宿主生产装配注入
/// `DriftAiParseCache(appDatabase)`（§5.6⑭ 持久留痕与 7 天缓存）。
/// [compressor] 缺省纯 Dart 实现（§3.3 口径）；宿主可换平台通道实现。
/// [refLookup] 缺省透传（联查快表接入后由宿主注入，§7.1 第 6 步）。
PhotoParser createPhotoParser({
  String? baiduAccessToken,
  String? baiduApiKey,
  String? baiduSecretKey,
  String? aiBaseUrl,
  String? aiApiKey,
  String? aiModel,
  BaiduDishConfig? baiduConfig,
  ImageDishAdapter? visionAdapter,
  AiParseCache? cache,
  ImageCompressor? compressor,
}) {
  final providers = <ImageDishAdapter>[];

  // 先行侧：百度菜品识别（§7.4；凭据=显式参数 > dart-define 常量）。
  final resolvedToken = (baiduAccessToken ?? kSlimcaBaiduAccessToken).trim();
  final resolvedApiKey = (baiduApiKey ?? kSlimcaBaiduApiKey).trim();
  final resolvedSecretKey = (baiduSecretKey ?? kSlimcaBaiduSecretKey).trim();
  final hasBaiduCredentials = resolvedToken.isNotEmpty ||
      (resolvedApiKey.isNotEmpty && resolvedSecretKey.isNotEmpty);
  if (baiduConfig != null) {
    providers.add(BaiduDishAdapter(baiduConfig));
  } else if (hasBaiduCredentials) {
    providers.add(BaiduDishAdapter(BaiduDishConfig(
      accessToken: resolvedToken,
      apiKey: resolvedApiKey,
      secretKey: resolvedSecretKey,
      timeout: kPhotoBaiduTimeout,
    )));
  }

  // 兜底侧：Vision LLM（复用 OpenAI 兼容适配器 vision 能力，§7.5 预设；
  // [visionAdapter] 亦可注入任意 ImageDishAdapter 定制兜底，测试/灰度用）。
  if (visionAdapter != null) {
    providers.add(visionAdapter);
  } else {
    final resolvedAiKey = (aiApiKey ?? kSlimcaAiKey).trim();
    if (resolvedAiKey.isNotEmpty) {
      final base = (aiBaseUrl ?? kSlimcaAiBase).trim();
      final model = (aiModel ?? kSlimcaAiModel).trim();
      providers.add(VisionLlmDishAdapter(
        adapter: OpenAiCompatibleAdapter(OpenAiCompatibleConfig(
          baseUrl: base.isEmpty ? kDefaultVisionBaseUrl : base,
          apiKey: resolvedAiKey,
          model: model.isEmpty ? kDefaultVisionModel : model,
          // 兼容端点对 json_schema 信封支持参差 → 宽档 + 校验器兜底（§7.2）。
          jsonCapability: LlmJsonCapability.jsonObject,
          timeout: kPhotoVisionTimeout,
        )),
        timeout: kPhotoVisionTimeout,
      ));
    }
  }

  // 全缺省：确定性离线桩（默认 mock，§11.2 W11-12「缺省 Fake」）。
  if (providers.isEmpty) {
    providers.add(FakeDishAdapter.fixed());
  }

  return PhotoParser(
    providers: providers,
    compressor: compressor ?? const PureDartImageCompressor(),
    cache: cache ?? InMemoryAiParseCache(),
  );
}
