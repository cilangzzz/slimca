/// 主题/动效的设备本地配置存取（§5.6⑲ settings 内容清单「动效等级/当前主题」、
/// §8.3「深浅色：跟随系统 + 日落定时切换」与 dynamic_color）。
///
/// 存储位置：settings 表（§5.6⑲ 本地键值配置，value 一律 JSON；本地件、永不
/// 同步）。注意分工：**当前主题指针（[kSettingCurrentThemeId]）与动效等级是
/// 设备本地选择**，指向同步真值表 theme_profiles 的行（§5.6⑳——包本身随
/// 同步走，换设备主题跟随；指针随设备，UI 偏好本地自决）。
///
/// 坏值口径（§6.1 本地优先）：缺键/坏 JSON/未知枚举一律回落默认——默认包=
/// 「墨」（W1 基线）、动效=full（§9.2 表值）、深浅=跟随系统、dynamic_color=关
/// （§8.3 手动主题优先，默认关）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:ui_kit/ui_kit.dart' show MotionLevel;

/// settings 键：当前主题包 id（§5.6⑲「当前主题」；值 = theme_profiles.id）。
const String kSettingCurrentThemeId = 'current_theme_id';

/// settings 键：动效等级（§5.6⑲「动效等级」；off/reduced/full，§9.2）。
const String kSettingMotionLevel = 'motion_level';

/// settings 键：深浅色手动覆盖（system/light/dark；缺省 system=跟随系统，
/// §8.3；W16 落「手动覆盖」半边，「日落定时切换」P2 再接）。
const String kSettingThemeModeOverride = 'theme_mode_override';

/// settings 键：dynamic_color 开关（§8.3「Android 12+ Material You：仅映射
/// primary/seed 两源」；默认关=手动主题优先，任务口径）。
const String kSettingDynamicColorEnabled = 'dynamic_color_enabled';

/// 默认主题包 id（「墨」= ui_kit 内置包清单首位，§8.3 内置默认；settings ⑲
/// current_theme_id 缺省值）。常量声明 + 单测断言与 ui_kit
/// `presetThemeProfileById` 同源（防止 ui_kit 清单重排后指针漂移）。
const String kDefaultThemePackId = 'preset-mo';

/// 主题偏好快照（bootstrap 启动期预载初值 + 运行期控制器状态，§10.4）。
class ThemeSettings {
  const ThemeSettings({
    this.packId = kDefaultThemePackId,
    this.motionLevel = MotionLevel.full,
    this.themeMode = ThemeMode.system,
    this.dynamicColorEnabled = false,
  });

  /// 当前主题包 id（theme_profiles.id，§5.6⑳）。
  final String packId;

  /// 动效等级（§9.2 MotionLevel；MotionConfig.forLevel 消费）。
  final MotionLevel motionLevel;

  /// 深浅色模式（跟随系统 / 手动覆盖，§8.3）。
  final ThemeMode themeMode;

  /// dynamic_color 开关（§8.3，默认关=手动主题优先）。
  final bool dynamicColorEnabled;

  ThemeSettings copyWith({
    String? packId,
    MotionLevel? motionLevel,
    ThemeMode? themeMode,
    bool? dynamicColorEnabled,
  }) =>
      ThemeSettings(
        packId: packId ?? this.packId,
        motionLevel: motionLevel ?? this.motionLevel,
        themeMode: themeMode ?? this.themeMode,
        dynamicColorEnabled: dynamicColorEnabled ?? this.dynamicColorEnabled,
      );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeSettings &&
        other.packId == packId &&
        other.motionLevel == motionLevel &&
        other.themeMode == themeMode &&
        other.dynamicColorEnabled == dynamicColorEnabled;
  }

  @override
  int get hashCode =>
      Object.hash(packId, motionLevel, themeMode, dynamicColorEnabled);
}

/// 启动期预载（bootstrap() 调用，返回 override 初值——首帧即正确主题、零
/// 闪跳，§2.3 步 0；坏值逐键自愈回落默认，§6.1）。
Future<ThemeSettings> loadThemeSettings(db.AppDatabase database) async {
  final String? packId = await _loadString(database, kSettingCurrentThemeId);
  final String? motion = await _loadString(database, kSettingMotionLevel);
  final String? mode = await _loadString(database, kSettingThemeModeOverride);
  final bool? dynamicEnabled =
      await _loadBool(database, kSettingDynamicColorEnabled);
  return ThemeSettings(
    packId: packId ?? kDefaultThemePackId,
    motionLevel: _parseMotionLevel(motion),
    themeMode: _parseThemeMode(mode),
    dynamicColorEnabled: dynamicEnabled ?? false,
  );
}

MotionLevel _parseMotionLevel(String? wire) => switch (wire) {
      'off' => MotionLevel.off,
      'reduced' => MotionLevel.reduced,
      'full' => MotionLevel.full,
      _ => MotionLevel.full, // 缺键/坏值回落 full（§9.2 默认档）。
    };

ThemeMode _parseThemeMode(String? wire) => switch (wire) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system, // 缺键/坏值回落跟随系统（§8.3）。
    };

Future<String?> _loadString(db.AppDatabase database, String key) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(key)))
      .getSingleOrNull();
  if (row == null) {
    return null;
  }
  try {
    final Object? value = jsonDecode(row.value);
    return value is String ? value : null;
  } on FormatException {
    return null; // 坏值视同未设置（§5.6⑲ 本地件自愈口径）。
  }
}

Future<bool?> _loadBool(db.AppDatabase database, String key) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(key)))
      .getSingleOrNull();
  if (row == null) {
    return null;
  }
  try {
    final Object? value = jsonDecode(row.value);
    return value is bool ? value : null;
  } on FormatException {
    return null;
  }
}

/// 写当前主题包指针（设置页/编辑器选择；settings.value 一律 JSON，§5.6⑲）。
Future<void> saveCurrentThemeId(
  db.AppDatabase database, {
  required String packId,
}) =>
    _saveString(database, kSettingCurrentThemeId, packId);

/// 写动效等级（§9.2 MotionLevel）。
Future<void> saveMotionLevel(
  db.AppDatabase database, {
  required MotionLevel level,
}) =>
    _saveString(database, kSettingMotionLevel, level.name);

/// 写深浅色模式（§8.3 跟随系统 + 手动覆盖）。
Future<void> saveThemeModeOverride(
  db.AppDatabase database, {
  required ThemeMode mode,
}) =>
    _saveString(database, kSettingThemeModeOverride, mode.name);

/// 写 dynamic_color 开关（§8.3，默认关）。
Future<void> saveDynamicColorEnabled(
  db.AppDatabase database, {
  required bool enabled,
}) =>
    _saveBool(database, kSettingDynamicColorEnabled, enabled);

Future<void> _saveString(
  db.AppDatabase database,
  String key,
  String value,
) async {
  await database.into(database.settings).insertOnConflictUpdate(
        db.SettingsCompanion.insert(key: key, value: jsonEncode(value)),
      );
}

Future<void> _saveBool(
  db.AppDatabase database,
  String key,
  bool value,
) async {
  await database.into(database.settings).insertOnConflictUpdate(
        db.SettingsCompanion.insert(key: key, value: jsonEncode(value)),
      );
}
