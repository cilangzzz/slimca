/// 计划域数据模型（§3.5/§3.6/§5.5）。
///
/// 本文件只放纯值对象（无 IO、无 Flutter 依赖）：
/// - [FitnessSeed]：健身记录页种子（Riverpod family key，须实现 ==/hashCode）；
/// - [FitnessSessionDraft]：一次手动健身提交载荷（网关落库入参，§5.5⑦）；
/// - [FitnessFormState]：健身表单状态（含 §3.5 MET 估算派生量）；
/// - [SavingsGoalView]：存钱目标 + 本地聚合进度视图（§5.5⑪⑫）；
/// - [TodoDayInstance]：某日待办实例（W13 重复待办查询时展开的虚拟实例，
///   §3.6/§5.5⑩，不预生成行）；
/// - [SavingsGoalDraft]：新建存钱目标载荷（W13 编辑器 → 网关落库入参）；
/// - [savingsLadderStep]：365/52 周/自定义存钱法的当日格子推算（§3.6）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;

import 'fitness_met_table.dart';
import 'rrule.dart' show dayDiff;

/// 健身记录页种子（family key，§10.1：须实现 ==/hashCode 以保证
/// autoDispose family 在同 seed 下复用状态）。
class FitnessSeed {
  const FitnessSeed({this.initialDate});

  /// 初始归属日 `yyyy-MM-dd`；null=今天（§5.1 日期约定）。
  final String? initialDate;

  @override
  bool operator ==(Object other) =>
      other is FitnessSeed && other.initialDate == initialDate;

  @override
  int get hashCode => initialDate.hashCode;

  @override
  String toString() => 'FitnessSeed(initialDate: $initialDate)';
}

/// 一次手动健身提交载荷（§5.5⑦ fitness_sessions + §5.2 facet 行）。
///
/// 网关 `PlanGateway.submitFitnessSession` 据此同事务落三行：
/// entries(kind=fitness) + entry_lines(type=burn,out) + fitness_sessions。
class FitnessSessionDraft {
  const FitnessSessionDraft({
    required this.date,
    required this.tzOffsetMin,
    required this.activity,
    required this.intensity,
    required this.durationS,
    required this.weightKg,
    this.note,
    this.title,
  });

  /// 归属日 `yyyy-MM-dd`（§5.1：按 date 归日聚合，杜绝 UTC 错日）。
  final String date;

  /// 录入时本地时区偏移（分钟，§5.1）。
  final int tzOffsetMin;

  /// 运动类型（内置 MET 表条目，§3.5）。
  final FitnessActivity activity;

  /// 强度档（§3.5）。
  final FitnessIntensity intensity;

  /// 时长（秒，§5.5⑦ duration_s）。
  final int durationS;

  /// 体重 kg（MET 估算输入，§3.5；落库前持久化进 settings 身体档案）。
  final double weightKg;

  /// 备注（§5.5⑦ note）。
  final String? note;

  /// 事件标题；null=网关按「${activity.name} ${分钟}分钟」拼默认值。
  final String? title;
}

/// 健身表单状态（§3.5 健身手动记录交互规格）。
///
/// 文本输入以 String 持有（输入中态），派生量 [durationMinutes]/[weightKg]
/// 负责解析与边界钳制（1-1440 分钟、25-300 kg），[estimatedKcal] 按
/// §3.5 公式实时重算供 UI ±20% 口径展示。
class FitnessFormState {
  const FitnessFormState({
    required this.date,
    required this.tzOffsetMin,
    required this.activity,
    required this.intensity,
    required this.durationText,
    required this.weightText,
    this.note = '',
    this.submitting = false,
    this.errorText,
  });

  /// 归属日 `yyyy-MM-dd`。
  final String date;

  /// 本地时区偏移（分钟）。
  final int tzOffsetMin;

  /// 选中运动（§3.5 类型选择）。
  final FitnessActivity activity;

  /// 强度档（§3.5）。
  final FitnessIntensity intensity;

