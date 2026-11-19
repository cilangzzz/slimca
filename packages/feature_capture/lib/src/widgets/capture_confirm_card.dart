/// AI 确认卡（§3.3「先拍后改确认卡」、§2.3 步骤 3-4、§9.3#4）。
///
/// 卡面容器复用 ui_kit [SlimcaConfirmCard]（§2.3 步骤 3「抽屉原地转为确认卡」：
/// 语义 token 卡面 + 插槽级联入场 §9.3#1；「单确认卡聚合多行状态」的多行
/// 状态机归属本包，§12.2#8）。插槽组装：
/// - AI 初值预填（标题/热量/金额/分类/置信度，§3.3）；
/// - 双数字 SlimcaCountUp / SlimcaMoneyCountUp（§9.3#4 count-up 800ms
///   easeOutExpo）；热量环 sweep（SlimcaCalorieRing sweepEntrance，§9.3#4，
///   份量滑杆联动重算时从当前 sweep 续播，§2.3 步骤 4）；
/// - SlimcaConfidenceDot 三色点（§2.3 步骤 3：≥0.8 绿 / 0.5-0.8 黄 / <0.5 红），
///   低置信度强制高亮「份量可能不准」（§3.3）；
/// - 份量滑杆（0.5-2.0x，热量=基准×倍率实时重算，§3.3）、金额点改、
///   分类九宫格快选（复用 CaptureCategoryPicker）、账本/日期可调；
/// - 页脚「确认落库」（经 [CaptureController.submitPendingCapture]）与
///   「重新解析」（§3.3「确认后金额不可变」）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_controller.dart';
import '../capture_models.dart';
import 'capture_category_picker.dart';
import 'capture_date_row.dart';
import 'capture_error_text.dart';
import 'capture_ledger_picker.dart';
import 'capture_text_field.dart';

/// 确认卡测试锚点。
const Key captureConfirmCardKey = ValueKey('capture_confirm_card');

/// 确认落库按钮测试锚点。
const Key captureConfirmSubmitKey = ValueKey('capture_confirm_submit');

/// 重新解析按钮测试锚点。
const Key captureReparseButtonKey = ValueKey('capture_reparse_button');

/// 金额点改输入框测试锚点。
const Key captureConfirmAmountFieldKey = ValueKey('capture_confirm_amount_field');

/// 份量滑杆测试锚点。
const Key capturePortionSliderKey = ValueKey('capture_portion_slider');

/// 低置信度高亮横幅测试锚点（§3.3「低置信度强制高亮『份量可能不准』」）。
const Key captureLowConfidenceBannerKey = ValueKey('capture_low_confidence_banner');

/// 确认卡环 sweep 的预算参考刻度（kcal）：§9.3#4 环 sweep 以固定刻度呈现
/// 解析热量占比；真实每日热量预算随 W5-6「每日目标」接入后替换。
const int kConfirmRingBudgetKcal = 2000;

/// AI 确认卡。
class CaptureConfirmCard extends StatelessWidget {
  const CaptureConfirmCard({
    super.key,
    required this.form,
    required this.controller,
    required this.onConfirm,
    this.showActions = true,
  });

  final CaptureFormState form;
  final CaptureController controller;
  final Future<void> Function() onConfirm;

