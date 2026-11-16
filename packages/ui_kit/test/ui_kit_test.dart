import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// ui_kit 导出面冒烟：核心类型可从 barrel 直接访问（§10.4 ui_kit「语义 token+组件+MotionConfig+转场库」）。
void main() {
  test('barrel 导出：token 与动效基建可访问', () {
    expect(SlimcaPalette.defaults.kcal.get(50), isNonZero);
    expect(SlimcaTheme.light.surface, isNot(SlimcaTheme.dark.surface));
    expect(MotionConfig.full.durL, const Duration(milliseconds: 280));
    expect(buildTheme(brightness: Brightness.light).useMaterial3, isTrue);
    expect(SlimcaStaggerItem, isNotNull);
    expect(SlimcaSpringRectTween, isNotNull);
  });
}
