/// BudgetsDao — 预算 CRUD（§5.4⑥ budgets、§11.2 W15「预算体系」主线）。
///
/// 预算体系语义（§5.4⑥/§3.4「月度+分类预算 P1」）：
/// - 按**账本**归属：预算挂任一 money 账本或内置 kcal 账本（含 kcal 账本：
///   「预算=收入、吃=支出、运动=再入账」，§5.4 kcal 账本行）；
/// - 按**分类**细分：category_id NULL=总预算，非空=分类级预算（§5.4⑥）；
/// - 按**周期**：daily（P0 热量+支出每日预算）/ monthly（P1 月度预算，
///   周期起点 day_of_month_start 自定义 1..28）；
/// - carry_over 结转开关（§5.4⑥ P1）：月度预算开启后，上一周期未用完的
///   余量并入本周期——结转计算在 day_summary 投影 v2 快照（§5.6⑬）按
///   「单步结转」实装（见 day_summary_projection.dart 迁移注记）。
///
/// 写路径纪律（§6.2，与 LedgerDao/SavingsGoalsDao 同口径）：
/// - budgets 为 §5.1 同步真值表：业务行与行快照**同事务**入队 sync_outbox
///   （SyncOutboxWriter.enqueueRow 读回快照，§5.6⑯）；
/// - 删除一律软删墓碑（deleted_at，§5.1 删除行），清除预算即软删；
/// - 同一 (ledger_id, category_id, period_type) 只允许一条现行预算（未删）：
///   重复设置 = 原行改额（带新 HLC 戳），不堆叠多行——快照/汇总读取端按
///   「一条预算一项」的形状契约成立；
/// - 投影联动（§5.6⑬）：预算变更影响**所有已投影日**的 budget_snapshot
///   （daily 预算影响每一日；monthly 周期窗口可覆盖历史任意区间）——
///   同事务标记全部投影行 dirty 后重算自愈（DaySummaryProjection.
///   markBudgetSnapshotDirty + recomputeDirtyDays，W15 v2）。
library;

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'day_summary_projection.dart';
import 'local_write_clock.dart';
import 'sync_outbox_writer.dart';

/// budgets.period_type wire 值：每日预算（P0，§5.4⑥）。
const String kBudgetPeriodDaily = 'daily';

/// budgets.period_type wire 值：月度预算（P1，§5.4⑥）。
const String kBudgetPeriodMonthly = 'monthly';

/// 预算 DAO（§5.4⑥ budgets）。
///
/// [projection] 非空时：预算写路径同事务联动重算 day_summary.budget_snapshot
/// （W15 v2，§5.6⑬）；为空则跳过投影（纯 outbox/同步侧用法）。
class BudgetsDao {
  BudgetsDao(this._db, {LocalWriteClock? clock, this.projection})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：业务行同事务读回快照入队。
  final SyncOutboxWriter _outbox;

  /// 非空时：预算变更后同事务重算预算快照（§5.6⑬ W15 v2）。
  final DaySummaryProjection? projection;

