import 'package:core_domain/core_domain.dart' show formatCalendarDay;
import 'package:feature_capture/feature_capture.dart' show CaptureSeed;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/capture_channels_sheet.dart';
import '../features/dashboard/dashboard_state.dart';
import '../features/dashboard/today_dashboard_page.dart';
import '../features/ledger/ledger_page.dart';
import '../features/plan/fitness_log_page.dart';
import '../features/plan/plan_page.dart';
import '../features/settings/settings_page.dart';

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
        // Tab 2 账本：流水列表（W5-6 真页）+分类管理+预算入口+统计入口（§4.2）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ledger',
              builder: (context, state) => const LedgerPage(),
            ),
          ],
        ),
        // Tab 3 计划：待办/健身/存钱三卡（W5-6 真页，§4.2）+ 健身手动记录
        // 子路由（§4.3 /plan/fitness P1 路由，W5-6 接入）。
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
        onPressed: () => showCaptureChannelsSheet(
          context,
          seed: CaptureSeed(
            initialDate: formatCalendarDay(ref.read(selectedDateProvider)),
          ),
        ),
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
