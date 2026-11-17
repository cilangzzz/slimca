/// 确定性脚本化小票 OCR 假适配器（W16 任务「FakeAdapter（fixture）」；测试
/// 专用与缺省离线桩——任务硬规则：测试禁止真实平台通道，用 Fake）。
///
/// 三种形态（与 FakeDishAdapter 同风格）：
/// - [FakeReceiptOcrAdapter.scripted]：按调用次序依次弹出脚本项
///   （[ReceiptDraft] 或 [LlmException]）；
/// - [FakeReceiptOcrAdapter.fixed]：恒返回固定 fixture 草稿（缺省装配的
///   「默认 mock」——未接线 native handler 时端侧路径离线可用，确认卡有
///   真数据可改，§2.4-3）；
/// - [FakeReceiptOcrAdapter.fromTextLines]：fixture 文本行经共享字段抽取器
///   （extractReceiptFields）生成草稿——字段理解逻辑走真实路径（冒烟口径）。
///
/// [images] 记录每次收到的原图输入（即用即焚断言用）；零延迟零网络零时钟
/// ——测试完全离线且确定。
library;

import '../llm/llm_adapter.dart';
import '../receipt/receipt_field_extractor.dart';
import '../receipt/receipt_models.dart';
import '../receipt/receipt_ocr_adapter.dart';

/// 缺省 fixture 草稿（缺省装配默认 mock；便利店小票：合计 12.50 元、两行
/// 明细、带时间。rawText 含一行会员噪声「扫码积分送好礼」——作为「OCR 全文
/// 不进结构化文本/不上云」断言的锚点行）。
const ReceiptDraft kDefaultReceiptDraft = ReceiptDraft(
  merchant: '全家便利店',
  totalMinor: 1250,
  datetime: ReceiptDateTime(day: '2026-03-05', time: '12:31'),
  lineItems: <ReceiptLineItem>[
    ReceiptLineItem(name: '可乐', amountMinor: 350, quantity: 1),
    ReceiptLineItem(name: '饭团', amountMinor: 900),
  ],
  rawText: '全家便利店\n2026-03-05 12:31\n扫码积分送好礼\n可乐 x1 3.50\n'
      '饭团 9.00\n实收 12.50',
);

class FakeReceiptOcrAdapter implements ReceiptOcrAdapter {
  FakeReceiptOcrAdapter._({
    required Object Function(int callIndex) next,
    this.providerId = 'fake_receipt_ocr',
    this.modelId = 'fake-receipt-ocr-v1',
  }) : _next = next;

  /// 顺序脚本工厂：脚本项为 [ReceiptDraft]（该次草稿）或 [LlmException]
  /// （该次抛出的分类异常）。
  ///
  /// 脚本耗尽即抛 StateError（测试脚本不足应显式暴露，而非静默重复）。
  factory FakeReceiptOcrAdapter.scripted(
    List<Object> script, {
    String providerId = 'fake_receipt_ocr',
    String modelId = 'fake-receipt-ocr-v1',
  }) {
    final items = List<Object>.unmodifiable(script);
    return FakeReceiptOcrAdapter._(
      next: (callIndex) {
        if (callIndex >= items.length) {
          throw StateError(
            'FakeReceiptOcrAdapter 脚本耗尽（第 $callIndex 次调用，脚本共 '
            '${items.length} 项）——测试脚本与预期调用次数不符',
          );
        }
        return items[callIndex];
      },
      providerId: providerId,
      modelId: modelId,
    );
  }

  /// 固定草稿工厂（缺省装配默认 mock；fixture 草稿可覆写）。
  factory FakeReceiptOcrAdapter.fixed({
    ReceiptDraft? draft,
    String providerId = 'fake_receipt_ocr',
    String modelId = 'fake-receipt-ocr-v1',
  }) =>
      FakeReceiptOcrAdapter.scripted(
        <Object>[draft ?? kDefaultReceiptDraft],
        providerId: providerId,
        modelId: modelId,
      );

  /// fixture 文本行工厂：经共享抽取器生成草稿（字段理解逻辑的真实路径；
  /// 骨架通道适配器行为同构——通道回文本行、extractReceiptFields 理解）。
  factory FakeReceiptOcrAdapter.fromTextLines(
    List<String> textLines, {
    String providerId = 'fake_receipt_ocr',
    String modelId = 'fake-receipt-ocr-v1',
  }) =>
      FakeReceiptOcrAdapter.scripted(
        <Object>[extractReceiptFields(textLines)],
        providerId: providerId,
        modelId: modelId,
      );

  /// 恒定重复工厂（缓存回放等多次识别同一小票的场景；草稿可覆写）。
  factory FakeReceiptOcrAdapter.repeating({
    ReceiptDraft? draft,
    String providerId = 'fake_receipt_ocr',
    String modelId = 'fake-receipt-ocr-v1',
  }) {
    final fixed = draft ?? kDefaultReceiptDraft;
    return FakeReceiptOcrAdapter._(
      next: (_) => fixed,
      providerId: providerId,
      modelId: modelId,
    );
  }

  final Object Function(int callIndex) _next;

  @override
  final String providerId;

  @override
  final String modelId;

  /// 收到的原图日志（按调用序；即用即焚/输入口径断言用）。
  final List<ReceiptImageInput> images = <ReceiptImageInput>[];

  int _callIndex = 0;

  @override
  Future<ReceiptDraft> recognize(ReceiptImageInput image) async {
    images.add(image);
    final item = _next(_callIndex++);
    if (item is LlmException) {
      throw item;
    }
    if (item is ReceiptDraft) {
      return item;
    }
    throw StateError('FakeReceiptOcrAdapter 脚本项必须是 ReceiptDraft 或 '
        'LlmException，实际 ${item.runtimeType}');
  }

  /// 最近一次收到的输入（便捷断言）。
  ReceiptImageInput? get lastImage => images.isEmpty ? null : images.last;
}
