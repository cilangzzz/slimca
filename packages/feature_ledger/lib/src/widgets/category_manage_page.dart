/// 分类管理页（§11.1 W5-6「分类管理」；§11.2 W15 预算体系）：
/// - 每日目标：每日总支出/总热量/分类级目标，落库 budgets(period=daily)，
///   §5.4⑥、§3.4；
/// - 月度目标：月度总支出（周期起点/结转开关），落库 budgets(period=
///   monthly)，§5.4⑥ P1/W15；
/// - 分类增删改：categories 表逻辑引用（不建外键，§5.4⑤/§6.2），
///   内置分类不可删（§5.4⑤ is_preset），自定义分类软删墓碑（§5.1）。
///
/// 写入经 [LedgerAdminRepository]（W15 起预算路径收口 core_db BudgetsDao：
/// outbox 同事务入队 + budget_snapshot v2 联动，§6.2/§5.6⑬）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ledger_admin_repository.dart';
import '../ledger_colors.dart';
import '../ledger_format.dart';
import '../ledger_models.dart';

/// 分类管理页测试锚点（页面同屏存在大量同名文本，统一按 key 定位）。
const Key ledgerSpendGoalSetKey = ValueKey<String>('ledger_spend_goal_set');

/// 每日热量目标「设置/修改」按钮锚点。
const Key ledgerKcalGoalSetKey = ValueKey<String>('ledger_kcal_goal_set');

/// 月度支出目标「设置/修改」按钮锚点（W15 预算体系，§5.4⑥ monthly）。
const Key ledgerMonthGoalSetKey = ValueKey<String>('ledger_month_goal_set');

/// 月度目标输入框锚点。
const Key ledgerMonthGoalInputKey = ValueKey<String>('ledger_month_goal_input');

/// 月度目标结转开关锚点。
const Key ledgerMonthGoalCarryKey = ValueKey<String>('ledger_month_goal_carry');

/// 月度目标保存按钮锚点。
const Key ledgerMonthGoalSaveKey = ValueKey<String>('ledger_month_goal_save');

/// 目标输入框锚点（金额/热量对话框共用）。
const Key ledgerGoalInputKey = ValueKey<String>('ledger_goal_input');

/// 目标对话框保存按钮锚点。
const Key ledgerGoalSaveKey = ValueKey<String>('ledger_goal_save');

/// 「新建分类」按钮锚点。
const Key ledgerCategoryCreateKey = ValueKey<String>('ledger_category_create');

/// 分类对话框名称输入框锚点（新建/编辑共用）。
const Key ledgerCategoryNameFieldKey =
    ValueKey<String>('ledger_category_name_field');

/// 分类对话框保存按钮锚点（新建/编辑共用）。
const Key ledgerCategoryDialogSaveKey =
    ValueKey<String>('ledger_category_dialog_save');

/// 删除确认对话框「删除」按钮锚点。
const Key ledgerCategoryConfirmDeleteKey =
    ValueKey<String>('ledger_category_confirm_delete');

/// 分类管理页（构造注入仓库，§10.4）。
class CategoryManagePage extends StatelessWidget {
  const CategoryManagePage({super.key, required this.repository});

