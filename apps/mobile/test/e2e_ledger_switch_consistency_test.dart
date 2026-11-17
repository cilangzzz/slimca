// E2E 专项验收（§11.2 W15 任务 3/5：「录入页账本选择器接多账本（默认账本
// 记忆）」+「账本切换后录入与账单口径一致」）。
//
// 与 widget_test（壳冒烟）互补，本用例聚焦 W15 多账本这一条验收线：
// - 完整 App 冷启动（SlimcaApp：go_router 壳 + 4 Tab + 真仪表盘）；
// - 内存真库 override（Drift NativeDatabase.memory，走真实 schema/seed 链路，
//   非 mock）+ RecordingTelemetryService 捕获 ledger_switched 漏斗；
// - 账本 Tab 顶栏切换器新建第二个 money 账本（§3.4 多账本 P1）→ 建档即切换
//   为当前/默认账本（settings default_ledger_id + money 组 sort 置首，§6.2
//   同事务出网）→ 录入页账本选择器按记忆预选新账本（feature_capture 按
//   sort-first 口径解析缺省）→ 仅记钱提交一笔 → entry_lines.ledger_id 落
//   新账本（录入口径）；
// - 切回默认账本：新账本流水不串账（账单口径一致），再录一笔默认账本收到
//   其 id（默认账本记忆双向成立）；ledger_switched 漏斗随切换落盘。
//
// 测试装配与冒烟同一口径：内存库 + 固定 device_id 的 HlcClock 直接 override
// （不跑 bootstrap()）；feature_capture 网关/解析器按 bootstrap() 同款工厂
// 注入（§10.4）；内置账本种子用 ensureDefaultLedgers 补齐（§5.4）。Windows
// 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, DatabaseConnection;
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
import 'package:slimca/telemetry/w15_funnel_events.dart';

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
/// `closeStreamsSynchronously: true`：见 e2e_record_to_dashboard_test 同注。
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

/// money 账本名 → 行（断言与切换目标定位用）。
Future<db.Ledger?> _moneyLedgerByName(
  db.AppDatabase database,
  String name,
) async {
  final rows = await (database.select(database.ledgers)
        ..where((t) => t.kind.equals('money') & t.deletedAt.isNull()))
      .get();
  for (final row in rows) {
    if (row.name == name) {
      return row;
    }
  }
  return null;
}

/// settings[default_ledger_id]（§5.6⑲ JSON 字符串值）。
Future<String?> _defaultLedgerSetting(db.AppDatabase database) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(db.kSettingDefaultLedgerId)))
      .getSingleOrNull();
  if (row == null) return null;
  final decoded = jsonDecode(row.value);
  return decoded is String ? decoded : null;
}

/// 小步轮询等待异步落库条件成立（建档/切换的 DB 写链路在弹层动画帧间跑，
/// pumpAndSettle 可能在帧排空时提前返回——与 widget_test _pumpUntilFound
/// 同款纪律：条件轮询而非固定时长）。
Future<void> _pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  for (var i = 0; i < 150; i++) {
    if (await condition()) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待落库条件超时');
}

