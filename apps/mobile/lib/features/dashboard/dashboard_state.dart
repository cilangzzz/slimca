import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:feature_ledger/feature_ledger.dart'
    show LedgerBudgetItem, parseBudgetSnapshot;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// 有记录日色点流（§3.2 月格 Compact 色点：一点=有记录；数据源=day_summary
/// 投影表 watch，「有记录」口径与 feature_dashboard watchRecordedDays 同款——
/// kcal/spend/income 任一非零）。月历展开态（SlimcaCalendar）直出。
final recordedDaysProvider = StreamProvider<Set<String>>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return database.select(database.daySummaries).watch().map(
        (List<db.DaySummary> rows) => rows
            .where(
              (db.DaySummary r) =>
                  r.kcalIn != 0 ||
                  r.kcalOut != 0 ||
                  r.spendMinor != 0 ||
                  r.incomeMinor != 0,
            )
            .map((db.DaySummary r) => r.date)
            .toSet(),
      );
});

/// 仪表盘当前选中日期状态（§3.2「一切围绕日期」）。
///
/// 设计决策：
/// - 日期一律归一化为本地日历日（时分秒清零），杜绝 UTC 错日——与 §5.1
///   「date = 本地日历日 yyyy-MM-dd，一切聚合按 date 分组」同一纪律；
/// - Riverpod 3 用 NotifierProvider（§10.1 状态选型）；聚合数据经
///   [dashboardDayProvider] 从明细行 reactive stream 重建（§6.1 原则 3）。
final selectedDateProvider =
    NotifierProvider<SelectedDate, DateTime>(SelectedDate.new);

class SelectedDate extends Notifier<DateTime> {
  @override
  DateTime build() => normalizeDate(DateTime.now());

  /// 选中周历条上的某一天。
  void select(DateTime date) => state = normalizeDate(date);

  /// 左右滑切日（§3.2 周历条，共享轴转场 ≤280ms，§2.3 步 7）。
  void shiftByDays(int days) {
    final d = state;
    state = DateTime(d.year, d.month, d.day + days);
  }

  /// 归一化：丢弃时分秒，保留本地年月日。
  static DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 给定日期所在周的周一（周一为一周起点，与文档成文口径 2026-11-16 周一一致）。
  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// 返回 [d] 所在周的 7 天（周一…周日）。
  static List<DateTime> weekOf(DateTime d) {
    final monday = startOfWeek(d);
    return List.generate(
      7,
      (i) => DateTime(monday.year, monday.month, monday.day + i),
    );
  }
}

// ── 当日数据视图模型（§3.2 卡片墙数据源）──────────────────────────

/// 当日聚合（§3.2：摄入/消耗/支出/收入）。
///
/// W2 过渡实现=reactive stream 从明细行实时重建（§6.1 原则 3「投影不同步、
/// 从明细重建」、§10.1 reactive stream 直驱仪表盘）；day_summary 投影表
/// （§5.6⑬）落库后切换为「首帧直读投影表 + 明细流失效重算」，签名不变。
class DashboardDay {
  const DashboardDay({
    required this.kcalIn,
    required this.kcalOut,
    required this.spendMinor,
    required this.incomeMinor,
    required this.entries,
  });

  /// 零值空态（§3.2 卡片墙空态；loading/error 分支共用——无 spinner，§2.3 步 0）。
  const DashboardDay.zero()
      : kcalIn = 0,
        kcalOut = 0,
        spendMinor = 0,
        incomeMinor = 0,
        entries = const [];

  /// 摄入 kcal（calorie 行求和，§2.2）。
  final int kcalIn;

  /// 运动消耗 kcal（burn 行求和，§2.2/§3.5）。
  final int kcalOut;

  /// 支出（分，money 行 out 求和，§2.2）。
  final int spendMinor;

  /// 收入（分，money 行 in 求和）。
  final int incomeMinor;

  /// 当日事件视图（按 created_at 升序；供「今日记录」卡）。
  final List<DashboardEntryView> entries;

  int get netKcal => kcalIn - kcalOut;
}

/// 单条事件视图（主干标题 + 各 facet 行聚合，§5.2）。
class DashboardEntryView {
  const DashboardEntryView({
    required this.entryId,
    required this.title,
    required this.kind,
    required this.kcalIn,
    required this.kcalOut,
    required this.spendMinor,
    required this.incomeMinor,
  });

