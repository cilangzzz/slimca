/// 账本管理仓库（§5.4④ ledgers 生命周期、§3.4 多账本 P1、§11.2 W15 主线）。
///
/// 职责：账本切换抽屉/管理页的读取（可用+归档+默认徽标）与写路径转接
/// （建账本/重命名/归档软删/切换默认）——写路径全部委托 core_db
/// [cdb.LedgerDao]（复用既有抽象，§10.3/§10.4），出网入队与 kcal 账本
/// 保护（不可删不可多开）由 DAO 层强制，本仓库不重复实现。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/drift.dart' as drift;

import 'ledger_models.dart';

/// 账本管理仓库接口（§10.4 分层纪律：页面依赖抽象）。
abstract interface class LedgerManageRepository {
  /// 可用账本（未删未归档，sort 升序）+ 默认徽标（§3.4 切换抽屉数据源）。
  /// settings 默认指针与 ledgers 同查询（单流响应式），徽标天然跟随切换。
  Stream<List<LedgerSwitchOption>> watchSwitchOptions();

  /// 已归档账本（恢复入口数据源；归档=产品态软移除，历史账单保留）。
  Stream<List<LedgerSwitchOption>> watchArchivedOptions();

  /// 新建 money 账本（§5.4④；kcal 不可多开由 DAO 强制），返回新 id。
  Future<String> createLedger({
    required String name,
    String? icon,
    String? currency,
  });

  /// 重命名账本（kcal 允许改名，DAO 契约）。
  Future<void> renameLedger(String id, {required String name});

  /// 归档/恢复账本（kcal 拒绝归档由 DAO 强制；幂等）。
  Future<void> setArchived(String id, {required bool archived});

  /// 切换默认账本（仅 money 账本，§5.6⑲ settings 指针；DAO 强制校验）。
  Future<void> setDefault(String id);
}

/// Drift 实现（写路径委托 cdb.LedgerDao；读路径单 SQL 联表 settings——
/// 默认徽标随指针切换响应式更新）。
class DriftLedgerManageRepository implements LedgerManageRepository {
  DriftLedgerManageRepository(this._db) : _dao = cdb.LedgerDao(_db);

  final cdb.AppDatabase _db;
  final cdb.LedgerDao _dao;

  /// 可用账本 + 默认徽标：单条 customSelect 联查 settings（§5.6⑲）——
  /// settings.value 为 JSON 字符串值（如 `"abc"`），Dart 侧解析比对；
  /// readsFrom 显式声明 ledgers+settings（customSelect watch 不自动推断）。
  @override
  Stream<List<LedgerSwitchOption>> watchSwitchOptions() {
    return _watchRows(archivedOnly: false);
  }

  @override
  Stream<List<LedgerSwitchOption>> watchArchivedOptions() {
    return _watchRows(archivedOnly: true);
  }

  Stream<List<LedgerSwitchOption>> _watchRows({required bool archivedOnly}) {
    final String archivedFilter =
        archivedOnly ? 'l.is_archived = 1' : 'l.is_archived = 0';
    final String sql = <String>[
      'SELECT l.id AS id, l.name AS name, l.icon AS icon,',
      "  l.currency AS currency, l.kind AS kind,",
      "  (SELECT s.value FROM settings s WHERE s.key = '${cdb.kSettingDefaultLedgerId}')"
          ' AS default_raw',
      'FROM ledgers l',
      'WHERE l.deleted_at IS NULL AND $archivedFilter',
      'ORDER BY l.sort ASC, l.created_at ASC',
    ].join(' ');
    return _db
        .customSelect(
          sql,
          readsFrom: <drift.ResultSetImplementation<drift.Table, drift.DataClass>>{
            _db.ledgers,
            _db.settings,
          },
        )
        .watch()
        .map((List<drift.QueryRow> rows) {
      // settings 默认指针的 JSON 字符串值（§5.6⑲）：value 为 JSON 文本
      // （如 `"abc"` 带引号），解码后比对 id；坏值防御性视为未设默认。
      // 注：drift QueryRow 类型化读取——无类型 Object 读会抛「Could not
      // find a matching SQL type」，settings.value 列恒 TEXT，按 String 读。
      String? defaultId;
      if (rows.isNotEmpty) {
        final String? raw = rows.first.readNullable<String>('default_raw');
        if (raw != null && raw.isNotEmpty) {
          try {
            final Object? decoded = jsonDecode(raw);
            if (decoded is String) {
              defaultId = decoded;
            }
          } on FormatException {
            defaultId = null;
          }
        }
      }
      return <LedgerSwitchOption>[
        for (final drift.QueryRow row in rows)
          LedgerSwitchOption(
            id: row.read<String>('id'),
            name: row.read<String>('name'),
            icon: row.read<String>('icon'),
            currency: row.read<String>('currency'),
            kind: row.read<String>('kind'),
            isDefault: defaultId == row.read<String>('id'),
          ),
      ];
    });
  }

  @override
  Future<String> createLedger({
    required String name,
    String? icon,
    String? currency,
  }) {
    return _dao.createLedger(name: name, icon: icon, currency: currency)
        .then((cdb.Ledger row) => row.id);
  }

  @override
  Future<void> renameLedger(String id, {required String name}) {
    return _dao.renameLedger(id, name: name);
  }

  @override
  Future<void> setArchived(String id, {required bool archived}) {
    return _dao.setLedgerArchived(id, archived: archived);
  }

  @override
  Future<void> setDefault(String id) {
    return _dao.setDefaultLedger(id);
  }
}
