/// 计划域数据模型（§3.5/§3.6/§5.5）。
///
/// 本文件只放纯值对象（无 IO、无 Flutter 依赖）：
/// - [FitnessSeed]：健身记录页种子（Riverpod family key，须实现 ==/hashCode）；
/// - [FitnessSessionDraft]：一次手动健身提交载荷（网关落库入参，§5.5⑦）；
/// - [FitnessFormState]：健身表单状态（含 §3.5 MET 估算派生量）；
/// - [SavingsGoalView]：存钱目标 + 本地聚合进度视图（§5.5⑪⑫）。
library;

import 'package:core_db/core_db.dart' as cdb;

import 'fitness_met_table.dart';

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
