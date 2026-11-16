/// 录入控制器（§10.1「Riverpod 3 AsyncNotifier 适配离线队列」）。
///
/// 职责：装载账本/分类选项、最近 chips 与编辑回填（build 异步初始化），
/// 承载两条写路径（§11.1 W3-4）：
/// - W2 手动 money 表单：键盘输入/方向/分类/账本/日期/备注变更，提交经
///   [CaptureGateway.submitMoneyCapture] / [CaptureGateway.applyMoneyCorrection]
///   （§3.4 修正=新增行，金额不可变）；
/// - W3-4 AI 双解析流（§3.3/§7.1）：文本输入 → 解析（input_hash 缓存命中
///   直复用，§5.6⑭；未命中走注入的 [CaptureParser]）→ 确认卡（AI 初值
///   预填 + 份量滑杆联动重算）→ 确认经 [CaptureGateway.submitAiCapture]
///   落库；解析失败（结构化失败/超时，§7.4）→ 自动降级手填表单，
///   用户原文全程保留（§2.4-3「输入页永不卡死」）。
library;

import 'dart:async';

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_gateway.dart';
import 'capture_models.dart';
import 'capture_money.dart';
import 'capture_parser.dart';

/// 录入控制器 provider（family 注入 [CaptureSeed]，autoDispose 跟随抽屉
/// 生命周期；§10.4）。
///
/// 用法：
/// ```dart
/// final form = ref.watch(captureControllerProvider(const CaptureSeed()));
/// ref.read(captureControllerProvider(seed).notifier).startParse();
/// ```
final captureControllerProvider = AsyncNotifierProvider.family.autoDispose<
    CaptureController, CaptureFormState, CaptureSeed>(CaptureController.new);

