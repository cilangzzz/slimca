/// 健身计划模板与周排期模型（§3.5 健身计划 P1 留存钩子、§5.5⑧⑨、
/// §11.2 W14 主线任务 1）。
///
/// 本文件只放纯值对象与解析（无 IO、无 Flutter 依赖，与 plan_models.dart
/// 同一口径）：
/// - [PlanExercise]：单个动作的排期参数（动作名/组数/目标次数/目标重量/
///   组间休息秒），即 §5.5⑧ exercises 列 JSON 数组的元素；
/// - [FitnessPlanTemplate]：exercises 列 JSON 的编解码（feature 层约定形状，
///   DB 层只存文本；解析防御见 [FitnessPlanTemplate.decode]，§7.4）；
/// - 周排期掩码辅助：§5.5⑧ weekday_mask「bit0=周一…bit6=周日」。
///
/// 「计划日自动生成会话」取舍（§3.5）：W14 收敛为「排期日一键开练」——
/// 不预生成空会话行（未训练日不留垃圾行），与 W13 重复待办「查询时展开、
/// 不预生成行」同一取向；会话行仅由用户开练动作创建（§5.5⑦）。
library;

import 'dart:convert';

/// §5.5⑧ exercises 列 JSON 的形状版本（前向兼容锚：新增字段只加键）。
const int kFitnessPlanTemplateVer = 1;

/// §5.5⑦ fitness_sessions.type：计划实例会话（模板排期发起）。
const String kFitnessSessionTypeTemplateInstance = 'template_instance';

/// §5.5⑦ fitness_sessions.source：计划会话来源。
const String kFitnessSessionSourcePlan = 'plan';

/// 计划实例的 MET 估算活动（§3.5 kcal = MET × 体重kg × 时长h；模板语义=
/// 组数/次数/重量配比，属力量域，取内置表「力量训练」中档，§11.2 W14）。
const String kFitnessPlanMetActivityId = 'strength_training';

/// 单个动作的排期参数（§5.5⑧ exercises JSON 数组元素）。
///
/// 字段口径：
/// - [name]：动作名。§5.5⑨ exercise_ref「动作库 id 或名称」——W14 动作库
///   （自建 800+ 集合）未上线，v1 直接落名称、落库时写入 exercise_sets.exercise_ref；
/// - [sets]：组数（≥1）；
/// - [targetReps]：目标次数（≥1）；
/// - [targetWeightKgX10]：目标重量 ×10 定点整数（§5.5⑨ weight_kg_x10 口径，
///   避免浮点同步问题；自重/徒手动作取 0）；
/// - [restS]：组间休息秒（组间计时器读数来源，§3.5「组间计时器」；0=不计时）。
class PlanExercise {
  const PlanExercise({
    required this.name,
    required this.sets,
    required this.targetReps,
    required this.targetWeightKgX10,
    required this.restS,
  })  : assert(sets >= 1, '组数必须 ≥1（§5.5⑧ 组数）'),
        assert(targetReps >= 1, '目标次数必须 ≥1（§5.5⑧ 目标次数）'),
        assert(targetWeightKgX10 >= 0, '目标重量必须非负（§5.5⑨ 定点 ×10）'),
        assert(restS >= 0, '组间休息秒必须非负（§3.5 组间计时器）');

  /// 动作名（§5.5⑨ exercise_ref，v1 名称口径）。
  final String name;

  /// 组数。
  final int sets;

  /// 目标次数。
  final int targetReps;

  /// 目标重量 ×10 定点（§5.5⑨ weight_kg_x10，避免浮点同步问题）。
  final int targetWeightKgX10;

  /// 组间休息秒（组间计时器读数，§3.5）。
  final int restS;

  /// 目标重量 kg（展示/开练预填用；定点 ×10 的浮点还原）。
  double get targetWeightKg => targetWeightKgX10 / 10;

  /// 行摘要（计划卡动作清单展示）。
  String get summaryLine {
    final weight = targetWeightKgX10 == 0
        ? '自重'
        : '${targetWeightKgX10 % 10 == 0 ? targetWeightKgX10 ~/ 10 : targetWeightKg.toStringAsFixed(1)}kg';
    return '$name $sets组×$targetReps次 $weight 休${restS}s';
  }

