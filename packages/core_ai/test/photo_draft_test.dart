/// food_items 草稿组装测试（W11-12 任务第 4 项：§5.2③
/// name/grams/est_kcal/source 联查钩子改写；§7.1 校验器为组装产物的硬闸门）。
library;

import 'dart:convert';

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_test/flutter_test.dart';

import 'photo_test_support.dart';

ValidatedParse validateAssembled({
  required List<DishCandidate> dishes,
  DishRefLookup? refLookup,
  FoodRefSource fallbackRefSource = FoodRefSource.baidu,
}) {
  final raw = assembleDishParseJson(
    dishes: dishes,
    refLookup: refLookup ?? const PassthroughDishRefLookup(),
    fallbackRefSource: fallbackRefSource,
  );
  // 组装产物一律过既有校验器（§7.1 硬闸门，与文本管线同一映射权威）。
  return validateAndMap(
    rawOutput: raw,
    mode: ParseMode.kcalOnly,
    categoryResolver: const PresetCategoryResolver(),
  );
}

void main() {
  group('未联查未直报（W11-12 缺省：est_kcal 走本地估计基准 + 置信度降档）', () {
    test('est_kcal = kFallbackKcalPer100g × grams / 100；ref_source 按供应商标记',
        () {
      final validated = validateAssembled(
        dishes: kFixtureDishes,
        fallbackRefSource: FoodRefSource.baidu,
      );

      expect(validated.kind, dom.EntryKind.food);
      expect(validated.lines, hasLength(1));
      final line = validated.lines.single;
      expect(line.type.wire, 'calorie');

      final items = line.items;
      expect(items, hasLength(2));
      // 宫保鸡丁 300g × 150kcal/100g = 450 kcal。
      expect(items[0].name, '宫保鸡丁');
      expect(items[0].portionG, 300);
      expect(items[0].kcal, 450);
      expect(items[0].refSource, FoodRefSource.baidu, reason: '百度识别 → §5.2③ baidu');
      expect(items[0].confidence, closeTo(0.7 * kUncalibratedConfidencePenalty, 1e-9),
          reason: '未联查校准 → 置信度降档（§7.1 红线）');
      // 米饭 200g × 150/100 = 300 kcal。
      expect(items[1].kcal, 300);
      expect(items[1].refSource, FoodRefSource.baidu);
      expect(items[1].confidence, closeTo(0.8 * kUncalibratedConfidencePenalty, 1e-9));

      // 行级 = Σitems（§7.2 口径）= 750；行置信度 = 最弱 facet。
      expect(line.amount, 750);
      expect(line.confidence, closeTo(0.56, 1e-9));
      // 拍照缺省分类提示（§3.3 餐食场景）。
      expect(line.categoryHint, kDefaultPhotoCategoryHint);
      // §5.2③：联查未命中 → 无来源库条目 id。
      expect(items[0].refId, isNull);
    });

    test('Vision 供应商标记 → ref_source=llm（§5.2③ 联查来源口径）', () {
      final validated = validateAssembled(
        dishes: const [
          DishCandidate(name: '牛肉拉面', grams: 450, confidence: 0.55),
        ],
        fallbackRefSource: FoodRefSource.llm,
      );
      expect(validated.lines.single.items.single.refSource, FoodRefSource.llm);
    });

    test('title 取候选菜名「、」连接并截断 20 字', () {
      final short = validateAssembled(
        dishes: const [
          DishCandidate(name: '宫保鸡丁', grams: 300, confidence: 0.7),
          DishCandidate(name: '米饭', grams: 200, confidence: 0.8),
        ],
      );
      expect(short.title, '宫保鸡丁、米饭');

      final longNames = List<DishCandidate>.generate(
        8,
        (i) => DishCandidate(name: '第${i + 1}道超长菜品名称占位符', grams: 100, confidence: 0.5),
      );
      final long = validateAssembled(dishes: longNames);
      expect(long.title.length, lessThanOrEqualTo(21),
          reason: '截 20 字 + 省略号');
      expect(long.title.endsWith('…'), isTrue);
    });

    test('parse_notes 携带联查命中统计（§7.3 → entries.note）', () {
      final validated = validateAssembled(dishes: kFixtureDishes);
      expect(validated.parseNotes, contains('联查校准命中 0 项'));
    });
  });

  group('联查命中（§7.1 第 6 步：联查校准改写 kcal/ref_source/ref_id/份量）', () {
    test('参考条目全字段改写；命中项不降置信度', () {
      final validated = validateAssembled(
        dishes: kFixtureDishes,
        refLookup: MapDishRefLookup(<String, DishRefEntry>{
          '宫保鸡丁': const DishRefEntry(
            kcalPer100g: 240,
            refSource: FoodRefSource.usda,
            refId: 'usda-001',
            defaultPortionG: 180,
          ),
        }),
        fallbackRefSource: FoodRefSource.baidu,
      );

      final items = validated.lines.single.items;
      // 命中：份量 180g、kcal 240×180/100=432、ref_source=usda、ref_id 回填。
      expect(items[0].portionG, 180, reason: '参考库默认份量覆写候选基准');
      expect(items[0].kcal, 432);
      expect(items[0].refSource, FoodRefSource.usda);
      expect(items[0].refId, 'usda-001');
      expect(items[0].confidence, closeTo(0.7, 1e-9), reason: '联查校准 → 不降档');
      // 未命中：保持候选基准与降档。
      expect(items[1].kcal, 300);
      expect(items[1].refSource, FoodRefSource.baidu);
      expect(validated.parseNotes, contains('联查校准命中 1 项'));
    });

    test('模型直报 hint：仅联查未命中时作 est_kcal 初值（红线 §7.1）', () {
      final validated = validateAssembled(
        dishes: const [
          DishCandidate(
            name: '牛肉拉面',
            grams: 450,
            confidence: 0.55,
            kcalPer100gHint: 111.1,
          ),
        ],
        fallbackRefSource: FoodRefSource.llm,
      );
      final item = validated.lines.single.items.single;
      expect(item.kcal, 500, reason: 'est_kcal = hint × grams / 100 = 111.1×450/100 ≈ 500');
      expect(item.refSource, FoodRefSource.llm, reason: 'LLM 直报未经联查');
      expect(item.confidence, closeTo(0.55 * kUncalibratedConfidencePenalty, 1e-9));
    });

    test('联查命中时 hint 不采用（校准优先于模型直报）', () {
      final validated = validateAssembled(
        dishes: const [
          DishCandidate(
            name: '宫保鸡丁',
            grams: 300,
            confidence: 0.7,
            kcalPer100gHint: 999,
          ),
        ],
        refLookup: MapDishRefLookup(<String, DishRefEntry>{
          '宫保鸡丁': const DishRefEntry(
            kcalPer100g: 240,
            refSource: FoodRefSource.local,
          ),
        }),
        fallbackRefSource: FoodRefSource.llm,
      );
      expect(validated.lines.single.items.single.kcal, 720, reason: '240×300/100');
    });
  });

  group('越界防御（§7.1 校验器口径）', () {
    test('行级 kcal 超 5000 → 截断（确认卡/修正闭环承接）', () {
      final dishes = List<DishCandidate>.generate(
        5,
        (i) => DishCandidate(
          name: '大菜$i',
          grams: 300,
          confidence: 0.6,
          kcalPer100gHint: 3000,
        ),
      );
      final validated = validateAssembled(dishes: dishes);
      expect(validated.lines.single.amount, 5000);
    });

    test('非法候选（空白名/非正份量）兜底不崩溃', () {
      final validated = validateAssembled(
        dishes: const [
          DishCandidate(name: '  ', grams: 300, confidence: 0.5),
          DishCandidate(name: '米饭', grams: -5, confidence: 0.5),
        ],
      );
      final items = validated.lines.single.items;
      expect(items, hasLength(1), reason: '空白名候选跳过');
      expect(items.single.name, '米饭');
      expect(items.single.portionG, kDefaultDishPortionG,
          reason: '非正份量 → 基准份量兜底');
    });

    test('组装产物必为合法 §7.2 JSON（可回放缓存载荷，§5.6⑭）', () {
      final raw = assembleDishParseJson(
        dishes: kFixtureDishes,
        refLookup: const PassthroughDishRefLookup(),
        fallbackRefSource: FoodRefSource.baidu,
      );
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      expect(decoded['title'], isNotEmpty);
      expect(decoded['kind'], 'food');
      final lines = decoded['lines'] as List<Object?>;
      final line = lines.single as Map<String, Object?>;
      expect(line['type'], 'calorie');
      expect((line['items'] as List<Object?>), hasLength(2));
    });
  });
}