  /// 时长输入（分钟，字符串中态）。
  final String durationText;

  /// 体重输入（kg，字符串中态）。
  final String weightText;

  /// 备注。
  final String note;

  /// 提交中（防重复提交）。
  final bool submitting;

  /// 提交失败文案；null=无错误。
  final String? errorText;

  /// 时长分钟数（解析失败/越界返回 null → 估算与提交均不可用）。
  /// 越界钳制到 [1, 1440]（一天上限，§3.5「手动记录一次一段」）。
  int? get durationMinutes {
    final value = int.tryParse(durationText.trim());
    if (value == null || value <= 0) return null;
    if (value > 1440) return null;
    return value;
  }

  /// 体重 kg（解析失败/越界返回 null；[25, 300] 合理区间）。
  double? get weightKg {
    final value = double.tryParse(weightText.trim());
    if (value == null || value < 25 || value > 300) return null;
    return value;
  }

  /// MET 表估算消耗（§3.5 kcal = MET × 体重kg × 时长h）；输入未就绪为 null。
  int? get estimatedKcal {
    final minutes = durationMinutes;
    final weight = weightKg;
    if (minutes == null || weight == null) return null;
    return estimateKcalBurn(
      activity: activity,
      intensity: intensity,
      durationS: minutes * 60,
      weightKg: weight,
    );
  }

  /// 能否提交：时长/体重就绪且未在提交中。
  bool get canSubmit =>
      !submitting && durationMinutes != null && weightKg != null;

  /// 「不改动」哨兵（可空字段沿用 TodoDao.updateDetails 口径：显式传 null
  /// 表示清除，不传表示保留）。
  static const Object _unchanged = Object();

  FitnessFormState copyWith({
    String? date,
    int? tzOffsetMin,
    FitnessActivity? activity,
    FitnessIntensity? intensity,
    String? durationText,
    String? weightText,
    String? note,
    bool? submitting,
    Object? errorText = _unchanged,
  }) =>
      FitnessFormState(
        date: date ?? this.date,
        tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
        activity: activity ?? this.activity,
        intensity: intensity ?? this.intensity,
        durationText: durationText ?? this.durationText,
        weightText: weightText ?? this.weightText,
        note: note ?? this.note,
        submitting: submitting ?? this.submitting,
        errorText: identical(errorText, _unchanged)
            ? this.errorText
            : errorText as String?,
      );
}

/// 存钱目标视图：目标行 + 本地聚合进度（§5.5⑪⑫）。
///
/// 进度=Σ contributions（append-only 只增不改，§6.1 append-first 天然免
/// 冲突）；聚合在网关侧完成，本视图只承载结果。
class SavingsGoalView {
  const SavingsGoalView({
    required this.goal,
    required this.contributedMinor,
  });

  /// 目标行（§5.5⑪ savings_goals）。
  final cdb.SavingsGoal goal;

  /// 已存金额（分，Σ savings_contributions.amount_minor，§5.5⑫）。
  final int contributedMinor;

  /// 进度 0-1（钳制；无目标额为 0）。
  double get progress {
    final target = goal.targetMinor;
    if (target <= 0) return 0;
    final ratio = contributedMinor / target;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  /// 目标金额（元，展示用）。
  String get targetYuan => (goal.targetMinor / 100).toStringAsFixed(2);

  /// 已存金额（元，展示用）。
  String get contributedYuan => (contributedMinor / 100).toStringAsFixed(2);
}

/// 某日待办实例（§3.6 待办完整版 W13、§5.5⑩）。
///
/// **虚拟实例，不落行**（W13 展开策略取舍，见 rrule.dart 文档注释）：重复
/// 待办按 anchor 展开命中当日时，由网关在内存中构造本对象渲染；勾选/编辑
/// 仍作用于 [todo] 基行。完成判定口径（W13 取舍）：
/// - 非重复：done_at 非空即完成（与 W5-6 行为一致）；
/// - 重复实例：done_at 落在实例日（本地日历日）才算该实例完成——基行
///   done_at 是「最近一次勾选」的痕迹，昨日勾选不应让今日实例呈完成态。
class TodoDayInstance {
  const TodoDayInstance({
    required this.todo,
    required this.date,
    required this.done,
    required this.recurring,
    this.repeatLabel,
  });

