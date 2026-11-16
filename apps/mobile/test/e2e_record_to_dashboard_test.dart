// E2E 专项验收（§11.1 W2 验收线：「手动记一笔→仪表盘环/支出卡即时更新」）。
//
// 与 widget_test.dart（W2 冒烟，覆盖壳导航+录入链路）互补，本用例聚焦
// 「写路径 → 仪表盘 reactive stream 即时重发」这一条验收线本身：
// - 完整 App 冷启动（SlimcaApp：go_router 壳 + 4 Tab + 真仪表盘）；
// - ProviderScope override 注入内存真库（Drift NativeDatabase.memory，
//   走真实 schema/migration/seed 链路，非 mock）；
// - 经 CapturePage 抽屉提交一笔支出（¥25.50 + 500 kcal）；
// - 断言记录前后仪表盘支出卡/热量环卡数值即时变化（零导航、零重启，
//   唯一驱动就是 drift watch 流重发 + Riverpod StreamProvider 重建）。
//
// 测试装配与冒烟同一口径：内存库 + 固定 device_id 的 HlcClock 直接
// override（不跑 bootstrap()，避免测试写真实文件库）；内置账本种子用
// ensureDefaultLedgers 手动补齐（ManualEntryService 依赖内置账本 id，§5.4）。
// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
///
/// `closeStreamsSynchronously: true`：drift 默认在查询流最后一个监听者
/// 取消后排一个 `Timer.run` 延迟清缓存；在 flutter_test 的 fake_async 区，
/// teardown 卸载 widget 树瞬间创建的该 Timer 无人清空 →
/// 「A Timer is still pending」断言失败。此开关是 drift 文档对这类测试的
/// 官方出口（取消监听即同步关流，不排 Timer）。
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

void main() {
  testWidgets('E2E：完整 App 启动 → CapturePage 记一笔支出 → 仪表盘支出卡/热量环即时更新',
      (WidgetTester tester) async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，E2E 照常执行）。
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，E2E 记账→仪表盘用例未执行');
      return;
    }

    // 固定设备标识（§6.3 12 位 hex）+ 内置账本种子（§5.4：默认 money 账本
    // + 内置 kcal 账本；ManualEntryService._builtinLedgerId 依赖）。
    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget); // AppBar 标题：完整壳已起

    // ── 记录前：空日基线（§3.2 空态零值，非空日才有记录卡）──
    expect(find.text('记一件事，钱和卡路里一起入账'), findsOneWidget,
        reason: '空态引导文案在位');
    expect(find.text('今日支出'), findsOneWidget);
    expect(find.text('¥0'), findsOneWidget,
        reason: '支出卡基线为零（0 分展示为 ¥0，§5.1 展示换算）');
    // 指标行 label/value 是两个 Text（Row），按 value Text 断言：环卡摄入/
    // 消耗两行 + 今日消耗卡共 3 处 '0 kcal'（§3.2 卡片墙空态基线均为零）。
    expect(find.text('0 kcal'), findsNWidgets(3),
        reason: '摄入/消耗指标与消耗卡基线为零');
    expect(find.text('0'), findsOneWidget, reason: '热量环心净 kcal 基线为零');

    // ── 经 CapturePage 录入：午饭 500 kcal / ¥25.50（§11.1 W2 主线）──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('captureTitleField')), findsOneWidget);
    expect(find.byKey(const Key('captureKcalField')), findsOneWidget);
    expect(find.byKey(const Key('captureAmountField')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('captureTitleField')),
      '测试午餐',
    );
    await tester.enterText(find.byKey(const Key('captureKcalField')), '500');
    await tester.enterText(
      find.byKey(const Key('captureAmountField')),
      '25.50',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('captureSubmitButton')));
    await tester.pumpAndSettle(); // 抽屉弹簧反向退场 + 明细流重发落界面

    // 抽屉已收起（§9.3#3），回不到录入面。
    expect(find.byKey(const Key('captureSubmitButton')), findsNothing);
    expect(find.text('记一笔'), findsNothing);

    // ── 记录后：仪表盘即时更新（唯一驱动=drift watch 流重发）──
    // 支出卡：¥0 → ¥25.50（§3.2 卡片墙第 2 项）。
    expect(find.text('¥0'), findsNothing, reason: '旧零值已被流重发改写');
    expect(find.text('¥25.50'), findsWidgets,
        reason: '支出卡金额即时更新（今日记录卡摘要同源复现）');

    // 热量环卡（§3.2 第 1 项）：环心净 kcal 0 → 500；摄入指标行同步。
    expect(find.text('摄入 0 kcal'), findsNothing, reason: '摄入指标已更新');
    expect(find.text('500 kcal'), findsOneWidget, reason: '热量环卡摄入指标=500');
    expect(find.text('0 kcal'), findsNWidgets(2),
        reason: '消耗指标与消耗卡仍为 0（未记运动）');
    expect(find.text('0'), findsNothing, reason: '环心净 kcal 已更新');
    expect(find.text('500'), findsOneWidget, reason: '热量环心净 kcal=摄入 500');

    // 今日记录卡出现该条目（§11 W2 流水面）。
    expect(find.text('测试午餐'), findsOneWidget);

    // ── 落库保真：真库中主干 + 拆行（§5.2 facet：热量行/金额行各自成行）──
    final entries = await database.select(database.entries).get();
    expect(entries, hasLength(1), reason: '一笔事件一条 entries 主干（§5.2①）');
    final lines = await database.select(database.entryLines).get();
    final moneyLines =
        lines.where((l) => l.type == 'money').toList();
    final kcalLines =
        lines.where((l) => l.type == 'calorie').toList();
    expect(moneyLines, hasLength(1), reason: '金额 facet 行（§5.3）');
    expect(moneyLines.single.amount, 2550, reason: '¥25.50 → 2550 分（§5.1）');
    expect(kcalLines, hasLength(1), reason: '热量 facet 行（§5.3）');
    expect(kcalLines.single.amount, 500);
    expect(entries.single.kind, 'mixed', reason: '钱+热量同记 → kind=mixed（§5.2①）');

    await database.close();
  });
}
