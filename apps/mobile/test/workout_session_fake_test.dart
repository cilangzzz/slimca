// W14 组间计时器骨架测试（§11.2 W14 主线「健身计划：模板排期+组间计时
// （锁屏可跑）+组明细」、W14 任务 5「Fake 断言（开练→KeepAwake.on、
// 结束→off）」+ 任务 2「通知常驻计时，Fake 断言」+ 任务 3「漏斗」）。
//
// 纪律（任务 5）：禁真实计时器/通知/平台通道——
// - KeepAwake 注入 FakeKeepAwakeService（记录 enable/disable 调用）；
// - 常驻通知注入 FakeWorkoutTimerNotifier（记录 show/cancel 序列）；
// - 一切时刻判定注入可控时钟（workoutClockProvider override，测试推进）；
// - 落库用内存 Drift 库（宿主缺 sqlite3 运行库时温和跳过，widget_test
//   同口径）；遥测注入 RecordingTelemetryService（test_support）。
//
// 覆盖：
// 1. 开练 → state 置位 + KeepAwake.enable + 常驻通知（训练中底条）+
//    workout_started；
// 2. 记组 → 组间休息（剩余秒=注入时钟对 rest_ends_at 绝对时刻的即时重算，
//    锁屏可跑的语义半边）+ set_logged + 原生倒计时通知（chronometerEndsAt）；
// 3. 休息到点 syncRest 回落训练态 + 通知还原；skipRest 提前；start 幂等；
// 4. 结束并保存 → KeepAwake.disable + 通知 cancel + 落库（fitness_sessions
//    type=template_instance/source=plan + entries(kind=fitness) + burn 行 +
//    exercise_sets 组明细 + 全量 outbox 同事务 §5.5⑦⑨/§6.2）+ 投影重算；
// 5. 放弃训练 → off + cancel + 零落库零 workout_completed；
// 6. 排期模板宽容解析（§7.4：坏 JSON/缺键/数值钳制）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart'
    show DatabaseConnection, OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/data/workout_models.dart';
import 'package:slimca/features/workout/workout_session_controller.dart';
import 'package:slimca/telemetry/w14_funnel_events.dart';
import 'package:slimca/workout/fake_keep_awake_service.dart';
import 'package:slimca/workout/fake_workout_timer_notifier.dart';
import 'package:slimca/workout/rest_timer_notifier.dart';

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（widget_test 同口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
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

/// 测试装配（每用例独立）：内存库 + Fakes + 可控时钟的 ProviderContainer。
class _Harness {
  final FakeKeepAwakeService keepAwake = FakeKeepAwakeService();
  final FakeWorkoutTimerNotifier notifier = FakeWorkoutTimerNotifier();
  final RecordingTelemetryService telemetry = RecordingTelemetryService();

  /// 注入时钟锚点（固定日历日 2026-11-17 周二，§5.1 本地日历日口径）。
  DateTime now = DateTime(2026, 11, 17, 18, 30);

  db.AppDatabase? database;
  ProviderContainer? container;

  int get nowMs => now.millisecondsSinceEpoch;

  /// 推进注入时钟（剩余秒/到点判定的测试推进器，禁真实计时器）。
  void advance(Duration delta) => now = now.add(delta);

