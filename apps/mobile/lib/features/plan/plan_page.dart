/// 计划 Tab 真页（计划域 IA 重设计定稿：今日为纲——默认页只回答
/// 「今天要做/要练/要存什么」，管理面下沉域主页）。
///
/// 版面（三层 IA 的 L0，每个目的地全局恰一条到达路径）：
/// 1. 今日待办卡：当日实例行（勾选就地完成，重复待办按 anchor 查询时展开、
///    不预生成行）+ 快速添加（轻层：只产当日无重复待办；重复/提醒走编辑
///    抽屉重层）+ 收集箱尾行（唯一收集箱入口 → /plan/todos）；
/// 2. 今日健身卡（四态互斥，一卡一叙事）：训练中横幅 > 今日排期行（全 App
///    唯一开练入口，壳层引擎）> 已练摘要 > 空态；卡尾「健身计划」（模板
///    管理 → /plan/plans）与「记录健身」（包版健身记录页）；
/// 3. 今日存钱卡：进行中目标行（行内一键投币 = SavingsCheckInButton，幂等
///    置灰；行点进目标详情）+「存钱目标」尾行（列表/新建 → /plan/savings）。
///
/// 数据源：读侧全部 reactive stream——待办实例/收集箱/存钱目标视图走
/// feature_plan providers（planGatewayProvider，§10.4 装配）；当日会话/
/// 排期走 plan_state（§3.2 一切围绕日期，随仪表盘选中日）；写路径纪律：
/// 待办轻层（快速添加/勾选）走壳层 TodoDao（outbox 同事务已验证），重层
/// （编辑抽屉/投币/会话）走 PlanGateway 唯一写路径，W13 留存钩子漏斗在
/// 网关侧记（§3.9）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:feature_plan/feature_plan.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../common/format.dart';
import '../dashboard/dashboard_state.dart';
import '../workout/workout_session_controller.dart';
import 'plan_state.dart';

/// 待办输入框测试锚点。
const Key planTodoInputKey = ValueKey('plan_todo_input');

/// 待办添加按钮测试锚点。
const Key planTodoAddKey = ValueKey('plan_todo_add');

/// 待办「详细」按钮测试锚点（轻/重两层：进编辑抽屉设重复/提醒）。
const Key planTodoAdvancedKey = ValueKey('plan_todo_advanced');

/// 待办勾选框测试锚点（`plan_todo_check_$todoId`）。
Key planTodoCheckKey(String todoId) => ValueKey('plan_todo_check_$todoId');

/// 收集箱尾行测试锚点。
const Key planInboxTileKey = ValueKey('plan_inbox_tile');

/// 「记录健身」按钮测试锚点。
const Key planFitnessAddKey = ValueKey('plan_fitness_add');

/// 健身计划卡测试锚点（排期/开练链路 e2e 锚）。
const Key planWorkoutCardKey = ValueKey('plan_workout_card');

/// 「开始训练」按钮测试锚点（`plan_workout_start_<planId>`）。
Key planWorkoutStartKey(String planId) =>
    ValueKey('plan_workout_start_$planId');

/// 「健身计划」入口按钮测试锚点（/plan/plans → feature_plan FitnessPlanPage）。
const Key planWorkoutTemplatesKey = ValueKey('plan_workout_templates');

/// 「继续训练」按钮测试锚点（已有进行中训练）。
const Key planWorkoutResumeKey = ValueKey('plan_workout_resume');

/// 存钱目标尾行测试锚点（/plan/savings → feature_plan SavingsPage）。
const Key planSavingsManageKey = ValueKey('plan_savings_manage');

/// 存钱目标行测试锚点（`plan_savings_goal_<goalId>`；行点进详情页）。
Key planSavingsGoalRowKey(String goalId) =>
    ValueKey('plan_savings_goal_$goalId');

