/// W13 主线 widget 测试（§11.2 W13「待办完整版（RRULE+提醒）+ 存钱目标」、
/// §3.6、§5.5⑩⑪⑫、§5.6⑬）。
///
/// 内存真库（NativeDatabase.memory）+ Fake 通知口径（feature 层只落
/// remind_at 字段，不触任何真实通知/网络通道，§3.6 P1 壳层调度口径）：
/// 1. 重复待办：编辑抽屉新建「每天」→ **当日展开不重复落行**（todos 恰 1 行、
///    瓦片恰 1 枚）→ 提醒字段落库 → 勾选联动投影（锚点日）→ 编辑改「每 3 天」
///    （锚点不变，series 续展）；
/// 2. 52 周挑战：新建目标 → 投币 3 次（今日 UI 打卡 1 次 + 双击防重复 +
///    前两日补投 2 次）→ 断言进度=贡献行求和（§5.5⑫）→ UI 金额刷新 →
///    day_summary.savings_progress 当日/历史日快照更新（§5.6⑬ 累计口径）；
/// 3. 自定义目标：首目标建档当日投影从 NULL 变有值（§5.6⑬「写后重算当日」），
///    投币后进度推进。
///
/// 运行前提：集成阶段已 `dart run build_runner build -d`（core_db W13 补列的
/// 生成成员 t.rrule_anchor_date/t.source 未 regen 前 core_db 不可编译，属
/// 预期，见 core_db w13 说明）+ `flutter pub get`；宿主缺 sqlite3 运行库时
/// 温和跳过（与 todo_flow_test 同口径）。
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

/// 测试夹具：内存真库 + 注入 HlcClock + 计划域网关（存钱 DAO 组合投影，
/// §5.6⑬ W13）。
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
      // 区无人清空会挂起测试（与 todo_flow_test 同口径）。
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，W13 主线测试未执行（$error）');
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

/// 泵待办页（ProviderScope 覆盖注入网关）。
Future<void> _pumpTodoPage(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [planGatewayProvider.overrideWithValue(harness.gateway)],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const TodoPage(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(todoInputKey));
}

/// 泵存钱页。
Future<void> _pumpSavingsPage(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [planGatewayProvider.overrideWithValue(harness.gateway)],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const SavingsPage(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(savingsCreateKey));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      // 找到 ≠ 可命中：弹簧抽屉进场（springSnappy 220ms，§9.2）首帧控件
      // 尚在屏外（slide 自底部起），直接 tap 会 miss。这里把弹簧播完整
      // （300ms > 220ms 整定）再返回，保证后续 tap 落点在屏内。
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

/// 轮询直到 [finder] 消失（弹簧抽屉退场动画结束后再断言，避免 EditableText
/// 与瓦片 Text 双重匹配）。
Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isEmpty) {
      // 退场弹簧同样播完整（再泵一轮），避免路由残帧干扰后续断言。
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件消失超时: $finder');
}

