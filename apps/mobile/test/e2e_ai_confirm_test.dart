// E2E 专项验收（§11.1 W3-4 验收线：「打开 → 确认」AI 双解析闭环（文本路径））。
//
// 与 widget_test.dart（缺省离线桩冒烟）、e2e_record_to_dashboard_test.dart
// （W2 手动记一笔→仪表盘即时更新）互补，本用例按 W3-4 验收口径逐环断言：
// - 注入式确定性脚本桩（core_ai FakeLlmAdapter.scripted → LlmAiParser 完整
//   管线 → CoreAiCaptureParser 桥，§10.4 收敛装配；零真实网络）；
// - 文本「早餐两个包子 ¥6」→ 解析 → 确认卡出现，热量/金额 count-up 播完
//   后数值稳定（§9.3#4）；
// - 确认 → entries + calorie（500 kcal 类）+ money（600 分）行 + food_items
//   落库；
// - corrections 审计随确认落库（§5.6⑮：确认卡上改标题 → 字段级审计行，
//   收敛后 source=ai_corrected——「AI 初值 vs 用户确认」差异审计）；
// - ai_parses 留痕（§5.6⑭）+ 仪表盘即时更新（唯一驱动=drift watch 流重发）。
//
// 测试装配与既有 e2e 同一口径：内存 Drift 真库 + 固定 device_id 的 HlcClock
// 直接 override（不跑 bootstrap()）；feature_capture 网关按 bootstrap() 同款
// 工厂注入（§10.4）；内置账本种子 ensureDefaultLedgers 补齐（§5.4）。Windows
// 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'dart:convert';

import 'package:core_ai/core_ai.dart';
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

import 'package:slimca/ai/capture_parser_bridge.dart';
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

/// 打开内存真库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
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

