/// 健身手动记录全链路 widget 测试（§11.1 W5-6 主线任务 1 验收、§3.5、
/// §5.5⑦、§5.6）。
///
/// 数据前提：内存真库（NativeDatabase.memory，§10.1 测试口径「真库 + Fake」，
/// 禁真实网络/平台通道）；`AppDatabase.beforeOpen` seed 默认账本（含内置
/// kcal 账本，§5.4）。断言三行同事务落库与投影重算：
/// 1. 记 30 分钟慢跑（中强度、70kg）→ fitness_sessions + burn 行落库、
///    day_summary.kcal_out=245 / net=-245（W5-6 验收「投影重算后 burn 计入」）；
/// 2. 删除 → 墓碑软删 + kcal_out 回落 0（§5.1/§5.6）。
///
/// 运行前提：集成阶段已 `flutter pub get`；宿主缺 sqlite3 运行库时温和跳过
/// （Windows 桌面常见，§10.1 测试口径）。
library;

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

/// 测试夹具：内存真库 + 注入 HlcClock + 计划域网关。
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
      // 区无人清空会挂起测试（与 apps/mobile widget_test 同口径）。
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，健身流程测试未执行（$error）');
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

/// 泵 FitnessLogPage（ProviderScope 覆盖注入网关）并等待表单装载。
Future<void> _pumpFitnessPage(WidgetTester tester, _Harness harness) async {
  // 放大视口：表单 + 列表一屏放下，免滚动命中。
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
        home: const FitnessLogPage(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(fitnessSubmitKey));
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

/// 向带 key 的 PlanTextField 输入文本（TextField 是其内部子控件）。
Future<void> _enterText(
    WidgetTester tester, Key fieldKey, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 轮询等待 fitness_sessions 达到 [count]，返回最新一条（提交落库的异步桥）。
Future<cdb.FitnessSession> _waitForSessionCount(
  WidgetTester tester,
  _Harness harness,
  int count,
) async {
  for (var i = 0; i < 150; i++) {
    final rows = await harness.db.select(harness.db.fitnessSessions).get();
    if (rows.length >= count) {
      return rows.first;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('提交未落库：fitness_sessions 数量未达到 $count');
}

/// 轮询直到 [probe] 为真（投影重算为异步桥接，§5.6）。
Future<void> _pumpUntilDb(
  WidgetTester tester,
  Future<bool> Function() probe,
) async {
  for (var i = 0; i < 150; i++) {
    if (await probe()) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待数据库状态超时');
}

void main() {
  testWidgets(
    'W5-6 验收：记 30 分钟慢跑→fitness_sessions+burn 行落库、投影 kcal_out 计入'
    '（§11.1 W5-6 / §3.5 / §5.5⑦ / §5.6）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return; // 温和跳过（缺 sqlite3 运行库）
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);

      await _pumpFitnessPage(tester, harness);

      // ① 类型选择：内置 MET 表「慢跑」（§3.5）。
      await tester.tap(find.text('慢跑'));
      await tester.pump();

      // ② 时长 30 分钟、体重 70kg（§3.5 身体档案输入）。
      await _enterText(tester, fitnessDurationFieldKey, '30');
      await _enterText(tester, fitnessWeightFieldKey, '70');

      // ③ 估算实时重算（count-up 800ms 后到位；§9.3#4）。
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('245'), findsOneWidget);

      // ④ 提交（§3.5 一键落库）。
      await tester.tap(find.byKey(fitnessSubmitKey));

      // ⑤ 等待落库（提交经 AsyncNotifier 异步编排）。
      final session = await _waitForSessionCount(tester, harness, 1);

      // fitness_sessions 行（§5.5⑦）。
      expect(session.date, today);
      expect(session.durationS, 1800);
      expect(session.type, 'cardio');
      expect(session.kcalBurn, 245);
      expect(session.source, 'manual');
      expect(session.entryId, isNotNull);
      expect(session.deletedAt, isNull);
      expect(_hlcPattern.hasMatch(session.hlc), isTrue);
      // 当日记录回填 start_at = now - duration；tz 随录入（§5.5⑦）。
      expect(session.startAt, isNotNull);
      expect(session.tzOffsetMin, now.timeZoneOffset.inMinutes);

      // entries 行（§5.2① kind=fitness）。
      final entryRows =
          await harness.db.select(harness.db.entries).get();
      final entry = entryRows.singleWhere((e) => e.id == session.entryId);
      expect(entry.kind, 'fitness');
      expect(entry.source, 'manual');
      expect(entry.status, 'confirmed');
      expect(entry.date, today);
      expect(entry.title, '慢跑 30 分钟');

      // entry_lines burn 行（§5.2② type=burn/direction=out、归集 kcal 账本、
      // 人工行无置信度、payload 记 session_id + MET 参数）。
      final lineRows =
          await harness.db.select(harness.db.entryLines).get();
      final burn = lineRows.singleWhere((l) => l.entryId == entry.id);
      expect(burn.type, 'burn');
      expect(burn.amount, 245);
      expect(burn.direction, 'out');
      expect(burn.status, 'active');
      expect(burn.confidence, isNull);
      expect(burn.deletedAt, isNull);
      final ledgers = await harness.db.select(harness.db.ledgers).get();
      final kcalLedger =
          ledgers.singleWhere((l) => l.kind == 'kcal' && l.deletedAt == null);
      expect(burn.ledgerId, kcalLedger.id);
      final payload =
          jsonDecode(burn.payload!) as Map<String, Object?>;
      expect(payload['session_id'], session.id);
      expect(payload['activity_id'], 'jogging');
      expect(payload['met'], 7.0);
      expect(payload['weight_kg'], 70.0);

      // day_summary 投影（§5.6⑬）：kcal_out=245、net=-245、dirty=false。
      await _pumpUntilDb(
        tester,
        () async {
          final summaries =
              await harness.db.select(harness.db.daySummaries).get();
          return summaries.any((s) => s.date == today && s.kcalOut == 245);
        },
      );
      final summary = (await harness.db.select(harness.db.daySummaries).get())
          .singleWhere((s) => s.date == today);
      expect(summary.kcalOut, 245);
      expect(summary.kcalIn, 0);
      expect(summary.netKcal, -245);
      expect(summary.dirty, isFalse);
    },
  );

  testWidgets(
    '删除会话：会话行+关联事件打墓碑、kcal_out 回落 0（§5.1 删除行 / §5.6）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final now = DateTime.now();
      final today = dom.formatCalendarDay(now);

      // 直接经网关播种一条会话（表单路径已在上例覆盖）。
      final sessionId = await harness.gateway.submitFitnessSession(
        FitnessSessionDraft(
          date: today,
          tzOffsetMin: now.timeZoneOffset.inMinutes,
          activity: findFitnessActivity('jogging')!,
          intensity: FitnessIntensity.mid,
          durationS: 1800,
          weightKg: 70,
        ),
      );

      await _pumpFitnessPage(tester, harness);
      await _pumpUntilFound(tester, find.byKey(fitnessDeleteKey(sessionId)));
      await tester.tap(find.byKey(fitnessDeleteKey(sessionId)));

      // 轮询：会话行墓碑 + 关联事件墓碑（§6.5 墓碑拒绝复活的前提是写墓碑）。
      await _pumpUntilDb(
        tester,
        () async {
          final rows =
              await harness.db.select(harness.db.fitnessSessions).get();
          return rows
              .any((s) => s.id == sessionId && s.deletedAt != null);
        },
      );
      final session = (await harness.db
              .select(harness.db.fitnessSessions)
              .get())
          .singleWhere((s) => s.id == sessionId);
      expect(session.deletedAt, isNotNull);

      final entry = (await harness.db.select(harness.db.entries).get())
          .singleWhere((e) => e.id == session.entryId);
      expect(entry.deletedAt, isNotNull);

      // 投影回落（§5.6 重建规则：删除后重算，kcal_out=0）。
      await _pumpUntilDb(
        tester,
        () async {
          final summaries =
              await harness.db.select(harness.db.daySummaries).get();
          return summaries.any((s) => s.date == today && s.kcalOut == 0);
        },
      );
      final summary = (await harness.db.select(harness.db.daySummaries).get())
          .singleWhere((s) => s.date == today);
      expect(summary.kcalOut, 0);
      expect(summary.netKcal, 0);
    },
  );
}
