/// 新建/编辑健身计划抽屉（§11.2 W14 主线任务 1、§3.5 健身计划 P1、
/// §5.5⑧：模板=名称+动作列表（动作名/组数/目标次数/目标重量/组间休息秒）
/// +按周排期（周一~周日勾选哪天练，存 fitness_plans.weekday_mask，
/// bit0=周一…bit6=周日））。
///
/// 形态与口径：
/// - 动作行支持增删；重量以 kg 输入、落库 ×10 定点（§5.5⑨ weight_kg_x10）；
/// - 组间休息秒缺省提示 90（§3.5 组间计时器读数来源，0=不计时）；
/// - 排期掩码可全不勾（纯模板：不出现在任何排期日、仍可一键开练）；
/// - 编辑模式预填既有计划（名称/掩码/动作列表），保存走
///   [PlanGateway.updateFitnessPlanDetails]；新建走 [PlanGateway.createFitnessPlan]
///   （§6.2 行快照同事务入队由网关承担）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../fitness_plan_models.dart';
import '../plan_gateway.dart';
import 'plan_sheet_sizing.dart';
import 'plan_text_field.dart';

/// 名称输入测试锚点。
const Key fitnessPlanNameFieldKey = ValueKey('fitness_plan_name_field');

/// 周排期勾选 chip 测试锚点（`fitness_plan_weekday_$bitIndex`，bit0=周一）。
Key fitnessPlanWeekdayChipKey(int bitIndex) =>
    ValueKey('fitness_plan_weekday_$bitIndex');

/// 添加动作按钮测试锚点。
const Key fitnessPlanAddExerciseKey = ValueKey('fitness_plan_add_exercise');

/// 动作行各输入测试锚点（`fitness_plan_exercise_$rowKey` 前缀）。
Key fitnessPlanExerciseNameKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_name_$rowKey');
Key fitnessPlanExerciseSetsKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_sets_$rowKey');
Key fitnessPlanExerciseRepsKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_reps_$rowKey');
Key fitnessPlanExerciseWeightKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_weight_$rowKey');
Key fitnessPlanExerciseRestKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_rest_$rowKey');
Key fitnessPlanExerciseDeleteKey(String rowKey) =>
    ValueKey('fitness_plan_exercise_delete_$rowKey');

/// 保存按钮测试锚点。
const Key fitnessPlanSubmitKey = ValueKey('fitness_plan_submit');

/// 动作行编辑草稿（行标识稳定键：删除某行不串其他行的输入内容）。
class _ExerciseRowDraft {
  _ExerciseRowDraft(this.rowKey);

  final String rowKey;
  String name = '';
  String sets = '';
  String reps = '';
  String weight = '';
  String rest = '';
}

/// 新建/编辑健身计划抽屉（§9.3#3 弹簧 bottomSheet 承载，由调用方唤起）。
class FitnessPlanEditorSheet extends ConsumerStatefulWidget {
  const FitnessPlanEditorSheet({super.key, this.plan});

  /// 非空=编辑模式（预填）；空=新建。
  final cdb.FitnessPlan? plan;

  @override
  ConsumerState<FitnessPlanEditorSheet> createState() =>
      _FitnessPlanEditorSheetState();
}

