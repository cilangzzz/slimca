/// 账本 Tab 页（§4.2「账本」/§11.1 W5-6；§11.2 W15 多账本+统计入口）：
/// 日简报卡 → 账本筛选条 → 月份切换条 → 分类筛选条 → 月度分类汇总 →
/// 按日分组账单流。
///
/// - 数据全部响应式（watch 流直驱，§3.2 零业务查询直读本表）；
/// - 多账本（§11.2 W15、§3.4 P1）：账本筛选条（「全部」+ 可用账本，过滤
///   集合互斥）与账本管理入口（[LedgerManagePage]：建账本/重命名/归档/
///   切换默认）；录入侧 ledgerId 由 capture 网关承接（非本包范围）；
/// - 统计入口（§4.2「统计入口」）：AppBar 图标 push [ReportPage]
///   （周/月/年 + 钱-热量双轴联动，§3.4）；
/// - 编辑入口：账单条目点按回调 [LedgerPage.onEditEntry]，由壳接线到
///   既有 correction supersede 链（§3.3 金额不可变：修改=新增行 supersede
///   旧行；壳侧 `showCaptureSheet(seed: CaptureSeed(editEntryId:))`）；
/// - 分类管理入口：默认 push [CategoryManagePage]（页面级转场统一由宿主
///   注入自定义 PageRouteBuilder 时走 [LedgerPage.onOpenCategoryManage]，
///   §9.5 工程约束）。
library;

import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import '../ledger_admin_repository.dart';
import '../ledger_calendar.dart';
import '../ledger_colors.dart';
import '../ledger_format.dart';
import '../ledger_manage_repository.dart';
import '../ledger_models.dart';
import '../ledger_repository.dart';
import '../report_repository.dart';
import 'category_manage_page.dart';
import 'ledger_brief_card.dart';
import 'ledger_manage_page.dart';
import 'report_page.dart';

/// 账本页（构造注入仓库，与 feature_dashboard 同款装配，§10.4）。
class LedgerPage extends StatefulWidget {
  const LedgerPage({
    super.key,
    required this.repository,
    this.adminRepository,
    this.manageRepository,
    this.reportRepository,
    this.initialMonth,
    this.briefingDate,
    this.onEditEntry,
    this.onOpenCategoryManage,
    this.onOpenLedgerManage,
    this.onOpenReport,
    this.onStartCapture,
  });

  /// 账单流/汇总/简报读取仓库。
  final LedgerRepository repository;

  /// 分类管理仓库；与 [onOpenCategoryManage] 二者至少其一非空才会显示
  /// 分类管理入口。
  final LedgerAdminRepository? adminRepository;

  /// 账本管理仓库（§11.2 W15 多账本）：非空时显示账本筛选条与管理入口。
  final LedgerManageRepository? manageRepository;

  /// 报表仓库（§3.4 统计报表）：非空时显示统计入口（或经
  /// [onOpenReport] 由宿主接管转场）。
  final ReportRepository? reportRepository;

  /// 初始选中月（任意时刻，归位到所在月 1 号）；缺省=今天所在月。
  final DateTime? initialMonth;

  /// 日简报日（归位到自然日）；缺省=今天（测试注入固定日保证确定性）。
  final DateTime? briefingDate;

  /// 账单条目点按 → 编辑（壳接线 capture 修正链，§3.3）。
  final void Function(String entryId)? onEditEntry;

  /// 覆写分类管理导航（宿主注入自定义转场，§9.5）；缺省 push
  /// [CategoryManagePage]。
  final VoidCallback? onOpenCategoryManage;

  /// 覆写账本管理导航（宿主注入自定义转场，§9.5）；缺省 push
  /// [LedgerManagePage]。
  final VoidCallback? onOpenLedgerManage;

  /// 覆写统计报表导航（宿主注入自定义转场，§9.5）；缺省 push
  /// [ReportPage]（需 [reportRepository] 同非空）。
  final VoidCallback? onOpenReport;

  /// 空态「立即记录」回调（壳接线录入抽屉）。
  final VoidCallback? onStartCapture;

  @override
  State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
  late DateTime _month = LedgerCalendar.monthAnchor(
    widget.initialMonth ?? LedgerCalendar.today(),
  );
  String? _filterCategoryId;

  /// 多账本筛选（§11.2 W15）：null=全部账本；集合互斥（行级 ledger_id）。
  String? _filterLedgerId;

  bool get _canOpenCategories =>
      widget.onOpenCategoryManage != null || widget.adminRepository != null;

  bool get _canOpenManage =>
      widget.onOpenLedgerManage != null || widget.manageRepository != null;

  bool get _canOpenReport =>
      widget.onOpenReport != null || widget.reportRepository != null;

