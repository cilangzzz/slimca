/// KeepAwakeService 的测试桩（W14 任务 2「Fake（测试记录调用）」；测试纪律
/// 「禁真实计时器/通知/平台通道」）。
///
/// 只记录调用序列，不触碰任何平台通道：`enableCount`/`disableCount`/
/// `isEnabled`/`calls` 供测试断言「开练→KeepAwake.on、结束→off」
/// （W14 任务 5）与调用交错次序。
library;

import 'keep_awake_service.dart';

/// 记录型唤醒锁（测试装配：`keepAwakeProvider.overrideWithValue`）。
class FakeKeepAwakeService implements KeepAwakeService {
  /// enable 调用计数（断言「开练→KeepAwake.on」）。
  int enableCount = 0;

  /// disable 调用计数（断言「结束→off」）。
  int disableCount = 0;

  /// 按调用序累积的调用名（enable/disable 交错断言）。
  final List<String> calls = <String>[];

  bool _enabled = false;

  /// 当前是否常亮（enable→true、disable→false；最后一次调用定态）。
  bool get isEnabled => _enabled;

  @override
  Future<void> enable() async {
    enableCount++;
    _enabled = true;
    calls.add('enable');
  }

  @override
  Future<void> disable() async {
    disableCount++;
    _enabled = false;
    calls.add('disable');
  }

  /// 清空调用记录（用例间隔离）。
  void reset() {
    enableCount = 0;
    disableCount = 0;
    calls.clear();
    _enabled = false;
  }
}
