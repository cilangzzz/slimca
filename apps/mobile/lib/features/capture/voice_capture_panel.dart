/// 「说」通道面板（§3.3 语音通道、§11.1 W5-6「语音端侧 ASR+云兜底」）。
///
/// 链路（W5-6 只通 Fake，§3.3 注记）：[SpeechTranscriber]（缺省
/// FakeTranscriber，注入点 speechTranscriberProvider）→ 转写文本 → **复用
/// 收敛后的 AI 解析管线**：写回 captureControllerProvider 的 inputText 后
/// startParse()——规范化、input_hash、缓存命中、CaptureParser 解析、校验、
/// ai_parses 留痕、失败降级全部与文本通道同构（§7.1/§5.6⑭/§7.4），零复制。
///
/// 唯一差异在提交口（§5.2① source=voice）：确认卡复用 feature_capture 导出的
/// [CaptureConfirmCard]，onConfirm 由本面板组装 [CaptureAiSubmitRequest] 直调
/// captureGatewayProvider.submitAiCapture——与控制器 submitPendingCapture 的
/// 载荷装配逐字段同构（热量/金额/份量倍率缩放明细/aiInitials 差异审计），
/// 仅 source 换 voice（feature_capture 控制器 pendingSource 锚定 text，
/// W5-6 不越界改包，面板侧覆盖提交口）。
library;

import 'dart:async';

import 'package:core_domain/core_domain.dart' as dom;
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../voice/speech_transcriber.dart';

/// 麦克风按钮测试锚点。
const Key voiceCaptureMicKey = ValueKey('voice_capture_mic');

/// 转写文本展示测试锚点。
const Key voiceCaptureTranscriptKey = ValueKey('voice_capture_transcript');

/// 「解析」按钮测试锚点。
const Key voiceCaptureParseKey = ValueKey('voice_capture_parse');

/// 重新转写按钮测试锚点。
const Key voiceCaptureRetranscribeKey = ValueKey('voice_capture_retranscribe');

/// 说通道面板：转写 → 解析 → 确认落库（source=voice，§5.2①）。
class VoiceCapturePanel extends ConsumerStatefulWidget {
  const VoiceCapturePanel({
    super.key,
    this.seed = const CaptureSeed(),
    this.onSubmitted,
    required this.onSwitchChannel,
  });

  /// 与壳共享的打开参数（同一 CaptureSeed → 同一控制器实例，§10.4 family）。
  final CaptureSeed seed;

  /// 提交成功回调（传 entryId）；缺省=成功后自动关闭抽屉（§4.3）。
  final void Function(String entryId)? onSubmitted;

  /// 解析失败降级时切回「写」通道的回调（原文保留在控制器 inputText，
  /// §7.4——写通道降级表单可接着手填，不丢用户输入）。
  final VoidCallback onSwitchChannel;

  @override
  ConsumerState<VoiceCapturePanel> createState() => _VoiceCapturePanelState();
}

class _VoiceCapturePanelState extends ConsumerState<VoiceCapturePanel> {
  String? _transcript;
  bool _transcribing = false;
  bool _submitting = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final asyncForm = ref.watch(captureControllerProvider(widget.seed));
    final form = asyncForm.value;
    final notifier =
        ref.read(captureControllerProvider(widget.seed).notifier);
    final stage = form?.aiStage ?? CaptureAiStage.input;

