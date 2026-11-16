/// 录入全链路 widget 测试（§11.1 W2「手动记账 CRUD 全链路」+ W3-4「AI 双解析
/// 闭环（文本）」、§3.3/§3.4、§2.4、§7）。
///
/// 流程（真库 NativeDatabase.memory + 注入 Fake 解析器，§3.3「测试一律用
/// 注入的 Fake/Mock 解析器，禁止真实网络调用」）：
/// 1. W2 手动记一笔（仅记钱档）：数字键盘 → 提交 → entries+money 行正确；
/// 2. W2 编辑既有记录：修正走新增 correction 行 supersede（金额不可变）；
/// 3. 单边开关（§3.3）：默认 AI 双解析、仅记热量仍走 AI、仅记钱回手动表单；
/// 4. W3-4 AI 双解析主链路：输入→解析→确认卡→份量滑杆校正→确认落库，
///    断言 entry(mixed)+calorie/money 行+food_items+ai_parses+corrections
///    （AI 初值 vs 用户确认差异，source=ai_corrected，§5.6⑮）；
/// 5. 失败降级（§7.4）：结构化失败 → 自动手填表单、原文保留、无 AI 痕迹；
/// 6. 最近 chip 复记（§2.4-1）：点选整卡预填、日期刷新到今天、无 AI 审计；
/// 7. input_hash 缓存（§3.3/§5.6⑭）：相同输入第二次解析直接复用 ai_parses 行；
/// 8. 仅记热量（kcal-only）：确认卡只产 calorie 行（§3.3 单边开关）。
///
/// 数据前提：`AppDatabase.beforeOpen` 会 seed 默认数据（core_db
/// `seedDefaultData`：默认 money 账本 + kcal 账本 + 内置中文分类，§5.4），
/// 因此用例直接使用内置分类（如「餐饮-正餐」），不再自建夹具行。
///
/// 运行前提：集成阶段已 `flutter pub get`（内存库经 drift/native 即可用）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
// BooleanExpressionOperators：`&` 谓词组合是 drift 扩展方法，需显式导入。
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
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

/// AI 输入样例（§7.2 例句口径）。
const String _aiText = '中午吃了兰州拉面花了 18';

/// 注入式 Fake 解析器（W3-4）：默认返回双行解析结果；[failure] 非空时抛
/// 结构化失败（§7.4），驱动降级路径测试。
class FakeParser implements CaptureParser {
  FakeParser(CaptureParseResult initialResult) : _result = initialResult;

  CaptureParseResult _result;

  /// 注入失败（非空 = parse 抛该异常）。
  CaptureStructuredFailure? failure;

  /// 解析器被真实调用的次数（缓存命中不再调用，§5.6⑭）。
  int calls = 0;

  /// 收到的请求（断言 input_hash/规范化口径，§7.1）。
  final List<CaptureParseRequest> requests = [];

  set result(CaptureParseResult value) => _result = value;

  @override
  Future<CaptureParseResult> parse(CaptureParseRequest request) async {
    calls++;
    requests.add(request);
    final failure = this.failure;
    if (failure != null) throw failure;
    return _result;
  }
}

/// 双行解析结果（§7.2 受约束输出形态）：calorie 550 kcal（低-中置信度 0.62，
/// 带菜品明细触发 food_items 落库）+ money ¥18.00（高置信度 0.93，
/// category_hint 命中内置「餐饮-正餐」）。
CaptureParseResult _dualParseResult() => CaptureParseResult(
      title: '兰州拉面',
      parseNotes: '份量按中碗估计；金额来自文本「18」',
      provider: 'fake',
      model: 'fake-1',
      promptVersion: 'w3-4-test-v1',
      latencyMs: 42,
      costMicro: 5,
      confidence: 0.8,
      lines: [
        const CaptureParsedLine(
          typeWire: 'calorie',
          amountKcal: 550,
          confidence: 0.62,
          items: [
            CaptureParsedItem(
              name: '牛肉拉面',
              portionG: 450,
              kcal: 500,
              proteinG: 25,
              carbG: 65,
              fatG: 12,
              confidence: 0.6,
            ),
          ],
        ),
        const CaptureParsedLine(
          typeWire: 'money',
          amountMinor: 1800,
          confidence: 0.93,
          categoryHint: '餐饮-正餐',
        ),
      ],
    );

