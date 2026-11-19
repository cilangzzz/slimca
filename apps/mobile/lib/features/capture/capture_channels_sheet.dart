/// 录入通道抽屉（§3.3 录入抽屉三通道：写/说/拍、§11.1 W5-6「录入页『说』
/// 段启用」、§11.2 W11-12「录入页『拍』段启用：接 feature_capture 拍照路径」）。
///
/// 结构：通道切换条（写=文本 CapturePage、说=语音 [VoiceCapturePanel]、
/// 拍=拍照 [PhotoCapturePanel] §11.2 W11-12）+ 通道体。三通道共享同一
/// [CaptureSeed] → 同一 captureControllerProvider 实例（§10.4 family by
/// seed），手打文本/转写文本/拍照中间态走同一条控制器状态机；sheet 顶层
/// watch 控制器保活（family autoDispose，避免「写↔说↔拍」切换时输入/解析
/// 中间态丢失）。
///
/// 抽屉高度恒为 `captureSheetHeight`（统一抽屉高度口径，本次 UX 插曲新增、
/// 与独立 showCaptureSheet 同款）：通道切换、单边档位切换、AI 阶段流转
/// （输入/解析中/确认卡/降级）均不改变抽屉尺寸——UI 不随内容缩放；
/// 键盘弹出时内容区按 viewInsets 收缩、钉底 CTA 恒在键盘上方。
///
/// 「写」通道整体复用 feature_capture 导出的 [CapturePage]（收敛后壳唯一
/// 录入 UI 纪律，§10.4；showPhotoEntry=false——「拍」通道为唯一拍照入口，
/// 写通道不重复内嵌拍照/相册按钮）；「拍」通道经 [PhotoCapturePanel] 渲染
/// 共享控制器的拍照状态机（入口/呼吸/确认卡全复用 feature_capture 组件，
/// §11.2 任务 2）；本文件只做通道编排，不复制任何表单/解析/拍照逻辑。
library;

import 'dart:async';

import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../telemetry/telemetry.dart';
import 'photo_capture_panel.dart';
import 'voice_capture_panel.dart';

/// 通道切换条测试锚点（写/说/拍）。
const Key captureChannelTextKey = ValueKey('capture_channel_text');
const Key captureChannelVoiceKey = ValueKey('capture_channel_voice');
const Key captureChannelPhotoKey = ValueKey('capture_channel_photo');

/// 唤起录入通道抽屉（§9.3#3 弹簧 bottomSheet；语义与 showCaptureSheet
/// 一致——onSubmitted 为宿主的提交成功纯通知（W7-8 漏斗埋点），抽屉关闭
/// 恒由页面自身负责（§4.3 提交成功收起，W7-8 集成修复口径）。
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

