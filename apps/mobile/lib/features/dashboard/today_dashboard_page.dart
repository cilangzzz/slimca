import 'dart:async';
import 'dart:ui' show clampDouble;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:feature_ledger/feature_ledger.dart' show LedgerBudgetItem;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'package:feature_capture/feature_capture.dart'
    show CaptureSeed, showCaptureSheet;

import '../../app/providers.dart';
import '../../common/format.dart';
import '../ledger/ledger_state.dart' show ledgerCategoryFilterProvider;
import '../workout/workout_session_controller.dart'
    show workoutSessionProvider;
import 'dashboard_state.dart';

/// 训练中态卡·剩余秒测试锚点（§11.2 W14 任务 4）。
const Key workoutCardRestKey = ValueKey('workout_card_rest_remaining');

/// 训练中态卡·跳过休息测试锚点。
const Key workoutCardSkipRestKey = ValueKey('workout_card_skip_rest');

/// 训练中态卡·结束并保存测试锚点。
const Key workoutCardEndKey = ValueKey('workout_card_end_save');

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
  /// 首页日历展开态（受控；SlimcaCalendar 内垂直手势/收起箭头回发，§3.2）。
  bool _calendarExpanded = false;

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    // 月格色点（§3.2 Compact：一点=有记录；day_summary 投影 watch 直出）。
    final recordedDays =
        ref.watch(recordedDaysProvider).value ?? const <String>{};
    final wallKey = ValueKey<DateTime>(selectedDate);
    final spacing = context.spacing;
    final sizes = context.sizes;

    return Scaffold(
      // 首页 AppBar 不带产品名标题（用户拍板：去除「Slimca」字样，
      // 状态栏下直接呈现卡片墙）。
      appBar: AppBar(centerTitle: false),
      body: SafeArea(
        child: ListView(
          // 底部留白（底栏重设计拍板（《UI-规范与重设计》§2.2 增补段））：清中央花瓣按钮凸出栏体
          // （cradle 间隙约 34）+ 呼吸——space600+rowSingleLine+space200
          // 组合表达（§2.2 禁裸尺寸，不引入裸值）。
          padding: EdgeInsets.fromLTRB(
            spacing.space200,
            spacing.space100,
            spacing.space200,
            spacing.space600 + sizes.rowSingleLine + spacing.space200,
          ),
          children: [
            _DateHeader(date: selectedDate),
            const SizedBox(height: 12),
            // 首页日历（§3 定稿组合容器）：折叠=周条，垂直下拉/箭头展开
            // 月网格选择具体日期（用户拍板 2026-11-19）；选中日单一真值
            // selectedDateProvider（§3.1④）。
            SlimcaCalendar(
              selectedDate: selectedDate,
              onDaySelected: (day) =>
                  ref.read(selectedDateProvider.notifier).select(day),
              recordCounts: <DateTime, int>{
                for (final String date in recordedDays)
                  DateTime.parse(date): 1,
              },
              expanded: _calendarExpanded,
              onExpandedChanged: (bool expanded) =>
                  setState(() => _calendarExpanded = expanded),
            ),
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
/// TweenAnimationBuilder 以弹簧展开一次（≤400ms 预算，§9.3），仅首帧播放、
/// 切日不重播——切日过渡由卡片墙 AnimatedSwitcher 承担。
///
/// §5 审计 #3 修正：原实现裸值 `Duration(milliseconds: 400)` + `easeOutBack`
/// 违反 §9.2「所有动效只引用 token 不写裸值」lint 纪律——改读
/// `MotionConfig.of(context)`，时长/曲线一体挂 springSoft token（§9.2
/// spring.soft 400ms ζ0.85 容器变形档；SpringCurve 为解析弹簧响应，
/// 欠阻尼轻微过冲=spatial 类允许过冲，§1.2 判定线）。
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final motion = MotionConfig.of(context);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion.springSoft.settleDuration, // §9.2 spring.soft
      curve: motion.springSoft.curve,
      builder: (context, t, child) => Opacity(
        // 欠阻尼弹簧过冲 >1：透明度必须钳到 [0,1]（Flutter 调试断言）。
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
        // W14 训练中态卡（§11.2 W14 任务 4：当日进行中训练显示剩余休息秒，
        // 读 workoutSessionProvider Riverpod 状态；无训练/非当日不占位）。
        SlimcaStaggerItem(index: 1, child: _WorkoutCard(date: date)),
        const SizedBox(height: 12),
        // 支出/运动两卡等高并排：本卡片墙位于 ListView（子项高度无界）内，
        // Row 直接 stretch 会拿到无限高度而布局崩溃，故 IntrinsicHeight 先取
        // 双卡固有高度作为有界约束（§3.2 卡片墙）。
        SlimcaStaggerItem(
          index: 2,
          child: _SpendBurnRow(day: day, date: date),
        ),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 3, child: _TodoCard(todos: todos)),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 4, child: _SavingsCard(date: date)),
        const SizedBox(height: 12),
        SlimcaStaggerItem(index: 5, child: _TodayEntriesCard(day: day)),
        const SizedBox(height: 16),
        SlimcaStaggerItem(
          index: 6,
          child: day.entries.isEmpty ? const _EmptyHint() : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// 训练中态卡（§11.2 W14 任务 4「训练中态卡（当日进行中训练显示剩余休息
/// 秒，读 Riverpod provider）」、§3.2 卡片墙「当日全貌」的瞬时项）。
///
/// - 显示条件：有进行中训练（workoutSessionProvider）且其归属日=当前选中日
///   （§3.2 一切围绕日期）；否则不占位（SizedBox.shrink，§2.3 零等待空屏）；
/// - 剩余休息秒：绝对时刻 + 注入时钟（workoutClockProvider）即时重算——
///   本卡 Timer.periodic(1s) 只做渲染节奏与到点探询（syncRest），秒值语义
///   不依赖真实计时器（W14 任务 5 测试经注入时钟 + pump 推进）；
/// - 「结束并保存」走控制器 endWorkout（落库 §6.2 + workout_completed +
///   KeepAwake off + 通知 cancel，W14 任务 5 断言 off）。
class _WorkoutCard extends ConsumerStatefulWidget {
  const _WorkoutCard({required this.date});

  /// 归属日 `yyyy-MM-dd`（§5.1；=卡片墙当日）。
  final String date;

  @override
  ConsumerState<_WorkoutCard> createState() => _WorkoutCardState();
}

class _WorkoutCardState extends ConsumerState<_WorkoutCard> {
  Timer? _ticker;
  int _lastRestSeconds = -1;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final nowMs = ref.read(workoutClockProvider)().millisecondsSinceEpoch;
    // 到点探询（业务推进经控制器，注入时钟判定；未到点 no-op 不重发）。
    ref.read(workoutSessionProvider.notifier).syncRest(nowMs: nowMs);
    final session = ref.read(workoutSessionProvider);
    final seconds = session?.remainingRestSeconds(nowMs) ?? -1;
    if (seconds != _lastRestSeconds) {
      _lastRestSeconds = seconds;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(workoutSessionProvider);
    if (session == null || session.date != widget.date) {
      return const SizedBox.shrink();
    }
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final nowMs =
        ref.watch(workoutClockProvider)().millisecondsSinceEpoch;
    final resting = session.isResting;
    final remaining = session.remainingRestSeconds(nowMs);

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.fitness_center, color: tokens.kcalOut),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '训练中 · ${session.planName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
              ),
              Text(
                '已完成 ${session.sets.length} 组',
                style: textTheme.labelMedium?.copyWith(
                  color: tokens.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (resting)
            // 剩余休息秒（W14 任务 4 核心验收：注入时钟对 rest_ends_at 的
            // 即时重算；跳过休息直开下一组）。
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: tokens.kcalOut.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text(
                    '组间休息',
                    style: textTheme.labelMedium?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$remaining',
                    key: workoutCardRestKey,
                    style: textTheme.headlineSmall?.copyWith(
                      color: tokens.kcalOut,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '秒后下一组',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.onSurfaceMuted,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    key: workoutCardSkipRestKey,
                    onPressed: () => ref
                        .read(workoutSessionProvider.notifier)
                        .skipRest(),
                    child: const Text('跳过'),
                  ),
                ],
              ),
            )
          else
            Text(
              session.allDone
                  ? '全部组完成 · 结束并保存入账（§5.5⑦）'
                  : '当前：${session.currentExercise.name}'
                      ' · 第 ${session.setNo}/${session.currentExercise.sets} 组',
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            key: workoutCardEndKey,
            onPressed: () => ref
                .read(workoutSessionProvider.notifier)
                .endWorkout(save: true),
            child: const Text('结束并保存'),
          ),
        ],
      ),
    );
  }
}