  /// 基行（§5.5⑩ todos；repeat_rule / rrule_anchor_date / remind_at 携带者）。
  final cdb.Todo todo;

  /// 实例日 `yyyy-MM-dd`；收集箱（date=NULL 基行直出）为 null（§5.5⑩）。
  final String? date;

  /// 当日实例是否完成（口径见类注释）。
  final bool done;

  /// 是否重复待办的（当日）实例。
  final bool recurring;

  /// 重复规则摘要（「每天」「每周一」…，§3.6）；非重复为 null。
  final String? repeatLabel;
}

/// rhythm 列 JSON 形状约定（§5.5⑪ rhythm「阶梯表或每日额」，feature 层定义，
/// DB 层只存 JSON 文本）：
/// - daily365：`{"kind":"daily365","unit_minor":100}` —— 第 N 天存 N×基数；
/// - week52：`{"kind":"week52","unit_minor":1000}` —— 第 N 周存 N×基数；
/// - custom：`{"kind":"custom","daily_amount_minor":500}` —— 每日固定额。
///
/// 目标金额由存钱法推导（§3.6「进度=贡献行求和」的目标锚）：
/// daily365 目标 = 基数 × Σ(1..365) = 基数 × 66795；
/// week52 目标 = 基数 × Σ(1..52) = 基数 × 1378。
const String kSavingsRhythmKindDaily365 = 'daily365';
const String kSavingsRhythmKindWeek52 = 'week52';
const String kSavingsRhythmKindCustom = 'custom';

/// 365 存钱法格子总数（Σ(1..365)=66795）。
const int kDaily365Slots = 365;

/// 52 周存钱法格子总数（Σ(1..52)=1378）。
const int kWeek52Slots = 52;

/// 新建存钱目标载荷（§3.6 存钱目标 P1、§5.5⑪；W13 编辑器 → 网关）。
///
/// - 365/52 周挑战：只填 [name] + [unitMinor]（每格基数），目标金额与
///   rhythm 由存钱法推导；[deadline] 不适用（挑战自带时长）；
/// - 自定义：[name] + [targetMinor]（目标金额）+ [dailyAmountMinor]
///   （每日投币额）+ 可选 [deadline]。
class SavingsGoalDraft {
  const SavingsGoalDraft.daily365({
    required this.name,
    required int this.unitMinor,
    this.startedOn,
  })  : method = cdb.kSavingsMethodDaily365,
        targetMinor = null,
        dailyAmountMinor = null,
        deadline = null,
        assert(unitMinor > 0, '每格基数必须为正（§5.1 金额分口径）');

  const SavingsGoalDraft.week52({
    required this.name,
    required int this.unitMinor,
    this.startedOn,
  })  : method = cdb.kSavingsMethodWeek52,
        targetMinor = null,
        dailyAmountMinor = null,
        deadline = null,
        assert(unitMinor > 0, '每格基数必须为正（§5.1 金额分口径）');

  const SavingsGoalDraft.custom({
    required this.name,
    required int this.targetMinor,
    required int this.dailyAmountMinor,
    this.deadline,
    this.startedOn,
  })  : method = cdb.kSavingsMethodCustom,
        unitMinor = null,
        assert(targetMinor > 0, '目标金额必须为正（§5.1 金额分口径）'),
        assert(dailyAmountMinor > 0, '每日投币额必须为正（§5.1 金额分口径）');

  /// 目标名（§5.5⑪ name）。
  final String name;

  /// §5.5⑪ method wire 值（daily365/week52/custom）。
  final String method;

