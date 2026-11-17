/// 仪表盘真页 widget 测试（§3.2、§11.1 W2 验收线：手动记一笔→仪表盘环/
/// 支出卡即时更新）。
///
/// 流程：内存真库 → 插入含热量与金额行的 entry → recomputeDay 重建投影 →
/// pump DashboardPage（构造注入 DriftDashboardRepository，§10.4）→ 断言
/// 热量环/支出卡显示对应数值 → 点选周历另一天断言共享轴切日（§9.3#2）。
/// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟测试同一守卫）。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:ui_kit/ui_kit.dart';

bool _isSqliteLibraryMissing(Object error) {
  final String msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

const String _device = '3F8A12C0B7D4';
const int _t0 = 1763251200000;

Future<void> _insertEntryWithFacetLines(
  AppDatabase db, {
  required String entryId,
  required String date,
  required String kind,
  required List<({String id, String type, int amount, String direction})> lines,
}) async {
  await db
      .into(db.entries)
      .insert(
        Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: _t0,
          kind: kind,
          source: 'manual',
          title: '一碗牛肉面',
          note: null,
          status: 'confirmed',
          aiParseId: null,
          createdAt: _t0,
          updatedAt: _t0,
          deletedAt: null,
          hlc: '000$_t0:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
  for (final ({String id, String type, int amount, String direction}) line
      in lines) {
    await db
        .into(db.entryLines)
        .insert(
          EntryLine(
            id: line.id,
            entryId: entryId,
            type: line.type,
            amount: line.amount,
            direction: line.direction,
            ledgerId: line.type == 'money' ? 'ledger-money' : 'ledger-kcal',
            categoryId: null,
            currency: line.type == 'money' ? 'CNY' : null,
            confidence: null,
            payload: null,
            correctionOf: null,
            status: 'active',
            createdAt: _t0 + 1,
            updatedAt: _t0 + 1,
            deletedAt: null,
            hlc: '000$_t0:000002:$_device',
            revision: 1,
            schemaVer: 1,
            deviceId: _device,
          ),
        );
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  DashboardRepository repo, {
  VoidCallback? onStartCapture,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness: Brightness.light), // §8.2/§9.2：token 挂载
      home: Scaffold(
        body: DashboardPage(
          repository: repo,
          initialDate: DateTime(2026, 11, 16),
          onStartCapture: onStartCapture,
        ),
      ),
    ),
  );
  // 投影流首值 + 冷启动 spring/级联推进（§9.3#1）。
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('记一笔（热量+金额）→ recompute → 环/支出卡即时更新；点选周历切日', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性
      final DashboardRepository repo = DriftDashboardRepository(db);

      // 11-16 mixed 事件：calorie 650 + money 1850（facet 拆行 §5.2②）。
      await _insertEntryWithFacetLines(
        db,
        entryId: 'e-1',
        date: '2026-11-16',
        kind: 'mixed',
        lines: const <({String id, String type, int amount, String direction})>[
          (id: 'l-1', type: 'calorie', amount: 650, direction: 'in'),
          (id: 'l-2', type: 'money', amount: 1850, direction: 'out'),
        ],
      );
      // 11-17 expense 事件：money 500（本月累计 = 23.50 元）。
      await _insertEntryWithFacetLines(
        db,
        entryId: 'e-2',
        date: '2026-11-17',
        kind: 'expense',
        lines: const <({String id, String type, int amount, String direction})>[
          (id: 'l-3', type: 'money', amount: 500, direction: 'out'),
        ],
      );

      // §5.6 重建规则 v1：写路径落库后重算当日投影。
      await repo.recomputeDay('2026-11-16');
      await repo.recomputeDay('2026-11-17');

      await _pumpDashboard(tester, repo);

      // 日期大字（§3.2）与卡片墙取数断言。
      expect(find.text('11月16日'), findsOneWidget);
      expect(find.text('热量'), findsOneWidget);
      // 环心净热量 650（§3.2 热量环：摄入/消耗/净）。
      expect(find.text('650'), findsOneWidget);
      // 摄入行与净热量卡同示 650 kcal（§3.2 双卡口径一致）。
      expect(find.text('650 kcal'), findsNWidgets(2));
      // 支出卡：今日 ¥18.50 + 本月累计 ¥23.50（§3.2 卡片墙）。
      expect(find.text('¥18.50'), findsOneWidget);
      expect(find.text('本月累计 ¥23.50'), findsOneWidget);
      // 有记录 → 无空态引导（§3.2 空态仅当日无记录时出现）。
      expect(find.text('今天还没有记录'), findsNothing);

      // 点选周历另一天（11-17，周二）→ 共享轴切日（§9.3#2）+ 新一天快照直出。
      // （§3 定稿组合容器中月网格以 0 透明度常驻两层栈内，日号需在周条
      // SlimcaCalendarStrip 作用域内定位，避免与月格同号歧义。）
      await tester.tap(
        find.descendant(
          of: find.byType(SlimcaCalendarStrip),
          matching: find.text('17'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('11月17日'), findsOneWidget);
      expect(find.text('¥5.00'), findsOneWidget, reason: '11-17 当日支出');
      expect(find.text('本月累计 ¥23.50'), findsOneWidget, reason: '月累计跨日不变');
      expect(find.text('0'), findsOneWidget, reason: '11-17 无热量行 → 环心归零');
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，仪表盘 widget 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('空态：当日无记录时引导首次录入（§3.2）', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性
      final DashboardRepository repo = DriftDashboardRepository(db);

      int captureCalls = 0;
      await _pumpDashboard(tester, repo, onStartCapture: () => captureCalls++);

      expect(find.text('今天还没有记录'), findsOneWidget);
      expect(find.text('¥0.00'), findsOneWidget);
      expect(find.text('0'), findsOneWidget, reason: '环心净热量空态为 0');

      // 空态引导卡位于卡片墙末尾，先滚动进入视口再点击（§3.2 引导首次录入）。
      await tester.ensureVisible(find.text('立即记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即记录'));
      await tester.pumpAndSettle();
      expect(captureCalls, 1);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，仪表盘 widget 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
