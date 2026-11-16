import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 应用主题与动效 token 装配层（§8 主题系统 / §9 动效系统）。
///
/// 设计决策：
/// - 本文件是 apps/mobile 对 ui_kit 的**唯一引用点**（§10.4：壳负责装配）。
///   W1 骨架期若 ui_kit 的 `buildTheme` / `MotionConfig` 签名有出入，只需调整本文件。
/// - 主题切换 = ColorScheme + ThemeExtension 全屏 morph（§8.3，转场 #10），
///   由 ui_kit 内部实现，壳只按亮度取 ThemeData。
/// - 深浅色跟随系统（§8.3），在 [main.dart] 的 MaterialApp.router 上分别注入。

/// 浅色主题（§8.2 语义 token 与 §9.2 MotionConfig 由 ui_kit 挂进 ThemeData）。
///
/// W1 约定的 ui_kit 签名：`buildTheme({required Brightness brightness})`，
/// 默认主题包（墨/纸，§8.3 内置包）在 ui_kit 内部生效；主题编辑器（P1）落地后
/// 此处改为从 theme_profiles 读取当前包（§5.6 ⑳）。
ThemeData slimcaLightTheme() => buildTheme(brightness: Brightness.light);

/// 深色主题（曜黑 AMOLED 纯黑独立开关，P1 接入，§8.3）。
ThemeData slimcaDarkTheme() => buildTheme(brightness: Brightness.dark);

/// 共享轴转场时长：§9.2 dur.l = 280ms（抽屉 / 页面 / 共享轴）。
///
/// W1 约定的 ui_kit 签名：`MotionConfig.of(context)` 返回携带
/// dur.xs/s/m/l/xl 与 spring.snappy/soft token 的实例（MotionLevel 治理降级，
/// §9.2/§9.6）。骨架期仅日切换用到，其余转场随六转场逐条接入（§9.3）。
Duration sharedAxisTransitionDuration(BuildContext context) =>
    MotionConfig.of(context).durL;
