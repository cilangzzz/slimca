/// TodoDao — 待办基础 CRUD（§5.5⑩ todos、§3.6 待办基础 P0）。
///
/// done_at 合并规则（§6.5 todo.done 行「完成事件只前进」）：并发 set vs
/// unset → set 胜（勾选永不丢失）。本地单写者语义下：set 置当前时刻（已有
/// 完成时刻则不覆盖，保留首次完成值）；unset 置 NULL——「取消完成仅无并发
/// 时生效」，跨设备并发合并由同步层按 done_at 非空者胜仲裁（W5-6 接入）。
///
/// 出网纪律（§6.2 写路径，W5-6 补课）：todos 为 §5.1 同步真值表，四个写
/// 路径（create/setDone/updateDetails/softDelete）的业务行与行快照入队
/// sync_outbox 同事务提交；no-op 分支（重复勾选/重复取消）不产生任何写、
/// 也不入队。pull 半边走 feature_sync 通用整行落库、不经本 DAO，无回声。
///
/// W13 扩展（§11.2 W13 主线「待办完整版（RRULE+提醒）」）：create/
/// updateDetails 增补重复规则三字段（repeat_rule=RRULE RFC5545、
/// rrule_anchor_date=展开锚点日 DTSTART——后者为 v1 内补列，见
/// [backfillTodoRruleAnchorColumn]、remind_at=提醒时刻）；RRULE 实例展开
/// 与提醒调度在 feature 层，数据层只存列与出网。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/plan_tables.dart' show Todos;
import '../uuid_v7.dart';
import 'day_summary_projection.dart';
import 'local_write_clock.dart';
import 'sync_outbox_writer.dart';

/// 待办 DAO（§5.5⑩ todos）。
class TodoDao {
  TodoDao(this._db, {LocalWriteClock? clock, this.projection})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：业务行同事务读回快照入队。
  final SyncOutboxWriter _outbox;

  /// 非空时：待办变更后立即重算所属日期投影（todo_done/todo_total），
  /// 支撑 W2 验收「仪表盘待办卡即时更新」（§11.1 W2、§5.6 重建规则）。
  final DaySummaryProjection? projection;

  /// 新建待办（§5.5⑩）：[date] NULL=无日期收集箱；id 由本地生成 UUIDv7
  /// （§5.1 主键约定）。业务行与 outbox 行快照同事务（§6.2）。
  ///
  /// W13 重复/提醒字段（§11.2 W13 主线、§5.5⑩）：
  /// - [repeatRule] 为 RRULE（RFC5545）文本，实例日期=RRULE 自锚点日展开；
  /// - [rruleAnchorDate] 为展开锚点日（DTSTART，v1 内补列）：缺省取 [date]
  ///   ——重复待办自计划日起展开；收集箱（date=NULL）重复待办需显式传锚点，
  ///   否则无展开起点（anchor 落 NULL）；
  /// - [remindAt] 为提醒时刻 UTC ms（通知调度由上层负责，数据层只存列）。
  Future<Todo> create({
    required String title,
    String? note,
    String? date,
    int? dueAt,
    String? goalLink,
    String? repeatRule,
    int? remindAt,
    String? rruleAnchorDate,
  }) async {
    final stamp = await _clock.next();
    final id = generateUuidV7();
    // 锚点缺省口径：有 RRULE 且未显式给锚点 → 锚点=计划日（DTSTART 语义）。
    final effectiveAnchor =
        rruleAnchorDate ?? (repeatRule != null ? date : null);
    await _db.transaction(() async {
      await _db.into(_db.todos).insert(
            TodosCompanion.insert(
              id: id,
              title: title,
              note: Value(note),
              date: Value(date),
              doneAt: const Value(null),
              dueAt: Value(dueAt),
              repeatRule: Value(repeatRule),
              remindAt: Value(remindAt),
              rruleAnchorDate: Value(effectiveAnchor),
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
      // §6.2 写路径纪律：todos 行快照同事务入队 sync_outbox（§5.6⑯）。
      await _outbox.enqueueRow('todos', id);
    });
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
      // §6.2：勾选/取消均为真值行写入，行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('todos', id);
      await _recomputeDay(row.date);
    });
  }

  /// 更新基础字段（标题/备注/计划日/截止/目标联动/重复规则/提醒）。
  ///
  /// 传 [_unchanged] 哨兵表示「不改动」；显式传 null 表示置空。计划日变更
  /// 时新旧两日的投影都要重算（§5.6 重建规则）。
  ///
  /// W13 重复字段语义（§5.5⑩）：[repeatRule]/[rruleAnchorDate]/[remindAt]
  /// 各自独立、互不联动——清空 repeat_rule 不隐式清锚点（锚点是否随 series
  /// 语义调整由上层决定）；改计划日不隐式平移锚点（实例展开口径由上层按
  /// RFC5545 处理）。
  Future<void> updateDetails({
    required String id,
    Object? title = _unchanged,
    Object? note = _unchanged,
    Object? date = _unchanged,
    Object? dueAt = _unchanged,
    Object? goalLink = _unchanged,
    Object? repeatRule = _unchanged,
    Object? remindAt = _unchanged,
    Object? rruleAnchorDate = _unchanged,
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
          repeatRule: repeatRule == _unchanged
              ? const Value.absent()
              : Value(repeatRule as String?),
          remindAt: remindAt == _unchanged
              ? const Value.absent()
              : Value(remindAt as int?),
          rruleAnchorDate: rruleAnchorDate == _unchanged
              ? const Value.absent()
              : Value(rruleAnchorDate as String?),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2：主干字段变更同为真值行写入，行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('todos', id);
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
      // §6.2：墓碑写入同事务入队；读回快照携带 deleted_at → 自动以
      // delete 语义出网（§5.6⑯/§6.5 墓碑拒绝复活）。
      await _outbox.enqueueRow('todos', id);
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

/// v1 内补列幂等回填（§6.4「行级 schema_ver 只加列前向兼容」的落点；W13）。
///
/// todos.rrule_anchor_date（RRULE 展开锚点日，DTSTART 语义）为 schema v1
/// 冻结后的只加列变更：**schemaVersion 保持 1**，旧 v1 库文件不触发
/// onUpgrade——在 beforeOpen 按 `PRAGMA table_info` 探测缺列并
/// `ALTER TABLE ADD COLUMN rrule_anchor_date TEXT NULL` 补齐（可空加列无
/// 默认值问题，与 backfillAttachmentBurnColumns 的 burned_at 同口径）。
/// rrule 本体（repeat_rule）§5.5⑩ 冻结清单已有列，无需补列。
///
/// 新库（onCreate createAll）已含本列 → 本函数幂等 no-op。取舍说明：V1 未
/// 发布（§11.2 W16 才商店发布）、冻结期禁破坏性迁移（§6.4），故选择
/// 「v1 内补列+幂等回填」——无版本号变化、无破坏性、对存量开发库文件自愈。
Future<void> backfillTodoRruleAnchorColumn(AppDatabase db) async {
  final info = await db.customSelect('PRAGMA table_info(todos)').get();
  if (info.isEmpty) {
    return; // 表不存在（onCreate 前的异常时序）：交给建表流程
  }
  final columns = info.map((row) => row.data['name'] as String).toSet();
  if (columns.contains('rrule_anchor_date')) {
    return; // 新库已含本列：幂等 no-op
  }
  await db.customStatement(
    'ALTER TABLE todos ADD COLUMN rrule_anchor_date TEXT NULL',
  );
}
