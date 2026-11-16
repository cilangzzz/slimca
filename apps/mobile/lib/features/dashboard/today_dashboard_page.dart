import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import 'dashboard_state.dart';

/// 日期仪表盘（§3.2，W2 主线的骨架版：日期大字 + 周历条 + 卡片墙空态，§11 W2）。
///
/// 设计决策：
/// - 本页是**唯一首页**（§4.1 原则 1、§3.2「唯一首页」），无第二个首页；
/// - 空态即最终形态的占位：卡片墙结构（热量环/支出/运动/待办/存钱）与
///   §3.2 卡片墙清单一一对应，W2 起由 day_summary 快照直出填数（§5.6 ⑬，
///   冷启动首帧零业务查询、无 spinner，§2.3 步 0 / §3.2 快照直出）；
/// - 语义色暂用 ColorScheme 角色，SlimcaTheme 语义 token（kcalIn/moneyOut 等，
///   §8.2）随 ui_kit 落地后整体替换，替换点集中在各卡片 build 内。
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
            // 左右滑切日：共享轴转场 280ms（§3.2、§9.2 dur.l、§9.3 转场 #2——
            // W2 起补方向感知与卡片 FLIP 位置保持）。
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
              child: AnimatedSwitcher(
                duration: sharedAxisTransitionDuration(context),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                // 以日期为 key：切日触发共享轴式过渡，卡片墙不整体闪烁重建。
                child: _CardWall(key: wallKey),
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
    final weekdays = const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400), // §9.3 转场 #1 上限
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
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
                  duration: const Duration(milliseconds: 180), // §9.2 dur.m
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

/// 卡片墙空态（§3.2 卡片墙：热量环/支出/运动/待办/存钱进度）。
///
/// W1 骨架为全零空态 + 「记录后自动更新」提示；W2 接入 day_summary 后
/// 本组件改为消费投影快照（首帧直出、零业务查询，§3.2 快照直出）。
/// 卡片墙整体上浮（§9.3 转场 #1 的 80ms 级联 stagger 于 W2 接入
/// MotionConfig token 后逐卡展开，骨架期整体淡入）。
class _CardWall extends StatelessWidget {
  const _CardWall({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        _CalorieRingCard(),
        SizedBox(height: 12),
        // 支出/运动两卡等高并排：Row 用 stretch 拉齐双卡高度。注意本卡片墙
        // 位于 ListView（子项高度无界）内，Row 直接 stretch 会拿到无限高度
        // 而布局崩溃（BoxConstraints forces an infinite height），故用
        // IntrinsicHeight 先取双卡固有高度作为有界约束（§3.2 卡片墙）。
        _SpendBurnRow(),
        SizedBox(height: 12),
        _TodoCard(),
        SizedBox(height: 12),
        _SavingsCard(),
        SizedBox(height: 16),
        _EmptyHint(),
      ],
    );
  }
}

/// 支出/运动双卡行：IntrinsicHeight 内 stretch，保证两卡等高（§3.2）。
class _SpendBurnRow extends StatelessWidget {
  const _SpendBurnRow();

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: const [
          Expanded(child: _SpendCard()),
          SizedBox(width: 12),
          Expanded(child: _BurnCard()),
        ],
      ),
    );
  }
}

/// 热量环卡：摄入/消耗/净 + 预算余（§3.2 卡片墙第 1 项）。
///
/// 空态：环为零进度、数字为 0、预算未设置。环的 sweep 填充动效与
/// 「今日还能吃」滚动数字随 W2 落库链路接入（§9.3 转场 #4/#5）。
class _CalorieRingCard extends StatelessWidget {
  const _CalorieRingCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _DashboardCard(
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: CustomPaint(
              painter: _ProgressRingPainter(
                trackColor: cs.surfaceContainerHighest,
                progressColor: cs.primary,
                progress: 0, // 空态零进度；W2 起由 day_summary 驱动（§5.6 ⑬）
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('0', style: textTheme.titleLarge),
                    Text('净 kcal', style: textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('热量', style: textTheme.titleMedium),
                const SizedBox(height: 6),
                _MetricLine(label: '摄入', value: '0 kcal'),
                _MetricLine(label: '消耗', value: '0 kcal'),
                _MetricLine(label: '预算', value: '未设置'),
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
  const _SpendCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日支出', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('¥0.00', style: textTheme.headlineSmall),
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
  const _BurnCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('今日消耗', style: textTheme.labelMedium),
          const SizedBox(height: 8),
          Text('0 kcal', style: textTheme.headlineSmall),
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
  const _TodoCard();

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
                '0/0',
                style: textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '今日暂无待办。完成待办将计入当日全貌。',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 存钱进度卡（§3.2 卡片墙第 5 项「上线后自动接入」、§3.6 存钱目标 P1）。
class _SavingsCard extends StatelessWidget {
  const _SavingsCard();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return _DashboardCard(
      child: Row(
        children: [
          Icon(
            Icons.savings_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '存钱目标上线后自动接入卡片墙（§3.2，P1）',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
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
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      // W2 起替换为 SlimcaTheme.surfaceCard 语义 token（§8.2）。
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
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

/// 零依赖进度环：轨道圆 + 进度弧（§9.3 转场 #4 环 sweep 的骨架版绘制器）。
///
/// W2 起接入 day_summary 数据与 sweep 弹簧动画（spring.soft，§9.2）；
/// 绘制保持 CustomPainter，便于替换为 ui_kit 的语义组件（§10.1 动效选型）。
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
      ..strokeWidth = 10
      ..color = trackColor;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 10) / 2;
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
