import 'dart:ui' show clampDouble;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:feature_capture/feature_capture.dart'
    show CaptureSeed, showCaptureSheet;

import '../../app/providers.dart';
import '../../common/format.dart';
import 'dashboard_state.dart';

/// 日期仪表盘（§3.2；W2：卡片墙由明细行 reactive stream 实时驱动——
/// 「手动记一笔→仪表盘环/支出卡即时更新」验收线，§11 W2）。
///
/// 设计决策：
/// - 本页是**唯一首页**（§4.1 原则 1、§3.2「唯一首页」），无第二个首页；
/// - 数据源=[dashboardDayProvider]/[dashboardTodosProvider]/[dailyBudgetProvider]：
///   聚合从明细行实时重建（§6.1 原则 3），loading/error 一律渲染零值空态——
///   页面永不出现 spinner（§2.3 步 0）；day_summary 投影直读（§5.6⑬ 首帧
///   直出、零业务查询）随投影 v1 落库接入，provider 签名不变；
/// - 冷启动卡片墙按 §9.3#1 级联上浮（SlimcaStaggerItem + cascadeInterval
///   token），切日过渡走 AnimatedSwitcher 共享轴（§9.3#2，§9.2 dur.l）；
/// - 语义色统一取 SlimcaTheme token（kcalIn/moneyOut/surfaceCard 等，§8.2
///   三层架构：组件层禁止裸色值）。
class TodayDashboardPage extends ConsumerStatefulWidget {
  const TodayDashboardPage({super.key});

  @override
  ConsumerState<TodayDashboardPage> createState() => _TodayDashboardPageState();
}

class _TodayDashboardPageState extends ConsumerState<TodayDashboardPage> {
  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final wallKey = ValueKey<DateTime>(selectedDate);

    return Scaffold(
      appBar: AppBar(title: const Text('Slimca'), centerTitle: false),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _DateHeader(date: selectedDate),
            const SizedBox(height: 12),
            _WeekStrip(selected: selectedDate),
            const SizedBox(height: 20),
            // 左右滑切日：共享轴转场 280ms（§3.2、§9.3 转场 #2——方向感知与
            // 卡片 FLIP 位置保持随转场 #2 完整实现接入）。
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v > 120) {
                  ref.read(selectedDateProvider.notifier).shiftByDays(-1);
                } else if (v < -120) {
                  ref.read(selectedDateProvider.notifier).shiftByDays(1);
                }
              },
              // Widget 级共享轴切换器（§9.3#2「AnimatedSwitcher + layout delta」
              // 手段的现成语义组件）：以日期为 key 换 child 即触发；时长/曲线/
              // 降级全部取 MotionConfig token，本页不写裸时长（§8.2/§9.2）。
              // 卡片 FLIP 位置保持（layout delta）随转场 #2 完整实现接入。
              child: SlimcaSharedAxisSwitcher(
                child: _CardWall(
                  key: wallKey,
                  date: formatCalendarDay(selectedDate),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 日期大字（§3.2「日期大字」、§9.3 转场 #1 冷启动 spring 展开）。
///
/// TweenAnimationBuilder 以 easeOutBack 近似 spring 展开一次（≤400ms 预算，
/// §9.3），仅首帧播放、切日不重播——切日过渡由卡片墙 AnimatedSwitcher 承担。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400), // §9.3 转场 #1 上限
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        // easeOutBack 会过冲 >1：透明度必须钳到 [0,1]（Flutter 调试断言）。
        opacity: clampDouble(t, 0.0, 1.0),
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '${date.month}月${date.day}日',
            style: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            weekdays[date.weekday - 1],
            style: textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 周历条：横滑选日（§3.2「日期大字+周历条」）。
///
/// 展示选中日期所在周的 7 天（周一为起点）；点选任意日切换当日视图。
/// 无限横滑翻周与月历下钻（§3.2 月历下钻，Container Transform）随 W2+ 接入。
class _WeekStrip extends ConsumerWidget {
  const _WeekStrip({required this.selected});

  final DateTime selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final now = SelectedDate.normalizeDate(DateTime.now());
    final days = SelectedDate.weekOf(selected);
    const weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(child: Builder(builder: (context) {
            final day = days[i];
            final isSelected = day == selected;
            final isToday = day == now;
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: i == 6 ? 0 : 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => ref.read(selectedDateProvider.notifier).select(day),
                child: AnimatedContainer(
                  duration: MotionConfig.of(context).durM, // §9.2 dur.m
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        weekdayLabels[i],
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isSelected ? cs.onPrimaryContainer : null,
                            ),
                      ),
                      const SizedBox(height: 4),
                      // 今日指示点：帮助用户在周历上锚定「今天」。
                      SizedBox(
                        width: 4,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isToday
                                ? cs.primary
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          })),
      ],
    );
  }
}