void main() {
  testWidgets('E2E：新建账本并切换默认 → 录入预选新账本 → 账单口径一致不串账',
      (WidgetTester tester) async {
    // 放大视口：抽屉表单/切换抽屉一屏放下，免滚动命中（与 capture_flow 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，E2E 照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，E2E 多账本用例未执行');
      return;
    }
    addTearDown(database.close);

    // 固定设备标识（§6.3 12 位 hex）+ 内置账本种子（§5.4：默认 money 账本
    // + 内置 kcal 账本）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    final telemetry = RecordingTelemetryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          telemetryServiceProvider.overrideWithValue(telemetry),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // ── 进入账本 Tab：顶栏切换器在位（W15 任务 1 多账本切换器）──────────
    await tester.tap(find.text('账本'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger_scope_switcher')), findsOneWidget,
        reason: 'W15 顶栏多账本切换器（§3.4 账本切换抽屉的下拉形态）');

    // ── 新建第二个 money 账本「差旅账本」（§3.4 多账本建档）────────────
    await tester.tap(find.byKey(const Key('ledger_scope_switcher')));
    await tester.pumpAndSettle();
    expect(find.text('切换账本'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ledger_create_tile')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('ledger_create_name_field')),
      '差旅账本',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('ledger_create_save')));
    await tester.pumpAndSettle();

    // 建档即切换为当前/默认账本（W15 默认账本记忆）：等待「账本落库 +
    // settings 记忆 + sort 置首」整条异步链完成（弹层动画帧间跑）。
    await _pumpUntilAsync(tester, () async {
      final ledger = await _moneyLedgerByName(database, '差旅账本');
      if (ledger == null || ledger.sort != 0) return false;
      return await _defaultLedgerSetting(database) == ledger.id;
    });

    final travel = await _moneyLedgerByName(database, '差旅账本');
    expect(travel, isNotNull, reason: '新账本落库（§5.4④ ledgers）');
    final travelId = travel!.id;
    // §6.2 写路径纪律：ledgers 行快照同事务入队 sync_outbox。
    final outboxRows = await (database.select(database.syncOutbox)
          ..where((t) =>
              t.targetTable.equals('ledgers') & t.rowId.equals(travelId)))
        .get();
    expect(outboxRows, isNotEmpty, reason: '真值表写入同事务出网（§6.2）');

    // 建档即切换为当前/默认账本（W15 默认账本记忆）：
    // settings 记忆 + money 组 sort 置首 + ledger_switched 漏斗。
    expect(await _defaultLedgerSetting(database), travelId,
        reason: 'settings[kSettingDefaultLedgerId] 记忆新默认账本（§5.6⑲）');
    final travelAfterSwitch = await _moneyLedgerByName(database, '差旅账本');
    final fallback = await _moneyLedgerByName(database, '默认账本');
    expect(travelAfterSwitch!.sort, 0,
        reason: '默认账本 sort 置首——录入页账本选择器按 sort-first 预选（W15 任务 3）');
    expect(fallback!.sort, 1, reason: '其余账本次序顺延（重排只写变化行）');
    await telemetry.flush();
    expect(telemetry.byName(W15TelemetryFunnel.ledgerSwitched), hasLength(1),
        reason: 'ledger_switched 漏斗随建档切换记一次（W15 任务 4）');

    // ── 录入页预选记忆账本并记一笔（§11.2 W15 任务 3「默认账本记忆」）──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    // 多账本选择器：新账本 chip 在位（§5.4④ 账本选项）。
    expect(find.text('差旅账本'), findsWidgets,
        reason: '录入页账本选择器接多账本（CaptureLedgerPicker 选项）');
    for (final key in const ['1', '2', '.', '3', '4']) {
      await tester.tap(find.byKey(ValueKey('capture_key_$key')));
    }
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '标题（留空自动取分类名）',
      ),
      '差旅高铁票',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    // 录入口径：金额行落记忆账本（默认账本记忆 → ledger_id）。
    final lines = await (database.select(database.entryLines)
          ..where((t) => t.type.equals('money') & t.deletedAt.isNull()))
        .get();
    expect(lines, hasLength(1));
    expect(lines.single.ledgerId, travelId,
        reason: '录入预选=记忆默认账本（W15 任务 3 验收线）');
    expect(lines.single.amount, 1234, reason: '¥12.34 → 1234 分（§5.1）');

    // ── 账单口径一致：新账本流水列出该笔 ─────────────────────────────
    await tester.tap(find.text('账本'));
    await tester.pumpAndSettle();
    expect(find.text('差旅账本'), findsOneWidget,
        reason: '切换器标题=当前账本');
    expect(find.text('差旅高铁票'), findsOneWidget,
        reason: '当前账本流水含新记账单（口径一致，§11.2 W15 任务 5）');
    expect(find.textContaining('支出 ¥12.34'), findsWidgets,
        reason: '日头合计=账本口径（money 行求和 §3.4）');

    // ── 切回默认账本：流水不串账 ─────────────────────────────────────
    await tester.tap(find.byKey(const Key('ledger_scope_switcher')));
    await tester.pumpAndSettle();
    final fallbackId = fallback.id;
    await tester.tap(find.byKey(Key('ledger_scope_$fallbackId')));
    await tester.pumpAndSettle();
    // 等默认账本记忆落库（切换编排异步链）。
    await _pumpUntilAsync(
      tester,
      () async => await _defaultLedgerSetting(database) == fallbackId,
    );
    await telemetry.flush();
    expect(telemetry.byName(W15TelemetryFunnel.ledgerSwitched), hasLength(2),
        reason: '显式切换再记一次 ledger_switched');
    expect(await _defaultLedgerSetting(database), fallbackId,
        reason: '默认账本记忆随切换更新');
    // 等流水流按新作用域重发后再断言不串账。
    await _pumpUntilAsync(tester, () async {
      await tester.pump();
      return find.text('差旅高铁票').evaluate().isEmpty;
    });
    expect(find.text('差旅高铁票'), findsNothing,
        reason: '默认账本流水不含他账本账单（行级 ledger_id 归账，§5.2②）');

    // ── 再录一笔：预选回落默认账本（记忆双向成立）────────────────────
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('仅记钱'));
    await tester.pumpAndSettle();
    for (final key in const ['5']) {
      await tester.tap(find.byKey(ValueKey('capture_key_$key')));
    }
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '标题（留空自动取分类名）',
      ),
      '默认账本早餐',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('capture_submit')));
    await tester.pumpAndSettle();

    final linesAfter = await (database.select(database.entryLines)
          ..where((t) => t.type.equals('money') & t.deletedAt.isNull()))
        .get();
    expect(linesAfter, hasLength(2));
    final newLine = linesAfter
        .where((l) => l.id != lines.single.id)
        .single;
    expect(newLine.ledgerId, fallbackId,
        reason: '切回默认账本后录入预选跟随记忆（默认账本记忆双向成立）');

    // 账单口径一致（另一侧）：默认账本流水只显示自己的账。
    await tester.tap(find.text('账本'));
    await tester.pumpAndSettle();
    expect(find.text('默认账本早餐'), findsOneWidget);
    expect(find.text('差旅高铁票'), findsNothing);
  });
}
