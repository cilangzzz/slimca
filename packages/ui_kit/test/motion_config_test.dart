import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// MotionConfig（§9.2 动效 token 表）默认值、降级档与 lerp 测试。
void main() {
  group('§9.2 token 表默认值（MotionLevel=full）', () {
    test('时长表', () {
      const MotionConfig m = MotionConfig.full;
      expect(m.level, MotionLevel.full);
      expect(m.durXs, const Duration(milliseconds: 60), reason: 'dur.xs 微反馈');
      expect(
        m.durS,
        const Duration(milliseconds: 120),
        reason: 'dur.s chip/勾选',
      );
      expect(m.durM, const Duration(milliseconds: 180), reason: 'dur.m 卡片上浮');
      expect(
        m.durL,
        const Duration(milliseconds: 280),
        reason: 'dur.l 抽屉/页面/共享轴',
      );
      expect(
        m.durXl,
        const Duration(milliseconds: 450),
        reason: 'dur.xl 落库飞入/容器变换',
      );
      expect(
        m.staggerInterval,
        const Duration(milliseconds: 80),
        reason: '§2.3/§9.3#1 级联间隔',
      );
      expect(
        m.countUpDuration,
        const Duration(milliseconds: 800),
        reason: '§9.3#4 count-up',
      );
      expect(
        m.themeMorphDuration,
        const Duration(milliseconds: 300),
        reason: '§9.3#10 主题 morph',
      );
      expect(
        m.offFadeDuration,
        const Duration(milliseconds: 100),
        reason: '§9.6 降级淡入淡出',
      );
    });

    test('弹簧表', () {
      const MotionConfig m = MotionConfig.full;
      expect(m.springSnappy.settleDuration, const Duration(milliseconds: 220));
      expect(m.springSnappy.dampingRatio, 1.0);
      expect(m.springSoft.settleDuration, const Duration(milliseconds: 400));
      expect(m.springSoft.dampingRatio, closeTo(0.85, 1e-12));
      expect(m.springSnappy.stiffness, greaterThan(0));
      expect(m.springSnappy.damping, greaterThan(0));
      expect(m.springSoft.stiffness, greaterThan(0));
      expect(m.springSoft.damping, greaterThan(0));
    });

    test('「用途」具名映射对齐 §9.2 用途列', () {
      const MotionConfig m = MotionConfig.full;
      expect(m.microFeedback, m.durXs);
      expect(m.chipCheck, m.durS);
      expect(m.cardFloat, m.durM);
      expect(m.drawer, m.durL);
      expect(m.page, m.durL);
      expect(m.sharedAxis, m.durL);
      expect(m.containerTransform, m.durXl);
      expect(m.heroFlight, m.durXl);
      expect(m.cascadeInterval, m.staggerInterval);
      expect(m.countUp, m.countUpDuration);
      expect(m.themeMorph, m.themeMorphDuration);
      expect(m.fadeOff, m.offFadeDuration);
    });
  });

  group('MotionLevel 降级阶梯（§9.2/§9.6）', () {
    test('reduced = 0.6x（§8.3 减弱动态效果）', () {
      const MotionConfig m = MotionConfig.reduced;
      expect(m.level, MotionLevel.reduced);
      expect(m.durL, const Duration(milliseconds: 168)); // 280 × 0.6
      expect(m.durXl, const Duration(milliseconds: 270)); // 450 × 0.6
      expect(m.springSnappy.settleDuration, const Duration(milliseconds: 132));
      expect(m.springSoft.settleDuration, const Duration(milliseconds: 240));
    });

    test('off = 全部 100ms 淡入淡出（§9.6）', () {
      const MotionConfig m = MotionConfig.off;
      expect(m.level, MotionLevel.off);
      expect(m.durXs, const Duration(milliseconds: 100));
      expect(m.durL, const Duration(milliseconds: 100));
      expect(m.durXl, const Duration(milliseconds: 100));
      expect(m.staggerInterval, const Duration(milliseconds: 100));
    });

    test('forLevel 合成 motionScale 滑杆（§8.2/§8.3）', () {
      expect(
        MotionConfig.forLevel(MotionLevel.full).durL,
        const Duration(milliseconds: 280),
      );
      expect(
        MotionConfig.forLevel(MotionLevel.full, motionScale: 1.5).durL,
        const Duration(milliseconds: 420), // 280 × 1.5
      );
      expect(
        MotionConfig.forLevel(MotionLevel.reduced).durL,
        const Duration(milliseconds: 168),
      );
      // off 直接降级，不叠加滑杆（§9.6）
      expect(
        MotionConfig.forLevel(MotionLevel.off, motionScale: 1.5).durL,
        const Duration(milliseconds: 100),
      );
      // 滑杆量程钳制 0.6-1.5（§8.3）
      expect(
        MotionConfig.forLevel(MotionLevel.full, motionScale: 3.0).durL,
        const Duration(milliseconds: 420),
      );
      expect(
        MotionConfig.forLevel(MotionLevel.full, motionScale: 0.1).durL,
        const Duration(milliseconds: 168), // 钳到 0.6 → 280 × 0.6
      );
    });
  });

  group('MotionConfig.lerp（§8.3 主题切换参与 ThemeExtension lerp）', () {
    final MotionConfig a = MotionConfig.full;
    final MotionConfig b = MotionConfig.off;

    test('端点与中点', () {
      expect(a.lerp(b, 0.0), equals(a));
      expect(a.lerp(b, 1.0), equals(b));
      final MotionConfig mid = a.lerp(b, 0.5);
      expect(mid.durL, const Duration(milliseconds: 190)); // (280+100)/2
      expect(mid.durXl, const Duration(milliseconds: 275)); // (450+100)/2
      expect(mid.level, MotionLevel.full); // t<0.5 取 a
      expect(a.lerp(b, 0.6).level, MotionLevel.off);
      expect(a.lerp(null, 0.4), same(a));
    });

    test('弹簧插值', () {
      final MotionConfig mid = MotionConfig.full.lerp(
        MotionConfig.reduced,
        0.5,
      );
      // (220 + 132) / 2
      expect(
        mid.springSnappy.settleDuration,
        const Duration(milliseconds: 176),
      );
      expect(mid.springSnappy.dampingRatio, closeTo(1.0, 1e-9));
      // (400 + 240) / 2
      expect(mid.springSoft.settleDuration, const Duration(milliseconds: 320));
    });

    test('== 与 copyWith', () {
      expect(MotionConfig.full, equals(MotionConfig.full));
      final MotionConfig c = MotionConfig.full.copyWith(
        durL: const Duration(milliseconds: 300),
      );
      expect(c.durL, const Duration(milliseconds: 300));
      expect(c.durXs, MotionConfig.full.durXs);
      expect(c, isNot(MotionConfig.full));
    });
  });

  group('SlimcaSpring 与 SpringCurve（§10.1 自研单自由度弹簧）', () {
    test('curve 端点收敛', () {
      for (final spring in <SlimcaSpring>[
        MotionConfig.full.springSnappy,
        MotionConfig.full.springSoft,
      ]) {
        final Curve curve = spring.curve;
        expect(curve.transform(0.0), closeTo(0.0, 1e-9));
        expect(curve.transform(1.0), closeTo(1.0, 0.02), reason: '整定时长内收敛到 1');
      }
    });

    test('curve 中段进度合理', () {
      for (final spring in <SlimcaSpring>[
        MotionConfig.full.springSnappy,
        MotionConfig.full.springSoft,
      ]) {
        final double v = spring.curve.transform(0.5);
        expect(v, greaterThan(0.5));
        expect(v, lessThan(1.05));
      }
    });

    test('springSoft 轻微过冲（阻尼比 0.85），springSnappy 不回弹', () {
      double maxSoft = 0.0;
      for (var i = 0; i <= 200; i++) {
        maxSoft = math.max(
          maxSoft,
          MotionConfig.full.springSoft.curve.transform(i / 200),
        );
      }
      expect(maxSoft, greaterThan(1.0), reason: 'ζ=0.85 应有轻微回弹');
      expect(maxSoft, lessThan(1.05));

      double maxSnappy = 0.0;
      for (var i = 0; i <= 200; i++) {
        maxSnappy = math.max(
          maxSnappy,
          MotionConfig.full.springSnappy.curve.transform(i / 200),
        );
      }
      expect(maxSnappy, lessThanOrEqualTo(1.0001), reason: 'ζ=1.0 临界阻尼不回弹');
    });

    test('simulation 收敛（拖拽速度继承的数值底座 §9.3#3）', () {
      final sim = MotionConfig.full.springSnappy.simulation(start: 0, end: 1);
      expect(sim.x(1.0), closeTo(1.0, 0.01));
      expect(sim.isDone(0.5), isTrue);
    });

    test('scaled 缩放整定时长', () {
      final SlimcaSpring s = MotionConfig.full.springSnappy.scaled(0.5);
      expect(s.settleDuration, const Duration(milliseconds: 110));
      expect(s.dampingRatio, 1.0);
    });
  });
}
