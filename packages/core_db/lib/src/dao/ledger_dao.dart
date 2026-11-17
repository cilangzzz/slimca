/// LedgerDao + 默认账本 seed（§5.4④ 账本、§3.4 单账本 MVP）。
///
/// seed 语义（§5.4/§3.4）：MVP 恒默认 money 账本（schema 先冻结、功能后
/// 启用）；kcal 账本系统内置一个、不可删除不可多开，币种=kcal——「金额分类
/// 与热量维度并存」（§11.1 W2、§5.4 kcal 账本行）。幂等：按 kind 查缺补插，
/// 已存在的行不动（允许用户后续改名/改图标）。
///
/// 出网纪律（§6.2 写路径，W5-6 补课）：ledgers 为 §5.1 同步真值表，seed
/// 行与行快照入队 sync_outbox 同事务——否则他端收不到默认账本/分类、
/// entry_lines 的 ledger_id 引用在服务端失配，破坏 W7-8「双设备一致率
/// 100%」（§11.1 W7-8）。幂等由「缺什么补什么」保证：行已存在（含 pull
/// 回来的他端 seed 行）不再插入、也就不再入队。
///
/// W15 多账本（§11.2 W15「多账本+预算体系+统计报表」、§3.4 多账本 P1）：
/// 在 seed 之上补齐账本生命周期写路径——建账本/重命名/归档软删/切换默认。
/// 纪律（§5.4④）：
/// - kcal 账本**不可删除不可多开**：createLedger 只开 money 口；kcal 只允许
///   改名改图标（seed 既定口径），归档/删除一律拒绝；
/// - 归档（§3.4「账本归档」）= is_archived 置位 + 历史账单原样保留（逻辑
///   引用不级联，§5.4⑤/§6.2），**不落 deleted_at 墓碑**——墓碑语义保留给
///   真删除（§5.1 删除行），归档是产品态而非同步删除；
/// - 默认账本走 settings[kSettingDefaultLedgerId]（§5.6⑲「默认账本」，
///   本地件、不出网）；仅 money 账本可作默认（kcal 口径恒由内置 kcal 账本
///   承接，§5.2②「kcal 行归集到内置 kcal 账本」）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';
import 'local_write_clock.dart';
import 'sync_outbox_writer.dart';

/// ledgers.kind wire 值：money=钱账本（§5.4④）。
const String kLedgerKindMoney = 'money';

/// ledgers.kind wire 值：kcal=热量账本（内置一个、不可删除不可多开，§5.4④）。
const String kLedgerKindKcal = 'kcal';

/// 账本 DAO（§5.4④ ledgers）。
class LedgerDao {
  LedgerDao(this._db, {LocalWriteClock? clock})
      : _clock = clock ?? LocalWriteClock(_db),
        _outbox = SyncOutboxWriter(_db);

  final AppDatabase _db;
  final LocalWriteClock _clock;

  /// 出网入队器（§5.6⑯/§6.2）：seed 真值行同事务读回快照入队。
  final SyncOutboxWriter _outbox;

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

      if (!kinds.contains(kLedgerKindMoney)) {
        await _insertLedger(const _SeedLedger(
          name: '默认账本',
          icon: 'account_balance_wallet',
          currency: 'CNY',
          kind: kLedgerKindMoney,
          sort: 0,
        ));
      }
      if (!kinds.contains(kLedgerKindKcal)) {
        await _insertLedger(const _SeedLedger(
          name: '热量账本',
          icon: 'local_fire_department',
          currency: 'kcal',
          kind: kLedgerKindKcal,
          sort: 1,
        ));
      }

      final setting = await (_db.select(_db.settings)
            ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
          .getSingleOrNull();
      if (setting == null) {
        final moneyRows = await (_db.select(_db.ledgers)
              ..where((t) =>
                  t.kind.equals(kLedgerKindMoney) & t.deletedAt.isNull()))
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
  ///
  /// W15 注（§11.2 多账本）：多账本启用后「默认账本」以 [defaultLedgerId]
  /// （settings 指针）为准，本方法保留为「首个可用 money 账本」的回退口径
  /// （settings 缺失/失效时的兜底，§5.6⑲）。
  Future<Ledger?> defaultMoneyLedger() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) =>
              t.kind.equals(kLedgerKindMoney) &
              t.deletedAt.isNull() &
              t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 内置 kcal 账本（§5.4：不可删除不可多开；seed 保证恰有一个）。
  Future<Ledger?> kcalLedger() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals(kLedgerKindKcal) & t.deletedAt.isNull())
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

