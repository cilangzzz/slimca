/// 录入页 CapturePage（§3.3 写通道、§11.1 W2「手动记账 CRUD 全链路」+ W3-4
/// 「AI 双解析闭环（文本）」）。
///
/// 组成（§3.3 录入抽屉）：单边开关 → 按档位分流：
/// - 仅记钱：W2 手动表单（方向 → 数字键盘 → 标题/分类/账本/日期/备注 → 保存，
///   §3.4 流水；编辑模式恒走此表单，金额不可变=新增修正行）；
/// - 钱+热量 / 仅记热量：AI 双解析流状态机（[CaptureAiStage]）：
///   文本输入区（+最近 chip 复记入口，§2.4）→ 解析中呼吸态 → 确认卡
///   （AI 初值预填 + count-up + 环 sweep + 置信度三色点 + 份量滑杆，§9.3#4）
///   → 确认落库；解析失败自动降级手填表单且原文保留（§7.4、§2.4-3）。
///
/// 可经 [showCaptureSheet] 以弹簧 bottomSheet 唤起（§9.3#3），也可作为
/// 普通页面嵌入路由。提交经 [captureControllerProvider]（AsyncNotifier）编排。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'capture_controller.dart';
import 'capture_models.dart';
import 'widgets/capture_ai_input.dart';
import 'widgets/capture_amount_input.dart';
import 'widgets/capture_category_picker.dart';
import 'widgets/capture_confirm_card.dart';
import 'widgets/capture_date_row.dart';
import 'widgets/capture_direction_toggle.dart';
import 'widgets/capture_ledger_picker.dart';
import 'widgets/capture_parsing_state.dart';
import 'widgets/capture_recent_chips.dart';
import 'widgets/capture_side_toggle.dart';
import 'widgets/capture_text_field.dart';

/// 提交按钮测试锚点（W2 手动表单与 AI 降级表单共用，两分支互斥渲染）。
const Key captureSubmitKey = ValueKey('capture_submit');

/// 解析失败降级横幅测试锚点（§7.4）。
const Key captureFallbackBannerKey = ValueKey('capture_fallback_banner');

/// 唤起录入抽屉（§9.3#3 弹簧 bottomSheet，§4.3「capture 抽屉语义」）。
Future<void> showCaptureSheet(
  BuildContext context, {
  CaptureSeed seed = const CaptureSeed(),
  void Function(String entryId)? onSubmitted,
}) {
  return showSlimcaSpringSheet<void>(
    context: context,
    motion: MotionConfig.of(context),
    builder: (_) => CapturePage(seed: seed, onSubmitted: onSubmitted),
  );
}

/// 录入页：W2 手动记账 + W3-4 AI 双解析流。
class CapturePage extends ConsumerWidget {
  const CapturePage({
    super.key,
    this.seed = const CaptureSeed(),
    this.onSubmitted,
  });

  /// 打开参数（编辑模式经 [CaptureSeed.editEntryId]，§3.4 修正=新增行）。
  final CaptureSeed seed;

