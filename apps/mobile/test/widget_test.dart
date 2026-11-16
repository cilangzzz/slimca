// Slimca W2+W3-4+W5-6 冒烟测试（§11 W2 手动记一笔 → 仪表盘即时更新 +
// §11.1 W3-4 AI 双解析闭环 + §11.1 W5-6 录入通道/真页 Tab）——三接缝收敛后
// 的壳层装配口径。
//
// 覆盖链路（§4.2 壳 + §9.3#3 录入抽屉 + §6.2 写路径 + §3.3 语音通道）：
// 冷启动首帧直出仪表盘（无 spinner §2.3 步 0）→ 4 Tab 导航壳（§4.2）→
// 中央「+」弹簧抽屉（W5-6：写/说/拍三通道，写=feature_capture CapturePage
// 唯一录入 UI，说=语音面板 W5-6 Fake 链路，拍=P1 禁用 §3.3）→ 单边开关
// 「仅记钱」手动填表保存 → entries/entry_lines 落库 → 仪表盘明细流实时重发；
// W3-4：AI 一句话输入 → 缺省装配（dart-define 工厂无 key → core_ai
// HeuristicFakeLlmAdapter 完整管线，零真实网络）→ 确认卡 → 确认入账 →
// 仪表盘即时更新；W5-6：账本/计划 Tab 真页（§3.4 流水按日分组、§4.2 计划
// 三卡 + 待办快速添加 §3.6）。
//
// 测试装配：内存 Drift 库 + 固定 device_id 的 HlcClock 直接 override（不跑
// bootstrap()，避免测试写真实文件库）；feature_capture 网关/解析器按
// bootstrap() 同款工厂注入（§10.4）；内置账本种子用 ensureDefaultLedgers
// 补齐（§5.4）。Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 同策略）。

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
import 'package:slimca/app/bootstrap.dart';
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
/// `closeStreamsSynchronously: true`：drift 在查询流最后一个监听者取消后
/// 默认排一个 `Timer.run` 延迟清缓存（减少 StreamBuilder 重连重复查询）。
/// 在 flutter_test 的 fake_async 区里，teardown 卸载 widget 树瞬间创建的
/// 该 Timer 无人清空 →「A Timer is still pending」断言失败。此开关即
/// drift 文档对这类测试的官方出口（cancel 时同步关流，不排 Timer）。
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

