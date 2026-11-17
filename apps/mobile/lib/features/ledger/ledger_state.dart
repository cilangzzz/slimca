/// 账本 Tab 数据流（§3.4 流水列表、§4.2 账本 Tab、§11.1 W5-6「记账完整化」；
/// W15 多账本口径升级 §11.2「多账本」、§3.4 多账本 P1）。
///
/// 设计决策（与 dashboard_state.dart 同一纪律）：
/// - 全量流水 = entries 主干 × entry_lines facet 行 join 的 reactive stream，
///   从明细行重建（§6.1 原则 3「投影不同步、从明细重建」），按 date 倒序
///   分组——任一行落库/墓碑/修正即时重发（W5-6「流水列表实时」验收线）；
/// - 墓碑行/被修正行/作废行不参与聚合（§5.1 删除行、§5.2② status=active）；
/// - facet 行拆分聚合（§5.2/§5.3）：calorie 行→摄入、burn 行→消耗、
///   money 行按 direction→支出/收入（§2.2 只读聚合口径）；
/// - W15 账本作用域口径（§5.2② 行级 ledger_id）：money 账本视图只聚合归属
///   该账本的 money 行；kcal 账本视图只聚合归集到内置 kcal 账本的 calorie/
///   burn 行——「一件事多维度」事件仍按行归属拆账（§5.3 facet 行同步正确性
///   的只读面）；分类筛选时数字在过滤后的行上重算（筛选态自洽，§3.4）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// 账单流查询（账本作用域 + 分类筛选；Riverpod family 参数，值对象相等性）。
///
/// - [ledgerId] null = 不按账本过滤（空库无作用域时的兜底口径，与 W5-6
///   全量流水行为一致）；
/// - [scopeKind] = money/kcal（§5.4④ wire 值），决定聚合哪些 facet 行；
/// - [categoryId] null = 不筛选；非空时只聚合该分类的行（§3.4 分类筛选）。
class LedgerBillQuery {
  const LedgerBillQuery({
    required this.ledgerId,
    required this.scopeKind,
    this.categoryId,
  });

  /// 账本 id（§5.4④ ledgers.id）；null=全量（兜底）。
  final String? ledgerId;

  /// money / kcal（§5.4④）。
  final String scopeKind;

  /// 分类筛选（§5.4⑤ categories.id）；null=不筛选。
  final String? categoryId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LedgerBillQuery &&
          other.ledgerId == ledgerId &&
          other.scopeKind == scopeKind &&
          other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(ledgerId, scopeKind, categoryId);
}

/// 账本 Tab 当前分类筛选（仪表盘支出卡「per-分类明细入口」预选后跳转用；
/// 全局非 autoDispose——导航跨 Tab 保持筛选态）。
final ledgerCategoryFilterProvider =
    NotifierProvider<LedgerCategoryFilter, String?>(LedgerCategoryFilter.new);

class LedgerCategoryFilter extends Notifier<String?> {
  @override
  String? build() => null;

  /// 选择/清除分类（null=全部）。
  void select(String? categoryId) => state = categoryId;
}

/// 单条流水视图（主干标题 + 各 facet 行聚合，§5.2）。
class LedgerEntryView {
  const LedgerEntryView({
    required this.entryId,
    required this.title,
    required this.kind,
    required this.kcalIn,
    required this.kcalOut,
    required this.spendMinor,
    required this.incomeMinor,
  });

  /// 事件主干 id（entries.id；点条目进编辑抽屉 §3.4）。
  final String entryId;

  /// 标题（§5.2① title 一句话描述）。
  final String title;

  /// kind wire 值（food/fitness/expense/mixed/note，§5.2①）。
  final String kind;

  /// 摄入 kcal（calorie 行求和；作用域/筛选内）。
  final int kcalIn;

  /// 消耗 kcal（burn 行求和，§3.5 健身手动记录进流水；作用域/筛选内）。
  final int kcalOut;

  /// 支出（分，money 行 out 求和；作用域/筛选内）。
  final int spendMinor;

  /// 收入（分，money 行 in 求和；作用域/筛选内）。
  final int incomeMinor;
}

/// 按日分组的流水段（§3.4「按日分组的支出列表」；合计=作用域/筛选内口径）。
class LedgerDayGroup {
  const LedgerDayGroup({
    required this.date,
    required this.entries,
    required this.spendMinor,
    required this.incomeMinor,
    required this.kcalIn,
    required this.kcalOut,
  });

  /// 归属日 yyyy-MM-dd（§5.1）。
  final String date;

  /// 当日事件（按 created_at 升序）。
  final List<LedgerEntryView> entries;

  /// 当日支出合计（分）。
  final int spendMinor;

  /// 当日收入合计（分）。
  final int incomeMinor;

  /// 当日摄入合计（kcal）。
  final int kcalIn;

  /// 当日消耗合计（kcal）。
  final int kcalOut;
}

/// 作用域流水按日分组流（§3.4；date 倒序、日内按 created_at 升序；
/// family 按 [LedgerBillQuery] 区分——账本切换/分类筛选即时换算重发）。
final ledgerDayGroupsProvider =
    StreamProvider.family<List<LedgerDayGroup>, LedgerBillQuery>((ref, query) {
  final database = ref.watch(appDatabaseProvider);
  return _watchLedgerGroups(database, query);
});

