/// W11-12 拍照原图「解析后即焚」开关测试（§3.7 数据主权、§3.3「原图解析后
/// 即焚不落存储」、§5.6㉑、§11.2 任务 3「settings 页加开关，默认开」）。
///
/// 覆盖：
/// - settings 表存取：缺省开（即焚=合规缺省）→ 写读回环 → 坏 JSON/非布尔
///   回落开（本地件自愈、损坏永不放宽，§6.1）；
/// - SettingsPage 开关（widget 测试，内存库/禁真实网络）：默认开渲染 →
///   toggle 写回 PhotoBurnPolicy 运行期持有 + settings 表落库 → 回开。
library;

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

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/features/settings/settings_page.dart';
import 'package:slimca/main.dart';
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

  group('SettingsPage 拍照原图即焚开关（widget 测试，内存库）', () {
    testWidgets('默认开渲染 → 关（运行期持有翻转 + settings 落库）→ 回开',
        (WidgetTester tester) async {
      final database = databaseRef;
      if (database == null) return; // Windows 宿主缺 sqlite3.dll：跳过。

      const deviceId = 'ABCDEF123456';
      final clock = HlcClock(deviceId: deviceId);
      await ensureDefaultLedgers(database, clock);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            hlcClockProvider.overrideWithValue(clock),
            captureGatewayProvider.overrideWithValue(
              createCaptureGateway(db: database, clock: clock),
            ),
            captureParserProvider.overrideWithValue(createCaptureParser()),
          ],
          child: const SlimcaApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      // ── 我的 Tab → 拍照即焚开关行（§11.2 任务 3「设置项可达」）──────────
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('拍照原图解析后即焚'), findsOneWidget);
      final switchFinder = find.byKey(settingsPhotoBurnSwitchKey);
      expect(switchFinder, findsOneWidget);
      expect(
        tester.widget<Switch>(switchFinder).value,
        isTrue,
        reason: '默认开=解析后即焚（§3.3/§11.2 任务 3）',
      );

      // ── 关 → 运行期持有翻转 + settings 表落库（§5.6⑲ value 一律 JSON）──
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(switchFinder).value, isFalse);
      final row = await database
          .customSelect(
            "SELECT value FROM settings WHERE key = 'photo_burn_after_parse'",
          )
          .getSingle();
      expect(jsonDecode(row.data['value']! as String), isFalse);

      // ── 回开默认档（数据主权：随时可撤回，§3.7）──────────────────────
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(switchFinder).value, isTrue);
      final row2 = await database
          .customSelect(
            "SELECT value FROM settings WHERE key = 'photo_burn_after_parse'",
          )
          .getSingle();
      expect(jsonDecode(row2.data['value']! as String), isTrue);
    });
  });
}
