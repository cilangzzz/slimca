// Slimca 应用壳冒烟测试（§4.2 壳结构、§2.3 步 0 无 spinner 冷启动）。
//
// 替换 flutter create 默认计数器模板测试：SlimcaApp 无 MyApp/计数器，
// 骨架期验证「首帧直出仪表盘 + 4 Tab 导航 + 中央 + 占位提示」。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/main.dart';

void main() {
  testWidgets('应用壳冒烟：仪表盘直出 + 4 Tab + 录入占位', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SlimcaApp()));

    // 冷启动首帧直出（无 spinner，§2.3 步 0）：等日期大字/卡片墙动画播完。
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Slimca'), findsOneWidget); // AppBar 标题

    // §4.2 四 Tab：今天 / 账本 / 计划 / 我的。
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('账本'), findsOneWidget);
    expect(find.text('计划'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 中央悬浮「+」= 录入抽屉占位（§4.2 capture，W3-4 接入真实现）。
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(
      find.text('录入抽屉（写/说/拍）将在 W3-4 接入（§4.2 capture）'),
      findsOneWidget,
    );
  });
}
