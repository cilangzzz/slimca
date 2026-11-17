import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:ui_kit/ui_kit.dart';

/// WCAG AA 对比度护栏测试（§8.3/§8.4：computeContrastRatio + 最近安全 tone 降级）。
void main() {
  group('computeContrastRatio（§8.3 WCAG 公式）', () {
    test('极值：黑/白 = 21:1，同色 = 1:1', () {
      expect(
        computeContrastRatio(const Color(0xFFFFFFFF), const Color(0xFF000000)),
        closeTo(21.0, 0.01),
      );
      expect(
        computeContrastRatio(const Color(0xFF123456), const Color(0xFF123456)),
        closeTo(1.0, 0.001),
      );
    });

    test('与参数顺序无关', () {
      final double ab = computeContrastRatio(
        const Color(0xFF1B1B1F),
        const Color(0xFFFDFBFF),
      );
      final double ba = computeContrastRatio(
        const Color(0xFFFDFBFF),
        const Color(0xFF1B1B1F),
      );
      expect(ab, closeTo(ba, 1e-9));
      expect(ab, greaterThan(10));
    });
  });

  group('resolveAaSafeColor（最近安全 tone 降级算法）', () {
    test('已达标前景原样返回（幂等前提）', () {
      const Color fg = Color(0xFF1B1B1F); // 深字
      const Color bg = Color(0xFFFFFFFF); // 白底
      expect(resolveAaSafeColor(fg, bg), same(fg));
    });

    test('浅底上的浅色前景压暗到 ≥4.5 且保色相（§8.2 锚定不被破坏）', () {
      // 浅橘前景（tone ~70 量级）在白底上必然不达标
      final Color fg = Color(TonalPalette.of(62, 68).get(70));
      const Color bg = Color(0xFFFFFFFF);
      expect(computeContrastRatio(fg, bg), lessThan(kAaTextContrast));

      final Color safe = resolveAaSafeColor(fg, bg);
      expect(
        computeContrastRatio(safe, bg),
        greaterThanOrEqualTo(kAaTextContrast),
      );
      // 色相/饱和度保持（HCT 色相不漂移）
      final double hueBefore = Hct.fromInt(fg.toARGB32()).hue;
      final double hueAfter = Hct.fromInt(safe.toARGB32()).hue;
      expect(hueAfter, closeTo(hueBefore, 2.0));
      // 最近安全 tone：明度被压低（浅底方向）
      expect(
        Hct.fromInt(safe.toARGB32()).tone,
        lessThan(Hct.fromInt(fg.toARGB32()).tone),
      );
    });

    test('深底上的深色前景提亮到 ≥4.5（方向远离背景明度）', () {
      final Color fg = Color(TonalPalette.of(150, 55).get(30));
      const Color bg = Color(0xFF0E0E12); // 近黑
      expect(computeContrastRatio(fg, bg), lessThan(kAaTextContrast));
      final Color safe = resolveAaSafeColor(fg, bg);
      expect(
        computeContrastRatio(safe, bg),
        greaterThanOrEqualTo(kAaTextContrast),
      );
      expect(
        Hct.fromInt(safe.toARGB32()).tone,
        greaterThan(Hct.fromInt(fg.toARGB32()).tone),
      );
    });

    test('病态组合（前景=背景）也能降级达标', () {
      const Color fg = Color(0xFF808080);
      const Color bg = Color(0xFF7E7E82);
      final Color safe = resolveAaSafeColor(fg, bg);
      expect(
        computeContrastRatio(safe, bg),
        greaterThanOrEqualTo(kAaTextContrast),
      );
    });

    test('降级幂等：安全色再降级不变', () {
      final Color fg = Color(TonalPalette.of(62, 68).get(70));
      const Color bg = Color(0xFFFFFFFF);
      final Color once = resolveAaSafeColor(fg, bg);
      final Color twice = resolveAaSafeColor(once, bg);
      expect(twice, once);
    });
  });

  group('enforceSlimcaAa / auditSlimcaAa（§8.3 buildTheme 前校验）', () {
    test('装配出口护栏：内置默认 token 过 enforceSlimcaAa 后全对达标', () {
      for (final SlimcaTheme tokens in <SlimcaTheme>[
        SlimcaTheme.light,
        SlimcaTheme.dark,
      ]) {
        for (final SlimcaAaPairResult r in auditSlimcaAa(
          enforceSlimcaAa(tokens),
        )) {
          expect(
            r.pass,
            isTrue,
            reason:
                '${tokens == SlimcaTheme.light ? '浅' : '深'}色 ${r.label}'
                ' 应达 ${r.threshold}:1（实测 ${r.ratio.toStringAsFixed(2)}）',
          );
        }
      }
    });

    test('W1 基线零漂移与护栏分层：浅色基线存在已知不达标对（不回写基线）', () {
      // 基线 = SlimcaTheme.fromPalette 原始推导（壳层 theme_pack 复刻表零漂移
      // 锚点），浅色外延 tone（moneyIn/kcalOut ≈70）不达 AA 正文阈值；
      // 降级只发生在装配出口（buildTheme / ThemeProfile.toSlimcaTheme）。
      final List<SlimcaAaPairResult> lightFails = auditSlimcaAa(
        SlimcaTheme.light,
      ).where((SlimcaAaPairResult r) => !r.pass).toList();
      expect(lightFails, isNotEmpty, reason: '浅色 W1 基线含已知不达标对');
      expect(
        lightFails.map((SlimcaAaPairResult r) => r.label),
        containsAll(<String>['收入金额 / 卡面', '消耗热量 / 卡面']),
      );
    });

    test('手写病态 token 被自动降级到全达标', () {
      // 构造深底深字 + 浅底浅字病态组合
      final SlimcaTheme sick = SlimcaTheme.light.copyWith(
        onSurface: const Color(0xFFB0B0B0),
        moneyIn: const Color(0xFFFFD54F),
        net: const Color(0xFF3A5A40),
      );
      expect(
        auditSlimcaAa(sick).any((SlimcaAaPairResult r) => !r.pass),
        isTrue,
        reason: '病态组合应被审计出不达标',
      );
      final SlimcaTheme fixed = enforceSlimcaAa(sick);
      expect(
        auditSlimcaAa(fixed).every((SlimcaAaPairResult r) => r.pass),
        isTrue,
        reason: '护栏执行后应全对达标（§8.3）',
      );
      // 未列入病态组合的字段不被误改
      expect(fixed.primary, sick.primary);
      expect(fixed.surface, sick.surface);
    });

    test('护栏幂等：重复执行结果稳定', () {
      final SlimcaTheme sick = SlimcaTheme.light.copyWith(
        moneyIn: const Color(0xFFFFD54F),
      );
      final SlimcaTheme once = enforceSlimcaAa(sick);
      final SlimcaTheme twice = enforceSlimcaAa(once);
      expect(twice, once);
    });

    test('降级保持前景色相（§8.2 双主色锚定的护栏实现口径）', () {
      final SlimcaTheme sick = SlimcaTheme.light.copyWith(
        moneyIn: const Color(0xFFFFD54F),
        kcalOut: const Color(0xFF7FC98F),
      );
      final SlimcaTheme fixed = enforceSlimcaAa(sick);
      // 护栏只动 tone：降级前后 HCT 色相/饱和度保持（锚定不被破坏）
      expect(
        Hct.fromInt(fixed.moneyIn.toARGB32()).hue,
        closeTo(Hct.fromInt(sick.moneyIn.toARGB32()).hue, 2.0),
        reason: 'moneyIn 降级不改色相（暖橘仍暖橘）',
      );
      expect(
        Hct.fromInt(fixed.kcalOut.toARGB32()).hue,
        closeTo(Hct.fromInt(sick.kcalOut.toARGB32()).hue, 2.0),
        reason: 'kcalOut 降级不改色相（绿仍绿）',
      );
    });
  });
}