/// 注入式确定性脚本桩（任务验收口径：FakeParser 注入改为 core_ai 适配器
/// 注入——FakeLlmAdapter.scripted 产受约束 JSON，经 LlmAiParser 完整管线
/// （受约束解码 + 校验 + §7.3 映射）与 CoreAiCaptureParser 桥，§10.4）。
///
/// 「早餐两个包子 ¥6」→ 500 kcal（两个包子量级，§11.1 W3-4 验收「500kcal 类」）
/// + 600 分（¥6，§5.1 分存储）；行级置信度取 §7.2 示例同款 0.62/0.93
/// （黄/绿三色点各现一次，§7.3 口径）。同输入恒同结果，无随机/时钟/网络。
CoreAiCaptureParser _scriptedParser() {
  const constrainedJson =
      '{"title":"早餐两个包子 ¥6","kind":"mixed",'
      '"parse_notes":"份量按两个包子估计；金额来自文本「¥6」",'
      '"lines":['
      '{"type":"calorie","amount_kcal":500,"confidence":0.62,'
      '"category_hint":"餐饮-早餐","items":[]},'
      '{"type":"money","amount_minor":600,"currency":"CNY",'
      '"confidence":0.93,"ledger_hint":"default"}]}';
  return CoreAiCaptureParser(
    adapter: FakeLlmAdapter.scripted(
      [jsonEncode(jsonDecode(constrainedJson))],
      providerId: 'fake-scripted',
      modelId: 'e2e-deterministic-v1',
    ),
  );
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
  testWidgets(
      'E2E：脚本桩（core_ai 管线）注入 → 「早餐两个包子 ¥6」→ 确认卡（count-up 后稳定）→ '
      '确认 → entry + calorie/money 行 + corrections 审计（ai_corrected）+ 仪表盘即时更新',
      (WidgetTester tester) async {
    // 放大视口：抽屉确认卡一屏放下，免滚动命中（与 capture_flow 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，E2E 照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AI 确认闭环 E2E 未执行');
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3）+ 内置账本种子（§5.4：默认 money 账本 + kcal 账本）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          // 脚本桩注入（§11.1 W3-4 验收：默认 mock 路径的显式注入形态，
          // 收敛后注入点 = captureParserProvider，实现 = core_ai 管线桥）。
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(_scriptedParser()),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsNothing,
        reason: '完整壳已起（首页 AppBar 无产品名标题，用户拍板移除）');

    // ── 打开录入抽屉 → 一句话输入 → 解析（§3.3 步 2-3）──────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_ai_input')), findsOneWidget);
    expect(find.byKey(const Key('capture_parse_button')), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('capture_ai_input')),
        matching: find.byType(TextField),
      ),
      '早餐两个包子 ¥6',
    );
    await tester.pump();
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
    expect(find.byKey(const Key('capture_confirm_submit')), findsOneWidget);

    // ── count-up 稳定（§9.3#4：数值滚到终值后不再变化）──────────────
    // pumpAndSettle 已收敛全部单次动画；再推固定时长两次，断言终值不变。
    // 确认卡热量区：SlimcaCountUp 整数 + 独立「kcal」单位文本；金额区
    // SlimcaMoneyCountUp 恒两位小数（§5.1 展示换算）。
    expect(find.text('500'), findsOneWidget, reason: '热量 count-up 终值');
    expect(find.text('kcal'), findsOneWidget);
    expect(find.text('¥6.00'), findsOneWidget, reason: '金额 count-up 终值（600 分）');
    expect(find.text('AI 解析初值（§7.1）'), findsOneWidget, reason: '来源徽标');
    expect(find.text('解析备注：份量按两个包子估计；金额来自文本「¥6」'),
        findsOneWidget, reason: 'parse_notes 上卡（§7.3）');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('500'), findsOneWidget, reason: 'count-up 已稳定');
    expect(find.text('¥6.00'), findsOneWidget, reason: 'count-up 已稳定');

    // ── 确认卡上修正标题（§2.3 步 4「先拍后改」→ corrections 审计行）──
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('capture_confirm_title')),
        matching: find.byType(TextField),
      ),
      '早餐两个包子',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture_confirm_submit')));
    await tester.pumpAndSettle(); // 确认落库 + 抽屉弹簧收起 + 明细流重发

    // 抽屉已收起：确认按钮不在树上（§2.3 步 5「卡片飞入仪表盘槽位」）。
    expect(find.byKey(const Key('capture_confirm_submit')), findsNothing);

    // ── 仪表盘即时更新（唯一驱动=drift watch 流重发，§2.3 步 5/6）────
    // 今日记录卡新条目（确认标题）+ 摘要「摄入 500 kcal · ¥6」。
    expect(find.text('早餐两个包子'), findsOneWidget);
    expect(find.text('摄入 500 kcal · ¥6'), findsOneWidget);
    // 支出卡：¥0 → ¥6（600 分，§5.1 展示换算）。
    expect(find.text('¥0'), findsNothing, reason: '旧零值已被流重发改写');
    expect(find.text('¥6'), findsWidgets, reason: '支出卡即时更新（与摘要同源）');
    // 热量环卡：环心净 kcal 0 → 500；摄入指标行同步；消耗仍为 0。
    expect(find.text('摄入 0 kcal'), findsNothing, reason: '摄入指标已更新');
    expect(find.text('500 kcal'), findsOneWidget, reason: '摄入指标=500');
    expect(find.text('0 kcal'), findsNWidgets(2), reason: '消耗两处仍为 0');
    expect(find.text('500'), findsOneWidget, reason: '环心净 kcal=摄入 500');
    expect(find.text('0'), findsNothing, reason: '环心旧零值已更新');

    // ── 落库保真：entries 主干 + facet 拆行（§5.2/§5.3）──────────────
    final entries = await database.select(database.entries).get();
    expect(entries, hasLength(1), reason: '一笔事件一条 entries 主干');
    final entry = entries.single;
    expect(entry.title, '早餐两个包子', reason: '确认标题落库（§5.2①）');
    expect(entry.kind, 'mixed', reason: '热量+金额 → mixed（§5.2①）');
    expect(entry.source, 'text', reason: 'AI 文本通道（§5.2① source）');
    expect(entry.status, 'confirmed', reason: '确认落库（§5.2① status）');
    expect(entry.aiParseId, isNotNull, reason: 'ai_parses.id 溯源（§5.6⑭）');
    expect(entry.note, '份量按两个包子估计；金额来自文本「¥6」',
        reason: 'parse_notes → entries.note 追加（§7.3）');
    expect(entry.date, formatCalendarDay(DateTime.now()),
        reason: '归属日=抽屉唤起日（§3.2）');

    final lines = await (database.select(database.entryLines)
          ..where((t) => t.entryId.equals(entry.id)))
        .get();
    final kcalLines = lines.where((l) => l.type == 'calorie').toList();
    final moneyLines = lines.where((l) => l.type == 'money').toList();
    expect(kcalLines, hasLength(1), reason: 'calorie 行（§5.3 拆行）');
    expect(kcalLines.single.amount, 500, reason: 'W3-4 验收：500kcal 类');
    expect(kcalLines.single.direction, 'in', reason: 'calorie=in（§5.2②）');
    expect(kcalLines.single.confidence, 0.62,
        reason: 'AI 产出行必带置信度（§5.2②）');
    expect(moneyLines, hasLength(1), reason: 'money 行（§5.3 拆行）');
    expect(moneyLines.single.amount, 600, reason: 'W3-4 验收：600 分（¥6）');
    expect(moneyLines.single.direction, 'out', reason: '文本路径恒出账（§5.2②）');
    expect(moneyLines.single.currency, 'CNY');
    expect(moneyLines.single.confidence, 0.93);

    // ── ai_parses 留痕（§5.6⑭）：网关 saveAiParse 落一行，raw_output=
    //    CaptureParseResult JSON（缓存回放格式），provider 透传脚本桩值。
    final parses = await database.select(database.aiParses).get();
    expect(parses, hasLength(1), reason: '收敛后单行留痕（core_ai 内部缓存为'
        '内存 memo，不双写 ai_parses）');
    expect(parses.single.id, entry.aiParseId);
    expect(parses.single.inputKind, 'text');
    expect(parses.single.provider, 'fake-scripted');
    expect(parses.single.inputHash, isNotEmpty);
    // raw_output 是 CaptureParseResult JSON（回放键）——含收敛桥映射的行。
    final replay =
        jsonDecode(parses.single.rawOutput) as Map<String, Object?>;
    expect(replay['title'], '早餐两个包子 ¥6');
    expect((replay['lines']! as List<Object?>), hasLength(2));

    // ── corrections 审计（§5.6⑮：改标题 → 字段级 append-only 一行）──
    // 热量/金额未改 → 不落审计（确认 ≠ 修正）；仅标题一处修正；
    // source=ai_corrected（W3-4 收敛口径：「AI 初值 vs 用户确认」差异）。
    final corrections = await database.select(database.corrections).get();
    expect(corrections, hasLength(1), reason: '仅标题一处修正（§5.6⑮）');
    final audit = corrections.single;
    expect(audit.entryId, entry.id);
    expect(audit.lineId, isNull, reason: '主干字段修正 line_id=NULL（§5.6⑮）');
    expect(audit.field, 'title');
    expect(audit.oldValue, '早餐两个包子 ¥6', reason: 'old_value=AI 初值');
    expect(audit.newValue, '早餐两个包子', reason: 'new_value=用户确认值');
    expect(audit.source, 'ai_corrected', reason: '§5.6⑮ 差异审计来源');
  });
}
