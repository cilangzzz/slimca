/// 组间计时器（§3.5「组间计时器（锁屏可跑）」、§11.2 W14 主线任务 2）。
///
/// 组成与口径：
/// - **大数字倒计时**：rest 秒数从模板读（调用方经 [RestTimerNotifier.start]
///   传入 §5.5⑧ exercises JSON 的 rest_s），面板渲染剩余秒 + 进度条；
///   颜色/时长只引用语义 token 与 MotionConfig（§8.2/§9.2，禁裸色值/裸时长）；
/// - **可测性（§10.1 测试口径「禁止真实计时器」）**：心跳源经
///   [restTickerFactoryProvider] 注入——生产缺省 [systemRestTicker]（1s 周期流，
///   仅 start() 时懒订阅）；测试 override 为手动 StreamController，逐枚触发
///   心跳断言倒计时推进（Fake 时钟口径）。剩余秒恒由「心跳驱动递减」推导，
///   UI 不直挂任何 Timer；
/// - **完成音/震动留接口（§11.2 W14）**：[RestFeedback] 抽象 +
///   [restFeedbackProvider] 注入点，feature 层缺省 [NoopRestFeedback]、不触
///   平台通道；宿主（壳层）override 注入 HapticFeedback/音效实现；
/// - **锁屏可跑**：前台化/保活由壳层承担（§10.4 壳负责装配），feature 层
///   不触 WakeLock/前台服务通道；
/// - 计满自动收起（state→null）并触发 [RestFeedback.onRestComplete]，训练
///   主流程随即可见「完成下一组」。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// 心跳源工厂：每次 [RestTimerNotifier.start] 调用一次，返回秒级心跳流
/// （单订阅流；重复休息各取新流，§11.2 W14 注入点）。
typedef RestTickerFactory = Stream<void> Function();

/// 缺省心跳源（生产）：1s 周期。仅在 start() 后被工厂产出并被订阅（懒生产：
/// 训练页不进休息不产生任何 Timer，避免无关 widget 测试的 fake_async 泄漏）。
Stream<void> systemRestTicker() =>
    Stream<void>.periodic(const Duration(seconds: 1));

/// 心跳源注入点（§11.2 W14 可测性）：测试 override 为手动触发的
/// StreamController（Fake 时钟口径，§10.1 测试纪律）。
final restTickerFactoryProvider =
    Provider<RestTickerFactory>((ref) => systemRestTicker);

/// 组间完成反馈接口（§11.2 W14「完成音/震动留接口」）。
abstract class RestFeedback {
  /// 休息计满：宿主注入提示音/震动（HapticFeedback/播放器，§10.4 壳装配）。
  void onRestComplete();
}

/// 缺省 no-op 实现（feature 层不触平台通道）。
class NoopRestFeedback implements RestFeedback {
  const NoopRestFeedback();

  @override
  void onRestComplete() {}
}

/// 反馈注入点：宿主可 override 为真实音/震动实现（§10.4）。
final restFeedbackProvider =
    Provider<RestFeedback>((ref) => const NoopRestFeedback());

/// 倒计时状态（不可变；provider 态 null=未在休息）。
class RestTimerState {
  const RestTimerState({required this.totalS, required this.remainingS});

  /// 本次休息总秒数（模板 rest_s，§5.5⑧）。
  final int totalS;

  /// 剩余秒（心跳驱动递减）。
  final int remainingS;
}

/// 组间倒计时控制器（§10.1 Riverpod 3 Notifier）。
class RestTimerNotifier extends Notifier<RestTimerState?> {
  StreamSubscription<void>? _sub;

  @override
  RestTimerState? build() {
    // provider 销毁（训练页出栈）即断流——心跳不越过页面生命周期。
    ref.onDispose(_cancel);
    return null;
  }

  /// 开始一段休息（rest 秒数由调用方从模板读入传入，§5.5⑧ rest_s；
  /// 非正值视为「该动作不休息」，直接收起）。
  void start(int seconds) {
    _cancel();
    if (seconds <= 0) return;
    state = RestTimerState(totalS: seconds, remainingS: seconds);
    _sub = ref.read(restTickerFactoryProvider)().listen((_) => _tick());
  }

  void _tick() {
    final s = state;
    if (s == null) return;
    final next = s.remainingS - 1;
    if (next <= 0) {
      // 计满：断流、收起、触发完成反馈（完成音/震动接口，§11.2 W14）。
      _cancel();
      state = null;
      ref.read(restFeedbackProvider).onRestComplete();
      return;
    }
    state = RestTimerState(totalS: s.totalS, remainingS: next);
  }

  /// 跳过休息（用户主动提前回到训练主流程）。
  void skip() {
    _cancel();
    state = null;
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
  }
}

/// 组间计时器 provider（autoDispose 跟随训练页生命周期）。
final restTimerProvider =
    NotifierProvider.autoDispose<RestTimerNotifier, RestTimerState?>(
        RestTimerNotifier.new);

/// 面板测试锚点。
const Key restTimerPanelKey = ValueKey('rest_timer_panel');

/// 跳过按钮测试锚点。
const Key restTimerSkipKey = ValueKey('rest_timer_skip');

/// 剩余秒大数字测试锚点（AnimatedSwitcher，child 为剩余秒 Text）。
const Key restTimerRemainKey = ValueKey('rest_timer_remain');

/// 组间计时器面板：大数字倒计时（rest 态 null 时整块收起）。
///
/// 动效（§9.2/§9.5）：数字切换走 AnimatedSwitcher（dur.s 微交互档，隐式动画
/// 仅限微交互）；进度条线性推进不设动画（每秒一帧的信息层刷新，无过渡语义）。
class RestTimerPanel extends ConsumerWidget {
  const RestTimerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rest = ref.watch(restTimerProvider);
    if (rest == null) return const SizedBox.shrink();
    final tokens = context.slimca;
    final motion = context.motion;
    final double progress =
        rest.totalS <= 0 ? 0 : rest.remainingS / rest.totalS;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        key: restTimerPanelKey,
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('组间休息（下一组待练）',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, color: tokens.onSurfaceMuted)),
              const SizedBox(height: 8),
              // 大数字倒计时（§3.5）：剩余秒随注入心跳递减；数字切换微交互
              // 走 dur.s（§9.2 token，禁裸时长）。
              AnimatedSwitcher(
                key: restTimerRemainKey,
                duration: motion.chipCheck,
                child: Text(
                  '${rest.remainingS}',
                  key: ValueKey<int>(rest.remainingS),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    color: tokens.kcalOut,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                color: tokens.kcalOut,
                backgroundColor: tokens.surfaceMuted,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  key: restTimerSkipKey,
                  onPressed: () =>
                      ref.read(restTimerProvider.notifier).skip(),
                  child: const Text('跳过休息'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
