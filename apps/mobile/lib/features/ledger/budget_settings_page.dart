/// 预算设置页（§4.3 /ledger/budgets「预算设置（P0 含每日目标；月度/分类
/// P1）」；W15 预算体系 §11.2、§3.4「月度+分类预算 P1」、§5.4⑥ budgets）。
///
/// 表单面（W15 任务 1）：
/// - 每日总支出目标（budgets period=daily、总预算 categoryId=NULL，分存储
///   §5.1）——feature_ledger `LedgerAdminRepository` 写路径（§10.4，W15
///   收口：经 core_db BudgetsDao 同事务 outbox + 投影联动 §5.6⑬）；
/// - 每日热量目标（kcal 账本「预算=收入」§2.1③）——同上；
/// - 分类每日预算（budgets.category_id 非空，§5.4⑥）——同上；
/// - 月度预算（period_type=monthly：总额/周期起点 1-28/结转开关）——同上
///   （setMonthlySpendGoal，§5.4⑥ P1/W15）；
/// - 全部保存成功即记 budget_set 漏斗（W15 任务 4；props.scope 只带标量
///   标签，金额禁入 §3.9）。
library;

import 'package:feature_ledger/feature_ledger.dart'
    show LedgerDailyBudget, kCategoryKindExpense;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../common/format.dart';
import '../../telemetry/w15_funnel_events.dart';

