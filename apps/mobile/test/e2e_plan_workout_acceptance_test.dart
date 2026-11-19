// Slimca W14 健身计划专项验收 e2e（§11.2 W14、§3.5 健身计划 P1、§5.5⑦⑧⑨、
// §6.2 写路径纪律）：
//
// 完整链路（两路集成：feature_plan 模板建档 × 壳层排期卡/训练中态卡）：
// 新建计划模板（feature_plan FitnessPlanEditorSheet：动作/组数/重量/休息秒）
// → 排期周三 → 计划 Tab 排期卡「开始训练」（壳层 WorkoutSessionController）
// → Fake 计时完成 3 组（注入时钟推进到点 + 跳过休息，禁真实计时器）
// → 断言 exercise_sets + fitness_sessions + entries/entry_lines(burn) 行 +
//   day_summary 投影 + 四类业务行 outbox 全量同事务入队（§6.2）
// → 仪表盘净热量扣减（摄入−消耗）+ 训练中态卡消失（§2.3 瞬时项）。
//
// 测试装配（plan_schedule_card_test 同口径）：内存 Drift 库 + 固定 device_id
// HlcClock override；KeepAwake/常驻通知注入 Fake 记录调用（禁真实平台通道）；
// 训练时钟注入可控时钟（workoutClockProvider override）；遥测注入 Recording；
// 计划域网关装配（planGatewayProvider override，§10.4 壳负责装配）。
// Windows 宿主缺 sqlite3 运行库时温和跳过（widget_test 同口径）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_plan/feature_plan.dart'
    show
        createPlanGateway,
        fitnessPlanCreateKey,
        fitnessPlanExerciseNameKey,
        fitnessPlanExerciseRestKey,
        fitnessPlanExerciseSetsKey,
        fitnessPlanExerciseRepsKey,
        fitnessPlanExerciseWeightKey,
        fitnessPlanNameFieldKey,
        fitnessPlanSubmitKey,
        fitnessPlanWeekdayChipKey,
        planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/dashboard/dashboard_state.dart'
    show selectedDateProvider;
import 'package:slimca/features/dashboard/today_dashboard_page.dart'
    show workoutCardEndKey;
import 'package:slimca/features/plan/plan_page.dart'
    show PlanPage, planWorkoutStartKey, planWorkoutTemplatesKey;
import 'package:slimca/features/workout/workout_runner_page.dart'
    show workoutLogSetKey, workoutRestRemainingKey, workoutSkipRestKey;
import 'package:slimca/main.dart';
import 'package:slimca/telemetry/w14_funnel_events.dart';
import 'package:slimca/workout/fake_keep_awake_service.dart';
import 'package:slimca/workout/fake_workout_timer_notifier.dart';
import 'package:slimca/workout/rest_timer_notifier.dart'
    show kWorkoutTimerNotificationId;

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
    DatabaseConnection(
        NativeDatabase.memory(), closeStreamsSynchronously: true),
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

/// 小步轮询等待控件出现（编辑器抽屉/路由转场动画播完再交互）。
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件消失超时: $finder');
}

