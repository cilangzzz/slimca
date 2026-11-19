/// 录入域的表单状态模型（§3.3 录入抽屉写通道、§3.4 记账表单字段、§11.1 W3-4）。
///
/// [CaptureFormState] 是 Riverpod 控制器的不可变状态，承载两条写路径：
/// - W2 手动 money 表单（数字键盘/方向/分类/账本/日期/备注）；
/// - W3-4 AI 双解析流（§3.3）：文本输入 → 解析中 → 确认卡 / 失败降级手填，
///   状态机见 [CaptureAiStage]。
/// 编辑模式经 [CaptureEditTarget] 携带被修正行（§3.4 修正=新增行）。
library;

import 'package:core_domain/core_domain.dart' as dom;

import 'capture_money.dart';
import 'capture_parser.dart';
import 'capture_photo_models.dart';

/// 单边开关（§3.3「仅记钱 / 仅记热量，schema 中对应 lines 只产出一类」）。
///
/// W3-4 语义：
/// - [both]（默认）：AI 双解析，确认卡按解析结果产出 calorie+money 行；
/// - [money]：W2 手动记账表单（纯记账用户不被热量字段骚扰，§2.4-2），
///   也是解析失败的降级目标之一；
/// - [calorie]：AI 双解析的 kcal-only 模式——确认卡只产 calorie 行
///   （W3-4 主线任务「单边开关接仅记热量」）。
enum CaptureSide {
  both('both'),
  money('money'),
  calorie('calorie');

  const CaptureSide(this.wire);

  /// 存储用文本（与 §3.3 语义一致）。
  final String wire;
}

/// AI 双解析流状态机（§3.3「文本输入区 → 解析 → 确认卡」、§2.3 步骤 2-4）。
///
/// 兼容注记（§11.2 W11-12）：拍照处理中**不新增枚举值**——复用 [parsing]
/// 呼吸态 + [CaptureFormState.photoProcessingLabel] 分段文案（压缩中… →
/// 识别中…/端侧粗估中…）。Dart 3 对枚举穷举 switch 是编译期硬约束，本枚举
/// 加值会破坏既有宿主面板（语音通道）的穷举 switch 编译；拍照通道的语义
/// 由 pendingPhoto/pendingSource 承载，不靠阶段值区分。
enum CaptureAiStage {
  /// 文本输入区（含最近 chip 复记入口，§2.4）。
  input,

  /// 解析中/拍照处理中呼吸态（骨架出现 ≤100ms，§9.4；拍照通道经
  /// [CaptureFormState.photoProcessingLabel] 分段，§11.2）。
  parsing,

  /// 确认卡（AI 初值预填 + count-up + 环 sweep + 置信度三色点，§9.3#4）。
  confirm,

  /// 解析失败降级手填表单（原输入保留，§7.4、§2.4-3）。
  manualFallback,
}

/// AI 初值快照（§5.6⑮ corrections 差异审计的「前值」侧：AI 预填 vs 用户确认）。
///
/// 复记（chip）与手动降级提交没有 AI 初值（null），不写差异审计行。
class CaptureAiInitials {
  const CaptureAiInitials({
    required this.title,
    required this.kcalConfidence,
    required this.moneyConfidence,
    this.kcal,
    this.moneyMinor,
    this.categoryId,
  });

  /// AI 建议标题（§7.3 title）。
  final String title;

  /// AI 初值热量（kcal）。
  final int? kcal;

  /// 热量行置信度（§7.3，三档色点口径 §2.3 步骤 3）。
  final double? kcalConfidence;

  /// AI 初值金额（分）。
  final int? moneyMinor;

  /// 金额行置信度。
  final double? moneyConfidence;

  /// AI 建议分类 id（category_hint 命中结果，§7.3）。
  final String? categoryId;
}

/// 录入抽屉打开参数（Riverpod family 注入，§10.4）。
class CaptureSeed {
  const CaptureSeed({this.editEntryId, this.initialDate});

