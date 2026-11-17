/// 账本域展示模型（§3.4 账单页/分类管理/日简报 + §5.4⑥ budgets 快照
/// 解析）。全部为不可变值对象；wire 常量与 core_db 列口径一致
/// （§5.1：金额=分、kcal=整数、kind/direction/status 存 TEXT wire 值）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as dom;

/// categories.kind wire 值（§5.4⑤ expense=支出分类 / income=收入分类）。
const String kCategoryKindExpense = 'expense';
const String kCategoryKindIncome = 'income';

/// ledgers.kind wire 值（§5.4④ money=钱账本 / kcal=热量账本）。
const String kLedgerKindMoney = 'money';
const String kLedgerKindKcal = 'kcal';

/// budgets.period_type wire 值（§5.4⑥ daily=P0 / monthly=P1 月度预算，
/// W15 实装 §11.2）。
const String kBudgetPeriodDaily = 'daily';
const String kBudgetPeriodMonthly = 'monthly';

/// 分类色 token 白名单（§8.2 语义 token 纪律：分类色不允许硬编码 hex，
/// 存 token 名，渲染时经 SlimcaTheme 解析——见 ledger_colors.dart）。
const List<String> kLedgerColorTokens = <String>[
  'primary',
  'kcalIn',
  'kcalOut',
  'net',
  'moneyIn',
  'moneyOut',
  'success',
  'warn',
  'danger',
];

/// 规范化分类色 token：null/空白/不在白名单 → 缺省 `primary`。
/// 白名单外的值不能进库——语义 token 体系被绕开后主题切换会失色（§8.2）。
String normalizeLedgerColorToken(String? token) =>
    token != null && kLedgerColorTokens.contains(token)
        ? token
        : kLedgerColorTokens.first;

/// 分类选项（§5.4⑤ categories 行的展示投影；筛选条/管理页/汇总卡共用）。
class LedgerCategoryOption {
  const LedgerCategoryOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.colorToken,
    required this.isPreset,
  });

  final String id;
  final String name;
  final String icon;

  /// expense / income（§5.4⑤ wire 值）。
  final String kind;
  final String colorToken;

  /// 内置分类不可删（§5.4⑤ is_preset）。
  final bool isPreset;
}

/// 账单流中的一行（entry_lines 展示投影；§5.3 facet 行）。
class LedgerBillLine {
  const LedgerBillLine({
    required this.lineId,
    required this.entryId,
    required this.type,
    required this.amount,
    required this.direction,
    required this.categoryId,
    required this.categoryName,
    required this.colorToken,
  });

  final String lineId;
  final String entryId;

  /// money / calorie / burn（dom.LineType）。
  final dom.LineType type;

  /// money 行=分、kcal 行=kcal 整数（§5.1）。
  final int amount;
  final dom.LineDirection direction;
  final String? categoryId;
  final String? categoryName;
  final String? colorToken;
}

/// 账单流中的一条账（entries 主干 + 归并后的活跃行；§5.2①）。
class LedgerBillEntry {
  LedgerBillEntry({
    required this.entryId,
    required this.date,
    required this.kind,
    required this.title,
    required this.status,
    required List<LedgerBillLine> lines,
  }) : lines = List<LedgerBillLine>.unmodifiable(lines);

  final String entryId;

  /// 归属自然日 `yyyy-MM-dd`（§5.1 本地自然日）。
  final String date;
  final dom.EntryKind kind;
  final String title;
  final dom.EntryStatus status;
  final List<LedgerBillLine> lines;

  /// 本账支出（分；只计 money-out 行，§5.3）。
  int get spendMinor => _sumLines(dom.LineType.money, dom.LineDirection.outcome);

  /// 本账收入（分；只计 money-in 行）。
  int get incomeMinor =>
      _sumLines(dom.LineType.money, dom.LineDirection.income);

  /// 本账摄入热量（kcal 整数；只计 calorie-in 行）。
  int get kcalIn =>
      _sumLines(dom.LineType.calorie, dom.LineDirection.income);

  /// 本账运动消耗热量（kcal 整数；只计 burn-out 行）。
  int get kcalOut =>
      _sumLines(dom.LineType.burn, dom.LineDirection.outcome);

