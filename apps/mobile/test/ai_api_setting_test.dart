// AI 服务配置（用户拍板：AI apikey 用户自设、默认空=离线解析桩）单元测试：
// - settings 表读写回环（本地件永不同步，key 只存本机 §3.7）；
// - configured 标记（从未保存过 → dart-define 开发联调回退口径）；
// - aiApiConfigProvider 装配（seed 注入初值、save 写回响应式）。
//
// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟同策略）。

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/app/providers.dart';
import 'package:slimca/settings/ai_api_setting.dart';

bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

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
      // 库加载失败的清理路径：忽略二次异常。
    }
    if (_isSqliteLibraryMissing(error)) return null;
    rethrow;
  }
}

void main() {
  test('AI 配置 settings 读写回环；坏值自愈为空串', () async {
    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AI 配置读写用例未执行');
      return;
    }
    addTearDown(database.close);

    // 未保存过：configured=false（dart-define 回退口径）。
    final (initial, configured) = await loadAiApiConfig(database);
    expect(configured, isFalse, reason: '从未保存过 → dart-define 联调回退');
    expect(initial.hasKey, isFalse, reason: '默认空 = 离线解析桩（用户拍板）');

    // 保存后回环 + configured=true（用户配置为准，含保存为空）。
    const saved = AiApiConfig(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'sk-test',
      model: 'deepseek-chat',
    );
    await saveAiApiConfig(database, config: saved);
    final (loaded, loadedConfigured) = await loadAiApiConfig(database);
    expect(loadedConfigured, isTrue, reason: '保存过 → 用户配置为准');
    expect(loaded.baseUrl, saved.baseUrl);
    expect(loaded.apiKey, saved.apiKey);
    expect(loaded.model, saved.model);
    expect(loaded.hasKey, isTrue);
  });

  test('aiApiConfigProvider：缺省空配置；seed 注入初值；save 写回', () {
    // 缺省（未装配 seed）：空配置、未保存过。
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(aiApiConfigProvider), (const AiApiConfig(), false));

    // seed 注入（bootstrap 预载 settings 初值口径）。
    final seeded = ProviderContainer(overrides: [
      aiApiConfigSeedProvider.overrideWithValue(
        (const AiApiConfig(apiKey: 'sk-seed'), true),
      ),
    ]);
    addTearDown(seeded.dispose);
    expect(
      seeded.read(aiApiConfigProvider),
      (const AiApiConfig(apiKey: 'sk-seed'), true),
    );

    // save 写回（设置页保存 → captureParserProvider 响应式重装的数据源）。
    const updated = AiApiConfig(baseUrl: 'https://x/v1', apiKey: 'sk-x');
    seeded.read(aiApiConfigProvider.notifier).save((updated, true));
    expect(seeded.read(aiApiConfigProvider), (updated, true));
  });
}