/// 支出/运动双卡行：IntrinsicHeight 内 stretch，保证两卡等高（§3.2）。
class _SpendBurnRow extends StatelessWidget {
  const _SpendBurnRow({required this.day, required this.date});

  final DashboardDay day;

  /// 归属日 `yyyy-MM-dd`（§5.1；支出卡读当日预算快照用）。
  final String date;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _SpendCard(day: day, date: date)),
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

/// 今日支出卡（§3.2 卡片墙第 2 项；暖橘=金额，§8.2）。
///
/// W15 任务 2「支出卡接预算快照 v2」：
/// - 数据=day_summary.budget_snapshot 直读（dashboardBudgetSnapshotProvider，
///   §5.6⑬ 快照直出、零业务查询；写路径同事务重算→即时重发）；
/// - 余/超支状态色已有语义 token：余=tokens.success、超支=tokens.danger
///   （§3.2「超支/超额即时反馈」、§8.2 组件层禁裸色值）；
/// - per-分类明细入口：分类预算行与「分类明细」跳账本 Tab 分类筛选
///   （ledgerCategoryFilterProvider 预选 + go('/ledger')，§3.4 分类筛选）；
/// - 未设预算 → 引导去 /ledger/budgets（§4.3）。
class _SpendCard extends ConsumerWidget {
  const _SpendCard({required this.day, required this.date});

