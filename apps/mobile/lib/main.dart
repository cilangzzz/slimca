import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

void main() {
  // W1 骨架：无异步初始化（DB/同步引擎 W2+ 接入后再改 async main，§11 W2/W5-6）。
  runApp(const ProviderScope(child: SlimcaApp()));
}

/// 应用根：ProviderScope + MaterialApp.router（§10.1 技术选型）。
///
/// 设计决策：
/// - 路由全部交给 go_router（§4.3 路由表），壳不持有任何页面状态；
/// - 深浅色跟随系统（§8.3），浅深两套 ThemeData 均来自 ui_kit `buildTheme`
///   （语义 token + MotionConfig 挂进主题，§8.2/§9.2）；
/// - 无 spinner 的冷启动承诺（§2.3 步 0）由仪表盘快照直出实现，壳层零加载屏。
class SlimcaApp extends StatelessWidget {
  const SlimcaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Slimca',
      debugShowCheckedModeBanner: false,
      routerConfig: slimcaRouter,
      theme: slimcaLightTheme(),
      darkTheme: slimcaDarkTheme(),
      // 主题模式下行为统一：Material 3（§8/§9 的动效与主题体系基于 M3）。
      themeMode: ThemeMode.system,
    );
  }
}
