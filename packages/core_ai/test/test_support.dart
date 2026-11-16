/// core_ai 测试支撑：确定性时钟/序列 id、§7.2 文档示例夹具、输入构造。
///
/// 全部离线：LLM 交互经 FakeLlmAdapter（脚本化响应），缓存经
/// InMemoryAiParseCache；Drift 实现测试仅在宿主具备 sqlite3 运行库时执行
/// （缺库温和跳过，与 core_db 测试同一策略）。
library;

import 'dart:math';

import 'package:core_ai/core_ai.dart';
// UUIDv7 生成（§5.1 id 时间有序）来自 core_db 公开导出。
import 'package:core_db/core_db.dart';

/// 测试基准时刻（UTC ms）——所有缓存时效断言以此为「现在」。
const int kBaseMs = 1763251200000;

/// 测试锚定日（本地日历日，§5.1）。
const String kTestDate = '2026-11-30';

/// §7.2 文档示例原样夹具（用户输入「中午吃了兰州拉面花了 18」的受约束
/// 输出）。字段断言以此为准：amount_minor=1800（分）、amount_kcal=550、
/// 置信度 0.93/0.62、category_hint=餐饮-面食（内置名单未命中 → 建议新建）。
const String kLanzhouParseJson = '''
{
  "title": "兰州拉面",
  "kind": "mixed",
  "lines": [
    { "type": "calorie", "amount_kcal": 550, "confidence": 0.62,
      "items": [{ "name": "牛肉拉面", "portion_g": 450, "kcal": 500,
                  "protein_g": 25, "carb_g": 65, "fat_g": 12, "ref_source": "local" }],
      "category_hint": "餐饮-面食" },
    { "type": "money", "amount_minor": 1800, "currency": "CNY", "confidence": 0.93,
      "ledger_hint": "default", "category_hint": "餐饮-面食", "merchant": null }
  ],
  "parse_notes": "份量按中碗估计；金额来自文本「18」"
}
''';

/// 与夹具对应的用户输入原文。
const String kLanzhouInputText = '中午吃了兰州拉面花了 18';

/// 构造解析输入（both 模式可覆写）。
ParseInput makeParseInput({
  String rawText = kLanzhouInputText,
  ParseMode mode = ParseMode.both,
  String date = kTestDate,
  AiInputKind kind = AiInputKind.text,
}) =>
    ParseInput(
      rawText: rawText,
      context: ParseContext(date: date, mode: mode),
      kind: kind,
    );

/// 确定性时钟（恒 [kBaseMs]）。
int fakeNowMs() => kBaseMs;

/// 递增序列 id 生成器：第 n 枚 id（n 从 0 起）内嵌时间 = base + n——
/// 首枚恰为「现在」（isFreshAt 年龄=0 → 新鲜，§5.6⑭ 时效判定可测），
/// 后续每枚 +1ms；缓存时效测试可另传 baseMs 构造任意年龄的记录。
String Function() makeIdSeq({int baseMs = kBaseMs}) {
  var n = 0;
  final rng = Random(7);
  return () => generateUuidV7(timestampMs: baseMs + (n++), random: rng);
}
