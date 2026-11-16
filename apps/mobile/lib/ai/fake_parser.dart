/// 默认解析器 FakeParser：确定性离线 mock（§11.1 W3-4「默认 FakeParser」）。
///
/// **真实 adapter 待 API key 配置后经
/// `--dart-define=SLIMCA_AI_BASE` / `--dart-define=SLIMCA_AI_KEY` /
/// `--dart-define=SLIMCA_AI_MODEL` 切换**（读取逻辑已写在
/// lib/ai/ai_parser_factory.dart，缺省一律装配本 mock——开发与测试
/// 零真实网络调用）。
///
/// 确定性纪律（测试可用）：同一输入恒产同一结果；无随机、无时钟、无网络。
/// 抽取规则是极简正则（只求确认卡有真数据可改，§2.3 步 3）：
/// - 热量：首个 `(\d{1,5})\s*(?:kcal|大卡|卡路里|卡)`；
/// - 金额：首个 `花(了)?\s*N` / `N\s*(元|块)`（N 最多两位小数）。
library;

import 'ai_parser.dart';

import '../common/format.dart';

/// 默认解析器（无 dart-define 配置时的装配缺省，§11.1 W3-4）。
class FakeParser implements AiParser {
  const FakeParser();

  static const String _provider = 'fake';
  static const String _model = 'fake-deterministic-v1';
  static const String _promptVersion = 'fake-v1';

  @override
  Future<AiParseResult> parse(AiParseRequest request) async {
    final input = request.input;
    final kcal = _firstKcal(input);
    final amountMinor = _firstMoneyMinor(input);

    // 行级置信度取 §7.2 示例同款确定性值（.62/.93 → 黄/绿三色点各现一次，
    // 确认卡三档色点可视化口径一致）。
    final lines = <AiParsedLine>[
      if (kcal != null)
        AiParsedLine(
          type: AiLineType.calorie,
          amount: kcal,
          confidence: 0.62,
          categoryHint: '餐饮',
          items: const [],
        ),
      if (amountMinor != null)
        AiParsedLine(
          type: AiLineType.money,
          amount: amountMinor,
          currency: 'CNY',
          confidence: 0.93,
          ledgerHint: 'default',
        ),
    ];

    // 整体置信度 = 行置信度最小值（与 AiParseResult.fromJson 兜底口径一致）。
    var overall = 1.0;
    for (final line in lines) {
      if (line.confidence < overall) overall = line.confidence;
    }

    return AiParseResult(
      title: input,
      kindHint: _kindHint(lines),
      lines: lines,
      parseNotes:
          'FakeParser（默认 mock）规则抽取：真实 adapter 待 API key 配置后'
          '经 --dart-define=SLIMCA_AI_BASE/KEY/MODEL 切换',
      confidence: overall,
      provider: _provider,
      model: _model,
      promptVersion: _promptVersion,
      latencyMs: 0,
      costMicro: 0,
    );
  }

  String _kindHint(List<AiParsedLine> lines) {
    final hasKcal = lines.any((l) => l.type == AiLineType.calorie);
    final hasMoney = lines.any((l) => l.type == AiLineType.money);
    if (hasKcal && hasMoney) return 'mixed';
    if (hasKcal) return 'food';
    if (hasMoney) return 'expense';
    return 'note';
  }

  /// 热量抽取；越界 [0,5000] 不产出行（保持与 §7.1 校验器自洽）。
  int? _firstKcal(String input) {
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
  int? _firstMoneyMinor(String input) {
    final match = RegExp(
      r'(?:花(?:了)?|消费|支付)\s*([0-9]+(?:\.[0-9]{1,2})?)'
      r'|([0-9]+(?:\.[0-9]{1,2})?)\s*(?:元|块)',
    ).firstMatch(input);
    final raw = match?.group(1) ?? match?.group(2);
    if (raw == null) return null;
    final minor = parseYuanToFen(raw);
    if (minor == null || minor <= 0) return null;
    return minor;
  }
}
