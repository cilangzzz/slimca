import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:ui_kit/ui_kit.dart';

/// 6 内置主题包测试（§8.3 清单 / §8.2 双主色锚定 / §8.3 AA 全包全亮度达标）。
void main() {
  group('内置清单（§8.3：墨 / 纸 / 霓虹 / 奶油 / 森野 / 曜黑）', () {
    test('恰好 6 套且 id 唯一、按 sort 排序', () {
      expect(kSlimcaPresetThemeProfiles, hasLength(6));
      final Set<String> ids = kSlimcaPresetThemeProfiles
          .map((ThemeProfile p) => p.id)
          .toSet();
      expect(ids, hasLength(6));
      expect(
        kSlimcaPresetThemeProfiles.map((ThemeProfile p) => p.sort).toList(),
        orderedEquals(<int>[0, 1, 2, 3, 4, 5]),
      );
      for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
        expect(p.isPreset, isTrue, reason: '${p.name} 应为内置包');
      }
    });

    test('按名称/按 id 可查', () {
      expect(presetThemeProfileById('preset-yaohei')!.name, '曜黑');
      expect(presetThemeProfileById('preset-mo')!.name, '墨');
      expect(presetThemeProfileById('custom-xxx'), isNull);
    });

    test('曜黑为 AMOLED 纯黑包，其余非纯黑（§8.3 独立开关）', () {
      expect(presetThemeProfileById('preset-yaohei')!.pureBlackDark, isTrue);
      for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
        if (p.id != 'preset-yaohei') {
          expect(p.pureBlackDark, isFalse, reason: '${p.name} 不应开纯黑');
        }
      }
    });
  });

  group('双主色锚定（§8.2：绿是吃、橘是钱，全包全亮度）', () {
    // 色相窗口：HCT 生成种子无漂移；token 侧 gamut 映射允许小幅偏转
    const double hueTolerance = 8.0;

    for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
      for (final Brightness brightness in Brightness.values) {
        test('${p.name}/${brightness.name}：kcalIn≈150、moneyOut≈62', () {
          final SlimcaTheme tokens = p.toSlimcaTheme(brightness);
          final Hct kcal = Hct.fromInt(tokens.kcalIn.toARGB32());
          final Hct money = Hct.fromInt(tokens.moneyOut.toARGB32());
          expect(
            kcal.hue,
            closeTo(150, hueTolerance),
            reason: '${p.name} ${brightness.name} kcalIn 色相应锚定 150',
          );
          expect(
            money.hue,
            closeTo(62, hueTolerance),
            reason: '${p.name} ${brightness.name} moneyOut 色相应锚定 62',
          );
        });
      }
    }
  });

  group('WCAG AA 护栏：6 包 × 深浅全部达标（§8.3 验收口径）', () {
    for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
      for (final Brightness brightness in Brightness.values) {
        test('${p.name}/${brightness.name} 全对达标', () {
          final SlimcaTheme tokens = p.toSlimcaTheme(brightness);
          for (final SlimcaAaPairResult r in auditSlimcaAa(tokens)) {
            expect(
              r.pass,
              isTrue,
              reason:
                  '${p.name}/${brightness.name} ${r.label} '
                  '应≥${r.threshold}:1（实测 ${r.ratio.toStringAsFixed(2)}）',
            );
          }
        });
      }
    }

    test('护栏降级可观测：默认浅色包至少修正一对外延 tone（moneyIn/kcalOut）', () {
      // §8.3 护栏的价值锚：W1 默认推导中浅色 moneyIn/kcalOut（tone70 量级）
      // 外延 tone 不达 AA 正文阈值，护栏自动降级到最近安全 tone
      final SlimcaTheme raw = kSlimcaPresetThemeProfiles.first.toSlimcaTheme(
        Brightness.light,
        enforceAa: false,
      );
      final SlimcaTheme fixed = kSlimcaPresetThemeProfiles.first.toSlimcaTheme(
        Brightness.light,
      );
      final int rawFails = auditSlimcaAa(
        raw,
      ).where((SlimcaAaPairResult r) => !r.pass).length;
      expect(rawFails, greaterThan(0), reason: '原始推导应存在不达标对');
      expect(
        auditSlimcaAa(fixed).every((SlimcaAaPairResult r) => r.pass),
        isTrue,
        reason: '护栏执行后全对达标',
      );
      expect(
        Hct.fromInt(fixed.moneyIn.toARGB32()).tone,
        isNot(Hct.fromInt(raw.moneyIn.toARGB32()).tone),
        reason: 'moneyIn 应被降级到不同 tone',
      );
    });
  });

  group('包间差异（换肤可见性）', () {
    test('中性基底各包异色（背景层级可感知）', () {
      final Set<Color> surfaces = kSlimcaPresetThemeProfiles
          .map((ThemeProfile p) => p.toSlimcaTheme(Brightness.dark).surface)
          .toSet();
      // 曜黑纯黑与其余深底至少两类色
      expect(surfaces.length, greaterThanOrEqualTo(5));
    });

    test('浅/深种子对各自派生不同 token（§8.3 深浅独立校验）', () {
      for (final ThemeProfile p in kSlimcaPresetThemeProfiles) {
        final SlimcaTheme light = p.toSlimcaTheme(Brightness.light);
        final SlimcaTheme dark = p.toSlimcaTheme(Brightness.dark);
        expect(
          light.surface.computeLuminance(),
          greaterThan(dark.surface.computeLuminance()),
          reason: '${p.name} 浅色底应亮于深色底',
        );
      }
    });
  });
}
