/// theme_profiles 行 ↔ ui_kit [ThemeProfile] 映射与内置包种子（§5.6⑳「主题包
/// 是一等同步实体，换设备主题跟随」、§8.3「主题包 = JSON profile」、§11.2 W16）。
///
/// 分层口径（§10.4）：ui_kit 持有主题包模型/6 内置包/序列化（theme_profile.dart/
/// theme_presets.dart，不依赖 drift）；core_db 持有 theme_profiles 表（W1 冻结
/// schema，含 §5.1 同步公共列）；本文件是壳层粘合——行↔包互转 + 内置包幂等
/// 种子（写路径经 DriftThemeProfileRepository → SyncOutboxWriter 同事务入队
/// outbox，§6.2）。
///
/// 上移注记：core_db 无 ThemeProfilesDao（W1 核对——建表冻结时无调用方），
/// 主题域写路径暂驻壳层 data 层（DriftThemeProfileRepository）；建议下个迭代
/// 整体上移 core_db（与 FoodItemsDao 同纪律），届时本文件的行映射随迁。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:ui_kit/ui_kit.dart'
    show MotionLevel, ThemeProfile, kSlimcaPresetThemeProfiles;

import '../data/theme_profile_repository.dart';

/// 内置包幂等种子（§6.2：业务行 + outbox 同事务；已存在即跳过）。
///
/// 由 bootstrap() 启动期调用（与 ensureDefaultLedgers 同段，§5.4）；两端独立
/// 种子产出同一 preset-* 行：内容恒定（ui_kit 包定义常量），同步层按行 id
/// upsert 收敛（§6.2 幂等键纪律）。tokens 列 = ui_kit `ThemeProfile.toTokensJson`
/// 编码（种子色 + §8.2 四滑杆 + AMOLED 开关——包定义真值，§8.3）。
Future<void> ensurePresetThemeProfiles(db.AppDatabase database) async {
  final DriftThemeProfileRepository repository = DriftThemeProfileRepository(
    database,
  );
  await repository.ensureSeeded(<ThemeProfileSeedInput>[
    for (final ThemeProfile preset in kSlimcaPresetThemeProfiles)
      ThemeProfileSeedInput(
        id: preset.id,
        name: preset.name,
        tokensJson: jsonEncode(preset.toTokensJson()),
        motionLevel: preset.motionLevel.name,
        sort: preset.sort,
        isPreset: true,
      ),
  ]);
}

/// theme_profiles 行 → ui_kit [ThemeProfile]（自定义包解析）。
///
/// 坏值口径（§6.1 本地优先）：tokens 非法 JSON/缺种子字段 → null（调用方
/// 回退默认包——不猜、不崩）。sync 公共列（hlc/revision 等 §5.1）不参与包
/// 语义，行级 LWW 由同步层仲裁（§6.5）。
ThemeProfile? themeProfileFromRow(db.ThemeProfile row) {
  try {
    final Map<String, Object?> tokens =
        jsonDecode(row.tokens) as Map<String, Object?>;
    return ThemeProfile.fromTokensJson(
      tokens,
      id: row.id,
      name: row.name,
      motionLevel: MotionLevel.values.asNameMap()[row.motionLevel] ??
          MotionLevel.full,
      fontId: row.fontId,
      isPreset: row.isPreset,
      sort: row.sort,
    );
  } on Object {
    return null; // 坏 tokens 行：解析失败回退默认包（§6.1）。
  }
}
