/// 收集箱页（§3.6 待办 P0 + 待办完整版 P1（W13）、§5.5⑩ todos）。
///
/// 定位（计划域 IA 重设计）：今日待办由壳层计划 Tab「今日待办」卡承载
/// （就地勾选/快速添加），本页只管**收集箱**（date IS NULL 的未排期池）：
/// 随手记的想法先进这里，再「加入今日」安排；重复/提醒在编辑抽屉设置
/// （收集箱待办无计划日——重复自保存日起展开，锚点口径见 rrule.dart）。
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

/// 收集箱页。
class TodoPage extends ConsumerStatefulWidget {
  const TodoPage({super.key});

  @override
  ConsumerState<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends ConsumerState<TodoPage> {
  late final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final title = _input.text.trim();
    if (title.isEmpty) return;
    _input.clear();
    // 收集箱新增 date=null（§5.5⑩ date IS NULL=收集箱池）。
    ref.read(planGatewayProvider).createTodo(title: title, date: null);
  }

  /// 打开 W13 编辑抽屉（§3.6）：[todo] 非空=编辑基行；空=新建
  /// （收集箱计划日=null，重复自保存日起展开，§5.5⑩）。
  void _openEditor({cdb.Todo? todo}) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => TodoEditorSheet(todo: todo, planDate: null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    // Riverpod 3 读态约定（与 capture_page 同口径）：.value + null 骨架帧。
    // 收集箱流：date IS NULL 基行直出、不展开（无展开起点，§5.5⑩）。
    final instances = ref.watch(todoDayInstancesProvider(null)).value;

    return Scaffold(
      appBar: AppBar(title: const Text('收集箱')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (instances != null)
              Text(
                '已完成 ${instances.where((t) => t.done).length}/${instances.length}',
                style:
                    TextStyle(fontSize: 13, color: tokens.onSurfaceMuted),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: todoInputKey,
                    controller: _input,
                    style: TextStyle(fontSize: 15, color: tokens.onSurface),
                    decoration: InputDecoration(
                      hintText: '随手记，先放收集箱…',
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
                  tooltip: '详细（重复/提醒）',
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
                            '收集箱为空：随手记的想法先放这里，再安排到具体的日子',
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

/// 收集箱瓦片（§3.6 W13）：勾选=行级完成（done_at 只前进 §6.5）、删除=基行
/// 墓碑（§5.1）、「加入今日」回填计划日（§3.6）；重复收集箱行展示规则摘要 +
/// 提醒角标；点标题进编辑抽屉（重复/提醒，§3.6 完整版）。
class _TodoTile extends ConsumerWidget {
  const _TodoTile({
    required this.instance,
    required this.onEdit,
  });

  final TodoDayInstance instance;
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
                                instance.repeatLabel ?? '重复',
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
            if (!done && !instance.recurring)
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
