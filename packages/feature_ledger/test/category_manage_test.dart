/// 分类管理页 widget 测试（§11.1 W5-6 验收线：设置每日目标 → 断言
/// budgets 落库 / 预算快照 / 日简报超支提示；分类增删改与内置不可删）。
///
/// 流程：内存真库（beforeOpen 自动 seed）→ 经页面对话框设置每日总支出
/// /总热量/分类级目标 → 断言 budgets 行 → 插入当日超支记录 →
/// recomputeDaySummary 重建投影（§5.6⑬）→ 断言 budget_snapshot JSON →
/// pump LedgerPage 断言日简报超支文案。分类增删改经对话框走
/// DriftLedgerAdminRepository（LocalWriteClock 发戳，§6.2）。Windows
/// 宿主缺 sqlite3 运行库时温和跳过；无真实网络/平台通道（§10.5）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
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

const String _device = '3F8A12C0B7D4';
const int _t0 = 1763251200000;

int _ms = _t0;

/// 插入一条 entry + facet 行（§5.2①/§5.2②；与账单页测试同款 fixture）。
Future<void> _insertEntryWithLines(
  cdb.AppDatabase db, {
  required String entryId,
  required String date,
  required String kind,
  required String title,
  required List<
      ({
        String id,
        String type,
        int amount,
        String direction,
        String? categoryId,
        String? ledgerId,
      })> lines,
}) async {
  final int entryMs = _ms;
  _ms += 1000;
  await db.into(db.entries).insert(
        cdb.Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: entryMs,
          kind: kind,
          source: 'manual',
          title: title,
          note: null,
          status: 'confirmed',
          aiParseId: null,
          createdAt: entryMs,
          updatedAt: entryMs,
          deletedAt: null,
          hlc: '$entryMs:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
  int counter = 1;
  for (final ({
        String id,
        String type,
        int amount,
        String direction,
        String? categoryId,
        String? ledgerId,
      }) line
      in lines) {
    counter++;
    final int lineMs = entryMs + counter;
    await db.into(db.entryLines).insert(
          cdb.EntryLine(
            id: line.id,
            entryId: entryId,
            type: line.type,
            amount: line.amount,
            direction: line.direction,
            ledgerId: line.ledgerId,
            categoryId: line.categoryId,
            currency: line.type == 'money' ? 'CNY' : null,
            confidence: null,
            payload: null,
            correctionOf: null,
            status: 'active',
            createdAt: lineMs,
            updatedAt: lineMs,
            deletedAt: null,
            hlc: '$lineMs:000001:$_device',
            revision: 1,
            schemaVer: 1,
            deviceId: _device,
          ),
        );
  }
}

/// 放大视口让整页全部可构建（测试结束由 addTearDown 复位）。
void _enlargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpManage(
  WidgetTester tester,
  LedgerAdminRepository admin,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light),
      home: Scaffold(body: CategoryManagePage(repository: admin)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _pumpLedger(
  WidgetTester tester,
  LedgerRepository repo, {
  required DateTime briefingDate,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light),
      home: Scaffold(
        body: LedgerPage(repository: repo, briefingDate: briefingDate),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// 对话框设置目标：点开 → 输入 → 保存（§3.4 每日目标入口）。
Future<void> _setGoalViaDialog(
  WidgetTester tester,
  Finder opener,
  String input,
) async {
  await tester.tap(opener);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(ledgerGoalInputKey), input);
  await tester.tap(find.byKey(ledgerGoalSaveKey));
  await tester.pumpAndSettle();
}

/// 从 budget_snapshot 的 daily 数组按 (ledger_id, category_id) 取项
/// （§5.6⑬；顺序无关断言）。
Map<Object?, Object?> _snapshotItem(
  List<Map<Object?, Object?>> items, {
  required String? ledgerId,
  required String? categoryId,
}) {
  return items.firstWhere(
    (Map<Object?, Object?> item) =>
        item['ledger_id'] == ledgerId && item['category_id'] == categoryId,
  );
}

void main() {
  testWidgets(
    '设置每日目标 → budgets 落库 + 预算快照 + 日简报超支提示（§3.4/§5.4⑥/§5.6⑬）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性
        final cdb.DaySummaryProjection projection = cdb.DaySummaryProjection(db);
        final DriftLedgerAdminRepository admin = DriftLedgerAdminRepository(db);

        final List<cdb.Category> cats = await cdb.CategoryDao(db).getAll();
        final String catMeal =
            cats.firstWhere((cdb.Category c) => c.name == '餐饮-正餐').id;
        final String moneyId =
            (await cdb.LedgerDao(db).defaultMoneyLedger())!.id;
        final String kcalId = (await cdb.LedgerDao(db).kcalLedger())!.id;

        await _pumpManage(tester, admin);

        // 每日支出目标 ¥10（→ 1000 分，§5.1）。
        await _setGoalViaDialog(
          tester,
          find.byKey(ledgerSpendGoalSetKey),
          '10',
        );
        // 每日热量目标 2000 kcal。
        await _setGoalViaDialog(
          tester,
          find.byKey(ledgerKcalGoalSetKey),
          '2000',
        );
        // 分类级目标：「餐饮-正餐」¥5（§5.4⑥ category_id 非空）。
        await _setGoalViaDialog(
          tester,
          find.byKey(ValueKey<String>('ledger_category_goal_$catMeal')),
          '5',
        );

        // UI 值即时回显（watch 流直驱）。
        expect(find.text('¥10.00'), findsOneWidget);
        expect(find.text('2000 kcal'), findsOneWidget);
        expect(find.text('¥5.00'), findsOneWidget);

        // budgets 落库断言（period=daily，§5.4⑥）。
        final List<cdb.Budget> rows = await (db.select(db.budgets)
              ..where((t) => t.deletedAt.isNull()))
            .get();
        expect(rows.length, 3);
        expect(
          rows
              .where((cdb.Budget b) =>
                  b.ledgerId == moneyId &&
                  b.categoryId == null &&
                  b.periodType == 'daily' &&
                  b.amount == 1000)
              .length,
          1,
        );
        expect(
          rows
              .where((cdb.Budget b) =>
                  b.ledgerId == kcalId &&
                  b.categoryId == null &&
                  b.periodType == 'daily' &&
                  b.amount == 2000)
              .length,
          1,
        );
        expect(
          rows
              .where((cdb.Budget b) =>
                  b.categoryId == catMeal &&
                  b.periodType == 'daily' &&
                  b.amount == 500)
              .length,
          1,
        );

        // 当日插一笔 mixed：money 1850（餐饮-正餐）+ calorie 650。
        final DateTime today = LedgerCalendar.today();
        final String todayKey = dom.formatCalendarDay(today);
        await _insertEntryWithLines(
          db,
          entryId: 'e-today',
          date: todayKey,
          kind: 'mixed',
          title: '牛肉面',
          lines: <({String id, String type, int amount, String direction, String? categoryId, String? ledgerId})>[
            (
              id: 'l-t1',
              type: 'calorie',
              amount: 650,
              direction: 'in',
              categoryId: catMeal,
              ledgerId: kcalId,
            ),
            (
              id: 'l-t2',
              type: 'money',
              amount: 1850,
              direction: 'out',
              categoryId: catMeal,
              ledgerId: moneyId,
            ),
          ],
        );

        // 重算今日投影（§5.6⑬；recompute 读 budgets + 当日活跃行）。
        await projection.recomputeDaySummary(todayKey);

        // 预算快照断言：总支出 used=1850/remaining=-850；总热量
        // used=650/remaining=1350；分类 used=1850/remaining=-1350。
        final cdb.DaySummary summary = await (db.select(db.daySummaries)
              ..where((t) => t.date.equals(todayKey)))
            .getSingle();
        final Map<String, Object?> decoded =
            jsonDecode(summary.budgetSnapshot) as Map<String, Object?>;
        final List<Map<Object?, Object?>> items = <Map<Object?, Object?>>[
          for (final Object? raw in decoded['daily']! as List<Object?>)
            raw! as Map<Object?, Object?>,
        ];
        expect(items.length, 3);
        final Map<Object?, Object?> moneyItem = _snapshotItem(
          items,
          ledgerId: moneyId,
          categoryId: null,
        );
        expect(moneyItem['amount'], 1000);
        expect(moneyItem['used'], 1850);
        expect(moneyItem['remaining'], -850);
        final Map<Object?, Object?> kcalItem = _snapshotItem(
          items,
          ledgerId: kcalId,
          categoryId: null,
        );
        expect(kcalItem['amount'], 2000);
        expect(kcalItem['used'], 650);
        expect(kcalItem['remaining'], 1350);
        final Map<Object?, Object?> categoryItem = _snapshotItem(
          items,
          ledgerId: moneyId,
          categoryId: catMeal,
        );
        expect(categoryItem['amount'], 500);
        expect(categoryItem['used'], 1850);
        expect(categoryItem['remaining'], -1350);

        // 日简报超支提示（§3.4）：总支出超 ¥8.50、分类超 ¥13.50、
        // 热量未超 → 还能吃 1350 kcal；无「预算余」文案。
        final DriftLedgerRepository repo = DriftLedgerRepository(db);
        await _pumpLedger(tester, repo, briefingDate: today);
        expect(find.textContaining('超支 ¥8.50'), findsOneWidget);
        expect(find.textContaining('超支 ¥13.50'), findsOneWidget);
        expect(find.textContaining('还能吃 1350 kcal'), findsOneWidget);
        expect(find.textContaining('预算余'), findsNothing);
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，分类管理 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );

  testWidgets(
    '分类增删改：自定义分类可建可改可删，内置分类不可删（§5.4⑤）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle();
        final DriftLedgerAdminRepository admin = DriftLedgerAdminRepository(db);
        final List<cdb.Category> cats = await cdb.CategoryDao(db).getAll();
        final String catMeal =
            cats.firstWhere((cdb.Category c) => c.name == '餐饮-正餐').id;

        await _pumpManage(tester, admin);

        // 新建「摄影」（expense 缺省 + 首个语义 token 缺省）。
        await tester.tap(find.byKey(ledgerCategoryCreateKey));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ledgerCategoryNameFieldKey),
          '摄影',
        );
        await tester.tap(find.byKey(ledgerCategoryDialogSaveKey));
        await tester.pumpAndSettle();

        final cdb.Category? created = await (db.select(db.categories)
              ..where((t) => t.name.equals('摄影')))
            .getSingleOrNull();
        expect(created, isNotNull);
        expect(created!.kind, 'expense');
        expect(created.isPreset, false);
        expect(created.deletedAt, isNull);
        expect(find.text('摄影'), findsOneWidget);

        // 重命名「摄影」→「摄影器材」（编辑对话框预填原名）。
        await tester.tap(
          find.byKey(ValueKey<String>('ledger_category_edit_${created.id}')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(ledgerCategoryNameFieldKey),
          '摄影器材',
        );
        await tester.tap(find.byKey(ledgerCategoryDialogSaveKey));
        await tester.pumpAndSettle();
        final cdb.Category? renamed = await (db.select(db.categories)
              ..where((t) => t.id.equals(created.id)))
            .getSingleOrNull();
        expect(renamed!.name, '摄影器材');
        expect(find.text('摄影器材'), findsOneWidget);

        // 删除「摄影器材」（确认弹窗 → 软删墓碑 §5.1）。
        await tester.tap(
          find.byKey(ValueKey<String>('ledger_category_delete_${created.id}')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ledgerCategoryConfirmDeleteKey));
        await tester.pumpAndSettle();
        final cdb.Category? tombstoned = await (db.select(db.categories)
              ..where((t) => t.id.equals(created.id)))
            .getSingleOrNull();
        expect(tombstoned!.deletedAt, isNotNull);
        expect(find.text('摄影器材'), findsNothing);

        // 内置分类：无删除入口，仓库层同样硬校验（§5.4⑤ is_preset）。
        expect(
          find.byKey(ValueKey<String>('ledger_category_delete_$catMeal')),
          findsNothing,
        );
        await expectLater(
          admin.softDeleteCategory(catMeal),
          throwsStateError,
        );
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，分类管理 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );
}
