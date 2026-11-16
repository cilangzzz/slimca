import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 六条 P0 关键转场（§9.3 清单）builder 可构造/可渲染冒烟测试。
void main() {
  group('路由级转场 builder 可构造', () {
    test('SlimcaSharedAxisPageRoute：full 档 280ms / off 档 100ms（§9.3#2）', () {
      final SlimcaSharedAxisPageRoute<void> route =
          SlimcaSharedAxisPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
          );
      expect(route.transitionDuration, const Duration(milliseconds: 280));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 280),
      );

      final SlimcaSharedAxisPageRoute<void> offRoute =
          SlimcaSharedAxisPageRoute<void>(
            builder: (_) => const SizedBox.shrink(),
            motion: MotionConfig.forLevel(MotionLevel.off),
          );
      expect(offRoute.transitionDuration, const Duration(milliseconds: 100));
    });

    test('SlimcaSpringSheetRoute：弹簧整定 220ms（§9.3#3，≤§2.3 280ms 预算）', () {
      final SlimcaSpringSheetRoute<void> route = SlimcaSpringSheetRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );
      expect(route.transitionDuration, const Duration(milliseconds: 220));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 220),
      );
      expect(route.barrierDismissible, isTrue);
      // 弹簧由 createSimulation 驱动（§9.3#3）
      expect(route.createSimulation(forward: true), isNotNull);

      final SlimcaSpringSheetRoute<void> offRoute =
          SlimcaSpringSheetRoute<void>(
            builder: (_) => const SizedBox.shrink(),
            motion: MotionConfig.forLevel(MotionLevel.off),
          );
      expect(offRoute.transitionDuration, const Duration(milliseconds: 100));
      expect(
        offRoute.createSimulation(forward: true),
        isNull,
      ); // off → 线性 100ms
    });

    test('SlimcaSpringRectTween 可构造（§9.3#5 Hero + spring）', () {
      final SlimcaSpringRectTween tween = SlimcaSpringRectTween(
        begin: Rect.fromLTWH(0, 0, 100, 100),
        end: Rect.fromLTWH(200, 300, 100, 100),
        spring: MotionConfig.full.springSoft,
      );
      final Rect? mid = tween.transform(0.5);
      expect(mid, isNotNull);
      expect(mid!.left, inInclusiveRange(0.0, 200.0));
    });
  });

  testWidgets('SlimcaSharedAxisSwitcher 日切换冒烟（§9.3#2）', (tester) async {
    Widget host(String day) => MaterialApp(
      home: Scaffold(
        body: SlimcaSharedAxisSwitcher(
          child: Text(day, key: ValueKey<String>(day)),
        ),
      ),
    );
    await tester.pumpWidget(host('day1'));
    await tester.pumpWidget(host('day2'));
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();
    expect(find.text('day2'), findsOneWidget);
    expect(find.text('day1'), findsNothing);
  });

  testWidgets('SlimcaStaggerItem 冷启动级联冒烟（§9.3#1）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                SlimcaStaggerItem(index: i, child: Text('card$i')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('card2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SlimcaCountUp：count-up + 目标变化续播（§9.3#4/§2.3 步骤 4）', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SlimcaCountUp(value: 550))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('550'), findsOneWidget);

    // 份量滑杆 1.0→1.5 热量重算 → TweenAnimationBuilder 从当前值续播到新目标
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SlimcaCountUp(value: 825))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('825'), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('825'), findsOneWidget);
  });

  testWidgets('SlimcaCalorieRing 热量环冒烟（§3.2）', (tester) async {
    Widget host({
      required int kcalIn,
      required int kcalOut,
      required int budget,
      required int net,
    }) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SlimcaCalorieRing(
            kcalIn: kcalIn,
            kcalOut: kcalOut,
            budget: budget,
            size: 120,
            center: Text('$net'),
          ),
        ),
      ),
    );

    // 预算内
    await tester.pumpWidget(
      host(kcalIn: 550, kcalOut: 120, budget: 2000, net: 430),
    );
    await tester.pumpAndSettle();
    expect(find.text('430'), findsOneWidget);

    // 超支段渲染不抛异常（§3.2 预算状态色）
    await tester.pumpWidget(
      host(kcalIn: 2400, kcalOut: 0, budget: 2000, net: 2400),
    );
    await tester.pumpAndSettle();
    expect(find.text('2400'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SlimcaConfidenceDot 三色点冒烟（§2.3/§7.3）', (tester) async {
    // off 档：圆点静置，pumpAndSettle 可完成
    final ThemeData offTheme = buildTheme(
      brightness: Brightness.light,
      motion: MotionConfig.forLevel(MotionLevel.off),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: offTheme,
        home: const Scaffold(
          body: Center(child: SlimcaConfidenceDot(confidence: 0.9)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SlimcaConfidenceDot), findsOneWidget);

    // full 档：pulse 循环动画，有限帧推进验证不抛异常
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const Scaffold(
          body: Center(child: SlimcaConfidenceDot(confidence: 0.3)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SlimcaHero 可挂载（§9.3#5）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SlimcaHero(tag: 'confirm-card', child: const Text('card')),
        ),
      ),
    );
    expect(find.text('card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SlimcaSharedAxisPageRoute 推入冒烟（§9.3#2）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  SlimcaSharedAxisPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('detail')),
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showSlimcaSpringSheet 弹出/关闭冒烟（§9.3#3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showSlimcaSpringSheet<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    height: 280,
                    child: Center(child: Text('sheet')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);

    Navigator.of(tester.element(find.text('sheet'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
