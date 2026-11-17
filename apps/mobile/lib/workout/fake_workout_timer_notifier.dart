/// WorkoutTimerNotifier 的测试桩（W14 任务 2「Fake 断言」；测试纪律
/// 「禁真实通知/平台通道」）。
///
/// 只记录调用序列，不触发任何通知：`shown`/`cancelled`/`activeById` 供测试
/// 断言「开练→常驻通知、组间休息→原生倒计时通知、结束→cancel」
/// （W14 任务 5）。
library;

import 'rest_timer_notifier.dart';

/// 记录型通知器（测试装配：`workoutTimerNotifierProvider.overrideWithValue`）。
class FakeWorkoutTimerNotifier implements WorkoutTimerNotifier {
  /// 按调用序累积的 show 请求（不折叠——断言调用序列）。
  final List<WorkoutTimerNotice> shown = <WorkoutTimerNotice>[];

  /// 按调用序累积的取消 id。
  final List<int> cancelled = <int>[];

  /// 当前「存活」视图（show 覆盖写、cancel 移除）——测试便捷断言。
  final Map<int, WorkoutTimerNotice> activeById = <int, WorkoutTimerNotice>{};

  /// 最近一次 show（便捷断言）。
  WorkoutTimerNotice? get lastShown =>
      shown.isEmpty ? null : shown.last;

  @override
  Future<void> show(WorkoutTimerNotice notice) async {
    shown.add(notice);
    activeById[notice.notificationId] = notice;
  }

  @override
  Future<void> cancel({required int notificationId}) async {
    cancelled.add(notificationId);
    activeById.remove(notificationId);
  }

  /// 清空调用记录（用例间隔离）。
  void reset() {
    shown.clear();
    cancelled.clear();
    activeById.clear();
  }
}
