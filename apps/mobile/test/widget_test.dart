// Slimca W2+W3-4+W5-6+W7-8+W13 冒烟测试（§11 W2 手动记一笔 → 仪表盘即时更新 +
// §11.1 W3-4 AI 双解析闭环 + §11.1 W5-6 录入通道/真页 Tab + §11.1 W7-8
// raw_input 上云开关/付费墙占位/遥测装配 + §11.2 W13 存钱卡空态与计划
// 存钱目标入口）——三接缝收敛后的壳层装配口径。
//
// 覆盖链路（§4.2 壳 + §9.3#3 录入抽屉 + §6.2 写路径 + §3.3 语音通道）：
// 冷启动首帧直出仪表盘（无 spinner §2.3 步 0）→ 4 Tab 导航壳（§4.2）→
// 中央「+」弹簧抽屉（W5-6 三通道 + W11-12 拍照段启用 §11.2：写=
// feature_capture CapturePage 唯一录入 UI，说=语音面板 W5-6 Fake 链路，
// 拍=拍照面板 W11-12 Fake 注入链路）→ 单边开关
// 「仅记钱」手动填表保存 → entries/entry_lines 落库 → 仪表盘明细流实时重发；
// W3-4：AI 一句话输入 → 缺省装配（dart-define 工厂无 key → core_ai
// HeuristicFakeLlmAdapter 完整管线，零真实网络）→ 确认卡 → 确认入账 →
// 仪表盘即时更新；W5-6：账本/计划 Tab 真页（§3.4 流水按日分组、§4.2 计划
// 三卡 + 待办快速添加 §3.6）；W13：仪表盘存钱卡与计划 Tab 存钱卡空态=
// 无目标引导创建（§11.2 W13 任务 1/2；建档→投币→数字变化 e2e 见
// savings_progress_card_test.dart）。
//
// W7-8（第二个用例）：我的 Tab → 分组卡 IA 渲染；V1 UX 插曲（《UI-规范与
// 重设计》§4.1）后：设置页按定稿 IA 重排（账号/同步卡→分组卡→尾部低频组），
// 「数据与隐私」开关组已移除（用户拍板，底层策略与 settings 落库机制保留），
// 断言「升级计划」无露出（IAP 代码保留、UI 不露出）+ 危险项确认弹窗（§4.3）。
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
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/settings/settings_page.dart';
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
    // 放大视口：抽屉表单/确认卡一屏放下，免滚动命中（与 capture_flow 同口径）；
    // W15 起取 3600 高——预算设置页四区块（含 22 条内置分类行）单屏尽收，
    // ListView(children:) 惰性构建下离屏区块不进树，断言需其在视口内。
    tester.view.physicalSize = const Size(900, 3600);
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

    // §4.2 四 Tab：今天 / 账本 / 计划 / 我的（「今天」×2 = 底部 Tab +
    // 首页日历「今天」锚定 pill，SlimcaCalendar §3.2 今日锚定簇）。
    expect(find.text('今天'), findsNWidgets(2));
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // W13 存钱进度卡（§3.2 卡片墙第 5 项、§11.2 W13 任务 2）：无目标空态
    // =引导创建（day_summary.savings_progress 快照 NULL 即此空态）。
    expect(find.textContaining('还没有存钱目标'), findsOneWidget,
        reason: '§11.2 W13 仪表盘存钱卡空态=无目标引导创建');

    // W14 训练中态卡（§11.2 W14 任务 4）：无进行中训练 → 不占位（§2.3
    // 零等待空屏；有训练且当日才渲染，剩余休息秒 e2e 见
    // plan_schedule_card_test.dart）。
    expect(find.textContaining('训练中 · '), findsNothing,
        reason: '§11.2 W14 无进行中训练 → 训练中态卡不占位');

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

    // 金额滚动直输（数字键盘类型 §7.3）：enterText ¥25.50（分存储转换，
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
    //    e2e_voice_capture_test.dart、拍照链路 e2e 见
    //    e2e_photo_capture_test.dart，此处核对通道切换与缺省「写」档）──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    // 写（缺省）= CapturePage 渲染；说/拍 = 通道位（拍段 W11-12 启用）。
    expect(find.byKey(const Key('capture_channel_text')), findsOneWidget);
    expect(find.byKey(const Key('capture_channel_voice')), findsOneWidget);
    expect(find.byKey(const Key('capture_channel_photo')), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture_channel_voice')));
    await tester.pump();
    // 说通道：面板标题 + 麦克风入口（Fake 链路只通面板，§3.3）。
    expect(find.text('说一笔'), findsOneWidget);
    expect(find.byKey(const Key('voice_capture_mic')), findsOneWidget);
    // 拍通道（§11.2 W11-12 任务 2「『拍』段启用」）：面板标题 + 拍照单一
    // 入口（仅入口渲染，不发起拍照——零平台通道/零网络；相册按钮不再
    // 并列露出，§10.4 单一入口纪律）。
    await tester.tap(find.byKey(const Key('capture_channel_photo')));
    await tester.pump();
    expect(find.text('拍一笔'), findsOneWidget);
    expect(find.byKey(const Key('capture_photo_camera')), findsOneWidget);
    expect(find.byKey(const Key('capture_photo_gallery')), findsNothing,
        reason: '拍照单一入口：相册选择不重复露出');
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

    // ── W15：账本 Tab 升级冒烟（§11.2 W15 任务 1：多账本切换器 + 报表/
    //    预算入口，§4.3 路由 /stats 与 /ledger/budgets）─────────────────
    expect(find.byKey(const Key('ledger_scope_switcher')), findsOneWidget,
        reason: 'W15 顶栏多账本切换器（§3.4 账本切换抽屉下拉形态）');
    expect(find.byKey(const Key('ledger_budget_entry')), findsOneWidget);
    expect(find.byKey(const Key('ledger_category_manage_entry')),
        findsOneWidget, reason: '分类管理入口（feature_ledger CategoryManagePage）');
    // 报表页（§4.3 /stats）：push → 周/月/年三档骨架渲染 → 返回账本栈。
    // 本用例已录 ¥43.50（当日两笔）→ 周档分类合计图例=¥43.50（页面本体=
    // feature_ledger ReportPage，壳层只做 §10.4 装配）。
    await tester.tap(find.byKey(const Key('ledger_stats_entry')));
    await tester.pumpAndSettle();
    expect(find.text('统计报表'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('钱-热量联动'), findsOneWidget,
        reason: 'W15 双轴联动卡渲染（§3.4 钱-热量双轴）');
    // 图例=per-分类合计（报表口径与账单流/事件拆行一致）：本用例两笔口径
    // 不同——W2 手动一笔无分类（¥25.50=未分类）；W3-4 AI 确认卡一笔挂
    // 「餐饮-正餐」（¥18.00）——图例两行而非合并 ¥43.50。
    expect(find.text('未分类 ¥25.50'), findsOneWidget,
        reason: '周档图例=W2 手动一笔（无分类行，报表与账单流口径一致）');
    expect(find.text('餐饮-正餐 ¥18.00'), findsOneWidget,
        reason: '周档图例=W3-4 AI 一笔（确认卡分类挂行）');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('统计报表'), findsNothing, reason: '返回回账本 Tab');
    // 预算设置页（§4.3 /ledger/budgets）：push → 三类表单渲染 → 返回。
    await tester.tap(find.byKey(const Key('ledger_budget_entry')));
    await tester.pumpAndSettle();
    expect(find.text('预算设置'), findsOneWidget);
    expect(find.text('每日总支出目标'), findsOneWidget);
    expect(find.text('每日热量目标'), findsOneWidget);
    expect(find.text('分类每日预算'), findsOneWidget);
    expect(find.text('月度预算'), findsOneWidget,
        reason: 'W15 月度周期表单（§5.4⑥ period_type=monthly）');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // ── W5-6：计划 Tab 真页（IA 重设计「今日为纲」：今日待办/今日健身/
    //    今日存钱三卡 + 收集箱/存钱目标/健身计划三个域尾行入口）──────────
    await tester.tap(find.text('计划'));
    await tester.pumpAndSettle();
    expect(find.text('今日待办'), findsOneWidget);
    expect(find.text('今日健身'), findsOneWidget);
    expect(find.text('记录健身'), findsOneWidget,
        reason: '健身卡尾「记录健身」→ 包版健身记录页（唯一手记入口）');
    // W13 存钱卡（§3.6、§11.2 W13 任务 1）：空态引导建档（尾行唯一入口，
    // 建档/投币流 e2e 见 savings_progress_card_test）。
    expect(find.textContaining('设定第一个存钱目标'), findsOneWidget,
        reason: '§11.2 W13 存钱卡空态=无目标引导创建');
    expect(find.text('存钱目标'), findsOneWidget,
        reason: '存钱尾行唯一入口 → /plan/savings');
    // W14 健身计划入口（§11.2 W14 任务 1）：卡尾唯一模板入口；空态=无排期
    // 引导；排期卡/训练链路 e2e 见 plan_schedule_card_test.dart。
    expect(find.text('健身计划'), findsOneWidget);
    expect(find.textContaining('今天没有健身安排'), findsOneWidget,
        reason: '§11.2 W14 健身卡空态=无排期引导（计划列表段已下沉）');
    expect(find.textContaining('收集箱'), findsOneWidget,
        reason: '待办卡尾收集箱唯一入口');
    // 待办快速添加 → 当日实例流即时重发（§5.5⑩）。
    await tester.enterText(
      find.byKey(const Key('plan_todo_input')),
      '冥想 10 分钟',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('plan_todo_add')));
    await _pumpUntilFound(tester, find.text('冥想 10 分钟'));
    // 勾选完成（勾选框就地 1 tap）→ done/total 计数刷新（§3.6 勾选完成、
    // done_at 只前进 §6.5；行点=编辑抽屉，勾选走勾选框——本页恰一枚勾选框）。
    await tester.tap(find.byType(Checkbox));
    await _pumpUntilFound(tester, find.text('1/1'));
  });

  testWidgets('W7-8+V1 插曲冒烟：设置页 IA 渲染（§4.1：无「升级计划」露出、'
      '分组卡/行、危险项弹窗）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，冒烟照常执行）。
      return;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // W7-8 装配同款最小集（§10.4）：遥测缺省 Noop（零副作用）。V1 插曲
    // （《UI-规范与重设计》§4.1）后设置页不再露出付费墙——IAP 抽象代码
    // （billing_provider/sku_catalog 等）保留不删，UI 无购买触点。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // ── 我的 Tab（§4.2：设置页 IA=账号/同步卡→功能分组→低频尾部）────
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    // 顶部账号/同步卡（§4.1「同步状态只读一行」；缺省=本地回环待用户凭据）
    // ——同步状态全文唯一出现处（数据分组的「同步」行是动作行，不再复述）。
    expect(find.textContaining('本地回环'), findsOneWidget);

    // §4.1 分组头（分组卡渲染，SlimcaMenuGroup）。
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);

    // ── §4.1 移除决策：设置页无「升级计划」露出（IAP 代码保留、UI 不露出，
    //    转化触点收敛到 AI 免费额度降级提示 §7.4）────────────────────────
    expect(find.text('升级 Slimca Pro'), findsNothing,
        reason: '§4.1：「升级计划」整块从主列表移除（产品拍板项）');
    expect(find.textContaining('恢复购买'), findsNothing,
        reason: '§4.3：裸「恢复购买」入口随付费墙一并移出');
    expect(find.textContaining('Pro 买断'), findsNothing);
    expect(find.textContaining('AI 能力订阅'), findsNothing,
        reason: '双轨 SKU 目录 UI 不露出（billing 代码保留待商业化）');
    expect(find.textContaining('Fake 计费流'), findsNothing);

    // 分组行渲染（§4.1 IA：外观=主题入口 / 数据=同步+导出 / 尾部=关于+版本）。
    expect(find.byKey(settingsThemeEntryKey), findsOneWidget);
    expect(find.text('同步'), findsOneWidget);
    expect(find.text('数据导出'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);

    // ── 危险项确认弹窗（§4.3：独立分组 + 具体动词按钮 + 取消不做默认）──
    await tester.ensureVisible(find.byKey(settingsClearDataKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(settingsClearDataKey));
    await tester.pumpAndSettle();
    expect(find.text('清空全部数据？'), findsOneWidget);
    // HIG alerts（§4.3）：按钮用具体动词「清空」，无「OK」。
    expect(find.widgetWithText(TextButton, '清空'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    // 取消路径：弹窗收起、无任何删除动作。
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部数据？'), findsNothing);
  });
}
