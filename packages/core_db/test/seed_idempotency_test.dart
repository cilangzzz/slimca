/// 默认数据 seed 幂等测试（§5.4、§3.4、§11.1 W2）。
///
/// 场景：
/// 1. 全新内存库打开（beforeOpen 自动 seed）→ 断言默认账本/内置 kcal 账本/
///    20+ 中文分类/settings 齐备且形状正确；
/// 2. 重复执行 seedDefaultData → 行数与主键集合不变（幂等）；
/// 3. 两个全新库 → 默认数据集一致（确定性）。
///
/// 运行前提：集成阶段已生成 app_database.g.dart 并 flutter pub get。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('seed 首次执行：默认账本 + 内置 kcal 账本 + 20+ 分类 + settings 齐备', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，seed 幂等测试未执行');
      return;
    }
    try {
      final ledgerDao = LedgerDao(db);
      final categoryDao = CategoryDao(db);

      // ── 账本（§5.4④：默认 money 账本恒存在 + 内置 kcal 账本恰一个）──
      final ledgers = await ledgerDao.getAll();
      expect(ledgers, hasLength(2), reason: '§5.4：默认 money 账本 + 内置 kcal 账本');
      final kcalRows = ledgers.where((l) => l.kind == 'kcal').toList();
      expect(kcalRows, hasLength(1), reason: '§5.4：kcal 账本系统内置一个、不可多开');
      expect(kcalRows.single.currency, 'kcal', reason: '§5.4：kcal 账本币种=kcal');
      final moneyRows = ledgers.where((l) => l.kind == 'money').toList();
      expect(moneyRows, hasLength(1));
      expect(moneyRows.single.currency, 'CNY');
      expect(moneyRows.single.openingBalanceMinor, 0);
      expect(ledgers.every((l) => !l.isArchived), isTrue, reason: 'seed 账本未归档');
      expect(ledgers.every((l) => l.revision == 1 && l.schemaVer == 1), isTrue);
      // hlc 定宽编码（§6.3）：13 位:6 位:12 位。
      final hlcPattern = RegExp(r'^\d{13}:\d{6}:[0-9A-F]{12}$');
      expect(ledgers.every((l) => hlcPattern.hasMatch(l.hlc)), isTrue);

      // ── 分类（§3.4 内置分类 P0：20+ 中文分类；§5.4⑤ kind/全局/色 token）──
      final categories = await categoryDao.getAll();
      expect(categories.length, greaterThanOrEqualTo(20),
          reason: '§3.4：内置 20+ 中文分类');
      expect(categories.every((c) => c.isPreset), isTrue, reason: '§5.4⑤：内置分类不可删');
      expect(categories.every((c) => c.ledgerId == null), isTrue,
          reason: '§5.4⑤：ledger_id NULL=全局分类');
      expect(categories.every((c) => c.icon.isNotEmpty && c.colorToken.isNotEmpty),
          isTrue,
          reason: '§5.4⑤/§8.2：icon 与语义 token 名必填，禁止裸色值');
      expect(categories.map((c) => c.kind).toSet(), {'expense', 'income'},
          reason: '§11.1 W2：金额分类与热量维度并存按文档（§5.4⑤ kind 行）');
      // 文档点名的分类必须在列（§3.4）。
      final names = categories.map((c) => c.name).toSet();
      for (final name in const [
        '餐饮-早餐', '餐饮-正餐', '餐饮-外卖', '交通', '购物', '居住',
        '娱乐', '医疗', '教育', '人情', '储蓄',
      ]) {
        expect(names, contains(name), reason: '§3.4 点名的内置分类: $name');
      }

      // ── settings（§5.6⑲）：device_id 12 位 hex、default_ledger_id 可解析 ──
      final deviceRow = await (db.select(db.settings)
            ..where((t) => t.key.equals(kSettingDeviceId)))
          .getSingle();
      final deviceId = jsonDecode(deviceRow.value) as String;
      expect(RegExp(r'^[0-9A-F]{12}$').hasMatch(deviceId), isTrue,
          reason: '§6.3：device_id 段=12 位定长 hex');

      final ledgerIdRow = await (db.select(db.settings)
            ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
          .getSingle();
      final defaultLedgerId = jsonDecode(ledgerIdRow.value) as String;
      expect(ledgers.any((l) => l.id == defaultLedgerId && l.kind == 'money'),
          isTrue, reason: '§5.6⑲：默认账本指向真实 money 账本');
    } finally {
      await db.close();
    }
  });

  test('seed 幂等：重复执行后行数与主键集合不变', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，seed 幂等测试未执行');
      return;
    }
    try {
      final ledgerDao = LedgerDao(db);
      final categoryDao = CategoryDao(db);

      final ledgers1 = await ledgerDao.getAll();
      final categories1 = await categoryDao.getAll();
      final device1 = await (db.select(db.settings)
            ..where((t) => t.key.equals(kSettingDeviceId)))
          .getSingle();

      // 再跑两轮 seed（模拟多次打开/多设备时序）。
      await seedDefaultData(db);
      await seedDefaultData(db);

      final ledgers2 = await ledgerDao.getAll();
      final categories2 = await categoryDao.getAll();
      final device2 = await (db.select(db.settings)
            ..where((t) => t.key.equals(kSettingDeviceId)))
          .getSingle();

      expect(ledgers2.length, ledgers1.length, reason: '账本不重复 seed');
      expect(ledgers2.map((l) => l.id), ledgers1.map((l) => l.id),
          reason: '账本主键不变（缺什么补什么、已有行不动）');
      expect(categories2.length, categories1.length, reason: '分类不重复 seed');
      expect(categories2.map((c) => c.id).toSet(), categories1.map((c) => c.id).toSet(),
          reason: '分类主键不变');
      expect(device2.value, device1.value, reason: 'device_id 一经生成不复写');
    } finally {
      await db.close();
    }
  });

  test('seed 确定性：两个全新库产出一致的默认数据集', () async {
    final dbA = await tryOpenTestDatabase();
    final dbB = await tryOpenTestDatabase();
    if (dbA == null || dbB == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，seed 幂等测试未执行');
      await dbA?.close();
      await dbB?.close();
      return;
    }
    try {
      final namesA =
          (await CategoryDao(dbA).getAll()).map((c) => '${c.kind}/${c.name}').toSet();
      final namesB =
          (await CategoryDao(dbB).getAll()).map((c) => '${c.kind}/${c.name}').toSet();
      expect(namesA, namesB, reason: '内置分类清单与顺序确定性');

      final ledgerKindsA =
          (await LedgerDao(dbA).getAll()).map((l) => l.kind).toSet();
      final ledgerKindsB =
          (await LedgerDao(dbB).getAll()).map((l) => l.kind).toSet();
      expect(ledgerKindsA, {'money', 'kcal'});
      expect(ledgerKindsA, ledgerKindsB);
    } finally {
      await dbA.close();
      await dbB.close();
    }
  });
}
