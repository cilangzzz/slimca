/// 确定性启发式假 LLM adapter（§11.1 W3-4「缺省 Fake」的管线内实现）。
///
/// 与 [FakeLlmAdapter]（脚本桩）不同：本实现可解析**任意**输入——用极简
/// 正则从文本中抽取热量/金额，产出 §7.2 受约束 JSON。装配进 [LlmAiParser]
/// 后走完整管线（规范化 → input_hash 缓存 → 受约束解码 → 校验/映射 →
/// 重试），与真实 adapter 行为同构，只是「模型」换成确定性规则——缺省
/// 装配（未配 API key）因此能离线跑通 AI 双解析闭环。
///
/// 确定性纪律（测试可用）：同一输入恒产同一输出；无随机、无时钟、无网络。
/// 抽取规则（原壳层 FakeParser 同款，§2.3 步 3「只求确认卡有真数据可改」）：
/// - 热量：首个 `(\d{1,5})\s*(?:kcal|大卡|卡路里|卡)`，越界 [0,5000] 不产出；
/// - 金额：首个 `花(了)?\s*N` / `N\s*(元|块)`（N 最多两位小数，元→分）。
/// 无任何抽取 → lines 为空 → 校验器 emptyResult → 管线 StructuredFailure
/// → 宿主降级手填（§7.4，与真实模型「解析不出」路径一致）。
library;

import 'dart:convert';

import '../llm/llm_adapter.dart';

class HeuristicFakeLlmAdapter implements LlmAdapter {
  const HeuristicFakeLlmAdapter();

  static const String _kParseNotes =
      'FakeParser（默认 mock）规则抽取：真实 adapter 待 API key 配置后'
      '经 --dart-define=SLIMCA_AI_BASE/KEY/MODEL 切换';

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'fake-deterministic-v1';

  @override
  LlmJsonCapability get jsonCapability => LlmJsonCapability.jsonSchema;

  @override
  Future<LlmResponse> complete(LlmRequest request) async {
    // 第一条 user 消息 = 规范化输入（纠错回喂消息在后，不参与抽取）。
    String? input;
    for (final message in request.messages) {
      if (message.role == LlmRole.user) {
        input = message.content;
        break;
      }
    }
    final text = input ?? '';
    final kcal = _firstKcal(text);
    final amountMinor = _firstMoneyMinor(text);
    final lines = <Map<String, Object?>>[
      if (kcal != null)
        <String, Object?>{
          'type': 'calorie',
          'amount_kcal': kcal,
          'confidence': 0.62,
          'category_hint': '餐饮-正餐',
          'items': <Object?>[],
        },
      if (amountMinor != null)
        <String, Object?>{
          'type': 'money',
          'amount_minor': amountMinor,
          'income': false,
          'currency': 'CNY',
          'confidence': 0.93,
          'ledger_hint': 'default',
          'category_hint': '餐饮-正餐',
          'merchant': null,
        },
    ];
    return LlmResponse(
      content: jsonEncode(<String, Object?>{
        'title': text,
        'kind': _kind(lines),
        'parse_notes': _kParseNotes,
        'lines': lines,
      }),
      provider: providerId,
      model: modelId,
      latencyMs: 0,
      promptTokens: 0,
      completionTokens: 0,
      costMicro: 0,
      finishReason: 'stop',
    );
  }

  /// 按产出行推导 kind（§5.2①：钱+热量=mixed；仅热量=food；仅钱=expense；
  /// 空=note——空行会在校验器以 emptyResult 失败，kind 仅占位）。
  static String _kind(List<Map<String, Object?>> lines) {
    final hasKcal = lines.any((l) => l['type'] == 'calorie');
    final hasMoney = lines.any((l) => l['type'] == 'money');
    if (hasKcal && hasMoney) return 'mixed';
    if (hasKcal) return 'food';
    if (hasMoney) return 'expense';
    return 'note';
  }

  /// 热量抽取；越界 [0,5000] 不产出行（与 §7.1 校验器自洽）。
  static int? _firstKcal(String input) {
    final match = RegExp(
      r'(\d{1,5})\s*(?:kcal|大卡|卡路里|卡)',
      caseSensitive: false,
    ).firstMatch(input);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    if (value == null || value < 0 || value > 5000) return null;
    return value;
  }

  /// 金额抽取（元 → 分，§5.1）；非法/非正不产出行。
  static int? _firstMoneyMinor(String input) {
    final match = RegExp(
      r'(?:花(?:了)?|消费|支付)\s*([0-9]+(?:\.[0-9]{1,2})?)'
      r'|([0-9]+(?:\.[0-9]{1,2})?)\s*(?:元|块)',
    ).firstMatch(input);
    final raw = match?.group(1) ?? match?.group(2);
    if (raw == null) return null;
    final minor = _yuanToFen(raw);
    if (minor == null || minor <= 0) return null;
    return minor;
  }

  /// 元文本 → 分（两位小数上限，杜绝浮点，§5.1；与壳层 parseYuanToFen 同构
  /// ——core_ai 不依赖壳层，此处内联同口径实现）。
  static int? _yuanToFen(String raw) {
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(raw);
    if (m == null) return null;
    final yuan = int.parse(m.group(1)!);
    final frac = m.group(2) ?? '';
    final fen = frac.isEmpty
        ? 0
        : (frac.length == 1 ? int.parse(frac) * 10 : int.parse(frac));
    return yuan * 100 + fen;
  }
}
