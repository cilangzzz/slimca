/// SyncLocalStore — pull 落库侧的本地真值表读写（W5-6，§6.2 读路径）。
///
/// 职责（§6.2「远端行落库走与本地写同一校验」）：
/// - entries / entry_lines 走 core_db 的仓库实现（[DriftEntryRepository]/
///   [DriftEntryLineRepository]）：软删墓碑拒绝复活、金额行不可变守卫、
///   投影联动——与 UI 本地写完全同一条校验路径（§5.1/§3.4/§5.6）；
/// - 其余 12 张真值表走通用 SQL 落库（快照整行 upsert，未知列过滤=
///   「老客户端忽略新列」前向兼容，§6.4）；
/// - per-table pull 游标存取（§5.6⑱ sync_cursors，PK(device_id, table_name)）；
/// - day_summary 脏标记与自愈重算（§5.6⑬ 重建规则——pull 只写真值表，
///   投影由 dirty 自愈，§6.5 末行）；
/// - push ack 的权威 revision 回写业务行（§6.2 写路径末步「本地回写
///   revision」）。
library;

import 'package:core_db/core_db.dart';
import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/drift.dart';

import 'sync_table_catalog.dart';

/// 本地真值表读写（Drift 实现）。
class DriftSyncLocalStore {
  DriftSyncLocalStore(
    this._db, {
    required String deviceId,
    DaySummaryProjection? projection,
  })  : _deviceId = deviceId,
        _projection = projection ?? DaySummaryProjection(_db) {
    _entryRepo = DriftEntryRepository(_db, projection: _projection);
    _lineRepo = DriftEntryLineRepository(_db, projection: _projection);
  }

  final AppDatabase _db;
  final String _deviceId;
  final DaySummaryProjection _projection;
  late final DriftEntryRepository _entryRepo;
  late final DriftEntryLineRepository _lineRepo;

  /// SQL 表名 → 表信息（§5.1 表集；列名经 GeneratedColumn.$name，
  /// 与行快照 snake_case 键同构，§6.2）。
  late final Map<String, ResultSetImplementation<Table, DataClass>> _infos = {
    'entries': _db.entries,
    'entry_lines': _db.entryLines,
    'food_items': _db.foodItems,
    'ledgers': _db.ledgers,
    'categories': _db.categories,
    'budgets': _db.budgets,
    'todos': _db.todos,
    'fitness_sessions': _db.fitnessSessions,
    'fitness_plans': _db.fitnessPlans,
    'exercise_sets': _db.exerciseSets,
    'savings_goals': _db.savingsGoals,
    'savings_contributions': _db.savingsContributions,
    'corrections': _db.corrections,
    'theme_profiles': _db.themeProfiles,
  };

  ResultSetImplementation<Table, DataClass> _infoOf(String tableName) {
    final info = _infos[tableName];
    if (info == null) {
      throw ArgumentError.value(
        tableName,
        'tableName',
        '不是 §5.1 同步真值表（14 张冻结表之外无同步语义）',
      );
    }
    return info;
  }

  Set<String> _columnNames(String tableName) =>
      _infoOf(tableName).$columns.map((c) => c.$name).toSet();

  // ── 行读取 ────────────────────────────────────────────────────────────

