/// 存钱写路径用例（§3.6 存钱目标 P1 留存钩子、§5.5⑪⑫、§11.2 W13 任务 4
/// 「savings_goal_created/coin_in 漏斗事件接入」）。
///
/// 复用抽象纪律（§10.4）：持久化语义全部复用 core_db 的
/// [SavingsGoalsDao]/[SavingsContributionsDao]（outbox 同事务入队、投影
/// savings_progress 同事务重算、append-only 幂等按 goal+date+source）——
/// 本服务只做 feature 层编排：存钱法节奏（rhythm JSON 形状）+ 格子/建议额
/// 计算 + W13 漏斗埋点，不重复实现任何合并/投影语义。
///
/// rhythm JSON 形状（§5.5⑪「阶梯表或每日额」，W13 壳层约定）：
/// - custom：`{"daily_amount_minor": n}`——投币建议额；
/// - daily365：`{"ladder": "day_n_yuan"}`——365 存钱法（第 N 天存 N 元）；
/// - week52：`{"ladder": "week_n_yuan"}`——52 周存钱法（第 N 周存 N 元）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart'
    show TelemetryService, formatCalendarDay;

import '../telemetry/w13_funnel_events.dart';

/// 存钱写路径服务（providers.dart 装配；页面/表单只经它写）。
class SavingsService {
  SavingsService({
    required db.SavingsGoalsDao goalsDao,
    required db.SavingsContributionsDao contributionsDao,
    required TelemetryService telemetry,
  }) : _goalsDao = goalsDao,
       _contributionsDao = contributionsDao,
       _telemetry = telemetry;

  final db.SavingsGoalsDao _goalsDao;
  final db.SavingsContributionsDao _contributionsDao;
  final TelemetryService _telemetry;

  /// 新建存钱目标（§5.5⑪）+ W13 漏斗 `savings_goal_created`。
  ///
  /// - [method]：daily365 / week52 / custom（§5.5⑪ 枚举）；
  /// - [dailyAmountMinor]：custom 的每日建议额（rhythm 落 JSON；365/52 周
  ///   法忽略——阶梯自格子号推导）；
  /// - [startedOn]：缺省设备本地今日（DAO 同缺省；365/52 的第 1 格锚点）。
  Future<db.SavingsGoal> createGoal({
    required String name,
    required int targetMinor,
    required String method,
    int? dailyAmountMinor,
    String? deadline,
    String? startedOn,
  }) async {
    final goal = await _goalsDao.create(
      name: name,
      targetMinor: targetMinor,
      method: method,
      rhythm: _rhythmJson(method, dailyAmountMinor),
      deadline: deadline,
      startedOn: startedOn,
    );
    // W13 漏斗（§11.2 任务 4）：建档即记——props 只有枚举标签（§3.9 金额
    // 与名称禁入遥测）。
    await _telemetry.funnel(
      W13TelemetryFunnel.savingsGoalCreated,
      props: <String, Object?>{'method': method},
    );
    return goal;
  }

  /// 投币打卡（§3.6「投币式打卡」）：当日贡献 append-only 追加 + W13 漏斗
  /// `coin_in`（仅真实新增时记——幂等命中不重复计「存进去」，漏斗不失真）。
  ///
  /// [amountMinor] 缺省取当日建议额（[suggestedAmountMinor]）。
  /// 返回 (贡献行, 是否本次新增)——幂等命中返回既有行与 false。
  Future<(db.SavingsContribution, bool)> coinIn(
    db.SavingsGoal goal, {
    int? amountMinor,
    String? date,
  }) async {
    final day = date ?? formatCalendarDay(DateTime.now());
    final existing = await _contributionsDao.findEffective(
      goalId: goal.id,
      date: day,
    );
    if (existing != null) {
      return (existing, false); // 当日已投币：幂等命中（§5.5⑫ 幂等口径）。
    }
    final slot = slotForDay(goal, day);
    final contribution = await _contributionsDao.append(
      goalId: goal.id,
      amountMinor: amountMinor ?? suggestedAmountMinor(goal, day),
      date: day,
      slot: slot,
    );
    await _telemetry.funnel(
      W13TelemetryFunnel.coinIn,
      props: <String, Object?>{
        'method': goal.method,
        if (slot != null) 'slot': slot,
      },
    );
    return (contribution, true);
  }

  /// 打卡日的格子号（§5.5⑫ slot；custom 为 null）。
  ///
  /// 365 法：第 N 天 = 自 started_on 的日偏移 + 1；52 周法：第 N 周 = 完整
  /// 周数 + 1（不足一周按当前第 N 周计——打卡语义按「现在进行到第几格」）。
  int? slotForDay(db.SavingsGoal goal, String day) {
    final started = _parseDay(goal.startedOn);
    final current = _parseDay(day);
    if (started == null || current == null) return null;
    switch (goal.method) {
      case db.kSavingsMethodDaily365:
        return current.difference(started).inDays + 1;
      case db.kSavingsMethodWeek52:
        return current.difference(started).inDays ~/ 7 + 1;
      default:
        return null; // custom：无格子（§5.5⑫）。
    }
  }

  /// 打卡日建议额（分；投币表单预填）：365/52 周法按第 N 格 = N 元阶梯，
  /// custom 取 rhythm 每日额；解析失败回退 100 分（¥1 兜底，§7.4 健壮性）。
  int suggestedAmountMinor(db.SavingsGoal goal, String day) {
    final slot = slotForDay(goal, day);
    switch (goal.method) {
      case db.kSavingsMethodDaily365:
      case db.kSavingsMethodWeek52:
        return slot != null && slot > 0 ? slot * 100 : 100;
      case db.kSavingsMethodCustom:
        final daily = _parseDailyAmount(goal.rhythm);
        return daily ?? 100;
      default:
        return 100;
    }
  }

  /// rhythm JSON（§5.5⑪）：按存钱法落壳层约定形状（见文件头）。
  String _rhythmJson(String method, int? dailyAmountMinor) {
    switch (method) {
      case db.kSavingsMethodDaily365:
        return jsonEncode(<String, Object?>{'ladder': 'day_n_yuan'});
      case db.kSavingsMethodWeek52:
        return jsonEncode(<String, Object?>{'ladder': 'week_n_yuan'});
      default:
        return jsonEncode(<String, Object?>{
          'daily_amount_minor': dailyAmountMinor ?? 100,
        });
    }
  }

  static int? _parseDailyAmount(String rhythm) {
    try {
      final decoded = jsonDecode(rhythm);
      if (decoded is Map) {
        final v = decoded['daily_amount_minor'];
        if (v is int && v >= 0) return v;
      }
    } on FormatException {
      // 坏 rhythm：走兜底建议额（§7.4）。
    }
    return null;
  }

  static DateTime? _parseDay(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }
}
