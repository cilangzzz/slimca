// V1 UX 插曲专项验收（《UI-规范与重设计》§4 设置/菜单页重设计 + §5 审计 #4）。
//
// 与 widget_test.dart 第二用例（壳冒烟：IA 渲染 + 无「升级计划」断言 +
// raw_input 开关落库）互补，本文件聚焦三块定稿验收线：
// 1. **无「升级计划」断言**（§4.1 移除决策）：IAP 抽象代码保留但 UI 全部不
//    露出——付费墙区块/裸恢复购买入口/SKU 目录均不渲染；
// 2. **菜单交互**（§4.1 IA + §4.3）：拍照即焚开关 toggle 写回 settings ⑲、
//    主题入口唤起编辑面板（W16 漏斗首步）、危险项「清空数据」确认弹窗
//    （具体动词按钮 + 取消路径 + 确认路径边界提示）；
// 3. **删除 undo e2e**（§4.3「常规单条删除走 snackbar undo」+ §5 审计 #4）：
//    仪表盘今日记录卡删除 → 乐观移除 + SnackBar 撤销 → 撤回后条目回归且
//    墓碑未落库；不撤销（超时）→ 软删墓碑提交（§6.5「墓碑拒绝复活」→
//    undo 采用延迟提交而非复活墓碑，同步语义零特例）。
//
// 测试装配：内存 Drift 库 + 固定 device_id 的 HlcClock 直接 override（不跑
// bootstrap()）；解析器走缺省 dart-define 工厂（离线桩）。Windows 宿主缺
// sqlite3 运行库时温和跳过（widget_test 同口径）。

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
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/app/router.dart' show slimcaRouter;
import 'package:slimca/data/drift_repositories.dart' show DriftEntryRepository;
import 'package:slimca/features/settings/settings_page.dart';
import 'package:slimca/main.dart';
import 'package:slimca/settings/photo_burn_setting.dart'
    show kSettingPhotoBurnAfterParse;

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 widget_test 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：drift 在流监听取消后排延迟清缓存
/// Timer，widget 测试 fake_async 区会「A Timer is still pending」——此开关
/// 即 drift 文档对这类测试的官方出口（widget_test 同注）。
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

Future<void> _pumpApp(WidgetTester tester, db.AppDatabase database) async {
  const deviceId = 'ABCDEF123456';
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);
  // slimcaRouter 是全局单例：同进程内前一用例的 Tab 位置会带进本用例
  //（StatefulShellRoute.indexedStack 保栈），先复位回「今天」Tab 再装配。
  slimcaRouter.go('/');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        hlcClockProvider.overrideWithValue(clock),
        captureGatewayProvider
            .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
        captureParserProvider.overrideWithValue(createCaptureParser()),
      ],
      child: const SlimcaApp(),
    ),
  );
  // 冷启动首帧直出：等卡片墙级联上浮播完（§9.3#1）。
  await tester.pump(const Duration(milliseconds: 600));
}