  // ── W15 多账本写路径（§11.2 W15、§3.4 多账本 P1、§5.4④） ───────────────

  /// 可用账本（未删**未归档**，按 sort/created_at 稳定排序）：切换抽屉与
  /// 录入账本选择的数据源（§3.4「账本切换抽屉」；归档账本不再出现）。
  Future<List<Ledger>> getActive() {
    final query = _db.select(_db.ledgers)
      ..where((t) => t.deletedAt.isNull() & t.isArchived.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.get();
  }

  /// [getActive] 的响应式形态。
  Stream<List<Ledger>> watchActive() {
    final query = _db.select(_db.ledgers)
      ..where((t) => t.deletedAt.isNull() & t.isArchived.equals(false))
      ..orderBy([
        (t) => OrderingTerm.asc(t.sort),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    return query.watch();
  }

  /// 新建 money 账本（§3.4 多账本 P1、§5.4④）。
  ///
  /// kind 恒为 money——kcal 账本系统内置一个、**不可多开**（§5.4④），本
  /// 方法不提供 kcal 建口（建 kcal 只能走 seed，§5.4/§3.4）。业务行与
  /// outbox 行快照同事务（§6.2 写路径纪律）。
  ///
  /// [currency] 缺省 CNY（人民币记账主场景）；[sort] 缺省追加到末尾。
  Future<Ledger> createLedger({
    required String name,
    String? icon,
    String? currency,
    int? sort,
  }) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '账本名不能为空（§5.4④）');
    }
    return _db.transaction(() async {
      final int effectiveSort = sort ?? await _nextSort();
      return _insertLedger(_SeedLedger(
        name: trimmed,
        icon: icon ?? 'account_balance_wallet',
        currency: currency ?? 'CNY',
        kind: kLedgerKindMoney,
        sort: effectiveSort,
      ));
    });
  }

