/// 仪表盘视图模型（§3.2 统一日期仪表盘、§5.6⑬ day_summary 投影行）。
///
/// 本层模型是「投影行 → UI」的轻量映射：标量字段口径与 §5.6⑬ 一一对应，
/// 两个 JSON 快照（budget_snapshot / savings_progress）在此解析为强类型。
/// 解析失败一律回退空值——快照直出不允许因坏数据阻塞首帧（§3.2 快照直出；
/// 自愈由 §5.6 重建规则兜底）。
library;

import 'dart:convert';

/// 预算快照（§5.6⑬ budget_snapshot JSON）。
///
/// v1 形态：`{"kcal_budget": <int kcal>, "spend_budget_minor": <int 分>}`；
/// 未设置的预算在 JSON 中省略（或为 null），解析后即 null。
class DashboardBudgetSnapshot {
  const DashboardBudgetSnapshot({this.kcalBudget, this.spendBudgetMinor});

  /// 热量预算 kcal（§3.4 每日目标；kcal 账本「预算=收入」§2.1③）。
  final int? kcalBudget;

  /// 每日支出预算（分，§3.4）。
  final int? spendBudgetMinor;

  /// 解析预算快照 JSON；空值/坏数据回退全空快照（§3.2 不阻塞直出）。
  static DashboardBudgetSnapshot tryParse(String? json) {
    if (json == null || json.isEmpty) {
      return const DashboardBudgetSnapshot();
    }
    try {
      final Object? decoded = jsonDecode(json);
      if (decoded is! Map) {
        return const DashboardBudgetSnapshot();
      }
      return DashboardBudgetSnapshot(
        kcalBudget: _asInt(decoded['kcal_budget']),
        spendBudgetMinor: _asInt(decoded['spend_budget_minor']),
      );
    } on FormatException {
      // §3.2：坏快照不阻塞直出；投影行由重建规则自愈（§5.6）。
      return const DashboardBudgetSnapshot();
    }
  }

  /// 写侧编码（§5.6⑬ budget_snapshot；只写已设置的键）。
  String encode() => jsonEncode(<String, Object?>{
    if (kcalBudget != null) 'kcal_budget': kcalBudget,
    if (spendBudgetMinor != null) 'spend_budget_minor': spendBudgetMinor,
  });

  static int? _asInt(Object? value) => value is int ? value : null;
}

/// 存钱目标进度单条（§5.6⑬ savings_progress JSON 的 goal 条目，P1 启用）。
class DashboardSavingsProgress {
  const DashboardSavingsProgress({
    required this.goalId,
    required this.contributedMinor,
    required this.targetMinor,
  });

  /// 存钱目标 id（§5.5⑪ savings_goals）。
  final String goalId;

  /// 已存金额（分，§5.1 金额口径）。
  final int contributedMinor;

  /// 目标金额（分）。
  final int targetMinor;

  /// 进度 0-1（§3.6「进度=贡献行求和」，append-only 免冲突 §5.5）。
  double get fraction =>
      targetMinor > 0 ? (contributedMinor / targetMinor).clamp(0.0, 1.0) : 0.0;
}

/// 解析存钱进度快照（§5.6⑬：goal_id→{contributed_minor,target_minor}）。
/// 空值/坏数据回退 null → 存钱卡走占位空态（§3.2「上线后自动接入」）。
Map<String, DashboardSavingsProgress>? parseSavingsProgress(String? json) {
  if (json == null || json.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map) {
      return null;
    }
    final Map<String, DashboardSavingsProgress> result =
        <String, DashboardSavingsProgress>{};
    decoded.forEach((Object? key, Object? value) {
      if (key is String && value is Map) {
        final int? contributed = _asInt(value['contributed_minor']);
        final int? target = _asInt(value['target_minor']);
        if (contributed != null && target != null) {
          result[key] = DashboardSavingsProgress(
            goalId: key,
            contributedMinor: contributed,
            targetMinor: target,
          );
        }
      }
    });
    return result.isEmpty ? null : result;
  } on FormatException {
    return null;
  }
}

int? _asInt(Object? value) => value is int ? value : null;

/// day_summary 单日投影的 UI 映射（§5.6⑬，字段一一对应）。
class DashboardDaySummary {
  const DashboardDaySummary({
    required this.date,
    required this.kcalIn,
    required this.kcalOut,
    required this.netKcal,
    required this.spendMinor,
    required this.incomeMinor,
    required this.todoDone,
    required this.todoTotal,
    required this.budget,
    this.savings,
  });

  /// 本地日历日 `yyyy-MM-dd`（§5.1 日期口径）。
  final String date;

  /// 摄入 kcal（entry_lines type=calorie direction=in，§2.2）。
  final int kcalIn;

  /// 消耗 kcal（burn 行，§2.2）。
  final int kcalOut;

  /// 净 kcal（摄入-消耗）。
  final int netKcal;

  /// 支出（分，money direction=out）。
  final int spendMinor;

  /// 收入（分，money direction=in）。
  final int incomeMinor;

  /// 待办完成数（§5.6⑬ todo_done）。
  final int todoDone;

  /// 待办总数（§5.6⑬ todo_total）。
  final int todoTotal;

  /// 预算余量快照（§5.6⑬ budget_snapshot）。
  final DashboardBudgetSnapshot budget;

  /// 存钱目标进度（§5.6⑬ savings_progress；null=尚无目标，P1 启用）。
  final Map<String, DashboardSavingsProgress>? savings;

  /// 是否有任何钱/热量记录——空态判定依据（§3.2「还没有记录时引导首次录入」；
  /// 待办不算「记录」，记录=统一事件模型的事件，§2.1）。
  bool get hasAnyRecord =>
      kcalIn != 0 || kcalOut != 0 || spendMinor != 0 || incomeMinor != 0;
}
