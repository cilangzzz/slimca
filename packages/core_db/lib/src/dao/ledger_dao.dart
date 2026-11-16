/// LedgerDao + 默认账本 seed（§5.4④ 账本、§3.4 单账本 MVP）。
///
/// seed 语义（§5.4/§3.4）：MVP 恒默认 money 账本（schema 先冻结、功能后
/// 启用）；kcal 账本系统内置一个、不可删除不可多开，币种=kcal——「金额分类
/// 与热量维度并存」（§11.1 W2、§5.4 kcal 账本行）。幂等：按 kind 查缺补插，
/// 已存在的行不动（允许用户后续改名/改图标）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'local_write_clock.dart';

/// 账本 DAO（§5.4④ ledgers）。
class LedgerDao {
  LedgerDao(this._db, {LocalWriteClock? clock})
      : _clock = clock ?? LocalWriteClock(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 默认数据 seed（空库首次打开由 [seedDefaultData] 调用）：
  /// - kind='money' 缺失 → 插入默认账本（CNY、期初余额 0）；
  /// - kind='kcal' 缺失 → 插入内置热量账本（currency='kcal'，§5.4）；
  /// - settings[kSettingDefaultLedgerId]（§5.6⑲ 默认账本）缺失 →
  ///   指向当前默认 money 账本（JSON 字符串值）。
  Future<void> seedDefaults() {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.ledgers)
            ..where((t) => t.deletedAt.isNull()))
          .get();
      final kinds = existing.map((l) => l.kind).toSet();

      if (!kinds.contains('money')) {
        await _insert(const _SeedLedger(
          name: '默认账本',
          icon: 'account_balance_wallet',
          currency: 'CNY',
          kind: 'money',
          sort: 0,
        ));
      }
      if (!kinds.contains('kcal')) {
        await _insert(const _SeedLedger(
          name: '热量账本',
          icon: 'local_fire_department',
          currency: 'kcal',
          kind: 'kcal',
          sort: 1,
        ));
      }

      final setting = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
          .getSingleOrNull();
      if (setting == null) {
        final moneyRows = await (_db.select(_db.ledgers)
              ..where((t) => t.kind.equals('money') & t.deletedAt.isNull()))
            .get();
        if (moneyRows.isNotEmpty) {
          await _db.into(_db.settings).insertOnConflictUpdate(
                SettingsCompanion.insert(
                  key: kSettingDefaultLedgerId,
                  value: jsonEncode(moneyRows.first.id),
                ),
              );
        }
      }
    });
  }

  Future<Ledger?> findById(String id) => (_db.select(_db.ledgers)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 默认 money 账本（未删未归档，按 sort 取第一条；MVP 恒存在，§3.4）。
  Future<Ledger?> defaultMoneyLedger() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) =>
              t.kind.equals('money') &
              t.deletedAt.isNull() &
              t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 内置 kcal 账本（§5.4：不可删除不可多开；seed 保证恰有一个）。
  Future<Ledger?> kcalLedger() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals('kcal') & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 全量账本（未删），按 sort/created_at 稳定排序。
  Future<List<Ledger>> getAll() {
    final query = _db.select(_db.ledgers)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.get();
  }

  /// 响应式账本列表（多账本 P1 的切换抽屉数据源，§3.4）。
  Stream<List<Ledger>> watchAll() {
    final query = _db.select(_db.ledgers)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch();
  }

  Future<void> _insert(_SeedLedger seed) async {
    final stamp = await _clock.next();
    await _db.into(_db.ledgers).insert(
          LedgersCompanion.insert(
            id: generateUuidV7(),
            name: seed.name,
            icon: seed.icon,
            currency: seed.currency,
            kind: seed.kind,
            sort: seed.sort,
            openingBalanceMinor: 0,
            isArchived: false,
            // 非空无默认列在 Companion.insert 中取裸值（Value 只用于
            // 可空/带默认列，§5.1 公共列均为非空无默认）。
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            hlc: stamp.hlc,
            revision: 1,
            deviceId: await _clock.deviceId(),
          ),
        );
  }
}

/// seed 行的静态描述（业务列；公共列由 [LocalWriteClock] 统一发戳）。
class _SeedLedger {
  const _SeedLedger({
    required this.name,
    required this.icon,
    required this.currency,
    required this.kind,
    required this.sort,
  });

  final String name;
  final String icon;
  final String currency;
  final String kind;
  final int sort;
}
