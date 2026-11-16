/// 计划 Tab 真页（§4.2「待办 / 健身 / 存钱三卡」、§11.1 W5-6「记账完整化：
/// 分类/每日目标/日简报」中的计划侧落地）。
///
/// 数据源（plan_state.dart，全部 reactive stream、§6.1 原则 3）：
/// - 待办：planTodosProvider（§5.5⑩ todos）+ todoDaoProvider 增改——勾选经
///   setDone（done_at 只前进合并 §6.5），当日流即时重发，仪表盘待办计数
///   （dashboardTodosProvider 直读 todos 表）同步刷新；
/// - 健身：planSessionsProvider（§5.5⑦ fitness_sessions）+「记录健身」推入
///   /plan/fitness 子路由（§4.3）；会话的 burn 行经 dashboard 流聚合进净热量
///   （§3.5「消耗进运动条与净热量」）；
/// - 存钱：§3.6 存钱目标 P1，占位卡。
///
/// 布局纪律与仪表盘一致（§3.2 卡片墙：surfaceCard 卡容器 + 语义 token，
/// §8.2 组件层禁裸色值）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../data/fitness_service.dart';
import '../dashboard/dashboard_state.dart';
import 'plan_state.dart';

/// 待办输入框测试锚点。
const Key planTodoInputKey = ValueKey('plan_todo_input');

/// 待办添加按钮测试锚点。
const Key planTodoAddKey = ValueKey('plan_todo_add');

/// 「记录健身」按钮测试锚点。
const Key planFitnessAddKey = ValueKey('plan_fitness_add');

/// 计划 Tab。
class PlanPage extends ConsumerWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final date = formatCalendarDay(selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text('计划')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _PlanTodoCard(date: date),
            const SizedBox(height: 12),
            _PlanFitnessCard(date: date),
            const SizedBox(height: 12),
            const _PlanSavingsCard(),
          ],
        ),
      ),
    );
  }
}

/// 计划卡容器（与仪表盘 _DashboardCard 同形：surfaceCard + r16，§3.2/§8.2）。
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.slimca.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// 卡头：标题 + 动作位。
class _PlanCardHeader extends StatelessWidget {
  const _PlanCardHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(title, style: textTheme.titleMedium),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ── 待办卡（§3.6 待办基础 P0、§5.5⑩）───────────────────────────────

/// 待办卡：当日待办清单 + 快速添加（未完成在前，TodoDao 排序口径）。
class _PlanTodoCard extends ConsumerStatefulWidget {
  const _PlanTodoCard({required this.date});

  /// 归属日（§3.2 一切围绕日期；随仪表盘选中日）。
  final String date;

  @override
  ConsumerState<_PlanTodoCard> createState() => _PlanTodoCardState();
}

class _PlanTodoCardState extends ConsumerState<_PlanTodoCard> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _addTodo() async {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    _inputController.clear();
    // §5.5⑩ create：date 归属当日（date 列非收集箱语义）。
    await ref
        .read(todoDaoProvider)
        .create(title: title, date: widget.date);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final asyncTodos = ref.watch(planTodosProvider(widget.date));
    final todos = asyncTodos.value ?? const <db.Todo>[];
    final done = todos.where((t) => t.doneAt != null).length;

    return _PlanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(
            title: '待办',
            trailing: Text(
              '${todos.isEmpty ? 0 : done}/${todos.length}',
              style: textTheme.labelMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (todos.isEmpty)
            Text(
              '今日暂无待办，添加一条（§3.6 待办基础）',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          else
            for (final todo in todos)
              _TodoRow(
                key: ValueKey('plan_todo_${todo.id}'),
                todo: todo,
                onToggle: (done) => ref
                    .read(todoDaoProvider)
                    .setDone(todo.id, done: done),
              ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: planTodoInputKey,
                  controller: _inputController,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addTodo(),
                  style: textTheme.bodyMedium,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '添加待办，如 晨跑 30 分钟',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                key: planTodoAddKey,
                tooltip: '添加待办',
                onPressed: _addTodo,
                icon: Icon(Icons.add_circle_outline, color: tokens.primary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单条待办行：勾选 + 标题（完成划线，§3.6 勾选完成）。
class _TodoRow extends StatelessWidget {
  const _TodoRow({super.key, required this.todo, required this.onToggle});

  final db.Todo todo;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final done = todo.doneAt != null;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onToggle(!done),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: done,
                onChanged: (v) => onToggle(v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                todo.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: done ? tokens.onSurfaceMuted : tokens.onSurface,
                  decoration:
                      done ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 健身卡（§3.5 健身记录与热量收支、§5.5⑦）────────────────────────

/// 健身卡：当日会话列表 +「记录健身」入口（/plan/fitness，§4.3）。
class _PlanFitnessCard extends ConsumerWidget {
  const _PlanFitnessCard({required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final sessions =
        ref.watch(planSessionsProvider(date)).value ?? const <db.FitnessSession>[];

    return _PlanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(
            title: '健身',
            trailing: TextButton(
              key: planFitnessAddKey,
              onPressed: () => context.push('/plan/fitness'),
              child: Text(
                '记录健身',
                style: TextStyle(fontSize: 14, color: tokens.primary),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (sessions.isEmpty)
            Text(
              '今日暂无健身记录。手动记一笔，消耗计入运动条与净热量'
              '（MET 估算 ±20%，§3.5）',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          else
            for (final session in sessions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 18,
                      color: tokens.kcalOut,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _sessionTitle(session),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      '消耗 ${session.kcalBurn} kcal',
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.kcalOut,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  /// 会话标题：备注优先，缺省「类型 + 分钟」（与 FitnessService 写路径同口径）。
  String _sessionTitle(db.FitnessSession session) {
    final note = session.note;
    if (note != null && note.trim().isNotEmpty) return note.trim();
    final label = kFitnessTypeLabels[session.type] ?? '健身';
    return '$label ${session.durationS ~/ 60} 分钟';
  }
}

// ── 存钱卡（P1 占位，§3.6）─────────────────────────────────────────

/// 存钱目标卡（§3.6 存钱目标 P1：目标+自动转入+进度环；W5-6 占位）。
class _PlanSavingsCard extends StatelessWidget {
  const _PlanSavingsCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return _PlanCard(
      child: Row(
        children: [
          Icon(Icons.savings_outlined, color: tokens.moneyOut),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '存钱目标 P1 上线后接入（目标+自动转入+进度环，§3.6）',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
