import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'app/router.dart';
import 'app/theme.dart';

Future<void> main() async {
  // §11 W2 接线：runApp 前完成异步装配（开库、device_id、内置账本种子），
  // 以 overrides 注入 ProviderScope——运行期依赖全同步可读、页面零等待
  // （§2.3 步 0 无 spinner 冷启动；装配细节见 lib/app/bootstrap.dart）。
  WidgetsFlutterBinding.ensureInitialized();
  final overrides = await bootstrap();
  runApp(ProviderScope(overrides: overrides, child: const SlimcaApp()));
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
