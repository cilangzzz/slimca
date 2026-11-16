// Slimca W5-6 语音 Fake 链路 e2e（§11.1 W5-6「语音端侧 ASR+云兜底」W5-6
// 只通 Fake 链路、§3.3 语音通道）：
//
// FakeTranscriber（脚本语料，零平台通道/零网络）→ 转写文本写回控制器
// inputText → 复用收敛后的 AI 解析管线（规范化/input_hash/CaptureParser，
// 缺省装配=HeuristicFakeLlmAdapter 离线桩，§7.1）→ 确认卡 → 提交口覆盖
// source=voice（§5.2① 录入来源）→ 同事务落库（entries + calorie/money 行 +
// ai_parses 留痕 + outbox 入队，§6.2）→ 仪表盘 reactive stream 即时重发
// （摄入/支出/净热量，§3.2）。
//
// 测试装配与 widget_test 同口径：内存 Drift 库 + 固定 device_id HlcClock
// override + bootstrap() 同款网关/解析器工厂；speechTranscriberProvider
// override 注入脚本化 Fake（禁真实平台通道，§3.3 离线优先）。

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
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';
import 'package:slimca/voice/speech_transcriber.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 core_db test_support 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：与 widget_test 同口径——drift 流取消
/// 后的延迟清缓存 Timer 在 fake_async 区无人清空会挂起测试（见 widget_test
/// 文件头注记）。
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

/// 小步轮询等待控件出现（解析呼吸态/置信度点为无限循环动画，pumpAndSettle
/// 永不收敛——与 widget_test 同策略）。
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
      'W5-6 语音 Fake 链路 e2e：FakeTranscriber → 解析 → 确认 → source=voice 落库 → 仪表盘即时更新',
      (WidgetTester tester) async {
    // 放大视口：抽屉表单/确认卡一屏放下，免滚动命中（与 widget_test 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，e2e 照常执行）。
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3）+ 内置账本种子（§5.4）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // W7-8 集成注：beforeOpen 默认数据 seed（§5.4）+ 内置账本种子把 24 条
    // seed 行同事务入队 sync_outbox——本用例断言的是本次语音提交的 3 条出网
    // 行（entry + 2 产出行），先清空 seed 出网项（seed 入队语义由 core_db
    // seed_idempotency_test 专属覆盖）。
    await database.delete(database.syncOutbox).go();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          // 语音链路注入点（§10.4）：脚本化 Fake，禁真实平台通道。
          speechTranscriberProvider.overrideWithValue(
            FakeTranscriber(transcripts: ['午餐牛肉面 500kcal 花了18']),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget);

    // ── 唤起通道抽屉并切「说」段（§3.3）────────────────────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('capture_channel_voice')));
    await tester.pump();
    expect(find.text('说一笔'), findsOneWidget);
    expect(find.byKey(const Key('voice_capture_mic')), findsOneWidget);

    // ── 转写：FakeTranscriber 出脚本语料（零延迟，pump 即达）────────
    await tester.tap(find.byKey(const Key('voice_capture_mic')));
    await _pumpUntilFound(tester, find.byKey(const Key('voice_capture_parse')));
    expect(
      find.textContaining('午餐牛肉面 500kcal 花了18'),
      findsOneWidget,
      reason: '转写文本展示（§3.3 语音通道产出=文本）',
    );

    // ── 解析：转写文本 → 收敛后的 AI 解析管线（与文本通道同构，§7.1）──
    await tester.tap(find.byKey(const Key('voice_capture_parse')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('capture_confirm_submit')),
    );
    // count-up 800ms 播完到终值（§9.3#4）。
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));

    // 确认卡（复用 feature_capture CaptureConfirmCard，§10.4）：离线桩
    // 确定性产出 500 kcal / ¥18.00。
    expect(find.byKey(const Key('capture_confirm_submit')), findsOneWidget);
    expect(find.text('午餐牛肉面 500kcal 花了18'), findsOneWidget,
        reason: 'AI 初值预填标题=转写原句');
    expect(find.text('500'), findsOneWidget, reason: '热量 count-up 终值');
    expect(find.text('¥18.00'), findsOneWidget, reason: '金额 count-up 终值');

    // ── 确认落库（提交口 source=voice，§5.2①）──────────────────────
    await tester.tap(find.byKey(const Key('capture_confirm_submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_confirm_submit')), findsNothing,
        reason: '提交成功后抽屉收起（§4.3）');

    // ── 仪表盘即时更新（明细流重发，§3.2；净=摄入−消耗 §3.5）────────
    expect(find.text('午餐牛肉面 500kcal 花了18'), findsOneWidget);
    expect(find.text('摄入 500 kcal · ¥18'), findsOneWidget,
        reason: 'AI 条目摘要（mixed 双行，yuanFromMinor 整元省 .00）');
    expect(find.text('¥18'), findsOneWidget,
        reason: '支出卡即时更新（分存储 1800 → 整元省 .00，§3.2 展示口径）');
    expect(find.text('500 kcal'), findsOneWidget, reason: '摄入指标行=500');
    expect(find.text('500'), findsOneWidget, reason: '热量环心净 kcal=500');

    // ── 落库口径断言（§5.2①②、§6.2）───────────────────────────────
    final entries = await database.select(database.entries).get();
    expect(entries.length, 1);
    final entry = entries.single;
    expect(entry.kind, 'mixed', reason: '双行=mixed（§5.2① kind 推导）');
    expect(entry.source, 'voice',
        reason: '说通道提交口 source=voice（§5.2① 录入来源）');
    expect(entry.status, 'confirmed', reason: '确认卡落库即 confirmed');
    expect(entry.aiParseId, isNotNull, reason: 'AI 路径 ai_parses 溯源（§5.2①）');
    expect(entry.title, '午餐牛肉面 500kcal 花了18');

    final lines = await database.select(database.entryLines).get();
    expect(lines.length, 2, reason: 'calorie 行 + money 行（§5.3 facet 拆行）');
    final calorieLine = lines.singleWhere((l) => l.type == 'calorie');
    final moneyLine = lines.singleWhere((l) => l.type == 'money');
    expect(calorieLine.amount, 500, reason: '摄入行=500 kcal');
    expect(calorieLine.direction, 'in', reason: 'calorie=in（§5.2②）');
    expect(calorieLine.confidence, isNotNull,
        reason: 'AI 产出行 confidence 必填（§5.2②）');
    expect(moneyLine.amount, 1800, reason: 'money 行=分存储 ¥18.00（§5.1）');
    expect(moneyLine.direction, 'out', reason: 'AI money 行恒支出（§5.2②）');

    final outboxRows = await database.select(database.syncOutbox).get();
    expect(outboxRows.length, 3,
        reason: 'entry + 2 行随写入队 outbox（§6.2 写路径纪律）');
    expect(
      outboxRows.map((r) => r.targetTable),
      unorderedEquals(['entries', 'entry_lines', 'entry_lines']),
      reason: '1 事件行 + 2 产出行（mixed 双行，§5.3 facet 拆行）',
    );

    final parses = await database.select(database.aiParses).get();
    expect(parses.length, 1, reason: 'ai_parses 留痕（§5.6⑭）');
  });
}
