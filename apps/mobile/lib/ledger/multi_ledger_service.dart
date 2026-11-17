/// W15 多账本壳层服务（§11.2 W15「多账本」主线、§3.4 多账本 P1、§5.4④
/// ledgers）。
///
/// 职责边界（§10.4 分层纪律）——本服务是 core_db/feature_ledger 既有抽象
/// 之上的**薄编排层**，不重复实现任何写路径：
/// - 账本读取：core_db `LedgerDao.watchAll/defaultMoneyLedger`（§5.4④）；
/// - 建账本：core_db `LedgerDao.createLedger`（money 口专用、§6.2 同事务
///   outbox 由 DAO 强制）；
/// - 默认账本指针：core_db `LedgerDao.setDefaultLedger`（§5.6⑲ settings
///   本地件，不出网）；
/// - 预算写入不在本服务——统一走 feature_ledger `LedgerAdminRepository`
///   （budgets 写路径经 core_db BudgetsDao W15 收口：§6.2 同事务 outbox +
///   budget_snapshot v2 投影联动，§5.6⑬），预算设置页经
///   `ledgerAdminRepositoryProvider` 直取。
///
/// 默认账本记忆（W15 任务 3「录入页账本选择器接多账本（默认账本记忆）」）：
/// 记忆真值 = settings[kSettingDefaultLedgerId]（§5.6⑲，core_db 指针）。
/// 指针写入之外，本服务做一次 **sort 桥接**：把默认 money 账本的 `sort`
/// 重排到 money 组首位——录入页账本选择器的缺省预选按「money 账本 sort
/// 升序第一条」解析（feature_capture CaptureController 口径），两处对齐后
/// 「切换默认账本 → 下次录入预选」无需改动 feature_capture；重排只写发生
/// 变化的行（幂等，无写放大），行快照 §6.2 同事务入队。feature_capture
/// 收编 settings 指针读取后，此桥接即可移除（sort 回归纯展示序）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// 多账本服务 provider（§10.4 壳负责装配）。
final multiLedgerServiceProvider = Provider<MultiLedgerService>((ref) {
  return MultiLedgerService(ref.watch(appDatabaseProvider));
});

/// 账本作用域流（§3.4 多账本切换抽屉数据源；LedgerDao 响应式读，§5.4④）。
final ledgerScopesProvider =
    StreamProvider<List<db.Ledger>>((ref) {
  return ref.watch(multiLedgerServiceProvider).watchScopes();
});

/// 默认账本 id 响应式流（§5.6⑲ 指针；切换抽屉「默认」徽标数据源，core_db
/// `LedgerDao.watchDefaultLedgerId` 复用）。
final defaultLedgerIdProvider = StreamProvider<String?>((ref) {
  return db.LedgerDao(ref.watch(appDatabaseProvider)).watchDefaultLedgerId();
});

/// 账本 Tab 当前作用域 id（null=未手动选择，UI 回落到默认 money 账本；
/// money 作用域切换时经 [MultiLedgerService.switchDefaultLedger] 持久化
/// 默认账本记忆，kcal 作用域为视图态、重启后回落默认账本）。
final currentLedgerScopeIdProvider =
    NotifierProvider<CurrentLedgerScopeId, String?>(CurrentLedgerScopeId.new);

class CurrentLedgerScopeId extends Notifier<String?> {
  @override
  String? build() => null;

  /// 切换账本 Tab 作用域（UI 直接调用；持久化与遥测由页面层编排）。
  void select(String id) => state = id;
}

/// W15 多账本壳层服务。
class MultiLedgerService {
  MultiLedgerService(this._db, {db.LocalWriteClock? clock})
      : _clock = clock ?? db.LocalWriteClock(_db),
        _dao = db.LedgerDao(_db),
        _outbox = db.SyncOutboxWriter(_db);

  final db.AppDatabase _db;

  /// 本地写戳（§6.3；sort 桥接行的公共列发戳，core_db 既有抽象复用）。
  final db.LocalWriteClock _clock;

  /// core_db 既有账本 DAO（读取/建档/指针的承担层，§10.3 抽象复用）。
  final db.LedgerDao _dao;

  /// 出网入队器（§5.6⑯/§6.2）：sort 桥接行同事务读回快照入队。
  final db.SyncOutboxWriter _outbox;

  /// 同步真值表名（§5.6⑯ outbox target_table）。
  static const String _kLedgersTable = 'ledgers';

  /// 响应式账本列表（money 组 + 内置 kcal 账本，按 sort 排序）。
  Stream<List<db.Ledger>> watchScopes() => _dao.watchAll();

  /// 新建 money 账本（§5.4④；委托 core_db `LedgerDao.createLedger`——
  /// 名称校验、money 口专用、§6.2 同事务 outbox 全由 DAO 承担），返回新 id。
  Future<String> createMoneyLedger({
    required String name,
    String currency = 'CNY',
  }) async {
    final row = await _dao.createLedger(name: name, currency: currency);
    return row.id;
  }

  /// 切换默认账本（W15 任务 3 默认账本记忆；仅 money 作用域可作默认——
  /// kcal 账本为系统内置视图态，不可删除不可多开 §5.4④，DAO 强制校验）。
  ///
  /// 两步编排：
  /// ① core_db `setDefaultLedger`——settings 指针（§5.6⑲ 记忆真值，幂等）；
  /// ② sort 桥接（见文件头）：默认账本置 money 组首位，录入页选择器
  ///    sort-first 预选与指针一致；只写变化行，行快照 §6.2 同事务入队。
  Future<void> switchDefaultLedger(String ledgerId) async {
    await _dao.setDefaultLedger(ledgerId);
    await _alignDefaultSortFirst(ledgerId);
  }

  /// sort 桥接：默认账本置首、其余按原相对次序顺延（§6.2 单事务）。
  Future<void> _alignDefaultSortFirst(String ledgerId) async {
    await _db.transaction(() async {
      final rows = await (_db.select(_db.ledgers)
            ..where((t) =>
                t.kind.equals('money') &
                t.deletedAt.isNull() &
                t.isArchived.equals(false))
            ..orderBy([
              (t) => OrderingTerm.asc(t.sort),
              (t) => OrderingTerm.asc(t.createdAt),
            ]))
          .get();
      final target = rows.where((r) => r.id == ledgerId).firstOrNull;
      if (target == null) {
        return; // 防御：指针刚指向的账本读不到（并发归档），跳过桥接。
      }
      final ordered = <db.Ledger>[
        target,
        ...rows.where((r) => r.id != ledgerId),
      ];
      for (var i = 0; i < ordered.length; i++) {
        final row = ordered[i];
        if (row.sort == i) continue;
        final stamp = await _clock.next();
        await (_db.update(_db.ledgers)..where((t) => t.id.equals(row.id)))
            .write(
          db.LedgersCompanion(
            sort: Value(i),
            updatedAt: Value(stamp.updatedAtMs),
            hlc: Value(stamp.hlc),
            revision: Value(row.revision + 1),
          ),
        );
        await _outbox.enqueueRow(_kLedgersTable, row.id);
      }
    });
  }
}