/// 向带 key 的 CaptureTextField 输入文本（TextField 是其内部子控件）。
Future<void> _enterField(
  WidgetTester tester,
  Key fieldKey,
  String text,
) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 小步轮询等待控件出现（解析中呼吸态 SlimcaBreath 是无限循环动画，
/// pumpAndSettle 永不收敛——与 feature_capture capture_flow_test 同策略）。
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
  testWidgets('W2+W3-4 冒烟：仅记钱手动一笔 → AI 缺省装配解析确认 → 仪表盘即时更新',
      (WidgetTester tester) async {
    // 放大视口：抽屉表单/确认卡一屏放下，免滚动命中（与 capture_flow 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，冒烟照常执行）。
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3 12 位 hex）+ 内置账本种子（§5.4）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          // feature_capture 装配（§10.4 壳负责装配，bootstrap() 同款工厂）：
          // 解析器走缺省 dart-define 工厂 → core_ai 离线桩完整管线。
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget); // AppBar 标题

    // §4.2 四 Tab：今天 / 账本 / 计划 / 我的。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // ── W2：仅记钱手动记一笔（§11 W2 验收线）────────────────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    // 缺省「钱+热量」档渲染 AI 输入区（§3.3 W3-4 主线档位）。
    expect(find.text('记一笔'), findsOneWidget);
    expect(find.byKey(const Key('capture_ai_input')), findsOneWidget);
    // 切「仅记钱」→ W2 手动表单（§2.4-2 纯记账用户不被热量字段骚扰）。
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capture_amount_display')), findsOneWidget);

    // 数字键盘输入 ¥25.50（分存储转换，杜绝浮点 §5.1）。
    for (final key in const ['2', '5', '.', '5', '0']) {
      await tester.tap(find.byKey(ValueKey('capture_key_$key')));
    }
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
    await tester.pumpAndSettle();

    // 抽屉已收起（§9.3#3 弹簧反向退场）。
    expect(find.byKey(const Key('capture_submit')), findsNothing);
    expect(find.text('记一笔'), findsNothing);

    // 仪表盘即时更新：今日记录卡条目 + 支出卡 + 摘要；热量侧仍为零值。
    expect(find.text('测试午餐'), findsOneWidget);
    expect(find.text('¥25.50'), findsWidgets, reason: '支出卡 + 条目摘要同源复现');
    expect(find.text('0 kcal'), findsNWidgets(3), reason: '热量侧基线未动');
    expect(find.text('0'), findsOneWidget, reason: '热量环心净 kcal 仍为 0');

    // ── W3-4：AI 文本解析闭环（缺省装配 → core_ai 管线离线桩；
    //    测试无 dart-define → mock 零真实网络，§11.1 W3-4）────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _enterField(
      tester,
      const Key('capture_ai_input'),
      '测试晚餐 500kcal 花了18',
    );
    await tester.tap(find.byKey(const Key('capture_parse_button')));
    // 解析中呼吸态/确认卡置信度三色点均为无限循环动画（SlimcaBreath/
    // SlimcaConfidenceDot），pumpAndSettle 永不收敛：轮询等确认卡出现，
    // 再推固定时长让 count-up（800ms）播完到终值（§9.3#4）。
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('capture_confirm_submit')),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));

    // 确认卡出现（§2.3 步 3「抽屉原地转确认卡」）：离线桩确定性产出
    // 500 kcal / ¥18.00（置信度三色点、count-up 同卡可见）。
    expect(find.byKey(const Key('capture_confirm_submit')), findsOneWidget);
    expect(find.text('测试晚餐 500kcal 花了18'), findsOneWidget,
        reason: 'AI 初值预填标题=原句');
    expect(find.text('500'), findsOneWidget, reason: '热量 count-up 终值');
    expect(find.text('¥18.00'), findsOneWidget, reason: '金额 count-up 终值（1800 分）');
    expect(find.text('AI 解析初值（§7.1）'), findsOneWidget, reason: '来源徽标');

    await tester.tap(find.byKey(const Key('capture_confirm_submit')));
    await tester.pumpAndSettle();

    // 确认后抽屉收起（§2.3 步 5「卡片飞入仪表盘槽位」）。
    expect(find.byKey(const Key('capture_confirm_submit')), findsNothing);

    // 仪表盘即时更新（唯一驱动=drift watch 流重发，§11 W2 数据底座）：
    // - 今日记录卡新条目（AI title=原句，离线桩确定性）；
    // - 摄入 500 kcal（§3.2 热量环卡指标行 + 环心）；
    // - 支出卡 25.50+18.00=¥43.50；AI 条目摘要「摄入 500 kcal · ¥18」。
    expect(find.text('测试晚餐 500kcal 花了18'), findsOneWidget);
    expect(find.text('摄入 500 kcal · ¥18'), findsOneWidget,
        reason: 'AI 条目摘要（yuanFromMinor 整元省 .00）');
    expect(find.text('¥43.50'), findsOneWidget, reason: '支出卡合计即时更新');
    expect(find.text('500 kcal'), findsOneWidget, reason: '摄入指标行=500');
    expect(find.text('500'), findsOneWidget, reason: '热量环心净 kcal=500');

    // ── W5-6：录入通道抽屉「说/拍」段（§3.3 三通道；语音链路 e2e 见
    //    e2e_voice_capture_test.dart，此处核对通道切换与缺省「写」档）──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    // 写（缺省）= CapturePage 渲染；说/拍 = W5-6 通道位。
    expect(find.byKey(const Key('capture_channel_text')), findsOneWidget);
    expect(find.byKey(const Key('capture_channel_voice')), findsOneWidget);
    expect(find.byKey(const Key('capture_channel_photo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture_channel_voice')));
    await tester.pump();
    // 说通道：面板标题 + 麦克风入口（Fake 链路只通面板，§3.3）。
    expect(find.text('说一笔'), findsOneWidget);
    expect(find.byKey(const Key('voice_capture_mic')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture_channel_text')));
    await tester.pump();
    expect(find.text('记一笔'), findsOneWidget, reason: '切回写通道复现 CapturePage');
    // 关闭抽屉（CapturePage 头部关闭钮）。
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == '关闭',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_channel_text')), findsNothing);

    // ── W5-6：账本 Tab 真页（§3.4 流水按日分组）────────────────────
    await tester.tap(find.text('账本'));
    await tester.pumpAndSettle();
    // 两条记录同日入组：日头合计 + 各条目标题（数据源=join 流重建 §6.1）。
    expect(find.text('测试午餐'), findsOneWidget);
    expect(find.text('测试晚餐 500kcal 花了18'), findsOneWidget);
    expect(find.textContaining('支出 ¥43.50'), findsWidgets,
        reason: '日头合计=两笔支出之和（25.50+18.00）');

    // ── W5-6：计划 Tab 真页（§4.2 三卡 + §3.6 待办快速添加）──────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('待办'), findsOneWidget);
    expect(find.text('健身'), findsOneWidget);
    expect(find.text('记录健身'), findsOneWidget,
        reason: '§4.3 /plan/fitness 子路由入口');
    expect(find.textContaining('存钱目标 P1'), findsOneWidget,
        reason: '§3.6 存钱 P1 占位卡');
    // 待办快速添加 → 当日流即时重发（§5.5⑩）。
    await tester.enterText(
      find.byKey(const Key('plan_todo_input')),
      '冥想 10 分钟',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan_todo_add')));
    await _pumpUntilFound(tester, find.text('冥想 10 分钟'));
    // 勾选完成 → done/total 计数刷新（§3.6 勾选完成、done_at 只前进 §6.5）。
    await tester.tap(find.text('冥想 10 分钟'));
    await _pumpUntilFound(tester, find.text('1/1'));
  });
}