  Future<bool> setUp() async {
    // Fake 状态复位（harness 跨用例复用，调用记录不得泄漏到下一用例）。
    keepAwake.reset();
    notifier.reset();
    telemetry.events.clear();
    now = DateTime(2026, 11, 17, 18, 30);
    final opened = await _tryOpenMemoryDatabase();
    if (opened == null) return false; // 宿主缺 sqlite3：跳过（集成机有库）。
    database = opened;
    final clock = HlcClock(deviceId: 'ABCDEF123456');
    await ensureDefaultLedgers(opened, clock);
    // seed 行（账本/分类/settings）随建库/种子同事务入队 sync_outbox——本
    // 用例只断言 W14 训练写路径的出网行，先清空 seed 出网项（与
    // e2e_fitness_to_dashboard_test 同口径；seed 入队语义由 core_db
    // seed_idempotency_test 专属覆盖）。
    await opened.delete(opened.syncOutbox).go();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(opened),
      hlcClockProvider.overrideWithValue(clock),
      keepAwakeProvider.overrideWithValue(keepAwake),
      workoutTimerNotifierProvider.overrideWithValue(notifier),
      telemetryServiceProvider.overrideWithValue(telemetry),
      workoutClockProvider.overrideWithValue(() => now),
    ]);
    return true;
  }

  Future<void> tearDown() async {
    // Riverpod 3：ProviderContainer.dispose() 为同步 void（不可 await）。
    container?.dispose();
    container = null;
    await database?.close();
    database = null;
  }

  /// 种子健身计划（§5.5⑧：三分化推日，掩码全周，2 动作 × 休息秒）。
  Future<db.FitnessPlan> seedPlan() async {
    final opened = database!;
    final clockNow = now.millisecondsSinceEpoch;
    final plan = db.FitnessPlan(
      id: 'plan-w14-1',
      name: '三分化 · 推日',
      weekdayMask: 0x7F,
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
      createdAt: clockNow,
      updatedAt: clockNow,
      deletedAt: null,
      hlc: HlcClock(deviceId: 'ABCDEF123456').now().format(),
      revision: 1,
      schemaVer: kCurrentSchemaVer,
      deviceId: 'ABCDEF123456',
    );
    await opened.into(opened.fitnessPlans).insert(plan);
    return plan;
  }

  WorkoutSessionController get controller =>
      container!.read(workoutSessionProvider.notifier);

  WorkoutSessionState? get state => container!.read(workoutSessionProvider);
}

