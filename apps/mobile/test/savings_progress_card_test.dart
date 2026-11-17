// W13 存钱目标 + 漏斗埋点测试（§11.2 W13 任务 2「仪表盘存钱进度卡接真数据」、
// 任务 4「savings_goal_created/coin_in/todo_recurrence_created 漏斗事件」、
// 任务 5「插目标+贡献→卡片数字变化」）。
//
// 覆盖链路（内存 Drift 库 + 遥测记录桩，禁真实通知/网络）：
// 1. 仪表盘存钱进度卡：空态=无目标引导创建（§3.2「上线后自动接入」+ 任务 2
//    空态口径）→ 建档（SavingsService.createGoal → 投影同事务重算）→ 卡片
//    出现 ¥0/¥100 → 投币（coinIn → 贡献行 append + 投影重算）→ 卡片数字
//    变化 ¥5/¥100（5%）（任务 5 验收）；
// 2. 计划 Tab 存钱卡：目标行/进度渲染 + 投币表单（建议额预填、幂等命中
//    SnackBar、进度即时推进）；
// 3. 漏斗埋点：savings_goal_created / coin_in（幂等命中不重复计）/
//    todo_recurrence_created（计划 Tab 重复待办建档）。
//
// 测试装配与 widget_test 同口径：不跑 bootstrap()；写路径直连 DAO+服务
// （SavingsService 持投影与遥测桩）。Windows 宿主缺 sqlite3 时温和跳过。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/data/savings_service.dart';
import 'package:slimca/main.dart';
import 'package:slimca/telemetry/w13_funnel_events.dart';

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（widget_test 同口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 小步轮询等待文本出现（投影流重发是真实异步，pumpAndSettle 对无限动画
/// 不收敛——widget_test 同策略）。
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
  testWidgets('W13：存钱卡接真数据（建档→投币→数字变化）+ W13 漏斗埋点',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = db.AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await database.customSelect('SELECT 1').getSingle();
    } catch (error) {
      try {
        await database.close();
      } catch (_) {}
      if (_isSqliteLibraryMissing(error)) {
        return; // Windows 宿主缺 sqlite3.dll：跳过（集成机有库）。
      }
      rethrow;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // 遥测记录桩（test_support 复用：漏斗/指标/崩溃内存记录，禁真实 IO）。
    final telemetry = RecordingTelemetryService();
    // 写路径直连 DAO+服务（§5.6⑬ W13 实装口径：DAO 持投影——写事务内重算
    // savings_progress 快照，仪表盘流即时重发）。
    final projection = db.DaySummaryProjection(database);
    final service = SavingsService(
      goalsDao: db.SavingsGoalsDao(database, projection: projection),
      contributionsDao:
          db.SavingsContributionsDao(database, projection: projection),
      telemetry: telemetry,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
        child: const SlimcaApp(),
      ),
    );
    // 冷启动级联播完（§9.3#1；widget_test 同口径 600ms）。
    await tester.pump(const Duration(milliseconds: 600));

    // ── 任务 2 空态：无目标引导创建（快照 NULL = W1-W12 恒 NULL 旧空态）──
    expect(find.textContaining('还没有存钱目标'), findsOneWidget,
        reason: 'W13 仪表盘存钱卡空态=无目标引导创建');

    // ── 任务 5 前半：建档 → 卡片出现（投影行从 NULL 变为有值）──────────
    final goal = await service.createGoal(
      name: '旅行基金',
      targetMinor: 10000, // ¥100
      method: db.kSavingsMethodCustom,
      dailyAmountMinor: 500, // ¥5 每日建议额
    );
    expect(
      telemetry.byName(W13TelemetryFunnel.savingsGoalCreated),
      hasLength(1),
      reason: '任务 4：savings_goal_created 漏斗（建档即记）',
    );
    await _pumpUntilFound(tester, find.textContaining('/ ¥100（0%）'));
    expect(find.textContaining('还没有存钱目标'), findsNothing,
        reason: '空态让位真数据（started_on=今日 → 当日有效目标）');

    // ── 切计划 Tab：存钱卡目标行 + 投币表单（§3.6 投币式打卡）────────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.text('旅行基金'));
    expect(find.textContaining('¥0 / ¥100'), findsOneWidget,
        reason: '计划卡与仪表盘卡同源（Σ贡献口径 §5.5⑫）');

    // 投币表单：建议额预填（custom → 每日额 ¥5）→ 提交。
    await tester.tap(find.byKey(Key('plan_savings_coin_${goal.id}')));
    await tester.pumpAndSettle();
    final amountField =
        find.byKey(const Key('plan_coin_amount_field'));
    expect(amountField, findsOneWidget);
    expect(
      tester.widget<TextField>(amountField).controller!.text,
      '5',
      reason: '投币建议额预填（custom 每日额 500 分 → ¥5）',
    );
    await tester.tap(find.byKey(const Key('plan_coin_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已投币入账'), findsOneWidget,
        reason: '投币成功反馈');
    // 刷掉 SnackBar 展示期定时器（4s）——避免「Timer is still pending」。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 进度即时推进（append → 投影同事务重算 → 流重发）。
    await _pumpUntilFound(tester, find.textContaining('¥5 / ¥100'));
    expect(find.textContaining('5%'), findsOneWidget,
        reason: '进度=贡献行求和（500/10000=5%）');

    // 幂等（同日同来源重复投币）：二次提交为 no-op，漏斗不重复计。
    await tester.tap(find.byKey(Key('plan_savings_coin_${goal.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan_coin_submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('今日已投过币'), findsOneWidget,
        reason: '幂等命中友好反馈（§5.5⑫ goal+date+source 去重）');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('¥5 / ¥100'), findsOneWidget,
        reason: '幂等命中不改进度（首写胜 §6.1 append-only）');
    expect(telemetry.byName(W13TelemetryFunnel.coinIn), hasLength(1),
        reason: '任务 4：coin_in 只记真实新增（幂等命中不重复计）');

    // ── 任务 4：todo_recurrence_created（计划 Tab 重复待办建档）──────────
    await tester.enterText(
      find.byKey(const Key('plan_todo_input')),
      '每日冥想',
    );
    await tester.pump();
    await tester.tap(find.text('每天'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan_todo_add')));
    await _pumpUntilFound(tester, find.text('每日冥想'));
    expect(
      telemetry.byName(W13TelemetryFunnel.todoRecurrenceCreated),
      hasLength(1),
      reason: '任务 4：重复待办建档漏斗（RRULE 档位）',
    );

    // ── 切回仪表盘：存钱进度卡数字变化（任务 5 终态；仪表盘卡金额与目标
    // 分两枚 Text 渲染：'¥5' + '/ ¥100（5%）'）。
    await tester.tap(find.text('今天'));
    await tester.pumpAndSettle();
    expect(find.text('¥5'), findsOneWidget,
        reason: '仪表盘进度卡=Σ贡献（day_summary 快照直出 §5.6⑬）');
    expect(find.textContaining('/ ¥100（5%）'), findsOneWidget,
        reason: '目标合计与百分比同源快照');
  });
}