class _FitnessPlanEditorSheetState
    extends ConsumerState<FitnessPlanEditorSheet> {
  static int _rowSeq = 0;

  String _name = '';
  final Set<int> _selectedBits = <int>{};
  final List<_ExerciseRowDraft> _rows = <_ExerciseRowDraft>[];
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final plan = widget.plan;
    if (plan != null) {
      _name = plan.name;
      for (var i = 0; i < kPlanWeekdayLabels.length; i++) {
        if ((plan.weekdayMask >> i) & 1 == 1) _selectedBits.add(i);
      }
      final template = FitnessPlanTemplate.decode(plan.exercises);
      for (final e in template.exercises) {
        final row = _ExerciseRowDraft('r${_rowSeq++}')
          ..name = e.name
          ..sets = '${e.sets}'
          ..reps = '${e.targetReps}'
          ..weight = e.targetWeightKgX10 == 0
              ? ''
              : e.targetWeightKgX10 % 10 == 0
                  ? '${e.targetWeightKgX10 ~/ 10}'
                  : e.targetWeightKg.toStringAsFixed(1)
          ..rest = '${e.restS}';
        _rows.add(row);
      }
    }
    if (_rows.isEmpty) _rows.add(_ExerciseRowDraft('r${_rowSeq++}'));
  }

  void _toggleBit(int bit) => setState(() {
        if (!_selectedBits.remove(bit)) _selectedBits.add(bit);
      });

  void _addRow() => setState(() {
        _rows.add(_ExerciseRowDraft('r${_rowSeq++}'));
        _errorText = null;
      });

  void _removeRow(_ExerciseRowDraft row) => setState(() {
        _rows.remove(row);
        _errorText = null;
      });

  /// 组装动作列表并保存（§5.5⑧；空名行丢弃，校验失败显示错误不打断输入，
  /// §3.7）。
  Future<void> _submit() async {
    final name = _name.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请填写计划名');
      return;
    }
    final exercises = <PlanExercise>[];
    for (final row in _rows) {
      final exerciseName = row.name.trim();
      if (exerciseName.isEmpty) continue; // 空名行丢弃（§11.2 W14 编辑器口径）
      final sets = int.tryParse(row.sets.trim());
      final reps = int.tryParse(row.reps.trim());
      final weight = double.tryParse(row.weight.trim());
      final rest = int.tryParse(row.rest.trim());
      if (sets == null ||
          sets < 1 ||
          reps == null ||
          reps < 1 ||
          (weight != null && weight < 0) ||
          (rest != null && rest < 0)) {
        setState(() => _errorText =
            '「$exerciseName」的组数/目标次数需为正整数，重量/休息需非负数字');
        return;
      }
      exercises.add(PlanExercise(
        name: exerciseName,
        sets: sets,
        targetReps: reps,
        // kg → ×10 定点（§5.5⑨ weight_kg_x10；空=自重 0）。
        targetWeightKgX10: ((weight ?? 0) * 10).round(),
        restS: rest ?? 0,
      ));
    }
    if (exercises.isEmpty) {
      setState(() => _errorText = '至少需要一个动作');
      return;
    }
    final gateway = ref.read(planGatewayProvider);
    final plan = widget.plan;
    if (plan == null) {
      await gateway.createFitnessPlan(
        name: name,
        weekdayMask: _maskValue,
        exercises: exercises,
      );
    } else {
      await gateway.updateFitnessPlanDetails(
        id: plan.id,
        name: name,
        weekdayMask: _maskValue,
        exercises: exercises,
        active: plan.active,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  int get _maskValue {
    var mask = 0;
    for (final bit in _selectedBits) {
      mask |= 1 << bit;
    }
    return mask;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final editing = widget.plan != null;
    // 稳定高度外框（planSheetHeight，与 capture 录入抽屉同口径）：动态动作行
    // 在内容区滚动，主 CTA「创建/保存」钉底（外框高度恒定）。
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
                      editing ? '编辑健身计划' : '新建健身计划',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface),
                    ),
                    const SizedBox(height: 12),
                    PlanTextField(
                      key: fitnessPlanNameFieldKey,
                      initial: _name,
                      hint: '计划名（如 推拉腿）',
                      onChanged: (v) => setState(() => _name = v),
                    ),
                    const SizedBox(height: 12),
                    Text('按周排期（勾选哪天练）',
                        style:
                            TextStyle(fontSize: 13, color: tokens.onSurfaceMuted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < kPlanWeekdayLabels.length; i++)
                          FilterChip(
                            key: fitnessPlanWeekdayChipKey(i),
                            label: Text(kPlanWeekdayLabels[i]),
                            selected: _selectedBits.contains(i),
                            onSelected: (_) => _toggleBit(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('动作列表（动作名/组数/目标次数/目标重量/组间休息秒）',
                        style:
                            TextStyle(fontSize: 13, color: tokens.onSurfaceMuted)),
                    const SizedBox(height: 8),
                    for (final row in _rows)
                      _ExerciseRowCard(
                        key: ValueKey<String>(row.rowKey),
                        row: row,
                        onRemove: () => _removeRow(row),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: fitnessPlanAddExerciseKey,
                      onPressed: _addRow,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加动作'),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(_errorText!,
                          style: TextStyle(fontSize: 13, color: tokens.danger)),
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
                  key: fitnessPlanSubmitKey,
                  onPressed: _submit,
                  child: Text(editing ? '保存修改' : '创建计划'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个动作行卡（名称 + 组数/次数/重量/休息四小字段 + 删除）。
class _ExerciseRowCard extends StatelessWidget {
  const _ExerciseRowCard({
    super.key,
    required this.row,
    required this.onRemove,
  });

  final _ExerciseRowDraft row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: PlanTextField(
                      key: fitnessPlanExerciseNameKey(row.rowKey),
                      initial: row.name,
                      hint: '动作名（如 卧推）',
                      onChanged: (v) => row.name = v,
                    ),
                  ),
                  IconButton(
                    key: fitnessPlanExerciseDeleteKey(row.rowKey),
                    tooltip: '移除动作',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onRemove,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _smallField(
                    context,
                    label: '组数',
                    fieldKey: fitnessPlanExerciseSetsKey(row.rowKey),
                    initial: row.sets,
                    hint: '3',
                    onChanged: (v) => row.sets = v,
                  ),
                  const SizedBox(width: 8),
                  _smallField(
                    context,
                    label: '目标次数',
                    fieldKey: fitnessPlanExerciseRepsKey(row.rowKey),
                    initial: row.reps,
                    hint: '10',
                    onChanged: (v) => row.reps = v,
                  ),
                  const SizedBox(width: 8),
                  _smallField(
                    context,
                    label: '重量kg',
                    fieldKey: fitnessPlanExerciseWeightKey(row.rowKey),
                    initial: row.weight,
                    hint: '40',
                    onChanged: (v) => row.weight = v,
                  ),
                  const SizedBox(width: 8),
                  _smallField(
                    context,
                    label: '休息秒',
                    fieldKey: fitnessPlanExerciseRestKey(row.rowKey),
                    initial: row.rest,
                    hint: '90',
                    onChanged: (v) => row.rest = v,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小数字字段（标签 + 窄输入；样式引用语义 token，§8.2 第 3 层）。
  Widget _smallField(
    BuildContext context, {
    required String label,
    required Key fieldKey,
    required String initial,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    final tokens = context.slimca;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: tokens.onSurfaceMuted)),
          const SizedBox(height: 4),
          SizedBox(
            height: 52,
            child: PlanTextField(
              key: fieldKey,
              initial: initial,
              hint: hint,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