  final LedgerAdminRepository repository;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        backgroundColor: tokens.surface,
        title: const Text('分类管理'),
      ),
      // 一条 budgets 流同时驱动目标卡与分类卡的"日目标"徽标（§5.4⑥）。
      body: StreamBuilder<List<LedgerDailyBudget>>(
        stream: repository.watchDailyBudgets(),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<LedgerDailyBudget>> snapshot,
        ) {
          final List<LedgerDailyBudget> budgets =
              snapshot.data ?? const <LedgerDailyBudget>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: <Widget>[
              SlimcaStaggerItem(
                index: 0,
                child: _DailyGoalCard(repository: repository, budgets: budgets),
              ),
              const SizedBox(height: 12),
              SlimcaStaggerItem(
                index: 1,
                child: _CategoryListCard(
                  repository: repository,
                  budgets: budgets,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 每日目标卡（§3.4/§5.4⑥）：总支出、总热量 + 分类级目标清单；
/// W15 增月度总支出目标（period=monthly，周期起点/结转）。
class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({required this.repository, required this.budgets});

  final LedgerAdminRepository repository;
  final List<LedgerDailyBudget> budgets;

  void _showSpendGoalDialog(
    BuildContext context,
    LedgerDailyBudget? current,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _GoalDialog(
        title: current == null ? '设置每日支出目标' : '修改每日支出目标',
        hint: '如 50（元）',
        initialText:
            current == null ? null : LedgerFormat.yuanInputText(current.amount),
        isKcal: false,
        onSave: (int minor) => repository.setDailySpendGoal(minor),
        onClear: current == null ? null : repository.clearDailySpendGoal,
      ),
    );
  }

  void _showKcalGoalDialog(
    BuildContext context,
    LedgerDailyBudget? current,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _GoalDialog(
        title: current == null ? '设置每日热量目标' : '修改每日热量目标',
        hint: '如 2000（kcal）',
        initialText: current == null ? null : '${current.amount}',
        isKcal: true,
        onSave: (int kcal) => repository.setDailyKcalGoal(kcal),
        onClear: current == null ? null : repository.clearDailyKcalGoal,
      ),
    );
  }

  /// 月度支出目标对话框（W15，§5.4⑥ monthly：金额 + 周期起点 + 结转开关）。
  void _showMonthlyGoalDialog(
    BuildContext context,
    LedgerDailyBudget? current,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => _MonthlyGoalDialog(
        title: current == null ? '设置月度支出目标' : '修改月度支出目标',
        initialText:
            current == null ? null : LedgerFormat.yuanInputText(current.amount),
        initialStart: current?.dayOfMonthStart ?? 1,
        initialCarryOver: current?.carryOver ?? false,
        onSave: (int minor, int dayOfMonthStart, bool carryOver) =>
            repository.setMonthlySpendGoal(
          minor,
          dayOfMonthStart: dayOfMonthStart,
          carryOver: carryOver,
        ),
        onClear: current == null ? null : repository.clearMonthlySpendGoal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    LedgerDailyBudget? spendGoal;
    LedgerDailyBudget? kcalGoal;
    LedgerDailyBudget? monthGoal;
    final List<LedgerDailyBudget> categoryGoals = <LedgerDailyBudget>[];
    for (final LedgerDailyBudget budget in budgets) {
      if (budget.isMonthly) {
        monthGoal ??= budget;
        continue;
      }
      if (budget.isCategoryGoal) {
        categoryGoals.add(budget);
      } else if (budget.isKcalGoal) {
        kcalGoal ??= budget;
      } else {
        spendGoal ??= budget;
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '每日目标',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            '按日设定总支出与总热量（§3.4）；落库 budgets(period=daily)（§5.4⑥）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          const SizedBox(height: 8),
          _GoalTile(
            buttonKey: ledgerSpendGoalSetKey,
            label: '每日支出目标',
            value: spendGoal == null
                ? '未设置'
                : LedgerFormat.moneyMinor(spendGoal.amount),
            isSet: spendGoal != null,
            onSet: () => _showSpendGoalDialog(context, spendGoal),
          ),
          _GoalTile(
            buttonKey: ledgerKcalGoalSetKey,
            label: '每日热量目标',
            value: kcalGoal == null
                ? '未设置'
                : LedgerFormat.kcal(kcalGoal.amount),
            isSet: kcalGoal != null,
            onSet: () => _showKcalGoalDialog(context, kcalGoal),
          ),
          for (final LedgerDailyBudget goal in categoryGoals)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '「${goal.categoryName ?? '已删分类'}」日目标',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.onSurfaceMuted,
                          ),
                    ),
                  ),
                  Text(
                    LedgerFormat.moneyMinor(goal.amount),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: '清除该分类日目标',
                    onPressed: () => repository
                        .clearCategoryDailyGoal(goal.categoryId!),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            '月度目标（§5.4⑥ monthly，W15）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          _GoalTile(
            buttonKey: ledgerMonthGoalSetKey,
            label: '月度支出目标',
            value: monthGoal == null
                ? '未设置'
                : '${LedgerFormat.moneyMinor(monthGoal.amount)}'
                    '（每月${monthGoal.dayOfMonthStart}日起'
                    '${monthGoal.carryOver ? ' · 结转' : ''}）',
            isSet: monthGoal != null,
            onSet: () => _showMonthlyGoalDialog(context, monthGoal),
          ),
        ],
      ),
    );
  }
}

