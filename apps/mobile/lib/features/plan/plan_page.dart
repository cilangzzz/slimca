/// 计划 Tab 真页（§4.2「待办 / 健身 / 存钱三卡」、§11.2 W13 主线
/// 「待办完整版（RRULE+提醒）+ 存钱目标」）。
///
/// 数据源（plan_state.dart，全部 reactive stream、§6.1 原则 3）：
/// - 待办完整版：planTodosProvider（§5.5⑩ todos）+ todoDaoProvider 增改——
///   勾选经 setDone（done_at 只前进合并 §6.5）；W13 起新增支持重复
///   （repeat_rule=RRULE RFC5545，锚点由 TodoDao 缺省回填计划日）与提醒
///   （remind_at，本地通知调度经 ReminderSyncCoordinator 按展开实例落），
///   重复建档记 todo_recurrence_created 漏斗（§11.2 W13 任务 4）；
/// - 健身：planSessionsProvider（§5.5⑦ fitness_sessions）+「记录健身」推入
///   /plan/fitness 子路由（§4.3）；会话的 burn 行经 dashboard 流聚合进净热量
///   （§3.5「消耗进运动条与净热量」）；
/// - 存钱目标（§3.6 P1 留存钩子，§11.2 W13）：planSavingsGoalsProvider
///   （打卡中目标 + Σ贡献进度）直驱——新建目标/投币打卡经
///   [SavingsService]（写路径同事务联动投影 + savings_goal_created/coin_in
///   漏斗）。
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
import '../../common/format.dart';
import '../../data/fitness_service.dart';
import '../../data/savings_service.dart';
import '../../telemetry/w13_funnel_events.dart';
import '../dashboard/dashboard_state.dart';
import 'plan_state.dart';

/// 待办输入框测试锚点。
const Key planTodoInputKey = ValueKey('plan_todo_input');

/// 待办添加按钮测试锚点。
const Key planTodoAddKey = ValueKey('plan_todo_add');

/// 「记录健身」按钮测试锚点。
const Key planFitnessAddKey = ValueKey('plan_fitness_add');

/// 「新建目标」按钮测试锚点。
const Key planSavingsCreateKey = ValueKey('plan_savings_create');

/// 目标建档表单锚点（名称/金额/提交）。
const Key planGoalNameFieldKey = ValueKey('plan_goal_name_field');
const Key planGoalTargetFieldKey = ValueKey('plan_goal_target_field');
const Key planGoalSubmitKey = ValueKey('plan_goal_submit');

/// 投币打卡按钮测试锚点（`plan_savings_coin_<goalId>`）。
Key planSavingsCoinKey(String goalId) =>
    ValueKey('plan_savings_coin_$goalId');

/// 投币表单锚点（金额预填/提交）。
const Key planCoinAmountFieldKey = ValueKey('plan_coin_amount_field');
const Key planCoinSubmitKey = ValueKey('plan_coin_submit');

/// 重复档位（§3.6 待办完整版 W13 基础档：不重复/每天/每周/每月）。
const Map<String, String> _repeatRuleByWire = <String, String>{
  'none': '',
  'daily': 'FREQ=DAILY',
  'weekly': 'FREQ=WEEKLY',
  'monthly': 'FREQ=MONTHLY',
};

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

// ── 待办卡（§3.6 待办完整版 W13：RRULE+提醒、§5.5⑩）────────────────────

/// 待办卡：当日待办清单 + 快速添加（未完成在前，TodoDao 排序口径）+
/// 重复/提醒选项行（W13 完整版基础档）。
class _PlanTodoCard extends ConsumerStatefulWidget {
  const _PlanTodoCard({required this.date});

  /// 归属日（§3.2 一切围绕日期；随仪表盘选中日）。
  final String date;

  @override
  ConsumerState<_PlanTodoCard> createState() => _PlanTodoCardState();
}

class _PlanTodoCardState extends ConsumerState<_PlanTodoCard> {
  final _inputController = TextEditingController();

