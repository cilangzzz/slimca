// E2E 专项验收（§11.1 W2 验收线：「手动记一笔→仪表盘环/支出卡即时更新」）。
//
// 与 widget_test.dart（W2+W3-4 冒烟，覆盖壳导航+录入链路）互补，本用例聚焦
// 「写路径 → 仪表盘 reactive stream 即时重发」这一条验收线本身：
// - 完整 App 冷启动（SlimcaApp：go_router 壳 + 4 Tab + 真仪表盘）；
// - ProviderScope override 注入内存真库（Drift NativeDatabase.memory，
//   走真实 schema/migration/seed 链路，非 mock）；
// - 经 feature_capture CapturePage（§10.4 收敛：壳采用其 CapturePage 作
//   唯一录入 UI）「仅记钱」表单提交一笔支出（¥25.50）；
// - 断言记录前后仪表盘支出卡数值即时变化（零导航、零重启，唯一驱动就是
//   drift watch 流重发 + Riverpod StreamProvider 重建）。
//
// W2 手动表单为纯 money 通道（§2.4-2「纯记账用户不被热量字段骚扰」）：
// kcal 不经手动录入（热量语义走 W3-4 AI 流），故本用例断言 kind=expense、
// 热量侧维持零值基线。
//
// 测试装配与冒烟同一口径：内存库 + 固定 device_id 的 HlcClock 直接
// override（不跑 bootstrap()，避免测试写真实文件库）；feature_capture
// 网关/解析器按 bootstrap() 同款工厂注入（§10.4）；内置账本种子用
// ensureDefaultLedgers 手动补齐（§5.4）。Windows 宿主缺 sqlite3 运行库时
// 温和跳过（与 core_db 冒烟同策略）。

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
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 core_db test_support 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存真库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：drift 默认在查询流最后一个监听者
/// 取消后排一个 `Timer.run` 延迟清缓存；在 flutter_test 的 fake_async 区，
/// teardown 卸载 widget 树瞬间创建的该 Timer 无人清空 →
/// 「A Timer is still pending」断言失败。此开关是 drift 文档对这类测试的
/// 官方出口（取消监听即同步关流，不排 Timer）。
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