/// 计划 Tab。
class PlanPage extends ConsumerWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final date = formatCalendarDay(selectedDate);
    final spacing = context.spacing;
    final sizes = context.sizes;
    const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('计划'),
            Text(
              '${calendarDayLabel(date)} · 周${weekdayLabels[selectedDate.weekday - 1]}'
              '（改日期回「今天」Tab）',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: context.slimca.onSurfaceMuted,
                  ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          // 底部留白（底栏重设计拍板）：清中央花瓣按钮凸出栏体（cradle 间隙
          // 约 34）+ 呼吸——space600+rowSingleLine+space200 组合表达。
          padding: EdgeInsets.fromLTRB(
            spacing.space200,
            spacing.space100,
            spacing.space200,
            spacing.space600 + sizes.rowSingleLine + spacing.space200,
          ),
          children: [
            _TodoCard(date: date),
            const SizedBox(height: 12),
            _FitnessCard(date: date),
            const SizedBox(height: 12),
            const _SavingsCard(),
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

/// 卡尾域入口行（menu-tile 形态：图标 + 标题 + 副标题 + chevron；域主页的
/// 唯一入口，单一入口纪律）。
class _DomainTile extends StatelessWidget {
  const _DomainTile({
    required super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$title · $subtitle',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurface,
                ),
              ),
            ),
            Icon(Icons.chevron_right,
                size: 20, color: tokens.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}

// ── 今日待办卡（§3.6 待办：勾选/快加轻层 + 编辑抽屉重层）────────────────

/// 今日待办卡：当日实例行（重复待办查询时展开，不预生成行）+ 快速添加 +
/// 收集箱尾行。
class _TodoCard extends ConsumerWidget {
  const _TodoCard({required this.date});

  /// 归属日（§3.2 一切围绕日期；随仪表盘选中日）。
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final instances =
        ref.watch(fp.todoDayInstancesProvider(date)).value;
    final inboxCount =
        ref.watch(fp.inboxTodosProvider).value?.length ?? 0;
    final todos = instances ?? const <fp.TodoDayInstance>[];
    final done = todos.where((t) => t.done).length;

    return _PlanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(
            title: '今日待办',
            trailing: Text(
              '${todos.isEmpty ? 0 : done}/${todos.length}',
              style: textTheme.labelMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (instances == null)
            const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (todos.isEmpty)
            Text(
              '今天没有待办，添加一条',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          else
            for (final instance in todos)
              _TodoRow(
                key: ValueKey('plan_todo_${instance.todo.id}'),
                instance: instance,
              ),
          const SizedBox(height: 8),
          _QuickAddRow(date: date),
          const SizedBox(height: 4),
          _DomainTile(
            key: planInboxTileKey,
            icon: Icons.inbox_outlined,
            iconColor: tokens.primary,
            title: '收集箱',
            subtitle: inboxCount > 0 ? '$inboxCount 条待整理' : '已清空',
            onTap: () => context.push('/plan/todos'),
          ),
        ],
      ),
    );
  }
}

/// 快速添加行（轻层）：只产当日无重复待办；「详细」进编辑抽屉重层
/// （重复 5 档/提醒/备注），两条创建路径按能力切分不重叠。
class _QuickAddRow extends ConsumerStatefulWidget {
  const _QuickAddRow({required this.date});

  final String date;

  @override
  ConsumerState<_QuickAddRow> createState() => _QuickAddRowState();
}

class _QuickAddRowState extends ConsumerState<_QuickAddRow> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    _inputController.clear();
    // 轻层创建（§5.5⑩）：date 归属当日；重复/提醒只能进编辑抽屉（重层），
    // 重复档位创建只剩编辑器一处（语义分叉消失）。
    await ref.read(todoDaoProvider).create(title: title, date: widget.date);
  }

  void _openEditor({db.Todo? todo}) {
    showSlimcaSpringSheet<void>(
      context: context,
      builder: (_) => fp.TodoEditorSheet(todo: todo, planDate: widget.date),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: planTodoInputKey,
            controller: _inputController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _add(),
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
          key: planTodoAdvancedKey,
          tooltip: '详细（重复/提醒）',
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.tune),
        ),
        IconButton(
          key: planTodoAddKey,
          tooltip: '添加待办',
          onPressed: _add,
          icon: Icon(Icons.add_circle_outline, color: tokens.primary),
        ),
      ],
    );
  }
}

