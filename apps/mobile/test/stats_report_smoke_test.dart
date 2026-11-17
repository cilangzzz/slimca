// 统计报表页渲染冒烟（§11.2 W15 任务 5：「报表页渲染冒烟——插数据→周/月/
// 年三档数字正确」、§3.4 统计报表 P1、§4.3 /stats）。
//
// 页面本体 = feature_ledger `ReportPage`（W15：周/月/年三档 + 分类堆叠 +
// 热量折线 + 钱-热量双轴联动，§3.4/§11.2）——壳层按 §10.4 构造注入
// `DriftReportRepository`；本用例验证装配正确性与三档数字口径：
// - 直接插内存真库（entries 主干 + money/calorie facet 行，§5.2 拆行口径，
//   只插 active 行）四个日期的样本：本周三（2027-02-24）、上周二（02-16）、
//   上月（01-20）、去年（2026-12-31）；
// - ReportPage 注入固定锚点 initialAnchor=2027-02-24（周三）——周期区间
//   确定性：周=02-22..02-28、月=02 月、年=2027；
// - 断言三档分类支出合计（图例=全区间分类合计）：周 ¥10.00、月 ¥30.00、
//   年 ¥70.00（去年 12-31 的 ¥80.00 不进任何一档）；周档点双轴图元选中
//   02-24 桶 → 详情条显示「支出 ¥10.00 / 摄入 300」（W15 双轴联动数字面）；
// - report_viewed 漏斗由壳层装配屏记（StatsReportScreen，W15 任务 4）——
//   本用例直 pump ReportPage，漏斗断言见 e2e 层（此处 0 次亦为正确：页面
//   本体无遥测依赖，§10.4 分层）。
//
// 测试装配：内存库 override（不跑 bootstrap）；页面单页 pump（MaterialApp
// 直挂——context.slimca/MotionConfig 未挂载时按 ui_kit 回退缺省 token）。
// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' show HlcClock;
import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:feature_ledger/feature_ledger.dart'
    show DriftReportRepository, ReportPeriod, ReportPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';


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

const String _kDeviceId = 'ABCDEF123456';

/// 插入一条样本事件：money 行（支出）+ 可选 calorie 行（§5.2 facet 拆行；
/// active 真值行直插——报表口径只数 active，墓碑/被修正行由其余用例覆盖）。
Future<void> _insertSample(
  db.AppDatabase database, {
  required String date,
  required int amountMinor,
  required String moneyLedgerId,
  required String kcalLedgerId,
  int kcal = 0,
  String title = '统计样本',
}) async {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  const uuid = Uuid();
  final entryId = uuid.v7();
  await database.batch((batch) {
    batch.insert(
      database.entries,
      db.EntriesCompanion.insert(
        id: entryId,
        date: date,
        tzOffsetMin: 480,
        kind: kcal > 0 ? 'mixed' : 'expense',
        source: 'manual',
        title: title,
        status: 'confirmed',
        createdAt: nowMs,
        updatedAt: nowMs,
        hlc: '0000000000000:000000:$_kDeviceId',
        revision: 1,
        deviceId: _kDeviceId,
      ),
    );
    batch.insert(
      database.entryLines,
      db.EntryLinesCompanion.insert(
        id: uuid.v7(),
        entryId: entryId,
        type: 'money',
        amount: amountMinor,
        direction: 'out',
        ledgerId: Value(moneyLedgerId),
        currency: const Value('CNY'),
        status: 'active',
        createdAt: nowMs,
        updatedAt: nowMs,
        hlc: '0000000000000:000001:$_kDeviceId',
        revision: 1,
        deviceId: _kDeviceId,
      ),
    );
    if (kcal > 0) {
      batch.insert(
        database.entryLines,
        db.EntryLinesCompanion.insert(
          id: uuid.v7(),
          entryId: entryId,
          type: 'calorie',
          amount: kcal,
          direction: 'in',
          ledgerId: Value(kcalLedgerId),
          status: 'active',
          createdAt: nowMs,
          updatedAt: nowMs,
          hlc: '0000000000000:000002:$_kDeviceId',
          revision: 1,
          deviceId: _kDeviceId,
        ),
      );
    }
  });
}

