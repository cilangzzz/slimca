/// createPhotoParser 装配工厂测试（W11-12 任务第 5 项：SLIMCA_BAIDU_* /
/// SLIMCA_AI_* dart-define 注入口径、缺省 Fake、百度先行顺序、宁降级不造假）。
///
/// `String.fromEnvironment` 是编译期常量，测试进程未注入时恒空串——本文件
/// 以显式参数注入覆盖（运行期与 dart-define 注入后行为等价，见工厂 doc）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';

import 'photo_test_support.dart';

void main() {
  group('缺省装配（无任何凭据 → 确定性 Fake，§11.2「缺省 Fake」）', () {
    test('全缺省 → 单 FakeDishAdapter + 纯 Dart 压缩 + 内存缓存', () {
      final parser = createPhotoParser();

      expect(parser.providers, hasLength(1));
      expect(parser.providers.single.providerId, 'fake_dish');
      expect(parser.compressor, isA<PureDartImageCompressor>(),
          reason: '缺省压缩机=纯 Dart 实现（§3.3，无平台通道）');
      expect(parser.cache, isA<InMemoryAiParseCache>(),
          reason: '缺省缓存=进程内 memo；生产宿主注入 DriftAiParseCache');
    });

    test('缺省 Fake 产出固定候选（离线管线可复现）', () async {
      final parser = createPhotoParser();
      final adapter = parser.providers.single as FakeDishAdapter;
      final dishes = await adapter.recognize(CompressedImage(
        bytes: makeJpegFixture(width: 8, height: 8),
        mime: 'image/jpeg',
        widthPx: 8,
        heightPx: 8,
      ));
      expect(dishes.map((d) => d.name).toList(), ['宫保鸡丁', '米饭']);
    });
  });

  group('凭据注入（§7.4 百度先行 → Vision 兜底）', () {
    test('仅百度 access_token → 单 BaiduDishAdapter（兜底缺位，不以 Fake 充数）',
        () {
      final parser = createPhotoParser(baiduAccessToken: 'tok-1');

      expect(parser.providers, hasLength(1));
      expect(parser.providers.single, isA<BaiduDishAdapter>());
      expect(parser.providers.single.providerId, 'baidu_dish');
    });

    test('仅百度 AK/SK → 单 BaiduDishAdapter（OAuth2 在线换 token 形态）', () {
      final parser =
          createPhotoParser(baiduApiKey: 'ak-1', baiduSecretKey: 'sk-1');

      expect(parser.providers, hasLength(1));
      expect(parser.providers.single, isA<BaiduDishAdapter>());
    });

    test('仅 AI Key → 单 VisionLlmDishAdapter（缺省 Qwen-VL DashScope 预设）',
        () {
      final parser = createPhotoParser(aiApiKey: 'sk-ai-1');

      expect(parser.providers, hasLength(1));
      expect(parser.providers.single.providerId, 'openai_compatible');
      expect(parser.providers.single.modelId, kDefaultVisionModel,
          reason: 'SLIMCA_AI_MODEL 未注入 → §7.5 预设 qwen-vl-plus');
    });

    test('AI Key + 自定义 base/model → 透传（GLM-4V 等切换口径）', () {
      final parser = createPhotoParser(
        aiBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
        aiApiKey: 'sk-ai-2',
        aiModel: 'glm-4v-plus',
      );

      expect(parser.providers.single.providerId, 'openai_compatible');
      expect(parser.providers.single.modelId, 'glm-4v-plus');
    });

    test('双配 → 2 供应商且百度先行（§7.4 第 4 级装配顺序）', () {
      final parser = createPhotoParser(
        baiduAccessToken: 'tok-1',
        aiApiKey: 'sk-ai-1',
      );

      expect(parser.providers, hasLength(2));
      expect(parser.providers[0], isA<BaiduDishAdapter>(),
          reason: '百度菜品识别先行（§3.3：快、便宜）');
      expect(parser.providers[1], isA<VisionLlmDishAdapter>(),
          reason: 'Vision LLM 兜底（§7.4）');
    });

    test('visionAdapter 显式注入 → 追加在百度之后（宿主定制兜底可替换）', () {
      final customVision = FakeDishAdapter.fixed(providerId: 'custom_vision');
      // 工厂兜底位收任意 ImageDishAdapter（VisionLlmDishAdapter 之外亦可，
      // 测试/灰度切换供应商用）。
      final parser = createPhotoParser(
        baiduAccessToken: 'tok-1',
        visionAdapter: customVision,
      );

      expect(parser.providers, hasLength(2));
      expect(parser.providers[0], isA<BaiduDishAdapter>());
      expect(parser.providers[1], same(customVision));
      expect(parser.providers[1].providerId, 'custom_vision');
    });

    test('baiduConfig 显式配置优先于散装凭据参数（配置对象整体生效）', () {
      // baiduConfig 缺凭据 + 散装参数给了 token：若散装参数仍生效，工厂会
      // 以散装凭据构造成功；配置对象整体生效则构造出空凭据 adapter →
      // ArgumentError（fail-fast，装配期显式暴露）。
      expect(
        () => createPhotoParser(
          baiduConfig: const BaiduDishConfig(
            accessToken: '',
            apiKey: '',
            secretKey: '',
          ),
          baiduAccessToken: 'tok-param',
        ),
        throwsArgumentError,
      );
    });
  });

  group('超时口径（§3.3：照片 12s；百度先行侧先败先切）', () {
    test('kPhotoBaiduTimeout=10s / kPhotoVisionTimeout=12s 与文档一字不差', () {
      expect(kPhotoBaiduTimeout, const Duration(seconds: 10));
      expect(kPhotoVisionTimeout, const Duration(seconds: 12));
    });
  });
}
