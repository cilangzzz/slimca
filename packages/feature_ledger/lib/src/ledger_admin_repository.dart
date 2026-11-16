/// 账本管理写入仓库：分类增删改（§5.4⑤ categories）与每日目标落库
/// （§5.4⑥ budgets period=daily；§3.4 每日目标）。
///
/// 写路径纪律（§5.1/§6.2）：
/// - 全部写入带 HLC 戳（LocalWriteClock 发号，§6.3）：revision 自增、
///   updatedAt/hlc 单调，W5-6 SyncEngine 接入后可无损上送；
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

  /// 设置每日总支出目标（分；挂默认 money 账本，总预算 categoryId=NULL）。
  Future<void> setDailySpendGoal(int amountMinor);

  /// 设置每日总热量目标（kcal 整数；挂内置 kcal 账本）。
  Future<void> setDailyKcalGoal(int kcal);

  /// 设置分类级每日支出目标（分；§5.4⑥ budgets.category_id 非空）。
  Future<void> setCategoryDailyGoal({
    required String categoryId,
    required int amountMinor,
  });

  /// 清除每日总支出目标（软删墓碑；幂等）。
  Future<void> clearDailySpendGoal();

  /// 清除每日总热量目标（软删墓碑；幂等）。
  Future<void> clearDailyKcalGoal();

  /// 清除分类级每日目标（软删墓碑；幂等）。
  Future<void> clearCategoryDailyGoal(String categoryId);
}

/// Drift 实现（复用 LedgerDao 解析目标账本——core_db 既有抽象，§10.3）。
class DriftLedgerAdminRepository implements LedgerAdminRepository {
  DriftLedgerAdminRepository(this._db, {cdb.LocalWriteClock? clock})
      : _clock = clock ?? cdb.LocalWriteClock(_db);

  final cdb.AppDatabase _db;
  final cdb.LocalWriteClock _clock;

  /// money/kcal periodType wire 值（§5.4⑥ daily=P0）。
  static const String _kPeriodDaily = 'daily';

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

  // ── 每日目标（§5.4⑥ budgets period=daily + §3.4） ────────────────────

  @override
  Stream<List<LedgerDailyBudget>> watchDailyBudgets() {
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
      _db.budgets.periodType.equals(_kPeriodDaily) &
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
            ),
        ]);
  }

  @override
  Future<void> setDailySpendGoal(int amountMinor) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    await _upsertDailyBudget(ledger.id, null, amountMinor);
  }

  @override
  Future<void> setDailyKcalGoal(int kcal) async {
    if (kcal <= 0) {
      throw ArgumentError.value(kcal, 'kcal', '每日热量目标必须为正整数（§3.4）');
    }
    final cdb.Ledger ledger = await _requireKcalLedger();
    await _upsertDailyBudget(ledger.id, null, kcal);
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
    await _upsertDailyBudget(ledger.id, categoryId, amountMinor);
  }

  @override
  Future<void> clearDailySpendGoal() async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    await _softDeleteDailyBudget(ledger.id, null);
  }

  @override
  Future<void> clearDailyKcalGoal() async {
    final cdb.Ledger ledger = await _requireKcalLedger();
    await _softDeleteDailyBudget(ledger.id, null);
  }

  @override
  Future<void> clearCategoryDailyGoal(String categoryId) async {
    final cdb.Ledger ledger = await _requireMoneyLedger();
    await _softDeleteDailyBudget(ledger.id, categoryId);
  }

  /// 默认 money 账本（§5.4④ seed 恒保证存在；复用 core_db LedgerDao）。
  Future<cdb.Ledger> _requireMoneyLedger() async {
    final cdb.Ledger? ledger = await cdb.LedgerDao(_db).defaultMoneyLedger();
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

  /// 每日目标 upsert：同一 (ledgerId, categoryId, daily) 只允许一条现行
  /// 预算——已有则原行改 amount（带新 HLC 戳），没有则插入。
  Future<void> _upsertDailyBudget(
    String ledgerId,
    String? categoryId,
    int amount,
  ) async {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', '每日目标必须为正数（§3.4）');
    }
    await _db.transaction(() async {
      final cdb.Budget? existing =
          await _findDailyBudget(ledgerId, categoryId);
      final cdb.WriteStamp stamp = await _clock.next();
      if (existing == null) {
        await _db.into(_db.budgets).insert(
              cdb.BudgetsCompanion.insert(
                id: cdb.generateUuidV7(),
                ledgerId: ledgerId,
                // NULL=总预算（§5.4⑥）。
                categoryId: drift.Value(categoryId),
                periodType: _kPeriodDaily,
                amount: amount,
                // 月度周期字段为 P1 预留（§5.4⑥）：dayOfMonthStart 恒 1。
                dayOfMonthStart: 1,
                carryOver: false,
                createdAt: stamp.updatedAtMs,
                updatedAt: stamp.updatedAtMs,
                hlc: stamp.hlc,
                revision: 1,
                deviceId: await _clock.deviceId(),
              ),
            );
      } else {
        await (_db.update(_db.budgets)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          cdb.BudgetsCompanion(
            amount: drift.Value(amount),
            updatedAt: drift.Value(stamp.updatedAtMs),
            hlc: drift.Value(stamp.hlc),
            revision: drift.Value(existing.revision + 1),
          ),
        );
      }
    });
  }

  /// 清除目标 = 预算行软删墓碑（§5.1 删除行）；幂等。
  Future<void> _softDeleteDailyBudget(
    String ledgerId,
    String? categoryId,
  ) async {
    final cdb.Budget? existing = await _findDailyBudget(ledgerId, categoryId);
    if (existing == null) {
      return;
    }
    final cdb.WriteStamp stamp = await _clock.next();
    await (_db.update(_db.budgets)..where((t) => t.id.equals(existing.id)))
        .write(
      cdb.BudgetsCompanion(
        deletedAt: drift.Value(stamp.updatedAtMs),
        updatedAt: drift.Value(stamp.updatedAtMs),
        hlc: drift.Value(stamp.hlc),
        revision: drift.Value(existing.revision + 1),
      ),
    );
  }

  /// 现行每日预算查询（未删）；总预算与分类预算按 categoryId 区分
  /// （NULL 与非 NULL 是不同目标，§5.4⑥）。
  Future<cdb.Budget?> _findDailyBudget(String ledgerId, String? categoryId) {
    return (_db.select(_db.budgets)
          ..where((t) {
            final drift.Expression<bool> categoryPredicate = categoryId == null
                ? t.categoryId.isNull()
                : t.categoryId.equals(categoryId);
            return t.periodType.equals(_kPeriodDaily) &
                t.ledgerId.equals(ledgerId) &
                categoryPredicate &
                t.deletedAt.isNull();
          }))
        .getSingleOrNull();
  }
}
