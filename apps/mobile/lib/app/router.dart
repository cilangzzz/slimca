import 'dart:async';

import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:feature_capture/feature_capture.dart' show CaptureSeed;
import 'package:feature_plan/feature_plan.dart' show FitnessPlanPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart' show SlimcaSharedAxisPage;

import '../features/capture/capture_channels_sheet.dart';
import '../features/dashboard/dashboard_state.dart';
import '../features/dashboard/today_dashboard_page.dart';
import '../features/ledger/budget_settings_page.dart';
import '../features/ledger/ledger_page.dart';
import '../features/plan/fitness_log_page.dart';
import '../features/plan/plan_page.dart';
import '../features/settings/settings_page.dart';
import '../features/stats/stats_report_screen.dart';
import '../features/workout/workout_runner_page.dart';
import '../telemetry/telemetry.dart';
import 'providers.dart';

/// 全局路由表（§4.3 路由表与页面清单）。
///
/// 设计决策：
/// - `StatefulShellRoute.indexedStack` 承载 4 Tab，各 Tab 独立导航栈且保留
///   滚动位置（§4.1 原则 3「回退保留滚动位置」、§4.3 实现注记）；
/// - Tab 结构与命名严格按 §4.2：今天 `/`、账本 `/ledger`、计划 `/plan`、
///   我的 `/settings`；中央悬浮「+」为录入抽屉（非路由页面，§4.2 capture）；
/// - W1 骨架挂 4 个 Tab 根页面；W2 起今天 Tab 渲染真仪表盘、中央「+」唤起
///   录入抽屉；W5-6：账本/计划 Tab 渲染真页（§11.1 W5-6「记账完整化」）、
///   计划挂健身手动记录子路由 `/plan/fitness`（§4.3 P1 路由，嵌套于 /plan
///   ——分支栈内 push，系统返回回计划页）；`/calendar`、`/entry/:id`、
///   `/ledger/*` 等子路由随 W2+ 逐条接入，接入时路由级转场一律注入自定义
///   `PageRouteBuilder`（§9.5 工程约束，共享轴/容器变换见 §9.3）。
final GoRouter slimcaRouter = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          SlimcaShell(navigationShell: navigationShell),
      branches: [
        // Tab 1 今天：日期仪表盘，唯一首页（§4.1 原则 1、§4.2）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const TodayDashboardPage(),
            ),
          ],
        ),
        // Tab 2 账本：流水列表（W5-6 真页）+分类管理+预算入口+统计入口（§4.2）。
        // W15：顶栏多账本切换器 + 分类筛选条（§11.2、§3.4 多账本/分类 P1）；
        // /ledger/budgets 子路由（§4.3 预算设置，分支栈内 push——底栏保持，
        // 路由级转场注入共享轴 PageRouteBuilder，§9.5）。
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ledger',
              builder: (context, state) => const LedgerPage(),
              routes: [
                GoRoute(
                  path: 'budgets',
                  pageBuilder: (context, state) => SlimcaSharedAxisPage(
                    name: state.matchedLocation,
                    builder: (_) => const BudgetSettingsPage(),
                  ),
                ),
              ],
            ),
          ],
        ),
        // Tab 3 计划：待办/健身/存钱/健身计划四卡（W5-6 真页 + W14 排期卡，
        // §4.2）+ 健身手动记录子路由（§4.3 /plan/fitness P1 路由，W5-6 接入）
        // + 训练中页子路由（§11.2 W14 任务 1/2：/plan/workout，排期卡
        // 「开始训练」置态后推入，分支栈内 push）。
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanPage(),
              routes: [
                GoRoute(
                  path: 'fitness',
                  builder: (context, state) => const FitnessLogPage(),
                ),
                GoRoute(
                  path: 'workout',
                  builder: (context, state) => const WorkoutRunnerPage(),
                ),
                // W14 健身计划模板管理（§11.2 W14 任务 1、§10.4 装配接入）：
                // feature_plan FitnessPlanPage——模板建档/编辑/删除+周排期
                // 日历+训练历史入口（壳内不重复建档 UI，计划卡「模板」进入）。
                GoRoute(
                  path: 'plans',
                  builder: (context, state) => const FitnessPlanPage(),
                ),
              ],
            ),
          ],
        ),
        // Tab 4 我的：主题/同步状态/AI 开关/数据导出/订阅（§4.2）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    // 统计报表（§4.3 /stats P1、W15 任务 1）：壳外全屏路由——周/月/年三档
    // + 钱-热量双轴联动的专注阅读面（返回回账本 Tab 栈）；页面本体=
    // feature_ledger ReportPage（W15），本路由只做壳层装配屏 + 转场注入
    // （共享轴 PageRouteBuilder，§9.5，§4.3 /stats 转场列）。
    GoRoute(
      path: '/stats',
      pageBuilder: (context, state) => SlimcaSharedAxisPage(
        name: state.matchedLocation,
        builder: (_) => const StatsReportScreen(),
      ),
    ),
  ],
);

