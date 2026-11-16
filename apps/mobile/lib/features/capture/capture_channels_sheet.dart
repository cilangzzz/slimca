/// 录入通道抽屉（§3.3 录入抽屉三通道：写/说/拍、§11.1 W5-6「录入页『说』
/// 段启用」）。
///
/// 结构：通道切换条（写=文本 CapturePage、说=语音 [VoiceCapturePanel]、
/// 拍=P1 占位禁用 §3.3）+ 通道体。两通道共享同一 [CaptureSeed] → 同一
/// captureControllerProvider 实例（§10.4 family by seed），语音转写文本与
/// 手打文本走同一条 AI 解析管线；sheet 顶层 watch 控制器保活（family
/// autoDispose，避免「写↔说」切换时输入/解析中间态丢失）。
///
/// 「写」通道整体复用 feature_capture 导出的 [CapturePage]（收敛后壳唯一
/// 录入 UI 纪律，§10.4）；本文件只做通道编排，不复制任何表单/解析逻辑。
library;

import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'voice_capture_panel.dart';

/// 通道切换条测试锚点（写/说/拍）。
const Key captureChannelTextKey = ValueKey('capture_channel_text');
const Key captureChannelVoiceKey = ValueKey('capture_channel_voice');
const Key captureChannelPhotoKey = ValueKey('capture_channel_photo');

/// 唤起录入通道抽屉（§9.3#3 弹簧 bottomSheet；语义与 showCaptureSheet
/// 一致——宿主可传 onSubmitted 接管提交完成，缺省自动关闭）。
Future<void> showCaptureChannelsSheet(
  BuildContext context, {
  CaptureSeed seed = const CaptureSeed(),
  void Function(String entryId)? onSubmitted,
}) {
  return showSlimcaSpringSheet<void>(
    context: context,
    motion: MotionConfig.of(context),
    builder: (_) => CaptureChannelsSheet(seed: seed, onSubmitted: onSubmitted),
  );
}

/// 录入通道（§3.3：写=手打文本、说=语音转写；拍=P1 占位）。
enum _CaptureChannel { text, voice }

/// 录入通道抽屉。
class CaptureChannelsSheet extends ConsumerStatefulWidget {
  const CaptureChannelsSheet({
    super.key,
    this.seed = const CaptureSeed(),
    this.onSubmitted,
  });

  /// 打开参数（编辑模式仍经 showCaptureSheet 直达 W2 表单，§3.4 修正链）。
  final CaptureSeed seed;

  /// 提交成功回调（传 entryId）；缺省=成功后自动关闭抽屉（§4.3）。
  final void Function(String entryId)? onSubmitted;

  @override
  ConsumerState<CaptureChannelsSheet> createState() =>
      _CaptureChannelsSheetState();
}

class _CaptureChannelsSheetState extends ConsumerState<CaptureChannelsSheet> {
  _CaptureChannel _channel = _CaptureChannel.text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // 保活 watch（§10.4 family autoDispose）：sheet 存续期间控制器不销毁，
    // 「写↔说」切换共享 inputText/解析中间态（两通道同一管线）。
    ref.watch(captureControllerProvider(widget.seed));

    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChannelBar(
              channel: _channel,
              onSelected: (channel) => setState(() => _channel = channel),
            ),
            Flexible(child: _body(context)),
          ],
        ),
      ),
    );
  }

  /// 通道体：「写」= CapturePage（feature_capture 唯一录入 UI，§10.4）；
  /// 「说」= VoiceCapturePanel（W5-6 Fake 链路，§3.3）。
  Widget _body(BuildContext context) {
    switch (_channel) {
      case _CaptureChannel.text:
        return CapturePage(seed: widget.seed, onSubmitted: widget.onSubmitted);
      case _CaptureChannel.voice:
        return VoiceCapturePanel(
          seed: widget.seed,
          onSubmitted: widget.onSubmitted,
          onSwitchChannel: () =>
              setState(() => _channel = _CaptureChannel.text),
        );
    }
  }
}

/// 通道切换条（§3.3 三通道；chip 微交互 dur.s，§9.2）。
class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.channel, required this.onSelected});

  final _CaptureChannel channel;
  final ValueChanged<_CaptureChannel> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Row(
        children: [
          _chip(
            context,
            key: captureChannelTextKey,
            icon: Icons.edit_outlined,
            label: '写',
            selected: channel == _CaptureChannel.text,
            onTap: () => onSelected(_CaptureChannel.text),
          ),
          const SizedBox(width: 8),
          _chip(
            context,
            key: captureChannelVoiceKey,
            icon: Icons.mic_none,
            label: '说',
            selected: channel == _CaptureChannel.voice,
            onTap: () => onSelected(_CaptureChannel.voice),
          ),
          const SizedBox(width: 8),
          // 拍：P1 占位（§3.3 拍照通道 W5-6 未排期），禁用态渲染。
          // Tooltip 不能夹在 Row 与 Expanded 之间（ParentData 断裂）：
          // Expanded 必须是 Row 直接子级，Tooltip 包在 Expanded 内侧。
          Expanded(
            child: Tooltip(
              message: '拍照通道 P1（§3.3）',
              child: _chip(
                context,
                key: captureChannelPhotoKey,
                icon: Icons.photo_camera_outlined,
                label: '拍',
                selected: false,
                enabled: false,
                onTap: null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// chip 主体（不含 Expanded——展宽策略由调用方的 Row 直接子级决定）。
  Widget _chip(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required bool selected,
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    final tokens = context.slimca;
    final motion = context.motion;
    return AnimatedContainer(
      duration: motion.chipCheck, // §9.2 dur.s chip 微交互
      curve: motion.springSnappy.curve,
      decoration: BoxDecoration(
        color: selected
            ? tokens.primary.withValues(alpha: 0.12)
            : tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? tokens.primary : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected
                      ? tokens.primary
                      : (enabled ? tokens.onSurfaceMuted : tokens.outline),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? tokens.primary
                        : (enabled ? tokens.onSurfaceMuted : tokens.outline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
