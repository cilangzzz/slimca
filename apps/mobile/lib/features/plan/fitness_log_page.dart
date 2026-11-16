/// 健身手动记录页（§3.5 健身记录与热量收支、§11.1 W5-6「健身手动记录进
/// 仪表盘与净热量」、§4.3 /plan/fitness）。
///
/// 表单字段（§3.5 手动记录 P0）：类型（力量/有氧/HIIT/其他）+ 时长（分钟）+
/// 身体档案体重（kg，settings，MET 估算依赖 §3.5 身体档案）+ 备注；消耗
/// kcal = MET × 体重kg × 时长h（[estimateBurnKcal]），UI 按 ±20% 口径标注
/// （§3.5 误差口径标注 P0——与 AI 置信度同一信任语言）。
///
/// 保存走 [fitnessServiceProvider]：fitness_sessions + entries(kind=fitness)
/// + entry_lines(type=burn) 同事务落库（§5.5⑦ entry_id 联动、§6.2 写路径），
/// 仪表盘 reactive stream 即时重发（净热量 = 摄入 − 消耗，§3.2/§3.5）。
library;

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../common/format.dart';
import '../../data/fitness_service.dart';
import '../dashboard/dashboard_state.dart';
import 'plan_state.dart';

/// 保存按钮测试锚点。
const Key fitnessSaveKey = ValueKey('fitness_save');

/// 时长输入测试锚点。
const Key fitnessDurationFieldKey = ValueKey('fitness_duration_field');

/// 体重输入测试锚点。
const Key fitnessWeightFieldKey = ValueKey('fitness_weight_field');

/// MET 估算摘要测试锚点。
const Key fitnessEstimateKey = ValueKey('fitness_estimate');

// 类型分段测试锚点前缀（fitness_type_<wire>）：key 在 _TypeSegments 内。

/// 健身手动记录页。
class FitnessLogPage extends ConsumerStatefulWidget {
  const FitnessLogPage({super.key});

  @override
  ConsumerState<FitnessLogPage> createState() => _FitnessLogPageState();
}

class _FitnessLogPageState extends ConsumerState<FitnessLogPage> {
  String _type = 'cardio'; // 缺省有氧（最常见手动记录，§5.5⑦ type）
  String _durationText = '';
  // 体重输入用持久控制器：流首帧回填一次（身体档案 §3.5），用户改动后不再
  // 覆盖——避免每次 build 新建控制器导致光标/输入状态丢失。
  final TextEditingController _weightController = TextEditingController();
  bool _weightTouched = false;
  String _note = '';
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final selectedDate = ref.watch(selectedDateProvider);
    final dateText = formatCalendarDay(selectedDate);
    final weightAsync = ref.watch(bodyWeightKgProvider);

    // 体重回填：流首帧/设置变更时同步输入框（用户改过则不覆盖）。
    final weightKg = weightAsync.value ?? kDefaultBodyWeightKg;
    if (!_weightTouched && weightAsync.hasValue && _weightController.text.isEmpty) {
      _weightController.text = _formatWeight(weightKg);
    }

    final duration = int.tryParse(_durationText.trim());
    final parsedWeight = double.tryParse(_weightController.text.trim());
    final estimate = (duration != null && duration > 0 && parsedWeight != null)
        ? estimateBurnKcal(
            type: _type, weightKg: parsedWeight, durationMinutes: duration)
        : null;
    final canSave = !_saving && duration != null && duration > 0;

