/// 「拍」通道面板（§3.3 拍照通道、§11.2 W11-12 任务 2「capture channels
/// sheet『拍』段启用：接 feature_capture 拍照路径」）。
///
/// 链路全部复用 feature_capture（§10.4 收敛纪律，壳零复制）：
/// - 入口区 [CapturePhotoEntry]（拍照/相册双入口 + §3.7 raw_input 口径隐私
///   提示文案随开关切换）；
/// - 编排 [CaptureController.startPhotoCapture]（共享 captureControllerProvider
///   实例——与「写/说」通道同一条状态机；sheet 顶层 watch 保活，family by
///   seed，§10.4）；
/// - 呼吸态 [CaptureParsingState]（分段文案 压缩中…→识别中…/端侧粗估中…，
///   §9.4/§11.2）；
/// - 确认卡 [CaptureConfirmCard]（复用份量滑杆/置信度点/count-up，§9.3#4；
///   onConfirm 走共享控制器 submitPendingCapture——即焚登记/临时文件删除/
///   photo_confirm 漏斗由控制器统一收口，§11.2 任务 3/5）；
/// - 失败降级（§7.4/§11.2 任务 4「绝不丢已拍数据」）：待焚原件保留在控制器
///   state，「切到『写』通道手填」复用写通道降级表单接续编辑，「返回重拍」
///   回拍照入口（原件在重拍时才被替换弃置）。
///
/// 本面板只做通道编排与阶段渲染（与 VoiceCapturePanel 同职责面）；拍照通道
/// 无语音通道的 source 覆盖问题——控制器 pendingSource 原生记 photo
/// （§5.2①），提交走共享 submitPendingCapture 即正确。
library;

import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

/// 页头标题测试锚点。
const Key photoCaptureTitleKey = ValueKey('photo_capture_title');

/// 拍通道降级横幅测试锚点（§7.4/§11.2 任务 4）。
const Key photoCaptureFallbackBannerKey =
    ValueKey('photo_capture_fallback_banner');

/// 「切到写通道手填」按钮测试锚点（降级跨通道接续，§7.4）。
const Key photoCaptureSwitchTextKey = ValueKey('photo_capture_switch_text');

/// 「返回重拍」按钮测试锚点（原件保留语义，§11.2 任务 4）。
const Key photoCaptureRetakeKey = ValueKey('photo_capture_retake');

/// 拍摄取景引导卡测试锚点（整卡可点发起拍照）。
const Key photoCaptureZoneKey = ValueKey('photo_capture_zone');

/// 拍通道面板：拍照/相册 → 识别/端侧粗估 → 确认落库（source=photo，§5.2①）。
class PhotoCapturePanel extends ConsumerStatefulWidget {
  const PhotoCapturePanel({
    super.key,
    this.seed = const CaptureSeed(),
    this.onSubmitted,
    required this.onSwitchChannel,
  });

  /// 与壳共享的打开参数（同一 CaptureSeed → 同一控制器实例，§10.4 family）。
  final CaptureSeed seed;

  /// 提交成功回调（传 entryId）：纯通知（§12 漏斗终点），不接管导航——提交
  /// 成功后抽屉恒由本面板自动关闭（§4.3，W7-8 集成修复口径）。
  final void Function(String entryId)? onSubmitted;

  /// 降级时切回「写」通道的回调（待焚原件与手填中间态在共享控制器 state，
  /// §7.4/§11.2 任务 4——写通道降级表单可接着编辑，不丢已拍数据）。
  final VoidCallback onSwitchChannel;

  @override
  ConsumerState<PhotoCapturePanel> createState() => _PhotoCapturePanelState();
}