  void _shiftMonth(int delta) {
    setState(() {
      _month = LedgerCalendar.shiftMonth(_month, delta);
    });
  }

  void _openCategoryManage() {
    final VoidCallback? callback = widget.onOpenCategoryManage;
    if (callback != null) {
      callback();
      return;
    }
    final LedgerAdminRepository? admin = widget.adminRepository;
    if (admin == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CategoryManagePage(repository: admin),
      ),
    );
  }

  void _openLedgerManage() {
    final VoidCallback? callback = widget.onOpenLedgerManage;
    if (callback != null) {
      callback();
      return;
    }
    final LedgerManageRepository? manage = widget.manageRepository;
    if (manage == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LedgerManagePage(repository: manage),
      ),
    );
  }

  void _openReport() {
    final VoidCallback? callback = widget.onOpenReport;
    if (callback != null) {
      callback();
      return;
    }
    final ReportRepository? report = widget.reportRepository;
    if (report == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportPage(repository: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final String monthPrefix = LedgerCalendar.monthPrefix(_month);
    final DateTime briefingDate = LedgerCalendar.normalize(
      widget.briefingDate ?? LedgerCalendar.today(),
    );
    return Scaffold(
      backgroundColor: tokens.surface,
      appBar: AppBar(
        backgroundColor: tokens.surface,
        title: const Text('账本'),
        actions: <Widget>[
          if (_canOpenReport)
            IconButton(
              key: const ValueKey<String>('ledger_page_report'),
              icon: const Icon(Icons.donut_small_outlined),
              tooltip: '统计报表',
              onPressed: _openReport,
            ),
          if (_canOpenManage)
            IconButton(
              key: const ValueKey<String>('ledger_page_ledger_manage'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              tooltip: '账本管理',
              onPressed: _openLedgerManage,
            ),
          if (_canOpenCategories)
            IconButton(
              icon: const Icon(Icons.category_outlined),
              tooltip: '分类管理',
              onPressed: _openCategoryManage,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: <Widget>[
          SlimcaStaggerItem(
            index: 0,
            child: LedgerDayBriefingCard(
              repository: widget.repository,
              date: briefingDate,
            ),
          ),
          if (widget.manageRepository != null) ...<Widget>[
            const SizedBox(height: 8),
            SlimcaStaggerItem(
              index: 1,
              child: _LedgerFilterBar(
                repository: widget.manageRepository!,
                selectedLedgerId: _filterLedgerId,
                onSelect: (String? ledgerId) {
                  setState(() {
                    _filterLedgerId = ledgerId;
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          SlimcaStaggerItem(
            index: 2,
            child: _MonthBar(month: _month, onShift: _shiftMonth),
          ),
          const SizedBox(height: 8),
          SlimcaStaggerItem(
            index: 3,
            child: _CategoryFilterBar(
              repository: widget.repository,
              selectedCategoryId: _filterCategoryId,
              onSelect: (String? categoryId) {
                setState(() {
                  _filterCategoryId = categoryId;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          SlimcaStaggerItem(
            index: 4,
            child: _CategorySummaryCard(
              repository: widget.repository,
              month: monthPrefix,
              ledgerId: _filterLedgerId,
            ),
          ),
          const SizedBox(height: 12),
          _BillList(
            repository: widget.repository,
            month: monthPrefix,
            categoryId: _filterCategoryId,
            ledgerId: _filterLedgerId,
            onEditEntry: widget.onEditEntry,
            onStartCapture: widget.onStartCapture,
          ),
        ],
      ),
    );
  }
}

/// 账本筛选条（§11.2 W15 多账本）：「全部」+ 可用账本；单选，选中态
/// primary 反色。过滤集合互斥（行级 ledger_id，§5.2②）。
class _LedgerFilterBar extends StatelessWidget {
  const _LedgerFilterBar({
    required this.repository,
    required this.selectedLedgerId,
    required this.onSelect,
  });

  final LedgerManageRepository repository;
  final String? selectedLedgerId;
  final void Function(String? ledgerId) onSelect;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerSwitchOption>>(
      stream: repository.watchSwitchOptions(),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LedgerSwitchOption>> snapshot,
      ) {
        final List<LedgerSwitchOption> options =
            snapshot.data ?? const <LedgerSwitchOption>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _FilterChip(
                key: const ValueKey<String>('ledger_filter_ledger_all'),
                label: '全部账本',
                selected: selectedLedgerId == null,
                onTap: () => onSelect(null),
              ),
              for (final LedgerSwitchOption option in options)
                _FilterChip(
                  key: ValueKey<String>('ledger_filter_ledger_${option.id}'),
                  label: option.isKcalLedger
                      ? '${option.name} ·热量'
                      : option.name,
                  selected: selectedLedgerId == option.id,
                  onTap: () => onSelect(option.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 月份切换条（§3.4）：‹ 2026年11月 ›。
class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.onShift});

  final DateTime month;
  final void Function(int delta) onShift;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一月',
            onPressed: () => onShift(-1),
          ),
          Expanded(
            child: Center(
              child: Text(
                LedgerCalendar.monthTitle(month),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurface,
                    ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一月',
            onPressed: () => onShift(1),
          ),
        ],
      ),
    );
  }
}

/// 分类筛选条（§3.4）：「全部」+ 全部分类；单选，选中态 primary 反色。
class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.repository,
    required this.selectedCategoryId,
    required this.onSelect,
  });

  final LedgerRepository repository;
  final String? selectedCategoryId;
  final void Function(String? categoryId) onSelect;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerCategoryOption>>(
      stream: repository.watchCategoryOptions(),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LedgerCategoryOption>> snapshot,
      ) {
        final List<LedgerCategoryOption> options =
            snapshot.data ?? const <LedgerCategoryOption>[];
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              _FilterChip(
                key: const ValueKey<String>('ledger_filter_all'),
                label: '全部',
                selected: selectedCategoryId == null,
                onTap: () => onSelect(null),
              ),
              for (final LedgerCategoryOption option in options)
                _FilterChip(
                  key: ValueKey<String>('ledger_filter_${option.id}'),
                  label: option.name,
                  selected: selectedCategoryId == option.id,
                  onTap: () => onSelect(option.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个筛选 chip（§9.2 dur.s 隐式动画仅限微交互口径）。
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: context.motion.durS,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? tokens.primary : tokens.surfaceCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? tokens.onPrimary : tokens.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ),
      ),
    );
  }
}

/// 月度分类汇总卡（§3.4 统计雏形：per-category money 行求和，支出降序；
/// 收入类以 `+` 前缀标 moneyIn 色；W15 多账本：ledgerId 过滤）。
class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({
    required this.repository,
    required this.month,
    this.ledgerId,
  });

  final LedgerRepository repository;
  final String month;

  /// 多账本过滤（§11.2 W15）：null=全部账本。
  final String? ledgerId;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      key: const ValueKey<String>('ledger_summary_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: StreamBuilder<List<LedgerCategorySum>>(
        stream: repository.watchMonthCategorySums(month, ledgerId: ledgerId),
        builder: (
          BuildContext context,
          AsyncSnapshot<List<LedgerCategorySum>> snapshot,
        ) {
          final List<LedgerCategorySum> sums =
              snapshot.data ?? const <LedgerCategorySum>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    '分类汇总',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: tokens.onSurface,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    month,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.onSurfaceMuted,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (sums.isEmpty)
                Text(
                  '本月暂无分类数据',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                )
              else
                for (final LedgerCategorySum sum in sums)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _SummaryRow(sum: sum),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// 汇总行：色点 + 分类名 + 支出（moneyOut）/收入（moneyIn）。
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.sum});

  final LedgerCategorySum sum;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final Color dotColor =
        ledgerColorFromToken(tokens, sum.colorToken) ?? tokens.onSurfaceMuted;
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            sum.categoryName ?? '未分类',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurface,
                ),
          ),
        ),
        if (sum.spendMinor > 0)
          Text(
            LedgerFormat.moneyMinor(sum.spendMinor),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.moneyOut,
                  fontWeight: FontWeight.w600,
                ),
          ),
        if (sum.spendMinor > 0 && sum.incomeMinor > 0)
          const SizedBox(width: 8),
        if (sum.incomeMinor > 0)
          Text(
            LedgerFormat.signedMoneyMinor(sum.incomeMinor),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.moneyIn,
                  fontWeight: FontWeight.w600,
                ),
          ),
      ],
    );
  }
}

