import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// buildTheme（§8.1-§8.3）与主题 morph（§9.3#10）测试。
void main() {
  group('buildTheme：Material 3 浅/深两套，从语义 token 构造', () {
    testWidgets('浅色：M3 + token/MotionConfig 挂载（§8.2/§9.2）', (tester) async {
      final ThemeData theme = buildTheme(brightness: Brightness.light);
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, SlimcaTheme.light.surface);
      expect(theme.colorScheme.primary, SlimcaTheme.light.primary);
      // §8.2 双主色锚定：secondary 槽位挂暖橘（金额）
      expect(theme.colorScheme.secondary, SlimcaTheme.light.moneyOut);
      expect(theme.colorScheme.error, SlimcaTheme.light.danger);

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Placeholder()),
        ),
      );
      final BuildContext context = tester.element(find.byType(Placeholder));
      expect(Theme.of(context).extension<SlimcaTheme>(), isNotNull);
      final MotionConfig motion = context.motion;
      expect(motion.level, MotionLevel.full);
      expect(motion.durL, const Duration(milliseconds: 280));
      expect(context.slimca.kcalIn, SlimcaTheme.light.kcalIn);
    });

    testWidgets('深色', (tester) async {
      final ThemeData theme = buildTheme(brightness: Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, SlimcaTheme.dark.surface);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Placeholder()),
        ),
      );
      final BuildContext context = tester.element(find.byType(Placeholder));
      expect(context.slimca, equals(SlimcaTheme.dark));
    });

    testWidgets('自定义语义 token 与 MotionLevel 注入（§8.3 主题包 / settings 动效等级）', (
      tester,
    ) async {
      final ThemeData theme = buildTheme(
        brightness: Brightness.light,
        semantic: SlimcaTheme.light.copyWith(primary: const Color(0xFF123456)),
        motion: MotionConfig.forLevel(MotionLevel.off),
      );
      expect(theme.colorScheme.primary, const Color(0xFF123456));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: Placeholder()),
        ),
      );
      final BuildContext context = tester.element(find.byType(Placeholder));
      expect(context.motion.level, MotionLevel.off);
      expect(context.motion.durL, const Duration(milliseconds: 100)); // §9.6
    });
  });

  group(
    'SlimcaThemeMorph（§9.3#10：ColorScheme.lerp + ThemeExtension lerp，300ms）',
    () {
      testWidgets('切换主题后收敛到目标 token', (tester) async {
        final ThemeData light = buildTheme(brightness: Brightness.light);
        final ThemeData dark = buildTheme(brightness: Brightness.dark);
        late BuildContext captured;
        Widget host(ThemeData data) => MaterialApp(
          theme: data,
          home: Builder(
            builder: (context) {
              captured = context;
              return SlimcaThemeMorph(
                data: data,
                child: const Scaffold(body: Placeholder()),
              );
            },
          ),
        );

        await tester.pumpWidget(host(light));
        expect(
          Theme.of(captured).scaffoldBackgroundColor,
          SlimcaTheme.light.surface,
        );

        await tester.pumpWidget(host(dark));
        await tester.pumpAndSettle();
        expect(
          Theme.of(captured).scaffoldBackgroundColor,
          SlimcaTheme.dark.surface,
        );
        expect(
          Theme.of(captured).extension<SlimcaTheme>(),
          equals(SlimcaTheme.dark),
        );
      });
    },
  );
}