/// 卡片墙（§3.2：热量环/支出/运动/待办/存钱进度 + 今日记录）。
///
/// - 数据：明细行 join 流实时聚合（dashboardDayProvider，§6.1 原则 3）；
/// - loading/error 渲染零值空态（无 spinner，§2.3 步 0）；
/// - 每卡按 §9.3#1 级联上浮（SlimcaStaggerItem；切日随墙重建重播，W2 口径）。
class _CardWall extends ConsumerWidget {
  const _CardWall({super.key, required this.date});

  /// 归属日 `yyyy-MM-dd`（§5.1）。
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final day = ref.watch(dashboardDayProvider(date)).value ??
        const DashboardDay.zero();
    final todos = ref.watch(dashboardTodosProvider(date)).value ??
        DashboardTodoCounts.empty;
    final budget = ref.watch(dailyBudgetProvider(date)).value ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SlimcaStaggerItem(
          index: 0,
          child: _CalorieRingCard(day: day, budget: budget),
        ),
        const SizedBox(height: 12),
        // 支出/运动两卡等高并排：本卡片墙位于 ListView（子项高度无界）内，
        // Row 直接 stretch 会拿到无限高度而布局崩溃，故 IntrinsicHeight 先取
        // 双卡固有高度作为有界约束（§3.2 卡片墙）。
        SlimcaStaggerItem(index: 1, child: _SpendBurnRow(day: day)),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 2, child: _TodoCard(todos: todos)),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 3, child: _SavingsCard(date: date)),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 4, child: _TodayEntriesCard(day: day)),
        const SizedBox(height: 16),
        SlimcaStaggerItem(
          index: 5,
          child: day.entries.isEmpty ? const _EmptyHint() : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 支出/运动双卡行：IntrinsicHeight 内 stretch，保证两卡等高（§3.2）。
class _SpendBurnRow extends StatelessWidget {
  const _SpendBurnRow({required this.day});

  final DashboardDay day;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _SpendCard(day: day)),
          const SizedBox(width: 12),
          Expanded(child: _BurnCard(day: day)),
        ],
      ),
    );
  }
}

/// 热量环卡：摄入/消耗/净 + 预算余（§3.2 卡片墙第 1 项）。
///
/// 预算已设置（kcal 账本 daily 预算，§5.4⑥）→ ui_kit 语义组件
/// SlimcaCalorieRing（spring.soft sweep 推进，§9.2/§9.3#4）；预算未设置
/// （W5-6 才有每日目标 UI，§11）→ 零进度轨道环 + 净热量数字，不用满环
/// 假装超支（§3.2「超支/超额即时反馈」语义诚实）。
class _CalorieRingCard extends StatelessWidget {
  const _CalorieRingCard({required this.day, required this.budget});

  final DashboardDay day;