    final body = <Widget>[];
    switch (stage) {
      case CaptureAiStage.input:
        body.addAll(_inputStage(context, form));
      case CaptureAiStage.parsing:
        // 解析中呼吸态（与文本通道同一骨架组件，§9.4 ≤100ms）。
        body.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CaptureParsingState(),
        ));
      case CaptureAiStage.confirm:
        if (form != null) {
          // 确认卡复用 feature_capture 导出组件；onConfirm 由本面板覆盖
          // 提交口（source=voice，§5.2①）。
          body.add(CaptureConfirmCard(
            form: form,
            controller: notifier,
            onConfirm: () => _submitVoice(form),
          ));
        }
      case CaptureAiStage.manualFallback:
        body.addAll(_fallbackStage(context, form, notifier));
    }

    return Material(
      color: tokens.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VoiceHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 转写输入段（stage=input）────────────────────────────────────

  List<Widget> _inputStage(BuildContext context, CaptureFormState? form) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final transcript = _transcript;
    return [
      // 麦克风主按钮（§3.3 语音通道入口；W5-6 经 FakeTranscriber 出文本）。
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Material(
              color: _transcribing ? tokens.surfaceMuted : tokens.primary,
              shape: const CircleBorder(),
              child: InkWell(
                key: voiceCaptureMicKey,
                customBorder: const CircleBorder(),
                onTap: _transcribing ? null : _startTranscribe,
                child: SizedBox(
                  width: 88,
                  height: 88,
                  child: Center(
                    child: _transcribing
                        ? SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: tokens.onSurfaceMuted,
                            ),
                          )
                        : Icon(Icons.mic, size: 36, color: tokens.onPrimary),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _transcribing ? '正在聆听…' : '点按说话',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (transcript != null) ...[
        // 转写文本（可直接改吗？——原文经控制器 inputText 进解析管线，
        // 展示只读；改写走「写」通道，§7.4 原文保留语义）。
        Container(
          key: voiceCaptureTranscriptKey,
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '「$transcript」',
            style: textTheme.bodyMedium?.copyWith(color: tokens.onSurface),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton(
              key: voiceCaptureRetranscribeKey,
              onPressed: _transcribing ? null : _startTranscribe,
              child: Text(
                '重新转写',
                style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: voiceCaptureParseKey,
                onPressed: _transcribing ? null : _startParse,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.primary,
                  foregroundColor: tokens.onPrimary,
                  disabledBackgroundColor: tokens.surfaceMuted,
                  disabledForegroundColor: tokens.onSurfaceMuted,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  '解析',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
      if (_errorText != null) ...[
        Text(
          _errorText!,
          key: const ValueKey('voice_capture_error'),
          style: TextStyle(fontSize: 13, color: tokens.danger),
        ),
        const SizedBox(height: 8),
      ],
      if (form != null && form.errorText != null)
        Text(
          form.errorText!,
          style: TextStyle(fontSize: 13, color: tokens.danger),
        ),
    ];
  }

  // ── 解析失败降级段（stage=manualFallback，§7.4）─────────────────

  List<Widget> _fallbackStage(
    BuildContext context,
    CaptureFormState? form,
    CaptureController notifier,
  ) {
    final tokens = context.slimca;
    return [
      Container(
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
                form?.fallbackHint ?? 'AI 解析失败（§7.4）',
                style: TextStyle(fontSize: 12, color: tokens.onSurface),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          // 原文保留在控制器（§7.4）：切回「写」通道后降级手填表单可接着改。
          TextButton(
            onPressed: widget.onSwitchChannel,
            child: Text(
              '切到「写」通道手填',
              style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => notifier.backToInput(),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.primary,
                foregroundColor: tokens.onPrimary,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                '返回重试',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // ── 转写与解析编排 ───────────────────────────────────────────────

  /// 转写：SpeechTranscriber 抽象（W5-6 缺省 Fake）+ ≤5s 预算（§2.3）。
  /// 成功后原文写进控制器 inputText——与文本通道同一条解析管线（§7.1）。
  Future<void> _startTranscribe() async {
    setState(() {
      _transcribing = true;
      _errorText = null;
    });
    try {
      final text = await ref
          .read(speechTranscriberProvider)
          .transcribe()
          .timeout(kVoiceTranscribeTimeout);
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _transcript = text;
      });
      ref
          .read(captureControllerProvider(widget.seed).notifier)
          .setInputText(text);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _errorText = '转写超时（语音 ≤5s，§2.3），请重试';
      });
    } on SpeechTranscribeException catch (error) {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _errorText = '转写失败：${error.message}（§3.3 可重试）';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _errorText = '转写失败，请重试（§3.3 语音通道失败分支）';
      });
    }
  }

  /// 解析：转写文本 → 控制器 AI 管线（setInputText → startParse，§3.3）。
  void _startParse() {
    final transcript = _transcript?.trim() ?? '';
    if (transcript.isEmpty) return;
    final notifier =
        ref.read(captureControllerProvider(widget.seed).notifier);
    notifier.setInputText(transcript);
    notifier.startParse();
  }

  /// 语音通道提交口（§5.2① source=voice）：载荷装配与
  /// CaptureController.submitPendingCapture 逐字段同构（热量/金额/份量倍率
  /// 缩放明细/aiInitials 差异审计，§3.3/§5.6⑮），仅 source 覆盖为 voice。
  /// 成功回调宿主或关闭抽屉（§4.3）；失败就地提示可重试（§2.4-3）。
  Future<void> _submitVoice(CaptureFormState form) async {
    if (_submitting || !form.canConfirm) return;
    final gateway = ref.read(captureGatewayProvider);
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      final kcal = form.showCalorieInConfirm ? form.confirmKcal : null;
      final amountMinor = form.showMoneyInConfirm ? form.amountMinor : null;
      final hasKcal = (kcal ?? 0) > 0;
      final hasMoney = (amountMinor ?? 0) > 0;
      final trimmedTitle = form.title.trim();
      final resolvedTitle = trimmedTitle.isNotEmpty
          ? trimmedTitle
          : (form.selectedCategoryName ?? '支出');
      final trimmedNote = form.note.trim();
      final result = form.parseResult;
      final multiplier = form.portionMultiplier;
      // 菜品明细随份量倍率联动缩放（§3.3 滑杆重算基准 portion_g）。
      final items = <CaptureConfirmedItem>[];
      if (hasKcal) {
        for (final line in result?.lines ?? const <CaptureParsedLine>[]) {
          for (final item in line.items) {
            items.add(CaptureConfirmedItem(
              name: item.name,
              portionG: item.portionG * multiplier,
              kcal: (item.kcal * multiplier).round(),
              proteinG: item.proteinG * multiplier,
              carbG: item.carbG * multiplier,
              fatG: item.fatG * multiplier,
              refSource: item.refSource,
              refId: item.refId,
              confidence: item.confidence,
            ));
          }
        }
      }
      final entryId = await gateway.submitAiCapture(CaptureAiSubmitRequest(
        date: form.date,
        tzOffsetMin: form.tzOffsetMin,
        title: resolvedTitle,
        note: trimmedNote.isEmpty ? null : trimmedNote,
        // 说通道语义：source=voice（§5.2① 录入来源清单）。
        source: dom.EntrySource.voice,
        aiParseId: form.aiParseId,
        kcal: hasKcal ? kcal : null,
        kcalConfidence: form.aiInitials?.kcalConfidence,
        moneyConfidence: form.aiInitials?.moneyConfidence,
        items: items,
        portionMultiplier: items.isEmpty ? null : multiplier,
        amountMinor: hasMoney ? amountMinor : null,
        // AI money 行方向恒支出（§5.2②，收入走 W2 手动表单）。
        moneyDirection: dom.LineDirection.outcome,
        ledgerId: hasMoney ? form.ledgerId : null,
        categoryId: form.categoryId,
        currency: form.selectedCurrency,
        aiInitials: form.aiInitials,
      ));
      if (!mounted) return;
      setState(() => _submitting = false);
      final callback = widget.onSubmitted;
      if (callback != null) {
        callback(entryId);
        return;
      }
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '提交失败，请重试（本地库写入，§3.7 离线优先）';
      });
    }
  }
}

/// 说通道页头（与 CapturePage 头部同形）：标题 + 副标题 + 关闭（§3.3）。
class _VoiceHeader extends StatelessWidget {
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
                '说一笔',
                key: const ValueKey('voice_capture_title'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: tokens.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '语音转写 → AI 解析（§3.3，W5-6 Fake 链路）',
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
