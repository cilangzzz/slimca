/// 录入控制器（§10.1「Riverpod 3 AsyncNotifier 适配离线队列」）。
///
/// 职责：装载账本/分类选项与编辑回填（build 异步初始化），承接键盘输入、
/// 方向/分类/账本/日期/备注变更（§3.3 写通道），提交经 [CaptureGateway]
/// 落库（§3.3「提交经 EntryRepository 落库」）。编辑模式走修正链
/// （§3.4「修正=新增行」，金额不可变）。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_gateway.dart';
import 'capture_models.dart';
import 'capture_money.dart';

/// 录入控制器 provider（family 注入 [CaptureSeed]，autoDispose 跟随抽屉
/// 生命周期；§10.4）。
///
/// 用法：
/// ```dart
/// final form = ref.watch(captureControllerProvider(const CaptureSeed()));
/// ref.read(captureControllerProvider(seed).notifier).submit();
/// ```
final captureControllerProvider = AsyncNotifierProvider.family.autoDispose<
    CaptureController, CaptureFormState, CaptureSeed>(CaptureController.new);

/// 手动记账控制器：表单状态机 + 提交编排。
class CaptureController extends AsyncNotifier<CaptureFormState> {
  CaptureController(this.seed);

  /// 打开参数（编辑模式/初始日期，§3.4 修正=新增行）。
  final CaptureSeed seed;

  CaptureGateway get _gateway => ref.read(captureGatewayProvider);

  @override
  Future<CaptureFormState> build() async {
    final gateway = ref.watch(captureGatewayProvider);
    final now = DateTime.now();

    // MVP「恒默认账本」（§3.4 单账本 MVP）：空库时惰性建默认账本。
    var ledgers = await gateway.loadMoneyLedgers();
    if (ledgers.isEmpty) {
      await gateway.ensureDefaultLedger();
      ledgers = await gateway.loadMoneyLedgers();
    }
    final String? initialLedgerId = ledgers.isEmpty ? null : ledgers.first.id;

    // 编辑模式回填（§3.4：编辑不改旧行，提交=新增 correction 行）。
    var direction = dom.LineDirection.outcome;
    String? categoryId;
    String? ledgerId = initialLedgerId;
    var amountText = '';
    var date = seed.initialDate ?? dom.formatCalendarDay(now);
    var tzOffsetMin = now.timeZoneOffset.inMinutes;
    var title = '';
    var note = '';
    CaptureEditTarget? editTarget;
    final editId = seed.editEntryId;
    if (editId != null) {
      editTarget = await gateway.loadEditTarget(editId);
      if (editTarget != null) {
        amountText = CaptureMoney.fromMinorUnits(editTarget.amountMinor);
        direction = editTarget.direction;
        categoryId = editTarget.categoryId;
        ledgerId = editTarget.ledgerId ?? ledgerId;
        date = editTarget.date;
        tzOffsetMin = editTarget.tzOffsetMin;
        title = editTarget.title;
        note = editTarget.note ?? '';
      }
    }

    // 分类按方向装载（kind=expense/income，§5.4⑤）；方向翻转时类别不匹配
    // 的已选分类清空。
    final categories = await gateway.loadCategories(direction);
    final keepCategory =
        categoryId != null && categories.any((o) => o.id == categoryId);
    if (!keepCategory) {
      categoryId = null;
    }

    return CaptureFormState(
      side: CaptureSide.money,
      amountText: amountText,
      direction: direction,
      categoryId: categoryId,
      ledgerId: ledgerId,
      date: date,
      tzOffsetMin: tzOffsetMin,
      title: title,
      note: note,
      ledgers: ledgers,
      categories: categories,
      editTarget: editTarget,
      submitting: false,
      errorText: null,
    );
  }

  void _apply(CaptureFormState next) => state = AsyncData(next);

