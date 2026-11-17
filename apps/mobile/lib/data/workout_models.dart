/// 训练域数据模型（§11.2 W14「健身计划」、§3.5 健身计划 P1、§5.5⑧⑨）。
///
/// 纯值对象 + 解析器（data 层，无框架依赖）：fitness_plans.exercises 的
/// JSON 形状与 exercise_sets 的行语义在此定形——feature 层（训练会话控制
/// 器）与写路径用例（WorkoutLogService）共读本层，保持 features → data
/// 单向依赖（§10.4 分层纪律）。
library;

import 'dart:convert';

/// 训练模板动作条目（§5.5⑧ exercises JSON 的一项：动作/组数/重量配比/
/// 休息秒）。
class WorkoutExercisePlan {
  const WorkoutExercisePlan({
    required this.name,
    required this.sets,
    required this.reps,
    this.weightKg,
    this.restS,
  });

  /// 动作（§5.5⑨ exercise_ref 口径：动作库 id 或名称；骨架取名称直存）。
  final String name;

  /// 组数（1..20）。
  final int sets;

  /// 每组次数（0..200）。
  final int reps;

  /// 重量 kg（可空：自重/未配置；0..500）。
  final double? weightKg;

  /// 组间休息秒（可空：0/缺省=该组完成后不启动倒计时；0..600）。
  final int? restS;
}

/// 解析 fitness_plans.exercises（§5.5⑧「排期模板：动作/组数/重量配比/
/// 休息秒」）。
///
/// 形状基准=计划域编辑器（feature_plan FitnessPlanTemplate.encode：
/// **顶层对象** `{"ver":1,"exercises":[{name,sets,target_reps,
/// target_weight_kg_x10,rest_s}]}`——snake_case 与 §5.5⑨ 列名同构），
/// 另兼容顶层裸数组（W14 壳层种子形状）；解析器**宽容适配**（§7.4 降级
/// 纪律）：动作行键名兼容 name/exercise_ref/ref/exercise/title/动作（动作）、
/// sets/组数、reps/target_reps/次数（次数）、weight_kg/weight/重量（kg 直填）
/// 与 target_weight_kg_x10/weight_kg_x10（×10 定点，§5.5⑨ 口径）；非法项
/// 跳过、数值钳制到合理域；坏 JSON/形状不符/全空 → 空列表（排期卡显示
/// 「模板待完善」，不崩不脏，§7.4 健壮性）。
List<WorkoutExercisePlan> parsePlanExercises(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return const <WorkoutExercisePlan>[];
  } on TypeError {
    return const <WorkoutExercisePlan>[];
  }
  // 顶层形状宽容适配（§7.4）：编辑器对象形状取 exercises 键（ver 校验
  // 从宽——未知版本只加键前向兼容，§5.5⑧ 注），裸数组直用。
  if (decoded is Map) decoded = decoded['exercises'];
  if (decoded is! List) return const <WorkoutExercisePlan>[];
  final result = <WorkoutExercisePlan>[];
  for (final item in decoded) {
    if (item is! Map) continue;
    final name = _textOf(item, const [
      'name',
      'exercise_ref',
      'ref',
      'exercise',
      'title',
      '动作',
    ]);
    if (name == null || name.isEmpty) continue; // 无动作名的项不可训练，跳过。
    final sets = _intOf(item, const ['sets', '组数']) ?? 3;
    final reps = _intOf(item, const ['reps', 'target_reps', '次数']) ?? 10;
    // 重量：kg 直填键优先级低于 ×10 定点键（定点为 §5.5⑨ 权威口径，命中
    // 且 >0 时覆盖；0=自重/未配 → null）。
    var weight = _doubleOf(item, const ['weight_kg', 'weight', '重量']);
    final weightX10 = _intOf(item, const [
      'target_weight_kg_x10',
      'weight_kg_x10',
    ]);
    if (weightX10 != null && weightX10 > 0) {
      weight = weightX10 / 10.0;
    }
    final rest = _intOf(item, const ['rest_s', 'rest', '休息秒']);
    result.add(WorkoutExercisePlan(
      name: name,
      sets: _clampInt(sets, 1, 20),
      reps: _clampInt(reps, 0, 200),
      weightKg: weight == null ? null : _clampDouble(weight, 0, 500),
      restS: rest == null ? null : _clampInt(rest, 0, 600),
    ));
  }
  return result;
}

/// 已完成组记录（训练中内存累积；结束同事务落 exercise_sets，§5.5⑨/§6.2
/// ——「组明细」真值行，随会话行一次性入账，避免半程孤儿行）。
class WorkoutSetEntry {
  const WorkoutSetEntry({
    required this.exerciseRef,
    required this.exerciseIndex,
    required this.setNo,
    required this.reps,
    required this.weightKg,
    required this.restS,
    required this.doneAtMs,
  });

  /// 动作（exercise_ref：骨架取模板名称，§5.5⑨）。
  final String exerciseRef;

  /// 动作序（0 起，模板内顺序）。
  final int exerciseIndex;

  /// 该动作第几组（1 起，§5.5⑨ sort 组序的语义来源）。
  final int setNo;

  /// 次数。
  final int reps;

  /// 重量 kg（可空=自重；落库转 ×10 定点 weight_kg_x10，§5.5⑨）。
  final double? weightKg;

  /// 该组完成的休息秒（0=无休息；落库存 rest_s，§5.5⑨）。
  final int restS;

  /// 完成时刻 UTC ms（§5.5⑨ done_at）。
  final int doneAtMs;
}

// ── 宽容解析辅助（§7.4）────────────────────────────────────────────

String? _textOf(Map<Object?, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = _lookup(map, key);
    if (value == null) continue;
    final text = '$value'.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

int? _intOf(Map<Object?, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = _lookup(map, key);
    if (value == null) continue;
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse('$value'.trim());
    if (parsed != null) return parsed;
  }
  return null;
}

double? _doubleOf(Map<Object?, Object?> map, List<String> keys) {
  for (final key in keys) {
    final value = _lookup(map, key);
    if (value == null) continue;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse('$value'.trim());
    if (parsed != null) return parsed;
  }
  return null;
}

/// 键名查找（大小写不敏感；JSON 键形状随计划域编辑器而异，§7.4）。
Object? _lookup(Map<Object?, Object?> map, String key) {
  for (final entry in map.entries) {
    if ('${entry.key}'.trim().toLowerCase() == key) return entry.value;
  }
  return null;
}

int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

double _clampDouble(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