  /// 重命名账本（§5.4④）。kcal 账本允许改名/改图标（seed 既定口径：已有
  /// 行不动、允许用户后续改名），仅删除/归档/多开被禁止。
  Future<void> renameLedger(String id, {required String name}) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', '账本名不能为空（§5.4④）');
    }
    return _db.transaction(() async {
      final row = await findById(id);
      if (row == null || row.deletedAt != null) {
        throw StateError('renameLedger: 账本不存在或已删 $id（§5.4④）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.ledgers)..where((t) => t.id.equals(id))).write(
        LedgersCompanion(
          name: Value(trimmed),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      await _outbox.enqueueRow('ledgers', id);
    });
  }

  /// 归档/恢复账本（§3.4「账本归档」、§5.4④ is_archived）。
  ///
  /// 归档=软移除：切换抽屉/录入不再出现（getActive 口径），历史账单行原样
  /// 保留（ledger_id 逻辑引用不级联，§5.4⑤/§6.2）。幂等：已是目标态直接
  /// 返回。kcal 账本拒绝归档（§5.4④「不可删除」——归档是删除的产品等价物）。
  ///
  /// 归档当前默认账本时，默认指针自动改指剩余首个可用 money 账本；无可指时
  /// 删除设置项（读取端回退 [defaultMoneyLedger]，空库 seed 兜底，§5.6⑲）。
  Future<void> setLedgerArchived(String id, {required bool archived}) {
    return _db.transaction(() async {
      final row = await findById(id);
      if (row == null || row.deletedAt != null) {
        throw StateError('setLedgerArchived: 账本不存在或已删 $id（§5.4④）');
      }
      if (row.isArchived == archived) {
        return; // 幂等：已是目标态（§6.2 写路径幂等纪律）。
      }
      if (row.kind == kLedgerKindKcal && archived) {
        throw StateError('内置 kcal 账本不可归档/删除（§5.4④）');
      }
      final stamp = await _clock.next();
      await (_db.update(_db.ledgers)..where((t) => t.id.equals(id))).write(
        LedgersCompanion(
          isArchived: Value(archived),
          updatedAt: Value(stamp.updatedAtMs),
          hlc: Value(stamp.hlc),
          revision: Value(row.revision + 1),
        ),
      );
      await _outbox.enqueueRow('ledgers', id);
      if (archived) {
        await _repointDefaultIfCurrent(id);
      }
    });
  }

  /// 切换默认账本（§5.4④ 多账本、§5.6⑲ settings「默认账本」）。
  ///
  /// 仅 money 账本可作默认：默认账本是「记一笔」money 行的归属语义
  /// （§5.2② ledger_id），kcal 行恒归集内置 kcal 账本、无「默认」概念。
  /// settings 为本地件（§5.6⑲），写指针不出网（无 outbox 语义）。
  Future<void> setDefaultLedger(String ledgerId) async {
    final row = await findById(ledgerId);
    if (row == null || row.deletedAt != null) {
      throw StateError('setDefaultLedger: 账本不存在或已删 $ledgerId（§5.4④）');
    }
    if (row.kind != kLedgerKindMoney) {
      throw ArgumentError.value(
        ledgerId,
        'ledgerId',
        '仅 money 账本可设为默认账本（§5.4④ kcal 口径恒内置）',
      );
    }
    if (row.isArchived) {
      throw StateError('已归档账本不可设为默认账本（§3.4 账本归档）');
    }
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: kSettingDefaultLedgerId,
            value: jsonEncode(ledgerId),
          ),
        );
  }

  /// 当前默认账本 id（§5.6⑲）：settings 指向有效（未删未归档的 money）账本
  /// 时用之；设置缺失/失效回退「首个可用 money 账本」（[defaultMoneyLedger]）；
  /// 无任何 money 账本返回 null（seed 保证不发生，防御返回）。
  Future<String?> defaultLedgerId() async {
    final setting = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
        .getSingleOrNull();
    if (setting != null) {
      final id = _decodeDefaultId(setting.value);
      if (id != null) {
        final row = await (_db.select(_db.ledgers)
              ..where((t) => t.id.equals(id) & t.deletedAt.isNull()))
            .getSingleOrNull();
        if (row != null &&
            row.kind == kLedgerKindMoney &&
            !row.isArchived) {
          return row.id;
        }
      }
    }
    return (await defaultMoneyLedger())?.id;
  }

  /// 当前默认账本行（[defaultLedgerId] 的行形式；null 时上层引导建账本）。
  Future<Ledger?> defaultLedger() async {
    final String? id = await defaultLedgerId();
    if (id == null) {
      return null;
    }
    return findById(id);
  }

  /// 默认账本 id 响应式（切换抽屉「默认」徽标的数据源之一）。
  ///
  /// 发 raw 设置值、不做账本有效性校验——有效性由 [defaultLedgerId] 在读取
  /// 点解析；「settings 与 ledgers 同查询」的联表场景（如切换抽屉流）天然
  /// 响应式，无需经此流二次校验。
  Stream<String?> watchDefaultLedgerId() {
    return (_db.select(_db.settings)
          ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
        .watchSingleOrNull()
        .map((row) => row == null ? null : _decodeDefaultId(row.value));
  }

  /// 归档默认账本后的指针重排（§5.4④）：仅当 settings 指向被归档账本时触发。
  Future<void> _repointDefaultIfCurrent(String archivedId) async {
    final setting = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
        .getSingleOrNull();
    if (setting == null) {
      return;
    }
    if (_decodeDefaultId(setting.value) != archivedId) {
      return;
    }
    final remaining = await (_db.select(_db.ledgers)
          ..where((t) =>
              t.kind.equals(kLedgerKindMoney) &
              t.deletedAt.isNull() &
              t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    if (remaining.isEmpty) {
      // 无可用 money 账本：撤下指针（读取端回退 defaultMoneyLedger 的 null
      // → 上层引导建账本；空库 seed 兜底在下次打开补种，§5.4/§5.6⑲）。
      await (_db.delete(_db.settings)
            ..where((t) => t.key.equals(kSettingDefaultLedgerId)))
          .go();
      return;
    }
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: kSettingDefaultLedgerId,
            value: jsonEncode(remaining.first.id),
          ),
        );
  }

  /// settings[default_ledger_id] 的 JSON 字符串值解析（坏值防御性返回 null）。
  String? _decodeDefaultId(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is String ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// 未删账本的最大 sort + 1（新建账本排到末尾，含归档行防碰撞）。
  Future<int> _nextSort() async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.sort)])
          ..limit(1))
        .get();
    return (rows.isEmpty ? -1 : rows.first.sort) + 1;
  }

  Future<Ledger> _insertLedger(_SeedLedger seed) async {
    final stamp = await _clock.next();
    final id = generateUuidV7();
    await _db.into(_db.ledgers).insert(
          LedgersCompanion.insert(
            id: id,
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
    // §6.2：seed 行同为同步真值表，行快照同事务入队（调用方 seedDefaults
    // 已在事务内，§5.6⑯）。
    await _outbox.enqueueRow('ledgers', id);
    return (_db.select(_db.ledgers)..where((t) => t.id.equals(id)))
        .getSingle();
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