void main() {
  group('排期模板宽容解析（§5.5⑧、§7.4 降级）', () {
    test('标准形状（计划域编辑器口径）：name/sets/target_reps/×10 定点/rest_s',
        () {
      final parsed = parsePlanExercises(jsonEncode([
        {
          'name': '深蹲',
          'sets': 4,
          'target_reps': 8,
          'target_weight_kg_x10': 600,
          'rest_s': 120,
        },
      ]));
      expect(parsed.length, 1);
      expect(parsed.single.name, '深蹲');
      expect(parsed.single.sets, 4);
      expect(parsed.single.reps, 8);
      expect(parsed.single.weightKg, 60.0, reason: '×10 定点回 kg（§5.5⑨）');
      expect(parsed.single.restS, 120);
    });

    test('别名键与缺键（§7.4 宽容）：exercise_ref/rest/重量 变体 + 缺省值', () {
      final parsed = parsePlanExercises(jsonEncode([
        {'exercise_ref': '硬拉', '组数': 2, 'rest': 45},
        {'name': '引体向上'}, // 全缺省：sets=3 reps=10 自重无休息。
        {'ref': '平板支撑', '重量': 0},
      ]));
      expect(parsed.length, 3);
      expect(parsed[0].name, '硬拉');
      expect(parsed[0].sets, 2);
      expect(parsed[0].restS, 45);
      expect(parsed[1].sets, 3);
      expect(parsed[1].reps, 10);
      expect(parsed[1].weightKg, isNull);
      expect(parsed[2].weightKg, 0.0);
    });

    test('坏形状自愈（§7.4）：坏 JSON/非数组/无动作名项 → 跳过/空列表', () {
      expect(parsePlanExercises('not-json'), isEmpty);
      expect(parsePlanExercises(jsonEncode({'name': 'x'})), isEmpty);
      expect(
        parsePlanExercises(jsonEncode([{'sets': 3, 'reps': 10}])),
        isEmpty,
        reason: '无动作名的项不可训练，跳过',
      );
      final clamped = parsePlanExercises(jsonEncode([
        {'name': '超界', 'sets': 99, 'reps': 9999, 'rest_s': 9999},
      ]));
      expect(clamped.single.sets, 20, reason: '数值钳制到合理域');
      expect(clamped.single.reps, 200);
      expect(clamped.single.restS, 600);
    });
  });

  group('W14 任务 5：开练→KeepAwake.on / 结束→off（Fake 记录调用）', () {
    final harness = _Harness();
    var ready = false;

    setUp(() async {
      ready = await harness.setUp();
      if (ready) await harness.seedPlan();
    });

    tearDown(() async {
      await harness.tearDown();
      ready = false;
    });

    test('开练：state 置位 + enable + 常驻通知 + workout_started', () async {
      if (!ready) return;
      final plan = await (harness.database!.select(harness.database!.fitnessPlans))
          .getSingle();
      expect(harness.state, isNull, reason: '初始无进行中训练');

      await harness.controller.startFromPlan(plan, date: '2026-11-17');

      final state = harness.state!;
      expect(state.planId, 'plan-w14-1');
      expect(state.planName, '三分化 · 推日');
      expect(state.date, '2026-11-17');
      expect(state.exercises.length, 2, reason: '§5.5⑧ 模板解析');
      expect(state.totalSets, 5);
      expect(state.setNo, 1);
      expect(state.sets, isEmpty);
      expect(state.isResting, isFalse);

      // W14 任务 5 断言：开练 → KeepAwake.on。
      expect(harness.keepAwake.enableCount, 1);
      expect(harness.keepAwake.isEnabled, isTrue);
      expect(harness.keepAwake.calls, ['enable']);

      // W14 任务 2 断言：常驻通知（训练中底条，无倒计时）。
      expect(harness.notifier.shown.length, 1);
      final notice = harness.notifier.lastShown!;
      expect(notice.notificationId, kWorkoutTimerNotificationId);
      expect(notice.title, '训练进行中');
      expect(notice.ongoing, isTrue);
      expect(notice.chronometerEndsAtMs, isNull);
      expect(harness.notifier.cancelled, isEmpty);

      // W14 任务 3 断言：漏斗起点（props 只带枚举标签，§3.9）。
      final started = harness.telemetry.byName(W14TelemetryFunnel.workoutStarted);
      expect(started.length, 1);
      expect(started.single.props['source'], 'plan');
    });

    test('重复开练幂等：训练中再 startFromPlan 为 no-op（不重复副作用）', () async {
      if (!ready) return;
      final plan = await (harness.database!.select(harness.database!.fitnessPlans))
          .getSingle();
      await harness.controller.startFromPlan(plan, date: '2026-11-17');
      await harness.controller.startFromPlan(plan, date: '2026-11-17');

      expect(harness.keepAwake.enableCount, 1, reason: '训练中幂等 no-op');
      expect(harness.notifier.shown.length, 1);
      expect(harness.state!.planId, 'plan-w14-1');
    });
  });

  group('W14 任务 2/3：记组 → 组间休息（注入时钟重算）+ 通知 + 漏斗', () {
    final harness = _Harness();
    var ready = false;

    setUp(() async {
      ready = await harness.setUp();
      if (ready) {
        final plan = await harness.seedPlan();
        await harness.controller.startFromPlan(plan, date: '2026-11-17');
      }
    });

    tearDown(() async {
      await harness.tearDown();
      ready = false;
    });

    test('完成一组：记录字段齐全 + 休息倒计时（剩余秒=ceil，锁屏可跑语义）', () async {
      if (!ready) return;
      final logAtMs = harness.nowMs;
      await harness.controller.logCurrentSet();

      final state = harness.state!;
      expect(state.sets.length, 1);
      final set = state.sets.single;
      expect(set.exerciseRef, '杠铃卧推');
      expect(set.exerciseIndex, 0);
      expect(set.setNo, 1);
      expect(set.reps, 10);
      expect(set.weightKg, 40.0);
      expect(set.restS, 90);
      expect(set.doneAtMs, logAtMs);
      expect(state.setNo, 2, reason: '同动作推进到第 2 组');

      // 绝对时刻倒计时（§3.5 组间计时 锁屏可跑的语义半边）。
      expect(state.isResting, isTrue);
      expect(state.restEndsAtMs, logAtMs + 90 * 1000);
      expect(state.remainingRestSeconds(harness.nowMs), 90,
          reason: '起始整秒');
      harness.advance(const Duration(seconds: 30));
      expect(state.remainingRestSeconds(harness.nowMs), 60,
          reason: '注入时钟推进 → 即时重算（无需真实计时器）');
      harness.advance(const Duration(seconds: 61));
      expect(state.remainingRestSeconds(harness.nowMs), 0, reason: '到点为 0');
      expect(state.isResting, isTrue, reason: '到点回落由 syncRest 判定推进');

      // W14 任务 2 断言：组间休息通知挂原生倒计时（chronometerEndsAt）。
      expect(harness.notifier.shown.length, 2);
      final restNotice = harness.notifier.lastShown!;
      expect(restNotice.title, '组间休息');
      expect(restNotice.body, contains('杠铃卧推'));
      expect(restNotice.body, contains('第 1/3 组'));
      expect(restNotice.chronometerEndsAtMs, logAtMs + 90 * 1000);
      expect(restNotice.ongoing, isTrue);

      // W14 任务 3 断言：set_logged（rest_s 标量，§3.9）。
      final logged = harness.telemetry.byName(W14TelemetryFunnel.setLogged);
      expect(logged.length, 1);
      expect(logged.single.props['rest_s'], 90);
    });

    test('休息中不重复记组（no-op 防御）', () async {
      if (!ready) return;
      await harness.controller.logCurrentSet();
      final setsLength = harness.state!.sets.length;
      await harness.controller.logCurrentSet(); // 休息中：no-op。
      expect(harness.state!.sets.length, setsLength);
      expect(harness.telemetry.byName(W14TelemetryFunnel.setLogged).length, 1);
    });

    test('到点 syncRest：休息态回落 + 通知还原为训练中底条', () async {
      if (!ready) return;
      await harness.controller.logCurrentSet();
      harness.advance(const Duration(seconds: 91));
      harness.controller.syncRest(nowMs: harness.nowMs);

      expect(harness.state!.isResting, isFalse, reason: '到点回落');
      expect(harness.state!.setNo, 2);
      // 通知还原（最后一条=训练中底条，已完成 1 组）。
      final notice = harness.notifier.lastShown!;
      expect(notice.title, '训练进行中');
      expect(notice.body, contains('已完成 1 组'));
      expect(notice.chronometerEndsAtMs, isNull);
    });

    test('未到点 syncRest 为 no-op（不写状态）', () async {
      if (!ready) return;
      await harness.controller.logCurrentSet();
      harness.advance(const Duration(seconds: 5));
      harness.controller.syncRest(nowMs: harness.nowMs);
      expect(harness.state!.isResting, isTrue, reason: '未到点不推进');
      expect(harness.notifier.shown.length, 2, reason: '无通知重发');
    });

    test('skipRest 提前结束休息 + 通知还原', () async {
      if (!ready) return;
      await harness.controller.logCurrentSet();
      await harness.controller.skipRest();
      expect(harness.state!.isResting, isFalse);
      expect(harness.notifier.lastShown!.title, '训练进行中');
    });

    test('动作组满自动切换：末组休息后指针进下一动作第 1 组', () async {
      if (!ready) return;
      for (var i = 0; i < 3; i++) {
        await harness.controller.logCurrentSet(); // 杠铃卧推 3 组。
        harness.advance(const Duration(seconds: 91));
        harness.controller.syncRest(nowMs: harness.nowMs);
      }
      final state = harness.state!;
      expect(state.sets.length, 3);
      expect(state.sets.last.exerciseIndex, 0, reason: '第 3 组归属动作 1（0 起）');
      expect(state.exerciseIndex, 1, reason: '动作 1 组满 → 指针进动作 2（0 起）');
      expect(state.setNo, 1);
    });
  });

  group('W14 任务 5：结束并保存 → off + cancel + 落库（§5.5⑦⑨/§6.2）', () {
    final harness = _Harness();
    var ready = false;
    late int startedAtMs;

    setUp(() async {
      ready = await harness.setUp();
      if (ready) {
        final plan = await harness.seedPlan();
        startedAtMs = harness.nowMs;
        await harness.controller.startFromPlan(plan, date: '2026-11-17');
        // 5 组全记（组间休息逐次到点推进；模板 3+2）。
        for (var i = 0; i < 5; i++) {
          await harness.controller.logCurrentSet();
          harness.advance(const Duration(seconds: 91));
          harness.controller.syncRest(nowMs: harness.nowMs);
        }
      }
    });

    tearDown(() async {
      await harness.tearDown();
      ready = false;
    });

    test('结束并保存：off + cancel + 会话/事件/burn/组明细/outbox/投影全链', () async {
      if (!ready) return;
      expect(harness.state!.sets.length, 5);
      expect(harness.state!.allDone, isTrue, reason: '3+2 组全部完成');
      // setUp 循环已推进 5×91s=455s；补齐到整 2400s（40 分钟）注入时钟——
      // 时长/ kcal 断言因此可写死（MET 估算 5.0 × 60kg × 40min = 200）。
      harness.advance(const Duration(seconds: 2400 - 5 * 91)); // 训练时长 40 分钟。

      await harness.controller.endWorkout(save: true);

      // W14 任务 5 断言：结束 → off + 通知 cancel。
      expect(harness.state, isNull);
      expect(harness.keepAwake.disableCount, 1);
      expect(harness.keepAwake.isEnabled, isFalse);
      expect(harness.keepAwake.calls, ['enable', 'disable']);
      expect(harness.notifier.cancelled, [kWorkoutTimerNotificationId]);
      expect(harness.notifier.activeById, isEmpty, reason: '常驻通知已撤');

      // W14 任务 3 断言：workout_completed（props 只带标签/计数，§3.9）。
      final completed =
          harness.telemetry.byName(W14TelemetryFunnel.workoutCompleted);
      expect(completed.length, 1);
      expect(completed.single.props['source'], 'plan');
      expect(completed.single.props['sets'], 5);

      // ── 落库口径（§5.5⑦⑨、§6.2）──────────────────────────────────
      final database = harness.database!;
      final sessions = await database.select(database.fitnessSessions).get();
      expect(sessions.length, 1);
      final session = sessions.single;
      expect(session.type, 'template_instance', reason: '§5.5⑦ 计划会话');
      expect(session.source, 'plan', reason: '§5.5⑦ source 枚举');
      expect(session.planDayId, 'plan-w14-1', reason: '计划溯源（v1 暂存 plan id）');
      expect(session.durationS, 2400);
      // MET 估算：strength 5.0 × 60kg（身体档案缺省）× 40min = 200 kcal（§3.5）。
      expect(session.kcalBurn, 200);
      expect(session.startAt, startedAtMs);
      expect(session.entryId, isNotNull, reason: '§5.5⑦ entry_id 联动');

      final entries = await database.select(database.entries).get();
      expect(entries.length, 1);
      final entry = entries.single;
      expect(entry.id, session.entryId);
      expect(entry.kind, 'fitness');
      expect(entry.source, 'manual', reason: '§5.2① source 枚举无 plan → 手动域');
      expect(entry.status, 'confirmed');
      expect(entry.title, '三分化 · 推日 训练 40 分钟');
      expect(entry.date, '2026-11-17');

      final lines = await database.select(database.entryLines).get();
      expect(lines.length, 1);
      final burn = lines.single;
      expect(burn.type, 'burn');
      expect(burn.amount, 200);
      expect(burn.direction, 'out');
      expect(burn.confidence, isNull, reason: '人工估算行无 AI 置信度（§5.2②）');
      expect(burn.ledgerId, isNotNull, reason: 'burn 行归集内置 kcal 账本');
      final payload = jsonDecode(burn.payload!) as Map<String, Object?>;
      expect(payload['session_id'], session.id);
      expect(payload['plan_id'], 'plan-w14-1');
      expect(payload['sets_count'], 5);

      // 组明细（§5.5⑨：weight ×10 定点、rest_s、sort 全局组序、done_at）。
      final sets = await (database.select(database.exerciseSets)
            ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
          .get();
      expect(sets.length, 5);
      expect(sets[0].exerciseRef, '杠铃卧推');
      expect(sets[0].weightKgX10, 400, reason: '40kg ×10 定点（§5.5⑨）');
      expect(sets[0].reps, 10);
      expect(sets[0].restS, 90);
      expect(sets[0].sessionId, session.id);
      expect(sets[3].exerciseRef, '哑铃肩推');
      expect(sets[3].weightKgX10, 125, reason: '12.5kg ×10 定点');
      expect(sets[3].restS, 60);
      for (var i = 0; i < sets.length; i++) {
        expect(sets[i].sort, i + 1,
            reason: 'sort=全局组序，1 起（§5.5⑨；W14 集成统一与 feature_plan '
                'PlanGateway 同口径）');
        expect(sets[i].doneAt, greaterThan(0));
      }

      // outbox：3 行主链 + 5 行组明细，全量同事务入队（§6.2）。
      final outbox = await database.select(database.syncOutbox).get();
      final byTable = <String, int>{};
      for (final row in outbox) {
        byTable[row.targetTable] = (byTable[row.targetTable] ?? 0) + 1;
      }
      expect(byTable, {
        'fitness_sessions': 1,
        'entries': 1,
        'entry_lines': 1,
        'exercise_sets': 5,
      });

      // 投影联动（§5.6）：当日 kcal_out 重算 = 200。
      final summary = await (database.select(database.daySummaries)
            ..where((t) => t.date.equals('2026-11-17')))
          .getSingleOrNull();
      expect(summary, isNotNull);
      expect(summary!.kcalOut, 200);
      expect(summary.netKcal, -200);
    });

    test('放弃训练：off + cancel + 零落库 + 无 workout_completed', () async {
      if (!ready) return;
      await harness.controller.endWorkout(save: false);

      expect(harness.state, isNull);
      expect(harness.keepAwake.disableCount, 1, reason: '放弃同样 off（任务 5）');
      expect(harness.keepAwake.isEnabled, isFalse);
      expect(harness.notifier.cancelled, [kWorkoutTimerNotificationId]);

      final database = harness.database!;
      expect(await database.select(database.fitnessSessions).get(), isEmpty);
      expect(await database.select(database.entries).get(), isEmpty);
      expect(await database.select(database.entryLines).get(), isEmpty);
      expect(await database.select(database.exerciseSets).get(), isEmpty);
      expect(
        harness.telemetry.byName(W14TelemetryFunnel.workoutCompleted),
        isEmpty,
        reason: '放弃不计完成（漏斗不失真，W13 coinIn 幂等同口径）',
      );
    });

    test('空组结束（save=true）：零落库、无 workout_completed，副作用仍释放',
        () async {
      if (!ready) return;
      // 重建一个开练未记组的控制器态：先结束当前态（保存），再重开不记组。
      await harness.controller.endWorkout(save: true);
      final plan = await harness.database!
          .select(harness.database!.fitnessPlans)
          .getSingle();
      harness.keepAwake.reset();
      harness.notifier.reset();
      await harness.controller.startFromPlan(plan, date: '2026-11-17');
      await harness.controller.endWorkout(save: true);

      expect(harness.state, isNull);
      expect(harness.keepAwake.calls, ['enable', 'disable'],
          reason: '空训练收尾仍释放常亮（§6.1 收尾纪律）');
      expect(harness.notifier.cancelled, [kWorkoutTimerNotificationId]);
      // 仅第一次 5 组会话落库（本次空组未落库）。
      final sessions = await harness.database!
          .select(harness.database!.fitnessSessions)
          .get();
      expect(sessions.length, 1);
      expect(
        harness.telemetry.byName(W14TelemetryFunnel.workoutCompleted).length,
        1,
        reason: '空组不计 workout_completed',
      );
    });
  });
}
