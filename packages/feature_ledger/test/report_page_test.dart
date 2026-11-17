/// 统计报表页 widget 测试（§3.4 统计报表、§11.2 W15「周/月/年+钱-热量
/// 双轴联动视图」验收线）。
///
/// 任务口径「双轴联动选中状态」：点击双轴面板的某桶 → 详情条显示该桶
/// 日期/金额/热量（两轴高亮本体是画布高亮带，此处以共享选中态的可观察
/// 出口——详情条——断言联动）；点热量折线同桶 → 选中态跨面板同步（联动）；
/// 同桶再点 → 反选清除。另覆盖周期三档切换与档位标题。
///
/// 流程：内存真库（seed 内置账本/分类）→ 直插 11 月固定流水 → pump
/// ReportPage（构造注入 DriftReportRepository，§10.4）→ 按坐标点桶断言。
/// Windows 宿主缺 sqlite3 运行库时温和跳过。无真实网络/平台通道（§10.5）。
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
int _ms = 1763251200000;

/// 插入一条 entry + 单行 money-out facet（§5.2①②）。
Future<void> _insertSpend(
  cdb.AppDatabase db, {
  required String entryId,
  required String date,
  required String title,
  required int amountMinor,
}) async {
  final cdb.Ledger money = (await cdb.LedgerDao(db).defaultMoneyLedger())!;
  final cdb.Category meal = (await cdb.CategoryDao(db).getAll())
      .firstWhere((c) => c.name == '餐饮-正餐');
  final int entryMs = _ms;
  _ms += 1000;
  await db.into(db.entries).insert(
        cdb.Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: entryMs,
          kind: 'expense',
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
  final int lineMs = entryMs + 2;
  await db.into(db.entryLines).insert(
        cdb.EntryLine(
          id: '$entryId-l1',
          entryId: entryId,
          type: 'money',
          amount: amountMinor,
          direction: 'out',
          ledgerId: money.id,
          categoryId: meal.id,
          currency: 'CNY',
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

/// 插入一条 calorie-in 行（kcal 账本；§5.2②）。
Future<void> _insertKcal(
  cdb.AppDatabase db, {
  required String entryId,
  required String date,
  required int kcal,
}) async {
  final cdb.Ledger kcalLedger = (await cdb.LedgerDao(db).kcalLedger())!;
  final int entryMs = _ms;
  _ms += 1000;
  await db.into(db.entries).insert(
        cdb.Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: entryMs,
          kind: 'food',
          source: 'manual',
          title: 'kcal 事件 $entryId',
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
  final int lineMs = entryMs + 2;
  await db.into(db.entryLines).insert(
        cdb.EntryLine(
          id: '$entryId-l1',
          entryId: entryId,
          type: 'calorie',
          amount: kcal,
          direction: 'in',
          ledgerId: kcalLedger.id,
          categoryId: null,
          currency: null,
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

/// 放大视口让报表页全量可构建（ListView 懒构建裁剪问题）。
void _enlargeViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pumpReport(
  WidgetTester tester,
  ReportRepository repo, {
  ReportPeriod period = ReportPeriod.month,
  // 锚点缺省固定日（测试确定性；DateTime 无 const 构造，用可空+回退）。
  DateTime? anchor,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light), // §8.2/§9.2 token 挂载
      home: Scaffold(
        body: ReportPage(
          repository: repo,
          initialPeriod: period,
          initialAnchor: anchor ?? DateTime(2026, 11, 20),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// 点图表（按 key 定位）的第 [index] 个桶（月档 11 月：index i → 11 月 i+1 日）。
/// 命中换算与画笔共用 _ChartGeometry.padding=12 的布桶几何（report_page.dart）。
Future<void> _tapBucket(
  WidgetTester tester,
  String chartKey,
  int index, {
  int bucketCount = 30,
}) async {
  final Rect rect = tester.getRect(find.byKey(ValueKey<String>(chartKey)));
  const double padding = 12;
  final double slot = (rect.width - padding * 2) / bucketCount;
  final double dx = rect.left + padding + slot * (index + 0.5);
  await tester.tapAt(Offset(dx, rect.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('双轴联动选中状态：点桶 → 详情条联动；跨面板同步；反选清除',
      (WidgetTester tester) async {
    _enlargeViewport(tester);
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();

      // 固定种子：11-03 支出 ¥12.00、11-06 支出 ¥30.00 + 摄入 650 kcal。
      await _insertSpend(db,
          entryId: '0196a7e0-0000-7000-8000-00000000d001',
          date: '2026-11-03', title: '11-3 午饭', amountMinor: 1200);
      await _insertSpend(db,
          entryId: '0196a7e0-0000-7000-8000-00000000d002',
          date: '2026-11-06', title: '11-6 晚饭', amountMinor: 3000);
      await _insertKcal(db,
          entryId: '0196a7e0-0000-7000-8000-00000000d003',
          date: '2026-11-06', kcal: 650);

      final DriftReportRepository repo = DriftReportRepository(db);
      await _pumpReport(tester, repo, period: ReportPeriod.month);

      // 未选中：详情条为引导文案（联动关闭态）。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('点任一图元'),
        ),
        findsOneWidget,
      );

      // 1) 点双轴面板第 3 桶（11-03）→ 详情条显示该日支出（联动高亮的
      //    数字出口；§11.2「点击日期联动两轴高亮」）。
      await _tapBucket(tester, 'report_dual_axis', 2);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('11月3日'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('¥12.00'),
        ),
        findsOneWidget,
      );

      // 2) 点热量折线面板第 6 桶（11-06）→ 选中态跨面板同步（三卡共享
      //    选中态，§3.4 双轴联动语义）。
      await _tapBucket(tester, 'report_kcal_chart', 5);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('11月6日'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('¥30.00'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('摄入 650'),
        ),
        findsOneWidget,
      );

      // 3) 同桶再点 = 反选：详情条回落引导文案（两轴高亮同步清除）。
      await _tapBucket(tester, 'report_dual_axis', 5);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('点任一图元'),
        ),
        findsOneWidget,
      );
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，报表页联动测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('周期三档切换：标题与桶轴随档位变化（§3.4 周/月/年）',
      (WidgetTester tester) async {
    _enlargeViewport(tester);
    final cdb.AppDatabase db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      await _insertSpend(db,
          entryId: '0196a7e0-0000-7000-8000-00000000e001',
          date: '2026-11-17', title: '本周花销', amountMinor: 4400);
      final DriftReportRepository repo = DriftReportRepository(db);
      // 锚点 2026-11-20（周五）：周档=11-16(周一)~11-22(周日)。
      await _pumpReport(tester, repo, period: ReportPeriod.month);

      // 月档标题。
      expect(find.text('2026年11月'), findsOneWidget);
      // 切周档 → 周标题（11月16日 - 11月22日）。
      await tester.tap(find.byKey(const ValueKey<String>('report_period_week')));
      await tester.pumpAndSettle();
      expect(find.text('11月16日 - 11月22日'), findsOneWidget);
      // 周档桶数=7：详情条选中第 2 桶（11-17，本周花销）。
      await _tapBucket(tester, 'report_dual_axis', 1, bucketCount: 7);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('11月17日'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('report_detail_strip')),
          matching: find.textContaining('¥44.00'),
        ),
        findsOneWidget,
      );

      // 切年档 → 年标题（2026年）。
      await tester.tap(find.byKey(const ValueKey<String>('report_period_year')));
      await tester.pumpAndSettle();
      expect(find.text('2026年'), findsOneWidget);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，报表页周期切换测试未执行');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
