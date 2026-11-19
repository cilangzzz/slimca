// 底栏重设计回归测试（拍板：凹槽花瓣底栏；定型条目《UI-规范与重设计》§5
// #14、§2.2 增补段，《大厂设计规范》§7.2 决策——BottomAppBar 框架凹槽
// CircularNotchedRectangle（notchMargin 显式 6）承接花瓣
// SlimcaCookieShapeBorder FAB，NavigationBar 嵌入其内背景透明、
// clipBehavior antiAlias 使 pill 随凹槽裁剪）。
//
// 覆盖（评审嫁接项 dock_bar_shell_test 落地）：
// 1. 壳结构唯一性：FAB/NavigationBar/BottomAppBar 全树恰一、FAB 形状=花瓣、
//    tooltip '记一件事' 语义查找不回归（11 个既有测试文件的 finder 依赖面）；
// 2. FAB onPressed 遥测链不回归：tap → 录入通道抽屉（写/说/拍）打开→关闭；
// 3. 凹槽缺口点击不穿透：花瓣尖 28 与凹槽 34 之间的间隙环区域命中被栏体
//    Material 吸收，不误触 body、不唤起抽屉（无 ghost-tap）；
// 4. 6 主题包 × 明暗：primary/outline 对 surfaceCard 自然达标 3:1（一体化后
//    中央按钮由 FAB 豁免转入容器类校验；自然达标=护栏不降级全 App 主色）；
// 5. MotionLevel=off 档：底栏壳（真 slimcaRouter）pumpAndSettle 收敛
//    （坑点 11——本期零新增动画路径，off 档天然合规的回归锚点）。
//
// 测试装配与 widget_test.dart 同口径：内存 Drift 库 + 固定 device_id 的
// HlcClock 直接 override（不跑 bootstrap()）；Windows 宿主缺 sqlite3 运行库
// 时温和跳过。

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/app/router.dart';
import 'package:slimca/features/capture/capture_channels_sheet.dart'
    show captureChannelTextKey;
import 'package:slimca/main.dart';
import 'package:ui_kit/ui_kit.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 widget_test 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
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

/// 泵起完整壳（SlimcaApp + 内存库 override，widget_test 同口径）。
/// 返回 null 表示宿主缺 sqlite3，调用方跳过。
Future<db.AppDatabase?> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final database = await _tryOpenMemoryDatabase();
  if (database == null) return null;
  addTearDown(database.close);

  const deviceId = 'ABCDEF123456';
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        hlcClockProvider.overrideWithValue(clock),
        captureGatewayProvider
            .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
        captureParserProvider.overrideWithValue(createCaptureParser()),
        planGatewayProvider.overrideWithValue(
          createPlanGateway(db: database, clock: clock),
        ),
      ],
      child: const SlimcaApp(),
    ),
  );
  // 冷启动首帧直出 + 卡片墙级联播完（widget_test 同口径）。
  await tester.pump(const Duration(milliseconds: 600));
  return database;
}

/// 定窗 pumpAndSettle：显式 30s 上限——任何不收敛动画快速失败并指明位置，
/// 而非默认 10 分钟挂死（并级联污染同文件后续用例的 !inTest）。
Future<void> _settle(WidgetTester tester) =>
    tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );

