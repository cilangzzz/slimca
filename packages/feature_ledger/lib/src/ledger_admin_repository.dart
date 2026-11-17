/// 账本管理写入仓库：分类增删改（§5.4⑤ categories）与每日/月度目标落库
/// （§5.4⑥ budgets period=daily/monthly；§3.4 每日目标、§11.2 W15 预算
/// 体系）。
///
/// 写路径纪律（§5.1/§6.2）：
/// - 全部写入带 HLC 戳（LocalWriteClock 发号，§6.3）：revision 自增、
///   updatedAt/hlc 单调，W5-6 SyncEngine 接入后可无损上送；
/// - budgets 写路径经 core_db [cdb.BudgetsDao]（W15 收口）：业务行与
///   outbox 行快照同事务入队（§6.2/§5.6⑯——W5-6 版直写 budgets 漏入队的
///   补课项）、day_summary.budget_snapshot v2 投影联动（§5.6⑬）；
/// - 删除一律软删墓碑（deleted_at，§5.1 删除行；墓碑拒绝复活 §6.5）；
/// - 分类对账单是逻辑引用（不建外键，§5.4⑤/§6.2）：删分类后历史账单行
///   原样保留（join 落"未分类"），不做级联物理删；
/// - 内置 20+ 中文分类不可删（§5.4⑤ is_preset）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/drift.dart' as drift;

import 'ledger_models.dart';

/// 账本管理仓库接口（§10.4 分层纪律）。
abstract interface class LedgerAdminRepository {
  /// 全部分类（未删，kind → sort 排序；§5.4⑤）。
  Stream<List<LedgerCategoryOption>> watchCategoryOptions();

  /// 新建自定义分类，返回新 id。name 去首尾空白后必须非空；kind 限
  /// expense/income；colorToken 校验语义 token 白名单（§8.2）。
  Future<String> createCategory({
    required String name,
    required String kind,
    String? icon,
    String? colorToken,
  });

  /// 更新分类（改名/图标/色 token）。已删墓碑拒绝更新（§6.5）。
  Future<void> updateCategory({
    required String id,
    String? name,
    String? icon,
    String? colorToken,
  });

  /// 软删自定义分类（墓碑）；内置分类抛 StateError（§5.4⑤ is_preset）。
  /// 幂等：不存在/已删直接返回。
  Future<void> softDeleteCategory(String id);

  /// 现行每日目标（budgets period=daily 且未删，§5.4⑥）。
  Stream<List<LedgerDailyBudget>> watchDailyBudgets();

  /// 现行月度支出目标（budgets period=monthly 且未删，§5.4⑥ P1/W15）。
  Stream<List<LedgerDailyBudget>> watchMonthlyBudgets();

  /// 设置每日总支出目标（分；挂默认 money 账本，总预算 categoryId=NULL）。
  Future<void> setDailySpendGoal(int amountMinor);

  /// 设置每日总热量目标（kcal 整数；挂内置 kcal 账本）。
  Future<void> setDailyKcalGoal(int kcal);

  /// 设置分类级每日支出目标（分；§5.4⑥ budgets.category_id 非空）。
  Future<void> setCategoryDailyGoal({
    required String categoryId,
    required int amountMinor,
  });

  /// 设置月度总支出目标（分；§5.4⑥ period=monthly、周期起点/结转开关，
  /// W15 预算体系；挂默认 money 账本、总预算 categoryId=NULL）。
  Future<void> setMonthlySpendGoal(
    int amountMinor, {
    int dayOfMonthStart = 1,
    bool carryOver = false,
  });

  /// 清除每日总支出目标（软删墓碑；幂等）。
  Future<void> clearDailySpendGoal();

  /// 清除每日总热量目标（软删墓碑；幂等）。
  Future<void> clearDailyKcalGoal();

  /// 清除分类级每日目标（软删墓碑；幂等）。
  Future<void> clearCategoryDailyGoal(String categoryId);

