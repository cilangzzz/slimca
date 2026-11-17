import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:ui_kit/ui_kit.dart';

/// dynamic_color 适配层测试（§8.3 两源映射 + 护栏 + 回退）。
///
/// 纪律：测试禁止真实平台通道——CorePaletteLoader 一律注入 Fake
/// （[CorePalette.of] 合成动态色），不触 DynamicColorPlugin。

/// 合成紫色动态取色（hue 260 / chroma 40；material_color_utilities
/// `CorePalette.of` 收 ARGB 源色，经 Hct 生成保证色相/饱和度可复现）。
CorePalette _purplePalette() => CorePalette.of(Hct.from(260, 40, 40).toInt());

void main() {
  // 基准包：紫中性基底（非默认冷灰），便于断言两源映射生效
  final ThemeProfile base = kSlimcaPresetThemeProfiles.first;

  group('SlimcaDynamicThemeMapper.map（§8.3 仅映射 primary/neutral 两源）', () {
    test('palette=null 回退手动种子色（iOS/旧机型口径）', () {
      final SlimcaTheme fallback = SlimcaDynamicThemeMapper.map(
        palette: null,
        base: base.toSlimcaTheme(Brightness.light),
        brightness: Brightness.light,
      );
      expect(fallback, base.toSlimcaTheme(Brightness.light));
    });

    test('accent 源 → primary/onPrimary；neutral 源 → 背景层级', () {
      final CorePalette dynamic = _purplePalette(); // 紫色动态取色
      final SlimcaTheme mapped = SlimcaDynamicThemeMapper.map(
        palette: dynamic,
        base: base.toSlimcaTheme(Brightness.light),
        brightness: Brightness.light,
      );
      // 源 1：accent 映射进品牌主色（M3 明度惯例浅色 tone 40）
      expect(mapped.primary, Color(dynamic.primary.get(40)));
      expect(mapped.onPrimary, Color(dynamic.primary.get(100)));
      // 源 2：neutral 映射进背景层级（浅色 M3 惯例 tone 98/94/100）
      expect(mapped.surface, Color(dynamic.neutral.get(98)));
      expect(mapped.surfaceMuted, Color(dynamic.neutral.get(94)));
      expect(mapped.surfaceCard, Color(dynamic.neutral.get(100)));
      expect(mapped.outline, Color(dynamic.neutralVariant.get(50)));
    });

    test('双主色锚定不被动态色覆盖（§8.3：不整体套用系统色）', () {
      final CorePalette dynamic = _purplePalette();
      for (final Brightness brightness in Brightness.values) {
        final SlimcaTheme mapped = SlimcaDynamicThemeMapper.map(
          palette: dynamic,
          base: base.toSlimcaTheme(brightness),
          brightness: brightness,
        );
        final SlimcaTheme baseTokens = base.toSlimcaTheme(brightness);
        // kcal/money/danger 系列保持基准包种子派生（动态色不映射）
        expect(mapped.kcalIn, baseTokens.kcalIn);
        expect(mapped.moneyOut, baseTokens.moneyOut);
        expect(mapped.moneyIn, baseTokens.moneyIn);
        expect(mapped.danger, baseTokens.danger);
        // HCT 色相锚定（§8.2）
        expect(Hct.fromInt(mapped.kcalIn.toARGB32()).hue, closeTo(150, 8.0));
        expect(Hct.fromInt(mapped.moneyOut.toARGB32()).hue, closeTo(62, 8.0));
      }
    });

    test('映射出口过 AA 护栏（平台取色不保证达标）', () {
      final CorePalette dynamic = _purplePalette();
      for (final Brightness brightness in Brightness.values) {
        final SlimcaTheme mapped = SlimcaDynamicThemeMapper.map(
          palette: dynamic,
          base: base.toSlimcaTheme(brightness),
          brightness: brightness,
        );
        expect(
          auditSlimcaAa(mapped).every((SlimcaAaPairResult r) => r.pass),
          isTrue,
          reason: '${brightness.name} 动态映射应全对达标（§8.3 护栏）',
        );
      }
    });
  });

  group('SlimcaDynamicColorBuilder（集成层；loader 注入 Fake）', () {
    Future<CorePalette?> fakeLoader(CorePalette? palette) =>
        Future.value(palette);

    testWidgets('取到动态色：装配两套主题且 primary 来自平台', (tester) async {
      late ThemeData lightTheme;
      late ThemeData darkTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: SlimcaDynamicColorBuilder(
            profile: base,
            loader: () => fakeLoader(_purplePalette()),
            builder: (BuildContext context, ThemeData light, ThemeData dark) {
              lightTheme = light;
              darkTheme = dark;
              return const Placeholder();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final CorePalette dynamic = _purplePalette();
      expect(lightTheme.colorScheme.primary, Color(dynamic.primary.get(40)));
      expect(darkTheme.colorScheme.primary, Color(dynamic.primary.get(80)));
      // 语义 token 与 MotionConfig 挂载（§8.2/§9.2）
      expect(lightTheme.extension<SlimcaTheme>(), isNotNull);
      expect(lightTheme.extension<MotionConfig>(), isNotNull);
      // 深浅两套：表面亮暗关系
      expect(
        lightTheme.extension<SlimcaTheme>()!.surface.computeLuminance(),
        greaterThan(
          darkTheme.extension<SlimcaTheme>()!.surface.computeLuminance(),
        ),
      );
    });

    testWidgets('loader 抛异常/返回 null：回退手动种子色（§8.3）', (tester) async {
      late ThemeData lightTheme;
      await tester.pumpWidget(
        MaterialApp(
          home: SlimcaDynamicColorBuilder(
            profile: base,
            // 平台不支持/通道异常 → null
            loader: () async => null,
            builder: (BuildContext context, ThemeData light, ThemeData dark) {
              lightTheme = light;
              return const Placeholder();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        lightTheme.colorScheme.primary,
        base.toSlimcaTheme(Brightness.light).primary,
        reason: '回退路径应使用手动种子色主色',
      );
    });

    testWidgets('MotionLevel 随包装配（profile.motionLevel → MotionConfig）', (
      tester,
    ) async {
      final ThemeProfile quiet = base.copyWith(motionLevel: MotionLevel.off);
      late MotionConfig motion;
      await tester.pumpWidget(
        MaterialApp(
          home: SlimcaDynamicColorBuilder(
            profile: quiet,
            loader: () async => null,
            // MotionConfig 挂在装配出的 ThemeData 上：以 lightTheme 包一层
            // 再读 token（§9.2 动效 token 挂进主题）
            builder: (BuildContext context, ThemeData light, ThemeData dark) =>
                Theme(
                  data: light,
                  child: Builder(
                    builder: (BuildContext themed) {
                      motion = MotionConfig.of(themed);
                      return const Placeholder();
                    },
                  ),
                ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(motion.level, MotionLevel.off);
      // §9.6 off 档：全部转场 100ms 淡入淡出
      expect(motion.durL, const Duration(milliseconds: 100));
    });

    testWidgets('加载中先用手动种子色渲染（不阻塞首帧）', (tester) async {
      late ThemeData lightTheme;
      await tester.pumpWidget(
        MaterialApp(
          home: SlimcaDynamicColorBuilder(
            profile: base,
            loader: () => Future<CorePalette?>.delayed(
              const Duration(seconds: 1),
              () => _purplePalette(),
            ),
            builder: (BuildContext context, ThemeData light, ThemeData dark) {
              lightTheme = light;
              return const Placeholder();
            },
          ),
        ),
      );
      await tester.pump(); // 未完成 async gap：快照未就绪
      expect(
        lightTheme.colorScheme.primary,
        base.toSlimcaTheme(Brightness.light).primary,
        reason: '加载中应先以手动种子色渲染（回退路径）',
      );
      // 排空 loader 的延迟 Future（前推 2s > 1s 定时器，避免收尾 pending
      // timer；pumpAndSettle 不推进空闲树上的定时器）。
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });
  });
}
