/// 计划域页面骨架测试（§4.2 计划 Tab 三卡 + W5-6 占位页验收）。
///
/// 内存真库（NativeDatabase.memory）；断言：
/// 1. PlanHubPage 渲染 4 张入口卡（待办/健身/存钱/健身计划，§4.2）；
/// 2. SavingsPage / FitnessPlanPage 空库渲染空态引导（W13/W14 占位，
///    §3.6/§3.5），读侧 reactive 流接通不报错。
///
/// 运行前提：集成阶段已 `flutter pub get`；宿主缺 sqlite3 运行库时温和跳过。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_plan/feature_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 测试夹具：内存真库 + 注入 HlcClock + 计划域网关。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  PlanGateway? _gateway;

  cdb.AppDatabase get db => _db!;
  PlanGateway get gateway => _gateway!;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(
      // closeStreamsSynchronously：drift 流取消的清缓存 Timer 在 fake_async
      // 区无人清空会挂起测试（与 apps/mobile widget_test 同口径）。
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，页面骨架测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(deviceId: '3F8A12C0B7D4');
    _gateway = createPlanGateway(db: db, clock: _clock!);
    return true;
  }

  Future<void> close() async {
    await _db?.close();
  }
}

/// 泵任意计划域页面（ProviderScope 覆盖注入网关）。
Future<void> _pumpPage(WidgetTester tester, _Harness harness, Widget page,
    {Finder? waitFor}) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planGatewayProvider.overrideWithValue(harness.gateway),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: page,
      ),
    ),
  );
  for (var i = 0; i < 150; i++) {
    if (waitFor == null || waitFor.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $waitFor');
}

void main() {
  testWidgets(
    'PlanHubPage 渲染四张入口卡（今日待办/健身手动记录/存钱目标/健身计划，§4.2）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const PlanHubPage(),
        waitFor: find.text('健身手动记录'),
      );
      expect(find.text('今日待办'), findsOneWidget);
      expect(find.text('健身手动记录'), findsOneWidget);
      expect(find.text('存钱目标'), findsOneWidget);
      expect(find.text('健身计划'), findsOneWidget);
      // W13/W14 占位文案（§3.6/§3.5 P1 钩子）。
      expect(find.text('W13 上线（§3.6 P1）'), findsOneWidget);
      expect(find.text('W14 上线（§3.5 P1）'), findsOneWidget);
    },
  );

  testWidgets(
    'SavingsPage 空态引导（W13 占位；读侧 reactive 流接通，§3.6/§5.5⑪⑫）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const SavingsPage(),
        waitFor: find.text('存钱目标 W13 上线'),
      );
      expect(find.text('存钱目标 W13 上线'), findsOneWidget);
      expect(find.textContaining('savings_goals'), findsOneWidget);
    },
  );

  testWidgets(
    'FitnessPlanPage 空态引导（W14 占位；读侧 reactive 流接通，§3.5/§5.5⑧）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const FitnessPlanPage(),
        waitFor: find.text('健身计划 W14 上线'),
      );
      expect(find.text('健身计划 W14 上线'), findsOneWidget);
      expect(find.textContaining('fitness_sessions'), findsOneWidget);
    },
  );
}
