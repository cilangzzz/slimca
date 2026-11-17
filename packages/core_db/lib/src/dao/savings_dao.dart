/// SavingsGoalsDao / SavingsContributionsDao — 存钱目标与存钱贡献
/// （§5.5⑪⑫、§3.6 存钱目标 P1、§11.2 W13 主线「存钱目标（留存钩子）」）。
///
/// 读写纪律（与 TodoDao 同口径，§6.2 写路径）：
/// - 两表均为 §5.1 同步真值表，所有本地写路径的业务行与行快照**同事务**入队
///   sync_outbox（SyncOutboxWriter.enqueueRow 读回快照，§5.6⑯）；
/// - 投影联动（§5.6⑬/W13 实装）：目标写路径与贡献追加在**同一事务内**重算/
///   标记 day_summary.savings_progress 快照——进度卡与其余卡片同走快照直出、
///   零业务查询（§3.2）；
/// - 贡献 append-only（§6.1 原则 2「能只增不改的绝不改行」）：本 DAO 刻意不
///   提供贡献的修改/删除方法——远端墓碑仅经同步 pull 落库，一切求和口径
///   一律排除墓碑行。
///
/// 幂等口径（任务定义）：贡献追加按 **(goal_id, date, source)** 去重——
/// 人工投币与待办联动（§3.6「待办完成可选生成存钱贡献」）来源不同、各占
/// 一行互不挤占；同目标同日同来源重复追加为 no-op（返回既有行）。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'day_summary_projection.dart';
import 'local_write_clock.dart';
import 'sync_outbox_writer.dart';

/// §5.5⑪ savings_goals.method 枚举：365 存钱法。
const String kSavingsMethodDaily365 = 'daily365';

/// §5.5⑪ savings_goals.method 枚举：52 周存钱法。
const String kSavingsMethodWeek52 = 'week52';

/// §5.5⑪ savings_goals.method 枚举：自定义目标。
const String kSavingsMethodCustom = 'custom';

/// §5.5⑪ savings_goals.status 枚举：打卡中。
const String kSavingsGoalStatusActive = 'active';

/// §5.5⑪ savings_goals.status 枚举：已达目标（达成是事实状态，由上层按
/// Σ贡献 ≥ target_minor 判定后写回，DAO 不在求和读路径里偷偷改真值行）。
const String kSavingsGoalStatusCompleted = 'completed';

/// §5.5⑪ savings_goals.status 枚举：放弃（仍是真值行，区别于软删墓碑）。
const String kSavingsGoalStatusAbandoned = 'abandoned';

/// §5.5⑫ 贡献来源（v1 内补列 source，W13）：人工投币打卡。
const String kSavingsSourceManual = 'manual';

/// §5.5⑫ 贡献来源（v1 内补列 source，W13）：待办联动打卡
/// （§3.6「待办完成可选生成存钱贡献」，todos.goal_link → savings_goals）。
const String kSavingsSourceTodo = 'todo';

/// 存钱目标 DAO（§5.5⑪）。
///
/// [projection] 非空时：目标写路径同事务联动重算 day_summary.savings_progress
/// 快照（W13 实装，§5.6⑬）；为空则跳过投影（纯 outbox/同步侧用法）。
class SavingsGoalsDao {
  SavingsGoalsDao(this._db, {LocalWriteClock? clock, this.projection})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：业务行同事务读回快照入队。
  final SyncOutboxWriter _outbox;

  /// 非空时：目标变更后同事务重算存钱进度快照（§5.6⑬ W13）。
  final DaySummaryProjection? projection;

  /// 新建目标（§5.5⑪）：id 缺省本地生成 UUIDv7（§5.1 主键约定）。
  ///
  /// [rhythm] 为 §5.5⑪ rhythm 列的 JSON 文本（阶梯表或每日额，形状由上层
  /// 按存钱法定义）；[startedOn] 缺省取设备本地今日——365/52 周存钱法的
  /// 「第 1 格」锚点。业务行与 outbox 行快照同事务（§6.2）。
  Future<SavingsGoal> create({
    required String name,
    required int targetMinor,
    required String method,
    required String rhythm,
    String? deadline,
    String status = kSavingsGoalStatusActive,
    String? startedOn,
    String? id,
  }) async {
    assert(
      method == kSavingsMethodDaily365 ||
          method == kSavingsMethodWeek52 ||
          method == kSavingsMethodCustom,
      'method 仅 daily365/week52/custom（§5.5⑪）',
    );
    assert(
      status == kSavingsGoalStatusActive ||
          status == kSavingsGoalStatusCompleted ||
          status == kSavingsGoalStatusAbandoned,
      'status 仅 active/completed/abandoned（§5.5⑪）',
    );
    assert(targetMinor >= 0, 'target_minor 为金额（分）、非负（§5.1）');
    final rowId = id ?? generateUuidV7();
    final stamp = await _clock.next();
    final effectiveStartedOn = startedOn ?? _localToday();
    await _db.transaction(() async {
      await _db.into(_db.savingsGoals).insert(
            SavingsGoalsCompanion.insert(
              id: rowId,
              name: name,
              targetMinor: targetMinor,
              deadline: Value(deadline),
              method: method,
              rhythm: rhythm,
              status: status,
              startedOn: effectiveStartedOn,
              // §5.1 公共列：非空无默认列在 Companion.insert 中取裸值。
              createdAt: stamp.updatedAtMs,
              updatedAt: stamp.updatedAtMs,
              hlc: stamp.hlc,
              revision: 1,
              deviceId: await _clock.deviceId(),
            ),
          );
      // §6.2 写路径纪律：savings_goals 行快照同事务入队 sync_outbox（§5.6⑯）。
      await _outbox.enqueueRow('savings_goals', rowId);
      await _touchProjectionForGoal(effectiveStartedOn);
    });
    return (await findById(rowId))!;
  }