  final String entryId;

  /// 事件标题（§5.2① title）。
  final String title;

  /// kind wire 值（food/fitness/expense/mixed/note，§5.2①）。
  final String kind;
  final int kcalIn;
  final int kcalOut;
  final int spendMinor;
  final int incomeMinor;
}

/// 当日待办计数（§3.2 卡片墙待办卡、§5.5⑩ todos）。
class DashboardTodoCounts {
  const DashboardTodoCounts({required this.done, required this.total});

  static const DashboardTodoCounts empty =
      DashboardTodoCounts(done: 0, total: 0);

  final int done;
  final int total;
}

// ── 当日数据流 providers ─────────────────────────────────────────

/// 当日聚合流（join：entries 主干 × entry_lines facet 行）。
///
/// 任一表变更即重发——「手动记一笔→环/支出卡即时更新」的数据底座
/// （§11 W2 验收线）。墓碑行/被修正行/作废行不参与聚合
/// （§5.1 删除行、§5.2② status）。
final dashboardDayProvider =
    StreamProvider.autoDispose.family<DashboardDay, String>((ref, date) {
  final database = ref.watch(appDatabaseProvider);
  return _watchDashboardDay(database, date);
});

/// 当日待办计数流（§5.5⑩ date 列；W2 只出计数，待办完整版 W13 接入，§11）。
final dashboardTodosProvider =
    StreamProvider.autoDispose.family<DashboardTodoCounts, String>((ref, date) {
  final database = ref.watch(appDatabaseProvider);
  return (database.select(database.todos)
        ..where((t) => t.date.equals(date) & t.deletedAt.isNull()))
      .watch()
      .map((rows) => DashboardTodoCounts(
            done: rows.where((r) => r.doneAt != null).length,
            total: rows.length,
          ));
});

/// 当日存钱进度流（§3.2 卡片墙第 5 项「上线后自动接入」、§5.6⑬
/// savings_progress 快照、§11.2 W13 任务 2）。
///
/// 快照直出纪律（§3.2「首帧读投影不发起业务查询」）：读 day_summary 投影行
/// 的 savings_progress JSON（goal_id→{contributed_minor,target_minor}），
/// 经 [db.parseSavingsProgress] 解包（防御性：坏形状→空 Map 自愈）；零业务
/// 查询。空 Map = 无当日有效目标（W1-W12 恒 NULL 旧行为即此空态）。
///
/// 响应性：存钱写路径（目标/贡献 DAO，§5.6⑬ W13 实装）在写事务内重算当日
/// 快照 → 本流即时重发 → 进度卡数字变化（任务 5 验收）。
final dashboardSavingsProgressProvider = StreamProvider.autoDispose
    .family<Map<String, db.SavingsProgressEntry>, String>((ref, date) {
  final projection = ref.watch(daySummaryProjectionProvider);
  return projection.watchDaySummary(date).map((row) {
    final json = row?.savingsProgress;
    if (json == null) return const <String, db.SavingsProgressEntry>{};
    return db.parseSavingsProgress(json);
  });
});

/// kcal 账本每日热量目标流（§5.4⑥ budgets：kcal 账本「预算=收入」§2.1③）。
///
/// W2 无预算设置 UI（每日目标 W5-6 接入，§11 W5-6），恒空=未设置；
/// W5-6 写入 budgets 行后本流即时点亮热量环 sweep（§9.3#4）。
final dailyBudgetProvider =
    StreamProvider.autoDispose.family<int, String>((ref, _) {
  final database = ref.watch(appDatabaseProvider);
  final query = database.select(database.budgets).join([
    innerJoin(
        database.ledgers, database.ledgers.id.equalsExp(database.budgets.ledgerId)),
  ])
    ..where(
      database.ledgers.kind.equals('kcal') &
          database.budgets.periodType.equals('daily') &
          database.budgets.deletedAt.isNull(),
    );
  return query.watchSingleOrNull().map(
        (row) => row?.readTable(database.budgets).amount ?? 0,
      );
});

