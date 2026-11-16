/// sync_outbox 入队器（§5.6⑯ 出网队列「一切出网必经之路」、§6.2 写路径纪律）。
///
/// §6.2「UI → Drift 事务提交（业务行 + sync_outbox 同事务写入，同步返回）」
/// 的统一落点（W5-6 集成披露的补课项，W7-8 双设备一致率的写路径基础）：
/// 真值表行写入后，**在同一事务内**由 [enqueueRow] 读回该行最终状态（含
/// §5.1 公共列与墓碑位）整行作为 payload 入队——
/// - payload 与落库行同源（读回而非调用方构造）：supersede 修正链、墓碑
///   保留、confirmed→edited 联动等多步写路径天然拿到权威终态，「行快照
///   回放一致性」不依赖调用方自律；
/// - 事务一致性（无半途 outbox）：业务写失败回滚时 outbox 行随之回滚；
///   读回不到目标行即抛错让整个事务回滚，绝不出现「业务行在、出网行指空」；
/// - 入队去重（§6.2 幂等纪律的本地半边）：同 (table_name, row_id) 的未
///   ack 出网行折叠为一条——同一事务重复入队防护；跨事务仍 pending 的旧行
///   同样收敛到最新快照（服务端只关心最终态，中间态从未被任何对端观察到，
///   折叠不丢事实）。已 ack 的历史出网行不动。
///
/// 使用边界（§6.2 读路径）：[enqueueRow] 只服务本地写路径；pull 落库侧
/// （feature_sync `DriftSyncLocalStore`）不得调用——远端行已是服务端真值，
/// 再入队会造成回声循环。entries/entry_lines 的 pull 半边复用同一仓库实现，
/// 因此 outbox 入队必须留在网关/DAO 层而非仓库层（装配纪律）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';

/// §5.1 同步真值表（14 张冻结表集）的出网入队器。
///
/// 无状态（除 [AppDatabase] 引用）：可由各 DAO/网关各自持有，入队语义
/// 完全一致。op/幂等键/时间戳均由本类派生，调用方只给表名与行 id。
class SyncOutboxWriter {
  SyncOutboxWriter(this._db);

  final AppDatabase _db;

  /// 表名 → Drift 表信息（§5.1 14 张真值表冻结集）。
  ///
  /// SQL 表名经 `entityName` 取自 schema 单侧定义（与 feature_sync 的
  /// `DriftSyncLocalStore` 同一取法），杜绝手写表名漂移（§6.2）。
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
        '不是 §5.1 同步真值表（14 张冻结表之外无出网语义）',
      );
    }
    return info;
  }

  /// 行快照读回入队（§6.2 写路径第一步）。
  ///
  /// 必须在业务写事务内、业务行写后调用：读回 [rowId] 行最终状态整行入队。
  /// - op 自动判定（§5.6⑯/§6.5）：快照携带墓碑（deleted_at 非空）→
  ///   `delete`，存活行 → `upsert`。「upsert 命中已删行拒绝复活」路径
  ///   （§6.5 删除行）的落库终态仍是墓碑，经此天然以 delete 语义出网，
  ///   快照与服务端仲裁语义一致；
  /// - 幂等键 id 由本地生成 UUIDv7（§5.1），服务端据此去重；
  /// - hlc/base_revision/created_at 取自行快照的 §5.1 公共列（与
  ///   feature_capture 网关既有入队约定同口径）。
  Future<void> enqueueRow(String tableName, String rowId) async {
    final info = _infoOf(tableName);
    final rows = await _db
        .customSelect(
          'SELECT * FROM "${info.entityName}" WHERE id = ?',
          variables: [Variable.withString(rowId)],
        )
        .get();
    if (rows.isEmpty) {
      // 读回不到目标行：调用顺序错误（不在写事务内/写前入队）。抛错让
      // 调用方事务整体回滚——宁可不发，不发指空的出网行（§6.2）。
      throw StateError(
        'enqueueRow: $tableName 无此行 $rowId——入队必须在业务写事务内、'
        '业务行写后调用（§6.2 同事务纪律）',
      );
    }
    final snapshot = rows.first.data;
    final hlc = snapshot['hlc'];
    final revision = snapshot['revision'];
    final updatedAt = snapshot['updated_at'];
    if (hlc is! String || revision is! int || updatedAt is! int) {
      // §5.1 公共列非空是 schema 冻结约束；坏数据不入出网（fail fast）。
      throw StateError(
        'enqueueRow: $tableName/$rowId 行快照缺 §5.1 公共列'
        '（hlc/revision/updated_at），拒绝入队',
      );
    }
    final op = snapshot['deleted_at'] != null
        ? dom.OutboxOp.delete
        : dom.OutboxOp.upsert;
    await _enqueue(
      tableName: tableName,
      rowId: rowId,
      op: op,
      payload: snapshot,
      hlc: hlc,
      baseRevision: revision,
      createdAt: updatedAt,
    );
  }

  /// 折叠或插入（§6.2 入队去重：同一事务重复入队防护）。
  Future<void> _enqueue({
    required String tableName,
    required String rowId,
    required dom.OutboxOp op,
    required Map<String, Object?> payload,
    required String hlc,
    required int baseRevision,
    required int createdAt,
  }) async {
    final pending = await _db
        .customSelect(
          'SELECT id FROM "sync_outbox" '
          'WHERE acked_at IS NULL AND table_name = ? AND row_id = ? LIMIT 1',
          variables: [
            Variable.withString(tableName),
            Variable.withString(rowId),
          ],
        )
        .get();
    if (pending.isNotEmpty) {
      // 已有未 ack 的出网行：改写为最新快照（同事务重复入去重；跨事务
      // pending 旧行同样收敛，服务端只见最终态，§6.2）。
      final pendingId = pending.first.data['id'] as String;
      await _db.customUpdate(
        'UPDATE "sync_outbox" '
        'SET op = ?, payload = ?, base_revision = ?, hlc = ?, created_at = ? '
        'WHERE id = ?',
        variables: [
          Variable.withString(op.wire),
          Variable.withString(jsonEncode(payload)),
          Variable.withInt(baseRevision),
          Variable.withString(hlc),
          Variable.withInt(createdAt),
          Variable.withString(pendingId),
        ],
        updates: {_db.syncOutbox},
      );
      return;
    }
    await _db.into(_db.syncOutbox).insert(
          SyncOutboxCompanion.insert(
            id: generateUuidV7(),
            targetTable: tableName,
            rowId: rowId,
            op: op.wire,
            payload: jsonEncode(payload),
            baseRevision: Value(baseRevision),
            hlc: hlc,
            createdAt: createdAt,
          ),
        );
  }
}
