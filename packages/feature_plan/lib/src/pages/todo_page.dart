/// 待办页（§3.6 待办基础 P0 + 待办完整版 P1（W13）、§5.5⑩ todos、
/// §11.1 W5-6 主线任务 2、§11.2 W13 主线「待办完整版（RRULE+提醒）」）。
///
/// 双视图（§3.6）：今日待办（date=今天）与收集箱（date IS NULL）。
/// W13 起今日视图读**当日实例流**（[todoDayInstancesProvider]）：非重复行
/// date=当日直出；重复待办按 anchor 展开命中当日的虚拟实例——查询时展开、
/// 不预生成行（取舍见 rrule.dart 文档注释）；勾选经
/// [PlanGateway.setTodoDone] 作用于基行（done_at 只前进合并 §6.5），同事务
/// 重算 day_summary.todo_done/todo_total（§5.6，锚点日即基行 date）。
///
/// 编辑入口：点瓦片或「详细」按钮 → [TodoEditorSheet]（标题/备注/重复规则
/// （每天/每周 X/每月 X 日/自定义间隔 N 天）/提醒时刻）；提醒只落 remind_at
/// 字段，真实通知由壳层调度（§3.6 P1，feature 层不触通知通道）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../plan_models.dart';
import '../plan_providers.dart';
import '../widgets/todo_editor_sheet.dart';

/// 新增输入框测试锚点。
const Key todoInputKey = ValueKey('todo_input');

/// 新增按钮测试锚点。
const Key todoAddKey = ValueKey('todo_add');

/// 详细编辑按钮测试锚点（打开 W13 编辑抽屉）。
const Key todoAdvancedKey = ValueKey('todo_advanced');

/// 勾选框测试锚点（`todo_check_$todoId`）。
Key todoCheckKey(String todoId) => ValueKey('todo_check_$todoId');

/// 删除按钮测试锚点（`todo_delete_$todoId`）。
Key todoDeleteKey(String todoId) => ValueKey('todo_delete_$todoId');

/// 收集箱→今日按钮测试锚点（`todo_move_today_$todoId`）。
Key todoMoveTodayKey(String todoId) => ValueKey('todo_move_today_$todoId');

/// 视图档位（§3.6 双视图）。
enum _TodoView { today, inbox }

/// 待办页。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  late final TextEditingController _input = TextEditingController();
  _TodoView _view = _TodoView.today;

  /// 今日（页面生命周期内固定，避免跨日抖动；§5.1 本地日历日）。
  late final String _today = dom.formatCalendarDay(DateTime.now());

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    _input.clear();
    final gateway = ref.read(planGatewayProvider);
    // 收集箱视图新增 date=null（§5.5⑩）；今日视图带当日计划日。
    gateway
        .createTodo(title: title, date: _view == _TodoView.today ? _today : null);
  }

  /// 打开 W13 编辑抽屉（§3.6）：[todo] 非空=编辑基行；空=新建
  /// （今日视图挂当日计划日、收集箱挂 null，§5.5⑩）。
  void _openEditor({cdb.Todo? todo}) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => TodoEditorSheet(
        todo: todo,
        planDate: todo != null
            ? null
            : (_view == _TodoView.today ? _today : null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    // W13：今日视图读当日实例流（重复待办查询时展开，§3.6/§11.2 W13）。
    final instances = _view == _TodoView.today
        ? ref.watch(todoDayInstancesProvider(_today)).value
        : ref.watch(todoDayInstancesProvider(null)).value;

    return Scaffold(
      appBar: AppBar(title: const Text('待办')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_TodoView>(
              segments: const [
                ButtonSegment(value: _TodoView.today, label: Text('今日待办')),
                ButtonSegment(value: _TodoView.inbox, label: Text('收集箱')),
              ],
              selected: {_view},
              onSelectionChanged: (selection) =>
                  setState(() => _view = selection.first),
            ),
            const SizedBox(height: 12),
            if (instances != null)
              Text(
                '已完成 ${instances.where((t) => t.done).length}/${instances.length}'
                '（§3.6 W13 当日实例口径）',
                style:
                    TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: todoInputKey,
                    controller: _input,
                    style: TextStyle(fontSize: 15, color: tokens.onSurface),
                    decoration: InputDecoration(
                      hintText: '添加待办…',
                      hintStyle:
                          TextStyle(fontSize: 14, color: tokens.onSurfaceMuted),
                      filled: true,
                      fillColor: tokens.surfaceCard,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: tokens.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: tokens.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: tokens.primary, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: todoAdvancedKey,
                  tooltip: '详细（重复/提醒，§3.6 W13）',
                  onPressed: () => _openEditor(),
                  icon: const Icon(Icons.tune),
                ),
                IconButton.filled(
                  key: todoAddKey,
                  tooltip: '添加',
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: instances == null
                  ? const Center(child: CircularProgressIndicator())
                  : instances.isEmpty
                      ? Center(
                          child: Text(
                            _view == _TodoView.today
                                ? '今日暂无待办（§3.6）'
                                : '收集箱为空：随手记的想法先放这里（§5.5⑩）',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 14, color: tokens.onSurfaceMuted),
                          ),
                        )
                      : ListView.separated(
                          itemCount: instances.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) => _TodoTile(
                            instance: instances[index],
                            view: _view,
                            onEdit: () => _openEditor(
                                todo: instances[index].todo),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条待办实例瓦片（§3.6 W13）：勾选联动投影（§5.6 todo_done）、删除=
/// 基行墓碑（§5.1）、收集箱项可「加入今日」（§3.6）、重复实例展示规则
/// 摘要 + 提醒角标；点标题进编辑抽屉（重复/提醒，§3.6 完整版）。
class _TodoTile extends ConsumerWidget {
  const _TodoTile({
    required this.instance,
    required this.view,
    required this.onEdit,
  });

  final TodoDayInstance instance;
  final _TodoView view;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final todo = instance.todo;
    final done = instance.done;
    final gateway = ref.read(planGatewayProvider);
    return Material(
      color: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              key: todoCheckKey(todo.id),
              value: done,
              onChanged: (value) =>
                  gateway.setTodoDone(todo.id, done: value ?? false),
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        style: TextStyle(
                          fontSize: 15,
                          color:
                              done ? tokens.onSurfaceMuted : tokens.onSurface,
                          decoration:
                              done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (instance.recurring || todo.remindAt != null)
                        Row(
                          children: [
                            if (instance.recurring)
                              Text(
                                '${instance.repeatLabel ?? '重复'}（§5.5⑩）',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: tokens.onSurfaceMuted),
                              ),
                            if (instance.recurring && todo.remindAt != null)
                              const SizedBox(width: 6),
                            if (todo.remindAt != null)
                              Icon(Icons.alarm,
                                  size: 13, color: tokens.onSurfaceMuted),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (view == _TodoView.inbox && !done && !instance.recurring)
              TextButton(
                key: todoMoveTodayKey(todo.id),
                onPressed: () => gateway.moveTodoToToday(todo.id,
                    date: dom.formatCalendarDay(DateTime.now())),
                child: const Text('加入今日'),
              ),
            IconButton(
              key: todoDeleteKey(todo.id),
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除',
              onPressed: () => gateway.deleteTodo(todo.id),
            ),
          ],
        ),
      ),
    );
  }
}
