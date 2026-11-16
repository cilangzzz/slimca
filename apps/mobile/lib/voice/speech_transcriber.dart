/// 语音转写抽象与装配（§3.3 语音通道、§11.1 W5-6「语音端侧 ASR+云兜底」）。
///
/// 分层边界（§10.4）：端侧 ASR 的平台细节（iOS Speech / Android
/// SpeechRecognizer）封装在转写器实现之后，录入 UI 只依赖 [SpeechTranscriber]
/// 抽象——「语音 ≤5s、失败云 ASR 兜底」（§3.3 语音通道验收）由实现方承担，
/// W5-6 主线只打通 **Fake 链路**：FakeTranscriber → 转写文本 → 复用 AI 解析
/// 管线（CaptureParser，§7.1）→ 确认卡 → 落库（source=voice，§5.2①）。
///
/// 装配（§10.4 壳负责装配）：[speechTranscriberProvider] 缺省绑定
/// [FakeTranscriber]（确定性离线桩，零平台通道调用）；测试按 §3.3 离线优先
/// 口径一律 override 注入 Fake，禁止真实平台通道（见 test/e2e_voice_capture_test.dart）。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 单次语音转写超时（§2.3 步骤 2「语音 ≤5s」输入预算；超时 → 面板给出
/// 重试提示，不卡死抽屉——与 §2.4-3「输入页永不卡死」同一纪律）。
const Duration kVoiceTranscribeTimeout = Duration(seconds: 5);

/// 语音转写抽象（§3.3 语音通道「端侧 ASR 优先（iOS Speech / Android
/// SpeechRecognizer），失败云 ASR 兜底」）。
///
/// 实现契约：
/// - 返回**转写文本**（一句话口语描述，直接进入 AI 解析管线，§7.1 规范化
///   + input_hash 与文本通道同构——语音通道的产出就是文本）；
/// - 失败/不可用抛 [SpeechTranscribeException]，调用方（说通道面板）就地
///   展示可重试提示，绝不打断录入抽屉（§2.4-3）；
/// - 实现方自行承担 ≤[kVoiceTranscribeTimeout] 的预算与云兜底切换（W5-6
///   Fake 链路无网络调用，天然满足离线优先 §3.7）。
abstract class SpeechTranscriber {
  /// 开始一次转写，返回口语原文的转写文本。
  Future<String> transcribe();
}

/// 转写失败（端侧不可用/权限拒绝/云兜底失败，§3.3 语音通道失败分支）。
class SpeechTranscribeException implements Exception {
  const SpeechTranscribeException(this.message, [this.cause]);

  /// 面板可直接展示的原因本体。
  final String message;
  final Object? cause;

  @override
  String toString() => 'SpeechTranscribeException($message)';
}

/// 演示用缺省转写语料（§7.2 示例同构：热量+金额一句话，HeuristicFakeLlmAdapter
/// 正则口径可解析；轮转产出，同一实例多次转写依次取下一句）。
const List<String> kFakeTranscriberDemoLines = [
  '午餐牛肉面 500kcal 花了18',
  '早餐豆浆油条 320kcal 花了6.5',
  '下午拿铁咖啡 180kcal 花了28',
];

/// 确定性 Fake 转写器（W5-6 主线唯一通路；测试注入语料实现可复现断言）。
///
/// - 零平台通道、零网络、零时钟依赖（latency 缺省=0，测试免 pump 等待；
///   传 latency 可模拟端侧延迟走 §2.3「语音 ≤5s」预算路径）；
/// - 语料轮转（cursor 环形递增）：同一实例连续转写依次产出不同句子，
///   便于链路测试断言「再次转写替换原文」。
class FakeTranscriber implements SpeechTranscriber {
  FakeTranscriber({List<String>? transcripts, this.latency = Duration.zero})
      : _transcripts =
            (transcripts == null || transcripts.isEmpty)
                ? kFakeTranscriberDemoLines
                : List<String>.unmodifiable(transcripts);

  final List<String> _transcripts;
  int _cursor = 0;

  /// 模拟端侧延迟（缺省 0；测试如需覆盖超时分支可显式传入）。
  final Duration latency;

  @override
  Future<String> transcribe() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    final line = _transcripts[_cursor % _transcripts.length];
    _cursor++;
    return line;
  }
}

/// 真实端侧 ASR 的 platform-channel 桩（iOS Speech / Android
/// SpeechRecognizer，§3.3 语音通道）。
///
/// **W5-6 只通 Fake 链路**：真机联调所需的权限申请（麦克风/语音识别）、
/// RecognitionListener 流式部分结果回调、失败云 ASR 兜底切换（§3.3）随
/// W5-6 后续真机验收接入；本桩当前只冻结通道契约名
/// [channel]（`slimca/speech_transcriber`），调用即抛
/// [UnimplementedError]——误装配在开发期立刻暴露，而非静默吞掉语音输入。
class PlatformChannelSpeechTranscriber implements SpeechTranscriber {
  /// 平台通道契约名（真机实现按此名接 MethodChannel handler）。
  static const MethodChannel channel = MethodChannel('slimca/speech_transcriber');

  @override
  Future<String> transcribe() async {
    // W5-6 主线口径：只通 FakeTranscriber 链路（§11.1 W5-6、§3.3 注记）。
    throw UnimplementedError(
      '端侧 ASR platform-channel W5-6 未接线（W5-6 只通 Fake 链路，§3.3）；'
      '缺省装配请用 speechTranscriberProvider → FakeTranscriber',
    );
  }
}

/// 语音转写器注入点（§10.4 壳负责装配）。
///
/// W5-6 缺省 = [FakeTranscriber]（确定性离线桩）；真机端侧 ASR 落地后改为
/// 平台探测装配（iOS/Android → [PlatformChannelSpeechTranscriber]，桌面/
/// 测试 → Fake）。测试一律 override 注入脚本化 Fake（禁真实平台通道）。
final Provider<SpeechTranscriber> speechTranscriberProvider =
    Provider<SpeechTranscriber>((ref) => FakeTranscriber());
