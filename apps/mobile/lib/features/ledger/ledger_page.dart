/// 账本 Tab 真页（§3.4 流水列表、§4.2「流水列表+分类管理+预算入口+统计
/// 入口」、§4.3 /ledger、§11.1 W5-6「记账完整化」；W15 多账本升级 §11.2）。
///
/// W15 结构（§11.2「多账本+预算体系+统计报表」、§3.4 多账本 P1「账本切换
/// 抽屉」）：
/// - 顶栏账本切换器（下拉弹层，语义 token 样式 §8.2）：money 账本组 + 内置
///   kcal 账本视图；选 money 账本即默认账本记忆（settings §5.6⑲ +
///   MultiLedgerService.switchDefaultLedger，§6.2 同事务）+ ledger_switched
///   漏斗；「新建账本」入口就地建档（§6.2 行快照同事务入队）；
/// - AppBar 动作位：统计报表（/stats §4.3）、预算设置（/ledger/budgets §4.3）、
///   分类管理（feature_ledger CategoryManagePage 复用 §10.4）；
/// - 分类筛选条（money 视图）：per-分类明细入口（仪表盘支出卡）跳转落点，
///   筛选态数字自洽（ledger_state 口径，§3.4）；
/// - 流水列表按日分组（ledgerDayGroupsProvider，date 倒序、日内 created_at
///   升序）；点条目进编辑抽屉（feature_capture CapturePage 编辑态，§3.4
///   修正=新增行、§10.4 唯一录入 UI 纪律）。空态一句话引导（§2.3 步 1）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:feature_capture/feature_capture.dart' show CaptureSeed, showCaptureSheet;
import 'package:feature_ledger/feature_ledger.dart'
    show
        CategoryManagePage,
        LedgerCategoryOption,
        LedgerManagePage,
        kCategoryKindExpense,
        ledgerColorFromToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../app/providers.dart';
import '../../common/format.dart';
import '../../ledger/multi_ledger_service.dart';
import '../../telemetry/w15_funnel_events.dart';
import 'ledger_state.dart';

