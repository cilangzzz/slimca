import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 设计 token 默认值与插值测试（§8.2 三层架构 / §8.3 lerp）。
void main() {
  group('SlimcaPalette（§8.2 第 1 层：种子色 → HCT tonal palette）', () {
    test('tone 色阶单调（0-100 明度）', () {
      final SlimcaPalette palette = SlimcaPalette.defaults;
      expect(
        palette.kcalTone(100).computeLuminance(),
        greaterThan(palette.kcalTone(40).computeLuminance()),
      );
      expect(
        palette.moneyTone(40).computeLuminance(),
        greaterThan(palette.moneyTone(10).computeLuminance()),
      );
    });

    test('fromSeeds 可构造（§8.4 种子色取色入口）', () {
      final SlimcaPalette p = SlimcaPalette.fromSeeds(
        kcalSeed: const Color(0xFF1E9E6A),
        moneySeed: const Color(0xFFE8853D),
        dangerSeed: const Color(0xFFD8402F),
        neutralSeed: const Color(0xFF5B6B7A),
      );
      expect(p.kcalTone(50), isNot(p.moneyTone(50)));
      expect(p.kcalTone(50), isNot(p.dangerTone(50)));
    });
  });

  group('SlimcaTheme 语义 token 默认值（§8.2 清单）', () {
    test('双主色锚定：kcalIn 绿、moneyOut 橘（§8.2「绿是吃、橘是钱」）', () {
      for (final SlimcaTheme tokens in <SlimcaTheme>[
        SlimcaTheme.light,
        SlimcaTheme.dark,
      ]) {
        final Color kcalIn = tokens.kcalIn;
        final Color moneyOut = tokens.moneyOut;
        // HCT 绿色域：G 通道占优；HCT 橙色域：R 通道占优
        expect(kcalIn.g, greaterThan(kcalIn.r), reason: '浅/深色 kcalIn 均应为绿');
        expect(kcalIn.g, greaterThan(kcalIn.b), reason: '浅/深色 kcalIn 均应为绿');
        expect(
          moneyOut.r,
          greaterThan(moneyOut.g),
          reason: '浅/深色 moneyOut 均应为橘',
        );
        expect(
          moneyOut.r,
          greaterThan(moneyOut.b),
          reason: '浅/深色 moneyOut 均应为橘',
        );
      }
    });

    test('浅/深背景层级关系与滑杆默认值', () {
      expect(
        SlimcaTheme.light.surface.computeLuminance(),
        greaterThan(SlimcaTheme.light.onSurface.computeLuminance()),
      );
      expect(
        SlimcaTheme.dark.surface.computeLuminance(),
        lessThan(SlimcaTheme.dark.onSurface.computeLuminance()),
      );
      expect(SlimcaTheme.light.surfaceCard, isNot(SlimcaTheme.light.surface));
      expect(SlimcaTheme.light.radiusScale, 1.0);
      expect(SlimcaTheme.light.density, 1.0);
      expect(SlimcaTheme.light.fontScale, 1.0);
      // §8.3 动效强度滑杆 0.6x-1.5x，默认 1.0
      expect(SlimcaTheme.light.motionScale, 1.0);
      expect(SlimcaTheme.light.motionScale, inInclusiveRange(0.6, 1.5));
    });

    test('状态三色互异（置信度三色点 §2.3/§7.3）', () {
      expect(SlimcaTheme.light.success, isNot(SlimcaTheme.light.warn));
      expect(SlimcaTheme.light.warn, isNot(SlimcaTheme.light.danger));
      expect(SlimcaTheme.light.success, isNot(SlimcaTheme.light.danger));
    });
  });

  group('SlimcaTheme.lerp（§8.3「ThemeExtensionTween 自实现 lerp」）', () {
    final SlimcaTheme a = SlimcaTheme.light;
    final SlimcaTheme b = SlimcaTheme.dark;

    test('端点与中点', () {
      expect(a.lerp(b, 0.0), equals(a));
      expect(a.lerp(b, 1.0), equals(b));
      final SlimcaTheme mid = a.lerp(b, 0.5);
      expect(mid.surface, Color.lerp(a.surface, b.surface, 0.5));
      expect(
        mid.radiusScale,
        closeTo((a.radiusScale + b.radiusScale) / 2, 1e-9),
      );
      expect(mid.kcalIn, Color.lerp(a.kcalIn, b.kcalIn, 0.5));
    });

    test('other 为 null 时返回自身（ThemeExtension 契约）', () {
      expect(a.lerp(null, 0.7), same(a));
    });

    test('copyWith 替换单字段', () {
      final SlimcaTheme c = a.copyWith(kcalIn: const Color(0xFF112233));
      expect(c.kcalIn, const Color(0xFF112233));
      expect(c.moneyOut, a.moneyOut);
      expect(c, isNot(a));
    });
  });

  group('ThemeExtensionTween（§8.3）', () {
    test('transform 端点与中点', () {
      final ThemeExtensionTween<SlimcaTheme> tween =
          ThemeExtensionTween<SlimcaTheme>(
            begin: SlimcaTheme.light,
            end: SlimcaTheme.dark,
          );
      expect(tween.transform(0.0), equals(SlimcaTheme.light));
      expect(tween.transform(1.0), equals(SlimcaTheme.dark));
      expect(
        tween.transform(0.5)!.surface,
        Color.lerp(SlimcaTheme.light.surface, SlimcaTheme.dark.surface, 0.5),
      );
    });
  });
}
