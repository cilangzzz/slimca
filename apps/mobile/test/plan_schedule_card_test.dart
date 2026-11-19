// W14 健身计划排期卡 e2e（§11.2 W14 任务 1「计划 Tab 接健身计划入口
// （计划列表/今日排期卡）」+ 任务 4「仪表盘训练中态卡（剩余休息秒，读
// Riverpod provider）」+ 任务 2/3 副作用链验收）。
//
// 链路：种子 fitness_plans（§5.5⑧ 掩码排期）→ 计划 Tab 健身计划卡渲染
// （今日排期段/计划列表段分流）→「开始训练」→ /plan/workout 训练中页 →
// 完成一组 → 组间休息（注入时钟推进，禁真实计时器）→ 仪表盘训练中态卡
// 剩余秒即时重算 → 跳过休息 → 结束并保存 → 落库（会话+组明细+outbox）。
//
// 测试装配（widget_test 同口径）：内存 Drift 库 + 固定 device_id HlcClock
// override；KeepAwake/常驻通知注入 Fake 记录调用（禁真实平台通道）；训练
// 时钟注入可控时钟（workoutClockProvider override）；遥测注入 Recording
// 遥测。Windows 宿主缺 sqlite3 运行库时温和跳过（widget_test 同口径）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/dashboard/today_dashboard_page.dart'
    show workoutCardEndKey, workoutCardRestKey, workoutCardSkipRestKey;
import 'package:slimca/features/plan/plan_page.dart'
    show planWorkoutCardKey, planWorkoutStartKey;
import 'package:slimca/features/workout/workout_runner_page.dart'
    show workoutLogSetKey, workoutRestRemainingKey;
import 'package:slimca/main.dart';
import 'package:slimca/telemetry/w14_funnel_events.dart';
import 'package:slimca/workout/fake_keep_awake_service.dart';
import 'package:slimca/workout/fake_workout_timer_notifier.dart';
import 'package:slimca/workout/rest_timer_notifier.dart';

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（widget_test 同口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to dynamic library') ||
      msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
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

/// 种子健身计划行（§5.5⑧；掩码按 weekday 计算，今日/明日各一）。
Future<db.FitnessPlan> _insertPlan(
  db.AppDatabase database,
  HlcClock clock, {
  required String id,
  required String name,
  required int weekdayMask,
}) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final plan = db.FitnessPlan(
    id: id,
    name: name,
    weekdayMask: weekdayMask,
    exercises: jsonEncode([
      {
        'name': '杠铃卧推',
        'sets': 3,
        'target_reps': 10,
        'target_weight_kg_x10': 400,
        'rest_s': 90,
      },
      {
        'name': '哑铃肩推',
        'sets': 2,
        'target_reps': 12,
        'target_weight_kg_x10': 125,
        'rest_s': 60,
      },
    ]),
    startDate: '2026-01-01',
    active: true,
    createdAt: nowMs,
    updatedAt: nowMs,
    deletedAt: null,
    hlc: clock.now().format(),
    revision: 1,
    schemaVer: kCurrentSchemaVer,
    deviceId: clock.deviceId,
  );
  await database.into(database.fitnessPlans).insert(plan);
  return plan;
}