  /// 本账净热量（摄入-消耗，§2.1③）。
  int get netKcal => kcalIn - kcalOut;

  int _sumLines(dom.LineType type, dom.LineDirection direction) => lines
      .where((LedgerBillLine line) => line.type == type && line.direction == direction)
      .fold(0, (int sum, LedgerBillLine line) => sum + line.amount);
}

/// 一个自然日的账单分组（§3.4 按日分组；日期降序由仓库保证）。
class LedgerDayGroup {
  const LedgerDayGroup({
    required this.date,
    required this.entries,
  });

  final String date;
  final List<LedgerBillEntry> entries;

  /// 当日支出合计（分；筛选态下为过滤后合计，由仓库按过滤行聚合）。
  int get spendMinor => entries.fold(
        0,
        (int sum, LedgerBillEntry entry) => sum + entry.spendMinor,
      );

  /// 当日收入合计（分）。
  int get incomeMinor => entries.fold(
        0,
        (int sum, LedgerBillEntry entry) => sum + entry.incomeMinor,
      );
}

/// 月度分类汇总行（§3.4 统计雏形：per-category 求和，money 行）。
/// [categoryId] 为 null 表示"未分类"行。
class LedgerCategorySum {
  const LedgerCategorySum({
    required this.categoryId,
    required this.categoryName,
    required this.colorToken,
    required this.spendMinor,
    required this.incomeMinor,
  });

  final String? categoryId;
  final String? categoryName;
  final String? colorToken;
  final int spendMinor;
  final int incomeMinor;
}

/// 预算快照中的一项（§5.6⑬ budget_snapshot；amount/used/remaining 口径：
/// money=分、kcal=kcal 整数；used 已由投影算好——money=窗口内支出、
/// kcal=窗口内摄入-消耗）。
///
/// W15 v2（§11.2）：扩展 periodType/periodStart/periodEnd/carryOver——
/// daily 项缺省即为 daily（v1 快照无周期键时默认口径不变）。
class LedgerBudgetItem {
  const LedgerBudgetItem({
    required this.ledgerId,
    required this.categoryId,
    required this.isKcal,
    required this.amount,
    required this.used,
    required this.remaining,
    this.periodType = kBudgetPeriodDaily,
    this.periodStart,
    this.periodEnd,
    this.carryOver = false,
  });

  /// 目标账本 id（快照键 ledger_id）；dashboard v1 平铺形态无此键 → null。
  final String? ledgerId;

  /// null=按日总目标（§5.4⑥ budgets.category_id NULL=总预算）。
  final String? categoryId;

  /// 是否 kcal 口径目标（kcal 账本=收入预算、吃=支出，§2.1③）。
  final bool isKcal;
  final int amount;
  final int used;
  final int remaining;

  /// 周期（§5.4⑥ daily/monthly；v1 快照项缺省 daily——向后兼容）。
  final String periodType;

  /// 月度周期窗口 [periodStart, periodEnd)（v2 快照 monthly 项携带；
  /// daily/v1 为 null）。
  final String? periodStart;
  final String? periodEnd;

  /// 结转开关（§5.4⑥ carry_over；monthly 语义，v1/快照缺省 false）。
  final bool carryOver;

  bool get isOver => remaining < 0;

  /// 是否分类级目标（§5.4⑥ category_id 非空）。
  bool get isCategoryGoal => categoryId != null;

  /// 是否月度预算（§5.4⑥ monthly，W15）。
  bool get isMonthly => periodType == kBudgetPeriodMonthly;
}

/// 日简报（§3.4：今日收支/热量摘要卡；数据走 day_summary 投影直读，
/// §3.2 首帧直读本表、零业务查询）。
class LedgerDayBriefing {
  const LedgerDayBriefing({
    required this.date,
    required this.kcalIn,
    required this.kcalOut,
    required this.netKcal,
    required this.spendMinor,
    required this.incomeMinor,
    required this.budgets,
  });

  final String date;

  /// day_summary 投影列（§5.6⑬）。
  final int kcalIn;
  final int kcalOut;
  final int netKcal;
  final int spendMinor;
  final int incomeMinor;

