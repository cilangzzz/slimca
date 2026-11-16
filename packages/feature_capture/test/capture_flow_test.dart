/// 手动记账全链路 widget 测试（§11.1 W2 主线验收、§3.3/§3.4）。
///
/// 流程（真库 NativeDatabase.memory）：
/// 1. 填表单（数字键盘 → ¥18.50、选分类）→ 提交 → 断言库中
///    entries(kind=expense) + entry_lines(type=money) 正确（§5.2 facet 拆行）；
/// 2. 编辑既有记录 → 提交 → 断言旧行 superseded、新行 active 且
///    correction_of 指向旧行，corrections 审计行落库（§3.4 金额不可变）；
/// 3. 单边开关（§3.3）：仅记热量侧为占位区、不可提交（W3-4 接 AI）。
///
/// 数据前提：`AppDatabase.beforeOpen` 会 seed 默认数据（core_db
/// `seedDefaultData`：默认 money 账本「默认账本」+ kcal 账本 + 22 个内置
/// 中文分类，§5.4），因此用例直接使用内置分类（如「餐饮-早餐」），
/// 不再自建夹具行。
///
/// 运行前提：集成阶段已 `flutter pub get`（内存库经 drift/native 即可用）。
library;

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

/// 泵 CapturePage（ProviderScope 覆盖注入网关）并等待表单装载完成。
Future<void> _pumpCapture(
  WidgetTester tester,
  _Harness harness, {
  CaptureSeed seed = const CaptureSeed(),
}) async {
  // 放大视口：抽屉内容（键盘+表单）一屏放下，免滚动命中。
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureGatewayProvider.overrideWithValue(harness.gateway),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: Scaffold(body: CapturePage(seed: seed)),
      ),
    ),
  );
  await _pumpUntilFound(
      tester, find.byKey(const ValueKey('capture_amount_display')));
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
    '手动记一笔：填表单→提交→库中 entry+money line 正确（§11.1 W2 / §3.4 / §5.2）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpCapture(tester, harness);

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
    '编辑既有记录：金额修正走 correction 新增行 supersede 旧行（§3.4 金额不可变）',
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
    '单边开关：仅记热量为占位区且不可提交；金额为空同样禁用（§3.3/W3-4 预留）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      await _pumpCapture(tester, harness);

      // 空金额：保存禁用（canSubmit 要求金额 >0，§5.1）。
      expect(
        tester.widget<FilledButton>(find.byKey(captureSubmitKey)).onPressed,
        isNull,
      );

      // 切到「仅记热量」：占位区出现、提交禁用（热量输入区 W3-4 接 AI）。
      await tester.tap(find.text('仅记热量'));
      await tester.pump();
      expect(find.byKey(const ValueKey('capture_calorie_placeholder')),
          findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(captureSubmitKey)).onPressed,
        isNull,
        reason: '§3.3 单边开关：热量侧 W3-4 前不可提交',
      );

      // 切回「仅记钱」：占位区消失，金额仍为空 → 保存依旧禁用。
      await tester.tap(find.text('仅记钱'));
      await tester.pump();
      expect(find.byKey(const ValueKey('capture_calorie_placeholder')),
          findsNothing);
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
}