  /// 重复档位 wire（none=不重复；§3.6 W13 基础档）。
  String _repeat = 'none';

  /// 提醒时刻（当日 HH:mm；null=不提醒）。
  TimeOfDay? _remindTime;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pickRemindTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _remindTime ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: '选择提醒时刻',
    );
    if (picked != null) {
      setState(() => _remindTime = picked);
    }
  }

  Future<void> _addTodo() async {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    _inputController.clear();
    // §5.5⑩ create：date 归属当日（date 列非收集箱语义）；W13 重复/提醒：
    // - repeat_rule=RRULE 文本（锚点由 TodoDao 缺省回填计划日=DTSTART）；
    // - remind_at=归属日所选时刻的 UTC ms（本地通知调度由
    //   ReminderSyncCoordinator 按展开实例落，§11.2 W13 任务 3）。
    final repeatRule = _repeatRuleByWire[_repeat];
    final hasRepeat = repeatRule != null && repeatRule.isNotEmpty;
    int? remindAt;
    if (_remindTime != null) {
      final selected = DateTime.parse(widget.date); // 本地 00:00（§5.1）
      remindAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _remindTime!.hour,
        _remindTime!.minute,
      ).millisecondsSinceEpoch;
    }
    final dao = ref.read(todoDaoProvider);
    await dao.create(
      title: title,
      date: widget.date,
      repeatRule: hasRepeat ? repeatRule : null,
      remindAt: remindAt,
    );
    // W13 漏斗（§11.2 任务 4）：重复待办建档即记（props 只带频率枚举，
    // §3.9 内容禁入）。
    if (hasRepeat) {
      final freq = repeatRule
          .split(';')
          .firstWhere((p) => p.startsWith('FREQ='), orElse: () => 'FREQ=?')
          .substring(5)
          .toLowerCase();
      await ref
          .read(telemetryServiceProvider)
          .funnel(
            W13TelemetryFunnel.todoRecurrenceCreated,
            props: <String, Object?>{'freq': freq},
          );
    }
    // 提醒权限运行时请求（Android 13+ POST_NOTIFICATIONS，§11.2 任务 3）：
    // 用户显式设置提醒时发起，权限被拒不阻塞（调度照常落、系统不展示）。
    if (remindAt != null) {
      await ref.read(reminderSchedulerProvider).ensurePermission();
    }
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
              '今日暂无待办，添加一条（§3.6 待办完整版：支持重复与提醒）',
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
          // W13 重复/提醒选项行（§3.6 待办完整版基础档）。
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'none', label: Text('不重复')),
                    ButtonSegment(value: 'daily', label: Text('每天')),
                    ButtonSegment(value: 'weekly', label: Text('每周')),
                    ButtonSegment(value: 'monthly', label: Text('每月')),
                  ],
                  selected: {_repeat},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onSelectionChanged: (selection) =>
                      setState(() => _repeat = selection.first),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('plan_todo_remind_toggle'),
                borderRadius: BorderRadius.circular(12),
                onTap: _pickRemindTime,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.alarm_outlined,
                        size: 18,
                        color: _remindTime != null
                            ? tokens.primary
                            : tokens.onSurfaceMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _remindTime == null
                            ? '提醒'
                            : '${_remindTime!.hour.toString().padLeft(2, '0')}:'
                                '${_remindTime!.minute.toString().padLeft(2, '0')}',
                        style: textTheme.labelMedium?.copyWith(
                          color: _remindTime != null
                              ? tokens.primary
                              : tokens.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

/// 单条待办行：勾选 + 标题（完成划线）+ 重复/提醒徽标（W13 完整版）。
class _TodoRow extends StatelessWidget {
  const _TodoRow({super.key, required this.todo, required this.onToggle});

  final db.Todo todo;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final done = todo.doneAt != null;
    final hasRepeat =
        todo.repeatRule != null && todo.repeatRule!.trim().isNotEmpty;
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
            // W13 徽标：重复（RRULE）与提醒（remind_at）一眼可辨（§3.6）。
            if (hasRepeat)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.repeat, size: 16, color: tokens.primary),
              ),
            if (todo.remindAt != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.alarm, size: 16, color: tokens.primary),
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

