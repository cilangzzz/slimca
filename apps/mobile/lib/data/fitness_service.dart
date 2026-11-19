/// 壳层训练引擎的 MET 估算工具（§3.5 估算式；供 workout_log_service 使用）。
///
/// 口径：kcal = MET × 体重kg × 时长h（§3.5 手动记录估算式），MET 表随
/// fitness_sessions.type 四大类取简表，UI 按 ±20% 口径标注（§3.5 误差口径
/// 标注 P0）。
///
/// 收敛注记（计划域 IA 重设计）：健身手动记录写路径唯一在 feature_plan
/// PlanGateway.submitFitnessSession（10 活动 × 3 强度档细表）——本文件的
/// 四类简表只服务壳层训练引擎的「结束并保存」汇总估算（会话 type 语义 =
/// template_instance → strength 档）；身体档案常量与体重读写统一走
/// feature_plan（kSettingBodyWeightKg/kDefaultBodyWeightKg=70，
/// loadBodyWeightKg/saveBodyWeightKg）。双基线已消除。
library;

/// W5-6 初版 MET 简表（§3.5「MET 表消耗估算」；kg/h 口径。数值取 Compendium
/// 常用中位近似，±20% 口径在 UI 标注）。
const Map<String, double> kMetTable = {
  'strength': 5.0, // 力量（中强度阻力训练）
  'cardio': 7.0, // 有氧（慢跑/骑行中位）
  'hiit': 10.0, // HIIT（高强度间歇）
  'other': 4.0, // 其他（快走/拉伸等轻活动）
};

/// MET 估算（§3.5：kcal = MET × 体重kg × 时长h；四舍五入回 INTEGER，§5.1）。
int estimateBurnKcal({
  required String type,
  required double weightKg,
  required int durationMinutes,
}) {
  final met = kMetTable[type] ?? kMetTable['other']!;
  final hours = durationMinutes / 60;
  return (met * weightKg * hours).round();
}