class _PhotoCapturePanelState extends ConsumerState<PhotoCapturePanel> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // 共享控制器 watch（sheet 顶层已保活，此处取值渲染阶段，§10.4）。
    final asyncForm = ref.watch(captureControllerProvider(widget.seed));
    final form = asyncForm.value;
    final notifier = ref.read(captureControllerProvider(widget.seed).notifier);
    final stage = form?.aiStage ?? CaptureAiStage.input;

    final body = <Widget>[];
    switch (stage) {
      case CaptureAiStage.input:
        body.addAll(_inputStage(context, form, notifier));
      case CaptureAiStage.parsing:
        // 拍照处理中呼吸态（分段文案 压缩中…→识别中…/端侧粗估中…，§9.4/
        // §11.2；文本解析同阶段沿用默认文案）——填充式居中。
        body.add(Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: CaptureParsingState(
                label: form?.photoProcessingLabel ?? '拍照识别中…',
              ),
            ),
          ),
        ));
      case CaptureAiStage.confirm:
        if (form != null) {
          // 统一抽屉高度口径：卡面滚动 + 动作页脚钉底（确认落库 CTA 恒可见，
          // §2.3 步骤 5）；提交走共享控制器 submitPendingCapture——即焚/漏斗
          // 由控制器收口（§11.2）。
          return Material(
            color: tokens.surface,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PhotoHeader(),
                  Flexible(
                    child: CaptureConfirmStage(
                      form: form,
                      controller: notifier,
                      onConfirm: () => _submitPhoto(form, notifier),
                      scrollPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      case CaptureAiStage.manualFallback:
        body.addAll(_fallbackStage(context, form, notifier));
    }

    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PhotoHeader(),
            // 统一高度框内填充式布局：取景引导卡扩展吃满、主操作贴底；
            // 降级簇贴底（大厂输入面板口径，无空白死角）。
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 拍照入口段（stage=input）────────────────────────────────────

  List<Widget> _inputStage(
    BuildContext context,
    CaptureFormState? form,
    CaptureController notifier,
  ) {
    final tokens = context.slimca;
    // money 侧无拍照语义（§3.3：拍照通道产出热量行；仅记钱档是 W2 手动
    // 表单，控制器 startPhotoCapture 守卫同口径）。
    if (form != null && form.side == CaptureSide.money) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '仅记钱档为手动表单（§3.4），无拍照语义；请切「写」通道或回'
            '「钱+热量」档后使用拍照入口。',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
        ),
      ];
    }
    return [
      // 拍摄取景引导卡（composer 同款填充面：整卡可点=大命中目标 ≥48）——
      // 空白被取景面吸收；卡面不持有任何拍照逻辑（意图仍收口控制器）。
      Expanded(
        child: GestureDetector(
          key: photoCaptureZoneKey,
          onTap: () => notifier.startPhotoCapture(fromCamera: true),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: tokens.surfaceCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.outline),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_camera_outlined,
                      size: 40, color: tokens.onSurfaceMuted),
                  const SizedBox(height: 12),
                  Text(
                    '拍一张餐食或小票',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '自动识别热量与金额（§3.3）',
                    style: TextStyle(
                        fontSize: 12, color: tokens.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      // 拍照单一入口（全宽主按钮）+ §3.7 口径隐私提示（文案随 raw_input
      // 开关切换）；相册选择不再并列露出（§10.4 单一入口纪律）。
      CapturePhotoEntry(
        showGalleryEntry: false,
        onCamera: () => notifier.startPhotoCapture(fromCamera: true),
        onGallery: () => notifier.startPhotoCapture(fromCamera: false),
      ),
      if (form?.errorText != null) ...[
        const SizedBox(height: 8),
        CaptureErrorText(
          text: form!.errorText!,
          testKey: const ValueKey('photo_capture_error'),
        ),
      ],
    ];
  }

  // ── 失败降级段（stage=manualFallback，§7.4/§11.2 任务 4）──────────

  List<Widget> _fallbackStage(
    BuildContext context,
    CaptureFormState? form,
    CaptureController notifier,
  ) {
    final tokens = context.slimca;
    return [
      Container(
        key: photoCaptureFallbackBannerKey,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.warn.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: tokens.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                form?.fallbackHint ?? '拍照识别失败，已转手动填写（§7.4）',
                style: TextStyle(fontSize: 12, color: tokens.onSurface),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          // 待焚原件保留在共享控制器 state（§11.2 任务 4）：切「写」通道后
          // 降级手填表单可接着编辑，保存仍走拍照通道提交链（source=photo）。
          TextButton(
            key: photoCaptureSwitchTextKey,
            onPressed: widget.onSwitchChannel,
            child: Text(
              '切到「写」通道手填',
              style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              key: photoCaptureRetakeKey,
              onPressed: () => notifier.backToInput(),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.primary,
                foregroundColor: tokens.onPrimary,
                minimumSize: Size.fromHeight(context.sizes.minTouchTarget),
                shape: const StadiumBorder(), // §7.1 按钮胶囊（M3 full）
              ),
              child: const Text(
                '返回重拍',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ── 提交编排 ────────────────────────────────────────────────────

  /// 确认落库（共享控制器 submitPendingCapture——即焚登记 + 临时文件删除 +
  /// photo_confirm 漏斗终点由控制器统一收口，§11.2 任务 3/5）。成功回调宿主
  /// 或关闭抽屉（§4.3）；失败 errorText 就地提示可重试（§2.4-3）。
  Future<void> _submitPhoto(
    CaptureFormState form,
    CaptureController notifier,
  ) async {
    if (!form.canConfirm) return;
    final entryId = await notifier.submitPendingCapture();
    if (entryId == null || !mounted) return;
    final callback = widget.onSubmitted;
    if (callback != null) {
      callback(entryId);
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

/// 拍通道页头（与 CapturePage/VoiceCapturePanel 头部同形）：标题 + 副标题 +
/// 关闭（§3.3 录入抽屉）。
class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader();

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '拍一笔',
                key: photoCaptureTitleKey,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: tokens.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '拍照/相册 → 识别 → 确认落库（§3.3，原图确认后即焚）',
                style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '关闭',
            icon: Icon(Icons.close, color: tokens.onSurfaceMuted),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
