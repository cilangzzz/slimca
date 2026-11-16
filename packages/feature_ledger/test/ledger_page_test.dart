/// 账本页 widget 测试（§11.1 W5-6 验收线：插多日多类记录 → 断言按日
/// 分组列表 / 分类筛选 / 分类汇总数字；月份切换空态；编辑入口回调）。
///
/// 流程：内存真库（beforeOpen 自动 seed 内置账本 + 22 条内置分类）→
/// 直接插 entry + facet 行 → pump LedgerPage（构造注入
/// DriftLedgerRepository，§10.4）→ 断言分组/合计/汇总 → 点选筛选与
/// 切月断言。Windows 宿主缺 sqlite3 运行库时温和跳过（与 feature_
/// dashboard widget 测试同一守卫）。无真实网络/平台通道（§10.5）。
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

const String _device = '3F8A12C0B7D4';
const int _t0 = 1763251200000;

/// 行级 hlc 单调递增（§6.3 全序；raw 直插不经时钟，测试内自增保证唯一）。
int _ms = _t0;

/// 插入一条 entry + facet 行（§5.2①/§5.2②；date 为本地自然日文本）。
Future<void> _insertEntryWithLines(
  cdb.AppDatabase db, {
  required String entryId,
  required String date,
  required String kind,
  required String title,
  String status = 'confirmed',
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
          status: status,
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

/// 多日多类固定种子（2026-11）：11-16 两笔、11-18 一笔、11-20 一笔收入。
/// 返回分类名 → id 映射（断言筛选用）。
Future<Map<String, String>> _seedNovember(cdb.AppDatabase db) async {
  final List<cdb.Category> cats = await cdb.CategoryDao(db).getAll();
  final Map<String, String> byName = <String, String>{
    for (final cdb.Category category in cats) category.name: category.id,
  };
  final String catMeal = byName['餐饮-正餐']!;
  final String catTraffic = byName['交通']!;
  final String catEdu = byName['教育']!;
  final String catSalary = byName['工资']!;
  final String moneyId = (await cdb.LedgerDao(db).defaultMoneyLedger())!.id;
  final String kcalId = (await cdb.LedgerDao(db).kcalLedger())!.id;

  // 11-16 mixed：calorie 650（挂餐饮子类 §5.2②）+ money 1850。
  await _insertEntryWithLines(
    db,
    entryId: 'e-1',
    date: '2026-11-16',
    kind: 'mixed',
    title: '牛肉面',
    lines: <({String id, String type, int amount, String direction, String? categoryId, String? ledgerId})>[
      (
        id: 'l-1',
        type: 'calorie',
        amount: 650,
        direction: 'in',
        categoryId: catMeal,
        ledgerId: kcalId,
      ),
      (
        id: 'l-2',
        type: 'money',
        amount: 1850,
        direction: 'out',
        categoryId: catMeal,
        ledgerId: moneyId,
      ),
    ],
  );
  // 11-16 expense：地铁 ¥4.00。
  await _insertEntryWithLines(
    db,
    entryId: 'e-2',
    date: '2026-11-16',
    kind: 'expense',
    title: '地铁通勤',
    lines: <({String id, String type, int amount, String direction, String? categoryId, String? ledgerId})>[
      (
        id: 'l-3',
        type: 'money',
        amount: 400,
        direction: 'out',
        categoryId: catTraffic,
        ledgerId: moneyId,
      ),
    ],
  );
  // 11-18 expense：书 ¥68.00。
  await _insertEntryWithLines(
    db,
    entryId: 'e-3',
    date: '2026-11-18',
    kind: 'expense',
    title: '买参考书',
    lines: <({String id, String type, int amount, String direction, String? categoryId, String? ledgerId})>[
      (
        id: 'l-4',
        type: 'money',
        amount: 6800,
        direction: 'out',
        categoryId: catEdu,
        ledgerId: moneyId,
      ),
    ],
  );
  // 11-20 income：工资 +¥5,000.00（income kind 行方向 in，§2.1③）。
  await _insertEntryWithLines(
    db,
    entryId: 'e-4',
    date: '2026-11-20',
    kind: 'expense',
    title: '十一月工资',
    lines: <({String id, String type, int amount, String direction, String? categoryId, String? ledgerId})>[
      (
        id: 'l-5',
        type: 'money',
        amount: 500000,
        direction: 'in',
        categoryId: catSalary,
        ledgerId: moneyId,
      ),
    ],
  );
  return byName;
}

/// 放大视口让整月列表全部可构建（ListView 懒构建会裁掉视口外子树，
/// 断言需要全量渲染）。测试结束由 addTearDown 复位。
void _enlargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpLedger(
  WidgetTester tester,
  LedgerRepository repo, {
  DateTime? month,
  DateTime? briefingDate,
  void Function(String entryId)? onEditEntry,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light), // §8.2/§9.2 token 挂载
      home: Scaffold(
        body: LedgerPage(
          repository: repo,
          initialMonth: month,
          briefingDate: briefingDate,
          onEditEntry: onEditEntry,
        ),
      ),
    ),
  );
  // watch 流首值 + 冷启动级联上浮（§9.3#1）。
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '多日多类记录 → 按日分组列表、日合计与月度分类汇总（§3.4）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性
        await _seedNovember(db);
        final DriftLedgerRepository repo = DriftLedgerRepository(db);

        await _pumpLedger(
          tester,
          repo,
          month: DateTime(2026, 11, 16),
          // 简报日选无投影行的 11-30 → 零值卡，与账单数据解耦（确定性）。
          briefingDate: DateTime(2026, 11, 30),
        );

        // 月份切换条（§3.4）。
        expect(find.text('2026年11月'), findsOneWidget);
        // 按日分组头（日期降序；§5.1 本地自然日 + 周几）。
        expect(find.text('11月16日 周一'), findsOneWidget);
        expect(find.text('11月18日 周三'), findsOneWidget);
        expect(find.text('11月20日 周五'), findsOneWidget);

        // 11-16 分组：两笔账 + 当日合计（18.50 + 4.00 = 22.50）。
        final Finder day16 =
            find.byKey(const ValueKey<String>('ledger_day_2026-11-16'));
        expect(find.descendant(of: day16, matching: find.text('牛肉面')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('地铁通勤')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('¥18.50')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('¥4.00')),
            findsOneWidget);
        // mixed 账副题：分类名 + 热量（§5.2② 分类/热量挂在行上）。
        expect(
            find.descendant(
                of: day16, matching: find.text('餐饮-正餐 · 650 kcal')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('支出 ¥22.50')),
            findsOneWidget);

        // 11-18 / 11-20 分组。
        final Finder day18 =
            find.byKey(const ValueKey<String>('ledger_day_2026-11-18'));
        expect(find.descendant(of: day18, matching: find.text('买参考书')),
            findsOneWidget);
        expect(find.descendant(of: day18, matching: find.text('支出 ¥68.00')),
            findsOneWidget);
        final Finder day20 =
            find.byKey(const ValueKey<String>('ledger_day_2026-11-20'));
        expect(find.descendant(of: day20, matching: find.text('十一月工资')),
            findsOneWidget);
        expect(
            find.descendant(of: day20, matching: find.text('+¥5,000.00')),
            findsOneWidget);
        expect(find.descendant(of: day20, matching: find.text('收入 +¥5,000.00')),
            findsOneWidget);

        // 月度分类汇总（§3.4 统计雏形；限定在汇总卡内断言，避免与
        // 账单行同名文本歧义）。
        final Finder summary =
            find.byKey(const ValueKey<String>('ledger_summary_card'));
        expect(
            find.descendant(of: summary, matching: find.text('餐饮-正餐')),
            findsOneWidget);
        expect(
            find.descendant(of: summary, matching: find.text('¥18.50')),
            findsOneWidget);
        expect(find.descendant(of: summary, matching: find.text('交通')),
            findsOneWidget);
        expect(find.descendant(of: summary, matching: find.text('¥4.00')),
            findsOneWidget);
        expect(find.descendant(of: summary, matching: find.text('教育')),
            findsOneWidget);
        expect(find.descendant(of: summary, matching: find.text('¥68.00')),
            findsOneWidget);
        expect(find.descendant(of: summary, matching: find.text('工资')),
            findsOneWidget);
        expect(
            find.descendant(of: summary, matching: find.text('+¥5,000.00')),
            findsOneWidget);

        // 简报日（11-30）无投影行 → 零值 + 引导（§5.6⑬ 本地件只读）。
        expect(find.text('当日暂无记录'), findsOneWidget);
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，账本页 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );

  testWidgets(
    '分类筛选 → 列表与日合计按类过滤，汇总保持全月口径（§3.4）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle();
        final Map<String, String> byName = await _seedNovember(db);
        final String catTraffic = byName['交通']!;
        final DriftLedgerRepository repo = DriftLedgerRepository(db);

        await _pumpLedger(
          tester,
          repo,
          month: DateTime(2026, 11, 16),
          briefingDate: DateTime(2026, 11, 30),
        );

        // 点选「交通」chip（其余分类的账被过滤出列表，§3.4 分类筛选）。
        await tester
            .tap(find.byKey(ValueKey<String>('ledger_filter_$catTraffic')));
        await tester.pumpAndSettle();

        // 11-16 只剩地铁一笔，日合计重算为 ¥4.00。
        final Finder day16 =
            find.byKey(const ValueKey<String>('ledger_day_2026-11-16'));
        expect(find.descendant(of: day16, matching: find.text('地铁通勤')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('牛肉面')),
            findsNothing);
        expect(find.descendant(of: day16, matching: find.text('支出 ¥4.00')),
            findsOneWidget);
        // 无命中行的日子整节消失。
        expect(
            find.byKey(const ValueKey<String>('ledger_day_2026-11-18')),
            findsNothing);
        expect(
            find.byKey(const ValueKey<String>('ledger_day_2026-11-20')),
            findsNothing);
        // 汇总卡不受筛选影响（全月口径，§3.4 统计雏形）。
        final Finder summary =
            find.byKey(const ValueKey<String>('ledger_summary_card'));
        expect(
            find.descendant(of: summary, matching: find.text('¥18.50')),
            findsOneWidget);
        expect(
            find.descendant(of: summary, matching: find.text('¥68.00')),
            findsOneWidget);

        // 点「全部」恢复完整列表。
        await tester
            .tap(find.byKey(const ValueKey<String>('ledger_filter_all')));
        await tester.pumpAndSettle();
        expect(find.descendant(of: day16, matching: find.text('牛肉面')),
            findsOneWidget);
        expect(find.descendant(of: day16, matching: find.text('支出 ¥22.50')),
            findsOneWidget);
        expect(
            find.byKey(const ValueKey<String>('ledger_day_2026-11-18')),
            findsOneWidget);
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，账本页 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );

  testWidgets(
    '月份切换 → 下一月空态引导、上一月恢复（§3.4）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle();
        await _seedNovember(db);
        final DriftLedgerRepository repo = DriftLedgerRepository(db);

        await _pumpLedger(
          tester,
          repo,
          month: DateTime(2026, 11, 16),
          briefingDate: DateTime(2026, 11, 30),
        );

        // 切到下一月（2026-12）→ 无账单 → 空态引导。
        await tester.tap(find.byIcon(Icons.chevron_right));
        await tester.pumpAndSettle();
        expect(find.text('2026年12月'), findsOneWidget);
        expect(find.text('本月还没有账单'), findsOneWidget);
        expect(
            find.byKey(const ValueKey<String>('ledger_day_2026-11-16')),
            findsNothing);

        // 切回上一月 → 数据恢复。
        await tester.tap(find.byIcon(Icons.chevron_left));
        await tester.pumpAndSettle();
        expect(find.text('2026年11月'), findsOneWidget);
        expect(find.text('牛肉面'), findsOneWidget);
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，账本页 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );

  testWidgets(
    '账单条目点按 → onEditEntry 回调（编辑走壳侧 capture 修正链 §3.3）',
    (WidgetTester tester) async {
      _enlargeViewport(tester);
      final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle();
        await _seedNovember(db);
        final DriftLedgerRepository repo = DriftLedgerRepository(db);

        String? editedEntryId;
        await _pumpLedger(
          tester,
          repo,
          month: DateTime(2026, 11, 16),
          briefingDate: DateTime(2026, 11, 30),
          onEditEntry: (String entryId) => editedEntryId = entryId,
        );

        await tester.tap(find.text('牛肉面'));
        await tester.pumpAndSettle();
        expect(editedEntryId, 'e-1');
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，账本页 widget 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    },
  );
}
