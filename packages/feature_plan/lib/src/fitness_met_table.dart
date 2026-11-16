/// 内置 MET 表与消耗估算（§3.5「时长+类型+MET 表消耗估算」、§5.5⑦）。
///
/// 估算公式（§3.5）：**kcal = MET × 体重kg × 时长h**；UI 按 ±20% 口径标注
/// （§3.5 误差口径标注 P0——与 AI 置信度同一信任语言，§2.3 步骤 3）。
///
/// MET 值取自 Compendium of Physical Activities 常用档位（四舍五入到 0.1），
/// 每个活动按强度档（低/中/高）给出三档 MET——「强度档」不是独立列，
/// 落库时作为 MET 参数写进 burn 行 payload（§5.2② payload「MET 参数」）。
library;

/// 运动强度档（§3.5「强度档」；wire 值写入 burn 行 payload，§5.2②）。
enum FitnessIntensity {
  low('low', '低'),
  mid('mid', '中'),
  high('high', '高');

  const FitnessIntensity(this.wire, this.label);

  /// payload/导出用文本。
  final String wire;

  /// UI 展示名。
  final String label;

  static FitnessIntensity fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () =>
            throw ArgumentError('未知 FitnessIntensity: $value（§3.5 强度档）'),
      );
}

/// 运动大类（§5.5⑦ fitness_sessions.type 列枚举）。
///
/// W5-6 手动记录只用前四档；`template_instance` 属 P1 健身计划实例
/// （§3.5 健身计划、§11.1 W14），此处不提供选择。
enum FitnessType {
  strength('strength', '力量'),
  cardio('cardio', '有氧'),
  hiit('hiit', 'HIIT'),
  other('other', '其他');

  const FitnessType(this.wire, this.label);

  /// fitness_sessions.type 列 wire 值（与 §5.5⑦ 枚举一字不差）。
  final String wire;

  /// UI 展示名。
  final String label;

  /// 行读侧回放（坏值抛错，§6.3 读侧校验口径）。
  static FitnessType fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () =>
            throw ArgumentError('未知 FitnessType: $value（§5.5⑦ type 枚举）'),
      );
}

/// 内置 MET 表的单个活动条目（§3.5 类型选择）。
class FitnessActivity {
  const FitnessActivity({
    required this.id,
    required this.name,
    required this.type,
    required this.metLow,
    required this.metMid,
    required this.metHigh,
  });

  /// 稳定标识（burn 行 payload.activity_id 留痕，§5.2②）。
  final String id;

  /// 中文名（UI 展示、事件标题默认前缀）。
  final String name;

  /// 归属大类（fitness_sessions.type 列，§5.5⑦）。
  final FitnessType type;

  /// 三档 MET（低/中/高，§3.5 强度档）。
  final double metLow;
  final double metMid;
  final double metHigh;

  /// 取某强度档的 MET 值。
  double metFor(FitnessIntensity intensity) => switch (intensity) {
        FitnessIntensity.low => metLow,
        FitnessIntensity.mid => metMid,
        FitnessIntensity.high => metHigh,
      };
}

/// 内置活动清单（§3.5：类型选择覆盖 力量/有氧/HIIT/其他 四大类）。
const List<FitnessActivity> kFitnessActivities = [
  FitnessActivity(
      id: 'brisk_walk',
      name: '快走',
      type: FitnessType.cardio,
      metLow: 3.5,
      metMid: 4.3,
      metHigh: 5.0),
  FitnessActivity(
      id: 'jogging',
      name: '慢跑',
      type: FitnessType.cardio,
      metLow: 6.0,
      metMid: 7.0,
      metHigh: 8.5),
  FitnessActivity(
      id: 'cycling',
      name: '骑行',
      type: FitnessType.cardio,
      metLow: 3.5,
      metMid: 6.8,
      metHigh: 10.0),
  FitnessActivity(
      id: 'swimming',
      name: '游泳',
      type: FitnessType.cardio,
      metLow: 4.5,
      metMid: 6.0,
      metHigh: 8.3),
  FitnessActivity(
      id: 'rope_skipping',
      name: '跳绳',
      type: FitnessType.hiit,
      metLow: 8.8,
      metMid: 11.0,
      metHigh: 12.3),
  FitnessActivity(
      id: 'hiit',
      name: 'HIIT 间歇',
      type: FitnessType.hiit,
      metLow: 6.0,
      metMid: 8.0,
      metHigh: 10.0),
  FitnessActivity(
      id: 'strength_training',
      name: '力量训练',
      type: FitnessType.strength,
      metLow: 3.5,
      metMid: 5.0,
      metHigh: 6.0),
  FitnessActivity(
      id: 'yoga',
      name: '瑜伽拉伸',
      type: FitnessType.other,
      metLow: 2.5,
      metMid: 3.0,
      metHigh: 4.0),
  FitnessActivity(
      id: 'ball_sports',
      name: '球类运动',
      type: FitnessType.other,
      metLow: 4.5,
      metMid: 6.5,
      metHigh: 8.0),
  FitnessActivity(
      id: 'other',
      name: '其他运动',
      type: FitnessType.other,
      metLow: 3.0,
      metMid: 4.5,
      metHigh: 6.0),
];

/// 按 id 查活动；未命中返回 null（payload 回放防御）。
FitnessActivity? findFitnessActivity(String id) {
  for (final activity in kFitnessActivities) {
    if (activity.id == id) return activity;
  }
  return null;
}

/// MET 表消耗估算（§3.5：kcal = MET × 体重kg × 时长h）。
///
/// 结果为整数 kcal（§5.1「kcal 一律 INTEGER」）；[durationS] 秒、
/// [weightKg] 来自身体档案（settings 体重，§3.5 身体档案 P0）。
/// 输入非法（非正时长/体重）抛 [ArgumentError]——调用方 UI 已先行校验。
int estimateKcalBurn({
  required FitnessActivity activity,
  required FitnessIntensity intensity,
  required int durationS,
  required double weightKg,
}) {
  if (durationS <= 0) {
    throw ArgumentError.value(durationS, 'durationS', '时长必须为正（秒）');
  }
  if (weightKg <= 0) {
    throw ArgumentError.value(
        weightKg, 'weightKg', '体重必须为正（kg，MET 估算依赖，§3.5）');
  }
  final met = activity.metFor(intensity);
  return (met * weightKg * durationS / Duration.secondsPerHour).round();
}