/// 账本 Tab。
class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopes =
        ref.watch(ledgerScopesProvider).value ?? const <db.Ledger>[];
    final currentId = ref.watch(currentLedgerScopeIdProvider);
    final scope = _resolveScope(scopes, currentId);
    final categoryFilter = ref.watch(ledgerCategoryFilterProvider);
    final asyncGroups =
        ref.watch(ledgerDayGroupsProvider(LedgerBillQuery(
      ledgerId: scope?.id,
      scopeKind: scope?.kind ?? 'money',
      categoryId: categoryFilter,
    )));
    final groups = asyncGroups.value ?? const <LedgerDayGroup>[];
    final isKcalScope = scope?.kind == 'kcal';
    final spacing = context.spacing;
    final sizes = context.sizes;

    return Scaffold(
      appBar: AppBar(
        // 顶栏账本切换器（§3.4「账本切换抽屉」下拉形态；语义 token 样式）。
        title: _LedgerScopeSwitcher(
          scopes: scopes,
          current: scope,
        ),
        actions: [
          // 统计报表入口（§4.2「统计入口」、§4.3 /stats，W15 任务 1）。
          IconButton(
            key: const Key('ledger_stats_entry'),
            icon: const Icon(Icons.insights_outlined),
            tooltip: '统计报表',
            onPressed: () => context.push('/stats'),
          ),
          // 预算设置入口（§4.2「预算入口」、§4.3 /ledger/budgets，W15 任务 1）。
          IconButton(
            key: const Key('ledger_budget_entry'),
            icon: const Icon(Icons.savings_outlined),
            tooltip: '预算设置',
            onPressed: () => context.push('/ledger/budgets'),
          ),
          // 分类管理入口（§4.2；复用 feature_ledger CategoryManagePage，§10.4）。
          IconButton(
            key: const Key('ledger_category_manage_entry'),
            icon: const Icon(Icons.category_outlined),
            tooltip: '分类管理',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CategoryManagePage(
                  repository: ref.read(ledgerAdminRepositoryProvider),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 分类筛选条（§3.4 分类筛选；kcal 视图为热量口径、money 分类
            // 不适用，隐藏）。
            if (!isKcalScope)
              _CategoryFilterBar(
                selectedId: categoryFilter,
                onSelected: (id) => ref
                    .read(ledgerCategoryFilterProvider.notifier)
                    .select(id),
              ),
            Expanded(
              child: groups.isEmpty
                  ? _LedgerEmptyHint(hasData: asyncGroups.hasValue)
                  : ListView(
                      // 底部留白（底栏重设计拍板（《UI-规范与重设计》§2.2 增补段））：清中央花瓣按钮
                      // 凸出栏体（cradle 间隙约 34）+ 呼吸——space600+
                      // rowSingleLine+space200 组合表达（§2.2 禁裸尺寸）。
                      padding: EdgeInsets.fromLTRB(
                        spacing.space200,
                        spacing.space100,
                        spacing.space200,
                        spacing.space600 + sizes.rowSingleLine + spacing.space200,
                      ),
                      children: [
                        for (final group in groups) ...[
                          _LedgerDayHeader(group: group),
                          const SizedBox(height: 4),
                          _LedgerCard(
                            child: Column(
                              children: [
                                for (final view in group.entries)
                                  _LedgerEntryTile(
                                    key: ValueKey(
                                        'ledger_entry_${view.entryId}'),
                                    view: view,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 12),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 当前作用域解析：手动选择优先；未选择回落默认 money 账本（=默认账本
  /// 记忆，W15），再回落 kcal 账本；无任何账本（seed 前防御）返回 null。
  static db.Ledger? _resolveScope(
    List<db.Ledger> scopes,
    String? currentId,
  ) {
    for (final ledger in scopes) {
      if (ledger.id == currentId) {
        return ledger;
      }
    }
    for (final ledger in scopes) {
      if (ledger.kind == 'money' && !ledger.isArchived) {
        return ledger;
      }
    }
    return scopes.isEmpty ? null : scopes.first;
  }
}

/// 顶栏账本切换器：当前账本名 + 下拉箭头，点按弹出切换抽屉（§3.4 多账本
/// P1「账本切换抽屉」的顶栏下拉形态；样式取语义 token，§8.2 组件层纪律）。
class _LedgerScopeSwitcher extends ConsumerWidget {
  const _LedgerScopeSwitcher({
    required this.scopes,
    required this.current,
  });

  final List<db.Ledger> scopes;

  /// 当前作用域（null=尚未有可用账本）。
  final db.Ledger? current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      key: const Key('ledger_scope_switcher'),
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showSwitcherSheet(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _scopeIcon(current?.kind),
              size: 20,
              color: tokens.onSurface,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                current?.name ?? '账本',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: tokens.onSurfaceMuted,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSwitcherSheet(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: tokens.surfaceCard,
      // 弹层内 Consumer：切换/建档经弹层自身 context 收尾（pop 关弹层而非
      // 误关页面路由），sheetRef 与页面 ref 同一容器。
      builder: (sheetContext) => Consumer(
        builder: (innerContext, sheetRef, _) {
          final sheetScopes = sheetRef
                  .watch(ledgerScopesProvider)
                  .value ??
              scopes;
          // 默认徽标（§5.6⑲ 指针响应式；core_db watchDefaultLedgerId 复用）。
          final defaultLedgerId =
              sheetRef.watch(defaultLedgerIdProvider).value;
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '切换账本',
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
                for (final ledger in sheetScopes)
                  _ScopeTile(
                    ledger: ledger,
                    isCurrent: ledger.id == current?.id,
                    isDefault: ledger.id == defaultLedgerId,
                    onTap: () =>
                        _selectScope(innerContext, sheetRef, ledger),
                  ),
                const Divider(height: 24),
                // 新建账本（§3.4 多账本建档；W15 壳层服务 §6.2 写路径）。
                ListTile(
                  key: const Key('ledger_create_tile'),
                  leading: Icon(
                    Icons.add_circle_outline,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  ),
                  title: const Text('新建账本'),
                  onTap: () => _createLedger(innerContext, sheetRef),
                ),
                // 账本管理（§3.4「账本归档」P1；feature_ledger
                // LedgerManagePage 复用 §10.4——重命名/归档/设默认）。
                ListTile(
                  key: const Key('ledger_manage_tile'),
                  leading: Icon(
                    Icons.settings_outlined,
                    color: tokens.onSurfaceMuted,
                  ),
                  title: const Text('管理账本'),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LedgerManagePage(
                          repository:
                              sheetRef.read(ledgerManageRepositoryProvider),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 切换作用域：money 账本 = 默认账本记忆（settings + sort 置首，§6.2）+
  /// ledger_switched 漏斗；kcal 账本为视图态切换（同记漏斗，不持久化默认）。
  Future<void> _selectScope(
    BuildContext sheetContext,
    WidgetRef sheetRef,
    db.Ledger ledger,
  ) {
    return _applyScopeSelection(
      sheetRef,
      sheetContext,
      ledger.id,
      kind: ledger.kind,
    );
  }

  /// 新建账本对话框（§3.4；建档成功即切换为新账本并记忆为默认——与
  /// [_selectScope] 同一编排：select → ledger_switched → §6.2 持久化）。
  Future<void> _createLedger(
    BuildContext sheetContext,
    WidgetRef sheetRef,
  ) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建账本'),
        content: TextField(
          key: const Key('ledger_create_name_field'),
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(
            labelText: '账本名',
            hintText: '如：差旅、家用',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('ledger_create_save'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (created != true || !sheetContext.mounted) {
      return;
    }
    try {
      final id = await sheetRef
          .read(multiLedgerServiceProvider)
          .createMoneyLedger(name: controller.text);
      if (!sheetContext.mounted) {
        return;
      }
      await _applyScopeSelection(sheetRef, sheetContext, id, kind: 'money');
    } on ArgumentError {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          const SnackBar(content: Text('请输入账本名')),
        );
      }
    } on Object {
      if (sheetContext.mounted) {
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          const SnackBar(content: Text('创建失败，请重试')),
        );
      }
    }
  }

  /// 切换作用域的统一编排（W15 任务 3/4）：
  /// ① 账本 Tab 当前作用域置位；② ledger_switched 漏斗（props 只带 kind
  /// 标量标签，账本名禁入 §3.9）；③ money 账本 = 默认账本记忆（settings
  /// kSettingDefaultLedgerId + money 组 sort 置首，§6.2 同事务）；kcal 账本
  /// 为视图态切换（不持久化默认，§5.4④ 系统内置）。
  Future<void> _applyScopeSelection(
    WidgetRef sheetRef,
    BuildContext sheetContext,
    String ledgerId, {
    required String kind,
  }) async {
    sheetRef.read(currentLedgerScopeIdProvider.notifier).select(ledgerId);
    try {
      await sheetRef
          .read(telemetryServiceProvider)
          .funnel(W15TelemetryFunnel.ledgerSwitched, props: <String, Object?>{
            'kind': kind,
          });
    } catch (_) {
      // 遥测失败不影响主流程（§3.9）。
    }
    if (kind == 'money') {
      try {
        await sheetRef
            .read(multiLedgerServiceProvider)
            .switchDefaultLedger(ledgerId);
      } catch (_) {
        // 默认账本持久化失败不阻断视图切换（本地件自愈，§6.1 只降级）。
      }
    }
    if (sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
  }

  IconData _scopeIcon(String? kind) {
    return switch (kind) {
      'kcal' => Icons.local_fire_department_outlined,
      _ => Icons.account_balance_wallet_outlined,
    };
  }
}

/// 切换抽屉内的账本行（图标/名称/币种 + 默认徽标 + 当前勾选；语义 token
/// 样式）。
class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.ledger,
    required this.isCurrent,
    required this.isDefault,
    required this.onTap,
  });

  final db.Ledger ledger;
  final bool isCurrent;

  /// §5.6⑲ 默认账本指针（「默认」徽标；与 [isCurrent] 的视图勾选独立）。
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final isKcal = ledger.kind == 'kcal';
    return ListTile(
      key: Key('ledger_scope_${ledger.id}'),
      leading: Icon(
        isKcal
            ? Icons.local_fire_department_outlined
            : Icons.account_balance_wallet_outlined,
        color: isKcal ? tokens.kcalOut : tokens.moneyOut,
      ),
      title: Text(
        ledger.name,
        style: textTheme.bodyLarge?.copyWith(
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          color: tokens.onSurface,
        ),
      ),
      subtitle: Text(
        isKcal ? '热量账本（系统内置）' : ledger.currency,
        style: textTheme.bodySmall?.copyWith(color: tokens.onSurfaceMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDefault)
            Text(
              '默认',
              style: textTheme.labelSmall?.copyWith(
                color: tokens.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, color: Theme.of(context).colorScheme.primary),
          ],
        ],
      ),
      onTap: onTap,
    );
  }
}

/// 分类筛选条（§3.4；money 视图专用——per-分类明细入口的落点，筛选态
/// 数字自洽）。
class _CategoryFilterBar extends ConsumerWidget {
  const _CategoryFilterBar({
    required this.selectedId,
    required this.onSelected,
  });

  final String? selectedId;
  final void Function(String?) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(ledgerCategoryOptionsProvider).value;
    // 分类流未装载/无支出分类时不占位（§2.3 零等待空屏）。
    final expenseOptions = (options ?? const <LedgerCategoryOption>[])
        .where((option) => option.kind == kCategoryKindExpense)
        .toList(growable: false);
    if (expenseOptions.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: selectedId == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final option in expenseOptions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('ledger_filter_${option.id}'),
                label: Text(option.name),
                selected: selectedId == option.id,
                onSelected: (_) => onSelected(option.id),
                avatar: Icon(
                  Icons.circle,
                  size: 10,
                  // 分类色经语义 token 解析（§8.2，复用 feature_ledger
                  // ledger_colors 白名单映射）。
                  color: ledgerChipColor(context, option.colorToken),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分类色 token → 语义色（feature_ledger `ledgerColorFromToken` 的薄别名；
/// 白名单外回退主色，避免裸色值 §8.2）。
Color ledgerChipColor(BuildContext context, String tokenName) {
  final tokens = context.slimca;
  final resolved = ledgerColorFromToken(tokens, tokenName);
  return resolved ?? tokens.primary;
}

/// 日头：n月n日 + 作用域内合计（§3.4 按日分组；money 视图=支出/收入、
/// kcal 视图=摄入/消耗——合计已按 ledger_state 口径归零另一侧）。
class _LedgerDayHeader extends StatelessWidget {
  const _LedgerDayHeader({required this.group});

  final LedgerDayGroup group;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final parts = <String>[
      if (group.spendMinor > 0) '支出 ${yuanFromMinor(group.spendMinor)}',
      if (group.incomeMinor > 0) '收入 ${yuanFromMinor(group.incomeMinor)}',
      if (group.kcalIn > 0) '摄入 ${group.kcalIn} kcal',
      if (group.kcalOut > 0) '消耗 ${group.kcalOut} kcal',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Text(
            calendarDayLabel(group.date),
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: tokens.onSurface,
            ),
          ),
          const Spacer(),
          if (parts.isNotEmpty)
            Text(
              parts.join(' · '),
              style: textTheme.labelMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// 账本卡容器（与仪表盘/计划卡同形：surfaceCard + r16，§3.2/§8.2）。
class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.slimca.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: child,
      ),
    );
  }
}

/// 单条流水行：kind 图标 + 标题 + 摘要（作用域内摄入/消耗/支出/收入），
/// 点击进编辑。
class _LedgerEntryTile extends StatelessWidget {
  const _LedgerEntryTile({super.key, required this.view});

  final LedgerEntryView view;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    // 摘要的金额/热量着色（语义 token，§8.2）。
    final summaryParts = <String, Color>{
      if (view.kcalIn > 0) '摄入 ${view.kcalIn} kcal': tokens.kcalIn,
      if (view.kcalOut > 0) '消耗 ${view.kcalOut} kcal': tokens.kcalOut,
      if (view.spendMinor > 0)
        '支出 ${yuanFromMinor(view.spendMinor)}': tokens.moneyOut,
      if (view.incomeMinor > 0)
        '收入 ${yuanFromMinor(view.incomeMinor)}': tokens.moneyIn,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        _kindIcon(view.kind),
        color: tokens.onSurfaceMuted,
      ),
      title: Text(
        view.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium,
      ),
      subtitle: summaryParts.isEmpty
          ? Text(
              '仅记录描述',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 2,
              children: [
                for (final entry in summaryParts.entries)
                  Text(
                    entry.key,
                    style: textTheme.bodySmall?.copyWith(
                      color: entry.value,
                    ),
                  ),
              ],
            ),
      // 编辑：弹簧抽屉编辑态（预填+修正链落库，§3.4/§6.5 金额不可变）。
      onTap: () => showCaptureSheet(
        context,
        seed: CaptureSeed(editEntryId: view.entryId),
      ),
    );
  }

  IconData _kindIcon(String kindWire) {
    return switch (kindWire) {
      'food' => Icons.restaurant_outlined,
      'expense' => Icons.payments_outlined,
      'mixed' => Icons.restaurant_menu_outlined,
      'fitness' => Icons.fitness_center,
      'note' => Icons.sticky_note_2_outlined,
      _ => Icons.edit_note_outlined,
    };
  }
}

/// 空态引导：一句话定位 + 录入入口提示（§1.2、§2.3 步 1）。
class _LedgerEmptyHint extends StatelessWidget {
  const _LedgerEmptyHint({required this.hasData});

  /// 流已装载但确无数据=true；装载中=false（不显示「还没有记录」误导）。
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: tokens.onSurfaceMuted,
          ),
          const SizedBox(height: 12),
          Text(
            hasData ? '该账本还没有记录' : '正在装载流水…',
            style: textTheme.bodyLarge?.copyWith(color: tokens.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            hasData
                ? '点击底部「+」记一笔，或切换/新建账本（§3.4 多账本）'
                : '§2.3 零等待空屏：流水装载即现，无 spinner 打断',
            style: textTheme.bodySmall?.copyWith(
              color: tokens.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}
