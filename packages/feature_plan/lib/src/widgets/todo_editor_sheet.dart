/// 待办编辑抽屉（§3.6 待办完整版 P1：重复（RRULE）+ 提醒，§5.5⑩、
/// §11.2 W13 主线「待办完整版（RRULE+提醒）」）。
///
/// 双模式：
/// - 新建（[TodoEditorSheet.todo]==null）：落 [PlanGateway.createTodo]，
///   计划日=[planDate]（今日视图传当日；收集箱传 null——收集箱重复待办
///   无展开起点，锚点自保存日起，§5.5⑩）；
/// - 编辑（todo 非空）：落 [PlanGateway.updateTodoDetails]，重复规则/提醒
///   独立更新；清空规则时锚点一并清（锚点随 series 语义，上层决策口径见
///   todo_dao.dart updateDetails 注释）。
///
/// 提醒口径（§3.6 P1）：本抽屉只落 remind_at 字段（本地时:分 + 计划日 →
/// UTC ms，§5.5⑩ remind_at）；真实通知由壳层调度——apps/mobile 接本地通知
/// 插件后按 remind_at 的本地时:分 + RRULE 逐实例重排（feature 层不触通知
/// 通道，测试亦不产生任何真实通知）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../rrule.dart';
import '../widgets/plan_text_field.dart';

/// 编辑抽屉标题输入测试锚点。
const Key todoEditorTitleKey = ValueKey('todo_editor_title');

/// 编辑抽屉备注输入测试锚点。
const Key todoEditorNoteKey = ValueKey('todo_editor_note');

/// 编辑抽屉保存按钮测试锚点。
const Key todoEditorSaveKey = ValueKey('todo_editor_save');

/// 重复档位选择 chip 测试锚点（`todo_repeat_$kindName`）。
Key todoRepeatChipKey(TodoRepeatKind kind) =>
    ValueKey('todo_repeat_${kind.name}');

/// 每周档星期 chip 测试锚点（`todo_weekday_$n`，1=周一…7=周日）。
Key todoWeekdayChipKey(int weekday) => ValueKey('todo_weekday_$weekday');

/// 每月档「几号」输入测试锚点。
const Key todoEditorMonthDayKey = ValueKey('todo_editor_month_day');

/// 自定义间隔「几天」输入测试锚点。
const Key todoEditorIntervalKey = ValueKey('todo_editor_interval');

/// 提醒开关测试锚点。
const Key todoEditorRemindToggleKey = ValueKey('todo_editor_remind_toggle');

/// 提醒时刻选择按钮测试锚点。
const Key todoEditorRemindPickKey = ValueKey('todo_editor_remind_pick');

/// 提醒清除按钮测试锚点。
const Key todoEditorRemindClearKey = ValueKey('todo_editor_remind_clear');

/// 待办编辑抽屉（重复规则 + 提醒，§3.6 W13）。
class TodoEditorSheet extends ConsumerStatefulWidget {
  const TodoEditorSheet({super.key, this.todo, this.planDate});

  /// 非空=编辑模式（作用于该基行）；null=新建。
  final cdb.Todo? todo;

  /// 新建模式的计划日（null=收集箱收集，§5.5⑩）。
  final String? planDate;

  @override
  ConsumerState<TodoEditorSheet> createState() => _TodoEditorSheetState();
}

class _TodoEditorSheetState extends ConsumerState<TodoEditorSheet> {
  String _titleText = '';
  String _noteText = '';

  TodoRepeatKind _kind = TodoRepeatKind.none;
  String _monthDayText = '';
  String _intervalText = '';
  int _weekday = DateTime.now().weekday; // 每周档缺省选中当日星期

  bool _remindEnabled = false;
  ({int hour, int minute}) _remindTime = (hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    final todo = widget.todo;
    if (todo != null) {
      _titleText = todo.title;
      _noteText = todo.note ?? '';
      final spec = TodoRepeatSpec.fromRrule(todo.repeatRule);
      if (spec != null) {
        _kind = spec.kind;
        _weekday = spec.weekday;
        _monthDayText = '${spec.monthDay}';
        _intervalText = '${spec.intervalDays}';
      }
      if (todo.remindAt != null) {
        _remindEnabled = true;
        _remindTime = localTimeOfDay(todo.remindAt!);
      }
    }
  }

  bool get _isEdit => widget.todo != null;

  /// 当前编辑中的规则（月内日/间隔非法时返回 null → 保存不可用）。
  TodoRepeatSpec? get _spec {
    switch (_kind) {
      case TodoRepeatKind.none:
        return const TodoRepeatSpec.none();
      case TodoRepeatKind.daily:
        return const TodoRepeatSpec.daily();
      case TodoRepeatKind.weekly:
        return TodoRepeatSpec.weekly(_weekday);
      case TodoRepeatKind.monthly:
        final day = int.tryParse(_monthDayText.trim());
        if (day == null || day < 1 || day > 31) return null;
        return TodoRepeatSpec.monthly(day);
      case TodoRepeatKind.everyNDays:
        final n = int.tryParse(_intervalText.trim());
        if (n == null || n < 2) return null;
        return TodoRepeatSpec.everyNDays(n);
    }
  }

  bool get _canSave =>
      _titleText.trim().isNotEmpty && _spec != null;

