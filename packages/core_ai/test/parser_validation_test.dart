/// 受约束 JSON 校验与 §7.3 字段映射测试（§7.1 校验器硬闸门）。
///
/// 覆盖任务口径：缺字段/类型错/金额单位分/分类映射/单边过滤/围栏提取/
/// kcal 边界/置信度必填。全部离线（直接调 validateAndMap，不经网络）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// 构造一个只含金额行的输出 JSON。
String moneyOnlyJson({
  required int amountMinor,
  double confidence = 0.9,
  Object? income,
  String? categoryHint,
  bool omitConfidence = false,
}) {
  final buffer = StringBuffer()
    ..write('{"title":"买书","kind":"expense","lines":[{"type":"money"')
    ..write(',"amount_minor":$amountMinor');
  if (!omitConfidence) {
    buffer.write(',"confidence":$confidence');
  }
  if (income != null) {
    // 字符串值需加引号（测试构造合法 JSON，让校验器报「必须为布尔」）。
    final incomeJson = income is String ? '"$income"' : income;
    buffer.write(',"income":$incomeJson');
  }
  if (categoryHint != null) {
    buffer.write(',"category_hint":"$categoryHint"');
  }
  buffer.write('}]}');
  return buffer.toString();
}

/// 校验并断言抛出 [AiValidationException]，返回错误清单。
List<String> expectErrors(String raw, {ParseMode mode = ParseMode.both}) {
  try {
    validateAndMap(
      rawOutput: raw,
      mode: mode,
      categoryResolver: const PresetCategoryResolver(),
    );
    fail('预期校验失败，实际通过：$raw');
  } on AiValidationException catch (error) {
    expect(error.errors, isNotEmpty);
    expect(error.rawOutput, raw);
    return error.errors;
  }
}