  /// 更新目标字段（名称/目标金额/截止日/存钱法/阶梯表/状态/起始日）。
  ///
  /// 传 [_unchanged] 哨兵表示「不改动」；显式传 null 仅 [deadline] 支持
  /// （置空截止日）。状态流转（active→completed/abandoned）由上层决策——
  /// 达成判定依据 Σ贡献 ≥ target（watchSumByGoal 流），DAO 读路径零副作用。
  Future<void> updateDetails({
    required String id,
    Object? name = _unchanged,
    Object? targetMinor = _unchanged,
    Object? deadline = _unchanged,
    Object? method = _unchanged,
    Object? rhythm = _unchanged,
    Object? status = _unchanged,
    Object? startedOn = _unchanged,
  }) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.savingsGoals)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('updateDetails: savings_goals 无此行 $id（§5.5⑪）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
        SavingsGoalsCompanion(
          name: name == _unchanged
              ? const Value.absent()
              : Value(name as String),
          targetMinor: targetMinor == _unchanged
              ? const Value.absent()
              : Value(targetMinor as int),
          deadline: deadline == _unchanged
              ? const Value.absent()
              : Value(deadline as String?),
          method: method == _unchanged
              ? const Value.absent()
              : Value(method as String),
          rhythm: rhythm == _unchanged
              ? const Value.absent()
              : Value(rhythm as String),
          status: status == _unchanged
              ? const Value.absent()
              : Value(status as String),
          startedOn: startedOn == _unchanged
              ? const Value.absent()
              : Value(startedOn as String),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2：主干字段变更同为真值行写入，行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('savings_goals', id);
      final effectiveStartedOn =
          startedOn == _unchanged ? row.startedOn : startedOn as String;
      await _touchProjectionForGoal(effectiveStartedOn);
    });
  }

  /// 归档（任务口径「归档=软删」，§5.1 删除行；§6.5 墓碑拒绝复活）。
  ///
  /// 与 status='abandoned'（放弃，仍是一条存活真值行）语义不同：归档是删除
  /// 语义，读侧/快照/求和一律排除墓碑行。重复归档幂等（保留首次墓碑时刻，
  /// 与 TodoDao.softDelete 同口径）；无此行抛 StateError。
  Future<void> softDelete(String id) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.savingsGoals)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        throw StateError('softDelete: savings_goals 无此行 $id（§5.1 删除行）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.savingsGoals)..where((t) => t.id.equals(id))).write(
        SavingsGoalsCompanion(
          deletedAt: Value(row.deletedAt ?? stamp.updatedAtMs),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      // §6.2：墓碑写入同事务入队；读回快照携带 deleted_at → 自动以 delete
      // 语义出网（§5.6⑯/§6.5 墓碑拒绝复活）。
      await _outbox.enqueueRow('savings_goals', id);
      await _touchProjectionForGoal(row.startedOn);
    });
  }

  Future<SavingsGoal?> findById(String id) => (_db.select(_db.savingsGoals)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 全部未归档目标（建档序）——计划页目标清单（§3.6）。
  Stream<List<SavingsGoal>> watchAll() {
    return (_db.select(_db.savingsGoals)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// 打卡中的目标（§5.5⑪ status='active'，排除墓碑）——仪表盘进度卡/
  /// 打卡页数据源。
  Stream<List<SavingsGoal>> watchActive() {
    return (_db.select(_db.savingsGoals)
          ..where((t) =>
              t.status.equals(kSavingsGoalStatusActive) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// 目标写路径的投影联动——**必须在写事务内调用**（§6.2「业务行 + 投影
  /// 同事务」）。
  ///
  /// - 既有快照行统一标 dirty：目标有效性（建档/归档/状态/起始日/截止日）
  ///   与 target_minor 变更可影响 started_on 之后的任何一日快照
  ///   （savings_progress 为累计口径），统一交 recomputeDirtyDays 后台自愈
  ///   （§5.6 自愈）；
  /// - 建档日与设备本地当日立即重算：当日窗口内（started_on <= 当日）的
  ///   目标进度卡即时可见——首目标建档当日快照从 NULL 变为有值，dirty 标记
  ///   （只扫 savings_progress 非空行）覆盖不到 NULL 行；未来起始的目标
  ///   当日快照仍为 NULL（未生效，属正确空态）。
  Future<void> _touchProjectionForGoal(String startedOn) async {
    final target = projection;
    if (target == null) {
      return;
    }
    await target.markSavingsProgressDirty();
    await target.recomputeDaySummary(startedOn);
    await target.recomputeDaySummary(_localToday());
  }

  /// updateDetails 的「不改动」哨兵（与 TodoDao 同口径）。
  static const Object _unchanged = Object();
}

/// 存钱贡献 DAO（§5.5⑫ append-only）。
///
/// 写路径只有 [append]（§6.1 原则 2）；贡献行的「删除」仅存在于同步 pull
/// 落库的远端墓碑（deleted_at），求和口径一律排除。任务口径幂等键：
/// **(goal_id, date, source)**。
class SavingsContributionsDao {
  SavingsContributionsDao(this._db, {LocalWriteClock? clock, this.projection})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）。
  final SyncOutboxWriter _outbox;

  /// 非空时：贡献追加后同事务重算贡献日快照、其后的既有快照行标 dirty
  /// （§5.6⑬ W13 累计口径）。
  final DaySummaryProjection? projection;

  /// 追加一条贡献（§5.5⑫ append-only、§6.1「能只增不改的绝不改行」）。
  ///
  /// - 幂等：同 (goal_id, date, source) 已有存活行 → no-op 返回既有行，
  ///   不产生新行、不入队 outbox、不触投影（无写入即无事实变化）；传入
  ///   [amountMinor]/[slot]/[note] 与既有行不一致时**以既有行为准**（首写
  ///   胜，与 append-only 免冲突口径一致）；
  /// - 目标必须存在且未归档（墓碑行不接受新贡献，§6.5）：否则 StateError
  ///   令事务整体回滚；状态为 completed/abandoned 时不拦截（业务门槛由
  ///   上层决定，DAO 只挡删除语义）；
  /// - [slot] 为 365/52 周存钱法格子号（daily365 第 N 天 / week52 第 N 周），
  ///   custom 通常为 null；[source] 缺省人工投币。
  Future<SavingsContribution> append({
    required String goalId,
    required int amountMinor,
    required String date,
    int? slot,
    String? note,
    String source = kSavingsSourceManual,
    String? id,
  }) {
    assert(amountMinor >= 0, 'amount_minor 为金额（分）、非负（§5.1）');
    assert(
      source == kSavingsSourceManual || source == kSavingsSourceTodo,
      'source 仅 manual/todo（§5.5⑫ v1 内补列 source，W13）',
    );
    return _db.transaction(() async {
      final goal = await (_db.select(_db.savingsGoals)
            ..where((t) => t.id.equals(goalId)))
          .getSingleOrNull();
      if (goal == null) {
        throw StateError(
          'append: savings_goals 无此行 $goalId（§5.5⑪ 逻辑引用不建外键，'
          '应用层校验）',
        );
      }
      if (goal.deletedAt != null) {
        throw StateError(
          'append: 目标 $goalId 已归档（墓碑行不接受新贡献，§6.5）',
        );
      }
      final existing = await (_db.select(_db.savingsContributions)
            ..where((t) =>
                t.goalId.equals(goalId) &
                t.date.equals(date) &
                t.source.equals(source) &
                t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        return existing; // 幂等命中：首写胜，no-op（不入队、不触投影）
      }
      final stamp = await _clock.next();
      final rowId = id ?? generateUuidV7();
      await _db.into(_db.savingsContributions).insert(
            SavingsContributionsCompanion.insert(
              id: rowId,
              goalId: goalId,
              date: date,
              amountMinor: amountMinor,
              slot: Value(slot),
              note: Value(note),
              source: Value(source),
              createdAt: stamp.updatedAtMs,
              updatedAt: stamp.updatedAtMs,
              hlc: stamp.hlc,
              revision: 1,
              deviceId: await _clock.deviceId(),
            ),
          );
      // §6.2 写路径纪律：savings_contributions 行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('savings_contributions', rowId);
      await _touchProjectionForContribution(date);
      return (_db.select(_db.savingsContributions)
            ..where((t) => t.id.equals(rowId)))
          .getSingle();
    });
  }

  Future<SavingsContribution?> findById(String id) =>
      (_db.select(_db.savingsContributions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  /// 幂等探针：目标某日某来源的存活贡献行（无则 null）。
  ///
  /// 供上层写前查重（如待办联动路径先探后投）；[append] 内部同口径自检。
  Future<SavingsContribution?> findEffective({
    required String goalId,
    required String date,
    String source = kSavingsSourceManual,
  }) {
    return (_db.select(_db.savingsContributions)
          ..where((t) =>
              t.goalId.equals(goalId) &
              t.date.equals(date) &
              t.source.equals(source) &
              t.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// 某目标全部贡献行（append-only 时间线：打卡日升序、同日按创建序，
  /// hlc 兜底全序）。含远端墓碑行（上层可自行过滤 deletedAt 渲染「撤销」
  /// 痕迹）。
  Stream<List<SavingsContribution>> watchByGoal(String goalId) {
    return (_db.select(_db.savingsContributions)
          ..where((t) => t.goalId.equals(goalId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.date),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.hlc),
          ]))
        .watch();
  }

  /// 按目标求和进度（§5.5⑫「目标进度=Σ贡献行」）：排除墓碑。
  Future<int> sumByGoal(String goalId) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total '
          'FROM savings_contributions '
          'WHERE goal_id = ? AND deleted_at IS NULL',
          variables: [Variable.withString(goalId)],
        )
        .getSingle();
    return row.read<int>('total');
  }

  /// 按目标求和的响应式流（§10.1 Drift reactive stream）：进度环/进度条
  /// 直驱（§3.2 存钱进度卡）。
  Stream<int> watchSumByGoal(String goalId) {
    return _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total '
          'FROM savings_contributions '
          'WHERE goal_id = ? AND deleted_at IS NULL',
          variables: [Variable.withString(goalId)],
          readsFrom: {_db.savingsContributions},
        )
        .map((row) => row.read<int>('total'))
        .watchSingle();
  }

  /// 贡献写路径的投影联动——**必须在写事务内调用**（§6.2）。
  ///
  /// savings_progress 为累计口径（date <= 快照日，§5.6⑬）：贡献日及其后的
  /// 既有快照行都要推进——贡献日立即重算（当日进度卡即时可见），其后日期
  /// 标 dirty 交 recomputeDirtyDays 后台自愈；先标后算，贡献日本身的 dirty
  /// 由重算复位。
  Future<void> _touchProjectionForContribution(String date) async {
    final target = projection;
    if (target == null) {
      return;
    }
    await target.markSavingsProgressDirty(fromDate: date);
    await target.recomputeDaySummary(date);
  }
}

/// 设备本地今日（yyyy-MM-dd，§5.1 日期约定，与 core_domain 日历日同源）：
/// 目标建档缺省起始日与「当日进度卡即时可见」的重算基准（§3.2）。
String _localToday() => dom.formatCalendarDay(DateTime.now());

/// v1 内补列幂等回填（§6.4「行级 schema_ver 只加列前向兼容」的落点；W13）。
///
/// savings_contributions.source（贡献来源，幂等键三元组之一）为 schema v1
/// 冻结后的只加列变更：**schemaVersion 保持 1**，旧 v1 库文件不触发
/// onUpgrade——在 beforeOpen 按 `PRAGMA table_info` 探测缺列并
/// `ALTER TABLE ADD COLUMN source TEXT NOT NULL DEFAULT 'manual'` 补齐
/// （SQLite 加列语义下存量行一次性落到默认值 'manual'，与
/// backfillAttachmentBurnColumns 的 status 同口径）。
///
/// 新库（onCreate createAll）已含本列 → 本函数幂等 no-op。取舍说明：V1 未
/// 发布（§11.2 W16 才商店发布）、冻结期禁破坏性迁移（§6.4），故选择
/// 「v1 内补列+默认值+幂等回填」——无版本号变化、无破坏性、对存量开发库
/// 文件自愈。
Future<void> backfillSavingsContributionSourceColumn(AppDatabase db) async {
  final info =
      await db.customSelect('PRAGMA table_info(savings_contributions)').get();
  if (info.isEmpty) {
    return; // 表不存在（onCreate 前的异常时序）：交给建表流程
  }
  final columns = info.map((row) => row.data['name'] as String).toSet();
  if (columns.contains('source')) {
    return; // 新库已含本列：幂等 no-op
  }
  await db.customStatement(
    "ALTER TABLE savings_contributions ADD COLUMN source "
    "TEXT NOT NULL DEFAULT 'manual'",
  );
}