  /// JSON 行快照（§5.5⑧ exercises 数组元素；键名 snake_case 与 §5.5⑨ 列名同构）。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'sets': sets,
        'target_reps': targetReps,
        'target_weight_kg_x10': targetWeightKgX10,
        'rest_s': restS,
      };

  /// JSON 行解析（§7.4 防御：形状不符返回 null，由 [FitnessPlanTemplate.decode]
  /// 逐行过滤，坏行不炸整模板）。
  static PlanExercise? tryParseJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final sets = raw['sets'];
    final reps = raw['target_reps'];
    final weight = raw['target_weight_kg_x10'];
    final rest = raw['rest_s'];
    // 缺省口径：数值字段缺失/类型不符时回退保守默认（组 1 次 10 自重 0 不休息），
    // 保证坏行可渲染、不静默丢动作（§7.4「解析失败自动降级」精神）。
    return PlanExercise(
      name: name.trim(),
      sets: sets is int && sets >= 1 ? sets : 1,
      targetReps: reps is int && reps >= 1 ? reps : 10,
      targetWeightKgX10: weight is int && weight >= 0 ? weight : 0,
      restS: rest is int && rest >= 0 ? rest : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlanExercise &&
      other.name == name &&
      other.sets == sets &&
      other.targetReps == targetReps &&
      other.targetWeightKgX10 == targetWeightKgX10 &&
      other.restS == restS;

  @override
  int get hashCode => Object.hash(
      name, sets, targetReps, targetWeightKgX10, restS);

  @override
  String toString() => 'PlanExercise($summaryLine)';
}

/// 健身计划模板（§5.5⑧ exercises 列的 feature 层视图）。
class FitnessPlanTemplate {
  const FitnessPlanTemplate({required this.exercises});

  /// 动作列表（顺序即训练顺序；组序展开见 FitnessWorkoutState.currentTarget）。
  final List<PlanExercise> exercises;

  /// 全模板总组数（开练页「共 N 组」与完成判定）。
  int get totalSets => exercises.fold(0, (acc, e) => acc + e.sets);

  /// 模板是否可开练（至少一个动作）。
  bool get isStartable => exercises.isNotEmpty;

  /// 编码为 exercises 列 JSON（§5.5⑧；形状见 [kFitnessPlanTemplateVer]）。
  String encode() => jsonEncode(<String, Object?>{
        'ver': kFitnessPlanTemplateVer,
        'exercises': [for (final e in exercises) e.toJson()],
      });

  /// 防御解析（§7.4）：坏 JSON/形状不符返回空模板（读侧渲染空态引导），
  /// 数组内坏行逐条过滤——模板数据异常永不炸计划页/开练页。
  static FitnessPlanTemplate decode(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const FitnessPlanTemplate(exercises: []);
    }
    if (decoded is! Map) return const FitnessPlanTemplate(exercises: []);
    final list = decoded['exercises'];
    if (list is! List) return const FitnessPlanTemplate(exercises: []);
    final parsed = <PlanExercise>[];
    for (final item in list) {
      // 坏行逐条过滤（§7.4 防御：单行异常不炸整模板）。
      final exercise = PlanExercise.tryParseJson(item);
      if (exercise != null) parsed.add(exercise);
    }
    return FitnessPlanTemplate(exercises: parsed);
  }
}

/// §5.5⑧ weekday_mask 展示标签：bit0=周一 … bit6=周日（掩码位序）。
const List<String> kPlanWeekdayLabels = [
  '周一', '周二', '周三', '周四', '周五', '周六', '周日',
];

/// DateTime.weekday（周一=1…周日=7）→ §5.5⑧ 掩码位（bit0=周一…bit6=周日）。
int planWeekdayBitOf(DateTime day) => 1 << (day.weekday - 1);

/// 排期掩码是否覆盖某日（§5.5⑧ 按周排期；[day] 用本地 DateTime）。
bool planMaskCovers(int mask, DateTime day) =>
    (mask & planWeekdayBitOf(day)) != 0;

/// 排期掩码摘要（「周一、周三」；空掩码返回 null——纯模板无排期）。
String? planMaskSummary(int mask) {
  final parts = <String>[
    for (var i = 0; i < kPlanWeekdayLabels.length; i++)
      if ((mask >> i) & 1 == 1) kPlanWeekdayLabels[i],
  ];
  return parts.isEmpty ? null : parts.join('、');
}