  /// 非空 = 编辑模式：对既有记录做修正（§3.4「修正=新增行」），
  /// 编辑模式恒走 W2 money 手动表单（金额行修正链）。
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

/// AI 确认卡/降级表单/复记的提交载荷（W3-4 写路径 → 网关，§3.3/§11.1 W3-4）。
///
/// 行集合由单边开关过滤（§3.3：kcal-only 模式只产 calorie 行）；kind 由
/// 行集合推导（§5.2①：双行=mixed、仅热量=food（任务称 meal，文档枚举无
/// meal、餐食语义对应 food）、仅金额=expense）。
class CaptureAiSubmitRequest {
  const CaptureAiSubmitRequest({
    required this.date,
    required this.tzOffsetMin,
    required this.title,
    required this.source,
    this.note,
    this.aiParseId,
    this.kcal,
    this.kcalConfidence,
    this.moneyConfidence,
    this.items = const [],
    this.portionMultiplier,
    this.amountMinor,
    this.moneyDirection = dom.LineDirection.outcome,
    this.ledgerId,
    this.categoryId,
    this.currency,
    this.aiInitials,
  });

  final String date;
  final int tzOffsetMin;

  /// 标题（AI 建议/用户改写/原文，§5.2①）。
  final String title;
  final String? note;

  /// 录入来源：text（AI 解析）/ chip（复记）/ manual（降级手填）（§5.2① source）。
  final dom.EntrySource source;

  /// → ai_parses.id 溯源（AI/缓存路径非空；chip/manual 为 null，§5.2①）。
  final String? aiParseId;

  // ── calorie 行（§5.2②；归集到内置 kcal 账本）───────────────────
  final int? kcal;
  final double? kcalConfidence;

  /// money 行置信度（AI 产出行必填，§5.2②；chip/manual 为 null）。
  final double? moneyConfidence;

  /// 菜品明细（§7.3 items[] → food_items 逐菜品）。
  final List<CaptureConfirmedItem> items;

  /// 确认时的份量倍率（payload 摘要留痕，§3.3 份量滑杆；1.0 可空省略）。
  final double? portionMultiplier;

  // ── money 行（§5.2②；确认后不可变）────────────────────────────
  final int? amountMinor;
  final dom.LineDirection moneyDirection;
  final String? ledgerId;
  final String? categoryId;
  final String? currency;

  /// AI 初值快照（非空时网关写「AI 初值 vs 用户确认」差异审计行，
  /// §5.6⑮ source=ai_corrected；chip/manual 为 null）。
  final CaptureAiInitials? aiInitials;

  bool get hasCalorie => (kcal ?? 0) > 0;
  bool get hasMoney => (amountMinor ?? 0) > 0;
}

/// 确认后的菜品明细（food_items 行载荷，§5.2③；份量滑杆联动重算后数值）。
class CaptureConfirmedItem {
  const CaptureConfirmedItem({
    required this.name,
    required this.portionG,
    required this.kcal,
    required this.confidence,
    this.proteinG = 0,
    this.carbG = 0,
    this.fatG = 0,
    this.refSource = 'local',
    this.refId,
  });