/// 预算设置页。
class BudgetSettingsPage extends ConsumerWidget {
  const BudgetSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(ledgerDailyBudgetsProvider).value ??
        const <LedgerDailyBudget>[];
    final dailyTotal = _firstOrNull(
      budgets.where((b) => !b.isKcalGoal && !b.isCategoryGoal),
    );
    final kcalGoal = _firstOrNull(
      budgets.where((b) => b.isKcalGoal && !b.isCategoryGoal),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('预算设置')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            _DailyAmountSection(
              title: '每日总支出目标',
              hint: '每天打算花多少（§3.4 每日目标）',
              currentAmount: dailyTotal?.amount,
              unit: _AmountUnit.yuan,
              fieldKey: 'budget_daily_spend_field',
              saveKey: 'budget_daily_spend_save',
              clearKey: 'budget_daily_spend_clear',
              scope: 'daily_total',
              onSave: (minor) => ref
                  .read(ledgerAdminRepositoryProvider)
                  .setDailySpendGoal(minor),
              onClear: () =>
                  ref.read(ledgerAdminRepositoryProvider).clearDailySpendGoal(),
            ),
            const SizedBox(height: 12),
            _DailyAmountSection(
              title: '每日热量目标',
              hint: '每天打算吃进多少 kcal（kcal 账本「预算=收入」§2.1③）',
              currentAmount: kcalGoal?.amount,
              unit: _AmountUnit.kcal,
              fieldKey: 'budget_kcal_field',
              saveKey: 'budget_kcal_save',
              clearKey: 'budget_kcal_clear',
              scope: 'kcal',
              onSave: (kcal) =>
                  ref.read(ledgerAdminRepositoryProvider).setDailyKcalGoal(kcal),
              onClear: () =>
                  ref.read(ledgerAdminRepositoryProvider).clearDailyKcalGoal(),
            ),
            const SizedBox(height: 12),
            _CategoryBudgetSection(currentBudgets: budgets),
            const SizedBox(height: 12),
            const _MonthlyBudgetSection(),
            const SizedBox(height: 16),
            Text(
              '预算即时联动：仪表盘支出卡/热量环与预算余快照直读 day_summary '
              '（§5.6⑬ budget_snapshot，写路径同事务重算）',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.slimca.onSurfaceMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 取第一条（Iterable.firstOrNull 的免依赖写法）。
T? _firstOrNull<T>(Iterable<T> source) {
  for (final item in source) {
    return item;
  }
  return null;
}

/// 金额/热量输入单位（§5.1：money=分、kcal=整数 kcal）。
enum _AmountUnit { yuan, kcal }

/// 每日目标区块（总额/热量共用表单：当前值 + 输入 + 保存/清除）。
class _DailyAmountSection extends ConsumerStatefulWidget {
  const _DailyAmountSection({
    required this.title,
    required this.hint,
    required this.currentAmount,
    required this.unit,
    required this.fieldKey,
    required this.saveKey,
    required this.clearKey,
    required this.scope,
    required this.onSave,
    required this.onClear,
  });

  final String title;
  final String hint;
  final int? currentAmount;
  final _AmountUnit unit;
  final String fieldKey;
  final String saveKey;
  final String clearKey;

  /// budget_set 漏斗的 scope 标签（daily_total/kcal）。
  final String scope;
  final Future<void> Function(int amount) onSave;
  final Future<void> Function() onClear;

  @override
  ConsumerState<_DailyAmountSection> createState() =>
      _DailyAmountSectionState();
}

class _DailyAmountSectionState extends ConsumerState<_DailyAmountSection> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final tokens = context.slimca;
    final messenger = ScaffoldMessenger.of(context);
    final int? amount;
    if (widget.unit == _AmountUnit.yuan) {
      amount = parseYuanToFen(_controller.text);
    } else {
      amount = int.tryParse(_controller.text.trim());
    }
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的有效数值')),
      );
      return;
    }
    try {
      await widget.onSave(amount);
      // W15 任务 4：预算设置漏斗（§3.9 props 只带 scope 标量标签）。
      try {
        await ref
            .read(telemetryServiceProvider)
            .funnel(W15TelemetryFunnel.budgetSet, props: <String, Object?>{
              'scope': widget.scope,
            });
      } catch (_) {
        // 遥测失败不影响主流程（§3.9）。
      }
      _controller.clear();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('预算已保存'),
          backgroundColor: tokens.success,
        ),
      );
    } on ArgumentError catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onClear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('已清除')));
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('清除失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final current = widget.currentAmount;
    final currentText = current == null
        ? '未设置'
        : widget.unit == _AmountUnit.yuan
            ? '${yuanFromMinor(current)}/天'
            : '$current kcal/天';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: textTheme.titleMedium,
                  ),
                ),
                Text(
                  currentText,
                  style: textTheme.labelLarge?.copyWith(
                    color: current == null
                        ? tokens.onSurfaceMuted
                        : tokens.moneyOut,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.hint,
              style: textTheme.bodySmall
                  ?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key(widget.fieldKey),
                    controller: _controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.unit == _AmountUnit.yuan
                          ? '金额（元），如 50 或 50.00'
                          : '热量（kcal），如 2000',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: Key(widget.saveKey),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: Key(widget.clearKey),
                  onPressed: current == null ? null : _clear,
                  child: const Text('清除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 分类每日预算区块（§5.4⑥ budgets.category_id 非空；per-分类表单）。
class _CategoryBudgetSection extends ConsumerWidget {
  const _CategoryBudgetSection({required this.currentBudgets});

  final List<LedgerDailyBudget> currentBudgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final options = ref.watch(ledgerCategoryOptionsProvider).value;
    final expenseOptions = (options ?? const [])
        .where((option) => option.kind == kCategoryKindExpense)
        .toList(growable: false);
    if (expenseOptions.isEmpty) {
      return const SizedBox.shrink();
    }
    final amountByCategory = <String, int>{
      for (final budget in currentBudgets)
        if (budget.isCategoryGoal && !budget.isKcalGoal)
          budget.categoryId!: budget.amount,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分类每日预算', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '按分类设每日上限（§5.4⑥；超支在支出卡按分类标红）',
              style: textTheme.bodySmall
                  ?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 8),
            for (final option in expenseOptions)
              _CategoryBudgetRow(
                categoryId: option.id,
                categoryName: option.name,
                currentAmount: amountByCategory[option.id],
              ),
          ],
        ),
      ),
    );
  }
}

/// 单个分类预算行：分类名 + 当日已设值 + 金额输入 + 保存/清除。
class _CategoryBudgetRow extends ConsumerStatefulWidget {
  const _CategoryBudgetRow({
    required this.categoryId,
    required this.categoryName,
    required this.currentAmount,
  });

  final String categoryId;
  final String categoryName;
  final int? currentAmount;

  @override
  ConsumerState<_CategoryBudgetRow> createState() => _CategoryBudgetRowState();
}