/// 单条待办实例行：勾选（就地完成，done_at 只前进）+ 标题（完成划线）+
/// 重复/提醒徽标；点标题进编辑抽屉（编辑/删除/重复/提醒）。
class _TodoRow extends ConsumerWidget {
  const _TodoRow({super.key, required this.instance});

  final fp.TodoDayInstance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final todo = instance.todo;
    final done = instance.done;
    final hasRepeat = instance.recurring;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              key: planTodoCheckKey(todo.id),
              value: done,
              onChanged: (v) => ref
                  .read(fp.planGatewayProvider)
                  .setTodoDone(todo.id, done: v ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showSlimcaSpringSheet<void>(
                context: context,
                builder: (_) => fp.TodoEditorSheet(todo: todo),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        todo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: done
                              ? tokens.onSurfaceMuted
                              : tokens.onSurface,
                          decoration: done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                    // 徽标：重复（RRULE）与提醒（remind_at）一眼可辨（§3.6）。
                    if (hasRepeat)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.repeat,
                            size: 16, color: tokens.primary),
                      ),
                    if (todo.remindAt != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.alarm,
                            size: 16, color: tokens.primary),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 今日健身卡（四态互斥：训练中横幅 > 排期 > 已练 > 空态）────────────

/// 今日健身卡（一卡一叙事）：训练中横幅（壳层引擎全局态）→ 今日排期行
/// （唯一开练入口）→ 已练摘要（纯信息不可点）→ 空态。
class _FitnessCard extends ConsumerWidget {
  const _FitnessCard({required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final session = ref.watch(workoutSessionProvider);
    final schedule = ref.watch(planScheduleProvider(date)).value ??
        const <FitnessPlanScheduleView>[];
    final sessions = ref.watch(planSessionsProvider(date)).value ??
        const <db.FitnessSession>[];

    return _PlanCard(
      child: Column(
        key: planWorkoutCardKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(title: '今日健身'),
          const SizedBox(height: 8),
          if (session != null)
            _ActiveSessionBanner(session: session)
          else if (schedule.isNotEmpty)
            for (final view in schedule) ...[
              _ScheduleRow(
                key: ValueKey('plan_schedule_${view.plan.id}'),
                view: view,
                onStart: () => _start(context, ref, view),
              ),
              const SizedBox(height: 8),
            ]
          else if (sessions.isNotEmpty) ...[
            Text(
              '今日已练 ${sessions.length} 次',
              style: textTheme.bodyMedium?.copyWith(color: tokens.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              '消耗 ${sessions.fold<int>(0, (sum, s) => sum + s.kcalBurn)} kcal',
              style: textTheme.bodyMedium?.copyWith(color: tokens.kcalOut),
            ),
          ] else ...[
            Text(
              '今天没有健身安排',
              style: textTheme.bodyMedium?.copyWith(color: tokens.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              '去「健身计划」排个模板，或「记录健身」记一笔',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                key: planWorkoutTemplatesKey,
                onPressed: () => context.push('/plan/plans'),
                child: Text(
                  '健身计划',
                  style: TextStyle(fontSize: 14, color: tokens.primary),
                ),
              ),
              TextButton(
                key: planFitnessAddKey,
                onPressed: () => Navigator.of(context).push(
                  SlimcaSharedAxisPageRoute<void>(
                      builder: (_) => const fp.FitnessLogPage()),
                ),
                child: Text(
                  '记录健身',
                  style: TextStyle(fontSize: 14, color: tokens.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 开练（全 App 唯一开练入口）：壳层引擎置态（常亮+常驻通知+workout_started
  /// 漏斗）→ 推入训练页（/plan/workout，分支栈内 push）。
  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    FitnessPlanScheduleView view,
  ) async {
    await ref
        .read(workoutSessionProvider.notifier)
        .startFromPlan(view.plan, date: date);
    if (context.mounted) {
      await context.push('/plan/workout');
    }
  }
}

/// 训练中横幅：继续训练（状态不重建）；控制面（完成一组/跳过休息/结束并
/// 保存）唯一在训练页，横幅只导航（避免控制面重复）。
class _ActiveSessionBanner extends StatelessWidget {
  const _ActiveSessionBanner({required this.session});

  final WorkoutSessionState session;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    return Material(
      color: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.fitness_center, size: 18, color: tokens.kcalOut),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '训练进行中 · ${session.planName} · '
                '已完成 ${session.sets.length}/${session.totalSets} 组',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: tokens.onSurface),
              ),
            ),
            TextButton(
              key: planWorkoutResumeKey,
              onPressed: () => context.push('/plan/workout'),
              child: const Text('继续训练'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 排期行：计划名 + 模板摘要 + 开始训练。
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    super.key,
    required this.view,
    required this.onStart,
  });

  final FitnessPlanScheduleView view;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final exercises = view.exercises;
    final totalSets = exercises.fold(0, (sum, e) => sum + e.sets);
    final summary = exercises.isEmpty
        ? '模板待完善'
        : '${exercises.first.name} 等 ${exercises.length} 个动作 · 共 $totalSets 组';
    return Row(
      children: [
        Icon(Icons.fitness_center, size: 18, color: tokens.kcalOut),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                view.plan.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          key: planWorkoutStartKey(view.plan.id),
          onPressed: onStart,
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('开始训练'),
        ),
      ],
    );
  }
}

// ── 今日存钱卡（行内一键投币 + 行点详情 + 尾行唯一列表入口）────────────

/// 今日存钱卡：进行中目标行（一键投币 = 打卡动效落点）+「存钱目标」尾行
/// （列表/新建唯一入口）。空态=尾行副标题引导建档。
class _SavingsCard extends ConsumerWidget {
  const _SavingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final views = ref.watch(fp.savingsGoalsProvider).value;
    final goals = views ?? const <fp.SavingsGoalView>[];

    return _PlanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(title: '存钱目标'),
          const SizedBox(height: 8),
          if (views == null)
            const SizedBox(
              height: 40,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final view in goals)
              _SavingsGoalRow(
                key: planSavingsGoalRowKey(view.goal.id),
                view: view,
              ),
          _DomainTile(
            key: planSavingsManageKey,
            icon: Icons.savings_outlined,
            iconColor: tokens.moneyIn,
            title: '存钱目标',
            subtitle: goals.isEmpty
                ? '设定第一个存钱目标，投币打卡攒下来'
                : '${goals.length} 个进行中',
            onTap: () => context.push('/plan/savings'),
          ),
        ],
      ),
    );
  }
}

/// 单个目标行：名称 + 金额进度（moneyIn 语义色）+ 一键投币；行点进目标
/// 详情页（进度环/贡献历史/标记达成/删除——壳层此前完全不可达的能力）。
class _SavingsGoalRow extends ConsumerWidget {
  const _SavingsGoalRow({super.key, required this.view});

  final fp.SavingsGoalView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final percent = (view.progress * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                SlimcaSharedAxisPageRoute<void>(
                  builder: (_) =>
                      fp.SavingsGoalDetailPage(goalId: view.goal.id),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.goal.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${yuanFromMinor(view.contributedMinor)} / '
                      '${yuanFromMinor(view.goal.targetMinor)}（$percent%）',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.moneyIn,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 进度条（进度=贡献行求和；投币后 reactive 流即时推进）。
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: view.progress),
                        duration: MotionConfig.of(context).durM,
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) =>
                            LinearProgressIndicator(
                          value: value,
                          minHeight: 6,
                          backgroundColor: tokens.outline,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              tokens.moneyIn),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 一键投币（留存钩子 0 跳打卡）：格子金额自动推算、今日已投置灰
          // 幂等防重复（DAO 幂等键兜底）。
          fp.SavingsCheckInButton(goal: view.goal),
        ],
      ),
    );
  }
}