  final String name;
  final double portionG;
  final int kcal;
  final double proteinG;
  final double carbG;
  final double fatG;
  final String refSource;
  final String? refId;
  final double confidence;
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
    this.aiStage = CaptureAiStage.input,
    this.inputText = '',
    this.parseResult,
    this.parseFromCache = false,
    this.aiParseId,
    this.aiInitials,
    this.pendingPhoto,
    this.photoProcessingLabel,
    this.confirmKcal,
    this.portionBaseKcal,
    this.portionMultiplier = 1.0,
    this.manualKcalText = '',
    this.fallbackHint,
    this.pendingSource = dom.EntrySource.text,
    this.pendingMoneyDirection = dom.LineDirection.outcome,
  });

  // ── 单边开关与 W2 手动 money 表单（§3.3/§3.4）──────────────────
  final CaptureSide side;

  /// 金额输入串（键入/确认卡点改原文，分转换见 [amountMinor]）。
  final String amountText;
  final dom.LineDirection direction;
  final String? categoryId;
  final String? ledgerId;

  /// 归属日（yyyy-MM-dd 本地日历日，§5.1）。
  final String date;
  final int tzOffsetMin;

  /// 标题（§5.2① title；AI 路径=解析建议/用户改写）。
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

  // ── W3-4 AI 双解析流（§3.3、§11.1 W3-4）────────────────────────
  final CaptureAiStage aiStage;

  /// 文本输入区原文（解析失败降级后原样保留，§7.4/§2.4-3）。
  final String inputText;

  /// 最近一次解析结果（确认卡数据源；input stage 为 null）。
  final CaptureParseResult? parseResult;

  /// 本次确认卡是否来自 input_hash 缓存命中（§3.3/§5.6⑭）。
  final bool parseFromCache;

  /// 本次解析的 ai_parses 行 id（entries.ai_parse_id 溯源，§5.2①）。
  final String? aiParseId;

  /// AI 初值快照（差异审计「前值」，§5.6⑮；chip/manual 为 null）。
  final CaptureAiInitials? aiInitials;

  /// 待焚拍照原件（§11.2 W11-12 任务 3「解析后即焚」，§5.6㉑ attachments）：
  /// 非空 = 本笔来自拍照通道（source 记 photo，§5.2①）；确认落库成功后登记
  /// attachments 行（burned）并删除本地临时文件；取消/切钱侧等放弃路径仅删
  /// 文件（行尚未登记）。即焚前的确认承诺见控制器（§11.2 任务 4）。
  final CapturePendingPhoto? pendingPhoto;

  /// 拍照呼吸态分段文案（压缩中… → 识别中… / 端侧粗估中…，§9.4/§11.2）。
  /// 语义：非空 = aiStage 处于 parsing 且本笔是拍照通道的处理等待（不新增
  /// CaptureAiStage 枚举值的兼容设计，见 [CaptureAiStage] 注记）；文本/语音
  /// 解析恒 null（呼吸态默认文案）。
  final String? photoProcessingLabel;

  /// 确认卡当前热量（= portionBaseKcal × portionMultiplier，§3.3 滑杆联动重算）。
  final int? confirmKcal;

  /// 热量重算基准（AI 初值或 chip 原值；滑杆缩放的分母）。
  final int? portionBaseKcal;

  /// 份量倍率（滑杆 0.5-2.0，§3.3 份量滑杆）。
  final double portionMultiplier;

  /// 降级手填表单的热量输入（kcal 整数文本）。
  final String manualKcalText;

  /// 解析失败提示（降级表单顶部横幅，§7.4）。
  final String? fallbackHint;

  /// 待提交来源（确认=AI text / chip=复记 / 降级=manual / 拍照通道=photo
  /// （含拍照降级手填，§11.2 W11-12），§5.2① source）。
  final dom.EntrySource pendingSource;

  /// 待提交 money 行方向（AI 路径恒 out；chip 复记继承原行方向）。
  final dom.LineDirection pendingMoneyDirection;

  // ── 派生量 ──────────────────────────────────────────────────────

  /// 金额分值；输入不完整/为 0 时为 null 或 0（§5.1 整数分）。
  int? get amountMinor => CaptureMoney.toMinorUnits(amountText);

  /// 编辑模式判定（§3.4 修正=新增行）。
  bool get isEditing => editTarget != null;

  /// 是否处于 AI 双解析流（§3.3；money 侧为 W2 手动表单）。
  bool get isAiFlow => side != CaptureSide.money;

  /// 本笔是否来自拍照通道（§11.2 W11-12：pendingPhoto 非空 = source 记
  /// photo；与 aiStage 无关——降级手填/确认卡阶段同样携带待焚原件）。
  bool get hasPendingPhoto => pendingPhoto != null;

  /// 确认卡是否渲染热量区（§3.3 单边开关：仅记热量只产 calorie 行）。
  bool get showCalorieInConfirm => side != CaptureSide.money;

  /// 确认卡是否渲染金额区（§3.3 单边开关：仅记热量不产 money 行）。
  bool get showMoneyInConfirm => side != CaptureSide.calorie;

  /// W2 手动 money 表单是否允许提交（金额 >0、账本已定、不在提交中）。
  bool get canSubmit =>
      side == CaptureSide.money &&
      !submitting &&
      (amountMinor ?? 0) > 0 &&
      ledgerId != null;

  /// 确认卡是否允许「确认落库」：至少一行产出；有金额必须已选账本
  /// （§5.2② money 行必填）；仅记热量模式必须有热量。
  bool get canConfirm {
    if (aiStage != CaptureAiStage.confirm || submitting) return false;
    final kcal = confirmKcal ?? 0;
    final money = amountMinor ?? 0;
    if (side == CaptureSide.calorie) return kcal > 0;
    return (kcal > 0 || money > 0) && (money <= 0 || ledgerId != null);
  }

  /// 降级手填表单热量解析值（空=未填；非法/超 [0,5000] = null，§7.1 校验器）。
  int? get manualKcalValue {
    final t = manualKcalText.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0 || v > kMaxParseKcal) return null;
    return v;
  }

  /// 降级表单热量输入是否非法（横幅提示用）。
  bool get manualKcalInvalid =>
      manualKcalText.trim().isNotEmpty && manualKcalValue == null;

  /// 降级表单是否允许提交：至少一行产出；有金额必须已选账本。
  bool get canSubmitFallback {
    if (aiStage != CaptureAiStage.manualFallback || submitting) return false;
    final kcal = manualKcalValue;
    final money = amountMinor ?? 0;
    if (manualKcalInvalid) return false;
    if (side == CaptureSide.calorie) return (kcal ?? 0) > 0;
    return (kcal != null || money > 0) && (money <= 0 || ledgerId != null);
  }

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

  /// 不可变更新；可空字段（categoryId/ledgerId/editTarget/errorText/
  /// parseResult/aiParseId/aiInitials/pendingPhoto/photoProcessingLabel/
  /// confirmKcal/portionBaseKcal/fallbackHint）以哨兵参数区分「不改动」
  /// 与「置 null」。
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
    CaptureAiStage? aiStage,
    String? inputText,
    Object? parseResult = _unchanged,
    bool? parseFromCache,
    Object? aiParseId = _unchanged,
    Object? aiInitials = _unchanged,
    Object? pendingPhoto = _unchanged,
    Object? photoProcessingLabel = _unchanged,
    Object? confirmKcal = _unchanged,
    Object? portionBaseKcal = _unchanged,
    double? portionMultiplier,
    String? manualKcalText,
    Object? fallbackHint = _unchanged,
    dom.EntrySource? pendingSource,
    dom.LineDirection? pendingMoneyDirection,
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
        aiStage: aiStage ?? this.aiStage,
        inputText: inputText ?? this.inputText,
        parseResult: identical(parseResult, _unchanged)
            ? this.parseResult
            : parseResult as CaptureParseResult?,
        parseFromCache: parseFromCache ?? this.parseFromCache,
        aiParseId: identical(aiParseId, _unchanged)
            ? this.aiParseId
            : aiParseId as String?,
        aiInitials: identical(aiInitials, _unchanged)
            ? this.aiInitials
            : aiInitials as CaptureAiInitials?,
        pendingPhoto: identical(pendingPhoto, _unchanged)
            ? this.pendingPhoto
            : pendingPhoto as CapturePendingPhoto?,
        photoProcessingLabel: identical(photoProcessingLabel, _unchanged)
            ? this.photoProcessingLabel
            : photoProcessingLabel as String?,
        confirmKcal: identical(confirmKcal, _unchanged)
            ? this.confirmKcal
            : confirmKcal as int?,
        portionBaseKcal: identical(portionBaseKcal, _unchanged)
            ? this.portionBaseKcal
            : portionBaseKcal as int?,
        portionMultiplier: portionMultiplier ?? this.portionMultiplier,
        manualKcalText: manualKcalText ?? this.manualKcalText,
        fallbackHint: identical(fallbackHint, _unchanged)
            ? this.fallbackHint
            : fallbackHint as String?,
        pendingSource: pendingSource ?? this.pendingSource,
        pendingMoneyDirection: pendingMoneyDirection ?? this.pendingMoneyDirection,
      );
}
