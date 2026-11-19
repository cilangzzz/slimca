// SlimcaCookieShapeBorder 几何单测（底栏重设计拍板：花瓣形 FAB）。
//
// 固化两类保障（评审 [13]）：
// 1. 默认常量（12 瓣 / 0.86）的轮廓几何——瓣尖恰落外接半径 R、瓣谷恰在
//    kR、路径闭合且 bounds=rect、无 NaN；
// 2. 失效域守卫——valleyRatio 低于 k_min(n)=cos(π/n)/(1+sin(π/n)) 时
//    getOuterPath 的 debug assert 必须触发（越界为闭式解增根，轮廓自交，
//    且路径仍闭合连续——连续性检查拦不住，见类 dartdoc）。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

void main() {
  // FAB regular 56×56 方形外接盒（getOuterPath 取 shortestSide/2=28）。
  // Rect.fromCenter 非 const 构造，用 fromLTWH 等价表达。
  const Rect rect = Rect.fromLTWH(72, 72, 56, 56);
  const double r = 28;
  const double valley = kSlimcaCookieValleyRatio * r; // ≈ 24.08

  Offset at(double angleRad, double radius) => Offset(
        100 + radius * math.cos(angleRad),
        100 + radius * math.sin(angleRad),
      );

  test('默认常量：12 个瓣尖恰落外接半径 R（内侧含、外侧不含）', () {
    final Path path = const SlimcaCookieShapeBorder().getOuterPath(rect);
    for (int i = 0; i < kSlimcaCookiePetals; i++) {
      final double theta = i * 2 * math.pi / kSlimcaCookiePetals;
      expect(
        path.contains(at(theta, r - 0.5)),
        isTrue,
        reason: '瓣尖内侧 $theta rad 应在轮廓内',
      );
      expect(
        path.contains(at(theta, r + 0.5)),
        isFalse,
        reason: '瓣尖外侧 $theta rad 应在轮廓外',
      );
    }
  });

  test('默认常量：12 个瓣谷恰在 kR（谷内侧含、外侧不含）', () {
    final Path path = const SlimcaCookieShapeBorder().getOuterPath(rect);
    for (int i = 0; i < kSlimcaCookiePetals; i++) {
      final double bisector = i * 2 * math.pi / kSlimcaCookiePetals +
          math.pi / kSlimcaCookiePetals;
      expect(
        path.contains(at(bisector, valley - 0.5)),
        isTrue,
        reason: '瓣谷内侧 $bisector rad 应在轮廓内',
      );
      expect(
        path.contains(at(bisector, valley + 0.5)),
        isFalse,
        reason: '瓣谷外侧 $bisector rad 应在轮廓外',
      );
    }
  });

  test('默认常量：路径闭合、bounds=外接盒、无 NaN', () {
    final Path path = const SlimcaCookieShapeBorder().getOuterPath(rect);
    final metrics = path.computeMetrics().toList();
    expect(metrics, hasLength(1));
    expect(metrics.single.isClosed, isTrue);

    final Rect bounds = path.getBounds();
    // getBounds 对圆锥弧段为控制点保守估计（本形状实测超出约 1.5dp），
    // 容差取 2.0；瓣尖/瓣谷采样用例才是几何真值锚。
    expect(bounds.left, closeTo(rect.left, 2.0));
    expect(bounds.right, closeTo(rect.right, 2.0));
    expect(bounds.top, closeTo(rect.top, 2.0));
    expect(bounds.bottom, closeTo(rect.bottom, 2.0));
    expect(bounds.isFinite, isTrue);
  });

  test('失效域守卫：valleyRatio 低于 k_min(12)=0.7673 时 debug assert 触发', () {
    const invalid = SlimcaCookieShapeBorder(valleyRatio: 0.7);
    expect(
      () => invalid.getOuterPath(rect),
      throwsA(isA<AssertionError>()),
      reason: '越界为闭式解增根（谷点落内交点、弧扫 >π 轮廓自交），必须 fail fast',
    );
  });

  test('有效域下界附近：valleyRatio=0.78（> k_min(12)）不触发 assert', () {
    const nearBound = SlimcaCookieShapeBorder(valleyRatio: 0.78);
    final Path path = nearBound.getOuterPath(rect);
    expect(path.computeMetrics().single.isClosed, isTrue);
  });

  test('相等性：同常量等值、异参数不等', () {
    expect(
      const SlimcaCookieShapeBorder(),
      equals(const SlimcaCookieShapeBorder(
        petals: kSlimcaCookiePetals,
        valleyRatio: kSlimcaCookieValleyRatio,
      )),
    );
    expect(
      const SlimcaCookieShapeBorder(),
      isNot(equals(const SlimcaCookieShapeBorder(valleyRatio: 0.8))),
    );
  });
}
