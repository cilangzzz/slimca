import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// W3-4 新组件冒烟 + MotionLevel 降级档断言（§2.3 步骤 3 / §9.2 / §9.6）：
/// SlimcaBreath（解析中呼吸态）、SlimcaConfirmCard（确认卡容器）、
/// SlimcaMoneyCountUp（金额 count-up）、SlimcaCalorieRing sweep 入场变体。
void main() {
  // 三档 MotionLevel 主题（§9.2 表值 / §9.6 off / §8.3 reduced）。
  // 局部 final：函数体内不能声明 getter，闭包按变量捕获。
  final ThemeData fullTheme = buildTheme(brightness: Brightness.light);
  final ThemeData offTheme = buildTheme(
    brightness: Brightness.light,
    motion: MotionConfig.forLevel(MotionLevel.off),
  );
  final ThemeData reducedTheme = buildTheme(
    brightness: Brightness.light,
    motion: MotionConfig.forLevel(MotionLevel.reduced),
  );

  group('SlimcaMoneyText 分→元格式化（§5.1 金额整数分口径）', () {
    test('基础与千位分组', () {
      expect(SlimcaMoneyText.format(0), '¥0.00');
      expect(SlimcaMoneyText.format(5), '¥0.05');
      expect(SlimcaMoneyText.format(1850), '¥18.50'); // §7.2 示例「花了 18」
      expect(SlimcaMoneyText.format(123456), '¥1,234.56');
    });

    test('负值带符号（不产生 double 中间值）', () {
      expect(SlimcaMoneyText.format(-990), '-¥9.90');
      expect(SlimcaMoneyText.format(-1), '-¥0.01');
    });
  });

  group('SlimcaBreath 解析中呼吸态（§2.3 步骤 3 / §9.4 骨架 ≤100ms）', () {
    testWidgets('full 档：opacity/scale 循环呼吸，幅度按 token 推导周期', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fullTheme,
          home: const Scaffold(
            body: Center(child: SlimcaBreath(child: Text('parsing'))),
          ),
        ),
      );
      // 首帧：呼吸相位 0 → 透明度处于下限（0.55）
      final Opacity start = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(start.opacity, closeTo(0.55, 0.01));

      // 推进半周期（整周期 = 4 × dur.l = 1120ms）→ 相位 0.5 → 明显回升
      await tester.pump(const Duration(milliseconds: 560));
      final Opacity mid = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(mid.opacity, greaterThan(0.6));
      expect(mid.opacity, lessThan(0.95));
      // scale 通道在场（SlimcaBreath 子树内的 Transform.scale；MaterialApp
      // 框架自身也产生 Transform，断言限定在呼吸容器子树内）。
      expect(
        find.descendant(
          of: find.byType(SlimcaBreath),
          matching: find.byType(Transform),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('off 档降级：100ms 单次淡入后静置，无循环呼吸（§9.6）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: offTheme,
          home: const Scaffold(
            body: Center(child: SlimcaBreath(child: Text('parsing'))),
          ),
        ),
      );
      // pumpAndSettle 可收敛 = 无 repeat 循环（降级关键断言）
      await tester.pumpAndSettle();
      final Opacity settled = tester.widget<Opacity>(
        find.byType(Opacity).first,
      );
      expect(settled.opacity, 1.0);
      expect(find.text('parsing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced 档：仍呼吸但周期随 token 缩短（§8.3 ×0.6）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: reducedTheme,
          home: const Scaffold(
            body: Center(child: SlimcaBreath(child: Text('parsing'))),
          ),
        ),
      );
      // reduced 整周期 = 4 × 168ms = 672ms；推进 100ms 仍处于呼吸相位内
      await tester.pump(const Duration(milliseconds: 100));
      final Opacity mid = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(mid.opacity, lessThan(0.99), reason: 'reduced 档仍应呼吸');
      expect(tester.takeException(), isNull);
    });

    testWidgets('breathing=false：业务主动停息 → 静置不循环（§2.3 步骤 3 原地转确认卡）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fullTheme,
          home: const Scaffold(
            body: Center(
              child: SlimcaBreath(breathing: false, child: Text('parsing')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final Opacity settled = tester.widget<Opacity>(
        find.byType(Opacity).first,
      );
      expect(settled.opacity, 1.0);
      expect(tester.takeException(), isNull);
    });
  });

  group('SlimcaConfirmCard 确认卡容器（§3.3 / §2.3 步骤 3 / §12.2#8）', () {
    Widget host({ThemeData? theme, bool cascade = true}) => MaterialApp(
      theme: theme ?? fullTheme,
      home: Scaffold(
        body: Center(
          child: SlimcaConfirmCard(
            cascade: cascade,
            header: const Text('header'),
            footer: const Text('footer'),
            slots: const <Widget>[Text('slot0'), Text('slot1'), Text('slot2')],
          ),
        ),
      ),
    );

    testWidgets('full 档：卡面语义 token + 插槽级联入场完成（§9.3#1 cascadeInterval）', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('header'), findsOneWidget);
      expect(find.text('slot0'), findsOneWidget);
      expect(find.text('slot1'), findsOneWidget);
      expect(find.text('slot2'), findsOneWidget);
      expect(find.text('footer'), findsOneWidget);
      // 卡面 = surfaceCard 语义 token（§8.2；圆角 16 几何常量与仪表盘卡片同口径）
      final Container card = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SlimcaConfirmCard),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = card.decoration! as BoxDecoration;
      expect(decoration.color, SlimcaTheme.light.surfaceCard);
      expect(tester.takeException(), isNull);
    });

    testWidgets('off 档降级：插槽 100ms 淡入且 pumpAndSettle 收敛（§9.6）', (tester) async {
      await tester.pumpWidget(host(theme: offTheme));
      await tester.pumpAndSettle();
      expect(find.text('slot2'), findsOneWidget);
      expect(find.text('footer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cascade=false：插槽直接在场（预览/降级场景）', (tester) async {
      await tester.pumpWidget(host(cascade: false));
      await tester.pump();
      expect(find.text('slot1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('SlimcaMoneyCountUp 金额 count-up（§9.3#4 / §5.1）', () {
    testWidgets('full 档：从 0 分滚到目标，easeOutExpo 800ms（复用 SlimcaCountUp）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fullTheme,
          home: const Scaffold(
            body: Center(child: SlimcaMoneyCountUp(amountMinor: 1800)),
          ),
        ),
      );
      // 首帧为起始值 0 分 →「¥0.00」，目标值尚未出现
      expect(find.text('¥18.00'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('¥18.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('目标变化续播（§2.3 步骤 4 金额点改）', (tester) async {
      Widget host(int minor) => MaterialApp(
        theme: fullTheme,
        home: Scaffold(
          body: Center(child: SlimcaMoneyCountUp(amountMinor: minor)),
        ),
      );
      await tester.pumpWidget(host(1800));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(4500));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('¥45.00'), findsNothing, reason: '应从当前值续播');
      await tester.pumpAndSettle();
      expect(find.text('¥45.00'), findsOneWidget);
    });

    testWidgets('off 档降级：100ms 线性完成（§9.6）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: offTheme,
          home: const Scaffold(
            body: Center(child: SlimcaMoneyCountUp(amountMinor: 1800)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('¥18.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced 档：时长 ×0.6（480ms）后到位（§8.3）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: reducedTheme,
          home: const Scaffold(
            body: Center(child: SlimcaMoneyCountUp(amountMinor: 1800)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 480));
      await tester.pumpAndSettle();
      expect(find.text('¥18.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('取色：支出 moneyOut / 收入 moneyIn（§8.2 双主色锚定）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fullTheme,
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SlimcaMoneyCountUp(amountMinor: 1800),
                const SlimcaMoneyCountUp(amountMinor: 1800, income: true),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // buildTheme 出口过 §8.3 AA 护栏：W1 基线中浅色 moneyIn（tone≈70）对
      // 白卡不达 4.5:1，装配时自动降级到最近安全 tone；静态基线零漂移不回写。
      final SlimcaTheme guarded = enforceSlimcaAa(SlimcaTheme.light);
      final TextStyle expense = tester
          .widget<Text>(find.byType(Text).first)
          .style!;
      expect(expense.color, guarded.moneyOut);
      final TextStyle income = tester
          .widget<Text>(find.byType(Text).last)
          .style!;
      expect(income.color, guarded.moneyIn);
    });

    testWidgets('业务 style 自带 color 时不覆盖', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fullTheme,
          home: const Scaffold(
            body: Center(
              child: SlimcaMoneyCountUp(
                amountMinor: 1800,
                style: TextStyle(color: Color(0xFF123456)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final TextStyle style = tester.widget<Text>(find.byType(Text)).style!;
      expect(style.color, const Color(0xFF123456));
    });
  });

  group('SlimcaCalorieRing sweep 入场变体（§9.3#4「热量环 sweep 填充」，W3-4）', () {
    Widget host({
      ThemeData? theme,
      required bool sweepEntrance,
      required int kcalIn,
      required int kcalOut,
      required int budget,
      required int net,
    }) => MaterialApp(
      theme: theme ?? fullTheme,
      home: Scaffold(
        body: Center(
          child: SlimcaCalorieRing(
            kcalIn: kcalIn,
            kcalOut: kcalOut,
            budget: budget,
            sweepEntrance: sweepEntrance,
            size: 120,
            center: Text('$net'),
          ),
        ),
      ),
    );

    testWidgets('sweepEntrance=true：从 0 扫到目标，springSoft 整定（缺省口径不变）', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          sweepEntrance: true,
          kcalIn: 550,
          kcalOut: 120,
          budget: 2000,
          net: 430,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('430'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sweepEntrance=false：首帧直达目标值（入场级联已承担，§9.3#1）', (tester) async {
      await tester.pumpWidget(
        host(
          sweepEntrance: false,
          kcalIn: 550,
          kcalOut: 120,
          budget: 2000,
          net: 430,
        ),
      );
      await tester.pump();
      expect(find.text('430'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('sweepEntrance=false 目标变化仍 spring 续播（§2.3 步骤 4）', (
      tester,
    ) async {
      Widget host(int kcalIn) => MaterialApp(
        theme: fullTheme,
        home: Scaffold(
          body: Center(
            child: SlimcaCalorieRing(
              kcalIn: kcalIn,
              kcalOut: 120,
              budget: 2000,
              sweepEntrance: false,
              size: 120,
              center: Text('$kcalIn'),
            ),
          ),
        ),
      );
      await tester.pumpWidget(host(550));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(825));
      await tester.pump(const Duration(milliseconds: 50));
      // 续播中：环中心静态文本即时更新，环弧 spring 推进不抛异常
      expect(find.text('825'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('off 档降级：两种 sweep 档均 100ms 淡入淡出收敛（§9.6）', (tester) async {
      for (final bool entrance in <bool>[true, false]) {
        await tester.pumpWidget(
          host(
            theme: offTheme,
            sweepEntrance: entrance,
            kcalIn: 550,
            kcalOut: 120,
            budget: 2000,
            net: 430,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('430'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