/// 录入通道（§3.3：写=手打文本、说=语音转写、拍=拍照/相册，§11.2 W11-12）。
enum _CaptureChannel { text, voice, photo }

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
    // 「写↔说↔拍」切换共享 inputText/解析中间态/待焚原件（三通道同一状态机）。
    ref.watch(captureControllerProvider(widget.seed));

    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          // 统一抽屉高度（本次 UX 插曲新增口径，§9.3#3 弹簧抽屉的延伸约束）：
          // 写/说/拍通道切换、单边档位切换、AI 阶段流转均不改变抽屉尺寸
          // （与独立 showCaptureSheet 同口径，captureSheetHeight）。
          key: captureSheetSizeKey,
          height: captureSheetHeight(context),
          child: Padding(
            // 键盘避让（与 plan 系编辑抽屉同款 viewInsets 补距）：内容区
            // 收缩、钉底 CTA 恒在键盘上方，外框高度不变（Android 15+
            // edge-to-edge 窗口不随键盘收缩，须自行让出键盘）。
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(child: _body(context)),
                // 通道切换条贴底（大厂输入面板口径：模式切换=底部导航条，
                // 三等宽），内容区在其上填充。
                _ChannelBar(
                  channel: _channel,
                  onSelected: (channel) {
                    setState(() => _channel = channel);
                    // W7-8 录入漏斗（§12 验收口径「录入渠道选择」）：写/说/拍选择
                    // 即记（props 仅通道枚举标量，§3.9 隐私口径）。
                    unawaited(ref
                        .read(telemetryServiceProvider)
                        .funnel(
                          TelemetryFunnel.captureChannelSelected,
                          props: <String, Object?>{'channel': channel.name},
                        ));
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 通道体：「写」= CapturePage（feature_capture 唯一录入 UI，§10.4）；
  /// 「说」= VoiceCapturePanel（W5-6 Fake 链路，§3.3）；「拍」=
  /// PhotoCapturePanel（W11-12 拍照路径，§11.2 任务 2）。
  Widget _body(BuildContext context) {
    switch (_channel) {
      case _CaptureChannel.text:
        // showPhotoEntry=false：拍照入口收敛到「拍」通道（单一入口纪律），
        // 写通道 AI 输入区不再重复内嵌拍照/相册按钮。
        return CapturePage(
          seed: widget.seed,
          onSubmitted: widget.onSubmitted,
          showPhotoEntry: false,
        );
      case _CaptureChannel.voice:
        return VoiceCapturePanel(
          seed: widget.seed,
          onSubmitted: widget.onSubmitted,
          onSwitchChannel: () =>
              setState(() => _channel = _CaptureChannel.text),
        );
      case _CaptureChannel.photo:
        return PhotoCapturePanel(
          seed: widget.seed,
          onSubmitted: widget.onSubmitted,
          onSwitchChannel: () =>
              setState(() => _channel = _CaptureChannel.text),
        );
    }
  }
}

/// 通道切换条（§3.3 三通道；chip 微交互 dur.s，§9.2）。三段 Expanded
/// 等宽（大厂分段控件口径——此前仅「拍」被 Expanded 拉伸致大小不一）。
class _ChannelBar extends StatelessWidget {
  const _ChannelBar({required this.channel, required this.onSelected});

  final _CaptureChannel channel;
  final ValueChanged<_CaptureChannel> onSelected;

  @override
  Widget build(BuildContext context) {
    // 贴底导航条位：上边距收窄、下边距留出安全区呼吸。
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: _chip(
              context,
              key: captureChannelTextKey,
              icon: Icons.edit_outlined,
              label: '写',
              selected: channel == _CaptureChannel.text,
              onTap: () => onSelected(_CaptureChannel.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _chip(
              context,
              key: captureChannelVoiceKey,
              icon: Icons.mic_none,
              label: '说',
              selected: channel == _CaptureChannel.voice,
              onTap: () => onSelected(_CaptureChannel.voice),
            ),
          ),
          const SizedBox(width: 8),
          // 拍：W11-12 启用（§11.2 任务 2「录入页『拍』段启用」）：经
          // PhotoCapturePanel 接 feature_capture 拍照路径（CaptureImageSource
          // 壳注入 → §3.7 闸门分流 → 确认卡复用 → 即焚，§3.3）。
          Expanded(
            child: _chip(
              context,
              key: captureChannelPhotoKey,
              icon: Icons.photo_camera_outlined,
              label: '拍',
              selected: channel == _CaptureChannel.photo,
              onTap: () => onSelected(_CaptureChannel.photo),
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
        borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
        border: Border.all(
          color: selected ? tokens.primary : tokens.outline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(context.sizes.radiusGroupCard),
          onTap: onTap,
          child: SizedBox(
            // §6.3/§13.2 触控目标 ≥48（SlimcaSizes.minTouchTarget 已定稿）。
            height: context.sizes.minTouchTarget,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: context.sizes.iconVisual,
                  color: selected
                      ? tokens.primary
                      : (enabled ? tokens.onSurfaceMuted : tokens.outline),
                ),
                SizedBox(width: context.spacing.space100),
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