  /// 键入数字（分存储转换延迟到提交时，§5.1 整数分）。
  void inputDigit(String digit) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(
      amountText: CaptureMoney.appendDigit(current.amountText, digit),
      errorText: null,
    ));
  }

  /// 键入小数点。
  void inputDot() {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(
      amountText: CaptureMoney.appendDot(current.amountText),
      errorText: null,
    ));
  }

  /// 退格。
  void backspace() {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(
      amountText: CaptureMoney.backspace(current.amountText),
      errorText: null,
    ));
  }

  /// 单边开关（§3.3「仅记钱/仅记热量」）：calorie 侧 W2 仅渲染占位区，
  /// 不可提交（热量输入区 W3-4 接 AI 双解析，§11.1）。
  void setSide(CaptureSide side) {
    final current = state.value;
    if (current == null || current.side == side) return;
    _apply(current.copyWith(side: side, errorText: null));
  }

  /// 收支方向（§5.2② direction：expense=out / income=in）。
  Future<void> setDirection(dom.LineDirection direction) async {
    final current = state.value;
    if (current == null || current.direction == direction) return;
    final categories = await _gateway.loadCategories(direction);
    final keepCurrent =
        current.categoryId != null &&
            categories.any((o) => o.id == current.categoryId);
    _apply(current.copyWith(
      direction: direction,
      categories: categories,
      categoryId: keepCurrent ? current.categoryId : null,
      errorText: null,
    ));
  }

  void selectCategory(String? categoryId) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(categoryId: categoryId, errorText: null));
  }

  void selectLedger(String ledgerId) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(ledgerId: ledgerId, errorText: null));
  }

  /// 归属日（本地日历日 yyyy-MM-dd，§5.1：一切聚合按 date 分组）。
  void setDate(DateTime picked) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(date: dom.formatCalendarDay(picked)));
  }

  void setTitle(String title) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(title: title));
  }

  void setNote(String note) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(note: note));
  }

  /// 提交：新建=落一笔 money 记录；编辑=新增 correction 行 supersede 旧行
  /// （§3.4 金额不可变）。成功返回 entryId；被禁用/失败返回 null（失败
  /// 提示写入 [CaptureFormState.errorText]，不抛异常打断表单）。
  Future<String?> submit() async {
    final current = state.value;
    if (current == null || !current.canSubmit) return null;
    final gateway = _gateway;
    _apply(current.copyWith(submitting: true, errorText: null));
    try {
      final String entryId;
      if (current.isEditing) {
        entryId = await gateway.applyMoneyCorrection(_correctionRequest(current));
      } else {
        final normalized = _normalize(current);
        entryId = await gateway.submitMoneyCapture(
          date: current.date,
          tzOffsetMin: current.tzOffsetMin,
          title: normalized.title,
          note: normalized.note,
          amountMinor: current.amountMinor!,
          direction: current.direction,
          ledgerId: current.ledgerId!,
          categoryId: current.categoryId,
          currency: current.selectedCurrency,
        );
      }
      _apply(current.copyWith(submitting: false));
      return entryId;
    } catch (error) {
      // 离线优先体验：提交失败不打断表单，错误就地可见可重试（§3.7 本地优先）。
      _apply(current.copyWith(submitting: false, errorText: '提交失败，请重试'));
      return null;
    }
  }

  /// 新建载荷：标题回填「分类名 → 方向名」（§5.2① title 一句话描述），
  /// 备注空白归一为 null。
  ({String title, String? note}) _normalize(CaptureFormState form) {
    final trimmedTitle = form.title.trim();
    final resolvedTitle = trimmedTitle.isNotEmpty
        ? trimmedTitle
        : (form.selectedCategoryName ??
            (form.direction == dom.LineDirection.outcome ? '支出' : '收入'));
    final trimmedNote = form.note.trim();
    return (title: resolvedTitle, note: trimmedNote.isEmpty ? null : trimmedNote);
  }

  CaptureCorrectionRequest _correctionRequest(CaptureFormState form) {
    final normalized = _normalize(form);
    final editTarget = form.editTarget!;
    return CaptureCorrectionRequest(
      entryId: editTarget.entryId,
      oldLineId: editTarget.oldLineId,
      amountMinor: form.amountMinor!,
      direction: form.direction,
      categoryId: form.categoryId,
      ledgerId: form.ledgerId!,
      title: normalized.title,
      note: normalized.note,
      date: form.date,
      tzOffsetMin: form.tzOffsetMin,
    );
  }
}