  /// 设置/更新一条预算（§5.4⑥），返回落库后的现行行。
  ///
  /// - [ledgerId] 必须指向未删账本（逻辑引用人工校验，§5.4④/§6.2）；
  ///   kcal 账本允许（预算=kcal 整数，§5.4 kcal 账本行）；
  /// - [categoryId] 非空时必须指向未删分类（NULL=总预算，§5.4⑥）；
  /// - [periodType] 限 daily/monthly（wire 值，§5.4⑥）；
  /// - [amount] 必须为正：money 账本=分、kcal 账本=kcal（§5.1 口径）；
  /// - [dayOfMonthStart] 月度周期起点（1..28，规避大小月边界；daily 忽略）；
  /// - [carryOver] 结转开关（monthly 语义，daily 忽略，§5.4⑥）；
  /// - [id] 新建行的主键（缺省本地生成 UUIDv7，§5.1）。
  ///
  /// 同 (ledger, category, period) 已有现行预算时改为原行更新（revision+1、
  /// 新 HLC 戳），否则插入——「一条预算一项」形状契约（类文档头）。
  Future<Budget> upsertBudget({
    required String ledgerId,
    String? categoryId,
    required String periodType,
    required int amount,
    int dayOfMonthStart = 1,
    bool carryOver = false,
    String? id,
  }) async {
    if (periodType != kBudgetPeriodDaily &&
        periodType != kBudgetPeriodMonthly) {
      throw ArgumentError.value(
        periodType,
        'periodType',
        '必须为 daily/monthly（§5.4⑥）',
      );
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', '预算额必须为正数（§5.4⑥）');
    }
    if (periodType == kBudgetPeriodMonthly &&
        (dayOfMonthStart < 1 || dayOfMonthStart > 28)) {
      throw ArgumentError.value(
        dayOfMonthStart,
        'dayOfMonthStart',
        '月度周期起点必须为 1..28（规避大小月边界，§5.4⑥）',
      );
    }
    return _db.transaction(() async {
      // 账本存在性（§5.4④）：逻辑引用不建外键，写前人工校验（§6.2）。
      final ledger = await (_db.select(_db.ledgers)
            ..where((t) => t.id.equals(ledgerId) & t.deletedAt.isNull()))
          .getSingleOrNull();
      if (ledger == null) {
        throw StateError('预算归属账本不存在或已删：$ledgerId（§5.4④）');
      }
      // 分类存在性（§5.4⑤）：同上。
      if (categoryId != null) {
        final category = await (_db.select(_db.categories)
              ..where((t) =>
                  t.id.equals(categoryId) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (category == null) {
          throw StateError('预算分类不存在或已删：$categoryId（§5.4⑤）');
        }
      }
      final existing = await findCurrent(
        ledgerId: ledgerId,
        categoryId: categoryId,
        periodType: periodType,
      );
      final stamp = await _clock.next();
      final String rowId;
      if (existing == null) {
        rowId = id ?? generateUuidV7();
        await _db.into(_db.budgets).insert(
              BudgetsCompanion.insert(
                id: rowId,
                ledgerId: ledgerId,
                // NULL=总预算（§5.4⑥）。
                categoryId: Value(categoryId),
                periodType: periodType,
                amount: amount,
                dayOfMonthStart: dayOfMonthStart,
                carryOver: carryOver,
                // §5.1 公共列：非空无默认列取裸值。
                createdAt: stamp.updatedAtMs,
                updatedAt: stamp.updatedAtMs,
                hlc: stamp.hlc,
                revision: 1,
                deviceId: await _clock.deviceId(),
              ),
            );
      } else {
        rowId = existing.id;
        await (_db.update(_db.budgets)..where((t) => t.id.equals(rowId)))
            .write(
          BudgetsCompanion(
            amount: Value(amount),
            dayOfMonthStart: Value(dayOfMonthStart),
            carryOver: Value(carryOver),
            updatedAt: Value(stamp.updatedAtMs),
            hlc: Value(stamp.hlc),
            revision: Value(existing.revision + 1),
          ),
        );
      }
      // §6.2：真值行快照同事务入队（§5.6⑯）。
      await _outbox.enqueueRow('budgets', rowId);
      await _linkProjection();
      return (_db.select(_db.budgets)..where((t) => t.id.equals(rowId)))
          .getSingle();
    });
  }

  /// 清除预算 = 软删墓碑（§5.1 删除行）；幂等：不存在/已删直接返回。
  Future<void> softDeleteBudget(String id) {
    return _db.transaction(() async {
      final existing = await (_db.select(_db.budgets)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (existing == null || existing.deletedAt != null) {
        return; // 幂等（§6.5 删除策略）。
      }
      final stamp = await _clock.next();
      await (_db.update(_db.budgets)..where((t) => t.id.equals(id))).write(
        BudgetsCompanion(
          deletedAt: Value(stamp.updatedAtMs),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(existing.revision + 1),
        ),
      );
      // 墓碑行快照以 delete 语义出网（enqueueRow 按 deleted_at 判 op，§5.6⑯）。
      await _outbox.enqueueRow('budgets', id);
      await _linkProjection();
    });
  }

  /// 现行预算查询（未删）：总预算与分类预算按 categoryId 区分（NULL 与非
  /// NULL 是不同预算，§5.4⑥）；总预算按「category_id IS NULL」精确匹配。
  Future<Budget?> findCurrent({
    required String ledgerId,
    String? categoryId,
    required String periodType,
  }) {
    return (_db.select(_db.budgets)
          ..where((t) {
            final Expression<bool> categoryPredicate = categoryId == null
                ? t.categoryId.isNull()
                : t.categoryId.equals(categoryId);
            return t.periodType.equals(periodType) &
                t.ledgerId.equals(ledgerId) &
                categoryPredicate &
                t.deletedAt.isNull();
          }))
        .getSingleOrNull();
  }

  /// 全部现行预算（未删），[periodType] 可选过滤；创建序稳定排序。
  Future<List<Budget>> getAll({String? periodType}) async {
    final query = _db.select(_db.budgets)
      ..where((t) {
        Expression<bool> predicate = t.deletedAt.isNull();
        if (periodType != null) {
          predicate = predicate & t.periodType.equals(periodType);
        }
        return predicate;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// [getAll] 的响应式形态（预算设置页/管理页数据源）。
  Stream<List<Budget>> watchAll({String? periodType}) {
    final query = _db.select(_db.budgets)
      ..where((t) {
        Expression<bool> predicate = t.deletedAt.isNull();
        if (periodType != null) {
          predicate = predicate & t.periodType.equals(periodType);
        }
        return predicate;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.watch();
  }

  /// 投影联动（§5.6⑬ W15 v2）：预算行变更影响所有已投影日的快照——同事务
  /// 标记 dirty 后重算自愈。投影未注入时跳过（同步 pull 侧由 pull 编排补算）。
  Future<void> _linkProjection() async {
    final DaySummaryProjection? target = projection;
    if (target == null) {
      return;
    }
    await target.markBudgetSnapshotDirty();
    await target.recomputeDirtyDays();
  }
}