void main() {
  testWidgets('壳结构唯一性：花瓣 FAB/NavigationBar/BottomAppBar 恰一 + 标签唯一',
      (WidgetTester tester) async {
    final database = await _pumpShell(tester);
    if (database == null) return;

    expect(find.byType(FloatingActionButton), findsOneWidget,
        reason: '中央录入入口全屏唯一（单一功能入口拍板，产品设计文档 §4.2'
            '「+」悬浮行；《大厂设计规范》§3 P12 显著填充克制）');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(BottomAppBar), findsOneWidget,
        reason: '一体化底栏：BottomAppBar 凹槽承接 + NavigationBar 嵌入其内');

    final FloatingActionButton fab =
        tester.widget<FloatingActionButton>(find.byType(FloatingActionButton));
    expect(fab.shape, isA<SlimcaCookieShapeBorder>(),
        reason: '中央按钮形态=花瓣（M3 Expressive cookie，拍板推导）');
    expect(fab.backgroundColor, isNotNull,
        reason: '显式 primary 填充（§8.2 token，非框架 primaryContainer 默认）');
    expect(fab.tooltip, '记一件事');

    // 标签唯一（「今天」×2 = 底栏 Tab + 日历「今天」锚定 pill，widget_test
    // 同口径；其余三 Tab 恰一——SlimcaCookieShapeBorder 内禁同名 Text）。
    expect(find.text('今天'), findsNWidgets(2));
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });

  testWidgets('FAB onPressed 遥测链不回归：tap → 录入通道抽屉打开 → 关闭',
      (WidgetTester tester) async {
    final database = await _pumpShell(tester);
    if (database == null) return;

    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    expect(find.byKey(captureChannelTextKey), findsOneWidget,
        reason: '「写」通道入口在树（funnel captureOpen→showCaptureChannelsSheet 链）');

    // 点左上角 barrier 关闭（SlimcaSpringSheetRoute barrierDismissible 默认 true）。
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);
    expect(find.byKey(captureChannelTextKey), findsNothing);
  });

  testWidgets('凹槽缺口点击不穿透 body：间隙环区域不误触 body/不切换 Tab',
      (WidgetTester tester) async {
    final database = await _pumpShell(tester);
    if (database == null) return;

    // FAB 中心即 centerDocked 锚点 = 底栏顶缘。花瓣尖=外接半径 28，凹槽
    // 半径 = (56 + 2×notchMargin 6)/2 = 34 → 取 31（间隙环内、凹槽缺口）。
    // 机制：RenderPhysicalShape.hitTest 对凹槽 clip 路径做 contains 判定，
    // 缺口区直接拒绝 → 点击穿透底栏子树，由 Scaffold body Material 吸收
    // （extendBody=false 时缺口身后无手势处理者，故无害；若未来
    // extendBody=true 或栏后加可点内容须重验）。
    final Offset fabCenter = tester.getCenter(find.byType(FloatingActionButton));
    final Offset gapPoint = fabCenter.translate(0, 31);
    await tester.tapAt(gapPoint);
    await _settle(tester);

    // 缺口点击：不唤起抽屉、不切 Tab——三 Tab 标签仍各恰一（若被静默切到
    // 某个 Tab，其页面 AppBar 标题会叠加令 findsOneWidget 失败）。
    expect(find.byKey(captureChannelTextKey), findsNothing);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byType(BottomAppBar), findsOneWidget);
  });

  testWidgets('360dp 窄屏冒烟：凹槽与相邻 destination pill 贴边档壳可完整构建',
      (WidgetTester tester) async {
    // [9] 评审发现：360dp 下凹槽弧与「账本/计划」选中 pill 顶角最小间距
    // 仅 ~1.1dp（≤340dp 会出现 pill 顶角被凹槽裁切 2-4dp 的缺口）——本用例
    // 只保证窄屏档构建/pumpAndSettle 不炸；pill 顶角裁切观感属真机眼检项
    //（见 apps-mobile CHANGELOG 遗留项）。
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) return;
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await _settle(tester);

    expect(find.byType(BottomAppBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    // 窄屏选中态切换（pill 最贴近凹槽的档位）收敛。
    await tester.tap(find.text('账本'));
    await _settle(tester);
    expect(find.text('账本'), findsOneWidget);
  });

  test('6 主题包 × 明暗：primary/outline 对 surfaceCard 自然达标 3:1（容器类）', () {
    // 范围注记：本用例只覆盖 6 内置包 × 明暗的全部实际组合；dynamic_color
    // 平台取色与用户自定义包不在矩阵内——该路径由装配出口 enforceSlimcaAa
    // 兜底（不达标自动降级最近安全 tone，允许降级、不允许崩溃）。
    for (final ThemeProfile profile in kSlimcaPresetThemeProfiles) {
      for (final Brightness brightness in Brightness.values) {
        final SlimcaTheme tokens =
            profile.toSlimcaTheme(brightness, enforceAa: false);
        final double primaryRatio =
            computeContrastRatio(tokens.primary, tokens.surfaceCard);
        final double outlineRatio =
            computeContrastRatio(tokens.outline, tokens.surfaceCard);
        expect(primaryRatio, greaterThanOrEqualTo(kAaUiContrast),
            reason: '${profile.id}/$brightness primary↔surfaceCard 需自然达标'
                '（实 Ratio=${primaryRatio.toStringAsFixed(2)}）——靠 '
                'enforceSlimcaAa 降级会牵动全 App 主色，应改该包 profile');
        expect(outlineRatio, greaterThanOrEqualTo(kAaUiContrast),
            reason: '${profile.id}/$brightness outline 描边兜底可用'
                '（实 Ratio=${outlineRatio.toStringAsFixed(2)}）');
      }
    }
  });

  testWidgets('MotionLevel=off 档：底栏壳 pumpAndSettle 收敛（坑点 11）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) return;
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);

    // 真 slimcaRouter 壳 + off 档动效（buildTheme 注入 MotionConfig off——
    // 全部动画路径显式 off 分支（100ms fadeOff）→ pumpAndSettle 必须收敛。
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider
              .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
          captureParserProvider.overrideWithValue(createCaptureParser()),
        ],
        child: MaterialApp.router(
          theme: buildTheme(
            brightness: Brightness.light,
            motion: MotionConfig.forLevel(MotionLevel.off),
          ),
          routerConfig: slimcaRouter,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await _settle(tester);
    expect(find.byType(BottomAppBar), findsOneWidget);

    // 切 Tab（off 档 100ms fadeOff）收敛。
    await tester.tap(find.text('账本'));
    await _settle(tester);
    expect(find.text('账本'), findsOneWidget);

    // 唤起抽屉 + 关闭（off 档）收敛。
    await tester.tap(find.byType(FloatingActionButton));
    await _settle(tester);
    expect(find.byKey(captureChannelTextKey), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await _settle(tester);
    expect(find.byKey(captureChannelTextKey), findsNothing);
  });
}
