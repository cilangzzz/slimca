/// 手动记账录入页 CapturePage（§3.3 写通道、§11.1 W2「手动记账 CRUD 全链路」）。
///
/// 组成（§3.3 录入抽屉）：单边开关 → 方向 in/out → 金额数字键盘 → 标题/
/// 分类/账本/日期/备注 → 提交（spring 微动效，§9.2 springSnappy）。
/// 可经 [showCaptureSheet] 以弹簧 bottomSheet 唤起（§9.3#3），也可作为
/// 普通页面嵌入路由。
///
/// 提交语义（§3.4）：新建=entries(kind=expense)+entry_lines(type=money)；
/// 编辑=新增 correction 行 supersede 旧行（金额不可变）。提交经
/// [captureControllerProvider]（AsyncNotifier）编排。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'capture_controller.dart';
import 'capture_models.dart';
import 'widgets/capture_amount_input.dart';
import 'widgets/capture_category_picker.dart';
import 'widgets/capture_direction_toggle.dart';
import 'widgets/capture_ledger_picker.dart';
import 'widgets/capture_side_toggle.dart';

/// 提交按钮测试锚点。
const Key captureSubmitKey = ValueKey('capture_submit');

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

/// 手动记账录入页。
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
        _CaptureHeader(isEditing: form?.isEditing ?? false),
        if (form == null)
          // build 异步装载（账本/分类/编辑回填）：抽屉打开 ≤280ms 预算内的
          // 过渡帧（§2.3 打开到可输入 ≤280ms）。
          const SizedBox(
            height: 140,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
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
                  // §3.3 单边开关：热量输入区 W3-4 接 AI（占位）。
                  : _caloriePlaceholder(context),
            ),
          ),
          _submitFooter(context, ref, form),
        ],
      ],
    );

    return Material(
      color: tokens.surface,
      child: SafeArea(top: false, child: body),
    );
  }

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
        _CaptureTextField(
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
        _CaptureDateRow(date: form.date, onPicked: notifier.setDate),
        const SizedBox(height: 14),
        _CaptureTextField(
          initial: form.note,
          hint: '备注',
          maxLines: 2,
          onChanged: notifier.setNote,
        ),
      ],
    );
  }

  /// §3.3 单边开关的「仅记热量」占位区：W3-4 AI 双解析上线后替换为
  /// 菜品/份量输入（届时 lines 只产出一类 calorie）。
  Widget _caloriePlaceholder(BuildContext context) {
    final tokens = context.slimca;
    return Container(
      key: const ValueKey('capture_calorie_placeholder'),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_outlined,
              size: 40, color: tokens.kcalIn),
          const SizedBox(height: 12),
          Text(
            '热量输入区将在 W3-4 随 AI 双解析上线',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: tokens.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前版本先记钱；此处为单边开关预留位（§3.3）',
            style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
          ),
        ],
      ),
    );
  }

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
            onPressed: () => _onSubmit(context, ref),
          ),
        ],
      ),
    );
  }

  /// 提交编排：成功后回调宿主或自动关闭抽屉（§4.3 capture 抽屉语义）。
  Future<void> _onSubmit(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(captureControllerProvider(seed).notifier);
    final entryId = await notifier.submit();
    if (entryId == null) return;
    final callback = onSubmitted;
    if (callback != null) {
      callback(entryId);
      return;
    }
    if (!context.mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }
}

/// 页头：标题 + 关闭（§3.3 录入抽屉）。
class _CaptureHeader extends StatelessWidget {
  const _CaptureHeader({required this.isEditing});

  final bool isEditing;

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
                isEditing ? '金额不可变，保存将新增修正行（§3.4）' : '手动记账（§3.4 流水）',
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

/// 文本输入（标题/备注）：内部持有 controller，initial 外部变化时才回写，
/// 避免逐帧重建导致光标跳动。
class _CaptureTextField extends StatefulWidget {
  const _CaptureTextField({
    required this.initial,
    required this.hint,
    required this.onChanged,
    this.maxLines = 1,
  });

  final String initial;
  final String hint;
  final ValueChanged<String> onChanged;
  final int maxLines;

  @override
  State<_CaptureTextField> createState() => _CaptureTextFieldState();
}

class _CaptureTextFieldState extends State<_CaptureTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(_CaptureTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial &&
        widget.initial != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.initial,
        selection:
            TextSelection.collapsed(offset: widget.initial.characters.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      style: TextStyle(fontSize: 15, color: tokens.onSurface),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
        filled: true,
        fillColor: tokens.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: tokens.primary, width: 1.5),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// 日期行（§5.1 本地日历日 yyyy-MM-dd + tz_offset_min；tz 在提交时取当前）。
class _CaptureDateRow extends StatelessWidget {
  const _CaptureDateRow({required this.date, required this.onPicked});

  final String date;
  final ValueChanged<DateTime> onPicked;

  DateTime? _parseDay(String text) {
    final parts = text.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> _pick(BuildContext context) async {
    final initial = _parseDay(date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Material(
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('capture_date_row'),
        onTap: () => _pick(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 20, color: tokens.onSurfaceMuted),
              const SizedBox(width: 10),
              Text(
                date,
                style: TextStyle(fontSize: 15, color: tokens.onSurface),
              ),
              const Spacer(),
              Text(
                '归属日（可回记）',
                style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
              ),
            ],
          ),
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