/// 按日分组账单流（§3.4）：日期降序分节，节头带当日合计；空月出引导态。
/// W15 多账本：ledgerId 过滤（§11.2）。
class _BillList extends StatelessWidget {
  const _BillList({
    required this.repository,
    required this.month,
    required this.categoryId,
    required this.ledgerId,
    required this.onEditEntry,
    required this.onStartCapture,
  });

  final LedgerRepository repository;
  final String month;
  final String? categoryId;

  /// 多账本过滤（§11.2 W15）：null=全部账本。
  final String? ledgerId;
  final void Function(String entryId)? onEditEntry;
  final VoidCallback? onStartCapture;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerDayGroup>>(
      stream: repository.watchMonthBillGroups(
        month,
        categoryId: categoryId,
        ledgerId: ledgerId,
      ),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<LedgerDayGroup>> snapshot,
      ) {
        if (!snapshot.hasData) {
          // 快照直出首帧：空占位，不转圈（§3.2 无任何加载态阻塞）。
          return const SizedBox.shrink();
        }
        final List<LedgerDayGroup> groups =
            snapshot.data ?? const <LedgerDayGroup>[];
        if (groups.isEmpty) {
          return _EmptyState(onStartCapture: onStartCapture);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final LedgerDayGroup group in groups)
              _DayGroupSection(group: group, onEditEntry: onEditEntry),
          ],
        );
      },
    );
  }
}

