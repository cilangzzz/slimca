import 'package:flutter/material.dart' show Curves, Cubic;
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// W17 插曲新增 MotionConfig 曲线 token 测试（UI-规范与重设计.md §2.2 新增
/// token 表 / §1.2 缓动曲线）：curveExpand / curveCollapse / curveEffectsStandard
/// 三档在 full/reduced/off 三级 MotionLevel 下的取值、缩放/插值行为与
/// 「effects 禁过冲」判定线。
///
/// 既有时长/弹簧 token 断言见 motion_config_test.dart（W17 未改动，全兼容）。
void main() {
  group('§2.2 新增曲线 token 默认值（MotionLevel=full）', () {
    test('curveExpand = emphasized-decelerate (0.05, 0.7, 0.1, 1)', () {
      const MotionConfig m = MotionConfig.full;
      // const Cubic 规范化后为同一实例（token 表 const 冻结，值即官方参数）
      expect(
        identical(m.curveExpand, const Cubic(0.05, 0.7, 0.1, 1.0)),
        isTrue,
      );
      // 端点
      expect(m.curveExpand.transform(0.0), 0.0);
      expect(m.curveExpand.transform(1.0), closeTo(1.0, 1e-9));
      // decelerate：前半程快（中点 > 0.5），进场 ease-out 语义
      expect(m.curveExpand.transform(0.5), greaterThan(0.5));
    });

    test('curveCollapse = emphasized-accelerate (0.3, 0.0, 0.8, 0.15)', () {
      const MotionConfig m = MotionConfig.full;
      expect(
        identical(m.curveCollapse, const Cubic(0.3, 0.0, 0.8, 0.15)),
        isTrue,
      );
      expect(m.curveCollapse.transform(0.0), 0.0);
      expect(m.curveCollapse.transform(1.0), closeTo(1.0, 1e-9));
      // accelerate：前半程慢（中点 < 0.5），出场 ease-in 语义
      expect(m.curveCollapse.transform(0.5), lessThan(0.5));
    });

    test(
      'curveEffectsStandard = expressive default effects (0.34, 0.80, 0.34, 1)',
      () {
        const MotionConfig m = MotionConfig.full;
        expect(
          identical(
            m.curveEffectsStandard,
            const Cubic(0.34, 0.80, 0.34, 1.00),
          ),
          isTrue,
        );
        expect(m.curveEffectsStandard.transform(0.0), 0.0);
        expect(m.curveEffectsStandard.transform(1.0), closeTo(1.0, 1e-9));
        // effects 档曲线前段快速推进（P1y=0.80 前载型）：x=0.5 处 y≈0.905
        // （官方 expressive default effects 参数定死曲线形状，§2.2 token 表）
        expect(m.curveEffectsStandard.transform(0.5), closeTo(0.905, 0.01));
      },
    );

    test('effects 禁过冲判定线：全采样 ≤1（spatial 类才允许过冲，§1.2）', () {
      const MotionConfig m = MotionConfig.full;
      double maxEffects = 0.0;
      double maxExpand = 0.0;
      double minCollapse = 1.0;
      for (int i = 0; i <= 200; i++) {
        final double t = i / 200;
        final double e = m.curveEffectsStandard.transform(t);
        final double x = m.curveExpand.transform(t);
        final double c = m.curveCollapse.transform(t);
        if (e > maxEffects) maxEffects = e;
        if (x > maxExpand) maxExpand = x;
        if (c < minCollapse) minCollapse = c;
      }
      expect(
        maxEffects,
        lessThanOrEqualTo(1.0001),
        reason: 'curveEffectsStandard 为透明度/颜色专用，禁过冲（§2.2 判定线）',
      );
      expect(
        maxExpand,
        lessThanOrEqualTo(1.0001),
        reason: 'emphasized-decelerate 无过冲',
      );
      expect(minCollapse, greaterThanOrEqualTo(-0.0001), reason: '单调不越界');
      expect(minCollapse, lessThanOrEqualTo(1.0001));
    });
  });

  group('三档 MotionLevel 下的曲线档（§2.2 补全不破坏原则）', () {
    test('reduced：曲线不随 0.6x 缩放（缩放的是时长）', () {
      const MotionConfig m = MotionConfig.reduced;
      expect(
        identical(m.curveExpand, const Cubic(0.05, 0.7, 0.1, 1.0)),
        isTrue,
      );
      expect(
        identical(m.curveCollapse, const Cubic(0.3, 0.0, 0.8, 0.15)),
        isTrue,
      );
      expect(
        identical(m.curveEffectsStandard, const Cubic(0.34, 0.80, 0.34, 1.00)),
        isTrue,
      );
    });

    test('off：照既有惯例线性化（不改 offFadeDuration=100ms 语义）', () {
      const MotionConfig m = MotionConfig.off;
      expect(identical(m.curveExpand, Curves.linear), isTrue);
      expect(identical(m.curveCollapse, Curves.linear), isTrue);
      expect(identical(m.curveEffectsStandard, Curves.linear), isTrue);
    });

    test('scaled：曲线随 token 整体保留，不参与缩放', () {
      final MotionConfig scaled = MotionConfig.full.scaled(1.2);
      expect(
        identical(scaled.curveExpand, MotionConfig.full.curveExpand),
        isTrue,
      );
      expect(
        identical(scaled.curveCollapse, MotionConfig.full.curveCollapse),
        isTrue,
      );
      expect(
        identical(
          scaled.curveEffectsStandard,
          MotionConfig.full.curveEffectsStandard,
        ),
        isTrue,
      );
    });
  });

  group('lerp / copyWith / ==（ThemeExtension 契约含新字段）', () {
    test('lerp 曲线按 t 前后半程切换（既有惯例）', () {
      final MotionConfig mid = MotionConfig.full.lerp(MotionConfig.off, 0.4);
      expect(identical(mid.curveExpand, MotionConfig.full.curveExpand), isTrue);
      final MotionConfig later = MotionConfig.full.lerp(MotionConfig.off, 0.6);
      expect(identical(later.curveExpand, Curves.linear), isTrue);
    });

    test('copyWith 可替换新字段且参与相等性', () {
      const MotionConfig m = MotionConfig.full;
      final MotionConfig c = m.copyWith(curveExpand: Curves.linear);
      expect(c.curveExpand, Curves.linear);
      expect(c, isNot(m));
      expect(m.copyWith(), equals(m));
    });
  });
}