  /// budget_snapshot 解析结果（§5.6⑬）。
  final List<LedgerBudgetItem> budgets;

  /// 按日总支出目标（第一条总预算 money 项；daily 口径——月度预算不混入
  /// 「每日目标」行，§5.4⑥ 周期语义 W15）。
  LedgerBudgetItem? get spendBudget {
    for (final LedgerBudgetItem item in budgets) {
      if (!item.isKcal &&
          item.categoryId == null &&
          item.periodType == kBudgetPeriodDaily) {
        return item;
      }
    }
    return null;
  }

  /// 按日总热量目标（第一条总预算 kcal 项；daily 口径，§5.4⑥）。
  LedgerBudgetItem? get kcalBudget {
    for (final LedgerBudgetItem item in budgets) {
      if (item.isKcal &&
          item.categoryId == null &&
          item.periodType == kBudgetPeriodDaily) {
        return item;
      }
    }
    return null;
  }

  /// 当日是否有任何记录（无记录时不渲染目标行，提示而非报错 §3.4）。
  bool get hasAnyRecord =>
      kcalIn != 0 || kcalOut != 0 || spendMinor != 0 || incomeMinor != 0;
}

/// 分类管理页的每日目标行（budgets period=daily 行 + 账本/分类名回填）。
class LedgerDailyBudget {
  const LedgerDailyBudget({
    required this.id,
    required this.ledgerId,
    required this.ledgerKind,
    required this.categoryId,
    required this.categoryName,
    required this.amount,
    this.periodType = kBudgetPeriodDaily,
    this.dayOfMonthStart = 1,
    this.carryOver = false,
  });

  final String id;
  final String ledgerId;

  /// money / kcal（§5.4④；kcal 账本的目标按 kcal 整数口径）。
  final String ledgerKind;

  /// null=按日总目标（§5.4⑥）。
  final String? categoryId;
  final String? categoryName;
  final int amount;

  /// 周期（§5.4⑥；W15 monthly 预算行复用本模型回填管理页）。
  final String periodType;

  /// 月度周期起点（1..28，§5.4⑥；daily 恒 1）。
  final int dayOfMonthStart;

  /// 结转开关（§5.4⑥ carry_over；monthly 语义）。
  final bool carryOver;

  bool get isKcalGoal => ledgerKind == kLedgerKindKcal;

  /// 是否分类级目标（§5.4⑥ category_id 非空）。
  bool get isCategoryGoal => categoryId != null;

  /// 是否月度预算（§5.4⑥ monthly，W15）。
  bool get isMonthly => periodType == kBudgetPeriodMonthly;
}