void main() {
  testWidgets('E2E：完整 App 启动 → CapturePage 仅记钱表单记一笔支出 → 仪表盘支出卡即时更新',
      (WidgetTester tester) async {
    // 放大视口：抽屉表单一屏放下，免滚动命中（与 capture_flow 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，E2E 照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，E2E 记账→仪表盘用例未执行');
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3 12 位 hex）+ 内置账本种子（§5.4：默认 money 账本
    // + 内置 kcal 账本）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // W9-10 录入漏斗断言面（§2.3「打开→输入→解析→确认」、§11.1 W9-10 北极星
    // 实测）：RecordingTelemetryService 捕获壳层 FAB 流的漏斗/护栏指标。
    final telemetry = RecordingTelemetryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          // feature_capture 装配（§10.4 壳负责装配，bootstrap() 同款工厂）。
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          telemetryServiceProvider.overrideWithValue(telemetry),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    // 完整壳已起（首页 AppBar 无产品名标题——用户拍板移除「Slimca」字样）。
    expect(find.text('Slimca'), findsNothing);

    // ── 记录前：空日基线（§3.2 空态零值，非空日才有记录卡）──
    expect(find.text('记一件事，钱和卡路里一起入账'), findsOneWidget,
        reason: '空态引导文案在位');
    expect(find.text('今日支出'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget,
        reason: '支出卡基线为零（0 分展示为 ¥0，§5.1 展示换算）');
    // 指标行 label/value 是两个 Text（Row），按 value Text 断言：环卡摄入/
    // 消耗两行 + 今日消耗卡共 3 处 '0 kcal'（§3.2 卡片墙空态基线均为零）。
    expect(find.text('0 kcal'), findsNWidgets(3),
        reason: '摄入/消耗指标与消耗卡基线为零');
    expect(find.text('0'), findsOneWidget, reason: '热量环心净 kcal 基线为零');

    // ── 经 CapturePage 录入：仅记钱表单记午饭 ¥25.50（§11.1 W2 主线）──
    await tester.tap(find.byType(FloatingActionButton));
    // W9-10 录入漏斗首步「打开」（W7-8 缺口，核对补齐）：抽屉唤起即记。
    await telemetry.flush();
    expect(telemetry.byName(TelemetryFunnel.captureOpen), hasLength(1),
        reason: '漏斗「打开」起点：唤起录入抽屉即记（§2.3）');
    await tester.pumpAndSettle();
    // 缺省「钱+热量」档渲染 AI 输入区；切「仅记钱」→ W2 手动表单（§3.3）。
    expect(find.byKey(const Key('capture_ai_input')), findsOneWidget);
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture_amount_display')), findsOneWidget);

    // 金额滚动直输（数字键盘类型 §7.1）：enterText ¥25.50（分存储转换，
    // 杜绝浮点 §5.1）。
    await tester.enterText(
      find.byKey(const ValueKey('capture_amount_display')),
      '25.50',
    );
    await tester.pump();
    expect(find.text('25.50'), findsOneWidget);

    // 标题（手动表单标题框无 key，按提示文案定位）。
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '标题（留空自动取分类名）',
      ),
      '测试午餐',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle(); // 抽屉弹簧反向退场 + 明细流重发落界面

    // W9-10 录入漏斗终点 + 护栏耗时（§2.3 步 5「确认」、护栏「打开→确认
    // ≤8s（P50）」的 metric 数据源）。
    await telemetry.flush();
    expect(telemetry.byName(TelemetryFunnel.captureConfirm), hasLength(1),
        reason: '漏斗终点「确认」在提交成功路径触发（W7-8 口径保持）');
    final guardrail = telemetry.byName(TelemetryMetricName.captureOpenToConfirmMs);
    expect(guardrail, hasLength(1), reason: '打开→确认护栏耗时随确认落盘');
    expect(guardrail.single.props['value'], greaterThan(0));
    expect(guardrail.single.props['unit'], 'ms');

    // 抽屉已收起（§9.3#3），回不到录入面。
    expect(find.byKey(const Key('capture_submit')), findsNothing);
    expect(find.text('记一笔'), findsNothing);

    // ── 记录后：仪表盘即时更新（唯一驱动=drift watch 流重发）──
    // 空态引导已被今日记录卡替换；支出卡：¥0 → ¥25.50（§3.2 卡片墙第 2 项）。
    expect(find.text('记一件事，钱和卡路里一起入账'), findsNothing,
        reason: '空态引导已被记录卡替换');
    expect(find.text('¥0'), findsNothing, reason: '旧零值已被流重发改写');
    expect(find.text('¥25.50'), findsWidgets,
        reason: '支出卡金额即时更新（今日记录卡摘要同源复现）');
    expect(find.text('测试午餐'), findsOneWidget, reason: '今日记录卡出现该条目');

    // 热量侧零值基线不变（W2 手动表单为纯 money 通道，§2.4-2）。
    expect(find.text('0 kcal'), findsNWidgets(3),
        reason: '摄入/消耗指标与消耗卡仍为零');
    expect(find.text('0'), findsOneWidget, reason: '热量环心净 kcal 仍为零');

    // ── 落库保真：真库中主干 + money 拆行（§5.2 facet）──
    final entries = await database.select(database.entries).get();
    expect(entries, hasLength(1), reason: '一笔事件一条 entries 主干（§5.2①）');
    expect(entries.single.kind, 'expense',
        reason: '仅金额 → kind=expense（§5.2①，收入方向由行级 direction 表达）');
    expect(entries.single.source, 'manual', reason: '手动通道（§5.2① source）');
    expect(entries.single.status, 'confirmed', reason: '手动路径不走 draft');
    expect(entries.single.aiParseId, isNull, reason: '手动路径无 AI 溯源');
    expect(entries.single.title, '测试午餐');
    final lines = await database.select(database.entryLines).get();
    final moneyLines = lines.where((l) => l.type == 'money').toList();
    final kcalLines = lines.where((l) => l.type == 'calorie').toList();
    expect(moneyLines, hasLength(1), reason: '金额 facet 行（§5.3）');
    expect(moneyLines.single.amount, 2550, reason: '¥25.50 → 2550 分（§5.1）');
    expect(moneyLines.single.direction, 'out', reason: '支出方向（§5.2②）');
    expect(moneyLines.single.confidence, isNull,
        reason: '人工行无置信度（§5.2② confidence AI 产出行必填）');
    expect(kcalLines, isEmpty, reason: 'W2 手动表单无热量字段（§2.4-2）');
  });
}
