/// LedgerDao 多账本扩展对账测试（§5.4④、§3.4 多账本 P1、§11.2 W15）。
///
/// 覆盖：
/// - createLedger：money 建口（kcal 不可多开——无 kcal 建口）、outbox 同事务
///   入队、sort 追加；
/// - renameLedger：money/kcal 均允许（seed 既定口径）；空名拒绝；
/// - setLedgerArchived：归档软移除（getActive 不再出现、watchAll 仍在）、
///   恢复、kcal 拒绝归档（§5.4④ 不可删除）、幂等；
/// - setDefaultLedger / defaultLedgerId / defaultLedger：settings 指针
///   （§5.6⑲）、kcal/已归档账本拒绝、默认账本归档后指针自动重排、
///   最后一个 money 账本归档后指针撤下（读取回退 null）；
/// - 归档不落墓碑（deleted_at 保持 NULL——墓碑语义保留给真删除，§5.1）。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
// as drift：测试内 where 表达式 `&` 组合算子（前缀导入扩展不生效，须裸导入）。
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('createLedger/rename/archive：写路径、kcal 保护与幂等', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，LedgerDao 多账本测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      await drainSeedOutbox(database);
      final db.LedgerDao dao = db.LedgerDao(database);

      // 建账本：money 建口 + outbox 同事务入队（§6.2）。
      final db.Ledger travel = await dao.createLedger(
        name: '旅行账本',
        currency: 'CNY',
      );
      expect(travel.kind, db.kLedgerKindMoney, reason: 'kcal 不可多开（§5.4④）');
      expect(travel.currency, 'CNY');
      expect(travel.isArchived, isFalse);
      final db.Ledger? outboxed = await (database.select(database.ledgers)
            ..where((t) => t.id.equals(travel.id)))
          .getSingleOrNull();
      expect(outboxed, isNotNull);
      final List<db.SyncOutboxItem> ledgerOutbox = await (database.select(
        database.syncOutbox,
      )..where((t) => t.targetTable.equals('ledgers') & t.rowId.equals(travel.id)))
          .get();
      expect(ledgerOutbox.single.op, 'upsert');

      // 空名拒绝。
      expect(
        () => dao.createLedger(name: '   '),
        throwsArgumentError,
      );

      // 重命名：money 与 kcal 均允许（seed 口径「允许用户后续改名」）。
      await dao.renameLedger(travel.id, name: '旅行备用金');
      expect((await dao.findById(travel.id))!.name, '旅行备用金');
      final db.Ledger kcal = (await dao.kcalLedger())!;
      await dao.renameLedger(kcal.id, name: '热量账本改');
      expect((await dao.findById(kcal.id))!.name, '热量账本改');

      // kcal 归档拒绝（§5.4④ 不可删除）。
      expect(
        () => dao.setLedgerArchived(kcal.id, archived: true),
        throwsStateError,
      );

      // 归档：getActive 移除、watchAll 仍在、不落墓碑；幂等恢复。
      await dao.setLedgerArchived(travel.id, archived: true);
      final db.Ledger archived = (await dao.findById(travel.id))!;
      expect(archived.isArchived, isTrue);
      expect(archived.deletedAt, isNull,
          reason: '归档≠删除：墓碑语义保留给真删除（§5.1）');
      expect(
        (await dao.getActive()).map((l) => l.id),
        isNot(contains(travel.id)),
        reason: '归档账本不进切换抽屉（§3.4）',
      );
      expect(
        (await dao.getAll()).map((l) => l.id),
        contains(travel.id),
        reason: '归档行仍在全量列表（历史账单引用保留，§5.4⑤ 逻辑引用）',
      );
      await dao.setLedgerArchived(travel.id, archived: false);
      expect((await dao.findById(travel.id))!.isArchived, isFalse);
    } finally {
      await database.close();
    }
  });

  test('默认账本：settings 指针、kcal/归档拒绝、归档默认后指针重排', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，LedgerDao 多账本测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final db.LedgerDao dao = db.LedgerDao(database);
      final db.Ledger seedDefault =
          (await dao.defaultMoneyLedger())!; // seed 默认账本
      final db.Ledger kcal = (await dao.kcalLedger())!;
      final db.Ledger second =
          await dao.createLedger(name: '第二账本', currency: 'CNY');

      // 切换默认：settings 指针写入（§5.6⑲），defaultLedgerId/defaultLedger
      // 随之解析。
      await dao.setDefaultLedger(second.id);
      final db.Setting setting = await (database.select(database.settings)
            ..where((t) => t.key.equals(db.kSettingDefaultLedgerId)))
          .getSingle();
      expect(jsonDecode(setting.value), second.id);
      expect(await dao.defaultLedgerId(), second.id);
      expect((await dao.defaultLedger())!.id, second.id);

      // kcal 不能作默认（口径恒内置，§5.2② kcal 行归集内置 kcal 账本）。
      expect(
        () => dao.setDefaultLedger(kcal.id),
        throwsArgumentError,
      );

      // 归档当前默认 → 指针自动重排到剩余首个可用 money 账本。
      await dao.setLedgerArchived(second.id, archived: true);
      expect(await dao.defaultLedgerId(), seedDefault.id,
          reason: '归档默认账本后指针重排（§3.4 账本归档语义自洽）');

      // 归档后的账本不能设为默认。
      expect(
        () => dao.setDefaultLedger(second.id),
        throwsStateError,
      );

      // 最后一个 money 账本也归档 → 指针撤下，defaultLedgerId 回退 null
      // （上层引导建账本；空库 seed 兜底在下次打开补种）。
      await dao.setLedgerArchived(seedDefault.id, archived: true);
      final String? pointer = await dao.defaultLedgerId();
      expect(pointer, isNull, reason: '无可用 money 账本 → 指针撤下');
      final db.Setting? settingRow = await (database.select(database.settings)
            ..where((t) => t.key.equals(db.kSettingDefaultLedgerId)))
          .getSingleOrNull();
      expect(settingRow, isNull);
    } finally {
      await database.close();
    }
  });

  test('watchDefaultLedgerId / watchActive 响应式跟手', () async {
    final db.AppDatabase? maybe = await tryOpenTestDatabase();
    if (maybe == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，LedgerDao 多账本测试未执行');
      return;
    }
    final db.AppDatabase database = maybe;
    try {
      final db.LedgerDao dao = db.LedgerDao(database);
      final db.Ledger seedDefault = (await dao.defaultMoneyLedger())!;
      final db.Ledger second =
          await dao.createLedger(name: '第三账本', currency: 'CNY');

      // watchDefaultLedgerId：settings 行变更 → 新指针值（每次 listen 取
      // 一个新流——drift watch 流单订阅语义，避免复用流对象）。
      expect(await dao.watchDefaultLedgerId().first, seedDefault.id,
          reason: 'seed 写入的默认指针');
      await dao.setDefaultLedger(second.id);
      expect(await dao.watchDefaultLedgerId().first, second.id,
          reason: 'watch 流响应 settings 变更（§10.1 reactive stream）');

      // watchActive：归档 → 可用列表收窄。
      final List<db.Ledger> beforeArchive = await dao.watchActive().first;
      expect(beforeArchive.map((l) => l.id), contains(second.id));
      await dao.setLedgerArchived(second.id, archived: true);
      final List<db.Ledger> afterArchive = await dao.watchActive().first;
      expect(afterArchive.map((l) => l.id), isNot(contains(second.id)));
    } finally {
      await database.close();
    }
  });
}