/// 测试夹具：内存真库 + 注入 HlcClock + 录入网关。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  CaptureGateway? _gateway;

  cdb.AppDatabase get db => _db!;
  CaptureGateway get gateway => _gateway!;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，Capture 流程测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(deviceId: '3F8A12C0B7D4');
    _gateway = createCaptureGateway(db: db, clock: _clock!);
    return true;
  }

  Future<void> close() async {
    await _db?.close();
  }

  /// 按名称取内置分类 id（beforeOpen seed 的内置分类，§5.4⑤）。
  Future<String> presetCategoryId(String name, {required String kind}) async {
    final rows = await (db.select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind)))
        .get();
    return rows.single.id;
  }
}

/// 泵 CapturePage（ProviderScope 覆盖注入网关 + Fake 解析器）并等待表单装载。
///
/// [moneySide]=true：默认「钱+热量」档先渲染 AI 输入区，随后点「仅记钱」切到
/// W2 手动表单；编辑模式（seed.editEntryId）恒为手动表单。
Future<void> _pumpCapture(
  WidgetTester tester,
  _Harness harness, {
  CaptureSeed seed = const CaptureSeed(),
  FakeParser? parser,
  bool moneySide = false,
}) async {
  // 放大视口：抽屉内容（确认卡/表单）一屏放下，免滚动命中。
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureGatewayProvider.overrideWithValue(harness.gateway),
        if (parser != null) captureParserProvider.overrideWithValue(parser),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: Scaffold(body: CapturePage(seed: seed)),
      ),
    ),
  );

  if (moneySide) {
    await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
    await tester.tap(find.text('仅记钱'));
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('capture_amount_display')));
  } else if (seed.editEntryId != null) {
    await _pumpUntilFound(
        tester, find.byKey(const ValueKey('capture_amount_display')));
  } else {
    await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
  }
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