class _CategoryBudgetRowState extends ConsumerState<_CategoryBudgetRow> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = parseYuanToFen(_controller.text);
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的有效金额')),
      );
      return;
    }
    try {
      await ref
          .read(ledgerAdminRepositoryProvider)
          .setCategoryDailyGoal(
            categoryId: widget.categoryId,
            amountMinor: amount,
          );
      try {
        await ref
            .read(telemetryServiceProvider)
            .funnel(W15TelemetryFunnel.budgetSet, props: <String, Object?>{
              'scope': 'category',
            });
      } catch (_) {
        // 遥测失败不影响主流程（§3.9）。
      }
      _controller.clear();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.categoryName} 预算已保存')),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  Future<void> _clear() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(ledgerAdminRepositoryProvider)
          .clearCategoryDailyGoal(widget.categoryId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.categoryName} 预算已清除')),
      );
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('清除失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final current = widget.currentAmount;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              widget.categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              current == null ? '未设置' : '${yuanFromMinor(current)}/天',
              style: textTheme.bodySmall?.copyWith(
                color: current == null
                    ? tokens.onSurfaceMuted
                    : tokens.moneyOut,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              key: Key('budget_category_field_${widget.categoryId}'),
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '元/天',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            key: Key('budget_category_save_${widget.categoryId}'),
            tooltip: '保存',
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
          IconButton(
            key: Key('budget_category_clear_${widget.categoryId}'),
            tooltip: '清除',
            icon: const Icon(Icons.close),
            onPressed: current == null ? null : _clear,
          ),
        ],
      ),
    );
  }
}

/// 月度预算区块（W15：§5.4⑥ period_type=monthly + §3.4「周期起点自定义、
/// 结转开关」；壳层 MultiLedgerService 写路径 §6.2）。
class _MonthlyBudgetSection extends ConsumerStatefulWidget {
  const _MonthlyBudgetSection();

  @override
  ConsumerState<_MonthlyBudgetSection> createState() =>
      _MonthlyBudgetSectionState();
}

class _MonthlyBudgetSectionState extends ConsumerState<_MonthlyBudgetSection> {
  final TextEditingController _amountController = TextEditingController();
  int _dayOfMonthStart = 1;
  bool _carryOver = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final amount = parseYuanToFen(_amountController.text);
    if (amount == null || amount <= 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('请输入大于 0 的有效金额')),
      );
      return;
    }
    try {
      // W15 月度预算写路径：feature_ledger admin 仓库 → core_db BudgetsDao
      // （§6.2 同事务 outbox + budget_snapshot v2 投影联动，§5.6⑬）。
      await ref
          .read(ledgerAdminRepositoryProvider)
          .setMonthlySpendGoal(
            amount,
            dayOfMonthStart: _dayOfMonthStart,
            carryOver: _carryOver,
          );
      try {
        await ref
            .read(telemetryServiceProvider)
            .funnel(W15TelemetryFunnel.budgetSet, props: <String, Object?>{
              'scope': 'monthly',
            });
      } catch (_) {
        // 遥测失败不影响主流程（§3.9）。
      }
      _amountController.clear();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('月度预算已保存')));
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('保存失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final monthly =
        ref.watch(monthlyBudgetsProvider).value ?? const <LedgerDailyBudget>[];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('月度预算', style: textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '月总额 + 周期起点（1-28 日）+ 结转开关（§5.4⑥）',
              style: textTheme.bodySmall
                  ?.copyWith(color: tokens.onSurfaceMuted),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('budget_monthly_amount'),
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      hintText: '月金额（元）',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  key: const Key('budget_monthly_start'),
                  value: _dayOfMonthStart,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var day = 1; day <= 28; day++)
                      DropdownMenuItem<int>(
                        value: day,
                        child: Text('$day 日'),
                      ),
                  ],
                  onChanged: (day) {
                    if (day != null) {
                      setState(() => _dayOfMonthStart = day);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('结转到下月'),
                const Spacer(),
                Switch(
                  key: const Key('budget_monthly_carry'),
                  value: _carryOver,
                  onChanged: (value) => setState(() => _carryOver = value),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const Key('budget_monthly_save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
            for (final budget in monthly)
              ListTile(
                key: Key('budget_monthly_row_${budget.id}'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.event_repeat_outlined),
                title: Text(
                  '每月 ${budget.dayOfMonthStart} 日起 '
                  '${yuanFromMinor(budget.amount)}'
                  '${budget.carryOver ? ' · 结转' : ''}',
                  style: textTheme.bodyMedium,
                ),
                trailing: IconButton(
                  key: Key('budget_monthly_delete_${budget.id}'),
                  tooltip: '清除',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      // 月度总预算清除（软删墓碑幂等，§5.4⑥/§6.5）。
                      await ref
                          .read(ledgerAdminRepositoryProvider)
                          .clearMonthlySpendGoal();
                    } on Object {
                      // 清除失败静默（墓碑语义，§6.1 只降级）。
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
