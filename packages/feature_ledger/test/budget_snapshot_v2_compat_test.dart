/// budget_snapshot v2 解析兼容 + 账本管理页冒烟测试（§5.6⑬、§11.2 W15）。
///
/// 覆盖（任务口径「预算快照 v2 形状与兼容」的读取端半边）：
/// - `parseBudgetSnapshot` **v2 形态**（daily+monthly 双数组、monthly 项
///   period_start/period_end/carry_over 键）逐项解析；
/// - **v1 形态兼容**（仅 daily 数组）：项缺省 daily 周期——旧快照解析不变；
/// - **平铺形态兼容**（feature_dashboard v1）：合成 used/remaining；
/// - `LedgerDayBriefing.spendBudget/kcalBudget`：月度预算不混入「每日目标」
///   行（§5.4⑥ 周期语义）；
/// - `LedgerManagePage` 冒烟：默认徽标/内置 kcal 只读行/新建账本流程
///   （写路径经 LedgerDao → outbox 同事务入队）。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过（widget 半边）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feature_ledger/feature_ledger.dart';
import 'package:ui_kit/ui_kit.dart';

bool _isSqliteLibraryMissing(Object error) {
  final String msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 放大视口让整页可构建（ListView 懒构建裁剪问题；测试结束复位）。
void _enlargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('parseBudgetSnapshot v2 形态与兼容（§5.6⑬ W15）', () {
    test('v2：daily+monthly 双数组，monthly 项携带周期窗口与结转标记', () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"v":2,'
        '"daily":['
        '{"ledger_id":"lm","category_id":null,"amount":10000,"used":5500,"remaining":4500},'
        '{"ledger_id":"lk","category_id":null,"amount":2000,"used":1500,"remaining":500}'
        '],'
        '"monthly":['
        '{"ledger_id":"lm","category_id":null,"amount":90000,"used":7700,'
        '"remaining":82300,"carry_over":false,"period_start":"2026-01-15",'
        '"period_end":"2026-02-15"},'
        '{"ledger_id":"lm","category_id":null,"amount":7800,"used":5500,'
        '"remaining":2300,"carry_over":true,"period_start":"2026-02-01",'
        '"period_end":"2026-03-01"}'
        ']}',
        daySpendMinor: 5500,
        dayNetKcal: 1500,
        kcalLedgerIds: const <String>{'lk'},
      );
      expect(items.length, 4, reason: 'daily 2 + monthly 2');
      // daily 项：periodType 缺省 daily（v1 兼容口径不变）。
      expect(items[0].periodType, kBudgetPeriodDaily);
      expect(items[0].isKcal, false);
      expect(items[0].remaining, 4500);
      expect(items[1].isKcal, true);
      // monthly 项：periodType/carry_over/period 窗口落位。
      final LedgerBudgetItem monthly15 = items[2];
      expect(monthly15.isMonthly, true);
      expect(monthly15.periodType, kBudgetPeriodMonthly);
      expect(monthly15.periodStart, '2026-01-15');
      expect(monthly15.periodEnd, '2026-02-15');
      expect(monthly15.carryOver, isFalse);
      final LedgerBudgetItem monthlyCarry = items[3];
      expect(monthlyCarry.carryOver, isTrue);
      expect(monthlyCarry.amount, 7800, reason: '结转后的 effective amount');
    });

    test('v1 兼容：仅 daily 数组 → 全部项缺省 daily 周期（旧快照解析不变）',
        () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"daily":[{"ledger_id":"lm","category_id":"c1","amount":500,'
        '"used":300,"remaining":200}]}',
        daySpendMinor: 300,
        dayNetKcal: 0,
      );
      expect(items.length, 1);
      expect(items.single.periodType, kBudgetPeriodDaily);
      expect(items.single.isMonthly, isFalse);
      expect(items.single.isCategoryGoal, true);
      expect(items.single.periodStart, isNull);
      expect(items.single.carryOver, isFalse);
    });

    test('平铺形态兼容：按当日投影值合成 used/remaining（升级期兼容）', () {
      final List<LedgerBudgetItem> items = parseBudgetSnapshot(
        '{"kcal_budget":2000,"spend_budget_minor":1000}',
        daySpendMinor: 1850,
        dayNetKcal: 650,
      );
      expect(items.length, 2);
      expect(items.every((LedgerBudgetItem i) =>
          i.periodType == kBudgetPeriodDaily), isTrue);
      expect(items[0].used, 650);
      expect(items[1].used, 1850);
    });

    test('日简报「每日目标」行不混入月度预算（§5.4⑥ 周期语义）', () {
      final List<LedgerBudgetItem> budgets = parseBudgetSnapshot(
        '{"v":2,'
        '"daily":[{"ledger_id":"lm","category_id":null,"amount":1000,'
        '"used":800,"remaining":200}],'
        '"monthly":[{"ledger_id":"lm","category_id":null,"amount":90000,'
        '"used":1000,"remaining":89000,"carry_over":false,'
        '"period_start":"2026-02-01","period_end":"2026-03-01"}]}',
        daySpendMinor: 800,
        dayNetKcal: 0,
      );
      final LedgerDayBriefing briefing = LedgerDayBriefing(
        date: '2026-02-03',
        kcalIn: 0,
        kcalOut: 0,
        netKcal: 0,
        spendMinor: 800,
        incomeMinor: 0,
        budgets: budgets,
      );
      expect(briefing.spendBudget?.amount, 1000,
          reason: 'spendBudget 只取 daily 总预算（月度预算不混入）');
      expect(briefing.kcalBudget, isNull);
    });
  });

  testWidgets('LedgerManagePage 冒烟：默认徽标/内置 kcal 只读/新建账本',
      (WidgetTester tester) async {
    _enlargeViewport(tester);
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      // 清空 seed 出网项（seed 会把内置账本/分类同事务入队，§5.4）——
      // 本用例只断言「新建账本」的出网行，从干净 outbox 起步。
      await db.delete(db.syncOutbox).go();
      final DriftLedgerManageRepository repo = DriftLedgerManageRepository(db);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(body: LedgerManagePage(repository: repo)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // seed 账本：默认账本带「默认」徽标；kcal 带内置徽标与不可删说明。
      expect(find.text('默认账本'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      expect(find.text('内置'), findsOneWidget,
          reason: 'kcal 行内置徽标（卡副题含「内置」二字，故用精确匹配）');
      expect(find.textContaining('不可删除不可多开'), findsOneWidget);
      // kcal 行无归档入口（不可删，§5.4④）。
      final cdb.Ledger kcal = (await cdb.LedgerDao(db).kcalLedger())!;
      expect(
        find.byKey(ValueKey<String>('ledger_manage_archive_${kcal.id}')),
        findsNothing,
      );

      // 新建账本流程：对话框 → 保存 → 列表出现 + outbox 入队。
      await tester.tap(find.byKey(ledgerManageCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ledgerManageNameFieldKey),
        '旅行账本',
      );
      await tester.tap(find.byKey(ledgerManageSaveKey));
      await tester.pumpAndSettle();
      expect(find.text('旅行账本'), findsOneWidget);
      final List<cdb.SyncOutboxItem> outbox = await (db.select(db.syncOutbox)
            ..where((t) => t.targetTable.equals('ledgers')))
          .get();
      expect(outbox.length, 1, reason: '新账本行快照同事务入队（§6.2）');

      // 设为默认：徽标迁移（settings 指针，§5.6⑲）。
      final cdb.Ledger travel = await (db.select(db.ledgers)
            ..where((t) => t.name.equals('旅行账本')))
          .getSingle();
      await tester.tap(
        find.byKey(ValueKey<String>('ledger_manage_default_${travel.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('默认'), findsOneWidget, reason: '默认徽标恒恰一个');
      expect(await cdb.LedgerDao(db).defaultLedgerId(), travel.id);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，账本管理页冒烟测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
