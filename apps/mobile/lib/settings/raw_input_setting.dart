/// raw_input 上云开关的存取与运行期持有（§3.7 数据主权、§3.3「raw_input 上云
/// 开关：默认关=即用即焚仅落结构化结果；开=原文留档便于排查；设置项可达」）。
///
/// 存储位置：settings 表（§5.6⑲ 本地键值配置，value 一律 JSON；内容清单
/// 明确列有「raw_input 上云开关」）。settings 是本地件、永不同步（§5.1 表
/// 分组）——开关是设备本地隐私选择。
///
/// 语义（W7-8 任务口径 + §7.4「raw_input 隐私：云端存储可关」）：
/// - **关（默认）**：AI 请求仅携带解析必需的「结构化最小集」（规范化文本，
///   §7.1 规范化输入=管线实际消费形态），原文全息内容不出设备；本地留痕
///   照旧（ai_parses 落结构化 raw_output，§5.6⑭——raw_input 本就不落库）；
/// - **开**：原文随 AI 请求上传，便于云端排查（原文留档）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;

/// settings 表键（§5.6⑲ 内容清单「raw_input 上云开关」）。
const String kSettingRawInputCloudEnabled = 'raw_input_cloud_enabled';

/// 运行期开关持有器（bootstrap 装载初值、设置页写回）。
///
/// 解析闸门（RawInputGateCaptureParser）在 AI 请求构造时同步读取——解析
/// 路径不需要响应式重建，故用可变持有器而非 StateNotifier（§10.4 装配纪律）。
class RawInputPolicy {
  /// 默认关（§3.3「默认关=即用即焚」）。
  bool enabled = false;
}

/// 读取开关（缺键/坏 JSON/非布尔一律回落默认关，本地件可自愈，§6.1）。
Future<bool> loadRawInputCloudEnabled(cdb.AppDatabase database) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(kSettingRawInputCloudEnabled)))
      .getSingleOrNull();
  if (row == null) return false;
  try {
    final value = jsonDecode(row.value);
    return value is bool && value;
  } on FormatException {
    return false; // 坏值视同未设置（§5.6⑲ 本地件自愈口径）。
  }
}

/// 写回开关（设置页 toggle；settings.value 一律 JSON，§5.6⑲）。
Future<void> saveRawInputCloudEnabled(
  cdb.AppDatabase database, {
  required bool enabled,
}) async {
  await database.into(database.settings).insertOnConflictUpdate(
        cdb.SettingsCompanion.insert(
          key: kSettingRawInputCloudEnabled,
          value: jsonEncode(enabled),
        ),
      );
}
