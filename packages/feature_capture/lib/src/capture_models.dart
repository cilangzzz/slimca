/// 录入域的表单状态模型（§3.3 录入抽屉写通道、§3.4 记账表单字段）。
///
/// [CaptureFormState] 是 Riverpod 控制器的不可变状态：金额输入串（分转换
/// 见 `capture_money.dart`）、方向、分类/账本、日期、备注与单边开关。
/// 编辑模式经 [CaptureEditTarget] 携带被修正行（§3.4 修正=新增行）。
library;

import 'package:core_domain/core_domain.dart' as dom;

import 'capture_money.dart';

/// 单边开关（§3.3「仅记钱 / 仅记热量，schema 中对应 lines 只产出一类」）。
///
/// W2 手动路径只开放 [money] 侧；[calorie] 侧是 W3-4 AI 双解析预留的
/// 输入区占位（§11.1 W3-4），state 字段先行冻结、UI 渲染占位且不可提交。
enum CaptureSide {
  money('money'),
  calorie('calorie');

  const CaptureSide(this.wire);

  /// 存储用文本（与 §3.3 语义一致）。
  final String wire;
}

/// 录入抽屉打开参数（Riverpod family 注入，§10.4）。
class CaptureSeed {
  const CaptureSeed({this.editEntryId, this.initialDate});

  /// 非空 = 编辑模式：对既有记录做修正（§3.4「修正=新增行」）。
  final String? editEntryId;

  /// 仪表盘当前选中日（yyyy-MM-dd 本地日历日，§5.1）；缺省=今天。
  final String? initialDate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CaptureSeed &&
          other.editEntryId == editEntryId &&
          other.initialDate == initialDate;

  @override
  int get hashCode => Object.hash(editEntryId, initialDate);
}

/// 账本选项（§5.4④ ledgers；MVP 恒默认 money 账本）。
class CaptureLedgerOption {
  const CaptureLedgerOption({
    required this.id,
    required this.name,
    required this.currency,
  });

  final String id;
  final String name;
  final String currency;
}

/// 分类选项（§5.4⑤ categories；[colorToken] 引用语义 token 名而非裸色值）。
class CaptureCategoryOption {
  const CaptureCategoryOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.colorToken,
    required this.isPreset,
  });

  final String id;
  final String name;
  final String icon;
  final String colorToken;
  final bool isPreset;
}

/// 编辑模式目标：被修正的既有记录 + 其 active money 行（§3.4 金额不可变）。
class CaptureEditTarget {
  const CaptureEditTarget({
    required this.entryId,
    required this.oldLineId,
    required this.amountMinor,
    required this.direction,
    required this.categoryId,
    required this.ledgerId,
    required this.currency,
    required this.date,
    required this.tzOffsetMin,
    required this.title,
    required this.note,
  });

  /// 事件主干 id（entries.id）。
  final String entryId;

  /// 被修正旧行 id（entry_lines.id；新行 correction_of 指向它，§5.2②）。
  final String oldLineId;
  final int amountMinor;
  final dom.LineDirection direction;
  final String? categoryId;
  final String? ledgerId;
  final String? currency;
  final String date;
  final int tzOffsetMin;
  final String title;
  final String? note;
}

/// 修正提交载荷（编辑模式 → [applyMoneyCorrection] 入参）。
class CaptureCorrectionRequest {
  const CaptureCorrectionRequest({
    required this.entryId,
    required this.oldLineId,
    required this.amountMinor,
    required this.direction,
    required this.categoryId,
    required this.ledgerId,
    required this.title,
    required this.note,
    required this.date,
    required this.tzOffsetMin,
  });

  final String entryId;
  final String oldLineId;
  final int amountMinor;
  final dom.LineDirection direction;
  final String? categoryId;
  final String ledgerId;
  final String title;
  final String? note;
  final String date;
  final int tzOffsetMin;
}