/// 向带 key 的 PlanTextField 输入文本（TextField 是其内部子控件）。
Future<void> _enterField(
    WidgetTester tester, Key fieldKey, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 轮询直到 [probe] 为真（落库/投影重算为异步桥接，§5.6）。
Future<void> _pumpUntilDb(
  WidgetTester tester,
  Future<bool> Function() probe,
) async {
  for (var i = 0; i < 150; i++) {
    if (await probe()) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待数据库状态超时');
}

void main() {
  testWidgets(
      'W14 专项验收：新建模板（排期周三）→ 排期卡开练 → Fake 计时完成 3 组 → '
      '落 session/组明细/entry/burn 行 + 投影 + outbox → 仪表盘净热量扣减、'
      '训练中态卡消失', (WidgetTester tester) async {
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
    // seed 行随建库/种子同事务入队 sync_outbox——本用例只断言 W14 计划模板与
    // 训练写路径的出网行，先清空 seed 出网项（plan_schedule_card_test 同口径）。
    await database.delete(database.syncOutbox).go();

    // 排期日=下一个周三（今日即周三则取下周三）：起始日缺省=今日（编辑器
    // createFitnessPlan 缺省口径），恒 ≤ 周三 → isPlanScheduledOn「已开跑」成立。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final addDays = (DateTime.wednesday - today.weekday) % 7;
    final wednesday =
        today.add(Duration(days: addDays == 0 ? 7 : addDays));
    final wednesdayStr = formatCalendarDay(wednesday);

    // W14 装配（bootstrap() 同款 + Fake/注入时钟，plan_schedule_card_test 口径）。
    final keepAwake = FakeKeepAwakeService();
    final notifier = FakeWorkoutTimerNotifier();
    final telemetry = RecordingTelemetryService();
    var fakeNow = DateTime(now.year, now.month, now.day, 18, 30);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider.overrideWithValue(
            createCaptureGateway(db: database, clock: clock),
          ),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
          keepAwakeProvider.overrideWithValue(keepAwake),
          workoutTimerNotifierProvider.overrideWithValue(notifier),
          telemetryServiceProvider.overrideWithValue(telemetry),
          workoutClockProvider.overrideWithValue(() => fakeNow),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsNothing,
        reason: '完整壳已起（首页 AppBar 无产品名标题，用户拍板移除）');

    // ── ① 新建计划模板（feature_plan 编辑器，排期周三）──────────────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(planWorkoutTemplatesKey));
    await _pumpUntilFound(tester, find.byKey(fitnessPlanCreateKey));
    await tester.tap(find.byKey(fitnessPlanCreateKey));
    await _pumpUntilFound(tester, find.byKey(fitnessPlanNameFieldKey));

    await _enterField(tester, fitnessPlanNameFieldKey, '推日力量');
    // 排期周三（§5.5⑧ weekday_mask bit2=周三）。
    await tester.tap(find.byKey(fitnessPlanWeekdayChipKey(2)));
    await tester.pump();
    // 动作行（编辑器新建缺省首行 r0）：卧推 3组×10次 40kg 休90s。
    const rowKey = 'r0';
    await _enterField(
        tester, fitnessPlanExerciseNameKey(rowKey), '卧推');
    await _enterField(tester, fitnessPlanExerciseSetsKey(rowKey), '3');
    await _enterField(tester, fitnessPlanExerciseRepsKey(rowKey), '10');
    await _enterField(tester, fitnessPlanExerciseWeightKey(rowKey), '40');
    await _enterField(tester, fitnessPlanExerciseRestKey(rowKey), '90');
    await tester.tap(find.byKey(fitnessPlanSubmitKey));

    // fitness_plans 落库 + 抽屉收起（PlanGateway 写路径 §6.2 outbox 同事务）。
    await _pumpUntilDb(
      tester,
      () async => (await database.select(database.fitnessPlans).get())
          .any((p) => p.name == '推日力量'),
    );
    await _pumpUntilGone(tester, find.byKey(fitnessPlanNameFieldKey));
    final plan = (await database.select(database.fitnessPlans).get()).single;
    expect(plan.weekdayMask, 1 << 2, reason: '排期=周三（bit2，§5.5⑧）');
    expect(plan.active, isTrue);
    expect(plan.deletedAt, isNull);

    // ── ② 回计划 Tab：选中周三 → 排期卡出现该计划 ────────────────────────
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final planTabContext = tester.element(find.byType(PlanPage));
    ProviderScope.containerOf(planTabContext, listen: false)
        .read(selectedDateProvider.notifier)
        .select(wednesday);
    await tester.pumpAndSettle();
    expect(find.text('推日力量'), findsOneWidget,
        reason: '排期行唯一渲染（IA 重设计后计划列表段下沉 /plan/plans，'
            'plan_schedule_card_test 同口径改单现）');
    expect(find.byKey(planWorkoutStartKey(plan.id)), findsOneWidget);

    // ── ③ 排期卡「开始训练」→ 壳层训练流（KeepAwake on + 常驻通知 + 漏斗）──
    await tester.tap(find.byKey(planWorkoutStartKey(plan.id)));
    await tester.pumpAndSettle();
    expect(keepAwake.calls, ['enable']);
    expect(notifier.shown.length, 1);
    expect(notifier.lastShown!.title, '训练进行中');
    expect(telemetry.byName(W14TelemetryFunnel.workoutStarted).length, 1);
    expect(find.textContaining('训练中 · 推日力量'), findsOneWidget);
    expect(find.byKey(workoutLogSetKey), findsOneWidget);

    // ── ④ Fake 计时完成 3 组（§5.5⑨ 组明细内存累积）──────────────────────
    // 组 1：完成后休息 90s → 注入时钟推进 90s → 每秒 tick syncRest 到点回落。
    await tester.tap(find.byKey(workoutLogSetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(notifier.lastShown!.title, '组间休息');
    expect(
      notifier.lastShown!.chronometerEndsAtMs,
      isNotNull,
      reason: '通知挂原生倒计时（锁屏仍走秒的展示半边）',
    );
    expect(find.byKey(workoutRestRemainingKey), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(workoutRestRemainingKey)).data,
      '90',
    );
    fakeNow = fakeNow.add(const Duration(seconds: 90));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(workoutRestRemainingKey), findsNothing,
        reason: '注入时钟到点 → 组间休息自动回落（锁屏可跑语义）');
    expect(telemetry.byName(W14TelemetryFunnel.setLogged).length, 1);

    // 组 2：完成后休息 90s → 跳过（提前开下一组）。
    await tester.tap(find.byKey(workoutLogSetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(workoutRestRemainingKey), findsOneWidget);
    await tester.tap(find.byKey(workoutSkipRestKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(workoutRestRemainingKey), findsNothing);
    expect(telemetry.byName(W14TelemetryFunnel.setLogged).length, 2);

    // 组 3：末组完成 → 无下一组休息（全部完成，等「结束并保存」）。
    await tester.tap(find.byKey(workoutLogSetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(workoutRestRemainingKey), findsNothing,
        reason: '全部组完成不再计时');
    expect(telemetry.byName(W14TelemetryFunnel.setLogged).length, 3);

    // ── ⑤ 今天 Tab：训练中态卡 → 结束并保存（落库 §6.2 单事务）────────────
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.textContaining('训练中 · 推日力量'), findsOneWidget);
    expect(find.text('已完成 3 组'), findsOneWidget);
    await tester.tap(find.byKey(workoutCardEndKey));
    await _pumpUntilFound(tester, find.text('-12'));

    // 副作用收尾：KeepAwake off + 常驻通知 cancel + workout_completed。
    expect(keepAwake.calls, ['enable', 'disable']);
    expect(keepAwake.isEnabled, isFalse);
    expect(notifier.cancelled, [kWorkoutTimerNotificationId]);
    expect(telemetry.byName(W14TelemetryFunnel.workoutCompleted).length, 1);

    // 训练中态卡消失（§2.3 瞬时项）。
    expect(find.textContaining('训练中 · 推日力量'), findsNothing);

    // ── ⑥ 落库断言（§5.5⑦⑨/§6.2）：session + 3 组明细 + entry/burn 行 ────
    final sessions = await database.select(database.fitnessSessions).get();
    expect(sessions.length, 1);
    final session = sessions.single;
    expect(session.type, 'template_instance');
    expect(session.source, 'plan');
    expect(session.planDayId, plan.id);
    expect(session.date, wednesdayStr);
    expect(session.entryId, isNotNull, reason: 'entry 随完成训练联动（§5.5⑦）');
    // 时长=注入时钟差 90s → durationMinutes=2（ceil）；kcal=MET 估算
    // 5.0 × 70kg × (2/60)h = 12（§3.5 估算式，±20% 口径标注在 UI 层；
    // 身体档案缺省 70kg——与 feature_plan 网关同一常量，双基线已收敛）。
    expect(session.durationS, 90);
    expect(session.kcalBurn, 12);

    final sets = await database.select(database.exerciseSets).get();
    expect(sets.length, 3);
    final sorted = sets.toList()..sort((a, b) => a.sort.compareTo(b.sort));
    expect(sorted.map((s) => s.sort).toList(), [1, 2, 3]);
    for (final set in sorted) {
      expect(set.sessionId, session.id);
      expect(set.exerciseRef, '卧推');
      expect(set.reps, 10, reason: '沿用模板目标次数');
      expect(set.weightKgX10, 400, reason: '40kg ×10 定点（§5.5⑨）');
      expect(set.restS, 90, reason: 'rest_s 从模板读（§5.5⑨）');
      expect(set.doneAt, isNotNull);
    }

    final entries = await database.select(database.entries).get();
    expect(entries.length, 1);
    final entry = entries.single;
    expect(entry.id, session.entryId);
    expect(entry.kind, 'fitness');
    expect(entry.source, 'manual', reason: '计划语义由会话行 source 承担（§5.2①）');
    expect(entry.date, wednesdayStr);
    expect(entry.title, '推日力量 训练 2 分钟');

    final lines = await database.select(database.entryLines).get();
    expect(lines.length, 1);
    final burn = lines.single;
    expect(burn.type, 'burn');
    expect(burn.direction, 'out');
    expect(burn.amount, 12);
    expect(burn.entryId, entry.id);

    // ── ⑦ §6.2 出网纪律：业务行快照全部同事务入队（含模板行）────────────
    final outbox = await database.select(database.syncOutbox).get();
    final byTable = <String, int>{};
    for (final row in outbox) {
      byTable[row.targetTable] = (byTable[row.targetTable] ?? 0) + 1;
    }
    expect(byTable, {
      'fitness_plans': 1,
      'fitness_sessions': 1,
      'entries': 1,
      'entry_lines': 1,
      'exercise_sets': 3,
    });

    // ── ⑧ day_summary 投影联动（§5.6 重建规则）：当日 kcal_out/net 重算 ────
    final summaries = await database.select(database.daySummaries).get();
    final summary = summaries.singleWhere((s) => s.date == wednesdayStr);
    expect(summary.kcalOut, 12);
    expect(summary.netKcal, -12);
  });
}