/// 解析 day_summaries.budget_snapshot（§5.6⑬）为预算项列表。
///
/// 兼容**三形态**（W15 v2 升级期，§11.2）：
/// 1. core_db `DaySummaryProjection` **v2** 形态（W15）：
///    `{"v":2,"daily":[{ledger_id,category_id,amount,used,remaining}],
///      "monthly":[…,{carry_over,period_start,period_end}]}`；
/// 2. core_db `DaySummaryProjection` **v1** 形态（W2）：
///    `{"daily":[…]}`——daily 项缺省 daily 周期，向后兼容；
/// 3. feature_dashboard v1 平铺形态 `{"kcal_budget":int,"spend_budget_minor":int}`——
///    旧快照没有 used/明细，按当日投影值合成 used/remaining（升级期兼容，
///    投影重算后回归形态 1/2）。
///
/// 解析失败（空/坏 JSON/形态不符）一律返回空列表——快照是派生数据，
/// 简报卡退化为"目标未设置"提示而非崩溃（§3.4 体验口径）。
List<LedgerBudgetItem> parseBudgetSnapshot(
  String? snapshotJson, {
  required int daySpendMinor,
  required int dayNetKcal,
  Set<String> kcalLedgerIds = const <String>{},
}) {
  if (snapshotJson == null || snapshotJson.isEmpty) {
    return const <LedgerBudgetItem>[];
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(snapshotJson);
  } on FormatException {
    return const <LedgerBudgetItem>[];
  }
  if (decoded is! Map) {
    return const <LedgerBudgetItem>[];
  }
  final Object? daily = decoded['daily'];
  final Object? monthly = decoded['monthly'];
  if (daily is List || monthly is List) {
    final List<LedgerBudgetItem> items = <LedgerBudgetItem>[];
    if (daily is List) {
      for (final Object? raw in daily) {
        // v2 daily 项与 v1 逐键一致；periodType 缺省 daily（向后兼容）。
        final LedgerBudgetItem? item =
            _parseSnapshotItem(raw, kcalLedgerIds, kBudgetPeriodDaily);
        if (item != null) {
          items.add(item);
        }
      }
    }
    if (monthly is List) {
      for (final Object? raw in monthly) {
        if (raw is! Map) {
          continue;
        }
        final LedgerBudgetItem? item =
            _parseSnapshotItem(raw, kcalLedgerIds, kBudgetPeriodMonthly);
        if (item == null) {
          continue;
        }
        items.add(LedgerBudgetItem(
          ledgerId: item.ledgerId,
          categoryId: item.categoryId,
          isKcal: item.isKcal,
          amount: item.amount,
          used: item.used,
          remaining: item.remaining,
          periodType: kBudgetPeriodMonthly,
          periodStart: raw['period_start'] is String
              ? raw['period_start'] as String
              : null,
          periodEnd:
              raw['period_end'] is String ? raw['period_end'] as String : null,
          carryOver: raw['carry_over'] == true,
        ));
      }
    }
    return items;
  }
  // 平铺形态（feature_dashboard v1）：合成单条总目标项。
  final List<LedgerBudgetItem> items = <LedgerBudgetItem>[];
  final int? kcalBudget = _asInt(decoded['kcal_budget']);
  if (kcalBudget != null) {
    items.add(LedgerBudgetItem(
      ledgerId: null,
      categoryId: null,
      isKcal: true,
      amount: kcalBudget,
      used: dayNetKcal,
      remaining: kcalBudget - dayNetKcal,
    ));
  }
  final int? spendBudget = _asInt(decoded['spend_budget_minor']);
  if (spendBudget != null) {
    items.add(LedgerBudgetItem(
      ledgerId: null,
      categoryId: null,
      isKcal: false,
      amount: spendBudget,
      used: daySpendMinor,
      remaining: spendBudget - daySpendMinor,
    ));
  }
  return items;
}

/// 快照单项解析（amount/used 缺失或类型不符的异常项跳过；§5.6⑬ 快照形状）。
LedgerBudgetItem? _parseSnapshotItem(
  Object? raw,
  Set<String> kcalLedgerIds,
  String periodType,
) {
  if (raw is! Map) {
    return null;
  }
  final int? amount = _asInt(raw['amount']);
  final int? used = _asInt(raw['used']);
  if (amount == null || used == null) {
    return null;
  }
  final String? ledgerId =
      raw['ledger_id'] is String ? raw['ledger_id'] as String : null;
  final String? categoryId =
      raw['category_id'] is String ? raw['category_id'] as String : null;
  return LedgerBudgetItem(
    ledgerId: ledgerId,
    categoryId: categoryId,
    isKcal: ledgerId != null && kcalLedgerIds.contains(ledgerId),
    amount: amount,
    used: used,
    remaining: _asInt(raw['remaining']) ?? amount - used,
    periodType: periodType,
  );
}

/// 账本切换/管理选项（§5.4④ ledgers 行的展示投影 + 默认徽标，§3.4 多账本
/// 切换抽屉 W15）。kind/kLedgerKind* 与 core_db wire 值一致。
class LedgerSwitchOption {
  const LedgerSwitchOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.currency,
    required this.kind,
    required this.isDefault,
  });

  final String id;
  final String name;
  final String icon;

  /// money 账本=币种（CNY…）；kcal 账本=kcal（§5.4④）。
  final String currency;
  final String kind;

  /// 是否当前默认账本（settings[default_ledger_id] 指向，§5.6⑲）。
  final bool isDefault;

  bool get isKcalLedger => kind == kLedgerKindKcal;
}

/// JSON 数值容错读取（投影侧数字可能被序列化为 num/int，越界/缺失 → null）。
int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