/// 当日预算快照流（§5.6⑬ budget_snapshot；W15 任务 2「支出卡接预算快照
/// v2」——余/超支状态色与 per-分类明细入口的数据面）。
///
/// 快照直出纪律（§3.2）：读 day_summary 投影行的 budget_snapshot JSON，经
/// feature_ledger `parseBudgetSnapshot` 解包（防御性：坏形状→空列表自愈，
/// 与 savings_progress 同一口径），零业务查询。kcal 账本 id 集合用于把
/// 快照条目按账本 kind 分类（kcal 项由热量环口径消费，money 项=支出卡）。
/// 写路径（预算设置/记一笔）同事务重算当日投影 → 本流即时重发。
final dashboardBudgetSnapshotProvider = StreamProvider.autoDispose
    .family<List<LedgerBudgetItem>, String>((ref, date) {
  final projection = ref.watch(daySummaryProjectionProvider);
  final database = ref.watch(appDatabaseProvider);
  return projection.watchDaySummary(date).asyncMap((row) async {
    final kcalLedger = await db.LedgerDao(database).kcalLedger();
    return parseBudgetSnapshot(
      row?.budgetSnapshot,
      daySpendMinor: row?.spendMinor ?? 0,
      dayNetKcal: row?.netKcal ?? 0,
      kcalLedgerIds:
          kcalLedger == null ? const <String>{} : <String>{kcalLedger.id},
    );
  });
});

/// 分类名映射流（§5.4⑤；支出卡 per-分类预算行把快照 category_id 回填为
/// 展示名——分类改名后跟随最新名，逻辑引用不建外键 §5.4⑤）。
final categoryNamesProvider = StreamProvider<Map<String, String>>((ref) {
  return ref
      .watch(ledgerAdminRepositoryProvider)
      .watchCategoryOptions()
      .map((options) => <String, String>{
            for (final option in options) option.id: option.name,
          });
});

/// 当日明细 join 流 → 聚合视图（§5.3 facet 拆行：热量/消耗/金额各行为
/// 独立真值，此处只做只读聚合，不落任何投影表）。
Stream<DashboardDay> _watchDashboardDay(db.AppDatabase database, String date) {
  final query = database.select(database.entries).join([
    leftOuterJoin(
        database.entryLines,
        database.entryLines.entryId.equalsExp(database.entries.id)),
  ])
    ..where(database.entries.date.equals(date) &
        database.entries.deletedAt.isNull())
    ..orderBy([OrderingTerm.asc(database.entries.createdAt)]);

  return query.watch().map((rows) {
    final kcalInByEntry = <String, int>{};
    final kcalOutByEntry = <String, int>{};
    final spendByEntry = <String, int>{};
    final incomeByEntry = <String, int>{};
    final titles = <String, String>{};
    final kinds = <String, String>{};
    final order = <String>[];

    int totalOf(Map<String, int> values) =>
        values.values.fold(0, (sum, v) => sum + v);

    for (final row in rows) {
      final entry = row.readTable(database.entries);
      final line = row.readTableOrNull(database.entryLines);
      if (!titles.containsKey(entry.id)) {
        titles[entry.id] = entry.title;
        kinds[entry.id] = entry.kind;
        order.add(entry.id);
        kcalInByEntry[entry.id] = 0;
        kcalOutByEntry[entry.id] = 0;
        spendByEntry[entry.id] = 0;
        incomeByEntry[entry.id] = 0;
      }
      // 墓碑行/被修正行/作废行不入聚合（§5.1 删除行、§5.2② status）。
      if (line == null ||
          line.deletedAt != null ||
          line.status != LineStatus.active.wire) {
        continue;
      }
      // 行数据类 type/direction 为 wire 字符串（TEXT 列无 converter），
      // 与 wire 值比较走 ==；switch case 需常量，而枚举实例属性 .wire
      // 不可 const 求值，故用 if 链（§5.2② wire 命名与库内其余处一致）。
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

    final entries = <DashboardEntryView>[
      for (final id in order)
        DashboardEntryView(
          entryId: id,
          title: titles[id]!,
          kind: kinds[id]!,
          kcalIn: kcalInByEntry[id]!,
          kcalOut: kcalOutByEntry[id]!,
          spendMinor: spendByEntry[id]!,
          incomeMinor: incomeByEntry[id]!,
        ),
    ];
    return DashboardDay(
      kcalIn: totalOf(kcalInByEntry),
      kcalOut: totalOf(kcalOutByEntry),
      spendMinor: totalOf(spendByEntry),
      incomeMinor: totalOf(incomeByEntry),
      entries: entries,
    );
  });
}
