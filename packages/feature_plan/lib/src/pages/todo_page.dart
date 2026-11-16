/// 待办页（§3.6 待办基础 P0、§5.5⑩ todos、§11.1 W5-6 主线任务 2）。
///
/// 双视图（§3.6）：今日待办（date=今天）与收集箱（date IS NULL）；
/// 勾选经 [PlanGateway.setTodoDone]（done_at 只前进合并，§6.5）→ 同事务
/// 重算 day_summary.todo_done/todo_total（§5.6）。
///
/// 复用既有抽象：核心 CRUD 全部走 core_db `TodoDao`（经网关代理，§10.4），
/// 本页只做视图编排，不重复实现任何合并/投影语义。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../plan_gateway.dart';
import '../plan_providers.dart';

/// 新增输入框测试锚点。
const Key todoInputKey = ValueKey('todo_input');

/// 新增按钮测试锚点。
const Key todoAddKey = ValueKey('todo_add');

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

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    final todos = _view == _TodoView.today
        ? ref.watch(todayTodosProvider(_today)).value
        : ref.watch(inboxTodosProvider).value;
    final summary = ref.watch(planDaySummaryProvider(_today)).value;

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
            if (_view == _TodoView.today && summary != null)
              Text(
                '已完成 ${summary.todoDone}/${summary.todoTotal}'
                '（§5.6 投影）',
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
              child: todos == null
                  ? const Center(child: CircularProgressIndicator())
                  : todos.isEmpty
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
                          itemCount: todos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) =>
                              _TodoTile(todo: todos[index], view: _view),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条待办瓦片：勾选联动投影（§5.6 todo_done）、删除=墓碑（§5.1）、
/// 收集箱项可「加入今日」（§3.6）。
class _TodoTile extends ConsumerWidget {
  const _TodoTile({required this.todo, required this.view});

  final cdb.Todo todo;
  final _TodoView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final done = todo.doneAt != null;
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
              child: Text(
                todo.title,
                style: TextStyle(
                  fontSize: 15,
                  color: done ? tokens.onSurfaceMuted : tokens.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (view == _TodoView.inbox && !done)
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
