/// W14 主线 widget 测试（§11.2 W14「健身计划（留存钩子）：模板排期+组间计时
/// +组明细」、§3.5 健身记录与热量收支、§5.5⑦⑧⑨、§5.6、§6.2）。
///
/// 数据前提：内存真库（NativeDatabase.memory，§10.1 测试口径「真库 + Fake」，
/// 禁真实网络/平台通道）+ **注入 HlcClock 墙钟**（Fake 时钟：测试推进虚拟墙钟
/// 45 分钟 → 汇总时长/ MET 估算确定性）+ **注入休息心跳源**（Fake ticker：
/// 手动 StreamController，禁真实计时器）+ 完成反馈 Spy（音/震动接口留验）。
///
/// 主线验收（任务口径）：
/// 1. 建模板（名称+动作列表+排期掩码）→ fitness_plans 落库 + outbox 入队；
/// 2. 计划日历高亮：周排期条排期日 kcalOut 高亮、今日描边「今」角标、
///    非排期日低亮；
/// 3. 开练 → fitness_sessions 行（type=template_instance/source=plan/
///    start_at 真值）；
/// 4. 完成 3 组 → exercise_sets 3 行（组序/次数/重量/休息秒/完成时刻）；
///    第 1、2 组后组间计时器启动（rest_s=90 从模板读）——Fake 心跳计满触发
///    完成反馈 1 次 + 面板自动收起；第 2 次休息走「跳过」；第 3 组后无休息；
/// 5. 完成训练 → 会话汇总（时长=注入墙钟 45 分钟、kcal=MET 估算确定性）+
///    entries(kind=fitness)+entry_lines(type=burn) 联动 + 投影 kcal_out 即时
///    重算 + 五表 outbox 同事务入队（§6.2）。
///
/// 运行前提：集成阶段已 `flutter pub get`；宿主缺 sqlite3 运行库时温和跳过
/// （Windows 桌面常见，§10.1 测试口径）。
library;

import 'dart:async';
import 'dart:convert';

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

/// §6.3 定宽 HLC 编码：13 位毫秒:6 位计数器:12 位 hex。
final RegExp _hlcPattern = RegExp(r'^\d{13}:\d{6}:[0-9A-Fa-f]{12}$');

/// Fake 休息心跳源（§11.2 W14 可测性注入：手动 StreamController，禁真实
/// 计时器——每次 start() 取一条新流，测试逐枚触发心跳）。
class _FakeRestTicker {
  final List<StreamController<void>> controllers = <StreamController<void>>[];

  RestTickerFactory factory() => () {
        final controller = StreamController<void>();
        controllers.add(controller);
        return controller.stream;
      };

  /// 向最近一次 start() 取的心跳流注入 [ticks] 枚秒级心跳（一次注入、
  /// 顺序送达——倒计时逐秒递减到 0 后触发完成反馈并收起）。
  void emitLast(int ticks) {
    final controller = controllers.last;
    for (var i = 0; i < ticks; i++) {
      controller.add(null);
    }
  }
}

/// 完成反馈 Spy（§11.2 W14「完成音/震动留接口」的注入点验证）。
class _FeedbackSpy implements RestFeedback {
  int restCompleteCount = 0;

  @override
  void onRestComplete() => restCompleteCount++;
}

/// 测试夹具：内存真库 + 注入 HlcClock（可推进的 Fake 墙钟）+ 计划域网关。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  PlanGateway? _gateway;

  /// Fake 墙钟（UTC ms）：起始=真实 now（date 归日语义与真实日历一致），
  /// 测试中手动推进（45 分钟训练时长 → MET 估算确定性）。
  int fakeNowMs = DateTime.now().millisecondsSinceEpoch;

  cdb.AppDatabase get db => _db!;
  PlanGateway get gateway => _gateway!;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(
      // closeStreamsSynchronously：drift 流取消的清缓存 Timer 在 fake_async
      // 区无人清空会挂起测试（与 fitness_flow_test 同口径）。
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，W14 主线测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(
      deviceId: '3F8A12C0B7D4',
      wallClock: () => fakeNowMs,
    );
    _gateway = createPlanGateway(db: db, clock: _clock!);
    return true;
  }

  Future<void> close() async {
    await _db?.close();
  }
}