/// 单日分节：`11月16日 周一` + 当日合计 + 条目列（§3.4 按日分组）。
class _DayGroupSection extends StatelessWidget {
  const _DayGroupSection({required this.group, required this.onEditEntry});

  final LedgerDayGroup group;
  final void Function(String entryId)? onEditEntry;

  String get _dayTotalLabel {
    final List<String> parts = <String>[];
    if (group.spendMinor > 0) {
      parts.add('支出 ${LedgerFormat.moneyMinor(group.spendMinor)}');
    }
    if (group.incomeMinor > 0) {
      parts.add('收入 ${LedgerFormat.signedMoneyMinor(group.incomeMinor)}');
    }
    return parts.isEmpty ? '无收支' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Column(
      // 分节键：测试按日定位断言用（§3.4 按日分组）。
      key: ValueKey<String>('ledger_day_${group.date}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Row(
            children: <Widget>[
              Text(
                LedgerCalendar.dayGroupTitle(group.date),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.onSurfaceMuted,
                    ),
              ),
              const Spacer(),
              Text(
                _dayTotalLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
              ),
            ],
          ),
        ),
        for (final LedgerBillEntry entry in group.entries)
          _EntryTile(entry: entry, onEditEntry: onEditEntry),
      ],
    );
  }
}

/// 单条账：类型图标 + 标题/分类·热量副题 + 金额（或纯热量）尾列；
/// 点按触发编辑回调（§3.3 修正链由壳接线）。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onEditEntry});

  final LedgerBillEntry entry;
  final void Function(String entryId)? onEditEntry;

  IconData _kindIcon(dom.EntryKind kind) => switch (kind) {
        dom.EntryKind.food => Icons.restaurant_outlined,
        dom.EntryKind.fitness => Icons.fitness_center,
        dom.EntryKind.expense => Icons.payments_outlined,
        dom.EntryKind.mixed => Icons.restaurant_menu_outlined,
        dom.EntryKind.note => Icons.sticky_note_2_outlined,
      };

  /// 尾列文本：优先支出、其次收入、纯热量账展示 kcal（颜色在 build 内
  /// 按 [SlimcaTheme] token 解析）。
  String? get _trailingText {
    if (entry.spendMinor > 0) {
      return LedgerFormat.moneyMinor(entry.spendMinor);
    }
    if (entry.incomeMinor > 0) {
      return LedgerFormat.signedMoneyMinor(entry.incomeMinor);
    }
    if (entry.kcalOut > 0) {
      return '-${LedgerFormat.kcal(entry.kcalOut)}';
    }
    if (entry.kcalIn > 0) {
      return LedgerFormat.kcal(entry.kcalIn);
    }
    return null;
  }

  /// 尾列颜色：支出=moneyOut、收入=moneyIn、纯热量=net（§8.2）。
  Color _trailingColor(SlimcaTheme tokens) {
    if (entry.spendMinor > 0) {
      return tokens.moneyOut;
    }
    if (entry.incomeMinor > 0) {
      return tokens.moneyIn;
    }
    return tokens.net;
  }

  String? get _subtitle {
    final List<String> parts = <String>[];
    // 分类挂在行上（§5.2②）；取该账第一条有分类的行名。
    for (final LedgerBillLine line in entry.lines) {
      if (line.categoryName != null) {
        parts.add(line.categoryName!);
        break;
      }
    }
    if (entry.kcalIn > 0) {
      parts.add('${entry.kcalIn} kcal');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final String? trailingText = _trailingText;
    final String? subtitle = _subtitle;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap:
              onEditEntry == null ? null : () => onEditEntry!(entry.entryId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Icon(
                  _kindIcon(entry.kind),
                  size: 20,
                  color: tokens.onSurfaceMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: tokens.onSurface,
                            ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: tokens.onSurfaceMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailingText != null)
                  Text(
                    trailingText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _trailingColor(tokens),
                        ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空月引导态（§2.3 七步闭环引导；壳可接线录入抽屉）。
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStartCapture});

  final VoidCallback? onStartCapture;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.receipt_long_outlined,
            size: 32,
            color: tokens.onSurfaceMuted,
          ),
          const SizedBox(height: 8),
          Text(
            '本月还没有账单',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: tokens.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '记一件事，钱和热量一起入账',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
          ),
          if (onStartCapture != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onStartCapture,
              child: const Text('立即记录'),
            ),
          ],
        ],
      ),
    );
  }
}
