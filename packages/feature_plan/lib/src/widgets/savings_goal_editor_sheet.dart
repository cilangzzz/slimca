/// 新建存钱目标抽屉（§3.6 存钱目标 P1、§11.2 W13 主线「存钱目标（留存
/// 钩子）」：名称/金额/365 天挑战/52 周挑战/自定义）。
///
/// 形态与口径：
/// - 365 天挑战（daily365）：每格基数（元）→ 目标金额=基数×Σ(1..365)
///   （默认 1 元/天递增挑战），rhythm 落 `{"kind":"daily365",...}`；
/// - 52 周挑战（week52）：每格基数（元）→ 目标金额=基数×Σ(1..52)
///   （默认 10 元/周递增挑战），rhythm 落 `{"kind":"week52",...}`；
/// - 自定义（custom）：目标金额 + 每日投币额（+ 可选截止日），rhythm 落
///   `{"kind":"custom","daily_amount_minor":...}`；
/// - 金额一律以分落库（§5.1 minor unit），输入框按元展示换算；
/// - 起始日缺省=设备本地今日（§5.5⑪ started_on，365/52 周存钱法「第 1 格」
///   锚点）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../plan_models.dart';
import 'plan_sheet_sizing.dart';
import 'plan_text_field.dart';

/// 名称输入测试锚点。
const Key savingsNameFieldKey = ValueKey('savings_name_field');

/// 存钱法选择 chip 测试锚点（`savings_method_$wire`）。
Key savingsMethodChipKey(String wire) => ValueKey('savings_method_$wire');

/// 每格基数输入测试锚点（365/52 周挑战）。
const Key savingsUnitFieldKey = ValueKey('savings_unit_field');

/// 目标金额输入测试锚点（自定义）。
const Key savingsTargetFieldKey = ValueKey('savings_target_field');

/// 每日投币额输入测试锚点（自定义）。
const Key savingsDailyFieldKey = ValueKey('savings_daily_field');

/// 截止日选择按钮测试锚点（自定义可选）。
const Key savingsDeadlinePickKey = ValueKey('savings_deadline_pick');

/// 保存按钮测试锚点。
const Key savingsGoalSubmitKey = ValueKey('savings_goal_submit');

/// 挑战档位（编辑器 UI 结构化；wire 值=§5.5⑪ method 枚举）。
enum _MethodKind { daily365, week52, custom }

String _methodWire(_MethodKind kind) => switch (kind) {
      _MethodKind.daily365 => cdb.kSavingsMethodDaily365,
      _MethodKind.week52 => cdb.kSavingsMethodWeek52,
      _MethodKind.custom => cdb.kSavingsMethodCustom,
    };

String _methodLabel(_MethodKind kind) => switch (kind) {
      _MethodKind.daily365 => '365 天挑战',
      _MethodKind.week52 => '52 周挑战',
      _MethodKind.custom => '自定义',
    };

/// 每格基数缺省值（元）：365 天=1 元/天递增、52 周=10 元/周递增（§3.6
/// 经典存钱法口径）。
double _defaultUnitYuan(_MethodKind kind) =>
    kind == _MethodKind.daily365 ? 1 : 10;

/// 新建存钱目标抽屉。
class SavingsGoalEditorSheet extends ConsumerStatefulWidget {
  const SavingsGoalEditorSheet({super.key});

  @override
  ConsumerState<SavingsGoalEditorSheet> createState() =>
      _SavingsGoalEditorSheetState();
}