/// 录入表单状态（控制器 [CaptureController] 的值类型）。
class CaptureFormState {
  const CaptureFormState({
    required this.side,
    required this.amountText,
    required this.direction,
    required this.categoryId,
    required this.ledgerId,
    required this.date,
    required this.tzOffsetMin,
    required this.title,
    required this.note,
    required this.ledgers,
    required this.categories,
    required this.editTarget,
    required this.submitting,
    required this.errorText,
  });

  /// 单边开关（§3.3）：W2 默认 [CaptureSide.money]。
  final CaptureSide side;

  /// 金额输入串（键入原文，分转换见 [amountMinor]）。
  final String amountText;
  final dom.LineDirection direction;
  final String? categoryId;
  final String? ledgerId;

  /// 归属日（yyyy-MM-dd 本地日历日，§5.1）。
  final String date;
  final int tzOffsetMin;

  /// 标题（§5.2① title：一句话描述；空则提交时回填分类名/方向名）。
  final String title;
  final String note;

  /// 可选账本（MVP 恒默认账本，§3.4 单账本 MVP）。
  final List<CaptureLedgerOption> ledgers;

  /// 按当前方向过滤后的分类（kind=expense/income，§5.4⑤）。
  final List<CaptureCategoryOption> categories;

  /// 编辑模式目标；null = 新建。
  final CaptureEditTarget? editTarget;

  /// 提交进行中（按钮禁用 + 进度反馈）。
  final bool submitting;

  /// 最近一次提交失败的提示（成功提交/再次尝试时清空）。
  final String? errorText;

  /// 金额分值；输入不完整/为 0 时为 null 或 0（§5.1 整数分）。
  int? get amountMinor => CaptureMoney.toMinorUnits(amountText);

  /// 编辑模式判定（§3.4 修正=新增行）。
  bool get isEditing => editTarget != null;

  /// 是否允许提交：仅记钱侧、金额 >0、账本已定、不在提交中。
  bool get canSubmit =>
      side == CaptureSide.money &&
      !submitting &&
      (amountMinor ?? 0) > 0 &&
      ledgerId != null;

  /// 当前选中账本的币种（money 行默认 CNY，§5.2②）。
  String? get selectedCurrency {
    for (final ledger in ledgers) {
      if (ledger.id == ledgerId) return ledger.currency;
    }
    return null;
  }

  /// 当前选中分类名（标题回填用）。
  String? get selectedCategoryName {
    for (final option in categories) {
      if (option.id == categoryId) return option.name;
    }
    return null;
  }

  static const Object _unchanged = Object();

  /// 不可变更新；可空字段（categoryId/ledgerId/editTarget/errorText）以
  /// 哨兵参数区分「不改动」与「置 null」。
  CaptureFormState copyWith({
    CaptureSide? side,
    String? amountText,
    dom.LineDirection? direction,
    Object? categoryId = _unchanged,
    Object? ledgerId = _unchanged,
    String? date,
    int? tzOffsetMin,
    String? title,
    String? note,
    List<CaptureLedgerOption>? ledgers,
    List<CaptureCategoryOption>? categories,
    Object? editTarget = _unchanged,
    bool? submitting,
    Object? errorText = _unchanged,
  }) =>
      CaptureFormState(
        side: side ?? this.side,
        amountText: amountText ?? this.amountText,
        direction: direction ?? this.direction,
        categoryId: identical(categoryId, _unchanged)
            ? this.categoryId
            : categoryId as String?,
        ledgerId:
            identical(ledgerId, _unchanged) ? this.ledgerId : ledgerId as String?,
        date: date ?? this.date,
        tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
        title: title ?? this.title,
        note: note ?? this.note,
        ledgers: ledgers ?? this.ledgers,
        categories: categories ?? this.categories,
        editTarget:
            identical(editTarget, _unchanged) ? this.editTarget : editTarget as CaptureEditTarget?,
        submitting: submitting ?? this.submitting,
        errorText: identical(errorText, _unchanged)
            ? this.errorText
            : errorText as String?,
      );
}