void main() {
  testWidgets('报表冒烟：插数据 → 周/月/年三档数字正确 + 双轴桶选中数字面',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，冒烟照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，报表冒烟用例未执行');
      return;
    }
    addTearDown(database.close);

    const deviceId = _kDeviceId;
    final clock = HlcClock(deviceId: deviceId);
    // 内置账本种子（§5.4）：money 行挂默认账本、calorie 行归集 kcal 账本
    // （ensureDefaultLedgers 与壳层启动同一工厂，§5.4）。
    await ensureDefaultLedgers(database, clock);
    final moneyLedger = await db
        .LedgerDao(database)
        .defaultMoneyLedger()
        .then((row) => row!.id);
    final kcalLedger = await db
        .LedgerDao(database)
        .kcalLedger()
        .then((row) => row!.id);

    // 四个日期的样本（三档数字的确定性锚点=2027-02-24 周三）：
    // A 02-24 → 周/月/年；B 02-16 → 月；C 01-20 → 年；D 2026-12-31 → 全排除。
    await _insertSample(database,
        date: '2027-02-24',
        amountMinor: 1000,
        moneyLedgerId: moneyLedger,
        kcalLedgerId: kcalLedger,
        kcal: 300);
    await _insertSample(database,
        date: '2027-02-16',
        amountMinor: 2000,
        moneyLedgerId: moneyLedger,
        kcalLedgerId: kcalLedger,
        kcal: 200);
    await _insertSample(database,
        date: '2027-01-20',
        amountMinor: 4000,
        moneyLedgerId: moneyLedger,
        kcalLedgerId: kcalLedger);
    await _insertSample(database,
        date: '2026-12-31',
        amountMinor: 8000,
        moneyLedgerId: moneyLedger,
        kcalLedgerId: kcalLedger);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
        ],
        child: MaterialApp(
          home: ReportPage(
            repository: DriftReportRepository(database),
            initialPeriod: ReportPeriod.week,
            initialAnchor: DateTime(2027, 2, 24),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 报表骨架（feature_ledger ReportPage 三卡 + 三档切换条）。
    expect(find.text('统计报表'), findsOneWidget);
    expect(find.text('支出构成'), findsOneWidget);
    expect(find.text('热量趋势'), findsOneWidget);
    expect(find.text('钱-热量联动'), findsOneWidget);
    expect(find.byKey(const ValueKey('report_period_week')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_period_month')), findsOneWidget);
    expect(find.byKey(const ValueKey('report_period_year')), findsOneWidget);

    // ── 周档（锚点周）：分类合计图例=¥10.00（02-24 唯一样本）──────────
    expect(find.text('未分类 ¥10.00'), findsOneWidget,
        reason: '图例=全区间分类合计（周档只含 02-24）');

    // 双轴联动数字面：点 02-24 桶（周档 7 桶，周一 02-22=索引 0 → 02-24=2）。
    final chartFinder = find.byKey(const ValueKey('report_dual_axis'));
    final chartTopLeft = tester.getTopLeft(chartFinder);
    final chartSize = tester.getSize(chartFinder);
    final slot = (chartSize.width - 24) / 7; // _ChartGeometry.padding=12×2
    await tester.tapAt(Offset(
      chartTopLeft.dx + 12 + slot * 2 + slot / 2,
      chartTopLeft.dy + chartSize.height / 2,
    ));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report_detail_strip')),
        matching: find.text('支出 ¥10.00'),
      ),
      findsOneWidget,
      reason: '选中桶详情条=当日支出（W15 双轴联动数字面）',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('report_detail_strip')),
        matching: find.text('摄入 300 · 消耗 0 · 净 300 kcal'),
      ),
      findsOneWidget,
      reason: '选中桶详情条=当日摄入/消耗/净',
    );

    // ── 月档（02 月）：含 02-24 + 02-16 → ¥30.00 ─────────────────────
    await tester.tap(find.byKey(const ValueKey('report_period_month')));
    await tester.pumpAndSettle();
    expect(find.text('未分类 ¥30.00'), findsOneWidget,
        reason: '月档=同月两样本合计（§5.1 半开区间 [02-01, 03-01)）');
    expect(find.textContaining('¥40.00'), findsNothing,
        reason: '上月（01-20）不在月区间');

    // ── 年档（2027 年）：A+B+C → ¥70.00；去年 ¥80.00 排除 ────────────
    await tester.tap(find.byKey(const ValueKey('report_period_year')));
    await tester.pumpAndSettle();
    expect(find.text('未分类 ¥70.00'), findsOneWidget,
        reason: '年档=2027 年三样本合计（12 个月桶）');
    expect(find.textContaining('¥80.00'), findsNothing,
        reason: '去年（2026-12-31）样本不进 2027 年档');
  });
}
