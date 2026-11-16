// Slimca W5-6 健身手动记录 e2e（§11.1 W5-6「健身手动记录进仪表盘与净热量」、
// §3.5 健身记录与热量收支）：
//
// 计划 Tab「记录健身」→ /plan/fitness（§4.3 子路由）→ 类型+时长+身体档案
// 体重（settings，§3.5）→ MET 估算 kcal = MET × 体重kg × 时长h（±20% 口径
// 标注，§3.5）→ 保存：fitness_sessions + entries(kind=fitness, source=manual)
// + entry_lines(type=burn, direction=out) + 3 表 outbox 同事务落库（§5.5⑦
// entry_id 联动、§6.2 写路径）→ 计划卡列表与仪表盘「今日消耗/净=摄入−消耗」
// reactive stream 即时更新（§6.1 原则 3）。
//
// 测试装配与 widget_test 同口径：内存 Drift 库 + 固定 device_id HlcClock
// override（零平台通道、零真实网络——本链路纯本地）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 core_db test_support 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：与 widget_test 同口径（见其文件头注记）。
Future<db.AppDatabase?> _tryOpenMemoryDatabase() async {
  final database = db.AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    if (_isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 小步轮询等待控件出现（与 widget_test 同策略；本用例页多为有限动画，
/// 但流重发时点不定，统一轮询更稳）。
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder,
) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

void main() {
  testWidgets(
      'W5-6 健身 e2e：MET 估算记一笔 → 落库（会话+fitness 事件+burn 行+outbox）→ 仪表盘净热量即时更新',
      (WidgetTester tester) async {
    // 放大视口（与 widget_test 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，e2e 照常执行）。
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3）+ 内置账本种子（§5.4；burn 行归集 kcal 账本）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          // 与 bootstrap() 同款装配（本链路不触达 capture，保持口径一致）。
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget);

    // ── 计划 Tab → 记录健身（§4.2 三卡、§4.3 /plan/fitness）─────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('健身'), findsOneWidget);
    expect(find.textContaining('今日暂无健身记录'), findsOneWidget,
        reason: '空态引导（§2.3 步 1）');

    await tester.tap(find.byKey(const Key('plan_fitness_add')));
    await tester.pumpAndSettle();
    expect(find.textContaining('归属日'), findsOneWidget,
        reason: '归属日随仪表盘选中日（§3.2 一切围绕日期）');

    // ── 填表：有氧 30 分钟 × 体重 60kg（§3.5 身体档案缺省回填）───────
    await tester.tap(find.byKey(const ValueKey('fitness_type_cardio')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('fitness_duration_field')), '30');
    await tester.pump();
    // 体重由 bodyWeightKgProvider 缺省回填 60（settings 未设置 → 估算基线）。
    // 估算 = MET 7.0 × 60kg × 0.5h = 210 kcal（§3.5 估算式，±20% 口径标注）。
    await _pumpUntilFound(tester, find.byKey(const Key('fitness_estimate')));
    expect(find.textContaining('预计消耗 ≈ 210 kcal'), findsOneWidget);
    expect(find.textContaining('±20%'), findsOneWidget,
        reason: '§3.5 误差口径标注 P0');

    // ── 保存：同事务落库（§5.5⑦/§6.2）→ 返回计划页 ─────────────────
    await tester.tap(find.byKey(const Key('fitness_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fitness_save')), findsNothing,
        reason: '保存成功返回计划页');
    // 计划健身卡 reactive stream 即时重发（§6.1 原则 3；轮询容流重发时点）。
    await _pumpUntilFound(tester, find.text('消耗 210 kcal'));
    expect(find.text('消耗 210 kcal'), findsOneWidget);

    // ── 今天 Tab：仪表盘净热量即时更新（§3.5「消耗进运动条与净热量」）──
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.text('有氧 30 分钟'), findsOneWidget,
        reason: '今日记录卡条目（标题=类型+时长）');
    // 运动条 210（BurnCard 大数 + 热量卡指标行「消耗」两处）。
    expect(find.text('210 kcal'), findsNWidgets(2),
        reason: '消耗=MET 估算值即时入仪表盘（§11.1 W5-6 验收线）');
    expect(find.text('0 kcal'), findsOneWidget, reason: '摄入仍为 0');
    // 净 = 摄入 − 消耗 = 0 − 210 = −210（环心数字）。
    expect(find.text('-210'), findsOneWidget, reason: '净热量=摄入−消耗（§3.5）');
    expect(find.text('净 = 摄入 − 消耗'), findsOneWidget,
        reason: '净热量口径标注（W5-6 核对项）');
    expect(find.text('未设置'), findsOneWidget, reason: '预算未设置态（核对项 §4）');

    // ── 落库口径断言（§5.5⑦、§5.2①②、§6.2）───────────────────────
    final sessions = await database.select(database.fitnessSessions).get();
    expect(sessions.length, 1);
    final session = sessions.single;
    expect(session.type, 'cardio');
    expect(session.durationS, 1800, reason: '时长落库存秒（§5.5⑦ duration_s）');
    expect(session.kcalBurn, 210, reason: 'MET 估算消耗（§3.5）');
    expect(session.source, 'manual', reason: '手动记录（§5.5⑦ source）');
    expect(session.entryId, isNotNull,
        reason: '会话与事件同事务联动（§5.5⑦ entry_id）');

    final entries = await database.select(database.entries).get();
    expect(entries.length, 1);
    final entry = entries.single;
    expect(entry.kind, 'fitness', reason: 'fitness 事件（§5.2①）');
    expect(entry.source, 'manual');
    expect(entry.status, 'confirmed', reason: '手动路径即 confirmed');
    expect(entry.title, '有氧 30 分钟', reason: '标题缺省=类型+时长（§5.2①）');
    expect(entry.id, session.entryId, reason: 'entry_id 联动一致（§5.5⑦）');

    final lines = await database.select(database.entryLines).get();
    expect(lines.length, 1);
    final burn = lines.single;
    expect(burn.type, 'burn');
    expect(burn.amount, 210);
    expect(burn.direction, 'out', reason: 'burn=out（§5.2②）');
    expect(burn.confidence, isNull,
        reason: '人工估算行无 AI 置信度（§5.2②）');
    expect(burn.ledgerId, isNotNull, reason: 'burn 行归集内置 kcal 账本');
    final payload = jsonDecode(burn.payload!) as Map<String, Object?>;
    expect(payload['session_id'], session.id, reason: 'burn 行 payload 记 session_id');
    expect(payload['met'], 7.0, reason: '有氧 MET 7.0（§3.5 MET 表）');
    expect(payload['weight_kg'], 60.0, reason: '身体档案体重进 payload');

    final outboxRows = await database.select(database.syncOutbox).get();
    expect(outboxRows.length, 3,
        reason: 'fitness_sessions/entries/entry_lines 三行同事务入队（§6.2）');
    expect(
      outboxRows.map((r) => r.targetTable),
      unorderedEquals(['fitness_sessions', 'entries', 'entry_lines']),
    );

    final settingRows =
        await (database.select(database.settings)
              ..where((s) => s.key.equals('body_weight_kg')))
            .get();
    expect(settingRows.length, 1, reason: '身体档案体重落 settings（§3.5/§5.6⑲）');
    expect(
      double.tryParse(settingRows.single.value.replaceAll('"', '').trim()),
      60.0,
    );
  });
}
