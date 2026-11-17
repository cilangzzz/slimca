/// 确定性脚本化菜品识别假适配器（测试专用与缺省离线桩——任务硬规则：
/// 测试一律注入 Fake/Mock 识别器，禁止真实网络与相机调用）。
///
/// 两种形态（与 FakeLlmAdapter 同风格）：
/// - [FakeDishAdapter.scripted]：按调用次序依次弹出脚本项；脚本项为
///   `List<DishCandidate>`（该次候选清单，空清单=未识别到菜品）或
///   [LlmException]（该次抛出的分类异常）；
/// - [FakeDishAdapter.fixed]：恒返回固定候选（缺省装配的「默认 mock」
///   ——未配任何真实供应商凭据时，拍照管线离线产出确定性草稿，确认卡有
///   真数据可改，§2.4-3「只求确认卡有真数据可改」）。
///
/// [images] 记录每次收到的压缩规范形（断言输入口径与即用即焚用）；响应
/// 零延迟、零网络、零时钟——测试完全离线且确定。
library;

import '../llm/llm_adapter.dart';
import '../parse/parse_models.dart' show FoodRefSource;
import '../photo/photo_models.dart';

class FakeDishAdapter implements ImageDishAdapter {
  FakeDishAdapter._({
    required Object Function(int callIndex) next,
    this.providerId = 'fake_dish',
    this.modelId = 'fake-dish-model',
    this.dishRefSource = FoodRefSource.llm,
  }) : _next = next;

  /// 顺序脚本工厂：脚本项为 `List<DishCandidate>` 或 [LlmException]。
  ///
  /// 脚本耗尽即抛 StateError（测试脚本不足应显式暴露，而非静默重复）。
  factory FakeDishAdapter.scripted(
    List<Object> script, {
    String providerId = 'fake_dish',
    String modelId = 'fake-dish-model',
    FoodRefSource dishRefSource = FoodRefSource.llm,
  }) {
    final items = List<Object>.unmodifiable(script);
    return FakeDishAdapter._(
      next: (callIndex) {
        if (callIndex >= items.length) {
          throw StateError(
            'FakeDishAdapter 脚本耗尽（第 $callIndex 次调用，脚本共 '
            '${items.length} 项）——测试脚本与预期调用次数不符',
          );
        }
        return items[callIndex];
      },
      providerId: providerId,
      modelId: modelId,
      dishRefSource: dishRefSource,
    );
  }

  /// 固定候选工厂（缺省装配默认 mock；候选可覆写，缺省两道常见菜品）。
  factory FakeDishAdapter.fixed({
    List<DishCandidate>? dishes,
    String providerId = 'fake_dish',
    String modelId = 'fake-dish-model',
  }) {
    final fixed = dishes ?? const <DishCandidate>[
      DishCandidate(
        name: '宫保鸡丁',
        grams: 250,
        confidence: 0.62,
        categoryHint: '餐饮-正餐',
      ),
      DishCandidate(
        name: '米饭',
        grams: 200,
        confidence: 0.85,
        categoryHint: '餐饮-正餐',
      ),
    ];
    return FakeDishAdapter.scripted(<Object>[fixed],
        providerId: providerId, modelId: modelId);
  }

  final Object Function(int callIndex) _next;

  @override
  final String providerId;

  @override
  final String modelId;

  @override
  final FoodRefSource dishRefSource;

  /// 收到的压缩规范形日志（按调用序；断言输入口径/即用即焚用）。
  final List<CompressedImage> images = <CompressedImage>[];

  int _callIndex = 0;

  @override
  Future<List<DishCandidate>> recognize(CompressedImage image) async {
    images.add(image);
    final index = _callIndex++;
    final item = _next(index);
    if (item is LlmException) {
      throw item;
    }
    if (item is List<DishCandidate>) {
      return item;
    }
    throw StateError('FakeDishAdapter 脚本项必须是 List<DishCandidate> 或 '
        'LlmException，实际 ${item.runtimeType}');
  }

  /// 最近一次收到的输入（便捷断言）。
  CompressedImage? get lastImage => images.isEmpty ? null : images.last;
}
