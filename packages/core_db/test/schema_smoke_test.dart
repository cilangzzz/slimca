/// schema v1 冒烟测试（W1 骨架，§5.1-§5.7）。
///
/// 流程：内存库建全部 21 张表 → 插一条 entry + 两条 entry_lines（facet
/// 拆行：calorie 行 + money 行，§5.2/§5.3）→ 查询断言。
///
/// 运行前提：集成阶段先执行 `dart run build_runner build -d` 生成
/// app_database.g.dart，再 `flutter pub get` 拉取 drift 依赖。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见：
/// 缺 sqlite3.dll，动态库加载失败）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

void main() {
  test('schema v1 冒烟：建 21 张表 → entry + entry_lines facet 拆行 → 查询断言', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      // 探针：真正触发 sqlite3 动态库加载。
      await db.customSelect('SELECT 1').getSingle();

      // ── 建表断言（§5.1：schema v1 共 21 张，schemaVersion=1）──
      final tableRows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'drift_%'",
      ).get();
      expect(tableRows.length, 21, reason: '§5.1：21 张表（14 同步+5 本地+2 服务端为主）');

      // ── 索引断言（§5.2 声明的 4+5 个二级索引）──
      final indexRows = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
      ).get();
      expect(indexRows.length, 9, reason: 'entries 4 个 + entry_lines 5 个（§5.2）');

      // ── 插入 entry（事件主干）──
      const entryId = '0196a7e0-7e1f-7000-8000-3f8a12c0b7d4';
      await db.into(db.entries).insert(const Entry(
            id: entryId,
            date: '2026-11-16',
            tzOffsetMin: 480,
            occurredAt: 1763251200000,
            kind: 'food',
            source: 'text',
            title: '一碗牛肉面',
            note: null,
            status: 'confirmed',
            aiParseId: null,
            createdAt: 1763251200000,
            updatedAt: 1763251200000,
            deletedAt: null,
            hlc: '0001763251200000:000001:3F8A12C0B7D4',
            revision: 1,
            schemaVer: 1,
            deviceId: '3F8A12C0B7D4',
          ));

      // ── 插入两条 entry_lines（facet 拆行，§5.3：各维度独立成行，
      //    多端并发改不同维度互不覆盖）──
      await db.into(db.entryLines).insert(const EntryLine(
            id: '0196a7e0-7e1f-7000-8000-00000000ca10',
            entryId: entryId,
            type: 'calorie',
            amount: 650, // kcal，一律 INTEGER（§5.1）
            direction: 'in',
            ledgerId: 'kcal-builtin',
            categoryId: null,
            currency: null,
            confidence: 0.82,
            payload: null,
            correctionOf: null,
            status: 'active',
            createdAt: 1763251200000,
            updatedAt: 1763251200000,
            deletedAt: null,
            hlc: '0001763251200000:000002:3F8A12C0B7D4',
            revision: 1,
            schemaVer: 1,
            deviceId: '3F8A12C0B7D4',
          ));
      await db.into(db.entryLines).insert(const EntryLine(
            id: '0196a7e0-7e1f-7000-8000-00000000c0de',
            entryId: entryId,
            type: 'money',
            amount: 1850, // 分（¥18.50），一律 INTEGER（§5.1）
            direction: 'out',
            ledgerId: 'ledger-default',
            categoryId: 'cat-food',
            currency: 'CNY',
            confidence: 0.9,
            payload: null,
            correctionOf: null,
            status: 'active',
            createdAt: 1763251200001,
            updatedAt: 1763251200001,
            deletedAt: null,
            hlc: '0001763251200001:000003:3F8A12C0B7D4',
            revision: 1,
            schemaVer: 1,
            deviceId: '3F8A12C0B7D4',
          ));

      // ── 查询断言 ──
      final fetched = await (db.select(db.entries)
            ..where((tbl) => tbl.id.equals(entryId)))
          .getSingle();
      expect(fetched.kind, 'food');
      expect(fetched.date, '2026-11-16');
      expect(fetched.tzOffsetMin, 480);
      expect(fetched.status, 'confirmed');
      expect(fetched.schemaVer, 1);
      expect(fetched.deletedAt, isNull, reason: '软删墓碑：未删为 NULL（§5.1）');

      final lines = await (db.select(db.entryLines)
            ..where((tbl) => tbl.entryId.equals(entryId)))
          .get();
      expect(lines.length, 2, reason: '同一 entry 拆出 calorie+money 两个 facet 行');

      final calorie = lines.singleWhere((l) => l.type == 'calorie');
      expect(calorie.amount, 650);
      expect(calorie.direction, 'in');
      expect(calorie.confidence, closeTo(0.82, 1e-9));

      final money = lines.singleWhere((l) => l.type == 'money');
      expect(money.amount, 1850);
      expect(money.direction, 'out');
      expect(money.currency, 'CNY');
      expect(money.ledgerId, 'ledger-default');

      // hlc 行级独立：两行 facet 各带自身 hlc/updated_at（§5.3 同步正确性）。
      expect(calorie.hlc, isNot(money.hlc));
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // 「集成阶段如缺 DLL 可 skip」：Windows 宿主可能缺 sqlite3 运行库
        // （sqlite3.dll）。缺库时这里温和跳过、不掩盖其余异常。
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，schema 冒烟未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