/// 泵计划页（ProviderScope 覆盖注入网关 + Fake 心跳 + 反馈 Spy）。
Future<({WidgetTester tester, _FakeRestTicker ticker, _FeedbackSpy feedback})>
    _pumpPlanPage(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final ticker = _FakeRestTicker();
  final feedback = _FeedbackSpy();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planGatewayProvider.overrideWithValue(harness.gateway),
        restTickerFactoryProvider.overrideWithValue(ticker.factory()),
        restFeedbackProvider.overrideWithValue(feedback),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const FitnessPlanPage(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.text('开始你的第一个健身计划'));
  return (tester: tester, ticker: ticker, feedback: feedback);
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      // 找到 ≠ 可命中：弹簧抽屉/共享轴进场动画首帧控件尚在屏外（与 W13
      // 测试同口径），把动画播完整再返回。
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

/// 全表计划行。
Future<List<cdb.FitnessPlan>> _allPlans(_Harness harness) async =>
    harness.db.select(harness.db.fitnessPlans).get();

/// 全表会话行。
Future<List<cdb.FitnessSession>> _allSessions(_Harness harness) async =>
    harness.db.select(harness.db.fitnessSessions).get();

/// 全表组明细行。
Future<List<cdb.ExerciseSet>> _allSets(_Harness harness) async =>
    harness.db.select(harness.db.exerciseSets).get();

/// outbox 已出现的目标表集合。
Future<Set<String>> _outboxTables(_Harness harness) async {
  final rows = await harness.db.select(harness.db.syncOutbox).get();
  return {for (final row in rows) row.targetTable};
}

/// 某日投影行。
Future<cdb.DaySummary?> _summaryFor(_Harness harness, String date) async {
  final rows = await harness.db.select(harness.db.daySummaries).get();
  for (final row in rows) {
    if (row.date == date) return row;
  }
  return null;
}

/// 读组间计时器面板剩余秒（AnimatedSwitcher.child=剩余秒 Text）。
int _restRemaining(WidgetTester tester) {
  final switcher =
      tester.widget<AnimatedSwitcher>(find.byKey(restTimerRemainKey));
  final text = switcher.child! as Text;
  return int.parse(text.data!);
}

void main() {
  testWidgets(
    'W14 主线：建模板→日历高亮→开练→完成 3 组（Fake 计时触发/跳过）→'
    '汇总落 session+burn 行+投影+五表 outbox（§11.2 W14 / §3.5 / §5.5⑦⑧⑨ /'
    ' §5.6 / §6.2）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);
      final todayBit = planWeekdayBitOf(now);
      final todayIdx = now.weekday - 1;
      // 排期：今日 + 相邻一日；非排期断言日取今日+3（与两排期日不重合）。
      final otherIdx = (todayIdx + 1) % 7;
      final idleIdx = (todayIdx + 3) % 7;

      final env = await _pumpPlanPage(tester, harness);
      final fakeTicker = env.ticker;
      final feedbackSpy = env.feedback;

      // ① 新建计划抽屉：名称 + 周排期（今日、相邻日）+ 动作（卧推 3组×10次
      //    40kg 休 90s）（§5.5⑧ 模板字段全量）。
      await tester.tap(find.byKey(fitnessPlanCreateKey));
      await _pumpUntilFound(tester, find.byKey(fitnessPlanNameFieldKey));
      await _enterField(tester, fitnessPlanNameFieldKey, '推拉腿');
      await tester.tap(find.byKey(fitnessPlanWeekdayChipKey(todayIdx)));
      await tester.pump();
      await tester.tap(find.byKey(fitnessPlanWeekdayChipKey(otherIdx)));
      await tester.pump();
      const rowKey = 'r0';
      await _enterField(
          tester, fitnessPlanExerciseNameKey(rowKey), '卧推');
      await _enterField(tester, fitnessPlanExerciseSetsKey(rowKey), '3');
      await _enterField(tester, fitnessPlanExerciseRepsKey(rowKey), '10');
      await _enterField(tester, fitnessPlanExerciseWeightKey(rowKey), '40');
      await _enterField(tester, fitnessPlanExerciseRestKey(rowKey), '90');
      await tester.tap(find.byKey(fitnessPlanSubmitKey));

      // ② fitness_plans 落库：模板 JSON/掩码/起始日/公共列（§5.5⑧/§5.1）。
      await _pumpUntilDb(
        tester,
        () async => (await _allPlans(harness)).any((p) => p.name == '推拉腿'),
      );
      await _pumpUntilGone(tester, find.byKey(fitnessPlanNameFieldKey));
      final plan = (await _allPlans(harness)).single;
      expect(plan.weekdayMask & todayBit, isNot(0), reason: '排期含今日位');
      expect(plan.weekdayMask & (1 << otherIdx), isNot(0),
          reason: '排期含相邻日位');
      expect(plan.weekdayMask & (1 << idleIdx), 0, reason: '未勾位不入掩码');
      expect(plan.startDate, today, reason: '起始日缺省=设备本地今日');
      expect(plan.active, isTrue);
      expect(plan.deletedAt, isNull);
      expect(_hlcPattern.hasMatch(plan.hlc), isTrue);
      final template = FitnessPlanTemplate.decode(plan.exercises);
      expect(template.exercises, hasLength(1));
      expect(
        template.exercises.single,
        const PlanExercise(
            name: '卧推', sets: 3, targetReps: 10,
            targetWeightKgX10: 400, restS: 90),
        reason: '模板 JSON 编解码（重量 ×10 定点 §5.5⑨）',
      );

      // ③ 计划日历高亮（§11.2 W14 验收）：排期日 kcalOut 高亮、今日描边
      //    +「今」角标、非排期日 surfaceMuted。
      await _pumpUntilFound(
          tester, find.byKey(fitnessPlanDayChipKey(plan.id, todayIdx)));
      // 计划卡动作摘要直显（模板解析；卡片随流刷新渲染后断言）。
      expect(find.text('卧推 3组×10次 40kg 休90s'), findsOneWidget);
      final tokens = tester
          .element(find.byKey(fitnessPlanDayChipKey(plan.id, todayIdx)))
          .slimca;
      Color chipColor(int idx) =>
          (tester.widget<Container>(
                  find.byKey(fitnessPlanDayChipKey(plan.id, idx)))
              .decoration! as BoxDecoration)
              .color!;
      expect(chipColor(todayIdx), tokens.kcalOut, reason: '今日排期高亮');
      expect(chipColor(otherIdx), tokens.kcalOut, reason: '排期日高亮');
      expect(chipColor(idleIdx), tokens.surfaceMuted, reason: '非排期日低亮');
      expect(find.text('今'), findsOneWidget, reason: '今日角标');
      expect(find.text('今日已排 · 可开练'), findsOneWidget);

      // ④ 开练（§11.2 W14 任务 2）：fitness_sessions 行
      //    type=template_instance/source=plan/start_at 真值。
      await tester.tap(find.byKey(fitnessPlanStartKey(plan.id)));
      await _pumpUntilFound(tester, find.byKey(fitnessWorkoutCompleteKey));
      await _pumpUntilDb(tester, () async => (await _allSessions(harness))
          .any((s) => s.planDayId == plan.id));
      final session0 = (await _allSessions(harness)).single;
      expect(session0.type, kFitnessSessionTypeTemplateInstance);
      expect(session0.source, kFitnessSessionSourcePlan);
      expect(session0.startAt, isNotNull, reason: '开练时刻真值（§5.5⑦）');
      expect(session0.durationS, 0, reason: '汇总前置 0（§11.2 W14）');
      expect(session0.kcalBurn, 0);
      expect(session0.entryId, isNull, reason: 'entry 随完成训练联动');
      expect(session0.date, today);
      expect(session0.tzOffsetMin, now.timeZoneOffset.inMinutes);

      // ⑤ 完成 3 组（§11.2 W14 任务 3）：目标预填直接完成 →
      //    exercise_sets 逐行落库（组序/次数/重量/休息秒/完成时刻）。
      for (var i = 1; i <= 3; i++) {
        await tester.tap(find.byKey(fitnessWorkoutCompleteKey));
        await _pumpUntilDb(
          tester,
          () async => (await _allSets(harness)).length == i,
        );
        final sets = await _allSets(harness);
        expect(sets.length, i);
        final last = sets.last;
        expect(last.sessionId, session0.id);
        expect(last.exerciseRef, '卧推');
        expect(last.reps, 10, reason: '空输入沿用模板目标次数');
        expect(last.weightKgX10, 400, reason: '空输入沿用模板目标重量');
        expect(last.restS, 90, reason: 'rest_s 从模板读（§5.5⑨）');
        expect(last.sort, i, reason: '会话内全局组序');
        expect(last.doneAt, isNotNull, reason: '完成标记=done_at（§5.5⑨）');
        expect(last.deletedAt, isNull);
        expect(_hlcPattern.hasMatch(last.hlc), isTrue);
        if (i == 3) {
          // 组间休息（§3.5）：第 3 组收尾无下一组 → 不再计时。
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byKey(restTimerPanelKey), findsNothing,
              reason: '全部完成不再计时');
          break;
        }
        // 组间计时器随完成一组启动（rest 秒数从模板读，§5.5⑧ rest_s）。
        await _pumpUntilFound(tester, find.byKey(restTimerPanelKey));
        expect(_restRemaining(tester), 90, reason: '大数字倒计时=模板 rest_s');
        // 注入心跳未触发前不递减（禁真实计时器口径：pump 秒数不走表）。
        await tester.pump(const Duration(seconds: 3));
        expect(_restRemaining(tester), 90);
        if (i == 1) {
          // Fake 心跳计满（§11.2 W14 可测性）：90 枚秒级心跳 → 完成反馈
          // 恰 1 次 + 面板自动收起（完成音/震动留接口验证）。
          fakeTicker.emitLast(90);
          await tester.pump();
          expect(feedbackSpy.restCompleteCount, 1);
          await _pumpUntilGone(tester, find.byKey(restTimerPanelKey));
        } else {
          // 第 2 次休息走「跳过」：直接收起、不触发完成反馈。
          await tester.tap(find.byKey(restTimerSkipKey));
          await _pumpUntilGone(tester, find.byKey(restTimerPanelKey));
          expect(feedbackSpy.restCompleteCount, 1);
        }
      }
      expect(fakeTicker.controllers.length, 2,
          reason: '心跳流恰按每次休息（组 1/2 后）各取一条（单订阅工厂）');

      // ⑥ 完成训练（§11.2 W14 任务 3 汇总）：推进注入墙钟 45 分钟 →
      //    duration=2700s、kcal=MET 估算确定性（§3.5 公式复用）。
      harness.fakeNowMs += 45 * 60 * 1000;
      await tester.tap(find.byKey(fitnessWorkoutFinishKey));
      await _pumpUntilDb(
        tester,
        () async => (await _allSessions(harness)).single.entryId != null,
      );
      final session = (await _allSessions(harness)).single;
      expect(session.durationS, 2700, reason: '汇总时长=注入墙钟差（§5.5⑦）');
      final expectedKcal = estimateKcalBurn(
        activity: findFitnessActivity(kFitnessPlanMetActivityId)!,
        intensity: FitnessIntensity.mid,
        durationS: session.durationS,
        weightKg: 70,
      );
      expect(session.kcalBurn, expectedKcal,
          reason: '估算消耗走既有 MET 逻辑（§3.5）');
      expect(session.entryId, isNotNull);

      // ⑦ exercise_sets 恰 3 行、组序 1..3（§5.5⑨ append-only）。
      final sets = (await _allSets(harness))
        ..sort((a, b) => a.sort.compareTo(b.sort));
      expect(sets, hasLength(3));
      expect(sets.map((s) => s.sort).toList(), [1, 2, 3]);

      // ⑧ entry + burn 行联动（§5.5⑦/§2.2 facet 行模型；复用 W5-6 链路）。
      final entryRows = await harness.db.select(harness.db.entries).get();
      final entry = entryRows.singleWhere((e) => e.id == session.entryId);
      expect(entry.kind, 'fitness');
      expect(entry.source, 'manual',
          reason: 'entries.source 枚举无 plan 档（§5.2①），计划语义由'
              ' fitness_sessions.source 承担');
      expect(entry.status, 'confirmed');
      expect(entry.date, today);
      expect(entry.title, startsWith('推拉腿'), reason: '标题=计划名+时长');
      final lineRows = await harness.db.select(harness.db.entryLines).get();
      final burn = lineRows.singleWhere((l) => l.entryId == entry.id);
      expect(burn.type, 'burn');
      expect(burn.amount, session.kcalBurn);
      expect(burn.direction, 'out');
      expect(burn.status, 'active');
      expect(burn.confidence, isNull, reason: '人工行无置信度（§5.2②）');
      final ledgers = await harness.db.select(harness.db.ledgers).get();
      final kcalLedger =
          ledgers.singleWhere((l) => l.kind == 'kcal' && l.deletedAt == null);
      expect(burn.ledgerId, kcalLedger.id);
      final payload = jsonDecode(burn.payload!) as Map<String, Object?>;
      expect(payload['session_id'], session.id);
      expect(payload['plan_id'], plan.id);
      expect(payload['plan_name'], '推拉腿');
      expect(payload['sets'], 3);
      expect(payload['weight_kg'], 70.0);

      // ⑨ 投影联动（§5.6）：burn 行落库 → 当日 kcal_out/net 即时重算。
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.kcalOut == session.kcalBurn,
      );
      final summary = (await _summaryFor(harness, today))!;
      expect(summary.kcalOut, session.kcalBurn);
      expect(summary.netKcal, -session.kcalBurn);

      // ⑩ §6.2 出网纪律：五张真值表行快照均已同事务入队。
      final tables = await _outboxTables(harness);
      expect(
        tables,
        containsAll([
          'fitness_plans',
          'fitness_sessions',
          'exercise_sets',
          'entries',
          'entry_lines',
        ]),
      );
    },
  );

  testWidgets(
    '训练历史页：按日/按计划双维度分组（§11.2 W14 任务 4 / §5.5⑦）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);

      // 播种：计划 + 开练 + 2 组 + 完成（经网关直驱，页面路径已在上例覆盖）。
      final plan = await harness.gateway.createFitnessPlan(
        name: '力量A',
        weekdayMask: 0,
        exercises: const [
          PlanExercise(
              name: '卧推', sets: 2, targetReps: 10,
              targetWeightKgX10: 400, restS: 60),
        ],
      );
      final session = await harness.gateway.startWorkoutSession(
        planId: plan.id,
        date: today,
      );
      await harness.gateway.logExerciseSet(
        sessionId: session.id,
        exerciseRef: '卧推',
        reps: 10,
        weightKgX10: 400,
        restS: 60,
      );
      await harness.gateway.logExerciseSet(
        sessionId: session.id,
        exerciseRef: '卧推',
        reps: 8,
        weightKgX10: 420,
        restS: 60,
      );
      harness.fakeNowMs += 30 * 60 * 1000;
      await harness.gateway
          .finishWorkoutSession(sessionId: session.id, weightKg: 70);

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
            home: const FitnessHistoryPage(),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('按日'));

      // 按日维度：归属日为组头，瓦片含类型/时长/消耗口径/组数（组数流装载
      // 完成后断言，避免首帧骨架期误判）。
      await _pumpUntilFound(tester, find.textContaining('2 组'));
      expect(find.text(today), findsOneWidget, reason: '按日组头=归属日');
      expect(find.textContaining('计划训练'), findsOneWidget,
          reason: 'template_instance 类型标签（§5.5⑦）');
      expect(find.textContaining('2 组'), findsOneWidget,
          reason: '组数徽标=Σ组明细行（§5.5⑨）');
      expect(find.textContaining('MET ±20%'), findsOneWidget,
          reason: '误差口径标注（§3.5 信任语言）');

      // 按计划维度：计划名为组头，同一会话瓦片仍可见。
      await tester.tap(find.text('按计划'));
      await tester.pump();
      expect(find.text('力量A'), findsOneWidget, reason: '按计划组头=计划名');
      expect(find.textContaining('计划训练'), findsOneWidget);
    },
  );

  test(
    '模板 JSON 防御解析与周排期掩码辅助（§5.5⑧/§7.4 降级口径）',
    () {
      // 坏 JSON/形状不符 → 空模板（不抛，读侧渲染空态）。
      expect(FitnessPlanTemplate.decode('not-json').exercises, isEmpty);
      expect(FitnessPlanTemplate.decode('{"ver":1}').exercises, isEmpty);
      expect(
        FitnessPlanTemplate.decode('{"ver":1,"exercises":"bad"}').exercises,
        isEmpty,
      );
      // 坏行逐条过滤 + 缺省数值字段保守回退（组 1 次 10 自重不休息）。
      final degraded = FitnessPlanTemplate.decode(
          '{"ver":1,"exercises":["bad",{"name":"深蹲","sets":5}]}');
      expect(degraded.exercises, hasLength(1));
      expect(degraded.exercises.single.name, '深蹲');
      expect(degraded.exercises.single.sets, 5);
      expect(degraded.exercises.single.targetReps, 10);
      expect(degraded.exercises.single.targetWeightKgX10, 0);
      expect(degraded.exercises.single.restS, 0);
      // 编码 round-trip（§5.5⑧ exercises 列 JSON 形状）。
      final src = FitnessPlanTemplate(exercises: const [
        PlanExercise(
            name: '卧推', sets: 3, targetReps: 10,
            targetWeightKgX10: 400, restS: 90),
      ]);
      expect(
        FitnessPlanTemplate.decode(src.encode()).exercises,
        src.exercises,
      );
      // 周排期掩码（§5.5⑧ bit0=周一…bit6=周日）：2026-11-18 为周三。
      final wednesday = DateTime(2026, 11, 18);
      expect(wednesday.weekday, DateTime.wednesday);
      expect(planWeekdayBitOf(wednesday), 1 << 2);
      const mask = (1 << 0) | (1 << 2);
      expect(planMaskCovers(mask, wednesday), isTrue);
      expect(planMaskCovers(mask, DateTime(2026, 11, 17)), isFalse);
      expect(planMaskSummary(mask), '周一、周三');
      expect(planMaskSummary(0), isNull, reason: '空掩码=纯模板');
    },
  );
}