  final DashboardDay day;

  /// 归属日 `yyyy-MM-dd`（§5.1）。
  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    final textTheme = Theme.of(context).textTheme;
    final budgets =
        ref.watch(dashboardBudgetSnapshotProvider(date)).value ??
            const <LedgerBudgetItem>[];
    final names =
        ref.watch(categoryNamesProvider).value ?? const <String, String>{};

    // money 账本总预算（§5.4⑥ category_id NULL=总预算；kcal 项归热量环；
    // 周期限 daily——月度项随 v2 快照同入列表但不进「每日余量」行，§5.4⑥）。
    LedgerBudgetItem? spendBudget;
    for (final budget in budgets) {
      if (!budget.isKcal && !budget.isMonthly && budget.categoryId == null) {
        spendBudget = budget;
        break;
      }
    }
    final categoryBudgets = budgets
        .where((budget) =>
            !budget.isKcal && !budget.isMonthly && budget.categoryId != null)
        .toList(growable: false);

    // 跳账本 Tab 分类筛选（W15 per-分类明细入口；跨 Tab go 保分支栈）。
    void openCategoryFilter(String? categoryId) {
      ref.read(ledgerCategoryFilterProvider.notifier).select(categoryId);
      GoRouter.of(context).go('/ledger');
    }

    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日支出', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text(yuanFromMinor(day.spendMinor), style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          if (spendBudget == null)
            // 未设预算：引导去预算设置页（§4.3 /ledger/budgets）。
            InkWell(
              key: const Key('dashboard_budget_hint'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => GoRouter.of(context).push('/ledger/budgets'),
              // §5 审计 #5 修正：文本行命中 ≥48×48（kMinInteractiveDimension
              // =48dp 官方常量，§1.4 触碰目标）。
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                alignment: Alignment.centerLeft,
                child: Text(
                  '预算余 —（点此去「预算设置」）',
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.onSurfaceMuted,
                  ),
                ),
              ),
            )
          else ...[
            // 余/超支状态色（§3.2；remaining<0 = 超支标红）。
            Text(
              spendBudget.remaining >= 0
                  ? '预算余 ${yuanFromMinor(spendBudget.remaining)}'
                  : '超支 ${yuanFromMinor(-spendBudget.remaining)}',
              key: const Key('dashboard_budget_state'),
              style: textTheme.bodySmall?.copyWith(
                color: spendBudget.remaining >= 0
                    ? tokens.success
                    : tokens.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
            // per-分类预算行（≤3 条，超支优先；点行跳该分类筛选）。
            for (final budget in _prioritized(categoryBudgets))
              InkWell(
                key: Key('dashboard_budget_category_${budget.categoryId}'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => openCategoryFilter(budget.categoryId),
                // §5 审计 #5 修正：原 vertical padding 2 → 命中 <48dp；
                // 包 48dp 最小命中容器（minTouchTarget 落法，§1.4）。
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: kMinInteractiveDimension,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${names[budget.categoryId] ?? "分类"} '
                    '${budget.remaining >= 0
                        ? "余 ${yuanFromMinor(budget.remaining)}"
                        : "超支 ${yuanFromMinor(-budget.remaining)}"}',
                    style: textTheme.bodySmall?.copyWith(
                      color: budget.remaining >= 0
                          ? tokens.success
                          : tokens.danger,
                    ),
                  ),
                ),
              ),
            // 分类明细入口：跳账本 Tab 分类筛选条（§3.4）。
            InkWell(
              key: const Key('dashboard_spend_category_entry'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => openCategoryFilter(null),
              // §5 审计 #5 修正：命中 ≥48×48（同上 minTouchTarget 落法）。
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: kMinInteractiveDimension,
                ),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '分类明细',
                      style: textTheme.bodySmall?.copyWith(
                        color: tokens.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: tokens.primary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 分类预算行排序：超支在前、余升序（最紧的先露出；§3.2 卡片信息密度）。
  List<LedgerBudgetItem> _prioritized(List<LedgerBudgetItem> budgets) {
    final sorted = [...budgets]..sort((a, b) {
      final aOver = a.remaining < 0;
      final bOver = b.remaining < 0;
      if (aOver != bOver) return aOver ? -1 : 1;
      return a.remaining.compareTo(b.remaining);
    });
    return sorted.take(3).toList(growable: false);
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
        // 空态可点（修复「文案说去计划页却不可点」缺口）：整卡跳计划 Tab
        // 存钱卡（唯一建档入口）。
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/plan'),
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
                      '还没有存钱目标。去「计划」页新建目标，投币打卡攒起来',
                      style: textTheme.bodyMedium?.copyWith(
                        color: tokens.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.onSurfaceMuted),
            ],
          ),
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
/// - 删除 → **snackbar undo（§4.3「可撤销动作不用 alert、常规单条删除
///   走 snackbar undo」）**——删除请求先做乐观移除（页面态），SnackBar
///   「撤销」可撤回；未撤销在 SnackBar 关闭时才提交软删墓碑。为什么是
///   「延迟提交」而非「复活墓碑」：§6.5 明确墓碑拒绝复活（删后编辑保持
///   删除胜出），undo 只在墓碑落库前撤回请求，同步语义零特例；
/// - 完整流水列表/分类/预算入口在 /ledger（§4.3，W2+ 逐条接入）。
class _TodayEntriesCard extends ConsumerStatefulWidget {
  const _TodayEntriesCard({required this.day});

  final DashboardDay day;

  @override
  ConsumerState<_TodayEntriesCard> createState() => _TodayEntriesCardState();
}

class _TodayEntriesCardState extends ConsumerState<_TodayEntriesCard> {
  /// 待提交软删的事件 id 集（乐观移除中；undo 撤回/提交软删后移除）。
  final Map<String, _PendingDelete> _pendingDeletes = <String, _PendingDelete>{};

  /// 发起删除请求（§4.3 undo）：乐观移除 + SnackBar 撤销入口；SnackBar
  /// 关闭时按关闭原因收尾——「action」=用户已撤销，不提交；其余（超时/
  /// 滑走/被新 SnackBar 顶替）=按「未撤销=执行」提交软删（仓库捕获于请求
  /// 时刻，页面态销毁亦照常提交）。
  void _requestDelete(DashboardEntryView view) {
    final repo = ref.read(entryRepositoryProvider);
    final clock = ref.read(hlcClockProvider);
    setState(() {
      _pendingDeletes[view.entryId] = _PendingDelete(repo: repo, clock: clock);
    });
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除「${view.title}」'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            if (!mounted) return;
            setState(() => _pendingDeletes.remove(view.entryId));
          },
        ),
      ),
    );
    controller.closed.then((SnackBarClosedReason reason) {
      // 撤销路径：SnackBar 因 action 关闭，删除请求已撤回，不提交墓碑。
      if (reason == SnackBarClosedReason.action) return;
      final _PendingDelete? pending = _pendingDeletes.remove(view.entryId);
      if (pending == null) return;
      // §5.1 删除行/§6.5：软删墓碑；聚合流即时重发（乐观移除已先行）。
      unawaited(
        pending.repo.softDelete(view.entryId, hlc: pending.clock.now().format()),
      );
    });
  }

  @override
  void dispose() {
    // 页面态销毁（切日重建卡片墙/关页）时仍有未决删除：按「未撤销=执行」
    // 收尾，避免删除意图丢失（§4.3 undo 语义；仓库/时钟已在请求时刻捕获）。
    for (final MapEntry<String, _PendingDelete> entry
        in _pendingDeletes.entries) {
      unawaited(entry.value.repo
          .softDelete(entry.key, hlc: entry.value.clock.now().format()));
    }
    _pendingDeletes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 乐观移除：待提交软删的条目暂不入列表（undo 后随 setState 回归）。
    final entries = widget.day.entries
        .where((view) => !_pendingDeletes.containsKey(view.entryId))
        .toList(growable: false);
    if (entries.isEmpty && _pendingDeletes.isEmpty) {
      return const SizedBox.shrink(); // 空日不渲染（§2.3 零等待空屏）
    }
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日记录', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final view in entries)
            _EntryTile(view: view, onRequestDelete: _requestDelete),
        ],
      ),
    );
  }
}

/// 待提交软删的捕获（仓库/时钟于请求时刻定格，SnackBar 收尾或页面态销毁
/// 时提交——不依赖 context/widget 存活）。
class _PendingDelete {
  const _PendingDelete({required this.repo, required this.clock});

  final EntryRepository repo;
  final HlcClock clock;
}

/// 单条记录行：kind 图标 + 标题 + 金额/热量摘要 + 编辑/删除。
///
/// §5 审计 #4 修正：dense → 标准 56/72 行高（M3 ListTile 源码口径，§1.5/
/// §4.2 行规格）；删除走 snackbar undo（§4.3，见 [_TodayEntriesCard]）。
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.view, required this.onRequestDelete});

  final DashboardEntryView view;

  /// 删除请求回调（由卡片持有 undo 状态并延迟提交软删，§4.3）。
  final void Function(DashboardEntryView view) onRequestDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
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
        tooltip: '删除记录',
        // §4.3：删除发 undo 请求（乐观移除+SnackBar 撤销），未撤销才落墓碑。
        onPressed: () => onRequestDelete(view),
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
