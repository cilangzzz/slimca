/// W16 主题应用链路 providers（§11.2 W16 任务 2「ThemeProfile provider（当前
/// profile→buildTheme→MaterialApp，浅深跟随系统+手动覆盖）+ 切换时
/// SlimcaThemeMorph 全屏 morph」、§8.3/§9.3#10）。
///
/// 数据流：
/// settings 表（§5.6⑲ 本地件：当前主题指针/动效等级/深浅覆盖/dynamic 开关）
/// → [themeSettingsControllerProvider]（启动初值=bootstrap 预载 override，
/// 零闪跳 §2.3 步 0；运行期写回 settings）
/// → 包解析（内置包=ui_kit `kSlimcaPresetThemeProfiles` / 自定义包=
/// theme_profiles 流 + `themeProfileFromRow`，§5.6⑳）
/// → [slimcaLightThemeProvider]/[slimcaDarkThemeProvider]：ui_kit
/// `ThemeProfile.toSlimcaTheme`（种子→token+WCAG 护栏+AMOLED）→
/// `SlimcaDynamicThemeMapper.map`（§8.3 仅映射 primary/neutral 两源）→
/// ui_kit `buildTheme`（语义 token + MotionConfig 挂进主题，§8.2/§9.2）
/// → main.dart MaterialApp theme/darkTheme/themeMode + builder 内
/// `SlimcaThemeMorph`（§9.3#10 300ms 全屏 morph）。
///
/// 主题切换 = ColorScheme.lerp + ThemeExtension lerp（§8.3）：morph 由
/// SlimcaThemeMorph 承担，本文件只负责「主题源（settings 流）变化时更新
/// data」（ui_kit theme_morph.dart 契约）；dynamic_color 集成同 ui_kit
/// SlimcaDynamicColorBuilder 的装配语义（widget 形态不套 MaterialApp.theme
/// 参数，故取其同款三步：toSlimcaTheme → map → buildTheme）。
library;

import 'dart:async';

import 'package:core_db/core_db.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show CorePalette;
import 'package:ui_kit/ui_kit.dart'
    show
        CorePaletteLoader,
        MotionConfig,
        MotionLevel,
        SlimcaDynamicThemeMapper,
        SlimcaTheme,
        ThemeProfile,
        buildTheme,
        kSlimcaPresetThemeProfiles,
        loadPlatformCorePalette,
        presetThemeProfileById;

import '../app/providers.dart'
    show appDatabaseProvider, telemetryServiceProvider;
import '../data/theme_profile_repository.dart';
import '../telemetry/w16_funnel_events.dart';
import 'theme_profiles.dart' show themeProfileFromRow;
import 'theme_settings.dart';

// ── 依赖注入（§10.4 壳负责装配）─────────────────────────────────────

/// theme_profiles 仓库 provider（§5.6⑳；§6.2 写路径纪律见仓库文件头）。
///
/// 注：core_db 无 ThemeProfilesDao（W1 核对），实现暂驻壳层 data 层
/// （DriftThemeProfileRepository），建议上移 core_db——见仓库/映射文件头注记。
final themeProfileRepositoryProvider = Provider<DriftThemeProfileRepository>((
  ref,
) {
  return DriftThemeProfileRepository(ref.watch(appDatabaseProvider));
});

/// theme_profiles 流（编辑器网格/自定义包解析；Drift reactive stream，§10.1）。
final themeProfilesStreamProvider =
    StreamProvider<List<db.ThemeProfile>>((ref) {
      return ref.watch(themeProfileRepositoryProvider).watchAll();
    });

/// 平台动态色取色器注入点（§10.4 装配纪律；测试 override Fake，禁真实平台
/// 通道——ui_kit `CorePaletteLoader` 契约）。缺省 = ui_kit
/// [loadPlatformCorePalette]（dynamic_color 插件通道，不支持平台吞异常返回
/// null=回退手动种子色，§8.3）。
final corePaletteLoaderProvider = Provider<CorePaletteLoader>((ref) {
  return loadPlatformCorePalette;
});