/// 我的 Tab 进入设置页（NavigationBar 子树作用域查找，theme_editor_test 同策略
/// ——slimcaRouter 全局单例下 AppBar 标题与导航标签可能同屏双命中）。
Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('我的'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('V1 插曲：设置页无「升级计划」露出 + 分组卡 IA 渲染（§4.1/§4.2）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      return; // Windows 宿主缺 sqlite3：跳过。
    }
    addTearDown(database.close);

    await _pumpApp(tester, database);
    await _openSettings(tester);

    // ── §4.1 IA：顶部账号/同步卡（非 ListTile）→ 分组卡 → 尾部低频组 ──
    expect(find.text('本地账簿'), findsOneWidget,
        reason: '§4.1 顶部账号/同步卡（头像位 + 同步状态只读一行）');
    for (final header in const ['数据与隐私', '外观', '数据']) {
      expect(find.text(header), findsOneWidget,
          reason: '§4.1 分组头（Label Large 14/500，SlimcaMenuGroup）');
    }
    for (final row in const [
      '原文上云（raw_input）',
      '拍照原图解析后即焚',
      '主题',
      '同步',
      '数据导出',
      '关于',
      '版本',
      '清空数据',
    ]) {
      expect(find.text(row), findsOneWidget,
          reason: '§4.1/§4.2 分组行迁入：$row');
    }

    // ── §4.1 移除决策：升级计划/恢复购买/SKU 目录 UI 全部不露出 ────────
    expect(find.textContaining('升级'), findsNothing,
        reason: '「升级 Slimca Pro」整块移除（IAP 代码保留、UI 不露出）');
    expect(find.textContaining('恢复购买'), findsNothing,
        reason: '§4.3：裸恢复购买入口随付费墙移出（有购买记录才在「关于」'
            '显示状态行，V1 无购买 → 不渲染）');
    expect(find.textContaining('Pro 买断'), findsNothing);
    expect(find.textContaining('AI 能力订阅'), findsNothing,
        reason: '双轨 SKU 目录不渲染（转化触点收敛到 AI 免费额度降级提示 §7.4）');

    // 危险项独立分组样式（§4.3 红字：SlimcaTheme.danger 语义 token）。
    final dangerTileText = tester.widget<Text>(
      find.text('清空数据'),
    );
    expect(dangerTileText.style?.color, isNotNull,
        reason: '清空数据行红字（§4.3 红色文字按钮，不做填充块）');
  });

  testWidgets('V1 插曲：菜单交互——即焚开关写回 settings ⑲、主题入口唤起面板、'
      '危险项弹窗取消/确认路径（§4.3/§11.2 W11-12）', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      return;
    }
    addTearDown(database.close);

    await _pumpApp(tester, database);
    await _openSettings(tester);

    // ── 拍照原图即焚开关（默认开 §3.7/§11.2 任务 3）→ 关 → settings 落库 ──
    final burnSwitch = find.byKey(settingsPhotoBurnSwitchKey);
    expect(tester.widget<Switch>(burnSwitch).value, isTrue,
        reason: '默认开=即焚（合规缺省 §3.3）');
    await tester.tap(burnSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(burnSwitch).value, isFalse);
    final burnRow = await database
        .customSelect(
          "SELECT value FROM settings WHERE key = '$kSettingPhotoBurnAfterParse'",
        )
        .getSingle();
    expect(burnRow.data['value'], 'false',
        reason: 'settings ⑲ value 一律 JSON（§5.6⑲）');
    // 关=本机留档档位（关回默认开收尾，§3.7 随时可撤回）。
    await tester.tap(burnSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(burnSwitch).value, isTrue);

    // ── 主题入口（§11.2 W16 任务 1）：唤起主题编辑面板（弹簧 sheet）────
    await tester.tap(find.byKey(settingsThemeEntryKey));
    await tester.pumpAndSettle();
    expect(find.text('深浅色'), findsOneWidget,
        reason: '主题编辑面板打开（§8.3 深浅覆盖段可见）');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('深浅色'), findsNothing, reason: '面板收起回到设置页');

    // ── 危险项确认弹窗（§4.3：Cancel 不做默认按钮 + 具体动词「清空」）──
    await tester.ensureVisible(find.byKey(settingsClearDataKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(settingsClearDataKey));
    await tester.pumpAndSettle();
    expect(find.text('清空全部数据？'), findsOneWidget);
    // 取消路径：弹窗收起，无删除。
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('清空全部数据？'), findsNothing);
    // 确认路径：本插曲清空执行体随 /settings/export 接入（§4.3 路由表
    // 「导出/清空/隐私政策」）——确认动作以 SnackBar 明示边界，不假装已清空。
    await tester.tap(find.byKey(settingsClearDataKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '清空'));
    await tester.pumpAndSettle();
    expect(find.textContaining('清空流程随「数据导出」主权页'), findsOneWidget,
        reason: '确认后明示接线边界（占位不假装执行）');
    // 刷掉 SnackBar 展示期定时器（默认 4s）与退场动画——避免收尾
    // 「A Timer is still pending」（widget_test 同口径）。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('V1 插曲：今日记录删除 undo——乐观移除+撤销回归+超时落墓碑'
      '（§4.3 snackbar undo + §5 审计 #4 + §6.5 墓碑拒绝复活）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      return;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // 种子一条事件（主干行；§5.2① entries——undo e2e 只验主干软删语义，
    // facet 拆行同步正确性由 core_db/feature 仓测试覆盖）。id 形态与
    // dashboard_budget_state_test 同款 36 位 UUIDv7 形态（hex 段）。
    const entryId = '0196a7e0-0000-7000-8000-aaaa9999e1';
    final repo = DriftEntryRepository(database);
    await repo.upsert(Entry(
      id: entryId,
      date: _todayKey(),
      tzOffsetMin: 480,
      kind: EntryKind.expense,
      source: EntrySource.manual,
      title: 'Undo 用例一笔',
      status: EntryStatus.confirmed,
      meta: SyncMeta(
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
        hlc: clock.now().format(),
        revision: 1,
        deviceId: deviceId,
      ),
    ));

    // slimcaRouter 全局单例（同进程跨用例保留 Tab 位）：复位回「今天」Tab，
    // 保证今日记录卡在场（undo e2e 依赖仪表盘挂载）。
    slimcaRouter.go('/');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Undo 用例一笔'), findsOneWidget,
        reason: '今日记录卡渲染种子条目（明细流直驱 §11 W2）');

    Future<db.Entry> row() async {
      return (database.select(database.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
    }

    // ── 删除请求：乐观移除 + SnackBar 撤销入口（§4.3）──────────────────
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(find.text('Undo 用例一笔'), findsNothing,
        reason: '删除请求 → 条目乐观移除（不等软删提交）');
    expect(find.textContaining('已删除「Undo 用例一笔」'), findsOneWidget);
    expect((await row()).deletedAt, isNull,
        reason: '撤销窗口内墓碑未落库（延迟提交语义，§6.5 墓碑拒绝复活）');

    // ── 撤销：条目回归、墓碑仍不落库 ─────────────────────────────────
    // SnackBar 入场动画收敛后再点「撤销」——动画中段点按中心会被命中测试
    // 判为未命中（tap warnIfMissed 警告 → 撤销丢失）。
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('Undo 用例一笔'), findsOneWidget, reason: '撤销 → 条目回归');
    expect((await row()).deletedAt, isNull, reason: '撤销后不提交软删');

    // ── 二次删除不撤销：SnackBar 超时（4s）→ 提交软删墓碑（§5.1）──────
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(find.text('Undo 用例一笔'), findsNothing);
    // 先让 SnackBar 入场动画收敛：ScaffoldMessenger 在 isCompleted 的 build
    // 里才创建 4s 自动隐藏 Timer——入场未完成时 Timer 以推进后的时钟为起点，
    // pump(6s) 永远追不上（reason=timeout 永不触发）。
    await tester.pumpAndSettle();
    // SnackBar 默认 4s 超时 + 退场动画；fake_async 内推进即触发关闭回调
    // （reason=timeout → 按「未撤销=执行」提交）。
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect((await row()).deletedAt, isNotNull,
        reason: '未撤销 → 软删墓碑提交（§5.1 删除行；聚合流即时重发）');
    expect(find.text('Undo 用例一笔'), findsNothing);
  });
}

/// 本地日历日 `yyyy-MM-dd`（§5.1 date 口径）。
String _todayKey() {
  final DateTime now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
}