    return Scaffold(
      appBar: AppBar(title: const Text('记录健身')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // 归属日（§3.2「一切围绕日期」：随仪表盘当前选中日）。
            Text(
              '归属日：${calendarDayLabel(dateText)}',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 16),
            _FieldLabel('类型（§5.5⑦）'),
            _TypeSegments(
              selected: _type,
              onSelected: (type) => setState(() => _type = type),
            ),
            const SizedBox(height: 16),
            _FieldLabel('时长（分钟）'),
            TextField(
              key: fitnessDurationFieldKey,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                hintText: '如 30',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _durationText = v),
            ),
            const SizedBox(height: 16),
            _FieldLabel('体重（kg，身体档案 §3.5）'),
            TextField(
              key: fitnessWeightFieldKey,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'MET 估算依赖，如 60',
                border: OutlineInputBorder(),
              ),
              controller: _weightController,
              onChanged: (_) => _weightTouched = true,
            ),
            const SizedBox(height: 16),
            _FieldLabel('备注（可空）'),
            TextField(
              decoration: const InputDecoration(
                hintText: '如 晨跑 5km',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => _note = v,
            ),
            const SizedBox(height: 20),
            // MET 估算摘要（§3.5 估算式 + ±20% 口径标注）。
            if (estimate != null)
              Container(
                key: fitnessEstimateKey,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.kcalOut.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '预计消耗 ≈ $estimate kcal'
                  '（MET ${_metOf(_type)} × ${_formatWeight(parsedWeight)}kg'
                  ' × ${duration}min，±20% 口径 §3.5）',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: tokens.kcalOut),
                ),
              )
            else
              Text(
                '填时长与体重后自动估算消耗（MET 表 ±20% 口径，§3.5）',
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            const SizedBox(height: 20),
            if (_errorText != null) ...[
              Text(
                _errorText!,
                style: TextStyle(fontSize: 13, color: tokens.danger),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              key: fitnessSaveKey,
              onPressed: canSave ? () => _save() : null,
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
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: tokens.onPrimary,
                      ),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              '保存后消耗计入仪表盘运动条与净热量（摄入 − 消耗，§3.5）',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final duration = int.tryParse(_durationText.trim());
    final weight =
        double.tryParse(_weightController.text.trim()) ?? kDefaultBodyWeightKg;
    if (duration == null || duration <= 0) return;
    final kcal = estimateBurnKcal(
      type: _type,
      weightKg: weight,
      durationMinutes: duration,
    );
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref.read(fitnessServiceProvider).saveSession(FitnessSessionInput(
            date: formatCalendarDay(ref.read(selectedDateProvider)),
            type: _type,
            durationMinutes: duration,
            kcalBurn: kcal,
            weightKg: weight,
            note: _note.trim().isEmpty ? null : _note.trim(),
          ));
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = '保存失败，请重试（本地库写入，§3.7 离线优先）';
      });
    }
  }

  double _metOf(String type) => kMetTable[type] ?? kMetTable['other']!;

  String _formatWeight(double? kg) {
    if (kg == null) return '${kDefaultBodyWeightKg.round()}';
    return kg == kg.roundToDouble()
        ? '${kg.round()}'
        : kg.toStringAsFixed(1);
  }
}

/// 类型分段（§5.5⑦ type 四档；key=`fitness_type_<wire>` 供测试定位）。
class _TypeSegments extends StatelessWidget {
  const _TypeSegments({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final motion = context.motion;
    return Row(
      children: [
        for (final entry in kFitnessTypeLabels.entries) ...[
          if (entry != kFitnessTypeLabels.entries.first)
            const SizedBox(width: 8),
          Expanded(
            child: AnimatedContainer(
              duration: motion.chipCheck, // §9.2 dur.s chip 微交互
              curve: motion.springSnappy.curve,
              decoration: BoxDecoration(
                color: selected == entry.key
                    ? tokens.primary.withValues(alpha: 0.12)
                    : tokens.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected == entry.key ? tokens.primary : tokens.outline,
                  width: selected == entry.key ? 1.5 : 1,
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: ValueKey('fitness_type_${entry.key}'),
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelected(entry.key),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected == entry.key
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: selected == entry.key
                              ? tokens.primary
                              : tokens.onSurfaceMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 字段分组标签（与录入抽屉同形）。
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