void main() {
  testWidgets(
      'W14 e2e：排期卡渲染分流 → 开始训练 → 组间休息（注入时钟）→ 仪表盘'
      '训练中态卡剩余秒 → 结束并保存落库', (WidgetTester tester) async {
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

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);
    // seed 行（账本/分类/settings）随建库/种子同事务入队 sync_outbox——本
    // 用例只断言 W14 训练写路径的出网行，先清空 seed 出网项（与
    // e2e_fitness_to_dashboard_test 同口径）。
    await database.delete(database.syncOutbox).go();

    // 种子两计划：A=今日排期（掩码命中今日 weekday），B=明日（今日不出现，
    // 只进「计划」列表段）。掩码 bit0=周一…bit6=周日（§5.5⑧）。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final planA = await _insertPlan(
      database,
      clock,
      id: 'plan-w14-a',
      name: '三分化 · 推日',
      weekdayMask: 1 << (today.weekday - 1),
    );
    await _insertPlan(
      database,
      clock,
      id: 'plan-w14-b',
      name: '二分化 · 腿日',
      weekdayMask: 1 << (today.add(const Duration(days: 1)).weekday - 1),
    );

    // W14 装配（与 bootstrap() 同款，副作用注入 Fake + 注入时钟）。
    final keepAwake = FakeKeepAwakeService();
    final notifier = FakeWorkoutTimerNotifier();
    final telemetry = RecordingTelemetryService();
    // 注入时钟锚点（与真实日历日解耦：只服务剩余秒/时长判定，W14 任务 5）。
    var fakeNow = DateTime(now.year, now.month, now.day, 18, 30);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          keepAwakeProvider.overrideWithValue(keepAwake),
          workoutTimerNotifierProvider.overrideWithValue(notifier),
          telemetryServiceProvider.overrideWithValue(telemetry),
          workoutClockProvider.overrideWithValue(() => fakeNow),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsNothing,
        reason: '完整壳已起（首页 AppBar 无产品名标题，用户拍板移除）');

    // ── 计划 Tab：今日健身卡（§11.2 W14 任务 1；IA 重设计后卡尾「健身计划」
    //    为唯一模板入口）───────────────────────────────────────────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.byKey(planWorkoutCardKey), findsOneWidget);
    expect(find.text('健身计划'), findsOneWidget);

    // 排期分流：A 命中今日 → 排期行（计划列表段已下沉 /plan/plans，单现）；
    // B 不命中今日 → 不出现排期行、无其「开始训练」按钮。
    expect(find.text('三分化 · 推日'), findsOneWidget);
    expect(find.text('二分化 · 腿日'), findsNothing);
    expect(find.byKey(planWorkoutStartKey(planA.id)), findsOneWidget);
    expect(find.byKey(planWorkoutStartKey('plan-w14-b')), findsNothing);

    // ── 开始训练：副作用链（W14 任务 2/3）+ 训练中页 ─────────────────
    await tester.tap(find.byKey(planWorkoutStartKey(planA.id)));
    await tester.pumpAndSettle();

    // 开练 → KeepAwake.on（W14 任务 5 核心断言）+ 常驻通知 + workout_started。
    expect(keepAwake.calls, ['enable']);
    expect(notifier.shown.length, 1);
    expect(notifier.lastShown!.title, '训练进行中');
    expect(
      telemetry.byName(W14TelemetryFunnel.workoutStarted).length,
      1,
    );

    // 训练中页（§4.3 /plan/workout）：动作进度 + 完成一组入口。
    expect(find.textContaining('训练中 · 三分化'), findsOneWidget);
    expect(find.byKey(workoutLogSetKey), findsOneWidget);
    expect(find.textContaining('杠铃卧推'), findsWidgets);

    // ── 完成一组 → 组间休息（原生倒计时通知 + 页内剩余秒 90）──────────
    await tester.tap(find.byKey(workoutLogSetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final restNotice = notifier.lastShown!;
    expect(restNotice.title, '组间休息');
    expect(restNotice.chronometerEndsAtMs,
        isNotNull, reason: '通知挂原生倒计时（锁屏仍走秒的展示半边）');
    expect(find.byKey(workoutRestRemainingKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(workoutRestRemainingKey)).data, '90');

    // ── 仪表盘训练中态卡（W14 任务 4：读 Riverpod provider）────────────
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('训练中 · 三分化'), findsOneWidget);
    expect(find.byKey(workoutCardRestKey), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(workoutCardRestKey)).data, '90');

    // 剩余秒即时重算（注入时钟推进 30s + pump 让每秒 tick 重绘；禁真实计时器）。
    fakeNow = fakeNow.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Text>(find.byKey(workoutCardRestKey)).data, '60',
        reason: '剩余秒=注入时钟对 rest_ends_at 的重算（锁屏可跑语义）');

    // 跳过休息 → 回「当前动作」态（卡片横幅消失）。
    await tester.tap(find.byKey(workoutCardSkipRestKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(workoutCardRestKey), findsNothing);
    expect(find.textContaining('当前：杠铃卧推'), findsOneWidget);

    // ── 结束并保存（W14 任务 5 断言 off）→ 落库（§5.5⑦⑨/§6.2）─────────
    await tester.tap(find.byKey(workoutCardEndKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));

    // 结束 → KeepAwake.off + 常驻通知 cancel + workout_completed。
    expect(keepAwake.calls, ['enable', 'disable']);
    expect(keepAwake.isEnabled, isFalse);
    expect(notifier.cancelled, [kWorkoutTimerNotificationId]);
    expect(
      telemetry.byName(W14TelemetryFunnel.setLogged).length,
      1,
    );
    expect(
      telemetry.byName(W14TelemetryFunnel.workoutCompleted).length,
      1,
    );

    // 训练中态卡消失（§2.3 瞬时项）。
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('训练中 · 三分化'), findsNothing);

    // 落库口径：会话（template_instance/plan）+ 事件 + burn 行 + 1 组明细 +
    // 4 行 outbox 全量同事务（§6.2）。
    final sessions = await database.select(database.fitnessSessions).get();
    expect(sessions.length, 1);
    expect(sessions.single.type, 'template_instance');
    expect(sessions.single.source, 'plan');
    expect(sessions.single.planDayId, planA.id);

    final sets = await database.select(database.exerciseSets).get();
    expect(sets.length, 1);
    expect(sets.single.exerciseRef, '杠铃卧推');
    expect(sets.single.weightKgX10, 400, reason: '40kg ×10 定点（§5.5⑨）');
    expect(sets.single.restS, 90);
    expect(sets.single.sessionId, sessions.single.id);

    final outbox = await database.select(database.syncOutbox).get();
    final byTable = <String, int>{};
    for (final row in outbox) {
      byTable[row.targetTable] = (byTable[row.targetTable] ?? 0) + 1;
    }
    expect(byTable, {
      'fitness_sessions': 1,
      'entries': 1,
      'entry_lines': 1,
      'exercise_sets': 1,
    });

    // ── 回计划 Tab：分支栈仍在训练中页（训练已结束 → 空态防御分支）──────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('没有进行中的训练'), findsOneWidget,
        reason: '训练结束态下 /plan/workout 呈空态（无进行中训练，§11.2 W14）');
  });
}