/// 行是否落入查询口径（§5.2② 行级 ledger_id 归账 + §3.4 分类筛选）。
bool _lineInQuery(db.EntryLine line, LedgerBillQuery query) {
  // 分类筛选：命中行的分类必须一致（未分类行只在「全部」态出现）。
  if (query.categoryId != null && line.categoryId != query.categoryId) {
    return false;
  }
  final ledgerId = query.ledgerId;
  if (ledgerId == null) {
    return true; // 兜底口径：不过滤账本（空库无作用域）
  }
  final type = line.type;
  if (query.scopeKind == 'kcal') {
    // kcal 账本视图：摄入/消耗行归集内置 kcal 账本（§5.2②）。
    return (type == LineType.calorie.wire || type == LineType.burn.wire) &&
        line.ledgerId == ledgerId;
  }
  // money 账本视图：金额行归属该账本（§5.4④）。
  return type == LineType.money.wire && line.ledgerId == ledgerId;
}

Stream<List<LedgerDayGroup>> _watchLedgerGroups(
  db.AppDatabase database,
  LedgerBillQuery query,
) {
  final dbQuery = database.select(database.entries).join([
    leftOuterJoin(
        database.entryLines,
        database.entryLines.entryId.equalsExp(database.entries.id)),
  ])
    ..where(database.entries.deletedAt.isNull())
    ..orderBy([
      OrderingTerm.desc(database.entries.date),
      OrderingTerm.asc(database.entries.createdAt),
    ]);

  return dbQuery.watch().map((rows) {
    // 只读聚合（§2.2）：per-entry「口径内」facet 合计 → per-day 分组。
    final order = <String>[];
    final titles = <String, String>{};
    final kinds = <String, String>{};
    final dates = <String, String>{};
    final kcalInByEntry = <String, int>{};
    final kcalOutByEntry = <String, int>{};
    final spendByEntry = <String, int>{};
    final incomeByEntry = <String, int>{};
    final inScopeByEntry = <String, bool>{};

    for (final row in rows) {
      final entry = row.readTable(database.entries);
      final line = row.readTableOrNull(database.entryLines);
      if (!titles.containsKey(entry.id)) {
        titles[entry.id] = entry.title;
        kinds[entry.id] = entry.kind;
        dates[entry.id] = entry.date;
        order.add(entry.id);
        kcalInByEntry[entry.id] = 0;
        kcalOutByEntry[entry.id] = 0;
        spendByEntry[entry.id] = 0;
        incomeByEntry[entry.id] = 0;
        inScopeByEntry[entry.id] = false;
      }
      // 墓碑行/被修正行/作废行不入聚合（§5.1、§5.2②）。
      if (line == null ||
          line.deletedAt != null ||
          line.status != LineStatus.active.wire) {
        continue;
      }
      // 口径外行：既不计入聚合，也不让事件入列（账单口径一致，§3.4）。
      if (!_lineInQuery(line, query)) {
        continue;
      }
      inScopeByEntry[entry.id] = true;
      // wire 值比较走 ==（TEXT 列无 converter，与 dashboard 同口径）。
      final type = line.type;
      if (type == LineType.calorie.wire) {
        kcalInByEntry[entry.id] = kcalInByEntry[entry.id]! + line.amount;
      } else if (type == LineType.burn.wire) {
        kcalOutByEntry[entry.id] = kcalOutByEntry[entry.id]! + line.amount;
      } else if (type == LineType.money.wire) {
        if (line.direction == LineDirection.income.wire) {
          incomeByEntry[entry.id] = incomeByEntry[entry.id]! + line.amount;
        } else {
          spendByEntry[entry.id] = spendByEntry[entry.id]! + line.amount;
        }
      }
    }

    // 只保留口径内事件（该账本/该分类下确有产出行）。
    final views = <String, LedgerEntryView>{};
    for (final id in order) {
      if (!inScopeByEntry[id]!) {
        continue;
      }
      views[id] = LedgerEntryView(
        entryId: id,
        title: titles[id]!,
        kind: kinds[id]!,
        kcalIn: kcalInByEntry[id]!,
        kcalOut: kcalOutByEntry[id]!,
        spendMinor: spendByEntry[id]!,
        incomeMinor: incomeByEntry[id]!,
      );
    }
    final scopedOrder =
        order.where((id) => inScopeByEntry[id]!).toList(growable: false);
    return _foldGroups(scopedOrder, dates, views);
  });
}

/// 按日累加折叠（拆出独立函数避免 map 内可变累加的别名陷阱）。
List<LedgerDayGroup> _foldGroups(
  List<String> order,
  Map<String, String> dates,
  Map<String, LedgerEntryView> views,
) {
  final indexByDate = <String, int>{};
  final groups = <LedgerDayGroup>[];
  for (final id in order) {
    final date = dates[id]!;
    final view = views[id]!;
    final index = indexByDate.putIfAbsent(date, () {
      groups.add(LedgerDayGroup(
        date: date,
        entries: [],
        spendMinor: 0,
        incomeMinor: 0,
        kcalIn: 0,
        kcalOut: 0,
      ));
      return groups.length - 1;
    });
    final prev = groups[index];
    groups[index] = LedgerDayGroup(
      date: date,
      entries: [...prev.entries, view],
      spendMinor: prev.spendMinor + view.spendMinor,
      incomeMinor: prev.incomeMinor + view.incomeMinor,
      kcalIn: prev.kcalIn + view.kcalIn,
      kcalOut: prev.kcalOut + view.kcalOut,
    );
  }
  return groups;
}
