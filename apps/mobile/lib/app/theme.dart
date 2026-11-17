/// W1 基线保留：[slimcaLightTheme]/[slimcaDarkTheme]（帧预算基准测试
/// frame_budget_benchmark_test.dart 引用）= 默认包（墨）的缺省装配。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

/// 应用主题与动效 token 装配层（§8 主题系统 / §9 动效系统）。
///
/// 设计决策：
/// - 本文件是 apps/mobile 对 ui_kit 的**唯一引用点**（§10.4：壳负责装配）。
///   W1 骨架期若 ui_kit 的 `buildTheme` / `MotionConfig` 签名有出入，只需调整本文件。
/// - 主题切换 = ColorScheme + ThemeExtension 全屏 morph（§8.3，转场 #10），
///   由 ui_kit [SlimcaThemeMorph] 实现（main.dart builder 内接线），
///   本文件只按亮度装配目标 ThemeData。
/// - 深浅色跟随系统 + 手动覆盖（§8.3）由 lib/theme/theme_providers.dart 的
///   `slimcaThemeModeProvider` 给出 themeMode，MaterialApp 消费；W16 起主题
///   包来自 theme_profiles（§5.6⑳），装配链（ThemeProfile.toSlimcaTheme →
///   SlimcaDynamicThemeMapper → buildTheme，ui_kit 三步）见 theme_providers.dart。

/// 浅色主题（§8.2 语义 token 与 §9.2 MotionConfig 由 ui_kit 挂进 ThemeData）。
///
/// W1 约定的 ui_kit 签名：`buildTheme({required Brightness brightness})`，
/// 默认主题包（墨/纸，§8.3 内置包）在 ui_kit 内部生效；W16 起运行期主题
/// 经 `slimcaLightThemeProvider`（theme_profiles 当前包）装配，本函数保留
/// 为基准测试与降级路径的缺省装配点。
ThemeData slimcaLightTheme() => buildTheme(brightness: Brightness.light);

/// 深色主题（曜黑 AMOLED 纯黑随包 token 生效，§8.3）。
ThemeData slimcaDarkTheme() => buildTheme(brightness: Brightness.dark);

/// 共享轴转场时长：§9.2 dur.l = 280ms（抽屉 / 页面 / 共享轴）。
///
/// W1 约定的 ui_kit 签名：`MotionConfig.of(context)` 返回携带
/// dur.xs/s/m/l/xl 与 spring.snappy/soft token 的实例（MotionLevel 治理降级，
/// §9.2/§9.6）。骨架期仅日切换用到，其余转场随六转场逐条接入（§9.3）。
Duration sharedAxisTransitionDuration(BuildContext context) =>
    MotionConfig.of(context).durL;
