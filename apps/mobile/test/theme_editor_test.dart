// W16 主题编辑器测试（§11.2 W16 任务 1/3/4、§8.4、§5.6⑳、§6.2）。
//
// 覆盖链路：
// 1. 编辑器保存往返：ui_kit ThemeEditorPanel 草稿（命名）→ theme_profiles 行
//    （真值表，tokens JSON 往返一致）→ 指针落库 → 网格高亮 → 重开面板状态保持；
// 2. outbox 覆盖（§6.2 写路径纪律）：内置包种子 6 行；选预设包只改 settings
//    指针（本地件）不新增出网行；自定义包保存同事务 +1 行（op=upsert、payload
//    =整行快照）；自定义包软删 → 墓碑 delete 语义出网；
// 3. WCAG AA 护栏（§8.3）：编辑器反馈条渲染 + 命名空禁保存；护栏数学经 ui_kit
//    auditSlimcaAa/computeContrastRatio 直测（生效 token 经护栏兜底恒达标，
//    不达标禁保存的闸门在 ui_kit 面板内，其自测覆盖逐对降级）；
// 4. 坏值自愈（§6.1）：坏 tokens 行解析 null → 解析回退默认包；指针指向不
//    存在的包同样回退；内置包不可删（§5.6⑳ is_preset 语义护栏）；
// 5. 纯 Dart 单测：默认包 id 与 ui_kit 内置清单同源；tokens 行映射往返。
//
// 测试装配：内存 Drift 库（禁真实 IO/网络）+ RecordingTelemetryService；
// Windows 宿主缺 sqlite3 运行库时温和跳过（widget_test 同口径）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection, Value, Variable;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show captureGatewayProvider, captureParserProvider, createCaptureGateway;
import 'package:feature_plan/feature_plan.dart'
    show createPlanGateway, planGatewayProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/settings/settings_page.dart';
import 'package:slimca/main.dart';
import 'package:slimca/telemetry/w16_funnel_events.dart';
import 'package:slimca/theme/theme_profiles.dart'
    show ensurePresetThemeProfiles, themeProfileFromRow;
import 'package:slimca/theme/theme_settings.dart';
import 'package:ui_kit/ui_kit.dart'
    show
        SlimcaTheme,
        ThemeProfile,
        auditSlimcaAa,
        computeContrastRatio,
        kSlimcaPresetThemeProfiles,
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

/// theme_profiles 出网行数（§6.2 outbox 覆盖断言用）。
Future<int> _outboxCount(
  db.AppDatabase database, {
  String? rowId,
}) async {
  final rows = await database
      .customSelect(
        "SELECT row_id FROM sync_outbox WHERE table_name = 'theme_profiles'",
      )
      .get();
  if (rowId == null) {
    return rows.length;
  }
  return rows.where((r) => r.data['row_id'] == rowId).length;
}

/// ui_kit 编辑器的包名输入框（labelText=主题包名称）。
Finder _nameField() => find.byWidgetPredicate(
      (Widget w) => w is TextField && w.decoration?.labelText == '主题包名称',
    );

/// ui_kit 编辑器的保存按钮（AA 全达标文案）。
Finder _saveButton() => find.widgetWithText(FilledButton, '保存主题包');