  /// 是否内嵌动作区（重新解析 + 确认落库，§2.3 步骤 5）。缺省 true（卡尾
  /// 页脚）。统一抽屉高度下确认卡经 [CaptureConfirmStage] 以「卡面滚动 +
  /// 动作页脚钉底」组装——传 false 仅渲染卡面，动作区钉底恒可见。
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final kcal = form.confirmKcal;
    final kcalConfidence = form.aiInitials?.kcalConfidence;
    final moneyMinor = form.amountMinor ?? 0;
    final moneyConfidence = form.aiInitials?.moneyConfidence;
    return SlimcaConfirmCard(
      key: captureConfirmCardKey,
      header: _badge(context),
      footer: showActions ? CaptureConfirmActions(
        form: form,
        controller: controller,
        onConfirm: onConfirm,
      ) : null,
      slots: [
        _slot(
          CaptureTextField(
            key: const ValueKey('capture_confirm_title'),
            initial: form.title,
            hint: '标题',
            onChanged: controller.setTitle,
          ),
        ),
        if (form.showCalorieInConfirm && kcal != null && kcal > 0)
          _slot(_calorieSection(context, kcal: kcal, confidence: kcalConfidence)),
        if (form.showMoneyInConfirm && moneyMinor > 0)
          _slot(_moneySection(moneyMinor: moneyMinor, confidence: moneyConfidence)),
        _slot(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FieldLabel('分类'),
              CaptureCategoryPicker(
                options: form.categories,
                selectedId: form.categoryId,
                onSelected: controller.selectCategory,
              ),
            ],
          ),
        ),
        if (form.showMoneyInConfirm)
          _slot(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FieldLabel('账本'),
                CaptureLedgerPicker(
                  options: form.ledgers,
                  selectedId: form.ledgerId,
                  onSelected: controller.selectLedger,
                ),
              ],
            ),
          ),
        _slot(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CaptureDateRow(date: form.date, onPicked: controller.setDate),
              if (form.parseResult?.parseNotes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '解析备注：${form.parseResult!.parseNotes}',
                    key: const ValueKey('capture_parse_notes'),
                    style: TextStyle(
                        fontSize: 12, color: context.slimca.onSurfaceMuted),
                  ),
                ),
              if (form.errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: CaptureErrorText(
                    text: form.errorText!,
                    testKey: const ValueKey('capture_error_text'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 插槽统一底距（级联上浮的几何常量随卡内尺度取 12，§9.3#1）。
  Widget _slot(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 12), child: child);

  /// 来源徽标：AI 解析 / 缓存复用（input_hash，§3.3）/ 最近复记（§2.4）/
  /// 拍照识别与端侧粗估（§11.2 W11-12、§3.7——端侧路径无 ai_parse_id，
  /// 云端识别有，借此区分文案）。
  Widget _badge(BuildContext context) {
    final tokens = context.slimca;
    final label = form.aiInitials == null
        ? (form.pendingSource.wire == 'chip' ? '最近记录复记（§2.4）' : '手动填写')
        : form.parseFromCache
            ? 'AI 解析 · 缓存复用（§3.3）'
            : form.pendingSource.wire == 'photo'
                ? (form.aiParseId == null
                    ? '拍照端侧粗估初值（§3.7）'
                    : '拍照识别初值（§11.2）')
                : 'AI 解析初值（§7.1）';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            key: const ValueKey('capture_confirm_badge'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: tokens.kcalIn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: tokens.kcalIn),
            ),
          ),
          const Spacer(),
          if (form.portionMultiplier != 1.0)
            Text(
              '份量 x${form.portionMultiplier.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
            ),
        ],
      ),
    );
  }

  /// 热量区：环 sweep + count-up + 置信度三色点 + 低置信度高亮 + 份量滑杆。
  Widget _calorieSection(
    BuildContext context, {
    required int kcal,
    required double? confidence,
  }) {
    final tokens = context.slimca;
    final low = confidence != null && confidence < 0.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel('热量'),
        if (low)
          Container(
            key: captureLowConfidenceBannerKey,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: tokens.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    size: 16, color: tokens.danger),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '份量可能不准，请用滑杆校正（§3.3 低置信度强制高亮）',
                    style: TextStyle(fontSize: 12, color: tokens.danger),
                  ),
                ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SlimcaCalorieRing(
              kcalIn: kcal,
              kcalOut: 0,
              budget: kConfirmRingBudgetKcal,
              size: 108,
              strokeWidth: 10,
              center: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // §9.3#4 count-up 800ms easeOutExpo（滑杆重算时从当前值续播）
                  SlimcaCountUp(
                    value: kcal,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: tokens.kcalIn,
                    ),
                  ),
                  Text(
                    'kcal',
                    style: TextStyle(fontSize: 11, color: tokens.onSurfaceMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (confidence != null)
                    _ConfidenceLabel(confidence: confidence),
                  const SizedBox(height: 8),
                  Slider(
                    key: capturePortionSliderKey,
                    value: form.portionMultiplier,
                    min: 0.5,
                    max: 2.0,
                    divisions: 12,
                    label: 'x${form.portionMultiplier.toStringAsFixed(2)}',
                    onChanged: controller.setPortionMultiplier,
                  ),
                  Text(
                    '份量滑杆 0.5-2.0x，热量实时重算（§3.3）',
                    style: TextStyle(fontSize: 11, color: tokens.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 金额区：金额 count-up（SlimcaMoneyCountUp，§9.3#4）+ 置信度三色点 +
  /// 点改输入（§3.3「金额点改」）。
  Widget _moneySection({
    required int moneyMinor,
    required double? confidence,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _FieldLabel('金额'),
            const Spacer(),
            if (confidence != null) _ConfidenceLabel(confidence: confidence),
          ],
        ),
        // §9.3#4 双数字 count-up 之金额：分→元格式化 + moneyOut 语义色（§8.2）。
        SlimcaMoneyCountUp(
          amountMinor: moneyMinor,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        CaptureTextField(
          key: captureConfirmAmountFieldKey,
          initial: form.amountText,
          hint: '点改金额（元，最多两位小数）',
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: controller.setAmountText,
        ),
      ],
    );
  }

  /// 页脚：重新解析 + 确认落库——实现移至公开组件 [CaptureConfirmActions]
  /// （统一抽屉高度下动作区可钉底复用，§2.3 步骤 5）。
}

/// 确认卡动作区：重新解析 + 确认落库（§2.3 步骤 5 按钮区；§3.3 确认后
/// 金额不可变）。
///
/// 两种组装：`CaptureConfirmCard` 内嵌卡尾页脚（缺省），或统一抽屉高度下
/// 经 [CaptureConfirmStage] 钉底（CTA 恒可见）。
class CaptureConfirmActions extends StatelessWidget {
  const CaptureConfirmActions({
    super.key,
    required this.form,
    required this.controller,
    required this.onConfirm,
  });

  final CaptureFormState form;
  final CaptureController controller;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Row(
      children: [
        TextButton(
          key: captureReparseButtonKey,
          onPressed: form.submitting ? null : controller.backToInput,
          child: Text(
            '重新解析',
            style: TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            key: captureConfirmSubmitKey,
            onPressed: form.canConfirm ? onConfirm : null,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.primary,
              foregroundColor: tokens.onPrimary,
              disabledBackgroundColor: tokens.surfaceMuted,
              disabledForegroundColor: tokens.onSurfaceMuted,
              minimumSize: Size.fromHeight(context.sizes.minTouchTarget),
              shape: const StadiumBorder(), // §7.1 按钮胶囊（M3 full）
            ),
            child: form.submitting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.onPrimary,
                    ),
                  )
                : const Text(
                    '确认落库',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }
}

/// 置信度三色点 + 百分比（§2.3 步骤 3、§7.3 三档口径）。
class _ConfidenceLabel extends StatelessWidget {
  const _ConfidenceLabel({required this.confidence});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SlimcaConfidenceDot(confidence: confidence),
        const SizedBox(width: 6),
        Text(
          '置信度 ${(confidence * 100).round()}%',
          style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
        ),
      ],
    );
  }
}

/// 字段分组标签（与录入页同形）。
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
