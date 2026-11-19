// 仪表盘支出卡「余/超支」状态专项验收（§11.2 W15 任务 2「支出卡接预算
// 快照 v2」、§3.2「超支/超额即时反馈」、§5.6⑬ budget_snapshot v2）。
//
// 验收口径（W15 任务书专项 e2e 第 5 步的仪表盘半边）：
// - 建每日总支出预算（budgets period=daily，经 feature_ledger admin 仓库
//   → core_db BudgetsDao 同事务 outbox + 投影联动 §5.6⑬）→ 插当日 money
//   支出 → day_summary.budget_snapshot v2 重算 → 支出卡「预算余」绿色态；
// - 再插一笔越过预算线 → 快照重发 → 「超支」标红态（remaining<0，金额=
//   超出部分取正显示）。
//
// 装配与冒烟同口径：内存真库 + 固定 device_id HlcClock override；entries
// 写路径挂投影（bootstrap() 同款——投影单例同时注入仓库与 provider）。
// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_ledger/feature_ledger.dart';
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';

bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

void main() {
  testWidgets('W15：支出卡余/超支状态随预算快照 v2 正确翻转', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = db.AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    try {
      await database.customSelect('SELECT 1').getSingle();
    } catch (error) {
      try {
        await database.close();
      } catch (_) {}
      if (_isSqliteLibraryMissing(error)) {
        return; // 宿主缺 sqlite3 运行库：温和跳过。
      }
      rethrow;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = domain.HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // 投影单例（bootstrap() 同款：写路径与读端共用同一实例）。
    final projection = db.DaySummaryProjection(database);
    final entryRepo = db.DriftEntryRepository(database, projection: projection);
    final lineRepo =
        db.DriftEntryLineRepository(database, projection: projection);

    // ── 建预算：每日总支出 ¥100（BudgetsDao 同事务 outbox + 全投影行重算）──
    // clock 参数缺省：admin 仓库内部自建 core_db LocalWriteClock（写路径 HLC）。
    final DriftLedgerAdminRepository admin =
        DriftLedgerAdminRepository(database);
    await admin.setDailySpendGoal(10000);

    Future<void> insertSpend(int amountMinor, String lineIdTail) async {
      final db.Ledger money =
          (await db.LedgerDao(database).defaultMoneyLedger())!;
      final String day = _todayKey();
      final String entryId =
          '0196a7e0-0000-7000-8000-${lineIdTail}e1';
      final domain.SyncMeta meta = domain.SyncMeta(
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        hlc: clock.now().format(),
        revision: 1,
        deviceId: deviceId,
      );
      await entryRepo.upsert(domain.Entry(
        id: entryId,
        date: day,
        tzOffsetMin: 480,
        kind: domain.EntryKind.expense,
        source: domain.EntrySource.manual,
        title: '验收一笔',
        status: domain.EntryStatus.confirmed,
        meta: meta,
      ));
      await lineRepo.upsert(domain.EntryLine(
        id: '0196a7e0-0000-7000-8000-${lineIdTail}l1',
        entryId: entryId,
        type: domain.LineType.money,
        amount: amountMinor,
        direction: domain.LineDirection.outcome,
        ledgerId: money.id,
        currency: 'CNY',
        status: domain.LineStatus.active,
        meta: meta,
      ));
    }

    // 第一笔 ¥25.50（预算内）。
    await insertSpend(2550, 'aaaa1111');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          daySummaryProjectionProvider.overrideWithValue(projection),
          captureGatewayProvider.overrideWithValue(
            createCaptureGateway(
              db: database,
              clock: clock,
              projection: projection,
            ),
          ),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // 支出卡金额走明细 join 流（§5.3）；预算余走 budget_snapshot v2 直读
    // （§5.6⑬）——预算内：remaining=10000-2550=7450 → 「预算余 ¥74.50」。
    expect(find.text('¥25.50'), findsWidgets,
        reason: '支出卡金额=当日支出合计（明细流口径）');
    expect(
      find.byKey(const Key('dashboard_budget_state')),
      findsOneWidget,
    );
    expect(find.text('预算余 ¥74.50'), findsOneWidget,
        reason: '预算内=余态（§3.2 超支/超额即时反馈）');

    // ── 第二笔 ¥80：累计 ¥105.50 越线 → used=10550、remaining=-550 ──
    await insertSpend(8000, 'aaaa2222');
    await tester.pumpAndSettle();

    expect(find.text('超支 ¥5.50'), findsOneWidget,
        reason: '超支=remaining<0 标红，金额取超出部分（-550 → ¥5.50）');
    expect(find.text('预算余 ¥74.50'), findsNothing);
  });
}

/// 本地日历日 `yyyy-MM-dd`（§5.1 date 口径）。
String _todayKey() {
  final DateTime now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