/// 目标行：label + 当前值 + 设置/修改按钮。
class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.buttonKey,
    required this.label,
    required this.value,
    required this.isSet,
    required this.onSet,
  });

  final Key buttonKey;
  final String label;
  final String value;
  final bool isSet;
  final VoidCallback onSet;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurface,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isSet ? tokens.onSurface : tokens.onSurfaceMuted,
                  fontWeight: isSet ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
          const SizedBox(width: 4),
          TextButton(
            key: buttonKey,
            onPressed: onSet,
            child: Text(isSet ? '修改' : '设置'),
          ),
        ],
      ),
    );
  }
}

/// 目标输入对话框（金额=元两位小数 / 热量=kcal 整数；§5.1 口径在
/// LedgerFormat 解析层强制）。清除目标 = 软删墓碑（§5.1）。
class _GoalDialog extends StatefulWidget {
  const _GoalDialog({
    required this.title,
    required this.hint,
    required this.initialText,
    required this.isKcal,
    required this.onSave,
    this.onClear,
  });

  final String title;
  final String hint;
  final String? initialText;
  final bool isKcal;
  final Future<void> Function(int value) onSave;
  final Future<void> Function()? onClear;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final int? value = widget.isKcal
        ? LedgerFormat.parseKcal(_controller.text)
        : LedgerFormat.parseYuanToMinor(_controller.text);
    if (value == null) {
      setState(() {
        _errorText = widget.isKcal
            ? '请输入 kcal 整数（1-99999）'
            : '请输入金额（元，最多两位小数）';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    await widget.onSave(value);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _clear() async {
    final Future<void> Function()? onClear = widget.onClear;
    if (onClear == null) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await onClear();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: ledgerGoalInputKey,
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          hintText: widget.hint,
          errorText: _errorText,
        ),
      ),
      actions: <Widget>[
        if (widget.onClear != null)
          TextButton(
            onPressed: _saving ? null : _clear,
            child: const Text('清除目标'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: ledgerGoalSaveKey,
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 月度目标对话框（W15，§5.4⑥ monthly）：金额 + 周期起点（1..28）+
/// 结转开关；清除 = 软删墓碑（§5.1）。
class _MonthlyGoalDialog extends StatefulWidget {
  const _MonthlyGoalDialog({
    required this.title,
    required this.initialText,
    required this.initialStart,
    required this.initialCarryOver,
    required this.onSave,
    this.onClear,
  });

  final String title;
  final String? initialText;
  final int initialStart;
  final bool initialCarryOver;
  final Future<void> Function(int amountMinor, int dayOfMonthStart,
      bool carryOver) onSave;
  final Future<void> Function()? onClear;

  @override
  State<_MonthlyGoalDialog> createState() => _MonthlyGoalDialogState();
}

class _MonthlyGoalDialogState extends State<_MonthlyGoalDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  late int _start = widget.initialStart;
  late bool _carryOver = widget.initialCarryOver;
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final int? amountMinor = LedgerFormat.parseYuanToMinor(_controller.text);
    if (amountMinor == null) {
      setState(() {
        _errorText = '请输入金额（元，最多两位小数）';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    await widget.onSave(amountMinor, _start, _carryOver);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _clear() async {
    final Future<void> Function()? onClear = widget.onClear;
    if (onClear == null) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await onClear();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: ledgerMonthGoalInputKey,
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '如 2000（元/月）',
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '周期起点（每月几号，1-28，§5.4⑥）',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final int day in <int>[1, 10, 15, 20, 25, 28])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$day日'),
                      selected: _start == day,
                      onSelected: (bool selected) {
                        if (selected) {
                          setState(() {
                            _start = day;
                          });
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            key: ledgerMonthGoalCarryKey,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '结转未用完的额度',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.onSurface,
                  ),
            ),
            value: _carryOver,
            onChanged: (bool value) {
              setState(() {
                _carryOver = value;
              });
            },
          ),
        ],
      ),
      actions: <Widget>[
        if (widget.onClear != null)
          TextButton(
            onPressed: _saving ? null : _clear,
            child: const Text('清除目标'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: ledgerMonthGoalSaveKey,
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 分类清单卡（§5.4⑤）：支出/收入分组 + 新建入口；每行带日目标/
/// 编辑/删除操作。
class _CategoryListCard extends StatelessWidget {
  const _CategoryListCard({required this.repository, required this.budgets});

  final LedgerAdminRepository repository;
  final List<LedgerDailyBudget> budgets;

  /// 分类级日目标：categoryId → amount（kcal 口径目标不参与分类徽标，
  /// §5.4⑥ kcal 目标恒为总目标）。
  Map<String, int> get _categoryGoalMinorById {
    final Map<String, int> result = <String, int>{};
    for (final LedgerDailyBudget budget in budgets) {
      if (budget.isCategoryGoal && !budget.isKcalGoal) {
        result[budget.categoryId!] = budget.amount;
      }
    }
    return result;
  }

  void _showCreateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _CategoryEditDialog(repository: repository, original: null),
    );
  }

  void _showEditDialog(BuildContext context, LedgerCategoryOption option) {
    showDialog<void>(
      context: context,
      builder: (_) => _CategoryEditDialog(repository: repository, original: option),
    );
  }

  void _showGoalDialog(BuildContext context, LedgerCategoryOption option) {
    final int? goalMinor = _categoryGoalMinorById[option.id];
    showDialog<void>(
      context: context,
      builder: (_) => _GoalDialog(
        title: goalMinor == null
            ? '设置「${option.name}」每日目标'
            : '修改「${option.name}」每日目标',
        hint: '如 30（元）',
        initialText: goalMinor == null ? null : LedgerFormat.yuanInputText(goalMinor),
        isKcal: false,
        onSave: (int minor) => repository.setCategoryDailyGoal(
          categoryId: option.id,
          amountMinor: minor,
        ),
        onClear: goalMinor == null
            ? null
            : () => repository.clearCategoryDailyGoal(option.id),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, LedgerCategoryOption option) {
    final SlimcaTheme tokens = context.slimca;
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('删除分类「${option.name}」？'),
        content: Text(
          '删除为软删墓碑（§5.1），历史账单中的分类记录保留、新记录不再可选。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: ledgerCategoryConfirmDeleteKey,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              foregroundColor: tokens.onPrimary,
            ),
            onPressed: () {
              // 先关弹窗再执行幂等软删（删除不等待结果，§5.1 墓碑语义）。
              Navigator.of(dialogContext).pop();
              repository.softDeleteCategory(option.id);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final Map<String, int> goalMinorById = _categoryGoalMinorById;
    return StreamBuilder<List<LedgerCategoryOption>>(
      stream: repository.watchCategoryOptions(),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LedgerCategoryOption>> snapshot,
      ) {
        final List<LedgerCategoryOption> options =
            snapshot.data ?? const <LedgerCategoryOption>[];
        final List<LedgerCategoryOption> expense = options
            .where((LedgerCategoryOption o) => o.kind == kCategoryKindExpense)
            .toList();
        final List<LedgerCategoryOption> income = options
            .where((LedgerCategoryOption o) => o.kind == kCategoryKindIncome)
            .toList();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceCard,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '分类',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                '内置分类不可删（§5.4⑤）；自定义分类可改可删（软删墓碑，§5.1）',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
              ),
              const SizedBox(height: 8),
              _SectionLabel(text: '支出分类'),
              for (final LedgerCategoryOption option in expense)
                _CategoryTile(
                  option: option,
                  goalMinor: goalMinorById[option.id],
                  onEdit: () => _showEditDialog(context, option),
                  onGoal: () => _showGoalDialog(context, option),
                  onDelete: () => _showDeleteDialog(context, option),
                ),
              const SizedBox(height: 8),
              _SectionLabel(text: '收入分类'),
              for (final LedgerCategoryOption option in income)
                _CategoryTile(
                  option: option,
                  goalMinor: goalMinorById[option.id],
                  onEdit: () => _showEditDialog(context, option),
                  onGoal: () => _showGoalDialog(context, option),
                  onDelete: () => _showDeleteDialog(context, option),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ledgerCategoryCreateKey,
                  icon: const Icon(Icons.add),
                  label: const Text('新建分类'),
                  onPressed: () => _showCreateDialog(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 分组小标题。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tokens.onSurfaceMuted,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 单行分类：色点 + 名称（+ 内置徽标/日目标徽标）+ 目标/编辑/删除操作。
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.option,
    required this.goalMinor,
    required this.onEdit,
    required this.onGoal,
    required this.onDelete,
  });

  final LedgerCategoryOption option;

  /// 分类级日目标金额（分）；未设置时为 null。
  final int? goalMinor;
  final VoidCallback onEdit;
  final VoidCallback onGoal;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final Color dotColor =
        ledgerColorFromToken(tokens, option.colorToken) ?? tokens.onSurfaceMuted;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tokens.onSurface,
                            ),
                      ),
                    ),
                    if (option.isPreset) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '内置',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tokens.onSurfaceMuted,
                            ),
                      ),
                    ],
                  ],
                ),
                if (goalMinor != null)
                  Text(
                    '日目标 ${LedgerFormat.moneyMinor(goalMinor!)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.warn,
                        ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey<String>('ledger_category_goal_${option.id}'),
            icon: const Icon(Icons.flag_outlined, size: 18),
            tooltip: '每日目标',
            onPressed: onGoal,
          ),
          IconButton(
            key: ValueKey<String>('ledger_category_edit_${option.id}'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '编辑分类',
            onPressed: onEdit,
          ),
          if (!option.isPreset)
            // 内置分类不可删（§5.4⑤）：不渲染删除入口，而非点了报错。
            IconButton(
              key: ValueKey<String>('ledger_category_delete_${option.id}'),
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: '删除分类',
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

/// 新建/编辑分类对话框（§5.4⑤：名称 + 类型（仅新建）+ 语义色 token）。
class _CategoryEditDialog extends StatefulWidget {
  const _CategoryEditDialog({
    required this.repository,
    required this.original,
  });

  final LedgerAdminRepository repository;

  /// null=新建；非空=编辑（类型/色展示但类型不可改——历史行已按 kind 归组）。
  final LedgerCategoryOption? original;

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.original?.name ?? '');
  late String _kind =
      widget.original?.kind ?? kCategoryKindExpense;
  late String _token =
      widget.original?.colorToken ?? kLedgerColorTokens.first;
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = '分类名不能为空（§5.4⑤）';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final LedgerAdminRepository repository = widget.repository;
    final LedgerCategoryOption? original = widget.original;
    if (original == null) {
      await repository.createCategory(
        name: name,
        kind: _kind,
        colorToken: _token,
      );
    } else {
      await repository.updateCategory(id: original.id, name: name);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final bool isCreate = widget.original == null;
    return AlertDialog(
      title: Text(isCreate ? '新建分类' : '编辑分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: ledgerCategoryNameFieldKey,
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '分类名',
              errorText: _errorText,
            ),
          ),
          if (isCreate) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '类型',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('支出'),
                  selected: _kind == kCategoryKindExpense,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() {
                        _kind = kCategoryKindExpense;
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('收入'),
                  selected: _kind == kCategoryKindIncome,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() {
                        _kind = kCategoryKindIncome;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '颜色（语义 token，§8.2）',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final String token in kLedgerColorTokens)
                  _TokenDot(
                    token: token,
                    selected: _token == token,
                    onSelect: (String selected) {
                      setState(() {
                        _token = selected;
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: ledgerCategoryDialogSaveKey,
          onPressed: _saving ? null : _save,
          child: Text(isCreate ? '创建' : '保存'),
        ),
      ],
    );
  }
}

/// 语义色 token 选择圆点（选中加描边；色值经 SlimcaTheme 解析，§8.2）。
class _TokenDot extends StatelessWidget {
  const _TokenDot({
    required this.token,
    required this.selected,
    required this.onSelect,
  });

  final String token;
  final bool selected;
  final void Function(String token) onSelect;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final Color color = ledgerColorFromToken(tokens, token) ?? tokens.primary;
    return GestureDetector(
      onTap: () => onSelect(token),
      child: Tooltip(
        message: token,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected
                ? Border.all(color: tokens.onSurface, width: 2)
                : null,
          ),
        ),
      ),
    );
  }
}