/// 底部导航壳：4 Tab + 中央悬浮「+」（§4.1 原则 2）。
class SlimcaShell extends ConsumerWidget {
  const SlimcaShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      // IndexedStack 承载各分支导航栈；切 Tab 不重建、保留各自栈内状态。
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        // 录入通道抽屉（§4.2 capture 非路由页面语义、任意 Tab 可唤起；§9.3#3
        // 弹簧 bottomSheet springSnappy 220ms，§2.3 打开到可输入 ≤280ms）。
        // W5-6 收敛（§11.1 W5-6）：FAB 唤起「写/说/拍」三通道抽屉——「写」
        // 仍为 feature_capture 的 CapturePage（壳唯一录入 UI 纪律，§10.4），
        // 「说」为 W5-6 语音通道（Fake 链路，§3.3）；共享同一 CaptureSeed →
        // 同一 captureControllerProvider，两通道同一条 AI 解析管线；归属日取
        // 仪表盘当前选中日（§3.2）。编辑路径（修正链 §3.4）仍直达
        // showCaptureSheet 的 W2 表单，不经通道切换。
        onPressed: () {
          // W9-10 录入漏斗首步「打开」（§2.3「打开→输入→解析→确认」、
          // §11.1 W9-10「北极星实测·录入漏斗」）：抽屉唤起即记（W7-8 只埋
          // 渠道选择，漏斗缺「打开」起点，本次核对补齐）。openedAt 同时是
          // 护栏「打开→确认 ≤8s（P50）」的计时起点——确认落库时以
          // capture_open_to_confirm_ms 指标落盘（§2.3 护栏口径）。
          final openedAt = DateTime.now();
          final telemetry = ref.read(telemetryServiceProvider);
          unawaited(telemetry.funnel(TelemetryFunnel.captureOpen));
          showCaptureChannelsSheet(
            context,
            seed: CaptureSeed(
              initialDate: formatCalendarDay(ref.read(selectedDateProvider)),
            ),
            // W7-8 录入漏斗终点（§12 验收口径「确认」）：onSubmitted 在所有
            // 获取性提交路径（手记/AI 确认/降级手填/chip 复记）触发（§2.3 步 5
            // 打开→输入→解析→确认）。props 空（条目内容禁入遥测，§3.9）。
            // 注：编辑路径（修正链 showCaptureSheet，§3.4）为纠错而非获取，
            // 不计入本漏斗（§2.3 录入漏斗口径）。
            onSubmitted: (_) {
              unawaited(_funnelCaptureConfirmed(telemetry, openedAt: openedAt));
            },
          );
        },
        tooltip: '记一件事',
        child: const Icon(Icons.add),
      ),
      // 「+」悬浮于底部中央，与 4 Tab 并列（§4.1 原则 2）。
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: navigationShell.goBranch,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: '账本',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '计划',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 录入漏斗终点：确认落库 + 「打开→确认」护栏耗时（§2.3 步 5 与护栏口径、
/// §12 漏斗周报、§11.1 W9-10 北极星实测）。
///
/// 顺序保证：先 funnel capture_confirm（漏斗终点），再 metric
/// capture_open_to_confirm_ms（文字路径 ≤8s（P50）、拍照 ≤15s 的数据源；
/// 通道维度由漏斗里的 capture_channel_selected/parse_request.input_kind
/// 承担，周报侧按事件序列 join，本指标不携带内容字段，§3.9）。
Future<void> _funnelCaptureConfirmed(
  TelemetryService telemetry, {
  required DateTime openedAt,
}) async {
  await telemetry.funnel(TelemetryFunnel.captureConfirm);
  await telemetry.metric(
    TelemetryMetricName.captureOpenToConfirmMs,
    value: DateTime.now().difference(openedAt).inMilliseconds,
    unit: 'ms',
  );
}