/// 录入控制器：手动表单 + AI 双解析流的状态机与提交编排。
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
    // 编辑恒走 W2 money 手动表单（金额行修正链，§3.4 金额不可变）。
    final editing = seed.editEntryId != null;
    var side = editing ? CaptureSide.money : CaptureSide.both;
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

    // 最近记录 chips（§2.4 复记 ≤5s）：装载失败不阻塞抽屉（空列表退化）。
    List<CaptureRecentEntry> recentEntries = const [];
    try {
      recentEntries = await gateway.loadRecentEntries(limit: kRecentChipLimit);
    } catch (_) {
      recentEntries = const [];
    }

    return CaptureFormState(
      side: side,
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
      aiStage: CaptureAiStage.input,
      recentEntries: recentEntries,
    );
  }

  void _apply(CaptureFormState next) => state = AsyncData(next);

  // ── W2 手动 money 表单（§3.3 写通道/§3.4）──────────────────────

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

  /// 金额文本直写（确认卡「金额点改」与降级表单的 TextField，§3.3）：
  /// 合法性延迟到提交判定（[CaptureFormState.amountMinor] 为 null 即禁用）。
  void setAmountText(String text) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(amountText: text, errorText: null));
  }

  /// 降级手填表单的热量输入（kcal 整数文本）：合法性在
  /// [CaptureFormState.manualKcalValue]（空=未填；非整数/超 [0,5000] 视为
  /// 非法 → 禁用提交，§7.1 校验器口径）。
  void setManualKcalText(String text) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(manualKcalText: text, errorText: null));
  }

  /// 单边开关（§3.3「仅记钱/仅记热量/钱+热量」）。
  ///
  /// 切换即重置 AI 流状态回到输入区（原输入文本保留，§7.4「原输入保留」）；
  /// 手动 money 表单的字段（金额/标题等）互不干扰。
  void setSide(CaptureSide side) {
    final current = state.value;
    if (current == null || current.side == side) return;
    _apply(current.copyWith(
      side: side,
      aiStage: CaptureAiStage.input,
      parseResult: null,
      parseFromCache: false,
      aiParseId: null,
      aiInitials: null,
      confirmKcal: null,
      portionBaseKcal: null,
      portionMultiplier: 1.0,
      manualKcalText: '',
      fallbackHint: null,
      submitting: false,
      errorText: null,
      pendingSource: dom.EntrySource.text,
      pendingMoneyDirection: dom.LineDirection.outcome,
    ));
  }

  /// 收支方向（§5.2② direction：expense=out / income=in；W2 手动表单专用）。
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

  /// W2 提交：新建=落一笔 money 记录；编辑=新增 correction 行 supersede 旧行
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

  // ── W3-4 AI 双解析流（§3.3、§7.1、§2.3 步骤 2-4）────────────────

  /// 文本输入区原文变更（解析失败降级后原文保留在 [CaptureFormState.inputText]）。
  void setInputText(String text) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(inputText: text, errorText: null));
  }

  /// 「解析」：input_hash 缓存（§3.3/§5.6⑭）→ 注入的解析器（§7.1 adapter）
  /// → 校验器（§7.1）→ 确认卡；任何结构化失败/超时 → 自动降级手填表单并
  /// 保留原文（§7.4/§2.4-3）。
  Future<void> startParse() async {
    final current = state.value;
    if (current == null || current.aiStage == CaptureAiStage.parsing) return;
    final rawText = current.inputText.trim();
    if (rawText.isEmpty) {
      _apply(current.copyWith(errorText: '先输入一句话描述，再点解析'));
      return;
    }
    final gateway = _gateway;
    // 骨架先于任何 await 出现（§9.4「AI 等待骨架出现 ≤100ms」）。
    _apply(current.copyWith(
      aiStage: CaptureAiStage.parsing,
      submitting: false,
      errorText: null,
      fallbackHint: null,
    ));
    final normalized = CaptureInputNormalizer.normalize(rawText);
    final hash = CaptureInputNormalizer.inputHash(normalized);
    try {
      // ① input_hash 缓存：7 天内相同输入直接复用（§3.3、§5.6⑭）。
      final cached = await gateway.findCachedParse(
        inputHash: hash,
        inputKind: CaptureInputNormalizer.kindText,
      );
      if (cached != null) {
        await _enterConfirm(
          result: cached.result,
          aiParseId: cached.parseId,
          fromCache: true,
        );
        return;
      }
      // ② 注入解析器（测试注入 Fake，生产桥接 core_ai adapter，§10.4）；
      //    文本 5s 超时（§7.4）。
      final parser = ref.read(captureParserProvider);
      final result = await parser
          .parse(CaptureParseRequest(
            rawText: rawText,
            normalizedText: normalized,
            inputHash: hash,
            inputKind: CaptureInputNormalizer.kindText,
          ))
          .timeout(kCaptureParseTimeout);
      // ③ 校验器（§7.1「金额>0、kcal∈[0,5000]、必需字段齐」）：不过 → 结构化
      //    失败 → 降级（不落 ai_parses，坏输出不留痕）。
      final issue = result.checkUsable();
      if (issue != null) {
        throw CaptureStructuredFailure(
          code: CaptureFailureCode.schema,
          message: issue,
        );
      }
      // ④ ai_parses 留痕（§5.6⑭）→ 确认卡。
      final parseId = await gateway.saveAiParse(
        result: result,
        inputHash: hash,
        inputKind: CaptureInputNormalizer.kindText,
      );
      await _enterConfirm(result: result, aiParseId: parseId, fromCache: false);
    } on CaptureStructuredFailure catch (failure) {
      _enterManualFallback(
        'AI 解析失败：${failure.message}。已转手动填写，原文已保留（§7.4）',
      );
    } on TimeoutException {
      _enterManualFallback('AI 解析超时（5s）。已转手动填写，原文已保留（§7.4）');
    } catch (_) {
      _enterManualFallback('AI 解析失败。已转手动填写，原文已保留（§7.4）');
    }
  }

  /// 解析结果 → 确认卡预填（§3.3「AI 初值预填：标题/热量/金额/分类/置信度」）。
  ///
  /// 单边开关过滤（§3.3）：仅记热量模式丢弃 money 行（确认卡只产 calorie 行）；
  /// category_hint 经网关命中内置分类（§7.3），AI 初值快照入 state 供差异
  /// 审计（§5.6⑮）。
  Future<void> _enterConfirm({
    required CaptureParseResult result,
    required String aiParseId,
    required bool fromCache,
  }) async {
    final current = state.value;
    if (current == null) return;
    CaptureParsedLine? kcalLine;
    CaptureParsedLine? moneyLine;
    for (final line in result.lines) {
      if (line.isCalorie) {
        kcalLine ??= line;
      } else if (line.isMoney) {
        moneyLine ??= line;
      }
    }
    if (current.side == CaptureSide.calorie) moneyLine = null;
    final gateway = _gateway;
    String? categoryId;
    final hint = moneyLine?.categoryHint ?? kcalLine?.categoryHint;
    if (hint != null) {
      // AI money 行方向恒支出（收入走 W2 手动表单），按 expense 匹配（§5.4⑤）。
      categoryId = await gateway.matchCategoryByHint(hint, expense: true);
    }
    final kcal = kcalLine?.amountKcal;
    final amountMinor = moneyLine?.amountMinor;
    final ledgerId = current.ledgerId ??
        (current.ledgers.isEmpty ? null : current.ledgers.first.id);
    _apply(current.copyWith(
      aiStage: CaptureAiStage.confirm,
      parseResult: result,
      parseFromCache: fromCache,
      aiParseId: aiParseId,
      aiInitials: CaptureAiInitials(
        title: result.title,
        kcal: kcal,
        kcalConfidence: kcalLine?.confidence,
        moneyMinor: amountMinor,
        moneyConfidence: moneyLine?.confidence,
        categoryId: categoryId,
      ),
      title: result.title,
      note: result.parseNotes ?? current.note,
      confirmKcal: kcal,
      portionBaseKcal: kcal,
      portionMultiplier: 1.0,
      amountText:
          amountMinor == null ? '' : CaptureMoney.fromMinorUnits(amountMinor),
      categoryId: categoryId,
      ledgerId: ledgerId,
      manualKcalText: '',
      fallbackHint: null,
      errorText: null,
      submitting: false,
      pendingSource: dom.EntrySource.text,
      pendingMoneyDirection: dom.LineDirection.outcome,
    ));
  }

  /// 最近 chip 复记（§2.4-1「一键带入：日期刷新到今天、份量金额可微调」）：
  /// 整卡预填（标题/热量/金额/分类/账本），无 AI 初值 → 不产差异审计行；
  /// source=chip（§5.2①）。
  void applyRecentChip(CaptureRecentEntry chip) {
    final current = state.value;
    if (current == null) return;
    final includeMoney = current.side != CaptureSide.calorie;
    final kcal = current.side == CaptureSide.money ? null : chip.kcal;
    _apply(current.copyWith(
      aiStage: CaptureAiStage.confirm,
      parseResult: null,
      parseFromCache: false,
      aiParseId: null,
      aiInitials: null,
      title: chip.title,
      note: '',
      confirmKcal: kcal,
      portionBaseKcal: kcal,
      portionMultiplier: 1.0,
      amountText: includeMoney && chip.moneyMinor != null
          ? CaptureMoney.fromMinorUnits(chip.moneyMinor!)
          : '',
      categoryId: chip.categoryId,
      ledgerId: chip.ledgerId ?? current.ledgerId,
      // 日期刷新到今天（§2.4-1）。
      date: dom.formatCalendarDay(DateTime.now()),
      manualKcalText: '',
      fallbackHint: null,
      errorText: null,
      pendingSource: dom.EntrySource.chip,
      pendingMoneyDirection: chip.moneyDirection,
    ));
  }

  /// 份量滑杆联动热量重算（§3.3「份量滑杆 1.0→1.5 热量环实时重算」）：
  /// 基准 = [CaptureFormState.portionBaseKcal]（AI 初值/chip 原值），确认值
  /// = round(基准 × 倍率)。
  void setPortionMultiplier(double multiplier) {
    final current = state.value;
    if (current == null) return;
    final base = current.portionBaseKcal;
    if (base == null) return;
    final clamped = multiplier.clamp(0.5, 2.0).toDouble();
    _apply(current.copyWith(
      portionMultiplier: clamped,
      confirmKcal: (base * clamped).round(),
    ));
  }

  /// 回到输入区（确认卡「重新解析」/降级表单「重试解析」）：原文保留
  /// （§7.4），解析中间态清空。
  void backToInput() {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(
      aiStage: CaptureAiStage.input,
      parseResult: null,
      parseFromCache: false,
      aiParseId: null,
      aiInitials: null,
      confirmKcal: null,
      portionBaseKcal: null,
      portionMultiplier: 1.0,
      manualKcalText: '',
      fallbackHint: null,
      submitting: false,
      errorText: null,
      pendingSource: dom.EntrySource.text,
      pendingMoneyDirection: dom.LineDirection.outcome,
    ));
  }

  /// 解析失败降级（§7.4「原输入保留 → 自动降级手填表单」）：标题预填原文
  /// （绝不丢用户已输入文本，§2.4-3），无 AI 初值/溯源。
  void _enterManualFallback(String reason) {
    final current = state.value;
    if (current == null) return;
    _apply(current.copyWith(
      aiStage: CaptureAiStage.manualFallback,
      fallbackHint: reason,
      title: current.title.isEmpty ? current.inputText : current.title,
      manualKcalText: '',
      submitting: false,
      errorText: null,
      parseResult: null,
      parseFromCache: false,
      aiParseId: null,
      aiInitials: null,
      confirmKcal: null,
      portionBaseKcal: null,
      portionMultiplier: 1.0,
      pendingSource: dom.EntrySource.manual,
      pendingMoneyDirection: dom.LineDirection.outcome,
    ));
  }

  /// AI 流提交（确认卡「确认落库」/降级表单「保存」）：经
  /// [CaptureGateway.submitAiCapture] 同事务落库；单边开关过滤行集合
  /// （§3.3），差异审计由网关按 aiInitials 落（§5.6⑮ source=ai_corrected）。
  /// 成功返回 entryId；失败写 errorText 返回 null。
  Future<String?> submitPendingCapture() async {
    final current = state.value;
    if (current == null) return null;
    final isFallback = current.aiStage == CaptureAiStage.manualFallback;
    if (isFallback) {
      if (!current.canSubmitFallback) return null;
    } else if (current.aiStage == CaptureAiStage.confirm) {
      if (!current.canConfirm) return null;
    } else {
      return null; // input/parsing 阶段无提交语义
    }
    final gateway = _gateway;
    _apply(current.copyWith(submitting: true, errorText: null));
    try {
      final int? kcal;
      if (isFallback) {
        kcal = current.manualKcalValue;
      } else {
        kcal = current.showCalorieInConfirm ? current.confirmKcal : null;
      }
      final amountMinor = current.showMoneyInConfirm ? current.amountMinor : null;
      final hasKcal = (kcal ?? 0) > 0;
      final hasMoney = (amountMinor ?? 0) > 0;
      final normalized = _normalize(current);
      final result = current.parseResult;
      final multiplier = current.portionMultiplier;
      // 确认卡菜品明细随份量倍率联动缩放（§3.3 滑杆重算基准 portion_g）。
      final items = <CaptureConfirmedItem>[];
      if (!isFallback && hasKcal) {
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
      final initials = isFallback ? null : current.aiInitials;
      final entryId = await gateway.submitAiCapture(CaptureAiSubmitRequest(
        date: current.date,
        tzOffsetMin: current.tzOffsetMin,
        title: normalized.title,
        note: normalized.note,
        source: current.pendingSource,
        aiParseId: isFallback ? null : current.aiParseId,
        kcal: hasKcal ? kcal : null,
        kcalConfidence: initials?.kcalConfidence,
        moneyConfidence: initials?.moneyConfidence,
        items: items,
        portionMultiplier: items.isEmpty ? null : multiplier,
        amountMinor: hasMoney ? amountMinor : null,
        moneyDirection: current.pendingMoneyDirection,
        ledgerId: hasMoney ? current.ledgerId : null,
        categoryId: current.categoryId,
        currency: current.selectedCurrency,
        aiInitials: initials,
      ));
      _apply(current.copyWith(submitting: false));
      return entryId;
    } catch (error) {
      _apply(current.copyWith(submitting: false, errorText: '提交失败，请重试'));
      return null;
    }
  }
}