void main() {
  // ── 纯 Dart 单测（无 DB/平台依赖，任何宿主可跑）──────────────────────

  test('W16 默认包 id 与 ui_kit 内置清单同源（§8.3 内置默认=墨）', () {
    final ThemeProfile mo = presetThemeProfileById(kDefaultThemePackId)!;
    expect(mo.name, '墨');
    expect(mo.isPreset, isTrue);
    expect(mo.sort, 0, reason: '墨 = 内置清单首位（settings ⑲ 缺省指针指向它）');
    expect(kSlimcaPresetThemeProfiles.length, 6, reason: '§8.3 六套内置包');
  });

  test('W16 WCAG 数学（ui_kit 护栏）：黑白 21:1；不达标组合被 audit 拒绝（§8.3）',
      () {
    expect(
      computeContrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
      ),
      closeTo(21, 0.1),
    );
    expect(
      computeContrastRatio(
        const Color(0xFFFFFFFF),
        const Color(0xFFFFFFFF),
      ),
      closeTo(1, 0.001),
    );
    // 生效 token（护栏兜底后）逐对达标——编辑器保存闸门的常规路径。
    final SlimcaTheme presetTokens =
        presetThemeProfileById('preset-mo')!.toSlimcaTheme(Brightness.light);
    expect(auditSlimcaAa(presetTokens).every((r) => r.pass), isTrue);
  });

  test('W16 tokens 行映射往返：theme_profiles 行 ↔ ui_kit ThemeProfile（§5.6⑳）',
      () {
    final ThemeProfile mo = presetThemeProfileById('preset-mo')!;
    // 行 → 包：tokens JSON（ui_kit toTokensJson 编码）经 themeProfileFromRow
    // 解码，包语义（种子/滑杆/AMOLED 开关）逐字段一致。
    final String tokensJson = jsonEncode(mo.toTokensJson());
    final ThemeProfile decoded = ThemeProfile.fromTokensJson(
      jsonDecode(tokensJson) as Map<String, Object?>,
      id: mo.id,
      name: mo.name,
      motionLevel: mo.motionLevel,
      isPreset: true,
      sort: mo.sort,
    );
    expect(decoded, mo);
    // 坏 tokens 行 → themeProfileFromRow 返回 null（widget 集成侧断言解析
    // 回退默认包，见下方「坏值自愈」用例，§6.1）。
    expect(
      themeProfileFromRow(
        db.ThemeProfile(
          createdAt: 1,
          updatedAt: 1,
          hlc: 'x',
          revision: 1,
          schemaVer: 1,
          deviceId: 'test',
          id: 'row-bad',
          name: '坏包',
          tokens: 'not-json',
          motionLevel: 'full',
          isPreset: false,
          sort: 1,
        ),
      ),
      isNull,
    );
  });

  // ── 组件/集成测试（内存 DB）─────────────────────────────────────────

  testWidgets('W16 编辑器保存往返：ui_kit 面板草稿 → theme_profiles 行 + outbox '
      '同事务覆盖 + 指针落库 + 网格高亮 + 重开状态保持', (tester) async {
    tester.view.physicalSize = const Size(900, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      return; // Windows 宿主缺 sqlite3：跳过。
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDeviceId(database);
    await ensureDefaultLedgers(database, clock);
    await ensurePresetThemeProfiles(database);
    final recording = RecordingTelemetryService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider.overrideWithValue(
            createCaptureGateway(db: database, clock: clock),
          ),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          telemetryServiceProvider.overrideWithValue(recording),
          planGatewayProvider.overrideWithValue(
            createPlanGateway(db: database, clock: clock),
          ),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 前置：内置包种子 6 行 + 各自 outbox 出网行（§5.6⑳ 一等同步实体）。
    expect(await _outboxCount(database), 6);

    await _openThemeEditor(tester);

    // 选预设包：只改 settings 指针（本地件 §5.6⑲），theme_profiles 无新写入
    // → 出网行数不变（§6.2 只对真值表写入入队）。
    await tester.tap(find.byKey(const Key('theme_pack_card_preset-cream')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(await _outboxCount(database), 6,
        reason: '选预设包不改真值行——无新增出网行（§6.2）');

    // ── 自定义包保存（ui_kit 面板：AA 反馈条全达标 + 命名）────────────
    expect(find.textContaining('WCAG AA 全部达标'), findsOneWidget,
        reason: '生效 token 经护栏兜底 → AA 反馈条全达标（§8.3/§8.4）');
    // 草稿名 = 当前包名（奶油）→ 可直接保存为副本。
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNotNull);
    // 清空包名 → 禁保存（ui_kit 保存闸门：命名必备，§8.4）。
    await tester.enterText(_nameField(), '');
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNull,
        reason: '名字为空 → 保存按钮禁用（§8.4 命名与同步）');
    // 命名 → 恢复可保存（默认档位 AA 全达标）。
    await tester.enterText(_nameField(), '护眼薄荷');
    await tester.pump();
    expect(tester.widget<FilledButton>(_saveButton()).onPressed, isNotNull,
        reason: '命名 + 默认档位 AA 全达标 → 可保存');
    await tester.tap(_saveButton());
    await tester.pump(const Duration(milliseconds: 500));

    // theme_profiles 真值行（§5.6⑳）：命名/非内置/动效档。
    final List<db.ThemeProfile> profiles =
        await database.select(database.themeProfiles).get();
    final db.ThemeProfile custom = profiles.singleWhere((r) => !r.isPreset);
    expect(custom.name, '护眼薄荷');
    expect(custom.motionLevel, 'full');
    expect(custom.deletedAt, isNull);

    // tokens 往返：行 JSON 解码 = 保存草稿（= 奶油包种子派生，§8.3「主题包 =
    // JSON profile」）——包语义逐字段一致（含 id/name/is_preset/sort）。
    final ThemeProfile draft =
        presetThemeProfileById('preset-cream')!.copyWith(
      id: custom.id,
      name: '护眼薄荷',
      isPreset: false,
      sort: custom.sort,
    );
    final ThemeProfile? decoded = themeProfileFromRow(custom);
    expect(decoded, isNotNull);
    expect(decoded, draft);

    // outbox 覆盖（§6.2）：+1 行，op=upsert、payload=整行快照（读回而非
    // 调用方构造——SyncOutboxWriter 纪律）。
    expect(await _outboxCount(database), 7);
    final outboxRows = await database
        .customSelect(
          "SELECT * FROM sync_outbox WHERE table_name = 'theme_profiles'",
        )
        .get();
    final customOutbox =
        outboxRows.singleWhere((r) => r.data['row_id'] == custom.id);
    expect(customOutbox.data['op'], 'upsert');
    final payload = jsonDecode(customOutbox.data['payload']! as String)
        as Map<String, Object?>;
    expect(payload['name'], '护眼薄荷');
    // customSelect 读回的行快照为 SQLite 原生类型：bool 列以 0/1 整型落 payload。
    expect(payload['is_preset'] == false || payload['is_preset'] == 0, isTrue);
    expect(payload['tokens'], custom.tokens);
    expect(payload['hlc'], custom.hlc);

    // 指针落库 + 漏斗（theme_changed source=custom，§11.2 W16 任务 5）。
    final row = await database
        .customSelect(
          "SELECT value FROM settings WHERE key = 'current_theme_id'",
        )
        .getSingle();
    expect(jsonDecode(row.data['value']! as String), custom.id);
    final changed = recording.byName(W16TelemetryFunnel.themeChanged);
    expect(changed, isNotEmpty);
    expect(changed.last.props['theme_id'], custom.id);
    expect(changed.last.props['source'], 'custom');

    // 网格高亮（当前包 = 自定义包，§11.2 W16 任务 4「当前高亮」）。
    expect(find.byKey(const Key('theme_pack_selected_icon')), findsOneWidget);

    // 刷掉 SnackBar 展示期定时器（默认 4s）——避免收尾 pending timer
    // （widget_test 同口径）。
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // 往返：关面板重开（仍在设置 Tab——find.text('我的') 会同时命中导航标签
    // 与 AppBar 标题，故直接复点入口）→ 自定义包卡片仍在且高亮
    // （§5.6⑳ 入库后状态保持）。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(settingsThemeEntryKey));
    await tester.pumpAndSettle();
    // 网格卡名（作用域到 GridView：ui_kit 编辑器包名输入框同样持有
    // 「护眼薄荷」，裸 find.text 会双命中）。
    expect(
      find.descendant(of: find.byType(GridView), matching: find.text('护眼薄荷')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('theme_pack_selected_icon')), findsOneWidget);
    // 全 app 生效：自定义包 token 与草稿同源（= 奶油包派生）。
    final ThemeData appTheme =
        tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;
    expect(
      appTheme.colorScheme.surface,
      presetThemeProfileById('preset-cream')!.toSlimcaTheme(Brightness.light)
          .surface,
    );
  });

  // 注：本用例不用 widget 树（ProviderContainer + 内存库直读），用纯 Dart
  // test()。Riverpod 3 起无 active listener 的 StreamProvider 订阅被暂停
  // （3.3.2 CHANGELOG「StreamProvider now pauses its StreamSubscription when
  // the provider is not actively listened」）——只 await `.future` 不算
  // active listener，流永不派发（实测 10min 超时）。先 container.listen 建
  // 立活动订阅再 await future（widget 用例经 pumpWidget 的 watch 天然满足）。
  test('W16 坏值自愈：坏 tokens 行/幽灵指针回退默认包；内置包不可删；'
      '自定义包软删墓碑 delete 出网（§6.1、§5.6⑳、§6.5）', () async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      return;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDeviceId(database);
    await ensurePresetThemeProfiles(database);

    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        hlcClockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);

    // 直接插入坏 tokens 行（模拟对端同步到达的坏值，§6.1）。
    await database.into(database.themeProfiles).insert(
          db.ThemeProfilesCompanion.insert(
            id: 'custom_bad',
            name: '坏包',
            tokens: 'not-json',
            motionLevel: 'full',
            fontId: const Value(null),
            isPreset: false,
            sort: 99,
            createdAt: 1,
            updatedAt: 1,
            hlc: 'test-local-insert-hlc',
            revision: 1,
            deviceId: deviceId,
          ),
        );
    // 预热主题包流（custom pack 解析数据源）：Riverpod 3 需 active listener
    // 订阅才不暂停（见用例头注），listen 句柄随用例关闭。
    final streamSub = container.listen(themeProfilesStreamProvider, (_, __) {});
    addTearDown(streamSub.close);
    await container.read(themeProfilesStreamProvider.future);

    // 指针指向坏 tokens 包 → 解析回退默认包（不猜不崩，§6.1）。
    await container
        .read(themeSettingsControllerProvider.notifier)
        .selectPack('custom_bad', source: 'custom');
    expect(container.read(resolvedThemeProfileProvider),
        kSlimcaPresetThemeProfiles.first);

    // 指针指向不存在的包（幽灵 id）→ 同样回退默认包。
    await container
        .read(themeSettingsControllerProvider.notifier)
        .selectPack('preset-ghost', source: 'custom');
    expect(container.read(resolvedThemeProfileProvider),
        kSlimcaPresetThemeProfiles.first);

    // 内置包不可删（§5.6⑳ is_preset 语义护栏）。
    final repo = container.read(themeProfileRepositoryProvider);
    await expectLater(repo.softDelete('preset-mo'), throwsStateError);
    // 自定义包软删 → 墓碑行 + 出网行（delete 语义经快照 deleted_at 判定）。
    final profile = await repo.saveCustom(
      name: '可删包',
      tokensJson: jsonEncode(
        presetThemeProfileById('preset-mo')!.toTokensJson(),
      ),
      motionLevel: 'full',
    );
    await repo.softDelete(profile.id);
    final tombstone = await (database.select(database.themeProfiles)
          ..where((t) => t.id.equals(profile.id)))
        .getSingle();
    expect(tombstone.deletedAt, isNotNull);
    final outboxRows = await database
        .customSelect(
          "SELECT op FROM sync_outbox WHERE table_name = 'theme_profiles' "
          'AND row_id = ?',
          variables: [Variable.withString(profile.id)],
        )
        .get();
    expect(outboxRows.last.data['op'], 'delete',
        reason: '墓碑快照经 SyncOutboxWriter 判定为 delete 语义（§6.5）');
  });
}
