/// TodoDao — 待办基础 CRUD（§5.5⑩ todos、§3.6 待办基础 P0）。
///
/// done_at 合并规则（§6.5 todo.done 行「完成事件只前进」）：并发 set vs
/// unset → set 胜（勾选永不丢失）。本地单写者语义下：set 置当前时刻（已有
/// 完成时刻则不覆盖，保留首次完成值）；unset 置 NULL——「取消完成仅无并发
/// 时生效」，跨设备并发合并由同步层按 done_at 非空者胜仲裁（W5-6 接入）。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/plan_tables.dart' show Todos;
import '../uuid_v7.dart';
import 'day_summary_projection.dart';
import 'local_write_clock.dart';

/// 待办 DAO（§5.5⑩ todos）。
class TodoDao {
  TodoDao(this._db, {LocalWriteClock? clock, this.projection})
      : _clock = clock ?? LocalWriteClock(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 非空时：待办变更后立即重算所属日期投影（todo_done/todo_total），
  /// 支撑 W2 验收「仪表盘待办卡即时更新」（§11.1 W2、§5.6 重建规则）。
  final DaySummaryProjection? projection;

  /// 新建待办（§5.5⑩）：[date] NULL=无日期收集箱；id 由本地生成 UUIDv7
  /// （§5.1 主键约定）。
  Future<Todo> create({
    required String title,
    String? note,
    String? date,
    int? dueAt,
    String? goalLink,
  }) async {
    final stamp = await _clock.next();
    final id = generateUuidV7();
    await _db.into(_db.todos).insert(
          TodosCompanion.insert(
            id: id,
            title: title,
            note: Value(note),
            date: Value(date),
            doneAt: const Value(null),
            dueAt: Value(dueAt),
            goalLink: Value(goalLink),
            // 非空无默认列在 Companion.insert 中取裸值（Value 只用于
            // 可空/带默认列，§5.1 公共列均为非空无默认）。
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            hlc: stamp.hlc,
            revision: 1,
            deviceId: await _clock.deviceId(),
          ),
        );
    await _recomputeDay(date);
    return (await findById(id))!;
  }

  /// 勾选/取消完成（§5.5⑩ done_at 列、§6.5 只前进合并）。
  ///
  /// 只前进：已完成的待办重复勾选不覆盖原完成时刻；未勾选状态重复取消为
  /// no-op。变更在同事务内完成后联动重算投影。
  Future<void> setDone(String id, {required bool done}) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.todos)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('setDone: todos 无此行 $id（§5.5⑩）');
      }
      if (done && row.doneAt != null) {
        return; // 只前进：保留首次完成时刻（§6.5 set 胜）
      }
      if (!done && row.doneAt == null) {
        return; // 未完成重复取消：no-op
      }
      final stamp = await _clock.next();
      await (_db.update(_db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          doneAt: Value(done ? stamp.updatedAtMs : null),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      await _recomputeDay(row.date);
    });
  }

  /// 更新基础字段（标题/备注/计划日/截止/目标联动）。
  ///
  /// 传 [_unchanged] 哨兵表示「不改动」；显式传 null 表示置空。计划日变更
  /// 时新旧两日的投影都要重算（§5.6 重建规则）。
  Future<void> updateDetails({
    required String id,
    Object? title = _unchanged,
    Object? note = _unchanged,
    Object? date = _unchanged,
    Object? dueAt = _unchanged,
    Object? goalLink = _unchanged,
  }) {
    return _db.transaction(() async {
      final row = await (_db.select(_db.todos)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('updateDetails: todos 无此行 $id（§5.5⑩）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          title: title == _unchanged ? const Value.absent() : Value(title as String),
          note: note == _unchanged
              ? const Value.absent()
              : Value(note as String?),
          date: date == _unchanged
              ? const Value.absent()
              : Value(date as String?),
          dueAt: dueAt == _unchanged
              ? const Value.absent()
              : Value(dueAt as int?),
          goalLink: goalLink == _unchanged
              ? const Value.absent()
              : Value(goalLink as String?),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      final newDate = date == _unchanged ? row.date : date as String?;
      final affected = <String?>{row.date, newDate}..remove(null);
      for (final day in affected) {
        await _recomputeDay(day);
      }
    });
  }

  /// 软删墓碑（§5.1 删除行；§6.5 墓碑拒绝复活——由 upsert 侧保证，待办
  /// 本身只提供墓碑写入）。
  Future<void> softDelete(String id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.todos)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('softDelete: todos 无此行 $id（§5.1 删除行）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          deletedAt: Value(row.deletedAt ?? stamp.updatedAtMs),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      await _recomputeDay(row.date);
    });
  }

  Future<Todo?> findById(String id) => (_db.select(_db.todos)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 某日待办（未删；未完成在前，其余按创建序）——仪表盘待办 3 条预览
  /// （§3.2 卡片墙）数据源。
  Stream<List<Todo>> watchByDate(String date) {
    final query = _selectVisible()
      ..where((t) => t.date.equals(date))
      ..orderBy([
        (t) => OrderingTerm.desc(const CustomExpression<bool>('done_at IS NULL')),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    return query.watch();
  }

  /// 无日期收集箱（§5.5⑩：date NULL=收集箱）；排除墓碑。
  Stream<List<Todo>> watchInbox() {
    final query = _selectVisible()
      ..where((t) => t.date.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(const CustomExpression<bool>('done_at IS NULL')),
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(t.hlc),
      ]);
    return query.watch();
  }

  SimpleSelectStatement<Todos, Todo> _selectVisible() {
    return _db.select(_db.todos)
      ..where((t) => t.deletedAt.isNull());
  }

  Future<void> _recomputeDay(String? date) async {
    final target = projection;
    if (target == null || date == null) {
      return; // 收集箱（date=NULL）不进任何日投影（§5.5⑩）
    }
    await target.markDayDirty(date);
    await target.recomputeDaySummary(date);
  }

  /// updateDetails 的「不改动」哨兵。
  static const Object _unchanged = Object();
}
