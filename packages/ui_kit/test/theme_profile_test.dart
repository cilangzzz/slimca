import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:ui_kit/ui_kit.dart';

/// ThemeProfile 模型测试（§5.6⑳ 行形状对齐 / §8.2 四滑杆 / §8.3 lerp）。
void main() {
  // 样板包：种子色按 §8.2 锚定色相构造
  ThemeProfile sample({bool pureBlackDark = false}) => ThemeProfile(
    id: 'profile-sample',
    name: '样例',
    lightSeeds: SlimcaSeedSet(
      kcal: Color(Hct.from(150, 55, 40).toInt()),
      money: Color(Hct.from(62, 68, 45).toInt()),
      danger: Color(Hct.from(27, 72, 45).toInt()),
      neutral: Color(Hct.from(250, 8, 40).toInt()),
    ),
    darkSeeds: SlimcaSeedSet(
      kcal: Color(Hct.from(150, 55, 80).toInt()),
      money: Color(Hct.from(62, 68, 80).toInt()),
      danger: Color(Hct.from(27, 72, 80).toInt()),
      neutral: Color(Hct.from(250, 8, 80).toInt()),
    ),
    radiusScale: 1.2,
    density: 0.9,
    fontScale: 1.1,
    motionScale: 1.3,
    motionLevel: MotionLevel.reduced,
    fontId: 'font-slimca',
    sort: 7,
    pureBlackDark: pureBlackDark,
  );

  // 钳制/量程单测的最小样板种子（滑杆钳制只看标量，种子为必填占位）。
  SlimcaSeedSet seeds(double tone) => SlimcaSeedSet(
    kcal: Color(Hct.from(150, 55, tone).toInt()),
    money: Color(Hct.from(62, 68, tone).toInt()),
    danger: Color(Hct.from(27, 72, tone).toInt()),
    neutral: Color(Hct.from(250, 8, tone).toInt()),
  );

  group('序列化：theme_profiles 行形状（§5.6⑳ / drift ThemeProfile.fromJson 键）', () {
    test('行 JSON 键名与 theme_profiles 列一一对应', () {
      final Map<String, Object?> row = sample().toJsonRow();
      expect(
        row.keys,
        unorderedEquals(<String>[
          'id',
          'name',
          'tokens',
          'motionLevel',
          'fontId',
          'isPreset',
          'sort',
        ]),
      );
      // tokens 是 JSON 字符串（§5.6⑳ tokens TEXT(JSON)）
      expect(row['tokens'], isA<String>());
      final Map<String, Object?> tokens =
          jsonDecode(row['tokens'] as String) as Map<String, Object?>;
      expect(
        tokens.keys,
        containsAll(<String>[
          'light',
          'dark',
          'radiusScale',
          'density',
          'fontScale',
          'motionScale',
          'pureBlackDark',
        ]),
      );
      expect(
        (tokens['light'] as Map<String, Object?>).keys,
        unorderedEquals(<String>['kcal', 'money', 'danger', 'neutral']),
      );
    });

    test('行 JSON 往返无损（tokens 字符串 → 原包等值）', () {
      final ThemeProfile origin = sample();
      final ThemeProfile restored = ThemeProfile.fromJsonRow(
        origin.toJsonRow(),
      );
      expect(restored, equals(origin));
      expect(restored.motionLevel, MotionLevel.reduced);
      expect(restored.fontId, 'font-slimca');
      expect(restored.sort, 7);
    });

    test('tokens 兼容直传 Map 形状（sync payload 复用）', () {
      final ThemeProfile origin = sample();
      final Map<String, Object?> row = origin.toJsonRow();
      row['tokens'] = jsonDecode(row['tokens'] as String); // 字符串 → Map
      expect(ThemeProfile.fromJsonRow(row), equals(origin));
    });

    test('未知 motionLevel 回退 full（前向兼容，§6.4）', () {
      final Map<String, Object?> row = sample().toJsonRow()
        ..['motionLevel'] = 'future-level';
      expect(ThemeProfile.fromJsonRow(row).motionLevel, MotionLevel.full);
    });
  });

  group('滑杆量程钳制（§8.2 / §8.3 motionScale 0.6x-1.5x）', () {
    test('motionScale 越界钳制到 0.6-1.5', () {
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          motionScale: 2.5,
        ).motionScale,
        MotionConfig.motionScaleMax,
      );
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          motionScale: 0.1,
        ).motionScale,
        MotionConfig.motionScaleMin,
      );
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          motionScale: 1.3,
        ).copyWith(motionScale: 9.9).motionScale,
        MotionConfig.motionScaleMax,
      );
    });

    test('radiusScale/density/fontScale 各自量程钳制', () {
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          radiusScale: 5,
        ).radiusScale,
        ThemeProfile.radiusScaleMax,
      );
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          density: 0.1,
        ).density,
        ThemeProfile.densityMin,
      );
      expect(
        ThemeProfile(
          id: 'a',
          name: 'a',
          lightSeeds: seeds(40),
          darkSeeds: seeds(80),
          fontScale: 3,
        ).fontScale,
        ThemeProfile.fontScaleMax,
      );
    });
  });

  group('toSlimcaTheme（§8.2 第 1→2 层派生 + 护栏 + 纯黑开关）', () {
    test('滑杆写入 token，种子派生过 AA 护栏', () {
      final SlimcaTheme light = sample().toSlimcaTheme(Brightness.light);
      expect(light.radiusScale, 1.2);
      expect(light.density, 0.9);
      expect(light.fontScale, 1.1);
      expect(light.motionScale, 1.3);
      // 护栏（§8.3）：派生结果全对达标
      expect(
        auditSlimcaAa(light).every((SlimcaAaPairResult r) => r.pass),
        isTrue,
      );
      // 双主色锚定（§8.2）：kcalIn 绿 / moneyOut 橘
      expect(light.kcalIn.g, greaterThan(light.kcalIn.r));
      expect(light.moneyOut.r, greaterThan(light.moneyOut.g));
    });

    test('曜黑 AMOLED：深色 surface 纯黑（§8.3 独立开关）', () {
      final ThemeProfile yaohei = sample(pureBlackDark: true);
      final SlimcaTheme dark = yaohei.toSlimcaTheme(Brightness.dark);
      expect(dark.surface, const Color(0xFF000000));
      expect(
        dark.surface.computeLuminance(),
        lessThan(SlimcaTheme.dark.surface.computeLuminance()),
      );
      // 浅色不受纯黑开关影响
      expect(
        yaohei.toSlimcaTheme(Brightness.light).surface,
        isNot(const Color(0xFF000000)),
      );
    });

    test('motionLevel → MotionConfig 派生（§9.2 forLevel）', () {
      final MotionConfig motion = sample().toMotionConfig();
      expect(motion.level, MotionLevel.reduced);
      // reduced × 滑杆 1.3 → dur.l = 168 × 1.3 = 218.4 → 218ms
      expect(motion.durL, const Duration(milliseconds: 218));
    });
  });

  group('lerp（§8.3 主题切换插值口径）', () {
    late ThemeProfile a;
    late ThemeProfile b;

    setUp(() {
      a = sample();
      b = ThemeProfile(
        id: 'profile-b',
        name: '乙包',
        lightSeeds: SlimcaSeedSet(
          kcal: Color(Hct.from(150, 45, 40).toInt()),
          money: Color(Hct.from(62, 55, 45).toInt()),
          danger: Color(Hct.from(27, 64, 45).toInt()),
          neutral: Color(Hct.from(80, 6, 40).toInt()),
        ),
        darkSeeds: a.darkSeeds,
        radiusScale: 0.6,
        density: 1.1,
        fontScale: 0.9,
        motionScale: 0.7,
        motionLevel: MotionLevel.off,
        sort: 9,
        pureBlackDark: true,
      );
    });

    test('端点：t=0 为 a、t=1 为 b', () {
      expect(a.lerp(b, 0.0), equals(a));
      expect(a.lerp(b, 1.0), equals(b));
    });

    test('中点：颜色/滑杆取均值，离散字段按半程切换', () {
      final ThemeProfile mid = a.lerp(b, 0.5);
      expect(
        mid.lightSeeds.kcal,
        Color.lerp(a.lightSeeds.kcal, b.lightSeeds.kcal, 0.5),
      );
      expect(mid.radiusScale, closeTo((1.2 + 0.6) / 2, 1e-9));
      expect(mid.density, closeTo((0.9 + 1.1) / 2, 1e-9));
      expect(mid.fontScale, closeTo((1.1 + 0.9) / 2, 1e-9));
      expect(mid.motionScale, closeTo((1.3 + 0.7) / 2, 1e-9));
      // 离散字段：t≤0.5 取 a、t>0.5 取 b（与 MotionConfig.lerp 同规则）
      expect(a.lerp(b, 0.4).motionLevel, MotionLevel.reduced);
      expect(a.lerp(b, 0.6).motionLevel, MotionLevel.off);
      expect(a.lerp(b, 0.6).id, 'profile-b');
    });
  });
}
