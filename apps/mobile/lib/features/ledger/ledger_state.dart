/// 账本 Tab 数据流（§3.4 流水列表、§4.2 账本 Tab、§11.1 W5-6「记账完整化」）。
///
/// 设计决策（与 dashboard_state.dart 同一纪律）：
/// - 全量流水 = entries 主干 × entry_lines facet 行 join 的 reactive stream，
///   从明细行重建（§6.1 原则 3「投影不同步、从明细重建」），按 date 倒序
///   分组——任一行落库/墓碑/修正即时重发（W5-6「流水列表实时」验收线）；
/// - 墓碑行/被修正行/作废行不参与聚合（§5.1 删除行、§5.2② status=active）；
/// - facet 行拆分聚合（§5.2/§5.3）：calorie 行→摄入、burn 行→消耗、
///   money 行按 direction→支出/收入（§2.2 只读聚合口径）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

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

  /// 摄入 kcal（calorie 行求和）。
  final int kcalIn;

  /// 消耗 kcal（burn 行求和，§3.5 健身手动记录进流水）。
  final int kcalOut;

  /// 支出（分，money 行 out 求和）。
  final int spendMinor;

  /// 收入（分，money 行 in 求和）。
  final int incomeMinor;
}

/// 按日分组的流水段（§3.4「按日分组的支出列表」）。
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

/// 全量流水按日分组流（§3.4；date 倒序、日内按 created_at 升序）。
final ledgerDayGroupsProvider = StreamProvider<List<LedgerDayGroup>>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return _watchLedgerGroups(database);
});

Stream<List<LedgerDayGroup>> _watchLedgerGroups(db.AppDatabase database) {
  final query = database.select(database.entries).join([
    leftOuterJoin(
        database.entryLines,
        database.entryLines.entryId.equalsExp(database.entries.id)),
  ])
    ..where(database.entries.deletedAt.isNull())
    ..orderBy([
      OrderingTerm.desc(database.entries.date),
      OrderingTerm.asc(database.entries.createdAt),
    ]);

  return query.watch().map((rows) {
    // 只读聚合（§2.2）：per-entry facet 合计 → per-day 分组。
    final order = <String>[];
    final titles = <String, String>{};
    final kinds = <String, String>{};
    final dates = <String, String>{};
    final kcalInByEntry = <String, int>{};
    final kcalOutByEntry = <String, int>{};
    final spendByEntry = <String, int>{};
    final incomeByEntry = <String, int>{};

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
      }
      // 墓碑行/被修正行/作废行不入聚合（§5.1、§5.2②）。
      if (line == null ||
          line.deletedAt != null ||
          line.status != LineStatus.active.wire) {
        continue;
      }
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

    final views = <String, LedgerEntryView>{
      for (final id in order)
        id: LedgerEntryView(
          entryId: id,
          title: titles[id]!,
          kind: kinds[id]!,
          kcalIn: kcalInByEntry[id]!,
          kcalOut: kcalOutByEntry[id]!,
          spendMinor: spendByEntry[id]!,
          incomeMinor: incomeByEntry[id]!,
        ),
    };
    return _foldGroups(order, dates, views);
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