  /// 清除月度总支出目标（软删墓碑；幂等）。
  Future<void> clearMonthlySpendGoal();
}

/// Drift 实现（复用 LedgerDao 解析目标账本、BudgetsDao 收口预算写路径——
/// core_db 既有抽象，§10.3）。
class DriftLedgerAdminRepository implements LedgerAdminRepository {
  DriftLedgerAdminRepository(this._db, {cdb.LocalWriteClock? clock})
      : _clock = clock ?? cdb.LocalWriteClock(_db),
        // 投影实例无状态（仅 _db 引用）：预算写后同事务联动 budget_snapshot
        // v2（§5.6⑬ W15）。
        _budgets = cdb.BudgetsDao(
          _db,
          projection: cdb.DaySummaryProjection(_db),
        );

  final cdb.AppDatabase _db;
  final cdb.LocalWriteClock _clock;

  /// 预算写路径（W15 收口）：outbox 同事务入队 + budget_snapshot v2 联动
  /// 由 DAO 强制（§6.2/§5.6⑬）。投影注入：本仓库持独立投影实例（无状态，
  /// 仅 _db 引用）。
  final cdb.BudgetsDao _budgets;

  // ── 分类（§5.4⑤） ─────────────────────────────────────────────────────

  @override
  Stream<List<LedgerCategoryOption>> watchCategoryOptions() {
    return (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => drift.OrderingTerm.asc(t.kind),
            (t) => drift.OrderingTerm.asc(t.sort),
            (t) => drift.OrderingTerm.asc(t.createdAt),
          ]))
        .watch()
        .map((List<cdb.Category> rows) => <LedgerCategoryOption>[
              for (final cdb.Category row in rows)
                LedgerCategoryOption(
                  id: row.id,
                  name: row.name,
                  icon: row.icon,
                  kind: row.kind,
                  colorToken: row.colorToken,
                  isPreset: row.isPreset,
                ),
            ]);
  }

  @override
  Future<String> createCategory({
    required String name,
    required String kind,
    String? icon,
    String? colorToken,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '分类名不能为空（§5.4⑤）');
    }
    if (kind != kCategoryKindExpense && kind != kCategoryKindIncome) {
      throw ArgumentError.value(
        kind,
        'kind',
        '必须为 expense/income（§5.4⑤）',
      );
    }
    final String token = normalizeLedgerColorToken(colorToken);
    final int sort = await _nextSort();
    final cdb.WriteStamp stamp = await _clock.next();
    final String id = cdb.generateUuidV7();
    await _db.into(_db.categories).insert(
          cdb.CategoriesCompanion.insert(
            id: id,
            name: trimmed,
            icon: icon ?? 'label',
            sort: sort,
            // 逻辑引用不建外键（§5.4⑤）：MVP 分类全局生效，ledgerId=NULL。
            ledgerId: const drift.Value(null),
            kind: kind,
            colorToken: token,
            isPreset: false,
            createdAt: stamp.updatedAtMs,
            updatedAt: stamp.updatedAtMs,
            hlc: stamp.hlc,
            revision: 1,
            deviceId: await _clock.deviceId(),
          ),
        );
    return id;
  }

  @override
  Future<void> updateCategory({
    required String id,
    String? name,
    String? icon,
    String? colorToken,
  }) async {
    final cdb.Category? existing = await (_db.select(_db.categories)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      throw StateError('updateCategory: 分类不存在 $id（§5.4⑤）');
    }
    if (existing.deletedAt != null) {
      throw StateError('已删墓碑分类拒绝更新（§6.5 删除策略）');
    }
    final String? trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '分类名不能为空（§5.4⑤）');
    }
    final cdb.WriteStamp stamp = await _clock.next();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      cdb.CategoriesCompanion(
        name: trimmed == null ? const drift.Value.absent() : drift.Value(trimmed),
        icon: icon == null ? const drift.Value.absent() : drift.Value(icon),
        colorToken: colorToken == null
            ? const drift.Value.absent()
            : drift.Value(normalizeLedgerColorToken(colorToken)),
        updatedAt: drift.Value(stamp.updatedAtMs),
        hlc: drift.Value(stamp.hlc),
        revision: drift.Value(existing.revision + 1),
      ),
    );
  }

  @override
  Future<void> softDeleteCategory(String id) async {
    final cdb.Category? existing = await (_db.select(_db.categories)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.deletedAt != null) {
      return; // 幂等：不存在/已删墓碑直接返回（§6.5）。
    }
    if (existing.isPreset) {
      throw StateError('内置分类不可删（§5.4⑤ is_preset）');
    }
    final cdb.WriteStamp stamp = await _clock.next();
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      cdb.CategoriesCompanion(
        deletedAt: drift.Value(stamp.updatedAtMs),
        updatedAt: drift.Value(stamp.updatedAtMs),
        hlc: drift.Value(stamp.hlc),
        revision: drift.Value(existing.revision + 1),
      ),
    );
  }

  /// 自定义分类的 sort 取当前最大值 +1（内置分类占 0..N 不受影响）。
  Future<int> _nextSort() async {
    final cdb.Category? maxRow = await (_db.select(_db.categories)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) => drift.OrderingTerm.desc(t.sort),
          ])
          ..limit(1))
        .getSingleOrNull();
    return (maxRow?.sort ?? -1) + 1;
  }

  // ── 每日/月度目标（§5.4⑥ budgets period=daily/monthly + §3.4 + W15） ──

  /// budgets period 过滤的现行目标流（join 回账本/分类回填名称，§5.4⑥）。
  Stream<List<LedgerDailyBudget>> _watchBudgets(String periodType) {
    final query = _db.select(_db.budgets).join(<drift.Join>[
      // budgets.ledger_id 逻辑引用，join 回账本取 kind（kcal 口径判定；
      // ledgers 列要被读取，不关 useColumns）。
      drift.innerJoin(
        _db.ledgers,
        _db.ledgers.id.equalsExp(_db.budgets.ledgerId),
      ),
      // 分类级目标回填分类名；已删分类显示"已删分类"（§5.4⑤）。
      drift.leftOuterJoin(
        _db.categories,
        _db.categories.id.equalsExp(_db.budgets.categoryId),
      ),
    ]);
    query.where(
      _db.budgets.periodType.equals(periodType) &
          _db.budgets.deletedAt.isNull(),
    );
    query.orderBy(<drift.OrderingTerm>[
      drift.OrderingTerm.asc(_db.budgets.createdAt),
    ]);
    return query.watch().map((List<drift.TypedResult> rows) =>
        <LedgerDailyBudget>[
          for (final drift.TypedResult row in rows)
            LedgerDailyBudget(
              id: row.readTable(_db.budgets).id,
              ledgerId: row.readTable(_db.budgets).ledgerId,
              ledgerKind: row.readTable(_db.ledgers).kind,
              categoryId: row.readTable(_db.budgets).categoryId,
              categoryName: row.readTableOrNull(_db.categories)?.name,
              amount: row.readTable(_db.budgets).amount,
              periodType: periodType,
              dayOfMonthStart: row.readTable(_db.budgets).dayOfMonthStart,
              carryOver: row.readTable(_db.budgets).carryOver,
            ),
        ]);
  }

  @override
  Stream<List<LedgerDailyBudget>> watchDailyBudgets() {
    return _watchBudgets(kBudgetPeriodDaily);
  }

  @override
  Stream<List<LedgerDailyBudget>> watchMonthlyBudgets() {
    return _watchBudgets(kBudgetPeriodMonthly);
  }

  @override
  Future<void> setDailySpendGoal(int amountMinor) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    await _budgets.upsertBudget(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodDaily,
      amount: amountMinor,
    );
  }

  @override
  Future<void> setDailyKcalGoal(int kcal) async {
    if (kcal <= 0) {
      throw ArgumentError.value(kcal, 'kcal', '每日热量目标必须为正整数（§3.4）');
    }
    final cdb.Ledger ledger = await _requireKcalLedger();
    await _budgets.upsertBudget(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodDaily,
      amount: kcal,
    );
  }

  @override
  Future<void> setCategoryDailyGoal({
    required String categoryId,
    required int amountMinor,
  }) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    // 逻辑引用（§5.4⑤）：写前人工校验分类存在且未删。
    final cdb.Category? category = await (_db.select(_db.categories)
          ..where((t) => t.id.equals(categoryId) & t.deletedAt.isNull()))
        .getSingleOrNull();
    if (category == null) {
      throw StateError('分类不存在或已删：$categoryId（§5.4⑤）');
    }
    await _budgets.upsertBudget(
      ledgerId: ledger.id,
      categoryId: categoryId,
      periodType: kBudgetPeriodDaily,
      amount: amountMinor,
    );
  }

  @override
  Future<void> setMonthlySpendGoal(
    int amountMinor, {
    int dayOfMonthStart = 1,
    bool carryOver = false,
  }) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    await _budgets.upsertBudget(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodMonthly,
      amount: amountMinor,
      // 月度周期起点 1..28、结转开关（§5.4⑥ P1/W15；校验在 BudgetsDao）。
      dayOfMonthStart: dayOfMonthStart,
      carryOver: carryOver,
    );
  }

  @override
  Future<void> clearDailySpendGoal() async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    final cdb.Budget? existing = await _budgets.findCurrent(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodDaily,
    );
    if (existing != null) {
      await _budgets.softDeleteBudget(existing.id);
    }
  }

  @override
  Future<void> clearDailyKcalGoal() async {
    final cdb.Ledger ledger = await _requireKcalLedger();
    final cdb.Budget? existing = await _budgets.findCurrent(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodDaily,
    );
    if (existing != null) {
      await _budgets.softDeleteBudget(existing.id);
    }
  }

  @override
  Future<void> clearCategoryDailyGoal(String categoryId) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    final cdb.Budget? existing = await _budgets.findCurrent(
      ledgerId: ledger.id,
      categoryId: categoryId,
      periodType: kBudgetPeriodDaily,
    );
    if (existing != null) {
      await _budgets.softDeleteBudget(existing.id);
    }
  }

  @override
  Future<void> clearMonthlySpendGoal() async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    final cdb.Budget? existing = await _budgets.findCurrent(
      ledgerId: ledger.id,
      periodType: kBudgetPeriodMonthly,
    );
    if (existing != null) {
      await _budgets.softDeleteBudget(existing.id);
    }
  }

  /// 默认 money 账本（§5.4④ seed 恒保证存在；复用 core_db LedgerDao）。
  ///
  /// W15 多账本：以 settings 默认指针为准（[cdb.LedgerDao.defaultLedger]），
  /// 指针缺失/失效回退首个可用 money 账本（§5.6⑲）。
  Future<cdb.Ledger> _requireMoneyLedger() async {
    final cdb.LedgerDao dao = cdb.LedgerDao(_db);
    final cdb.Ledger? byPointer = await dao.defaultLedger();
    final cdb.Ledger? ledger =
        byPointer ?? await dao.defaultMoneyLedger();
    if (ledger == null) {
      throw StateError('默认 money 账本缺失（§5.4④ seed 保证恒存在）');
    }
    return ledger;
  }

  /// 内置 kcal 账本（§5.4④ 系统内置一个）。
  Future<cdb.Ledger> _requireKcalLedger() async {
    final cdb.Ledger? ledger = await cdb.LedgerDao(_db).kcalLedger();
    if (ledger == null) {
      throw StateError('内置 kcal 账本缺失（§5.4④ seed 保证恒存在）');
    }
    return ledger;
  }
}