// ── 设置态（§5.6⑲ 本地件）──────────────────────────────────────────

/// 主题偏好启动初值（bootstrap() 预载 settings 表后 override——首帧即正确
/// 主题、零闪跳，§2.3 步 0；缺省 = 默认包/full/跟随系统/dynamic 关）。
final initialThemeSettingsProvider = Provider<ThemeSettings>(
  (ref) => const ThemeSettings(),
);

/// 主题偏好控制器（§11.2 W16 任务 2）：状态 = [ThemeSettings]；写路径 =
/// 先改状态（UI 即刻生效）→ 异步落库 settings（失败向上抛给调用方 SnackBar，
/// 状态不回滚——下次启动按落库值装配，本地件自愈口径，与设置页开关同款）。
class ThemeSettingsController extends Notifier<ThemeSettings> {
  @override
  ThemeSettings build() => ref.read(initialThemeSettingsProvider);

  /// 切换主题包（§11.2 W16 任务 2/4）：状态先行 → settings 落库 →
  /// theme_changed 漏斗（§11.2 W16 任务 5；props 仅标量标签，§3.9）。
  ///
  /// morph（§9.3#10）不在此触发——状态变化使 resolved ThemeData 更新，
  /// main.dart builder 内 SlimcaThemeMorph 消费新 data 完成全屏 lerp。
  Future<void> selectPack(String packId, {required String source}) async {
    if (state.packId == packId) {
      return; // 重复选择幂等：不发事件不落库（§6.2 噪声抑制同源）。
    }
    state = state.copyWith(packId: packId);
    unawaited(
      ref
          .read(telemetryServiceProvider)
          .funnel(
            W16TelemetryFunnel.themeChanged,
            props: <String, Object?>{'theme_id': packId, 'source': source},
          ),
    );
    await saveCurrentThemeId(ref.read(appDatabaseProvider), packId: packId);
  }

  /// 动效等级（§9.2 MotionLevel；§8.1「动效与主题同源同发」——编辑器动效段
  /// 即改即生效，morph 由 main.dart SlimcaThemeMorph 承担）。
  Future<void> setMotionLevel(MotionLevel level) async {
    if (state.motionLevel == level) return;
    state = state.copyWith(motionLevel: level);
    await saveMotionLevel(ref.read(appDatabaseProvider), level: level);
  }

  /// 深浅色模式（§8.3 跟随系统 + 手动覆盖）。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (state.themeMode == mode) return;
    state = state.copyWith(themeMode: mode);
    await saveThemeModeOverride(ref.read(appDatabaseProvider), mode: mode);
  }

  /// dynamic_color 开关（§8.3，默认关=手动主题优先；开启后经
  /// SlimcaDynamicThemeMapper 仅映射 primary/neutral 两源，语义色保持包锚定）。
  Future<void> setDynamicColorEnabled(bool enabled) async {
    if (state.dynamicColorEnabled == enabled) return;
    state = state.copyWith(dynamicColorEnabled: enabled);
    await saveDynamicColorEnabled(ref.read(appDatabaseProvider), enabled: enabled);
  }
}

/// 主题偏好 provider（页面/编辑器 watch；resolved 主题 provider 依赖）。
final themeSettingsControllerProvider =
    NotifierProvider<ThemeSettingsController, ThemeSettings>(
      ThemeSettingsController.new,
    );

// ── 包解析（§5.6⑳ → ui_kit ThemeProfile）───────────────────────────