// ── 存钱卡（§3.6 存钱目标 P1 留存钩子、§5.5⑪⑫、§11.2 W13）────────────

/// 存钱目标卡（W13 真数据）：打卡中目标 + Σ贡献进度 +「新建目标/投币打卡」。
class _PlanSavingsCard extends ConsumerWidget {
  const _PlanSavingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final goals = ref.watch(planSavingsGoalsProvider).value ??
        const <PlanSavingsGoalView>[];

    return _PlanCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanCardHeader(
            title: '存钱目标',
            trailing: TextButton(
              key: planSavingsCreateKey,
              onPressed: () => _showGoalSheet(context),
              child: Text(
                '新建目标',
                style: TextStyle(fontSize: 14, color: tokens.primary),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (goals.isEmpty)
            Text(
              '设定第一个存钱目标，投币打卡攒下来'
              '（§3.6 存钱目标：365 法/52 周法/自定义，进度=贡献求和）',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          else
            for (final view in goals) ...[
              _SavingsGoalRow(
                key: ValueKey('plan_goal_${view.goal.id}'),
                view: view,
                onCoinIn: () => _showCoinSheet(context, view),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }

  /// 新建目标表单（§3.6 目标+金额+存钱法）。
  Future<void> _showGoalSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SavingsGoalSheet(),
    );
  }

  /// 投币打卡表单（§3.6 投币式打卡：当日贡献 append-only 追加）。
  Future<void> _showCoinSheet(
    BuildContext context,
    PlanSavingsGoalView view,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CoinInSheet(view: view),
    );
  }
}

/// 单个目标行：进度（金额 + 百分比 + 进度条）+ 投币入口。
class _SavingsGoalRow extends StatelessWidget {
  const _SavingsGoalRow({
    super.key,
    required this.view,
    required this.onCoinIn,
  });

  final PlanSavingsGoalView view;
  final VoidCallback onCoinIn;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final percent = (view.progress * 100).round();
    return Row(
      children: [
        Icon(Icons.savings_outlined, size: 20, color: tokens.moneyOut),
        const SizedBox(width: 10),
        Expanded(
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
                  color: tokens.onSurfaceMuted,
                ),
              ),
              const SizedBox(height: 6),
              // 进度条（§3.6 进度=贡献行求和；投币后 reactive 流即时推进）。
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: view.progress),
                  duration: MotionConfig.of(context).durM,
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    backgroundColor: tokens.outline,
                    valueColor: AlwaysStoppedAnimation<Color>(tokens.moneyOut),
                  ),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: planSavingsCoinKey(view.goal.id),
          tooltip: '投币打卡',
          onPressed: onCoinIn,
          icon: Icon(Icons.paid_outlined, color: tokens.moneyOut),
        ),
      ],
    );
  }
}

/// 新建存钱目标表单（§3.6：名称/目标金额/存钱法；custom 附每日建议额）。
class _SavingsGoalSheet extends ConsumerStatefulWidget {
  const _SavingsGoalSheet();

  @override
  ConsumerState<_SavingsGoalSheet> createState() => _SavingsGoalSheetState();
}

class _SavingsGoalSheetState extends ConsumerState<_SavingsGoalSheet> {
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  final _dailyController = TextEditingController();

