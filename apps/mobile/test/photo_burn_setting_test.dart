/// W11-12 拍照原图「解析后即焚」开关测试（§3.7 数据主权、§3.3「原图解析后
/// 即焚不落存储」、§5.6㉑）。
///
/// 覆盖 settings 表存取：缺省开（即焚=合规缺省）→ 写读回环 → 坏 JSON/非布尔
/// 回落开（本地件自愈、损坏永不放宽，§6.1）。
///
/// 「数据与隐私」分组已移除（用户拍板，SettingsPage 开关 UI 不露出）——原
/// widget 级 toggle 覆盖随入口一并撤下；运行期策略（photoBurnPolicyProvider）
/// 与 settings 落库读回（bootstrap 装配）保留，行为回归默认开档位。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/settings/photo_burn_setting.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻既有测试口径）。
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

void main() {
  late db.AppDatabase? databaseRef;

  setUp(() async {
    databaseRef = await _tryOpenMemoryDatabase();
  });

  tearDown(() async {
    await databaseRef?.close();
  });

  group('settings 表存取（§5.6⑲ 本地键值、value 一律 JSON）', () {
    test('缺省开：无行/坏 JSON/非布尔 → true（即焚=合规缺省，§3.7/§11.2 任务 3）',
        () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      expect(await loadPhotoBurnAfterParse(database), isTrue,
          reason: '默认开=原图解析后即焚（§3.3/§5.6㉑ 合规缺省）');

      // 坏 JSON → 开（本地件自愈，§6.1）。
      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(
              key: kSettingPhotoBurnAfterParse,
              value: '{not-json',
            ),
          );
      expect(await loadPhotoBurnAfterParse(database), isTrue);

      // 非布尔 JSON（数字 1）→ 开（严格布尔语义）。
      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(
              key: kSettingPhotoBurnAfterParse,
              value: '1',
            ),
          );
      expect(await loadPhotoBurnAfterParse(database), isTrue);
    });

    test('写读回环：save(false) → load(false)，行值为 JSON false', () async {
      final database = databaseRef;
      if (database == null) return;

      await savePhotoBurnAfterParse(database, enabled: false);
      expect(await loadPhotoBurnAfterParse(database), isFalse,
          reason: '关=用户显式选择本机留档（§3.7）');

      final row = await (database.select(database.settings)
            ..where((s) => s.key.equals(kSettingPhotoBurnAfterParse)))
          .getSingle();
      expect(jsonDecode(row.value), isFalse, reason: 'settings.value 一律 JSON');

      await savePhotoBurnAfterParse(database, enabled: true);
      expect(await loadPhotoBurnAfterParse(database), isTrue);
    });
  });
}