/// 当前主题包（ui_kit [ThemeProfile]）。
///
/// 解析序：内置包 = `presetThemeProfileById`（ui_kit 常量清单，首帧零异步，
/// §2.3）；自定义包 = theme_profiles 流 + `themeProfileFromRow`（§5.6⑳ tokens
/// JSON 种子色格式）；指针指向不存在的包/坏 tokens/流未就绪 → 回退默认包
/// （「墨」，§6.1 坏值自愈）。select 只订阅 packId——动效档/深浅覆盖变化不
/// 触发包解析重算（避免 ThemeData 无谓重建）。
final resolvedThemeProfileProvider = Provider<ThemeProfile>((ref) {
  final String packId = ref.watch(
    themeSettingsControllerProvider.select((s) => s.packId),
  );
  final ThemeProfile? preset = presetThemeProfileById(packId);
  if (preset != null) {
    return preset;
  }
  final List<db.ThemeProfile>? profiles =
      ref.watch(themeProfilesStreamProvider).value;
  if (profiles != null) {
    for (final db.ThemeProfile row in profiles) {
      if (row.id == packId && row.deletedAt == null) {
        final ThemeProfile? custom = themeProfileFromRow(row);
        if (custom != null) {
          return custom;
        }
        break; // 坏 tokens 行：落入下方默认包回退（§6.1）。
      }
    }
  }
  return kSlimcaPresetThemeProfiles.first;
});

/// 平台动态色（§8.3 仅映射 primary/neutral 两源；关闭/加载中/不可用 → null=
/// 手动主题优先）。
///
/// 关闭态不触碰平台通道（任务口径「默认关，手动主题优先」——默认零通道调用，
/// 测试零副作用）。select 只订阅开关位：无关设置变化不重跑取色。
final platformCorePaletteProvider = FutureProvider<CorePalette?>((ref) async {
  final bool enabled = ref.watch(
    themeSettingsControllerProvider.select((s) => s.dynamicColorEnabled),
  );
  if (!enabled) {
    return null;
  }
  return ref.watch(corePaletteLoaderProvider)();
});

// ── 主题装配（ui_kit 三步：toSlimcaTheme → map → buildTheme）─────────

/// 浅色 ThemeData（§11.2 W16 任务 2）：包种子派生语义 token（含 §8.3 WCAG
/// 护栏与 AMOLED 纯黑）→ dynamic_color 两源映射（§8.3）→ ui_kit buildTheme
/// （语义 token + MotionConfig 挂进主题）。
final slimcaLightThemeProvider = Provider<ThemeData>((ref) {
  final ThemeProfile profile = ref.watch(resolvedThemeProfileProvider);
  final CorePalette? palette = ref.watch(platformCorePaletteProvider).value;
  return _slimcaThemeData(ref, profile, Brightness.light, palette);
});

/// 深色 ThemeData（同上；曜黑 AMOLED 纯黑由包 `pureBlackDark` 生效）。
final slimcaDarkThemeProvider = Provider<ThemeData>((ref) {
  final ThemeProfile profile = ref.watch(resolvedThemeProfileProvider);
  final CorePalette? palette = ref.watch(platformCorePaletteProvider).value;
  return _slimcaThemeData(ref, profile, Brightness.dark, palette);
});

/// 单亮度装配（与 ui_kit `SlimcaDynamicColorBuilder._buildTheme` 同款三步）：
/// MotionLevel 取 settings ⑲ 动效等级（§5.6⑲ 设备本地偏好——编辑器动效段
/// 即改即写 settings），滑杆系数沿用包定义（§8.3 0.6x-1.5x）。
ThemeData _slimcaThemeData(
  Ref ref,
  ThemeProfile profile,
  Brightness brightness,
  CorePalette? palette,
) {
  final MotionLevel level =
      ref.watch(themeSettingsControllerProvider).motionLevel;
  final MotionConfig motion = profile
      .copyWith(motionLevel: level)
      .toMotionConfig();
  final SlimcaTheme tokens = SlimcaDynamicThemeMapper.map(
    palette: palette,
    base: profile.toSlimcaTheme(brightness),
    brightness: brightness,
  );
  return buildTheme(brightness: brightness, semantic: tokens, motion: motion);
}

/// 深浅色模式（§8.3 跟随系统 + 手动覆盖；main.dart themeMode 参数）。
final slimcaThemeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(themeSettingsControllerProvider).themeMode,
);

/// 当前包名（设置页主题入口副标题）。
final currentThemePackNameProvider = Provider<String>((ref) {
  return ref.watch(resolvedThemeProfileProvider).name;
});
