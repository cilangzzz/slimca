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
///
/// W11-12 主线「拍照通道」（§11.2、§3.3 拍照通道、§3.7 数据主权）：
/// [startPhotoCapture] 入口（拍照/相册，[CaptureImageSource] 壳注入）→
/// 端侧压缩（[CaptureImageCompressor]，长边 1280 JPEG q80）→ raw_input
/// 上云闸门分流（§3.7：关=端侧粗估 + 人工确认，字节不出端；开=云端识别
/// 12s 超时，百度→Vision 双供应商）→ 确认卡复用（份量滑杆联动）→ 确认
/// 落库后「解析后即焚」（attachments 登记 burned + 临时文件删除，
/// §5.6㉑）；失败自动降级手填且已拍数据确认前不焚不丢（§11.2 任务 4）；
/// 漏斗 photo_capture_open/photo_parse_result/photo_confirm + ≤15s 护栏
/// （[CapturePhotoFunnel]/[photoPathWithinGuard]）。
library;

import 'dart:async';
import 'dart:io';

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_attachment_store.dart';
import 'capture_gateway.dart';
import 'capture_models.dart';
import 'capture_money.dart';
import 'capture_parser.dart';
import 'capture_photo_compressor.dart';
import 'capture_photo_estimator.dart';
import 'capture_photo_models.dart';
import 'capture_photo_parser.dart';
import 'capture_photo_source.dart';
import 'capture_photo_telemetry.dart';

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

  /// 拍照漏斗计时起点（photo_capture_open 时刻；photo_confirm 收口算全程
  /// 耗时并对 §2.3「拍照 ≤15s」护栏，§11.2 任务 5）。
  int? _photoOpenedAtMs;

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
    );
  }

  void _apply(CaptureFormState next) => state = AsyncData(next);

  // ── W2 手动 money 表单（§3.3 写通道/§3.4）──────────────────────

  /// 金额文本直写（确认卡「金额点改」、money 表单滚动金额字段与降级表单
  /// 的 TextField，§3.3）：合法性延迟到提交判定
  /// （[CaptureFormState.amountMinor] 为 null 即禁用）。
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
  /// 手动 money 表单的字段（金额/标题等）互不干扰。切仅记钱=放弃拍照通道
  /// （money 表单无拍照语义）：待焚原件文件即刻删除（行尚未登记，无焚语义）；
  /// 切热量/双向保留原件（拍照通道产出热量行，§3.3）。
  void setSide(CaptureSide side) {
    final current = state.value;
    if (current == null || current.side == side) return;
    if (side == CaptureSide.money) {
      unawaited(_deleteTempFile(current.pendingPhoto?.localPath));
    }
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
      pendingPhoto: side == CaptureSide.money ? null : current.pendingPhoto,
      photoProcessingLabel: null,
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
      // 拍照通道让位（用户明确改走文本解析）：待焚原件即刻弃置——state 清空
      // + 临时文件尽力删除（行尚未登记，无焚语义；§11.2 任务 4 对称面）。
      pendingPhoto: null,
      photoProcessingLabel: null,
    ));
    unawaited(_deleteTempFile(current.pendingPhoto?.localPath));
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
  /// 审计（§5.6⑮）。拍照通道（§11.2）传 source=photo 与待焚原件
  /// [pendingPhoto]；端侧粗估路径无云端解析，aiParseId 为 null
  /// （ai_parses 不落行，§5.6⑭）。
  Future<void> _enterConfirm({
    required CaptureParseResult result,
    required String? aiParseId,
    required bool fromCache,
    dom.EntrySource source = dom.EntrySource.text,
    CapturePendingPhoto? pendingPhoto,
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
      pendingSource: source,
      pendingMoneyDirection: dom.LineDirection.outcome,
      // 拍照通道：待焚原件随确认卡进入提交链（§11.2 即焚推迟到落库成功）；
      // 文本路径传 null=无拍照痕迹。呼吸态分段文案同时清空。
      pendingPhoto: pendingPhoto,
      photoProcessingLabel: null,
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
  /// （§7.4），解析中间态清空。拍照通道（§11.2 任务 4）：待焚原件**保留**
  /// （重拍/重选在 [startPhotoCapture] 内替换，文本解析在 [startParse] 内
  /// 弃置——已拍数据在用户明确放弃前不焚不丢）。
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
      photoProcessingLabel: null,
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

  // ── W11-12 拍照通道（§11.2、§3.3 拍照通道、§3.7 数据主权）──────────

  /// 拍照通道主流程（§11.2 W11-12 任务 2-5）：
  ///
  /// ① 取图：拍照/相册经注入的 [CaptureImageSource]（image_picker 薄封装
  ///    由壳装配，§10.4；null=用户取消 → 原地回输入区，不动任何状态）；
  /// ② 端侧压缩：[CaptureImageCompressor]（长边 1280、JPEG q80，§3.3）；
  /// ③ input_hash 缓存：键=sha256(压缩字节)、input_kind=photo（§5.6⑭）——
  ///    只查本地 ai_parses，raw_input 关闭口径下仍可用（字节不出端，§3.7）；
  /// ④ raw_input 上云闸门（§3.7）：关=端侧粗估（不联网）→ 估计成功进确认卡
  ///    / 无法估计转人工确认——图片字节全程不出端；开=云端识别（百度→
  ///    Vision 双供应商，§7.4）12s 超时；
  /// ⑤ 确认卡复用（W3-4）→ 确认落库（[submitPendingCapture]）→ 即焚。
  ///
  /// 全程呼吸态分段文案（压缩中… → 识别中…/端侧粗估中…，§9.4）；任何失败
  /// 自动降级手填且待焚原件保留（§11.2 任务 4「绝不丢已拍数据」：原文图片
  /// 在用户确认落库前绝不即焚）。
  Future<void> startPhotoCapture({required bool fromCamera}) async {
    final current = state.value;
    // 守卫：仅 AI 流输入阶段响应（money 手动表单无拍照通道，§3.3；呼吸/
    // 确认阶段不重复入流）。
    if (current == null ||
        current.side == CaptureSide.money ||
        current.aiStage != CaptureAiStage.input) {
      return;
    }
    final gateway = _gateway;
    final rawInputOpen = ref.read(captureRawInputCloudEnabledProvider)();
    final openedAtMs = DateTime.now().millisecondsSinceEpoch;
    _photoOpenedAtMs = openedAtMs;
    _photoFunnel(CapturePhotoFunnel.photoCaptureOpen, {
      'from_camera': fromCamera,
    });
    // 呼吸态先于任何 await（§9.4：切阶段为同步 setState，取图等待发生在
    // 呼吸态之后）。拍照处理中复用 parsing 阶段 + photoProcessingLabel 分段
    // 文案（不新增 CaptureAiStage 枚举值——Dart 3 枚举穷举 switch 是编译期
    // 硬约束，加值会破坏既有宿主面板的穷举 switch，§11.2 兼容注记）。
    _apply(current.copyWith(
      aiStage: CaptureAiStage.parsing,
      photoProcessingLabel: '压缩中…',
      submitting: false,
      errorText: null,
      fallbackHint: null,
    ));
    try {
      // ① 取图（§11.2 任务 1；null=用户取消 → 回输入区，保留既有待焚原件）。
      final source = ref.read(captureImageSourceProvider);
      final photo =
          fromCamera ? await source.capturePhoto() : await source.pickGallery();
      if (photo == null) {
        final latest = state.value;
        if (latest != null) {
          _apply(latest.copyWith(
            aiStage: CaptureAiStage.input,
            photoProcessingLabel: null,
          ));
        }
        return;
      }
      // ② 端侧压缩（§3.3 长边 1280、JPEG q80 由注入实现承担；content_hash
      //    =sha256(压缩字节) 一址两用，§5.6㉑/§5.6⑭）。
      final compressor = ref.read(captureImageCompressorProvider);
      final compressed = await compressor.compress(photo);
      // 旧待焚原件弃置（重拍/重选场景：旧临时文件尽力删除；行尚未登记）。
      final previousPath = current.pendingPhoto?.localPath;
      if (previousPath != null && previousPath != photo.localPath) {
        await _deleteTempFile(previousPath);
      }
      final pending = CapturePendingPhoto(
        contentHash: compressed.contentHash,
        mime: compressed.mime,
        sizeBytes: compressed.sizeBytes,
        localPath: photo.localPath,
      );
      // 待焚原件先进 state（此后降级/确认路径统一携带，§11.2 任务 4），
      // 呼吸态进入识别/粗估分段。
      final afterCompress = state.value;
      if (afterCompress != null) {
        _apply(afterCompress.copyWith(
          photoProcessingLabel: rawInputOpen ? '识别中…' : '端侧粗估中…',
          pendingPhoto: pending,
        ));
      }
      // ③ input_hash 缓存命中直接复用（§5.6⑭；本地查询，关闭口径可用 §3.7）。
      final cached = await gateway.findCachedParse(
        inputHash: compressed.contentHash,
        inputKind: CaptureInputNormalizer.kindPhoto,
      );
      if (cached != null) {
        _photoFunnel(CapturePhotoFunnel.photoParseResult, {
          'outcome': 'cache',
          'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
        });
        await _enterConfirm(
          result: cached.result,
          aiParseId: cached.parseId,
          fromCache: true,
          source: dom.EntrySource.photo,
          pendingPhoto: pending,
        );
        return;
      }
      if (!rawInputOpen) {
        // ④a raw_input 关闭（§3.7 默认）：字节不出端 → 端侧粗估 + 人工确认。
        final estimator = ref.read(captureOnDeviceEstimatorProvider);
        final estimate = await estimator.estimate(CapturePhotoParseRequest(
          bytes: compressed.bytes,
          mime: compressed.mime,
          inputHash: compressed.contentHash,
        ));
        final usable = estimate?.checkUsable();
        if (estimate == null || usable != null) {
          // 端侧无法估计/未装配端侧模型（缺省最严兜底，§3.7）→ 人工确认。
          _photoFunnel(CapturePhotoFunnel.photoParseResult, {
            'outcome': 'manual',
            'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
          });
          _enterPhotoFallback(
            '原文上云已关闭（§3.7）：图片不出端且无法端侧识别，请手动填写'
            '（已拍照片确认落库后即焚）',
          );
          return;
        }
        _photoFunnel(CapturePhotoFunnel.photoParseResult, {
          'outcome': 'on_device',
          'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
        });
        await _enterConfirm(
          result: estimate,
          // 端侧路径无云端解析：ai_parses 不落行、entries.ai_parse_id 为 null
          // （§5.6⑭ 留痕为云端口径，§3.7 关=仅落结构化结果）。
          aiParseId: null,
          fromCache: false,
          source: dom.EntrySource.photo,
          pendingPhoto: pending,
        );
        return;
      }
      // ④b raw_input 开启（§3.7）：允许本次识别请求携带压缩字节上云；
      //     百度先行 → Vision 兜底（组合语义由注入实现承担，§7.4），12s 超时
      //     （§7.4 照片口径，全程 ≤15s 护栏含压缩与确认）。
      final parser = ref.read(capturePhotoParserProvider);
      final result = await parser
          .parse(CapturePhotoParseRequest(
            bytes: compressed.bytes,
            mime: compressed.mime,
            inputHash: compressed.contentHash,
          ))
          .timeout(kCapturePhotoParseTimeout);
      // ⑤ 校验器（§7.1「金额>0、kcal∈[0,5000]、必需字段齐」）：不过 → 结构化
      //    失败 → 降级（不落 ai_parses，坏输出不留痕）。
      final issue = result.checkUsable();
      if (issue != null) {
        throw CaptureStructuredFailure(
          code: CaptureFailureCode.schema,
          message: issue,
        );
      }
      // ⑥ ai_parses 留痕（§5.6⑭ input_kind=photo）→ 确认卡。
      final parseId = await gateway.saveAiParse(
        result: result,
        inputHash: compressed.contentHash,
        inputKind: CaptureInputNormalizer.kindPhoto,
      );
      _photoFunnel(CapturePhotoFunnel.photoParseResult, {
        'outcome': 'success',
        'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
      });
      await _enterConfirm(
        result: result,
        aiParseId: parseId,
        fromCache: false,
        source: dom.EntrySource.photo,
        pendingPhoto: pending,
      );
    } on CaptureStructuredFailure catch (failure) {
      _photoFunnel(CapturePhotoFunnel.photoParseResult, {
        'outcome': 'fallback',
        'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
        'code': failure.code.name,
      });
      _enterPhotoFallback(
        '拍照识别失败：${failure.message}。已转手动填写，已拍照片确认落库后即焚'
        '（§7.4/§11.2）',
      );
    } on TimeoutException {
      _photoFunnel(CapturePhotoFunnel.photoParseResult, {
        'outcome': 'fallback',
        'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
        'code': CaptureFailureCode.timeout.name,
      });
      _enterPhotoFallback(
        '拍照识别超时（12s）。已转手动填写，已拍照片确认落库后即焚（§7.4）',
      );
    } catch (_) {
      _photoFunnel(CapturePhotoFunnel.photoParseResult, {
        'outcome': 'fallback',
        'latency_ms': DateTime.now().millisecondsSinceEpoch - openedAtMs,
      });
      _enterPhotoFallback(
        '拍照识别失败。已转手动填写，已拍照片确认落库后即焚（§11.2）',
      );
    }
  }

  /// 拍照失败/端侧无法估计的降级（§7.4 自动降级手填、§11.2 任务 4「绝不丢
  /// 已拍数据」）：待焚原件**保留**在 state（即焚推迟到确认落库成功）；
  /// source 记 photo——本笔来自拍照通道的语义在降级路径同样成立（§5.2①），
  /// 文本降级路径（[_enterManualFallback]）不受影响。
  void _enterPhotoFallback(String reason) {
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
      photoProcessingLabel: null,
      pendingSource: dom.EntrySource.photo,
      pendingMoneyDirection: dom.LineDirection.outcome,
    ));
  }

  /// 尽力而为删除本地临时图片文件（即焚的「文件半边」，§3.7/§11.2 任务 3；
  /// 「行半边」=attachments 登记 burned）。失败静默不重试（行状态为即焚
  /// 真值，壳层启动临时目录清扫兜底）；顺带清理单层临时目录（仅空目录
  /// 成功，非空抛错被吞）。
  Future<void> _deleteTempFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (parent.path != Directory.systemTemp.path) {
        await parent.delete();
      }
    } catch (_) {
      // 即焚文件删除失败不影响主流程（§6.1 原则 1 同款纪律）。
    }
  }

  // ── 拍照通道遥测（§11.2 任务 5；埋点永不阻塞主流程，§3.9）──────────

  /// 拍照漏斗事件（telemetry 未装配=缺省 null 时跳过；props 仅标量枚举/
  /// 耗时/错误**类型**码，内容字段禁入——实现方另有 TelemetryPrivacy 闸门，
  /// §3.9）。
  void _photoFunnel(String event, Map<String, Object?> props) {
    final telemetry = ref.read(capturePhotoTelemetryProvider);
    if (telemetry == null) return;
    try {
      telemetry.funnel(event, props: props);
    } catch (_) {
      // 遥测失败不影响主流程（§3.9）。
    }
  }

  /// 拍照性能指标（tags.path='photo' 区分路径，§2.3 护栏口径）。
  void _photoMetric(String name, num value, Map<String, Object?> tags) {
    final telemetry = ref.read(capturePhotoTelemetryProvider);
    if (telemetry == null) return;
    try {
      telemetry.metric(name, value: value, tags: tags);
    } catch (_) {
      // 遥测失败不影响主流程（§3.9）。
    }
  }

  /// 拍照漏斗终点：photo_confirm（全程耗时 + within_guard 护栏）+ 复用
  /// capture_open_to_confirm_ms metric（tags.path='photo'，§2.3「拍照
  /// ≤15s」）。
  void _photoConfirmTelemetry() {
    final openedAtMs = _photoOpenedAtMs;
    final totalMs = openedAtMs == null
        ? 0
        : DateTime.now().millisecondsSinceEpoch - openedAtMs;
    _photoFunnel(CapturePhotoFunnel.photoConfirm, {
      'total_ms': totalMs,
      'within_guard': photoPathWithinGuard(totalMs),
    });
    _photoMetric(
      dom.TelemetryMetricName.captureOpenToConfirmMs,
      totalMs,
      const {'path': 'photo'},
    );
    _photoOpenedAtMs = null;
  }

  /// AI 流提交（确认卡「确认落库」/降级表单「保存」）：经
  /// [CaptureGateway.submitAiCapture] 同事务落库；单边开关过滤行集合
  /// （§3.3），差异审计由网关按 aiInitials 落（§5.6⑮ source=ai_corrected）。
  /// 拍照通道（§11.2 任务 3）：落库成功后执行「解析后即焚」——attachments
  /// 登记即 burned（blob_ref 恒 NULL，原图不落服务端，§5.6㉑）+ 本地临时
  /// 文件删除 + 漏斗终点埋点；提交失败则原件保留待重试（§11.2 任务 4）。
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
      return null; // input/parsing（含拍照处理中）阶段无提交语义
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
      // 拍照通道即焚（§3.7/§11.2 任务 3）：确认落库成功 → 登记 attachments
      // 行（登记即 burned）→ 删除本地临时文件。行登记失败不回滚已落库记录
      // （行状态为即焚真值，壳层临时目录清扫兜底）；文件删除尽力而为
      // （§6.1 原则 1 同款纪律：只降级不打断）。
      final photo = current.pendingPhoto;
      if (photo != null) {
        try {
          await ref
              .read(captureAttachmentStoreProvider)
              .registerBurned(CaptureAttachmentDraft(
                entryId: entryId,
                contentHash: photo.contentHash,
                kind: 'photo',
                mime: photo.mime,
                sizeBytes: photo.sizeBytes,
                localPath: photo.localPath,
              ));
        } catch (_) {
          // 即焚行登记失败不阻塞提交结果（清扫兜底，§3.7）。
        }
        await _deleteTempFile(photo.localPath);
        // 拍照漏斗终点 + 全程护栏 metric（§11.2 任务 5、§2.3 ≤15s）。
        _photoConfirmTelemetry();
      }
      // 以最新 state 收尾（焚步骤可能已清 pendingPhoto；避免旧快照复活待焚
      // 原件）。
      final latest = state.value;
      _apply((latest ?? current).copyWith(
        submitting: false,
        pendingPhoto: null,
        photoProcessingLabel: null,
      ));
      return entryId;
    } catch (error) {
      // 提交失败：待焚原件保留（重试提交仍携带，§11.2 任务 4「绝不丢已拍
      // 数据」——即焚只发生在确认落库成功之后）。
      _apply(current.copyWith(submitting: false, errorText: '提交失败，请重试'));
      return null;
    }
  }
}