  Future<void> _save() async {
    final title = _titleText.trim();
    if (title.isEmpty) return;
    final spec = _spec;
    if (spec == null) return; // 月内日/间隔非法：按钮置灰兜底，双保险
    final gateway = ref.read(planGatewayProvider);
    final note = _noteText.trim();
    final todo = widget.todo;
    final today = featureLocalToday();
    if (todo == null) {
      final planDate = widget.planDate;
      await gateway.createTodo(
        title: title,
        note: note.isEmpty ? null : note,
        date: planDate,
        repeatRule: spec.kind == TodoRepeatKind.none ? null : spec.toRrule(),
        // 提醒：计划日 + 时:分 → UTC ms（§5.5⑩ remind_at）；收集箱
        // （date=null）提醒挂当日时:分（壳层重排口径，见文件头注释）。
        remindAt: _remindEnabled
            ? remindAtMsFor(
                day: planDate ?? today,
                hour: _remindTime.hour,
                minute: _remindTime.minute,
              )
            : null,
      );
    } else {
      final newRule =
          spec.kind == TodoRepeatKind.none ? null : spec.toRrule();
      await gateway.updateTodoDetails(
        id: todo.id,
        title: title,
        note: note.isEmpty ? null : note,
        repeatRule: newRule,
        remindAt: _remindEnabled
            ? remindAtMsFor(
                day: todo.date ?? today,
                hour: _remindTime.hour,
                minute: _remindTime.minute,
              )
            : null,
        // 锚点策略（§5.5⑩ rrule_anchor_date，上层决策口径）：
        // - 清空规则 → 锚点一并清（series 语义随之终结）；
        // - 设规则且基行无锚点（W13 前老行/收集箱行）→ 锚点=计划日或今日；
        // - 其余（已有锚点）→ 不改动（series 展开起点不随编辑漂移）。
        clearAnchor: newRule == null && todo.repeatRule != null,
        anchorDate: newRule != null && todo.rruleAnchorDate == null
            ? (todo.date ?? today)
            : null,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? '编辑待办' : '新建待办',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface),
            ),
            const SizedBox(height: 12),
            PlanTextField(
              key: todoEditorTitleKey,
              initial: _titleText,
              hint: '标题（必填）',
              onChanged: (v) => setState(() => _titleText = v),
            ),
            const SizedBox(height: 12),
            PlanTextField(
              key: todoEditorNoteKey,
              initial: _noteText,
              hint: '备注（可选）',
              maxLines: 2,
              onChanged: (v) => _noteText = v,
            ),
            const SizedBox(height: 16),
            Text('重复（RRULE，§5.5⑩）',
                style: TextStyle(fontSize: 13, color: tokens.onSurfaceMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in TodoRepeatKind.values)
                  ChoiceChip(
                    key: todoRepeatChipKey(kind),
                    label: Text(_kindLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            if (_kind == TodoRepeatKind.weekly) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var w = 1; w <= 7; w++)
                    ChoiceChip(
                      key: todoWeekdayChipKey(w),
                      label: Text('周${weekdayLabel(w)}'),
                      selected: _weekday == w,
                      onSelected: (_) => setState(() => _weekday = w),
                    ),
                ],
              ),
            ],
            if (_kind == TodoRepeatKind.monthly) ...[
              const SizedBox(height: 8),
              PlanTextField(
                key: todoEditorMonthDayKey,
                initial: _monthDayText,
                hint: '每月几日（1-31）',
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _monthDayText = v),
              ),
            ],
            if (_kind == TodoRepeatKind.everyNDays) ...[
              const SizedBox(height: 8),
              PlanTextField(
                key: todoEditorIntervalKey,
                initial: _intervalText,
                hint: '间隔天数（≥2）',
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _intervalText = v),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  key: todoEditorRemindToggleKey,
                  value: _remindEnabled,
                  onChanged: (v) => setState(() => _remindEnabled = v),
                ),
                const SizedBox(width: 4),
                Text('提醒',
                    style: TextStyle(fontSize: 15, color: tokens.onSurface)),
                const Spacer(),
                if (_remindEnabled) ...[
                  TextButton(
                    key: todoEditorRemindPickKey,
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                            hour: _remindTime.hour, minute: _remindTime.minute),
                      );
                      if (picked != null) {
                        setState(() => _remindTime =
                            (hour: picked.hour, minute: picked.minute));
                      }
                    },
                    child: Text(formatTimeOfDay(
                        hour: _remindTime.hour, minute: _remindTime.minute)),
                  ),
                  IconButton(
                    key: todoEditorRemindClearKey,
                    tooltip: '清除提醒',
                    icon: const Icon(Icons.alarm_off, size: 20),
                    onPressed: () => setState(() => _remindEnabled = false),
                  ),
                ],
              ],
            ),
            if (widget.planDate == null && !_isEdit)
              Text(
                '收集箱待办无计划日：重复自保存日起展开（§5.5⑩）',
                style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: todoEditorSaveKey,
              onPressed: _canSave ? _save : null,
              child: Text(_isEdit ? '保存' : '创建'),
            ),
          ],
        ),
      ),
    );
  }

  /// 档位标签（选档 chip 文案；瓦片细 label 用 [TodoRepeatSpec.label]）。
  String _kindLabel(TodoRepeatKind kind) => switch (kind) {
        TodoRepeatKind.none => '不重复',
        TodoRepeatKind.daily => '每天',
        TodoRepeatKind.weekly => '每周…',
        TodoRepeatKind.monthly => '每月…',
        TodoRepeatKind.everyNDays => '自定义间隔',
      };
}
