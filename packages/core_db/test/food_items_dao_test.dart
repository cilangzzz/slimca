/// FoodItemsDao 测试（§5.2③ food_items、§3.3 菜品明细联动重算、§11.2 W11-12）。
///
/// 覆盖：
/// 1. create + findById/findByEntryId/findByLineId：字段与 §5.1 公共列齐备、
///    按创建序、行自身墓碑排除（业务清单不展示已删菜品）；
/// 2. updateDetails：哨兵语义、份量滑杆联动重算字段（portion/kcal/宏量）、
///    user_adjusted 自动置 true（§5.2③「用户是否改过（校准信号）」）、显式
///    覆盖口径、无真实变化 no-op 不推版本；
/// 3. softDelete：墓碑幂等（保留首次墓碑时刻）、查询排除。
///
/// 出网（§6.2 同事务入队）断言集中在 outbox_write_path_test.dart
/// （「food_items 写路径 outbox 覆盖」用例），本文件聚焦 DAO 行为。
///
/// 运行前提同既有策略：宿主缺 sqlite3 运行库时温和跳过。
library;

import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('create + 查询：字段/公共列齐备、按创建序、墓碑排除', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，FoodItemsDao 测试未执行');
      return;
    }
    try {
      final dao = FoodItemsDao(db);
      const entryId = 'entry-food-1';
      const lineId = 'line-calorie-1';

      final noodle = await dao.create(
        entryId: entryId,
        lineId: lineId,
        name: '牛肉拉面',
        portionG: 450,
        kcal: 500,
        proteinG: 25,
        carbG: 65,
        fatG: 12,
        refSource: 'local',
        confidence: 0.62,
      );
      expect(noodle.id, isNotEmpty, reason: '缺省 id=本地生成 UUIDv7（§5.1）');
      expect(noodle.entryId, entryId);
      expect(noodle.lineId, lineId);
      expect(noodle.name, '牛肉拉面');
      expect(noodle.portionG, 450);
      expect(noodle.kcal, 500);
      expect(noodle.proteinG, 25);
      expect(noodle.carbG, 65);
      expect(noodle.fatG, 12);
      expect(noodle.refSource, 'local');
      expect(noodle.refId, isNull);
      expect(noodle.confidence, closeTo(0.62, 1e-9));
      expect(noodle.userAdjusted, isFalse, reason: 'AI 初值：未经过用户改动');
      expect(noodle.revision, 1);
      expect(noodle.hlc, matches(RegExp(r'^\d{13}:\d{6}:[0-9A-F]{12}$')),
          reason: '§6.3 定宽 HLC 编码');
      expect(noodle.deletedAt, isNull);

      final egg = await dao.create(
        entryId: entryId,
        lineId: lineId,
        name: '卤蛋',
        portionG: 60,
        kcal: 200,
        proteinG: 12,
        carbG: 1,
        fatG: 14,
        refSource: 'baidu',
        refId: 'baidu-1024',
        confidence: 0.9,
        userAdjusted: true, // 手动补录菜品：登记即用户口径
        id: 'food-item-egg',
      );
      expect(egg.id, 'food-item-egg', reason: '可注入 id（§5.1 应用层生成）');
      expect(egg.refId, 'baidu-1024');
      expect(egg.userAdjusted, isTrue);

      // 按 entry 查询（§5.2③ entry_id）：创建序（牛肉面先登记）。
      final byEntry = await dao.findByEntryId(entryId);
      expect(byEntry.map((f) => f.id).toList(), [noodle.id, egg.id]);
      expect(byEntry, hasLength(2));

      // 按 calorie 行查询（§5.2③ line_id）：行级溯源视图。
      final byLine = await dao.findByLineId(lineId);
      expect(byLine, hasLength(2));

      // 其他 entry/line 无串扰。
      expect(await dao.findByEntryId('entry-other'), isEmpty);
      expect(await dao.findByLineId('line-other'), isEmpty);
      expect((await dao.findById('food-item-egg'))!.name, '卤蛋');
    } finally {
      await db.close();
    }
  });

  test('updateDetails：份量滑杆联动重算、user_adjusted 自动置 true、'
      '显式覆盖与 no-op 不推版本', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，FoodItemsDao 测试未执行');
      return;
    }
    try {
      final dao = FoodItemsDao(db);
      final item = await dao.create(
        entryId: 'entry-food-2',
        lineId: 'line-calorie-2',
        name: '红烧肉',
        portionG: 200,
        kcal: 570,
        proteinG: 24,
        carbG: 8,
        fatG: 48,
        refSource: 'llm',
        refId: 'llm-hongshaorou',
        confidence: 0.55,
        id: 'food-item-2',
      );
      expect(item.userAdjusted, isFalse);

      // 份量滑杆 200g→300g 联动重算（§3.3「份量滑杆联动热量重算」）：
      // 真实事实变化 → user_adjusted 自动置 true（校准信号，§5.2③）。
      await dao.updateDetails(
        id: 'food-item-2',
        portionG: 300,
        kcal: 855,
        proteinG: 36,
        carbG: 12,
        fatG: 72,
      );
      var row = (await dao.findById('food-item-2'))!;
      expect(row.portionG, 300);
      expect(row.kcal, 855);
      expect(row.proteinG, 36);
      expect(row.carbG, 12);
      expect(row.fatG, 72);
      expect(row.userAdjusted, isTrue, reason: '§5.2③ 校准信号：用户改过');
      expect(row.revision, 2, reason: '真实写入推进版本');
      expect(row.name, '红烧肉', reason: '哨兵字段不动');

      // 仅改名称（同样属于事实字段）→ 继续推进；ref_source 联查改写。
      await dao.updateDetails(
        id: 'food-item-2',
        name: '红烧肉（小碗）',
        refSource: 'usda',
        refId: 'usda-167569',
      );
      row = (await dao.findById('food-item-2'))!;
      expect(row.name, '红烧肉（小碗）');
      expect(row.refSource, 'usda');
      expect(row.refId, 'usda-167569');
      expect(row.revision, 3);

      // 显式 refId=null 置空（哨兵与 null 区分，§5.2③ ref_id 可空）。
      await dao.updateDetails(id: 'food-item-2', refId: null);
      row = (await dao.findById('food-item-2'))!;
      expect(row.refId, isNull);
      expect(row.revision, 4);

      // 显式 userAdjusted 覆盖自动口径（修正闭环写路径特殊口径）：
      // 事实变化但调用方明确声明非用户改动。
      await dao.updateDetails(
        id: 'food-item-2',
        kcal: 860,
        userAdjusted: false,
      );
      row = (await dao.findById('food-item-2'))!;
      expect(row.kcal, 860);
      expect(row.userAdjusted, isFalse, reason: '显式参数优先于自动置位');

      // 无真实变化：no-op——不推版本（与 §6.2「只对真实写入入队」同源）。
      final revisionBefore = row.revision;
      await dao.updateDetails(id: 'food-item-2', kcal: 860);
      row = (await dao.findById('food-item-2'))!;
      expect(row.revision, revisionBefore, reason: 'no-op 不推版本');

      // 无此行：StateError。
      await expectLater(
        dao.updateDetails(id: 'ghost-item', kcal: 1),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('softDelete：墓碑幂等、业务查询排除、findById 保留审计', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，FoodItemsDao 测试未执行');
      return;
    }
    try {
      final dao = FoodItemsDao(db);
      const entryId = 'entry-food-3';
      await dao.create(
        entryId: entryId,
        lineId: 'line-calorie-3',
        name: '米饭',
        portionG: 200,
        kcal: 232,
        proteinG: 5,
        carbG: 51,
        fatG: 0,
        refSource: 'local',
        confidence: 0.95,
        id: 'food-item-3a',
      );
      await dao.create(
        entryId: entryId,
        lineId: 'line-calorie-3',
        name: '青菜',
        portionG: 150,
        kcal: 30,
        proteinG: 2,
        carbG: 4,
        fatG: 0,
        refSource: 'local',
        confidence: 0.9,
        id: 'food-item-3b',
      );
      expect(await dao.findByEntryId(entryId), hasLength(2));

      // 软删墓碑（§5.1 删除行）：业务查询排除、findById 保留行。
      await dao.softDelete('food-item-3a');
      final tombstone = (await dao.findById('food-item-3a'))!;
      expect(tombstone.deletedAt, isNotNull);
      expect(tombstone.name, '米饭', reason: '墓碑保留行内容（同步对齐用）');
      expect((await dao.findByEntryId(entryId)).map((f) => f.id), ['food-item-3b']);
      expect(await dao.findByLineId('line-calorie-3'), hasLength(1));

      // 重复软删幂等：保留首次墓碑时刻、不再推版本（no-op）。
      final deletedAt = tombstone.deletedAt!;
      final revision = tombstone.revision;
      await dao.softDelete('food-item-3a');
      final again = (await dao.findById('food-item-3a'))!;
      expect(again.deletedAt, deletedAt);
      expect(again.revision, revision);

      // 墓碑行 updateDetails：仍可写（同步回写公共列场景）但本 DAO 口径下
      // 无事实变化即 no-op——不会复活墓碑。
      await dao.updateDetails(id: 'food-item-3a', name: '米饭');
      final afterNoop = (await dao.findById('food-item-3a'))!;
      expect(afterNoop.deletedAt, deletedAt, reason: '墓碑拒绝复活（§6.5）');
      expect(afterNoop.revision, revision);

      // 无此行：StateError。
      await expectLater(dao.softDelete('ghost-item'), throwsStateError);
    } finally {
      await db.close();
    }
  });
}