/// 向带 key 的 PlanTextField 输入文本（TextField 是其内部子控件，
/// 与 fitness_flow_test._enterText 同口径）。
Future<void> _enterField(
    WidgetTester tester, Key fieldKey, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 轮询直到 [probe] 为真（投影重算/Drift 流为异步桥接，§5.6）。
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

/// 全表待办行（Dart 侧过滤，无 drift 高级查询依赖）。
Future<List<cdb.Todo>> _allTodos(_Harness harness) async =>
    harness.db.select(harness.db.todos).get();

/// 全表贡献行。
Future<List<cdb.SavingsContribution>> _allContributions(
        _Harness harness) async =>
    harness.db.select(harness.db.savingsContributions).get();

/// 全表目标行。
Future<List<cdb.SavingsGoal>> _allGoals(_Harness harness) async =>
    harness.db.select(harness.db.savingsGoals).get();

/// 某日投影行（无行返回 null）。
Future<cdb.DaySummary?> _summaryFor(_Harness harness, String date) async {
  final rows = await harness.db.select(harness.db.daySummaries).get();
  for (final row in rows) {
    if (row.date == date) return row;
  }
  return null;
}

void main() {
  testWidgets(
    '重复待办：当日展开不重复落行 + 提醒字段 + 勾选联动投影 + 编辑改档'
    '（§3.6 完整版 / §5.5⑩ / §5.6 / §11.2 W13）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final today = dom.formatCalendarDay(DateTime.now());

      await _pumpTodoPage(tester, harness);

      // ① 编辑抽屉新建「每天」重复待办（重复规则 + 提醒，§3.6 W13）。
      await tester.tap(find.byKey(todoAdvancedKey));
      await _pumpUntilFound(tester, find.byKey(todoEditorTitleKey));
      await _enterField(tester, todoEditorTitleKey, '晨跑');
      await tester.tap(find.byKey(todoRepeatChipKey(TodoRepeatKind.daily)));
      await tester.pump();
      await tester.tap(find.byKey(todoEditorRemindToggleKey));
      await tester.pump();
      // 提醒缺省 09:00 档可见（只落字段，无真实通知——壳层调度口径）。
      expect(find.text('09:00'), findsOneWidget);
      await tester.tap(find.byKey(todoEditorSaveKey));

      // ② 当日展开不重复落行（§11.2 W13 展开策略）：todos 恰 1 行、
      //    瓦片恰 1 枚、规则/锚点/提醒字段落库正确。
      await _pumpUntilDb(
        tester,
        () async =>
            (await _allTodos(harness)).where((t) => t.title == '晨跑').length ==
                1,
      );
      await _pumpUntilGone(tester, find.byKey(todoEditorTitleKey));
      final rows = (await _allTodos(harness))
          .where((t) => t.title == '晨跑')
          .toList();
      expect(rows, hasLength(1), reason: '重复待办不预生成实例行（W13 取舍）');
      final todo = rows.single;
      expect(todo.repeatRule, 'FREQ=DAILY;INTERVAL=1');
      expect(todo.rruleAnchorDate, today, reason: '锚点缺省=计划日（DTSTART）');
      expect(todo.remindAt, remindAtMsFor(day: today, hour: 9, minute: 0));
      expect(todo.date, today);
      await _pumpUntilFound(tester, find.text('晨跑'));
      expect(find.text('晨跑'), findsOneWidget,
          reason: '当日实例虚拟展开且锚点日不重复渲染');
      expect(find.textContaining('每天'), findsOneWidget,
          reason: '重复规则摘要标签');

      // ③ 勾选 → 基行 done_at 落实例日 + 投影 todo_done=1（锚点日即基行
      //    date，§5.6 重建规则；done_at 只前进合并 §6.5）。
      await tester.tap(find.byKey(todoCheckKey(todo.id)));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.todoDone == 1 &&
            (await _summaryFor(harness, today))?.todoTotal == 1,
      );

      // ④ 编辑改档「每 3 天」（点瓦片标题 → 编辑抽屉）：规则更新、锚点
      //    不变（series 续展，§5.5⑩ 上层决策口径）。
      await tester.tap(find.text('晨跑'));
      await _pumpUntilFound(tester, find.byKey(todoEditorSaveKey));
      await tester
          .tap(find.byKey(todoRepeatChipKey(TodoRepeatKind.everyNDays)));
      await tester.pump();
      await _enterField(tester, todoEditorIntervalKey, '3');
      await tester.tap(find.byKey(todoEditorSaveKey));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _allTodos(harness))
                    .where((t) => t.id == todo.id)
                    .single
                    .repeatRule ==
                'FREQ=DAILY;INTERVAL=3',
      );
      await _pumpUntilGone(tester, find.byKey(todoEditorTitleKey));
      final edited = (await _allTodos(harness))
          .where((t) => t.id == todo.id)
          .single;
      expect(edited.rruleAnchorDate, today, reason: '改档不动锚点');
      expect(edited.remindAt, isNotNull, reason: '编辑保留提醒字段');
      await _pumpUntilFound(tester, find.textContaining('每3天'));
    },
  );

  testWidgets(
    '52 周挑战：新建→投币 3 次→进度=贡献求和→投影 savings_progress 更新'
    '（§3.6 / §5.5⑪⑫ / §5.6⑬）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);
      final yesterday =
          dom.formatCalendarDay(now.subtract(const Duration(days: 1)));
      final day2Ago =
          dom.formatCalendarDay(now.subtract(const Duration(days: 2)));

      await _pumpSavingsPage(tester, harness);

      // ① 新建 52 周挑战（每格基数缺省 10 元 → 目标 13,780 元，§3.6）。
      await tester.tap(find.byKey(savingsCreateKey));
      await _pumpUntilFound(tester, find.byKey(savingsNameFieldKey));
      await _enterField(tester, savingsNameFieldKey, '旅行基金');
      await tester
          .tap(find.byKey(savingsMethodChipKey(cdb.kSavingsMethodWeek52)));
      await tester.pump();
      await tester.tap(find.byKey(savingsGoalSubmitKey));
      await _pumpUntilDb(
        tester,
        () async => (await _allGoals(harness))
            .any((g) => g.name == '旅行基金' && g.method == 'week52'),
      );
      final goal = (await _allGoals(harness)).first;
      expect(goal.targetMinor, 1378000,
          reason: '52 周目标=基数×Σ(1..52)=1000 分×1378');
      expect(goal.startedOn, today);
      expect(goal.rhythm, contains('week52'));

      // ② 首次投币（UI 打卡）：第 1 周 = 1000 分；打卡后按钮翻置灰态
      //    （§3.6 状态防重复）。
      await _pumpUntilFound(tester, find.byKey(savingsCheckInKey(goal.id)));
      await tester.tap(find.byKey(savingsCheckInKey(goal.id)));
      await _pumpUntilDb(
        tester,
        () async => (await _allContributions(harness)).length == 1,
      );
      final first = (await _allContributions(harness)).single;
      expect(first.goalId, goal.id);
      expect(first.amountMinor, 1000, reason: '第 1 周=1×基数');
      expect(first.slot, 1);
      expect(first.source, cdb.kSavingsSourceManual);
      expect(first.date, today);

      // ③ 双击防重复：DAO 幂等键 (goal_id, date, source)——同日重复追加
      //    no-op 返回既有行（首写胜），不产生新行（§5.5⑫ W13 补列 source）。
      final again = await harness.gateway.contributeToGoal(
        goalId: goal.id,
        date: today,
        amountMinor: 99999,
      );
      expect(again.id, first.id, reason: '幂等命中：首写胜');
      expect((await _allContributions(harness)).length, 1);

      // ④ 前两日补投 2 次（跨日打卡，经网关模拟）：贡献行合计 3 行。
      await harness.gateway
          .contributeToGoal(goalId: goal.id, date: yesterday, amountMinor: 2000);
      await harness.gateway
          .contributeToGoal(goalId: goal.id, date: day2Ago, amountMinor: 3000);
      await _pumpUntilDb(
        tester,
        () async => (await _allContributions(harness)).length == 3,
      );
      final sum = (await _allContributions(harness))
          .where((c) => c.deletedAt == null)
          .fold<int>(0, (acc, c) => acc + c.amountMinor);
      expect(sum, 6000, reason: '进度=贡献行求和（1000+2000+3000，§5.5⑫）');

      // ⑤ UI 刷新：卡片金额 count-up 到 60.00 / 13780.00 元（§9.3#4；
      //    目标 1,378,000 分 = 13,780 元）。
      await _pumpUntilFound(
          tester, find.textContaining('60.00 / 13780.00 元'));

      // ⑥ 投影 savings_progress（§5.6⑬ W13 实装，口径=任务定义）：贡献追加
      //    同事务「先 markSavingsProgressDirty(fromDate: 贡献日) 再重算贡献日」
      //    ——贡献日快照即时推进；其后既有快照行交 recomputeDirtyDays 后台
      //    自愈（§5.6 自愈）。累计口径 date<=快照日 + 目标有效性
      //    started_on<=快照日（§5.6⑬「当日有效目标」冻结口径）：
      //    - 今日首次打卡后：今日快照即时 = 1000（目标今日起生效）；
      //    - 昨日/前日补投（早于 started_on，经网关显式金额直达 DAO）：补投日
      //      目标未生效 → 快照保持 NULL（贡献行仍落库，被其后窗口内快照的
      //      累计口径吸收）；窗口内跨日快照推进由 core_db savings_dao_test /
      //      savings_projection_test 覆盖（goal started_on 早于贡献日）；
      //    - 自愈跑完：今日 = Σ全部 6000（累计口径不漏补投行）。
      await _pumpUntilDb(
        tester,
        () async {
          final row = await _summaryFor(harness, today);
          if (row?.savingsProgress == null) return false;
          final parsed = cdb.parseSavingsProgress(row!.savingsProgress!);
          return parsed[goal.id]?.contributedMinor == 1000 &&
              parsed[goal.id]?.targetMinor == 1378000;
        },
      );
      final yesterdayRow = await _summaryFor(harness, yesterday);
      expect(yesterdayRow, isNotNull, reason: '贡献追加即时重算贡献日（§5.6⑬）');
      expect(
        yesterdayRow!.savingsProgress,
        isNull,
        reason: '补投日早于 started_on：目标未生效，当日无有效目标 → 快照 NULL'
            '（§5.6⑬ 冻结口径；W1-W12 恒 NULL 空态）',
      );
      // 后台自愈（§5.6「标记 dirty → 后台重算」的后台半步）：其后窗口内
      // 快照行补齐——补投行经累计口径进今日快照。
      await harness.gateway.projection.recomputeDirtyDays();
      final healed = await _summaryFor(harness, today);
      final healedParsed = cdb.parseSavingsProgress(healed!.savingsProgress!);
      expect(healedParsed[goal.id]?.contributedMinor, 6000,
          reason: '自愈后今日快照=Σ贡献行（1000+2000+3000，§5.5⑫）');
      expect(healedParsed[goal.id]?.targetMinor, 1378000);
      final healedYesterday = await _summaryFor(harness, yesterday);
      expect(healedYesterday!.savingsProgress, isNull,
          reason: '目标 started_on=今日，昨日恒无有效目标（自愈不改写窗口外日）');
    },
  );

  testWidgets(
    '自定义目标：首目标建档当日投影从 NULL 变有值 + 投币推进'
    '（§5.6⑬「写后重算当日」/§3.6）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final today = dom.formatCalendarDay(DateTime.now());

      await _pumpSavingsPage(tester, harness);

      // ① 空库：当日投影无存钱进度（W1-W12 恒 NULL 同一空态，§5.6⑬）。
      final before = await _summaryFor(harness, today);
      if (before != null) {
        expect(before.savingsProgress, isNull);
      }

      // ② 新建自定义目标（目标 100 元、每日 5 元，§3.6）。
      await tester.tap(find.byKey(savingsCreateKey));
      await _pumpUntilFound(tester, find.byKey(savingsNameFieldKey));
      await _enterField(tester, savingsNameFieldKey, '应急金');
      await tester
          .tap(find.byKey(savingsMethodChipKey(cdb.kSavingsMethodCustom)));
      await tester.pump();
      await _enterField(tester, savingsTargetFieldKey, '100');
      await _enterField(tester, savingsDailyFieldKey, '5');
      await tester.pump();
      await tester.tap(find.byKey(savingsGoalSubmitKey));
      await _pumpUntilDb(
        tester,
        () async => (await _allGoals(harness))
            .any((g) => g.name == '应急金' && g.method == 'custom'),
      );
      final goal = (await _allGoals(harness)).first;
      expect(goal.targetMinor, 10000);
      expect(goal.rhythm, contains('daily_amount_minor'));

      // ③ 建档当日投影即时可见（dirty 标记扫不到 NULL 行 → 建档路径显式
      //    重算当日，§5.6⑬）：目标金额进快照、贡献 0。
      await _pumpUntilDb(
        tester,
        () async {
          final row = await _summaryFor(harness, today);
          if (row?.savingsProgress == null) return false;
          final parsed = cdb.parseSavingsProgress(row!.savingsProgress!);
          return parsed[goal.id]?.targetMinor == 10000 &&
              parsed[goal.id]?.contributedMinor == 0;
        },
      );

      // ④ 投币打卡：每日固定额 500 分 → 进度 5%、投影推进。
      await _pumpUntilFound(tester, find.byKey(savingsCheckInKey(goal.id)));
      await tester.tap(find.byKey(savingsCheckInKey(goal.id)));
      await _pumpUntilDb(
        tester,
        () async {
          final row = await _summaryFor(harness, today);
          if (row?.savingsProgress == null) return false;
          return cdb.parseSavingsProgress(row!.savingsProgress!)[goal.id]
                  ?.contributedMinor ==
              500;
        },
      );
      final contrib = (await _allContributions(harness)).single;
      expect(contrib.amountMinor, 500);
      expect(contrib.slot, isNull, reason: '自定义目标无格子号（§5.5⑫）');
      await _pumpUntilFound(tester, find.textContaining('5.00 / 100.00 元'));
    },
  );

  test(
    '专项验收：每日重复待办跨两天只落 anchor 行、两日各展开一条实例'
    '（§11.2 W13 专项验收 / §5.5⑩「查询时展开、不预生成行」）',
    // 纯 DB/网关验收：无需泵帧，用真 async test（testWidgets 的 fake_async
    // 区不 pump 会让 drift watch 流的调度 Timer 挂起——与 todo_flow_test
    // 选 plain test 同理由）。
    () async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);
      final tomorrow =
          dom.formatCalendarDay(now.add(const Duration(days: 1)));

      // 每日重复待办（经网关建档，锚点缺省=计划日 DTSTART）。
      await harness.gateway.createTodo(
        title: '每日站立会',
        date: today,
        repeatRule: 'FREQ=DAILY;INTERVAL=1',
      );
      final rows = (await _allTodos(harness))
          .where((t) => t.title == '每日站立会')
          .toList();
      expect(rows, hasLength(1), reason: '跨两天只落 anchor 行（不预生成实例行）');
      expect(rows.single.rruleAnchorDate, today, reason: '锚点=计划日');

      // 两日各展开一条虚拟实例（日期各归各日、不重复渲染）。
      final todayInstances =
          await harness.gateway.watchTodoDayInstances(today).first;
      expect(todayInstances, hasLength(1), reason: '当日恰一条实例');
      expect(todayInstances.single.todo.id, rows.single.id);
      expect(todayInstances.single.date, today);
      expect(todayInstances.single.recurring, isTrue);
      expect(todayInstances.single.repeatLabel, '每天');
      expect(todayInstances.single.done, isFalse);

      final tomorrowInstances =
          await harness.gateway.watchTodoDayInstances(tomorrow).first;
      expect(tomorrowInstances, hasLength(1), reason: '次日恰一条实例');
      expect(tomorrowInstances.single.todo.id, rows.single.id);
      expect(tomorrowInstances.single.date, tomorrow);
      expect(tomorrowInstances.single.recurring, isTrue);

      // 展开纯查询态：落库行数不变（仍 1 行 anchor）。
      expect((await _allTodos(harness)).length, 1,
          reason: '展开不落行（W13 取舍）');
    },
  );
}