class _SavingsGoalEditorSheetState
    extends ConsumerState<SavingsGoalEditorSheet> {
  String _nameText = '';
  String _unitText = '1';
  String _targetText = '';
  String _dailyText = '';
  _MethodKind _method = _MethodKind.daily365;
  String? _deadline;

  /// 元输入 → 分（非法/非正返回 null，§5.1 金额分口径）。
  int? _parseMinor(String text) {
    final v = double.tryParse(text.trim());
    if (v == null || v <= 0) return null;
    return (v * 100).round();
  }

  int? get _unitMinor =>
      _method == _MethodKind.custom ? null : _parseMinor(_unitText);

  int? get _targetMinor =>
      _method == _MethodKind.custom ? _parseMinor(_targetText) : null;

  int? get _dailyMinor =>
      _method == _MethodKind.custom ? _parseMinor(_dailyText) : null;

  bool get _canSubmit {
    if (_nameText.trim().isEmpty) return false;
    return switch (_method) {
      _MethodKind.daily365 || _MethodKind.week52 => _unitMinor != null,
      _MethodKind.custom =>
        _targetMinor != null && _dailyMinor != null,
    };
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final name = _nameText.trim();
    final gateway = ref.read(planGatewayProvider);
    final SavingsGoalDraft draft = switch (_method) {
      _MethodKind.daily365 => SavingsGoalDraft.daily365(
          name: name, unitMinor: _unitMinor!),
      _MethodKind.week52 =>
        SavingsGoalDraft.week52(name: name, unitMinor: _unitMinor!),
      _MethodKind.custom => SavingsGoalDraft.custom(
          name: name,
          targetMinor: _targetMinor!,
          dailyAmountMinor: _dailyMinor!,
          deadline: _deadline,
        ),
    };
    await gateway.createSavingsGoal(draft);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _deadline = dom.formatCalendarDay(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final unitMinor = _unitMinor;
    final challengeTarget = switch (_method) {
      _MethodKind.daily365 => unitMinor == null
          ? null
          : unitMinor * (kDaily365Slots * (kDaily365Slots + 1) ~/ 2),
      _MethodKind.week52 => unitMinor == null
          ? null
          : unitMinor * (kWeek52Slots * (kWeek52Slots + 1) ~/ 2),
      _MethodKind.custom => null,
    };
    // 稳定高度外框（planSheetHeight，与 capture 录入抽屉同口径）：内容区
    // 键盘内收、滚动承载长内容，主 CTA「创建目标」钉底（外框高度恒定）。
    return SizedBox(
      height: planSheetHeight(context),
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '新建存钱目标',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface),
                    ),
                    const SizedBox(height: 12),
                    PlanTextField(
                      key: savingsNameFieldKey,
                      initial: _nameText,
                      hint: '目标名（如 旅行基金）',
                      onChanged: (v) => setState(() => _nameText = v),
                    ),
                    const SizedBox(height: 12),
                    Text('存钱法',
                        style: TextStyle(
                            fontSize: 13, color: tokens.onSurfaceMuted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final kind in _MethodKind.values)
                          ChoiceChip(
                            key: savingsMethodChipKey(_methodWire(kind)),
                            label: Text(_methodLabel(kind)),
                            selected: _method == kind,
                            onSelected: (_) => setState(() {
                              _method = kind;
                              // 每格基数随档位回填经典缺省（用户已改值则保留）。
                              final defaultText =
                                  _defaultUnitYuan(kind).toStringAsFixed(0);
                              final isPrevDefault = _unitText == '1' ||
                                  _unitText == '10' ||
                                  _unitText.isEmpty;
                              if (kind != _MethodKind.custom && isPrevDefault) {
                                _unitText = defaultText;
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_method != _MethodKind.custom) ...[
                      Text(
                          '每格基数（元）：第 N ${_method == _MethodKind.daily365 ? '天' : '周'}存 N×基数',
                          style: TextStyle(
                              fontSize: 13, color: tokens.onSurfaceMuted)),
                      const SizedBox(height: 8),
                      PlanTextField(
                        key: savingsUnitFieldKey,
                        initial: _unitText,
                        hint: _method == _MethodKind.daily365 ? '如 1' : '如 10',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) => setState(() => _unitText = v),
                      ),
                      if (challengeTarget != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '目标 ≈ ${(challengeTarget / 100).toStringAsFixed(2)} 元'
                            '（${_method == _MethodKind.daily365 ? '365' : '52'} 格递增求和）',
                            style: TextStyle(
                                fontSize: 13, color: tokens.onSurfaceMuted),
                          ),
                        ),
                    ] else ...[
                      Text('目标金额（元）',
                          style: TextStyle(
                              fontSize: 13, color: tokens.onSurfaceMuted)),
                      const SizedBox(height: 8),
                      PlanTextField(
                        key: savingsTargetFieldKey,
                        initial: _targetText,
                        hint: '如 10000',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) => setState(() => _targetText = v),
                      ),
                      const SizedBox(height: 12),
                      Text('每日投币额（元）',
                          style: TextStyle(
                              fontSize: 13, color: tokens.onSurfaceMuted)),
                      const SizedBox(height: 8),
                      PlanTextField(
                        key: savingsDailyFieldKey,
                        initial: _dailyText,
                        hint: '如 20',
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (v) => setState(() => _dailyText = v),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            key: savingsDeadlinePickKey,
                            onPressed: _pickDeadline,
                            child: Text(_deadline ?? '截止日（可选）'),
                          ),
                          if (_deadline != null)
                            IconButton(
                              tooltip: '清除截止日',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _deadline = null),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 主 CTA 钉底（唯一填充按钮，通栏宽度）。
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: savingsGoalSubmitKey,
                  onPressed: _canSubmit ? _submit : null,
                  child: const Text('创建目标'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
