/// AI 服务配置（用户自设 API Key/Base/Model）的存取（§3.7 数据主权、
/// §5.6⑲ settings 表本地键值配置）。
///
/// 用户拍板（2026-11-18）：AI apikey 调整为**用户自行设置**，默认为空——
/// 空 key → 解析器装配离线确定性桩（HeuristicFakeLlmAdapter，经 core_ai
/// 完整管线的 mock）；用户配置后 → OpenAI 兼容 adapter。凭据存 settings 表
/// （**本地件、永不同步**，§5.1 表分组——key 只存本机，不随同步出设备）。
///
/// 兼容注记：dart-define（SLIMCA_AI_BASE/KEY/MODEL）降级为「用户从未保存过
/// 配置时的开发联调回退」（bootstrap 判 `configured` 后传 null 让工厂回落
/// dart-define）；用户一旦保存过配置（含保存为空），以用户配置为准。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;

/// settings 表键（§5.6⑲ 内容清单「AI 配置」）。
const String kSettingAiApiBase = 'ai_api_base';
const String kSettingAiApiKey = 'ai_api_key';
const String kSettingAiApiModel = 'ai_api_model';

/// AI 服务配置值（用户自设；空串=未设置该项）。
class AiApiConfig {
  const AiApiConfig({this.baseUrl = '', this.apiKey = '', this.model = ''});

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 是否配置了 API key（空 key → 离线确定性桩）。
  bool get hasKey => apiKey.trim().isNotEmpty;
}

/// 读取配置（缺键一律空串；「从未保存过任何 AI 配置行」时 [configured]=false，
/// bootstrap 据此回落 dart-define 开发联调口径，见库注）。
Future<(AiApiConfig, bool)> loadAiApiConfig(cdb.AppDatabase database) async {
  final rows = await (database.select(database.settings)
        ..where((s) => s.key.isIn([
              kSettingAiApiBase,
              kSettingAiApiKey,
              kSettingAiApiModel,
            ])))
      .get();
  String base = '';
  String key = '';
  String model = '';
  var configured = false;
  for (final row in rows) {
    configured = true;
    final decoded = jsonDecode(row.value);
    if (decoded is! String) continue; // 坏值视同未设置（§5.6⑲ 本地件自愈）。
    switch (row.key) {
      case kSettingAiApiBase:
        base = decoded;
      case kSettingAiApiKey:
        key = decoded;
      case kSettingAiApiModel:
        model = decoded;
    }
  }
  return (AiApiConfig(baseUrl: base, apiKey: key, model: model), configured);
}

/// 写回配置（设置页保存；三键 upsert，settings.value 一律 JSON，§5.6⑲）。
Future<void> saveAiApiConfig(
  cdb.AppDatabase database, {
  required AiApiConfig config,
}) async {
  final rows = <(String, String)>[
    (kSettingAiApiBase, config.baseUrl),
    (kSettingAiApiKey, config.apiKey),
    (kSettingAiApiModel, config.model),
  ];
  for (final (key, value) in rows) {
    await database.into(database.settings).insertOnConflictUpdate(
          cdb.SettingsCompanion.insert(key: key, value: jsonEncode(value)),
        );
  }
}
