// W16 主题应用链路测试（§11.2 W16 任务 2/4、§8.3、§9.3#10）。
//
// 覆盖链路：
// 1. 切换主题包 → 全 app ColorScheme/ThemeExtension 生效断言（期望值经 ui_kit
//    `ThemeProfile.toSlimcaTheme` 同源推导——测试校验壳层装配链，token 推导
//    数学由 ui_kit 自测覆盖）；
// 2. SlimcaThemeMorph 全屏 morph 触发：动画中点值 ≠ 新旧端点（300ms 内
//    进行中，§9.3#10「ColorScheme.lerp + ThemeExtension lerp」）；
// 3. 动效等级 off → morph 降级 100ms 淡入淡出（§9.2/§9.6 MotionLevel 治理）；
// 4. dynamic_color：默认关零平台通道调用；开启后经 ui_kit
//    SlimcaDynamicThemeMapper 仅映射 primary/neutral 两源、语义 token 保持
//    包锚定（§8.3 双主色不随系统色漂移）；关闭即回手动主题（手动主题优先）；
// 5. 深浅色：手动覆盖深色 + 曜黑 AMOLED 纯黑（§8.3 独立开关包化）；
// 6. settings ⑲ 指针/动效档/深浅覆盖落库（本地件自愈口径）。
//
// 测试装配：内存 Drift 库 + 固定 device_id + RecordingTelemetryService +
// Fake CorePaletteLoader（ui_kit 契约，禁真实平台通道）；Windows 宿主缺
// sqlite3 运行库时温和跳过（widget_test 同口径）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show CorePalette, Hct;
import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/settings/settings_page.dart';
import 'package:slimca/main.dart';
import 'package:slimca/telemetry/w16_funnel_events.dart';
import 'package:slimca/theme/theme_profiles.dart'
    show ensurePresetThemeProfiles;
import 'package:ui_kit/ui_kit.dart'
    show
        CorePaletteLoader,
        MotionConfig,
        MotionLevel,
        SlimcaDynamicThemeMapper,
        SlimcaTheme,
        ThemeProfile,
        buildTheme,
        presetThemeProfileById;

import 'test_support.dart';

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

/// Material You 取色 Fake（ui_kit CorePaletteLoader 契约；§11.2 测试边界：
/// 禁真实平台通道。合成紫色动态取色，与 ui_kit 自测同款——CorePalette.of
/// 收 ARGB 源色，经 Hct 生成 hue 260 / chroma 40 的紫）。
class _FakeCorePaletteLoader {
  int calls = 0;

  final CorePalette palette = CorePalette.of(Hct.from(260, 40, 40).toInt());

  CorePaletteLoader asLoader() {
    return () async {
      calls++;
      return palette;
    };
  }
}

/// 最小装配（widget_test 同款 §10.4 口径 + W16 注入点）；宿主缺 sqlite3
/// 运行库时返回 null（调用方温和跳过）。
Future<db.AppDatabase?> _pumpApp(
  WidgetTester tester, {
  required RecordingTelemetryService recording,
  required _FakeCorePaletteLoader fakeLoader,
}) async {
  tester.view.physicalSize = const Size(900, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final database = await _tryOpenMemoryDatabase();
  if (database == null) {
    // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，测试照常执行）。
    return database;
  }
  addTearDown(database.close);

  const deviceId = 'ABCDEF123456';
  final clock = HlcClock(deviceId: deviceId);
  await ensureDeviceId(database);
  await ensureDefaultLedgers(database, clock);
  await ensurePresetThemeProfiles(database);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        hlcClockProvider.overrideWithValue(clock),
        captureGatewayProvider
            .overrideWithValue(createCaptureGateway(db: database, clock: clock)),
        captureParserProvider.overrideWithValue(createCaptureParser()),
        telemetryServiceProvider.overrideWithValue(recording),
        corePaletteLoaderProvider.overrideWithValue(fakeLoader.asLoader()),
      ],
      child: const SlimcaApp(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
  return database;
}

/// 主题探针：壳层 NavigationBar 的 context（位于 SlimcaThemeMorph 之下，
/// 读到的即 morph 后全 app 生效的主题）。
ThemeData _themeOf(WidgetTester tester) =>
    Theme.of(tester.element(find.byType(NavigationBar)));

/// 我的 Tab → 主题编辑面板（弹簧抽屉收敛）。
///
/// 导航标签用 NavigationBar 子树作用域查找：slimcaRouter 是全局单例，同文件
/// 前一个用例可能已停在设置 Tab——此时 AppBar 标题「我的」与导航标签同时
/// 可见，裸 find.text 会多命中。
Future<void> _openThemeEditor(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text('我的')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(settingsThemeEntryKey));
  await tester.pumpAndSettle();
}

