// Slimca W2 冒烟测试（§11 W2：手动记一笔 → 仪表盘环/支出卡即时更新）
// + W3-4 追加覆盖（§11.1 W3-4：AI 入口存在 + 默认 FakeParser 文本解析闭环）。
//
// 覆盖链路（§4.2 壳 + §9.3#3 录入抽屉 + §6.2 写路径）：
// 冷启动首帧直出仪表盘（无 spinner §2.3 步 0）→ 4 Tab 导航壳（§4.2）→
// 中央「+」弹簧抽屉（showSlimcaSpringSheet）→ 手动填表保存 →
// entries/entry_lines/sync_outbox 落库 → 仪表盘明细流实时重发；
// W3-4：AI 一句话输入 → 默认 FakeParser 解析（无 dart-define → mock，
// 零真实网络）→ 确认卡 → 确认入账 → 仪表盘即时更新（corrections/
// ai_parses 落库由 ai_capture_service_test.dart 专项覆盖）。
//
// 测试装配：内存 Drift 库 + 固定 device_id 的 HlcClock 直接 override
// （不跑 bootstrap()，避免测试写真实文件库）；内置账本种子用
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

void main() {
  testWidgets('W2+W3-4 冒烟：手动记一笔 → AI 入口 → FakeParser 解析确认 → 仪表盘即时更新',
      (WidgetTester tester) async {
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
        ],
        child: const SlimcaApp(),
      ),
    );

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等卡片墙级联上浮播完（§9.3#1）。
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget); // AppBar 标题

    // §4.2 四 Tab：今天 / 账本 / 计划 / 我的。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 中央悬浮「+」唤起录入抽屉（§4.2 capture 非路由页面；§9.3#3 弹簧）。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('captureTitleField')), findsOneWidget);
    expect(find.byKey(const Key('captureKcalField')), findsOneWidget);
    expect(find.byKey(const Key('captureAmountField')), findsOneWidget);

    // ── W3-4：AI 入口存在（§11.1 W3-4 主线；任务项「壳冒烟覆盖 AI 入口」）──
    expect(find.byKey(const Key('aiTextField')), findsOneWidget);
    expect(find.byKey(const Key('aiParseButton')), findsOneWidget);

    // 手动记一笔：午饭 500 kcal / ¥25.50（§11 W2 验收线）。
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
    await tester.pumpAndSettle();

    // 抽屉已收起（§9.3#3 弹簧反向退场）。
    expect(find.byKey(const Key('captureSubmitButton')), findsNothing);
    expect(find.text('记一笔'), findsNothing);

    // 仪表盘即时更新：热量环中心净热量、指标行、支出卡、今日记录卡。
    expect(find.text('测试午餐'), findsOneWidget); // 今日记录卡条目
    expect(find.text('¥25.50'), findsWidgets); // 支出卡 + 条目摘要
    expect(find.text('500 kcal'), findsOneWidget); // 摄入指标行
    expect(find.text('500'), findsOneWidget); // 环心净 kcal

    // ── W3-4：AI 文本解析闭环（默认 FakeParser，测试无 dart-define → mock
    //    零真实网络；§11.1 W3-4「AI 双解析闭环（文本）」）──
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('aiTextField')),
      '测试晚餐 500kcal 花了18',
    );
    await tester.tap(find.byKey(const Key('aiParseButton')));
    await tester.pumpAndSettle();

    // 确认卡出现（§2.3 步 3「抽屉原地转确认卡」）：FakeParser 确定性产出
    // 500 kcal / ¥18.00（置信度三色点 count-up 同卡可见）。
    expect(find.byKey(const Key('aiConfirmButton')), findsOneWidget);
    expect(find.byKey(const Key('aiConfirmKcalField')), findsOneWidget);
    expect(find.byKey(const Key('aiConfirmAmountField')), findsOneWidget);
    expect(find.text('500 kcal'), findsWidgets); // 确认卡 count-up（+仪表盘指标）
    expect(find.text('¥18'), findsWidgets); // 金额 count-up（yuanFromMinor 整元省 .00）

    await tester.tap(find.byKey(const Key('aiConfirmButton')));
    await tester.pumpAndSettle();

    // 确认后抽屉收起（§2.3 步 5「卡片飞入仪表盘槽位」）。
    expect(find.byKey(const Key('aiConfirmButton')), findsNothing);

    // 仪表盘即时更新（唯一驱动=drift watch 流重发，§11 W2 数据底座）：
    // - 今日记录卡新条目（AI title=原句，FakeParser 确定性）；
    // - 摄入 500+500=1000 kcal（§3.2 热量环卡指标行）；
    // - 支出卡 25.50+18.00=¥43.50；条目摘要「摄入 500 kcal · ¥18.00」。
    expect(find.text('测试晚餐 500kcal 花了18'), findsOneWidget);
    expect(find.text('1000 kcal'), findsOneWidget);
    expect(find.text('¥43.50'), findsOneWidget);
    expect(find.text('摄入 500 kcal · ¥18'), findsOneWidget);
  });
}
