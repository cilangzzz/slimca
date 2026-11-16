import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../features/capture/capture_page.dart';
import '../features/dashboard/today_dashboard_page.dart';
import '../features/ledger/ledger_page.dart';
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
///   录入抽屉；`/calendar`、`/entry/:id`、`/ledger/*` 等子路由随 W2+ 逐条
///   接入，接入时路由级转场一律注入自定义 `PageRouteBuilder`（§9.5 工程约束，
///   共享轴/容器变换见 §9.3）。
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
        // Tab 2 账本：流水列表+分类管理+预算入口+统计入口（§4.2）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/ledger',
              builder: (context, state) => const LedgerPage(),
            ),
          ],
        ),
        // Tab 3 计划：待办/健身/存钱三卡（§4.2）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanPage(),
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
class SlimcaShell extends StatelessWidget {
  const SlimcaShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 承载各分支导航栈；切 Tab 不重建、保留各自栈内状态。
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        // 录入抽屉（§4.2 capture 非路由页面语义、任意 Tab 可唤起；§9.3#3
        // 弹簧 bottomSheet springSnappy 220ms，§2.3 打开到可输入 ≤280ms）。
        // W2 先通「写」通道手动录入（§11 W2）；说/拍 W3-4/W11-12 接入。
        onPressed: () => showSlimcaSpringSheet(
          context: context,
          builder: (_) => const CapturePage(),
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