/// 壳层装配的期望 ThemeData（与 theme_providers 同款 ui_kit 三步：
/// toSlimcaTheme → map → buildTheme；palette=null=手动主题）。
ThemeData _expectedTheme(ThemeProfile profile, Brightness brightness) {
  return buildTheme(
    brightness: brightness,
    semantic: profile.toSlimcaTheme(brightness),
    motion: profile.copyWith(motionLevel: MotionLevel.full).toMotionConfig(),
  );
}

void main() {
  testWidgets('W16 链路：选包 → 全 app ColorScheme/ThemeExtension 生效 + '
      'morph 进行中点值 ≠ 新旧端点（§9.3#10 300ms）', (tester) async {
    final recording = RecordingTelemetryService();
    final database = await _pumpApp(
      tester,
      recording: recording,
      fakeLoader: _FakeCorePaletteLoader(),
    );
    if (database == null) {
      return; // Windows 宿主缺 sqlite3：跳过。
    }

    final ThemeProfile ink = presetThemeProfileById('preset-mo')!;
    // 奶油：kcal/money/中性三族 token 均与墨明显不同（morph 中点断言的稳健
    // 前提——森野与墨中性色差过小不宜作中点判据）。
    final ThemeProfile cream = presetThemeProfileById('preset-cream')!;
    final SlimcaTheme creamTokens = cream.toSlimcaTheme(Brightness.light);
    final SlimcaTheme inkTokens = ink.toSlimcaTheme(Brightness.light);
    expect(creamTokens.surface, isNot(inkTokens.surface),
        reason: '前置：两包 token 确实不同（否则中点断言无意义）');

    // 首帧 = 默认包（墨）：bootstrap 预载初值 → 零闪跳（§2.3 步 0）。
    final ThemeData before = _themeOf(tester);
    final ThemeData expectedBefore = _expectedTheme(ink, Brightness.light);
    expect(before.colorScheme.surface, expectedBefore.colorScheme.surface);
    expect(before.scaffoldBackgroundColor, expectedBefore.scaffoldBackgroundColor);
    expect(before.extension<SlimcaTheme>(), expectedBefore.extension<SlimcaTheme>());
    expect(before.extension<MotionConfig>()!.level, MotionLevel.full);

    // 我的 → 主题编辑器（theme_editor_opened 漏斗 §11.2 W16 任务 5）。
    await _openThemeEditor(tester);
    expect(recording.byName(W16TelemetryFunnel.themeEditorOpened), isNotEmpty);
    // 6 内置包渲染（§8.3 名称一字不差；作用域到 GridView——ui_kit 编辑器
    // 包名输入框持有当前包名「墨」，裸 find.text 会双命中）。
    for (final String name in <String>['墨', '纸', '霓虹', '奶油', '森野', '曜黑']) {
      expect(
        find.descendant(of: find.byType(GridView), matching: find.text(name)),
        findsOneWidget,
      );
    }

    // 选奶油 → 目标 ThemeData 即时切换（MaterialApp theme 参数）。
    await tester.tap(find.byKey(const Key('theme_pack_card_preset-cream')));
    await tester.pump();
    final ThemeData target =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    final ThemeData expectedTarget = _expectedTheme(cream, Brightness.light);
    expect(target.colorScheme.surface, expectedTarget.colorScheme.surface);
    expect(target.extension<SlimcaTheme>(), expectedTarget.extension<SlimcaTheme>());

    // morph 进行中（150ms/300ms）：全 app 主题为插值，≠ 新旧端点。
    await tester.pump(const Duration(milliseconds: 150));
    final ThemeData mid = _themeOf(tester);
    expect(mid.colorScheme.surface, isNot(inkTokens.surface));
    expect(mid.colorScheme.surface, isNot(creamTokens.surface));
    expect(mid.extension<SlimcaTheme>()!.kcalIn, isNot(inkTokens.kcalIn));
    expect(mid.extension<SlimcaTheme>()!.kcalIn, isNot(creamTokens.kcalIn));

    // morph 收敛：全 app ColorScheme/ThemeExtension/背景 = 目标包（§8.3）。
    await tester.pump(const Duration(milliseconds: 400));
    final ThemeData after = _themeOf(tester);
    expect(after.colorScheme.surface, creamTokens.surface);
    expect(after.scaffoldBackgroundColor, creamTokens.surface);
    expect(after.extension<SlimcaTheme>(), creamTokens);
    expect(after.extension<MotionConfig>()!.level, MotionLevel.full);

    // settings ⑲ 当前主题指针落库（§5.6⑲ 本地件 JSON）。
    final row = await database
        .customSelect(
          "SELECT value FROM settings WHERE key = 'current_theme_id'",
        )
        .getSingle();
    expect(jsonDecode(row.data['value']! as String), 'preset-cream');
    // theme_changed 漏斗（§11.2 W16 任务 5；props 仅标量标签 §3.9）。
    final changed = recording.byName(W16TelemetryFunnel.themeChanged);
    expect(changed, isNotEmpty);
    expect(changed.last.props['theme_id'], 'preset-cream');
    expect(changed.last.props['source'], 'preset');
  });

  testWidgets('W16 动效等级 off → morph 降级 100ms 淡入淡出（§9.2/§9.6）+ '
      'motion_level 落库', (tester) async {
    final recording = RecordingTelemetryService();
    final database = await _pumpApp(
      tester,
      recording: recording,
      fakeLoader: _FakeCorePaletteLoader(),
    );
    if (database == null) {
      return;
    }

    final ThemeProfile ink = presetThemeProfileById('preset-mo')!;
    final ThemeProfile amoled = presetThemeProfileById('preset-yaohei')!;
    // 深色下墨（蓝灰 tone 6）与曜黑（纯黑）surface 明显不同——中点断言的
    // 稳健前提（§8.3 AMOLED 纯黑）。
    expect(amoled.toSlimcaTheme(Brightness.dark).surface,
        isNot(ink.toSlimcaTheme(Brightness.dark).surface));

    await _openThemeEditor(tester);
    // 动效档 → 关（ui_kit 编辑器 MotionLevel 段；该次 morph 时长取旧档 token，
    // 留足裕量收敛）。分段控件在滚动面板深处——先滚入视口再点（否则 tap
    // 落在视口外不打中，与 ui_kit 自测 ensureVisible 同口径）。
    await tester.ensureVisible(find.text('关'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关'));
    // 先 pump 一帧让 provider 刷新（scheduler Timer(0)）+ AnimatedTheme 启动，
    // 再推进时长让 morph 收敛——单次 pump(duration) 只启动不动画（§9.3#10）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_themeOf(tester).extension<MotionConfig>()!.level, MotionLevel.off);

    // 深浅覆盖 → 深色（§8.3 手动覆盖；该次 morph 同样留足裕量）。
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_themeOf(tester).brightness, Brightness.dark);
    expect(_themeOf(tester).colorScheme.surface,
        ink.toSlimcaTheme(Brightness.dark).surface);

    // 动效=off 下选曜黑 → morph 应为 100ms 淡入淡出（§9.6）。
    await tester.ensureVisible(
      find.byKey(const Key('theme_pack_card_preset-yaohei')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_pack_card_preset-yaohei')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // 50ms 处仍为插值（≠ 端点）。
    expect(_themeOf(tester).colorScheme.surface,
        isNot(ink.toSlimcaTheme(Brightness.dark).surface));
    expect(_themeOf(tester).colorScheme.surface,
        isNot(amoled.toSlimcaTheme(Brightness.dark).surface));
    await tester.pump(const Duration(milliseconds: 150));
    // 200ms > 100ms → 已收敛至曜黑纯黑（AMOLED）。
    expect(_themeOf(tester).colorScheme.surface, const Color(0xFF000000));
    expect(_themeOf(tester).scaffoldBackgroundColor, const Color(0xFF000000));

    // settings ⑲ 动效等级/深浅覆盖落库（§5.6⑲）。
    final motionRow = await database
        .customSelect("SELECT value FROM settings WHERE key = 'motion_level'")
        .getSingle();
    expect(jsonDecode(motionRow.data['value']! as String), 'off');
    final modeRow = await database
        .customSelect(
          "SELECT value FROM settings WHERE key = 'theme_mode_override'",
        )
        .getSingle();
    expect(jsonDecode(modeRow.data['value']! as String), 'dark');
  });

  testWidgets('W16 dynamic_color：默认关零通道调用；开启经 ui_kit 两源映射、'
      '语义 token 保持包锚定（§8.3 手动主题优先）', (tester) async {
    final recording = RecordingTelemetryService();
    final fakeLoader = _FakeCorePaletteLoader();
    final database = await _pumpApp(
      tester,
      recording: recording,
      fakeLoader: fakeLoader,
    );
    if (database == null) {
      return;
    }

    final ThemeProfile ink = presetThemeProfileById('preset-mo')!;
    await _openThemeEditor(tester);

    // 默认关：零平台通道调用（§11.2 W16 任务 4 口径）。
    expect(fakeLoader.calls, 0,
        reason: 'dynamic_color 默认关 → 不触碰平台通道（手动主题优先）');
    final ThemeData manualTheme =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(manualTheme.colorScheme.primary,
        ink.toSlimcaTheme(Brightness.light).primary);

    // 开启：Fake 源一次取色 → ui_kit SlimcaDynamicThemeMapper 两源映射
    // （primary 源生效），surface/kcalIn 保持包派生（不整体套用系统色，§8.3）。
    await tester.tap(find.byKey(const Key('theme_dynamic_switch')));
    await tester.pumpAndSettle();
    expect(fakeLoader.calls, 1);
    final ThemeData dynamicTheme =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    final SlimcaTheme expectedMapped = SlimcaDynamicThemeMapper.map(
      palette: fakeLoader.palette,
      base: ink.toSlimcaTheme(Brightness.light),
      brightness: Brightness.light,
    );
    expect(dynamicTheme.colorScheme.primary, expectedMapped.primary);
    expect(dynamicTheme.scaffoldBackgroundColor, expectedMapped.surface,
        reason: '仅映射 primary/neutral 两源——不整体套用系统色（§8.3）');
    expect(dynamicTheme.extension<SlimcaTheme>(), expectedMapped);
    expect(dynamicTheme.extension<SlimcaTheme>()!.kcalIn,
        ink.toSlimcaTheme(Brightness.light).kcalIn,
        reason: '双主色锚定：健康绿语义不随系统色漂移（§8.2/§8.3）');

    // 关闭：即回手动主题包（手动主题优先），且不再取色。
    await tester.tap(find.byKey(const Key('theme_dynamic_switch')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.colorScheme
          .primary,
      ink.toSlimcaTheme(Brightness.light).primary,
    );
    expect(fakeLoader.calls, 1, reason: '关闭态不再调用取色源');
  });

  testWidgets('W16 深浅：手动覆盖深色（§8.3）+ 曜黑 AMOLED 纯黑 surface', (tester) async {
    final recording = RecordingTelemetryService();
    final database = await _pumpApp(
      tester,
      recording: recording,
      fakeLoader: _FakeCorePaletteLoader(),
    );
    if (database == null) {
      return;
    }

    final ThemeProfile ink = presetThemeProfileById('preset-mo')!;
    final ThemeProfile amoled = presetThemeProfileById('preset-yaohei')!;
    expect(amoled.toSlimcaTheme(Brightness.dark).surface,
        const Color(0xFF000000),
        reason: '曜黑 AMOLED = 纯黑 surface（§8.3 独立开关的包化落点）');

    await _openThemeEditor(tester);
    // 深浅覆盖 → 深色（§8.3 手动覆盖半边；「日落定时切换」P2 再接）。
    // 分段控件在滚动面板深处——先滚入视口再点（否则 tap 打不中）。
    await tester.ensureVisible(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_themeOf(tester).brightness, Brightness.dark);
    expect(_themeOf(tester).colorScheme.surface,
        ink.toSlimcaTheme(Brightness.dark).surface);

    // 选曜黑 → 深色 surface = 纯黑（AMOLED）。
    await tester.ensureVisible(
      find.byKey(const Key('theme_pack_card_preset-yaohei')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme_pack_card_preset-yaohei')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_themeOf(tester).scaffoldBackgroundColor, const Color(0xFF000000));

    // settings ⑲ 深浅覆盖落库（§5.6⑲）。
    final row = await database
        .customSelect(
          "SELECT value FROM settings WHERE key = 'theme_mode_override'",
        )
        .getSingle();
    expect(jsonDecode(row.data['value']! as String), 'dark');
  });
}
