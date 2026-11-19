/// 计划域页面骨架测试（计划域 IA 重设计后：L1 域管理页直测——宿主 TodayPlan
/// 页的接线 e2e 在 apps/mobile 侧）。
///
/// 内存真库（NativeDatabase.memory）；断言：
/// 1. FitnessLogPage 表单骨架渲染（10 活动/时长/体重/历史入口，§3.5）；
/// 2. SavingsPage 空库渲染空态引导（W13，§3.6），读侧 reactive 流接通；
/// 3. FitnessPlanPage 空库渲染空态引导（W14，§3.5），读侧 reactive 流接通；
///    开练入口不在本页（唯一开练入口在壳层计划 Tab「今日健身」卡，单一
///    入口纪律），训练历史入口挂在 FitnessLogPage AppBar。
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
    'FitnessLogPage 表单骨架（10 活动 × 强度档 + 时长/体重/估算 + 历史入口，§3.5）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const FitnessLogPage(),
        waitFor: find.byKey(fitnessSubmitKey),
      );
      // 表单骨架：内置 MET 表活动 chips + 时长/体重输入 + 估算值锚。
      expect(find.byKey(fitnessDurationFieldKey), findsOneWidget);
      expect(find.byKey(fitnessWeightFieldKey), findsOneWidget);
      expect(find.byKey(fitnessEstimateKey), findsOneWidget);
      expect(find.text('慢跑'), findsOneWidget);
      expect(find.text('力量训练'), findsOneWidget);
      // 训练历史入口（唯一入口挂在记录页 AppBar，§3.5）。
      expect(find.byKey(fitnessHistoryKey), findsOneWidget);
      // 归属日导航（按日查看；IconButton tooltip 断言）。
      expect(find.byTooltip('前一日'), findsOneWidget);
      expect(find.byTooltip('后一日'), findsOneWidget);
    },
  );

  testWidgets(
    'SavingsPage 空态引导（W13 全量：三种存钱法 + 投币打卡心智，§3.6/§5.5⑪⑫）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const SavingsPage(),
        waitFor: find.text('开始你的第一个存钱目标'),
      );
      expect(find.text('开始你的第一个存钱目标'), findsOneWidget);
      expect(find.textContaining('365 天挑战'), findsOneWidget);
      expect(find.textContaining('append-only'), findsOneWidget);
      // 新建目标入口（AppBar + 空态 CTA，§3.6）。
      expect(find.byKey(savingsCreateKey), findsOneWidget);
      expect(find.byKey(savingsEmptyCreateKey), findsOneWidget);
    },
  );

  testWidgets(
    'FitnessPlanPage 空态引导（W14 全量：模板/排期心智，§3.5/§5.5⑧⑨）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpPage(
        tester,
        harness,
        const FitnessPlanPage(),
        waitFor: find.text('开始你的第一个健身计划'),
      );
      expect(find.text('开始你的第一个健身计划'), findsOneWidget);
      expect(find.textContaining('按周排期'), findsOneWidget);
      // 新建计划入口（AppBar + 空态 CTA）。
      expect(find.byKey(fitnessPlanCreateKey), findsOneWidget);
      expect(find.byKey(fitnessPlanEmptyCreateKey), findsOneWidget);
      // 单一入口纪律：开练入口不在管理页（唯一在壳层「今日健身」卡排期行）。
      expect(find.text('开练'), findsNothing);
    },
  );
}
