/// 提醒对账协调器（§11.2 W13 任务 3「本地通知」装配：todos 流 → 规划 →
/// 调度器差异对账）。
///
/// 运行模型（与 SyncCoordinator 同款纪律，§6.1 本地优先）：
/// - `start()` 订阅 todos（remind_at 非空、未删）watch 流；每次流重发重规划
///   （`reminder_planner.dart` 纯函数），与上一次已调度集按通知 id 对账——
///   新增/变更 → schedule，消失 → cancel；
/// - 重复待办的每个展开实例各一条调度调用（§11.2 任务 3「按展开实例调度」，
///   Fake 下记录调用序列）；
/// - 启动期一次性权限请求（Android 13+ POST_NOTIFICATIONS，§3.3 运行时
///   接线）；结果不阻塞——被拒时调度照常落（系统不展示，用户可在系统设置
///   补授权）；
/// - 分区/调度失败静默吞掉（下轮流重发自愈重排；§6.1 原则 1 降级纪律）。
library;

import 'dart:async';

import 'package:core_db/core_db.dart' show AppDatabase;
import 'package:drift/drift.dart' show BooleanExpressionOperators;

import 'reminder_planner.dart';
import 'reminder_scheduler.dart';

/// 提醒对账协调器（生产由 bootstrap() 构造、main() 启动；测试直接构造）。
class ReminderSyncCoordinator {
  ReminderSyncCoordinator({
    required AppDatabase db,
    required ReminderScheduler scheduler,
  }) : _db = db,
       _scheduler = scheduler;

  final AppDatabase _db;
  final ReminderScheduler _scheduler;

  StreamSubscription<Object?>? _sub;

  /// 上一次对账后已落调度器的请求集（id → 请求；对账基准）。
  Map<int, TodoReminder> _scheduledById = const <int, TodoReminder>{};

  /// 在飞对账链（流回调不 await——串行化避免乱序）。
  Future<void> _pending = Future<void>.value();

  /// 是否已启动（幂等：重复 start 为 no-op）。
  bool get isStarted => _sub != null;

  /// 启动订阅（幂等）。返回后首帧对账可能仍在飞行——测试用轮询等 Fake。
  Future<void> start() async {
    if (_sub != null) return;
    // 启动期一次性权限请求（§11.2 任务 3 运行时接线；尽力而为不阻塞）。
    try {
      await _scheduler.ensurePermission();
    } on Object {
      // 权限查询失败静默：调度照常，拒发展示属系统行为（§6.1）。
    }
    final stream = (_db.select(_db.todos)
          ..where((t) => t.remindAt.isNotNull() & t.deletedAt.isNull()))
        .watch()
        .map((rows) => planTodoReminders(todos: rows, now: DateTime.now()));
    _sub = stream.listen(
      (plan) {
        _pending = _pending.then((_) => _reconcile(plan));
      },
      onError: (Object _) {
        // 流分区静默：保持上次已调度集，下轮流重发自愈（§6.1）。
      },
    );
  }

  /// 停止订阅并清空对账基准（已落系统通知不撤销——下次启动对账重建）。
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _scheduledById = const <int, TodoReminder>{};
    await _pending;
  }

  /// 等待在飞对账收口（测试辅助：调度断言前 quiesce）。
  Future<void> settleForTest() => _pending;

  /// 差异对账：计划集 vs 上次已调度集。
  Future<void> _reconcile(Map<int, TodoReminder> plan) async {
    try {
      for (final entry in _scheduledById.entries) {
        final stillPlanned = plan[entry.key];
        if (stillPlanned == null) {
          await _scheduler.cancel(notificationId: entry.key);
        } else if (stillPlanned != entry.value) {
          // 同 id 内容变化（理论上 id 已含实例日；标题/时刻改动走这里）：
          // 先取消再重排，幂等覆盖。
          await _scheduler.cancel(notificationId: entry.key);
          await _scheduler.schedule(stillPlanned);
        }
      }
      for (final entry in plan.entries) {
        if (!_scheduledById.containsKey(entry.key)) {
          await _scheduler.schedule(entry.value);
        }
      }
      _scheduledById = Map<int, TodoReminder>.of(plan);
    } on Object {
      // 单轮对账失败静默：下次流重发整轮重来（§6.1 自愈）。
    }
  }
}