  /// 每格基数（分）：365/52 周挑战专用。
  final int? unitMinor;

  /// 目标金额（分）：自定义目标专用；挑战目标由格子数推导。
  final int? targetMinor;

  /// 每日投币额（分）：自定义目标专用。
  final int? dailyAmountMinor;

  /// 截止日 `yyyy-MM-dd`（自定义可选；§5.5⑪ deadline）。
  final String? deadline;

  /// 起始日 `yyyy-MM-dd`；null=网关落库时取设备本地今日（§5.5⑪ started_on）。
  final String? startedOn;

  /// rhythm 列 JSON（§5.5⑪，形状见文件顶部约定）。
  String rhythmJson() => switch (method) {
        cdb.kSavingsMethodDaily365 => jsonEncode(<String, Object?>{
            'kind': kSavingsRhythmKindDaily365,
            'unit_minor': unitMinor,
          }),
        cdb.kSavingsMethodWeek52 => jsonEncode(<String, Object?>{
            'kind': kSavingsRhythmKindWeek52,
            'unit_minor': unitMinor,
          }),
        _ => jsonEncode(<String, Object?>{
            'kind': kSavingsRhythmKindCustom,
            'daily_amount_minor': dailyAmountMinor,
          }),
      };

  /// 目标金额（分）：挑战按格子推导，自定义取显式值。
  int get effectiveTargetMinor => switch (method) {
        cdb.kSavingsMethodDaily365 =>
          unitMinor! * (kDaily365Slots * (kDaily365Slots + 1) ~/ 2),
        cdb.kSavingsMethodWeek52 =>
          unitMinor! * (kWeek52Slots * (kWeek52Slots + 1) ~/ 2),
        _ => targetMinor!,
      };
}

/// 当日格子推算（§3.6 投币打卡：当日应投金额与格子号）。
///
/// - daily365：第 N 天 = 起始日起第 N 个自然日，金额 N×基数，slot=N；
/// - week52：第 N 周 = 起始日起第 N 个自然周，金额 N×基数，slot=N；
/// - custom：每日固定额，slot=null；
/// - [day] 早于 started_on（未开跑）或 rhythm 坏 JSON/缺键 → null
///   （§7.4 防御：不可推算时不投币，不猜默认值）；
/// - 格子号越顶（>365/52）钳制到末格并标注「已收官」（挑战时长封顶）。
({int amountMinor, int? slot, String? label})? savingsLadderStep({
  required cdb.SavingsGoal goal,
  required String day,
}) {
  final Object? rhythm;
  try {
    rhythm = jsonDecode(goal.rhythm);
  } on FormatException {
    return null;
  }
  if (rhythm is! Map) return null;
  final unitMinor = rhythm['unit_minor'];
  final dailyAmount = rhythm['daily_amount_minor'];
  // 未开跑（day < started_on）：无格子可投。
  final diff = dayDiff(goal.startedOn, day);
  if (diff < 0) return null;
  switch (goal.method) {
    case cdb.kSavingsMethodDaily365:
      if (unitMinor is! int || unitMinor <= 0) return null;
      final slot = diff >= kDaily365Slots ? kDaily365Slots : diff + 1;
      return (
        amountMinor: slot * unitMinor,
        slot: slot,
        label: slot >= kDaily365Slots ? '第$slot天（已收官）' : '第$slot天',
      );
    case cdb.kSavingsMethodWeek52:
      if (unitMinor is! int || unitMinor <= 0) return null;
      final week = diff ~/ 7;
      final slot = week >= kWeek52Slots ? kWeek52Slots : week + 1;
      return (
        amountMinor: slot * unitMinor,
        slot: slot,
        label: slot >= kWeek52Slots ? '第$slot周（已收官）' : '第$slot周',
      );
    case cdb.kSavingsMethodCustom:
      if (dailyAmount is! int || dailyAmount <= 0) return null;
      return (amountMinor: dailyAmount, slot: null, label: '每日存入');
    default:
      return null;
  }
}