void main() {
  group('§7.2 文档示例：全字段映射（§7.3 字段映射表）', () {
    late ValidatedParse parsed;

    setUp(() {
      parsed = validateAndMap(
        rawOutput: kLanzhouParseJson,
        mode: ParseMode.both,
        categoryResolver: const PresetCategoryResolver(),
      );
    });

    test('title/kind/parse_notes 主干映射', () {
      expect(parsed.title, '兰州拉面');
      expect(parsed.kind, dom.EntryKind.mixed, reason: '钱+热量 → mixed（§5.2①）');
      expect(parsed.parseNotes, '份量按中碗估计；金额来自文本「18」');
      // 「餐饮-面食」不在内置名单（名单只有 早餐/正餐/外卖 三档）→ 每行一条
      // 未命中 note（§7.3：挂「其他」并建议新建）。
      expect(parsed.notes, hasLength(2));
      expect(parsed.notes.first, contains('未命中内置分类'));
      expect(parsed.notes.first, contains('餐饮-面食'));
    });

    test('热量行：kcal 整数、direction=in、置信度三档、菜品明细继承行级置信度', () {
      final calorie = parsed.lines
          .singleWhere((l) => l.type == dom.LineType.calorie);
      expect(calorie.amount, 550, reason: '§7.3：lines[].type=calorie → amount=kcal');
      expect(calorie.direction, dom.LineDirection.income,
          reason: '§5.2②：calorie 行 direction 恒为 in');
      expect(calorie.confidence, 0.62);
      expect(calorie.band, ConfidenceBand.yellow, reason: '0.5-0.8 → 黄（§7.3）');
      expect(calorie.categoryHint, '餐饮-面食');

      expect(calorie.items, hasLength(1));
      final item = calorie.items.single;
      expect(item.name, '牛肉拉面');
      expect(item.portionG, 450);
      expect(item.kcal, 500);
      expect(item.proteinG, 25);
      expect(item.carbG, 65);
      expect(item.fatG, 12);
      expect(item.refSource, FoodRefSource.local, reason: '§5.2③ ref_source 透传');
      // §7.2 示例菜品级无 confidence → 继承行级（§5.2③ NOT NULL）。
      expect(item.confidence, 0.62);
    });

    test('金额行：单位=分、direction=out、币种/账本提示/payload', () {
      final money =
          parsed.lines.singleWhere((l) => l.type == dom.LineType.money);
      expect(money.amount, 1800, reason: '§5.1：金额一律最小货币单位「分」，18 元 → 1800');
      expect(money.direction, dom.LineDirection.outcome,
          reason: 'income 缺省支出 → out（§5.2②）');
      expect(money.currency, 'CNY');
      expect(money.ledgerHint, 'default');
      expect(money.confidence, 0.93);
      expect(money.band, ConfidenceBand.green, reason: '≥0.8 → 绿（§7.3）');
      expect(money.payload, {'ledger_hint': 'default'},
          reason: 'merchant=null 被剔除，§5.2② payload 行级明细');
    });

    test('category_hint「餐饮-面食」未命中内置名单 → 挂其他+建议新建（§7.3）', () {
      for (final line in parsed.lines) {
        expect(line.categoryId, isNull,
            reason: '缺省解析器无 id 映射：id 由宿主从 categories 表装载');
        expect(line.categorySuggestNew, isTrue,
            reason: '§7.3：未命中挂「其他」并建议新建');
      }
    });
  });

  group('分类映射（§7.3 category_hint → category_id）', () {
    test('命中内置分类（缺省名单）', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 1200, categoryHint: '餐饮-正餐'),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.categorySuggestNew, isFalse);
      expect(parsed.lines.single.categoryHint, '餐饮-正餐');
    });

    test('命中且宿主注入 name→id 映射 → categoryId 回填', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 1200, categoryHint: '交通'),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(
          nameToId: {'交通': 'cat-traffic'},
          fallbackCategoryId: 'cat-other',
        ),
      );
      final line = parsed.lines.single;
      expect(line.categoryId, 'cat-traffic');
      expect(line.categorySuggestNew, isFalse);
    });

    test('未命中 → 挂靠 fallbackCategoryId（「其他」）并建议新建', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 1200, categoryHint: ' 停车费 '),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(
          fallbackCategoryId: 'cat-other',
        ),
      );
      final line = parsed.lines.single;
      expect(line.categoryId, 'cat-other');
      expect(line.categorySuggestNew, isTrue);
      expect(line.categoryHint, '停车费');
    });

    test('别名归一（宿主注入 aliases）', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 3000, categoryHint: '吃饭'),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(
          nameToId: {'餐饮-正餐': 'cat-meal'},
          aliases: {'吃饭': '餐饮-正餐'},
        ),
      );
      expect(parsed.lines.single.categoryId, 'cat-meal');
      expect(parsed.lines.single.categoryHint, '餐饮-正餐');
    });

    test('category_hint 缺失 → 无分类建议（不误挂）', () {
      final parsed = validateAndMap(
        rawOutput: '{"title":"转账","kind":"expense","lines":'
            '[{"type":"money","amount_minor":500,"confidence":0.99}]}',
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(
          fallbackCategoryId: 'cat-other',
        ),
      );
      expect(parsed.lines.single.categoryId, isNull);
      expect(parsed.lines.single.categorySuggestNew, isFalse);
    });

    test('内置分类名清单覆盖 §3.4 口径（餐饮三档/交通/…/其他收入）', () {
      expect(kDefaultPresetCategoryNames, containsAll(<String>[
        '餐饮-早餐', '餐饮-正餐', '餐饮-外卖', '交通', '购物', '居住', '娱乐',
        '医疗', '教育', '人情', '储蓄', '其他支出', '工资', '其他收入',
      ]));
    });
  });

  group('income/direction 映射（§5.2② money 按 expense=out / income=in）', () {
    test('income=true → direction=in', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 5000, income: true),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.direction, dom.LineDirection.income);
    });

    test('income=false/缺省 → direction=out', () {
      for (final raw in [
        moneyOnlyJson(amountMinor: 5000, income: false),
        moneyOnlyJson(amountMinor: 5000),
      ]) {
        final parsed = validateAndMap(
          rawOutput: raw,
          mode: ParseMode.moneyOnly,
          categoryResolver: const PresetCategoryResolver(),
        );
        expect(parsed.lines.single.direction, dom.LineDirection.outcome);
      }
    });
  });

  group('金额口径：单位分与金额>0（§5.1/§7.1）', () {
    test('amount_minor=18 → 18 分（字面口径，不猜测元换算）', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 18),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.amount, 18);
    });

    test('amount_minor=0 → 拒绝（金额>0）', () {
      final errors = expectErrors(moneyOnlyJson(amountMinor: 0));
      expect(errors.first, contains('金额>0'));
    });

    test('amount_minor=-100 → 拒绝', () {
      final errors = expectErrors(moneyOnlyJson(amountMinor: -100));
      expect(errors.first, contains('金额>0'));
    });

    test('amount_minor=1 → 通过（最小合法分值）', () {
      final parsed = validateAndMap(
        rawOutput: moneyOnlyJson(amountMinor: 1),
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.amount, 1);
    });
  });

  group('缺字段（§7.1 必需字段齐）', () {
    test('缺 title', () {
      final errors = expectErrors('{"kind":"expense","lines":'
          '[{"type":"money","amount_minor":100,"confidence":0.9}]}');
      expect(errors.first, contains('title'));
    });

    test('缺 kind', () {
      final errors = expectErrors('{"title":"x","lines":'
          '[{"type":"money","amount_minor":100,"confidence":0.9}]}');
      expect(errors.first, contains('kind'));
    });

    test('缺 lines', () {
      final errors = expectErrors('{"title":"x","kind":"expense"}');
      expect(errors.first, contains('lines'));
    });

    test('金额行缺 amount_minor', () {
      final errors = expectErrors(
          '{"title":"x","kind":"expense","lines":[{"type":"money","confidence":0.9}]}');
      expect(errors.first, contains('amount_minor'));
    });

    test('缺行级 confidence（§5.2② AI 产出行必填）', () {
      final errors = expectErrors(
          moneyOnlyJson(amountMinor: 100, omitConfidence: true));
      expect(errors.first, contains('confidence'));
    });

    test('calorie 行缺 amount_kcal', () {
      final errors = expectErrors('{"title":"早餐","kind":"food","lines":'
          '[{"type":"calorie","confidence":0.6}]}');
      expect(errors.first, contains('amount_kcal'));
    });

    test('items 缺 portion_g（份量滑杆重算基准）', () {
      final errors = expectErrors('{"title":"早餐","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":300,"confidence":0.6,'
          '"items":[{"name":"包子","kcal":300}]}]}');
      expect(errors.first, contains('portion_g'));
    });
  });

  group('类型错（LLM 输出口径漂移 → 拒绝后重试）', () {
    test('amount_minor 为字符串', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"money","amount_minor":"1800","confidence":0.9}]}');
      expect(errors.first, contains('整数分'));
    });

    test('amount_minor 为小数（1800.5）', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"money","amount_minor":1800.5,"confidence":0.9}]}');
      expect(errors.first, contains('整数分'));
    });

    test('amount_kcal 为小数', () {
      final errors = expectErrors('{"title":"x","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":550.5,"confidence":0.6}]}');
      expect(errors.first, contains('整数'));
    });

    test('confidence 为字符串', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"money","amount_minor":100,"confidence":"0.9"}]}');
      expect(errors.first, contains('confidence'));
    });

    test('confidence 越界 [0,1]', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"money","amount_minor":100,"confidence":1.5}]}');
      expect(errors.first, contains('[0,1]'));
    });

    test('lines 不是数组', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":{}}');
      expect(errors.first, contains('lines'));
    });

    test('行元素不是对象', () {
      final errors = expectErrors(
          '{"title":"x","kind":"expense","lines":["money"]}');
      expect(errors.first, contains('对象'));
    });

    test('type 非法（自由文本行被拒绝，§7.1 拒绝自由文本）', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"payment","amount_minor":100,"confidence":0.9}]}');
      expect(errors.first, contains('type'));
    });

    test('kind 非法枚举', () {
      final errors = expectErrors('{"title":"x","kind":"shopping","lines":'
          '[{"type":"money","amount_minor":100,"confidence":0.9}]}');
      expect(errors.first, contains('kind'));
    });

    test('income 非布尔', () {
      final errors = expectErrors(moneyOnlyJson(amountMinor: 100, income: 'yes'));
      expect(errors.first, contains('income'));
    });

    test('parse_notes 非字符串', () {
      final errors = expectErrors('{"title":"x","kind":"expense","lines":'
          '[{"type":"money","amount_minor":100,"confidence":0.9}],"parse_notes":7}');
      expect(errors.first, contains('parse_notes'));
    });

    test('items 不是数组', () {
      final errors = expectErrors('{"title":"x","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":300,"confidence":0.6,"items":1}]}');
      expect(errors.first, contains('items'));
    });

    test('ref_source 非法（§5.2③ 枚举）', () {
      final errors = expectErrors('{"title":"x","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":300,"confidence":0.6,'
          '"items":[{"name":"包子","portion_g":100,"kcal":300,"ref_source":"magic"}]}]}');
      expect(errors.first, contains('ref_source'));
    });
  });

  group('kcal 边界（§7.1 kcal∈[0,5000]）', () {
    test('0 通过', () {
      final parsed = validateAndMap(
        rawOutput:
            '{"title":"黑咖啡","kind":"food","lines":[{"type":"calorie","amount_kcal":0,"confidence":0.9}]}',
        mode: ParseMode.kcalOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.amount, 0);
    });

    test('5000 通过', () {
      final parsed = validateAndMap(
        rawOutput:
            '{"title":"自助餐","kind":"food","lines":[{"type":"calorie","amount_kcal":5000,"confidence":0.4}]}',
        mode: ParseMode.kcalOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines.single.amount, 5000);
      expect(parsed.lines.single.band, ConfidenceBand.red, reason: '<0.5 → 红+强制高亮');
    });

    test('5001 拒绝', () {
      final errors = expectErrors('{"title":"x","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":5001,"confidence":0.6}]}');
      expect(errors.first, contains('[0,5000]'));
    });

    test('-1 拒绝', () {
      final errors = expectErrors('{"title":"x","kind":"food","lines":'
          '[{"type":"calorie","amount_kcal":-1,"confidence":0.6}]}');
      expect(errors.first, contains('[0,5000]'));
    });
  });

  group('单边开关（§3.3：schema 中对应 lines 只产出一类）', () {
    test('moneyOnly：丢弃 calorie 行，kind 推导为 expense', () {
      final parsed = validateAndMap(
        rawOutput: kLanzhouParseJson,
        mode: ParseMode.moneyOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines, hasLength(1));
      expect(parsed.lines.single.type, dom.LineType.money);
      expect(parsed.kind, dom.EntryKind.expense);
      expect(parsed.notes.join(), contains('仅记钱'));
    });

    test('kcalOnly：丢弃 money 行，kind 推导为 food', () {
      final parsed = validateAndMap(
        rawOutput: kLanzhouParseJson,
        mode: ParseMode.kcalOnly,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines, hasLength(1));
      expect(parsed.lines.single.type, dom.LineType.calorie);
      expect(parsed.kind, dom.EntryKind.food);
      expect(parsed.notes.join(), contains('仅记热量'));
    });

    test('both：两类行都保留', () {
      final parsed = validateAndMap(
        rawOutput: kLanzhouParseJson,
        mode: ParseMode.both,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.lines, hasLength(2));
    });

    test('moneyOnly 下模型只给了 calorie 行 → emptyResult', () {
      try {
        validateAndMap(
          rawOutput:
              '{"title":"黑咖啡","kind":"food","lines":[{"type":"calorie","amount_kcal":5,"confidence":0.6}]}',
          mode: ParseMode.moneyOnly,
          categoryResolver: const PresetCategoryResolver(),
        );
        fail('预期 emptyResult');
      } on AiValidationException catch (error) {
        expect(error.reason, AiFailureReason.emptyResult);
      }
    });
  });

  group('受约束解码容差（拒绝自由文本，§7.1）', () {
    test('markdown 围栏包裹的 JSON 可提取', () {
      final parsed = validateAndMap(
        rawOutput: '```json\n$kLanzhouParseJson\n```',
        mode: ParseMode.both,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.title, '兰州拉面');
    });

    test('前后缀说明文字可提取（取首个 { 到最后 }）', () {
      final parsed = validateAndMap(
        rawOutput: '解析结果如下：\n$kLanzhouParseJson\n希望有帮助',
        mode: ParseMode.both,
        categoryResolver: const PresetCategoryResolver(),
      );
      expect(parsed.title, '兰州拉面');
    });

    test('纯自由文本（无 JSON）→ invalidJson', () {
      try {
        validateAndMap(
          rawOutput: '我猜你中午吃了兰州拉面，大概花了 18 块钱。',
          mode: ParseMode.both,
          categoryResolver: const PresetCategoryResolver(),
        );
        fail('预期 invalidJson');
      } on AiValidationException catch (error) {
        expect(error.reason, AiFailureReason.invalidJson);
      }
    });

    test('顶层是数组 → invalidJson', () {
      try {
        validateAndMap(
          rawOutput: '[1,2,3]',
          mode: ParseMode.both,
          categoryResolver: const PresetCategoryResolver(),
        );
        fail('预期 invalidJson');
      } on AiValidationException catch (error) {
        expect(error.reason, AiFailureReason.invalidJson);
      }
    });
  });
}