/// 向带 key 的 [CaptureTextField] 输入文本（TextField 是其内部子控件）。
Future<void> _enterText(WidgetTester tester, Key fieldKey, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 轮询等待 entries 达到 [count]，返回首个 entry id（提交落库的异步桥）。
Future<String> _waitForEntryCount(
  WidgetTester tester,
  _Harness harness,
  int count,
) async {
  for (var i = 0; i < 150; i++) {
    final rows = await harness.db.select(harness.db.entries).get();
    if (rows.length >= count) {
      return rows.first.id;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('提交未落库：entries 数量未达到 $count');
}

Future<void> _typeAmount(
  WidgetTester tester,
  List<String> keys,
) async {
  for (final key in keys) {
    await tester.tap(find.byKey(ValueKey('capture_key_$key')));
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'W2 手动记一笔：仅记钱档填表单→提交→库中 entry+money line 正确（§11.1 W2 / §3.4 / §5.2）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpCapture(tester, harness, moneySide: true);

      // MVP「恒默认账本」（§3.4 单账本 MVP）：seed 已建唯一 money 账本。
      final ledgers = await harness.gateway.loadMoneyLedgers();
      expect(ledgers, hasLength(1), reason: 'seedDefaultData 建默认 money 账本');
      expect(ledgers.first.name, '默认账本');
      expect(ledgers.first.currency, 'CNY');

      // 方向默认「支出」（§5.2② direction；expense=out）：
      // 分类按 kind=expense 过滤，income 分类不出现（§5.4⑤）。
      expect(find.text('工资'), findsNothing);

      // 数字键盘输入 ¥18.50（分存储转换，杜绝浮点 §5.1）。
      await _typeAmount(tester, ['1', '8', '.', '5', '0']);
      expect(find.text('18.50'), findsOneWidget);

      // 选分类（§5.4⑤ 内置分类，color_token 引用语义 token 名 §8.2）。
      final breakfastId =
          await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
      await tester.tap(find.text('餐饮-早餐'));
      await tester.pump();

      // 提交（提交按钮 spring 微动效随 MotionConfig 生效）。
      await tester.tap(find.byKey(captureSubmitKey));
      await tester.pump();

      final entryId = await _waitForEntryCount(tester, harness, 1);

      // ── entries 断言（§5.2①）──
      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.kind, 'expense',
          reason: '§5.2① kind 枚举无单金额语义：手动记账落 expense，方向由行表达');
      expect(entry.source, 'manual');
      expect(entry.status, 'confirmed', reason: '手动路径直接确认（draft 属 AI 语义）');
      expect(entry.title, '餐饮-早餐', reason: '标题缺省回填分类名（§5.2① title）');
      expect(entry.note, isNull);
      expect(entry.date, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
          reason: '§5.1 本地日历日 yyyy-MM-dd');
      expect(entry.tzOffsetMin, DateTime.now().timeZoneOffset.inMinutes,
          reason: '录入时本地时区偏移（§5.1 tz_offset_min）');
      expect(entry.deviceId, '3F8A12C0B7D4');
      expect(entry.deletedAt, isNull, reason: '软删墓碑：未删为 NULL（§5.1）');
      expect(entry.hlc, matches(_hlcPattern),
          reason: 'HLC 由 HlcClock 签发，定宽编码（§6.3）');
      expect(entry.aiParseId, isNull, reason: '手动路径无 AI 溯源（§5.2①）');

      // ── entry_lines 断言（§5.2② facet 行）──
      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line.type, 'money');
      expect(line.amount, 1850, reason: '§5.1 金额整数分存储（¥18.50=1850 分）');
      expect(line.direction, 'out');
      expect(line.status, 'active');
      expect(line.correctionOf, isNull);
      expect(line.currency, 'CNY', reason: 'money 行币种默认 CNY（§5.2②）');
      expect(line.categoryId, breakfastId);
      expect(line.ledgerId, ledgers.first.id);
      expect(line.confidence, isNull, reason: '人工行无置信度（§5.2②）');
      expect(line.hlc, matches(_hlcPattern));
      expect(line.hlc, isNot(entry.hlc),
          reason: 'facet 行独立 HLC/updated_at（§5.3 同步正确性）');
    },
  );

  testWidgets(
    'W2 编辑既有记录：金额修正走 correction 新增行 supersede 旧行（§3.4 金额不可变）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      // 先经网关落一笔 ¥18.50（2026-11-10 回记，挂内置分类），再以编辑模式打开。
      final ledger = await harness.gateway.ensureDefaultLedger();
      final breakfastId =
          await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
      final entryId = await harness.gateway.submitMoneyCapture(
        date: '2026-11-10',
        tzOffsetMin: 480,
        title: '早餐',
        amountMinor: 1850,
        direction: dom.LineDirection.outcome,
        ledgerId: ledger.id,
        categoryId: breakfastId,
        currency: 'CNY',
      );
      final oldRows = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      final oldLineId = oldRows.single.id;
      expect(oldRows.single.revision, 1);

      await _pumpCapture(
        tester,
        harness,
        seed: CaptureSeed(editEntryId: entryId),
      );

      // 回填断言：金额显示 ¥18.50 + 标题「早餐」+ 原金额对照行。
      expect(find.text('18.50'), findsOneWidget);
      expect(find.text('早餐'), findsOneWidget);
      expect(find.byKey(const ValueKey('capture_original_amount')),
          findsOneWidget, reason: '编辑模式展示原金额对照（§3.4）');

      // 修改金额：退格清空「18.50」（5 步）后输入 20 → ¥20.00。
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('capture_key_backspace')));
      }
      await tester.pump();
      await _typeAmount(tester, ['2', '0']);
      expect(find.text('20'), findsOneWidget);

      await tester.tap(find.byKey(captureSubmitKey));
      await tester.pump();

      // 等待旧行被置为 superseded（修正事务完成的异步桥）。
      for (var i = 0; i < 150; i++) {
        final rows = await harness.db.select(harness.db.entryLines).get();
        final hasSuperseded =
            rows.any((r) => r.id == oldLineId && r.status == 'superseded');
        if (hasSuperseded) break;
        await tester.pump(const Duration(milliseconds: 20));
      }

      // ── 修正链断言（§5.2② correction_of / §3.4 金额不可变）──
      final allLines = await harness.db.select(harness.db.entryLines).get();
      expect(allLines, hasLength(2), reason: '修正=新增行：旧行保留、新行追加');
      final oldRow = allLines.singleWhere((r) => r.id == oldLineId);
      expect(oldRow.status, 'superseded', reason: '§5.2② 旧行 status→superseded');
      expect(oldRow.amount, 1850, reason: '旧行金额原样保留（审计性，§3.4）');
      expect(oldRow.revision, 2, reason: '旧行 revision 本地自增（§5.1 写路径）');
      final newRow = allLines.singleWhere((r) => r.correctionOf == oldLineId);
      expect(newRow.status, 'active');
      expect(newRow.amount, 2000, reason: '新行金额 ¥20.00=2000 分');
      expect(newRow.entryId, entryId);
      expect(newRow.direction, 'out');
      expect(newRow.currency, 'CNY');
      expect(newRow.categoryId, breakfastId);
      expect(newRow.ledgerId, ledger.id);
      expect(newRow.revision, 1);
      expect(newRow.hlc, matches(_hlcPattern));
      expect(oldRow.hlc, matches(_hlcPattern),
          reason: 'supersede 以同一次用户操作的 HLC 戳旧行（§5.2②）');

      // 主干行 status→edited（§5.2① edited=含修正）。
      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.status, 'edited');
      expect(entry.date, '2026-11-10', reason: '未改日期则保持');

      // corrections 审计行（§5.6⑮ append-only：仅 amount 一个字段变更）。
      final audits = await harness.db.select(harness.db.corrections).get();
      expect(audits, hasLength(1));
      final amountAudit = audits.single;
      expect(amountAudit.field, 'amount');
      expect(amountAudit.oldValue, '1850');
      expect(amountAudit.newValue, '2000');
      expect(amountAudit.entryId, entryId);
      expect(amountAudit.lineId, oldLineId);
      expect(amountAudit.source, 'user');
    },
  );

  testWidgets(
    '单边开关（§3.3）：默认 AI 双解析输入区、仅记热量仍走 AI、仅记钱回 W2 手动表单',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final parser = FakeParser(_dualParseResult());

      await _pumpCapture(tester, harness, parser: parser);

      // 默认「钱+热量」：AI 文本输入区出现，数字键盘不出现（W3-4 双解析默认档）。
      expect(find.byKey(captureAiInputKey), findsOneWidget);
      expect(find.byKey(const ValueKey('capture_key_1')), findsNothing);

      // 「仅记热量」：仍是 AI 输入区（kcal-only 提示，§3.3），键盘不出现。
      await tester.tap(find.text('仅记热量'));
      await tester.pump();
      expect(find.byKey(captureAiInputKey), findsOneWidget);
      expect(find.text('如：喝了一杯黑咖啡（仅解析热量，§3.3）'), findsOneWidget);
      expect(find.byKey(const ValueKey('capture_key_1')), findsNothing);

      // 「仅记钱」：W2 手动表单回归；空金额保存禁用（canSubmit 金额>0，§5.1）。
      await tester.tap(find.text('仅记钱'));
      await _pumpUntilFound(
          tester, find.byKey(const ValueKey('capture_amount_display')));
      expect(find.byKey(captureAiInputKey), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(captureSubmitKey)).onPressed,
        isNull,
      );

      // 键入金额后保存可用（键盘输入与单边开关状态互不干扰，§3.3）。
      await _typeAmount(tester, ['1', '8']);
      expect(find.text('18'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(captureSubmitKey)).onPressed,
        isNotNull,
      );

      // 全程未提交：无任何落库。
      expect((await harness.db.select(harness.db.entries).get()), isEmpty);
    },
  );

  testWidgets(
    'W3-4 AI 双解析主链路：解析→确认卡→滑杆校正→确认落库（entry+calorie+money 行+food_items+ai_parses+corrections）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final parser = FakeParser(_dualParseResult());

      await _pumpCapture(tester, harness, parser: parser);

      // 输入 → 解析（§3.3「文本输入区 → 解析」）。
      await _enterText(tester, captureAiInputKey, _aiText);
      await tester.tap(find.byKey(captureParseButtonKey));

      // 确认卡出现（解析为 Fake 即时返回；等待本身跨过解析中呼吸态）。
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      // SlimcaConfidenceDot 持续 pulse → 不可 pumpAndSettle；
      // 定长 pump 900ms 让 count-up（800ms，§9.3#4）与环 sweep 走完。
      await tester.pump(const Duration(milliseconds: 900));

      // ── AI 初值预填断言（§3.3「标题/热量/金额/分类/置信度」）──
      expect(find.text('AI 解析初值（§7.1）'), findsOneWidget);
      expect(find.text('兰州拉面'), findsOneWidget, reason: '标题预填 AI 建议');
      expect(find.text('550'), findsOneWidget, reason: '热量 count-up 终值（§9.3#4）');
      expect(find.text('¥18.00'), findsOneWidget, reason: '金额 count-up 终值');
      expect(find.text('置信度 62%'), findsOneWidget, reason: '热量行置信度三档标注');
      expect(find.text('置信度 93%'), findsOneWidget, reason: '金额行置信度三档标注');
      expect(find.byKey(captureLowConfidenceBannerKey), findsNothing,
          reason: '0.62≥0.5 不触发低置信度强制高亮（§3.3）');
      expect(find.text('解析备注：份量按中碗估计；金额来自文本「18」'), findsOneWidget,
          reason: 'parse_notes 展示（§7.3）');
      final zhengcanId =
          await harness.presetCategoryId('餐饮-正餐', kind: 'expense');
      expect(find.text('餐饮-正餐'), findsOneWidget,
          reason: 'category_hint 命中内置分类（§7.3）');

      // 份量滑杆联动重算（§3.3）：滑杆 0.5-2.0、divisions 12 → 中心点恰为 1.25x，
      // 550 → round(550×1.25)=688。
      await tester.tap(find.byKey(capturePortionSliderKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('688'), findsOneWidget, reason: '确认热量=基准×倍率（§3.3）');
      expect(find.text('份量 x1.25'), findsOneWidget);

      // 确认落库（§3.3「确认后金额不可变」；经 gateway 同事务写，§5.2）。
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      // ── entries 断言（§5.2①）：kind 由行集合推导（双行=mixed）──
      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.kind, 'mixed', reason: '§5.2① 双行=mixed（任务口径 meal=food 枚举）');
      expect(entry.source, 'text', reason: '§5.2① source：AI 文本解析');
      expect(entry.status, 'confirmed', reason: '用户已在确认卡确认（§3.3）');
      expect(entry.title, '兰州拉面');
      expect(entry.note, '份量按中碗估计；金额来自文本「18」');
      expect(entry.aiParseId, isNotNull, reason: 'ai_parses.id 溯源（§5.2①）');
      expect(entry.hlc, matches(_hlcPattern));

      // ── ai_parses 留痕断言（§5.6⑭：input_hash=sha256(规范化输入)）──
      final parses = await harness.db.select(harness.db.aiParses).get();
      expect(parses, hasLength(1));
      final parse = parses.single;
      expect(entry.aiParseId, parse.id);
      expect(parse.inputKind, 'text');
      expect(
        parse.inputHash,
        CaptureInputNormalizer.inputHash(
            CaptureInputNormalizer.normalize(_aiText)),
        reason: '§7.1/§5.6⑭ input_hash 口径',
      );
      expect(parse.provider, 'fake');
      expect(parse.model, 'fake-1');
      expect(parse.promptVersion, 'w3-4-test-v1');
      expect(parse.latencyMs, 42);
      expect(parse.cost, 5, reason: '成本微元留痕（§5.6⑭）');
      expect(parser.requests.single.rawText, _aiText,
          reason: 'adapter 收到原文（即用即焚，§3.3）');

      // ── entry_lines 断言（§5.2②）：calorie 行 + money 行 ──
      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(lines, hasLength(2));
      final kcalLine = lines.singleWhere((l) => l.type == 'calorie');
      final moneyLine = lines.singleWhere((l) => l.type == 'money');

      final kcalLedger = await harness.gateway.ensureKcalLedger();
      expect(kcalLine.amount, 688, reason: '滑杆校正后的确认热量');
      expect(kcalLine.direction, 'in', reason: '§5.2② calorie=in（摄入）');
      expect(kcalLine.ledgerId, kcalLedger.id,
          reason: '§5.2② kcal 行归集内置 kcal 账本');
      expect(kcalLine.confidence, 0.62, reason: 'AI 产出行必填置信度（§5.2②）');
      expect(kcalLine.currency, isNull, reason: 'kcal 行无币种');
      expect(kcalLine.correctionOf, isNull);
      final payload = jsonDecode(kcalLine.payload!) as Map<String, Object?>;
      expect(payload['portion_multiplier'], 1.25, reason: 'payload 摘要留痕（§3.3）');
      final payloadItems = payload['items']! as List<Object?>;
      expect(payloadItems, hasLength(1));
      final payloadItem = payloadItems.single as Map<Object?, Object?>;
      expect(payloadItem['kcal'], 625, reason: '菜品热量随倍率重算（§3.3）');
      expect(payloadItem['portion_g'], 562.5);

      final moneyLedger = (await harness.gateway.loadMoneyLedgers()).first;
      expect(moneyLine.amount, 1800, reason: '§5.1 金额整数分（¥18.00）');
      expect(moneyLine.direction, 'out');
      expect(moneyLine.ledgerId, moneyLedger.id);
      expect(moneyLine.currency, 'CNY');
      expect(moneyLine.categoryId, zhengcanId, reason: 'hint 命中「餐饮-正餐」');
      expect(moneyLine.confidence, 0.93);
      expect(moneyLine.payload, isNull);

      // ── food_items 逐菜品断言（§7.3「items[] → food_items 逐菜品」）──
      final foods = await harness.db.select(harness.db.foodItems).get();
      expect(foods, hasLength(1));
      final food = foods.single;
      expect(food.entryId, entryId);
      expect(food.lineId, kcalLine.id);
      expect(food.name, '牛肉拉面');
      expect(food.portionG, 562.5, reason: '份量随滑杆倍率重算（§5.2③）');
      expect(food.kcal, 625);
      expect(food.refSource, 'local');
      expect(food.confidence, 0.6);
      expect(food.userAdjusted, false);

      // ── corrections 差异审计（§5.6⑮：AI 初值 vs 用户确认）──
      final audits = await (harness.db.select(harness.db.corrections)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(audits, hasLength(1),
          reason: '唯一差异=滑杆改热量；标题/金额/分类与初值一致不产行');
      final audit = audits.single;
      expect(audit.field, 'kcal');
      expect(audit.oldValue, '550', reason: 'AI 初值（§5.6⑮ 前值）');
      expect(audit.newValue, '688', reason: '用户确认值');
      expect(audit.source, 'ai_corrected', reason: 'W3-4 口径：AI 预填被确认改动');
      expect(audit.entryId, entryId);
      expect(audit.lineId, kcalLine.id);
    },
  );

  testWidgets(
    'W3-4 失败降级（§7.4）：结构化失败→自动手填表单、原文保留、无 AI 痕迹落库',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final parser = FakeParser(_dualParseResult())
        ..failure = const CaptureStructuredFailure(
          code: CaptureFailureCode.provider,
          message: '供应商不可用',
        );

      await _pumpCapture(tester, harness, parser: parser);
      await _enterText(tester, captureAiInputKey, _aiText);
      await tester.tap(find.byKey(captureParseButtonKey));

      // 降级表单出现（§7.4「原输入保留 → 自动降级手填表单」）。
      await _pumpUntilFound(tester, find.byKey(captureFallbackBannerKey));
      expect(find.textContaining('供应商不可用'), findsOneWidget,
          reason: '结构化失败文案透出（§7.4）');
      expect(find.byKey(captureParseButtonKey), findsNothing,
          reason: '解析入口已被表单替换（自动切换）');
      expect(find.text(_aiText), findsOneWidget,
          reason: '§2.4-3「绝不丢用户已输入文本」：标题预填原文');
      expect(find.byKey(const ValueKey('capture_manual_kcal_field')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('capture_manual_amount_field')),
          findsOneWidget);

      // 手填热量 + 金额 → 保存。
      await _enterText(tester,
          const ValueKey('capture_manual_kcal_field'), '550');
      await _enterText(tester,
          const ValueKey('capture_manual_amount_field'), '18.50');
      await tester.tap(find.byKey(captureSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      // ── 落库断言：source=manual、无 AI 溯源/置信度 ──
      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.kind, 'mixed', reason: '手填双行同样 mixed（§5.2①）');
      expect(entry.source, 'manual', reason: '§5.2① source：手填');
      expect(entry.aiParseId, isNull, reason: '失败路径无 AI 溯源');
      expect(entry.title, _aiText);

      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(lines, hasLength(2));
      final kcalLine = lines.singleWhere((l) => l.type == 'calorie');
      final moneyLine = lines.singleWhere((l) => l.type == 'money');
      expect(kcalLine.amount, 550);
      expect(kcalLine.confidence, isNull, reason: '人工行无置信度（§5.2②）');
      expect(moneyLine.amount, 1850);
      expect(moneyLine.confidence, isNull);
      expect(moneyLine.currency, 'CNY');

      // 失败路径不留 AI 痕迹：ai_parses 无行（坏输出不留痕，§7.4）、无审计行。
      expect((await harness.db.select(harness.db.aiParses).get()), isEmpty);
      expect((await harness.db.select(harness.db.corrections).get()), isEmpty);
    },
  );

  testWidgets(
    'W3-4 最近 chip 复记（§2.4-1）：点选整卡预填、日期刷新到今天、无 AI 初值审计',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      // 经网关直接落一条种子记录（标题+热量+金额，2026-11-10 回记）。
      final ledger = await harness.gateway.ensureDefaultLedger();
      final breakfastId =
          await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
      final seedEntryId = await harness.gateway.submitAiCapture(
        CaptureAiSubmitRequest(
          date: '2026-11-10',
          tzOffsetMin: 480,
          title: '牛肉面加蛋',
          source: dom.EntrySource.text,
          kcal: 550,
          amountMinor: 1850,
          moneyDirection: dom.LineDirection.outcome,
          ledgerId: ledger.id,
          categoryId: breakfastId,
          currency: 'CNY',
        ),
      );

      final parser = FakeParser(_dualParseResult());
      await _pumpCapture(tester, harness, parser: parser);

      // 最近 chip 出现（§2.4-1 最近记录横滑）→ 点选整卡预填。
      await _pumpUntilFound(
          tester, find.byKey(ValueKey('capture_recent_chip_$seedEntryId')));
      expect(find.text('牛肉面加蛋'), findsOneWidget, reason: 'chip 展示原标题');
      await tester.tap(find.byKey(ValueKey('capture_recent_chip_$seedEntryId')));

      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('牛肉面加蛋'), findsOneWidget, reason: '标题预填');
      expect(find.text('550'), findsOneWidget, reason: '热量预填原值');
      expect(find.text('¥18.50'), findsOneWidget, reason: '金额预填原值');
      expect(find.text('餐饮-早餐'), findsOneWidget, reason: '分类预填原分类');
      expect(find.text(dom.formatCalendarDay(DateTime.now())), findsOneWidget,
          reason: '§2.4-1 复记日期刷新到今天');

      // 确认落库（source=chip）。
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      await _waitForEntryCount(tester, harness, 2);

      final rows = await harness.db.select(harness.db.entries).get();
      final newEntry =
          rows.singleWhere((r) => r.id != seedEntryId, orElse: () => throw StateError('复记未生成新事件'));
      expect(newEntry.source, 'chip', reason: '§5.2① source：复记');
      expect(newEntry.kind, 'mixed');
      expect(newEntry.aiParseId, isNull, reason: '复记无 AI 溯源（§5.2①）');
      expect(newEntry.title, '牛肉面加蛋');
      expect(newEntry.date, dom.formatCalendarDay(DateTime.now()),
          reason: '§2.4-1 日期刷新到今天');

      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(newEntry.id)))
          .get();
      expect(lines, hasLength(2));
      final kcalLine = lines.singleWhere((l) => l.type == 'calorie');
      final moneyLine = lines.singleWhere((l) => l.type == 'money');
      expect(kcalLine.amount, 550);
      expect(kcalLine.confidence, isNull, reason: '复记行人工语义（§5.2②）');
      expect(moneyLine.amount, 1850);
      expect(moneyLine.categoryId, breakfastId);
      expect(moneyLine.ledgerId, ledger.id);

      // 复记路径无 AI 审计（初值快照为 null）且无 ai_parses。
      final auditRows = await (harness.db.select(harness.db.corrections)
            ..where((t) => t.entryId.equals(newEntry.id)))
          .get();
      expect(
        auditRows,
        isEmpty,
        reason: '§5.6⑮ 复记无「AI 初值 vs 确认」差异',
      );
      expect((await harness.db.select(harness.db.aiParses).get()), isEmpty);
    },
  );

  testWidgets(
    'W3-4 input_hash 缓存（§3.3/§5.6⑭）：相同输入第二次解析直接复用、解析器不再被调',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final parser = FakeParser(_dualParseResult());

      await _pumpCapture(tester, harness, parser: parser);
      await _enterText(tester, captureAiInputKey, _aiText);
      await tester.tap(find.byKey(captureParseButtonKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      final firstEntryId = await _waitForEntryCount(tester, harness, 1);

      // 重新解析 → 回输入区（原文保留，§7.4）→ 再次解析。
      await tester.tap(find.byKey(captureReparseButtonKey));
      await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
      expect(find.text(_aiText), findsOneWidget, reason: '原文保留（§7.4）');
      await tester.tap(find.byKey(captureParseButtonKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      // 缓存命中断言：解析器只被调用一次；徽标显示缓存复用（§3.3）。
      expect(parser.calls, 1, reason: '§5.6⑭ 相同 input_hash 7 天内直接复用');
      expect(find.text('AI 解析 · 缓存复用（§3.3）'), findsOneWidget);
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await _waitForEntryCount(tester, harness, 2);

      // 两条事件共享同一 ai_parses 行（缓存回放，§5.6⑭ raw_output）。
      final rows = await harness.db.select(harness.db.entries).get();
      final parses = await harness.db.select(harness.db.aiParses).get();
      expect(parses, hasLength(1));
      final parseId = parses.single.id;
      final ids = rows.map((r) => r.aiParseId).toSet();
      expect(ids, {parseId}, reason: '缓存复用共享同一 ai_parses.id');
      expect(rows, hasLength(2));
      expect(rows.map((r) => r.id), contains(firstEntryId));

      // 缓存路径不重复落审计：两次确认均与初值一致（未改动）。
      expect((await harness.db.select(harness.db.corrections).get()), isEmpty);
    },
  );

  testWidgets(
    'W3-4 仅记热量（kcal-only，§3.3）：确认卡只产 calorie 行、无 money 行',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final parser = FakeParser(_dualParseResult());

      await _pumpCapture(tester, harness, parser: parser);
      await tester.tap(find.text('仅记热量'));
      await tester.pump();
      await _enterText(tester, captureAiInputKey, '喝了一杯黑咖啡');
      await tester.tap(find.byKey(captureParseButtonKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      // 确认卡只有热量区：金额点改框/金额数字/账本选择都不出现（§3.3 lines
      // 只产出一类）。
      expect(find.byKey(captureConfirmAmountFieldKey), findsNothing);
      expect(find.text('¥18.00'), findsNothing);
      expect(find.text('账本'), findsNothing);
      expect(find.text('550'), findsOneWidget);
      expect(find.text('置信度 62%'), findsOneWidget);

      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.kind, 'food',
          reason: '仅热量=food（§5.2①；任务口径 meal 对应文档 food 枚举）');
      expect(entry.source, 'text');
      expect(entry.aiParseId, isNotNull);

      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(lines, hasLength(1), reason: 'kcal-only 只产 calorie 行（§3.3）');
      expect(lines.single.type, 'calorie');
      expect(lines.single.amount, 550);
      expect(lines.single.direction, 'in');
      expect(lines.single.confidence, 0.62);

      // AI 留痕在、差异审计无（初值未被改动）。
      expect((await harness.db.select(harness.db.aiParses).get()), hasLength(1));
      expect((await harness.db.select(harness.db.corrections).get()), isEmpty);
    },
  );
}