  /// 存钱法（§5.5⑪ method 枚举；缺省自定义）。
  String _method = db.kSavingsMethodCustom;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _dailyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final target = parseYuanToFen(_targetController.text.trim());
    if (name.isEmpty || target == null) {
      setState(() => _errorText = '目标名与目标金额（元）必填');
      return;
    }
    if (_method == db.kSavingsMethodCustom) {
      final daily = parseYuanToFen(_dailyController.text.trim());
      if (daily == null) {
        setState(() => _errorText = '自定义存钱法需填写每日金额');
        return;
      }
      await ref.read(savingsServiceProvider).createGoal(
            name: name,
            targetMinor: target,
            method: _method,
            dailyAmountMinor: daily,
          );
    } else {
      await ref.read(savingsServiceProvider).createGoal(
            name: name,
            targetMinor: target,
            method: _method,
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新建存钱目标（§3.6）', style: textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              key: planGoalNameFieldKey,
              controller: _nameController,
              style: textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: '目标名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              key: planGoalTargetFieldKey,
              controller: _targetController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: '目标金额（元）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: db.kSavingsMethodCustom,
                  label: Text('自定义'),
                ),
                ButtonSegment(
                  value: db.kSavingsMethodDaily365,
                  label: Text('365 法'),
                ),
                ButtonSegment(
                  value: db.kSavingsMethodWeek52,
                  label: Text('52 周法'),
                ),
              ],
              selected: {_method},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _method = selection.first),
            ),
            if (_method == db.kSavingsMethodCustom) ...[
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('plan_goal_daily_field'),
                controller: _dailyController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: textTheme.bodyMedium,
                decoration: const InputDecoration(
                  labelText: '每日存入（元，投币建议额）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_method == db.kSavingsMethodDaily365 ||
                _method == db.kSavingsMethodWeek52) ...[
              const SizedBox(height: 6),
              Text(
                _method == db.kSavingsMethodDaily365
                    ? '365 存钱法：第 N 天存 N 元（自起始日计格）'
                    : '52 周存钱法：第 N 周存 N 元（自起始日计格）',
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: textTheme.bodySmall?.copyWith(color: tokens.danger),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: planGoalSubmitKey,
              onPressed: _submit,
              child: const Text('创建目标'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 投币打卡表单（§3.6 投币式打卡：当日贡献追加，append-only 幂等）。
class _CoinInSheet extends ConsumerStatefulWidget {
  const _CoinInSheet({required this.view});

  final PlanSavingsGoalView view;

  @override
  ConsumerState<_CoinInSheet> createState() => _CoinInSheetState();
}

class _CoinInSheetState extends ConsumerState<_CoinInSheet> {
  late final TextEditingController _amountController =
      TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // 建议额预填（§3.6 365/52 周法按第 N 格阶梯；custom 取每日额）。
    final today = formatCalendarDay(DateTime.now());
    final suggested = ref
        .read(savingsServiceProvider)
        .suggestedAmountMinor(widget.view.goal, today);
    _amountController.text = minorToYuanText(suggested);
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parseYuanToFen(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorText = '存入金额（元）必须大于 0');
      return;
    }
    final SavingsService service = ref.read(savingsServiceProvider);
    final (_, inserted) = await service.coinIn(
      widget.view.goal,
      amountMinor: amount,
    );
    if (!mounted) return;
    // 幂等命中（同日同来源重复投币）：友好反馈而非报错（§5.5⑫ 幂等口径）。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(inserted ? '已投币入账' : '今日已投过币啦（幂等保留首次）'),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final today = formatCalendarDay(DateTime.now());
    final slot = ref
        .read(savingsServiceProvider)
        .slotForDay(widget.view.goal, today);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '投币打卡 · ${widget.view.goal.name}（§3.6）',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              slot == null
                  ? '打卡日 $today · 进度 ${yuanFromMinor(widget.view.contributedMinor)}'
                      ' / ${yuanFromMinor(widget.view.goal.targetMinor)}'
                  : '今日第 $slot 格 · '
                      '${widget.view.goal.method == db.kSavingsMethodDaily365 ? '天' : '周'}'
                      ' · 进度 ${yuanFromMinor(widget.view.contributedMinor)}'
                      ' / ${yuanFromMinor(widget.view.goal.targetMinor)}',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: planCoinAmountFieldKey,
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: textTheme.bodyMedium,
              decoration: const InputDecoration(
                labelText: '本次存入（元）',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: textTheme.bodySmall?.copyWith(color: tokens.danger),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: planCoinSubmitKey,
              onPressed: _submit,
              child: const Text('投币'),
            ),
          ],
        ),
      ),
    );
  }
}