  /// 读本地行原始快照（snake_case 平铺，含墓碑行）；无则 null。
  ///
  /// 返回与 §5.6⑯ payload 同构的 Map，供引擎做 LWW/墓碑/类策略仲裁（§6.5）。
  Future<Map<String, Object?>?> getRawRow(String tableName, String rowId) async {
    final info = _infoOf(tableName);
    final rows = await _db
        .customSelect(
          'SELECT * FROM "${info.entityName}" WHERE id = ?',
          variables: [Variable.withString(rowId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// 经 entry_id 解析归属日（§5.1 一切聚合按 entries.date 归日）。
  Future<String?> entryDateOf(String entryId) async {
    final rows = await _db
        .customSelect(
          'SELECT date FROM "entries" WHERE id = ?',
          variables: [Variable.withString(entryId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data['date'] as String?;
  }

  // ── entries / entry_lines：与本地写同一校验路径 ────────────────────────

  /// 落库远端 entries 行（经 [DriftEntryRepository]——墓碑拒绝复活由仓库
  /// 强制，§6.5 删除行；投影同事务联动重算，§5.6）。
  ///
  /// 快照键不全（部分墓碑等病态载荷）抛 [ArgumentError]，由引擎降级走
  /// [applyGenericRow] 或记为坏载荷。
  Future<void> applyEntry(Map<String, Object?> payload) {
    final entry = domain.Entry.fromJson(payload);
    return _entryRepo.upsert(entry);
  }

  /// 落库远端 entry_lines 行（经 [DriftEntryLineRepository]——金额行不可变
  /// 守卫由仓库强制，违反抛 [domain.MoneyLineImmutableException]，§3.4/§6.5）。
  Future<void> applyLine(Map<String, Object?> payload) {
    final line = domain.EntryLine.fromJson(payload);
    return _lineRepo.upsert(line);
  }

  // ── 通用落库（其余 12 张真值表）───────────────────────────────────────

  /// 通用整行 upsert（INSERT … ON CONFLICT(id) DO UPDATE）。
  ///
  /// - 只更新载荷出现的列：部分快照（如墓碑元数据回写）不覆盖既有业务列；
  /// - 未知列过滤（§6.4「老客户端忽略新列」）；
  /// - bool 列以 0/1 绑定（schema 里 bool 存 INTEGER，§5.1）。
  /// 返回受影响的本地日历日（day_summary 脏标记用，§5.6⑬）。
  Future<Set<String>> applyGenericRow(
    SyncTableSpec spec,
    Map<String, Object?> payload,
  ) async {
    final info = _infoOf(spec.name);
    final known = _columnNames(spec.name);
    final cols = payload.keys.where(known.contains).toList()
      ..sort(); // 列序固定，SQL 生成确定性
    if (!cols.contains('id')) {
      throw ArgumentError('行快照缺少主键 id（§5.1）：${spec.name}');
    }
    final vars = <Variable>[];
    final placeholders = <String>[];
    for (final col in cols) {
      vars.add(Variable(_sqlValue(payload[col])));
      placeholders.add('?');
    }
    final setPart = cols
        .where((c) => c != 'id')
        .map((c) => '"$c" = excluded."$c"')
        .join(', ');
    final sql = 'INSERT INTO "${info.entityName}" '
        '(${cols.map((c) => '"$c"').join(', ')}) '
        'VALUES (${placeholders.join(', ')}) '
        'ON CONFLICT("id") DO UPDATE SET $setPart';
    await _db.customInsert(sql, variables: vars, updates: {info});

    // 受影响日期（§5.6 重建规则）：自带 date 列，或经 entry_id 解析。
    final dates = <String>{};
    final ownDate = spec.ownDateKey != null ? payload[spec.ownDateKey] : null;
    if (ownDate is String) {
      dates.add(ownDate);
    } else if (spec.parentKey == 'entry_id' &&
        payload['entry_id'] is String) {
      final date = await entryDateOf(payload['entry_id'] as String);
      if (date != null) {
        dates.add(date);
      }
    }
    if (spec.marksAllDatesDirty) {
      await markAllSummaryDatesDirty();
    }
    return dates;
  }

  /// JSON 值 → SQL 绑定值（bool→INTEGER，§5.1「bool 存 INTEGER」）。
  Object? _sqlValue(Object? v) => v is bool ? (v ? 1 : 0) : v;

  // ── 游标（§5.6⑱ sync_cursors）─────────────────────────────────────────

  /// 读本设备全部 per-table 游标（§6.2 since_hlc）。
  Future<Map<String, String>> readCursors() async {
    final rows = await (_db.select(_db.syncCursors)
          ..where((t) => t.deviceId.equals(_deviceId)))
        .get();
    return {for (final row in rows) row.targetTable: row.pullHlc};
  }

  /// 写回某表游标（整批落库成功后才推进，§6.2/§5.6⑰）。
  Future<void> writeCursor(String tableName, String pullHlc) {
    return _db.into(_db.syncCursors).insertOnConflictUpdate(
          SyncCursorsCompanion.insert(
            deviceId: _deviceId,
            targetTable: tableName,
            pullHlc: pullHlc,
          ),
        );
  }

  // ── push ack 回写（§6.2 写路径末步）──────────────────────────────────

  /// 服务端权威 revision 回写业务行（§5.1 revision「同步升级为服务端版本」）。
  Future<void> writeRevision(
    String tableName,
    String rowId,
    int revision,
  ) async {
    final info = _infoOf(tableName);
    await _db.customUpdate(
      'UPDATE "${info.entityName}" SET revision = ? WHERE id = ?',
      variables: [Variable.withInt(revision), Variable.withString(rowId)],
      updates: {info},
      updateKind: UpdateKind.update,
    );
  }

  // ── 投影自愈（§5.6⑬）─────────────────────────────────────────────────

  /// 标记指定日 dirty（§5.6 重建规则第一步；pull 只写真值表，投影由
  /// dirty 自愈重算，§6.5 末行「day_summary 不同步」）。
  Future<void> markDatesDirty(Iterable<String> dates) async {
    for (final date in dates) {
      await _projection.markDayDirty(date);
    }
  }

  /// 维度行（账本/分类/预算）变更影响全部已有投影日的 budget_snapshot
  /// （§5.6⑬）——全部标 dirty。
  Future<void> markAllSummaryDatesDirty() async {
    final rows =
        await _db.customSelect('SELECT date FROM "day_summaries"').get();
    for (final row in rows) {
      await _projection.markDayDirty(row.data['date'] as String);
    }
  }

  /// 自愈重算：只重算 dirty=1 的日期（§5.6「标记当日 dirty → 后台重算」）。
  Future<void> recomputeDirty() => _projection.recomputeDirtyDays();
}