  /// kcal 每日目标；0=未设置（§5.4⑥ daily 预算）。
  final int budget;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final center = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${day.netKcal}', style: textTheme.titleLarge),
        Text('净 kcal', style: textTheme.labelSmall),
      ],
    );

    final Widget ring = budget > 0
        ? SlimcaCalorieRing(
            kcalIn: day.kcalIn,
            kcalOut: day.kcalOut,
            budget: budget,
            size: 88,
            strokeWidth: 8,
            center: center,
          )
        : SizedBox(
            width: 88,
            height: 88,
            child: CustomPaint(
              painter: _ProgressRingPainter(
                trackColor: cs.surfaceContainerHighest,
                progressColor: cs.primary,
                progress: 0, // 预算未设置：不推 sweep，仅轨道（§3.2）
              ),
              child: Center(child: center),
            ),
          );

    return _DashboardCard(
      child: Row(
        children: [
          ring,
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('热量', style: textTheme.titleMedium),
                const SizedBox(height: 6),
                _MetricLine(label: '摄入', value: '${day.kcalIn} kcal'),
                _MetricLine(label: '消耗', value: '${day.kcalOut} kcal'),
                // 净热量口径（§3.5 健身手动记录进净热量：净 = 摄入 − 消耗，
                // W5-6 核对标注；burn 行已并入下方 kcalOut 求和）。
                Text(
                  '净 = 摄入 − 消耗',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                _MetricLine(
                  label: '预算',
                  value: budget > 0
                      // 预算余 = 目标 − 净（kcal 账本：吃=支出、运动=再入账，§2.1③）
                      ? '余 ${budget - day.netKcal} kcal'
                      : '未设置',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日支出卡：支出与预算余（§3.2 卡片墙第 2 项；暖橘=金额，§8.2）。
class _SpendCard extends StatelessWidget {
  const _SpendCard({required this.day});

  final DashboardDay day;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日支出', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(yuanFromMinor(day.spendMinor), style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '预算余 —（先去设置每日目标）',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 运动条卡：MET 估算消耗（§3.5 手动记录；±20% 口径标注，§3.5 误差口径）。
class _BurnCard extends StatelessWidget {
  const _BurnCard({required this.day});

  final DashboardDay day;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日消耗', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('${day.kcalOut} kcal', style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '手动记录运动（MET 估算 ±20%）',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 待办卡：3 条预览（§3.2 卡片墙第 4 项、§3.6 待办基础）。
class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.todos});

  final DashboardTodoCounts todos;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('待办', style: textTheme.titleMedium),
              Text(
                '${todos.done}/${todos.total}',
                style: textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            todos.total == 0
                ? '今日暂无待办。完成待办将计入当日全貌。'
                : '${todos.done} 项已完成，共 ${todos.total} 项（§5.5⑩）',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 存钱进度卡（§3.2 卡片墙第 5 项「上线后自动接入」、§3.6 存钱目标 P1
/// 留存钩子、§5.6⑬ savings_progress 快照、§11.2 W13 任务 2）。
///
/// - 数据：day_summary 投影流直读（dashboardSavingsProgressProvider，
///   快照直出、零业务查询 §3.2；写路径同事务联动 → 投币后数字即时变化）；
/// - 空态：无当日有效目标（快照 NULL/空 Map）→ 引导去计划页建档
///   （任务 2「空态=无目标引导创建」）；多目标渲染聚合计（Σ贡献/Σ目标）。
class _SavingsCard extends ConsumerWidget {
  const _SavingsCard({required this.date});

  /// 归属日 `yyyy-MM-dd`（§5.1）。
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final progress = ref.watch(dashboardSavingsProgressProvider(date)).value ??
        const <String, db.SavingsProgressEntry>{};

    if (progress.isEmpty) {
      return _DashboardCard(
        child: Row(
          children: [
            Icon(
              Icons.savings_outlined,
              color: tokens.onSurfaceMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('存钱', style: textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '还没有存钱目标。去「计划」页新建目标，'
                    '投币打卡攒起来（§3.6 存钱目标）',
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 多目标聚合计（§5.6⑬ 快照为多目标 JSON：Σ贡献 / Σ目标）。
    var contributed = 0;
    var target = 0;
    for (final entry in progress.values) {
      contributed += entry.contributedMinor;
      target += entry.targetMinor;
    }
    final percent = target <= 0
        ? 0
        : ((contributed / target).clamp(0.0, 1.0) * 100).round();

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('存钱', style: textTheme.titleMedium),
              if (progress.length > 1)
                Text(
                  '${progress.length} 个目标',
                  style: textTheme.labelMedium?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                yuanFromMinor(contributed),
                style: textTheme.headlineSmall?.copyWith(
                  color: tokens.moneyOut,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '/ ${yuanFromMinor(target)}（$percent%）',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条随快照流推进（投币打卡→写事务重算快照→本卡即时变化，
          // 任务 5「插目标+贡献→卡片数字变化」）。
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: target <= 0 ? 0.0 : contributed / target),
              duration: MotionConfig.of(context).durM,
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: clampDouble(value, 0.0, 1.0),
                minHeight: 6,
                backgroundColor: tokens.outline,
                valueColor: AlwaysStoppedAnimation<Color>(tokens.moneyOut),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今日记录卡（§11 W2 手动记账全链路的流水反馈面）。
///
/// - 点条目 → 录入抽屉编辑态（预填+修正链落库，§6.5 金额不可变）；
/// - 删除 → 软删墓碑（§5.1/§6.5），聚合流即时重发（明细流直驱）；
/// - 完整流水列表/分类/预算入口在 /ledger（§4.3，W2+ 逐条接入）。
class _TodayEntriesCard extends ConsumerWidget {
  const _TodayEntriesCard({required this.day});

  final DashboardDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (day.entries.isEmpty) {
      return const SizedBox.shrink(); // 空日不渲染（§2.3 零等待空屏）
    }
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日记录', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final view in day.entries) _EntryTile(view: view),
        ],
      ),
    );
  }
}

/// 单条记录行：kind 图标 + 标题 + 金额/热量摘要 + 编辑/删除。
class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.view});

  final DashboardEntryView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        _kindIcon(view.kind),
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: Text(
        view.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodyMedium,
      ),
      subtitle: Text(
        _summaryOf(view),
        style: textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      // 编辑：弹簧抽屉预填原事件；保存走修正链（§6.5 金额不可变→correction 行）。
      // W3-4 收敛：抽屉 = feature_capture CapturePage（§10.4 唯一录入 UI）。
      onTap: () => showCaptureSheet(
        context,
        seed: CaptureSeed(editEntryId: view.entryId),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: '删除（软删墓碑）',
        // §5.1 删除行/§6.5：软删墓碑拒绝复活；聚合流即时重发。
        onPressed: () {
          final clock = ref.read(hlcClockProvider);
          ref
              .read(entryRepositoryProvider)
              .softDelete(view.entryId, hlc: clock.now().format());
        },
      ),
    );
  }

  String _summaryOf(DashboardEntryView view) {
    final parts = <String>[];
    if (view.kcalIn > 0) parts.add('摄入 ${view.kcalIn} kcal');
    if (view.kcalOut > 0) parts.add('消耗 ${view.kcalOut} kcal');
    if (view.spendMinor > 0) parts.add(yuanFromMinor(view.spendMinor));
    if (view.incomeMinor > 0) parts.add('收入 ${yuanFromMinor(view.incomeMinor)}');
    return parts.isEmpty ? '仅记录描述' : parts.join(' · ');
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
class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          '记一件事，钱和卡路里一起入账',
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '点击底部「+」开始第一条记录',
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 仪表盘卡片容器：统一圆角与内边距（卡片墙视觉一致性，§3.2）。
class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // §8.2 语义 token：卡片底色取 SlimcaTheme.surfaceCard（三层架构组件层纪律）。
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

/// 卡片内指标行。
class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodyMedium),
          Text(value, style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          )),
        ],
      ),
    );
  }
}

/// 零依赖进度环：轨道圆 + 进度弧（§9.3 转场 #4 环 sweep 的 W2 降级版）。
///
/// 仅用于「预算未设置」态（W5-6 每日目标接入后统一走 SlimcaCalorieRing
/// 语义组件；绘制保持 CustomPainter，便于后续替换，§10.1 动效选型）。
class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.trackColor,
    required this.progressColor,
    required this.progress,
  });

  final Color trackColor;
  final Color progressColor;
  final double progress; // 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = trackColor;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 8) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(rect, -3 * 3.14159265 / 4, 3 * 3.14159265 / 2 * progress,
        false, arc);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