  /// 提交成功回调（传 entryId）；缺省=成功后自动关闭抽屉。
  final void Function(String entryId)? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final asyncForm = ref.watch(captureControllerProvider(seed));
    final form = asyncForm.value;

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CaptureHeader(form: form),
        if (form == null)
          // build 异步装载（账本/分类/最近 chips/编辑回填）：抽屉打开 ≤280ms
          // 预算内的过渡帧（§2.3 打开到可输入 ≤280ms）。
          const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          // 编辑模式恒为 W2 money 表单，单边开关不渲染（§3.4 修正链口径）。
          if (!form.isEditing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: CaptureSideToggle(
                value: form.side,
                onChanged: (side) => ref
                    .read(captureControllerProvider(seed).notifier)
                    .setSide(side),
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: form.side == CaptureSide.money
                  ? _moneyForm(context, ref, form)
                  : _aiFlowBody(context, ref, form),
            ),
          ),
          // W2 手动表单的页脚提交位；AI 流的提交按钮内嵌在确认卡/降级表单。
          if (form.side == CaptureSide.money)
            _submitFooter(context, ref, form),
        ],
      ],
    );

    return Material(
      color: tokens.surface,
      child: SafeArea(top: false, child: body),
    );
  }

  // ── W2 手动 money 表单（仅记钱 / 编辑模式，§3.4）──────────────────

  Widget _moneyForm(BuildContext context, WidgetRef ref, CaptureFormState form) {
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    final editTarget = form.editTarget;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('方向'),
        CaptureDirectionToggle(
          value: form.direction,
          onChanged: (direction) => notifier.setDirection(direction),
        ),
        const SizedBox(height: 14),
        CaptureAmountInput(
          amountText: form.amountText,
          direction: form.direction,
          originalAmountMinor: editTarget?.amountMinor,
          onDigit: notifier.inputDigit,
          onDot: notifier.inputDot,
          onBackspace: notifier.backspace,
        ),
        const SizedBox(height: 14),
        CaptureTextField(
          initial: form.title,
          hint: '标题（留空自动取分类名）',
          onChanged: notifier.setTitle,
        ),
        const SizedBox(height: 14),
        _FieldLabel('分类'),
        CaptureCategoryPicker(
          options: form.categories,
          selectedId: form.categoryId,
          onSelected: notifier.selectCategory,
        ),
        const SizedBox(height: 14),
        _FieldLabel('账本'),
        CaptureLedgerPicker(
          options: form.ledgers,
          selectedId: form.ledgerId,
          onSelected: notifier.selectLedger,
        ),
        const SizedBox(height: 14),
        CaptureDateRow(date: form.date, onPicked: notifier.setDate),
        const SizedBox(height: 14),
        CaptureTextField(
          initial: form.note,
          hint: '备注',
          maxLines: 2,
          onChanged: notifier.setNote,
        ),
      ],
    );
  }

  // ── W3-4 AI 双解析流（§3.3、§11.1 W3-4）──────────────────────────

  /// AI 流按 [CaptureAiStage] 分流：输入区 → 解析中呼吸态 → 确认卡 /
  /// 失败降级手填表单（§2.3 步骤 2-4、§7.4）。
  Widget _aiFlowBody(BuildContext context, WidgetRef ref, CaptureFormState form) {
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    switch (form.aiStage) {
      case CaptureAiStage.input:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 最近记录 chip 复记入口（§2.4-1「一键带入 ≤5 秒」）；空库不渲染。
            if (form.recentEntries.isNotEmpty) ...[
              CaptureRecentChips(
                entries: form.recentEntries,
                onSelected: notifier.applyRecentChip,
              ),
              const SizedBox(height: 14),
            ],
            CaptureAiInput(
              text: form.inputText,
              side: form.side,
              errorText: form.errorText,
              onChanged: notifier.setInputText,
              onParse: notifier.startParse,
            ),
          ],
        );
      case CaptureAiStage.parsing:
        // 解析中呼吸态（§9.4「AI 等待骨架出现 ≤100ms」：切阶段为同步 setState，
        // 网络等待发生在骨架之后）。
        return const CaptureParsingState();
      case CaptureAiStage.confirm:
        return CaptureConfirmCard(
          form: form,
          controller: notifier,
          onConfirm: () => _onAiSubmit(context, ref),
        );
      case CaptureAiStage.manualFallback:
        return _fallbackForm(context, ref, form);
    }
  }

  /// 失败降级手填表单（§7.4「原输入保留 → 自动降级手填表单」；§2.4-3
  /// 「输入页永不卡死」）：标题预填原文，热量/金额按单边开关裁剪。
  Widget _fallbackForm(
    BuildContext context,
    WidgetRef ref,
    CaptureFormState form,
  ) {
    final tokens = context.slimca;
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 降级提示横幅（§7.4 结构化失败文案 + 原文保留说明）。
        Container(
          key: captureFallbackBannerKey,
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
                  form.fallbackHint ?? 'AI 解析失败，已转手动填写（§7.4）',
                  style: TextStyle(fontSize: 12, color: tokens.onSurface),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        CaptureTextField(
          key: const ValueKey('capture_fallback_title'),
          initial: form.title,
          hint: '标题（原文已保留，可改）',
          onChanged: notifier.setTitle,
        ),
        if (form.showCalorieInConfirm) ...[
          const SizedBox(height: 14),
          _FieldLabel('热量（kcal）'),
          CaptureTextField(
            key: const ValueKey('capture_manual_kcal_field'),
            initial: form.manualKcalText,
            hint: form.manualKcalInvalid ? '须为 0-5000 的整数（§7.1）' : '如 550',
            keyboardType: TextInputType.number,
            onChanged: notifier.setManualKcalText,
          ),
        ],
        if (form.showMoneyInConfirm) ...[
          const SizedBox(height: 14),
          _FieldLabel('金额（元）'),
          CaptureTextField(
            key: const ValueKey('capture_manual_amount_field'),
            initial: form.amountText,
            hint: '如 18.50（最多两位小数，§5.1）',
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            onChanged: notifier.setAmountText,
          ),
        ],
        const SizedBox(height: 14),
        _FieldLabel('分类'),
        CaptureCategoryPicker(
          options: form.categories,
          selectedId: form.categoryId,
          onSelected: notifier.selectCategory,
        ),
        if (form.showMoneyInConfirm) ...[
          const SizedBox(height: 14),
          _FieldLabel('账本'),
          CaptureLedgerPicker(
            options: form.ledgers,
            selectedId: form.ledgerId,
            onSelected: notifier.selectLedger,
          ),
        ],
        const SizedBox(height: 14),
        CaptureDateRow(date: form.date, onPicked: notifier.setDate),
        const SizedBox(height: 14),
        CaptureTextField(
          initial: form.note,
          hint: '备注',
          maxLines: 2,
          onChanged: notifier.setNote,
        ),
        if (form.errorText != null) ...[
          const SizedBox(height: 8),
          Text(
            form.errorText!,
            key: const ValueKey('capture_error_text'),
            style: TextStyle(fontSize: 13, color: tokens.danger),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            TextButton(
              key: const ValueKey('capture_retry_parse_button'),
              onPressed: form.submitting ? null : notifier.backToInput,
              child: Text(
                '重试 AI 解析',
                style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SpringSubmitButton(
                label: '保存',
                enabled: form.canSubmitFallback,
                submitting: form.submitting,
                onPressed: () => _onAiSubmit(context, ref),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── 提交编排 ─────────────────────────────────────────────────────

  Widget _submitFooter(
    BuildContext context,
    WidgetRef ref,
    CaptureFormState form,
  ) {
    final tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (form.errorText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                form.errorText!,
                key: const ValueKey('capture_error_text'),
                style: TextStyle(fontSize: 13, color: tokens.danger),
              ),
            ),
          _SpringSubmitButton(
            label: form.isEditing ? '保存修正' : '保存',
            enabled: form.canSubmit,
            submitting: form.submitting,
            onPressed: () => _onMoneySubmit(context, ref),
          ),
        ],
      ),
    );
  }

  /// W2 提交（手动 money 表单）：成功后回调宿主或自动关闭抽屉（§4.3）。
  Future<void> _onMoneySubmit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    final entryId = await notifier.submit();
    if (entryId == null || !context.mounted) return;
    await _finishSubmit(context, entryId);
  }

  /// W3-4 提交（确认卡「确认落库」/ 降级表单「保存」）：经
  /// [CaptureController.submitPendingCapture] 同事务落库（§3.3）。
  Future<void> _onAiSubmit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    final entryId = await notifier.submitPendingCapture();
    if (entryId == null || !context.mounted) return;
    await _finishSubmit(context, entryId);
  }

  /// 提交成功收尾：回调宿主（纯通知——W7-8 漏斗埋点等，宿主不接管导航）+
  /// 关闭抽屉（§4.3 capture 抽屉语义：提交成功恒收起回到宿主页）。
  /// 调用方已在 await 后做过 context.mounted 检查。
  Future<void> _finishSubmit(BuildContext context, String entryId) async {
    // W7-8 集成修复：onSubmitted 是宿主的获取性提交通知（漏斗终点 §12），
    // 不是抽屉关闭的接管——原先「有回调则 return 不 pop」使 FAB 打开的
    // 录入抽屉提交后滞留（e2e ⑤ capture_submit 不收起 / 确认卡 pumpAndSettle
    // 超时）。关闭语义回归页面自身，回调只旁路通知。
    final callback = onSubmitted;
    if (callback != null) {
      callback(entryId);
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

/// 页头：标题 + 副标题（按模式分流）+ 关闭（§3.3 录入抽屉）。
class _CaptureHeader extends StatelessWidget {
  const _CaptureHeader({required this.form});

  final CaptureFormState? form;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final isEditing = form?.isEditing ?? false;
    final subtitle = isEditing
        ? '金额不可变，保存将新增修正行（§3.4）'
        : form?.side == CaptureSide.money
            ? '手动记账（§3.4 流水）'
            : 'AI 双解析（§3.3）：一句话 → 确认卡，低置信度必校';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing ? '编辑记录' : '记一笔',
                key: const ValueKey('capture_page_title'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: tokens.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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

/// 字段分组标签。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: tokens.onSurfaceMuted,
        ),
      ),
    );
  }
}

/// 提交按钮：按压 spring 微动效（§9.2 springSnappy 曲线驱动 scale，
/// §9.5 隐式动画仅限微交互）。
class _SpringSubmitButton extends StatefulWidget {
  const _SpringSubmitButton({
    required this.label,
    required this.enabled,
    required this.submitting,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  State<_SpringSubmitButton> createState() => _SpringSubmitButtonState();
}

class _SpringSubmitButtonState extends State<_SpringSubmitButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Listener(
      onPointerDown: widget.enabled
          ? (_) => setState(() => _pressed = true)
          : null,
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: motion.springSnappy.settleDuration,
        curve: motion.springSnappy.curve,
        child: FilledButton(
          key: captureSubmitKey,
          onPressed: widget.enabled ? widget.onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: tokens.primary,
            foregroundColor: tokens.onPrimary,
            disabledBackgroundColor: tokens.surfaceMuted,
            disabledForegroundColor: tokens.onSurfaceMuted,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: widget.submitting
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.onPrimary,
                  ),
                )
              : Text(
                  widget.label,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }
}
