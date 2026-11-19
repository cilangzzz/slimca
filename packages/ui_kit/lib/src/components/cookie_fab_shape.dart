import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 几何常量（非动效 token，范本 spring_sheet.dart kSlimcaSheet*）：
/// 形态出处 = M3 Expressive shape library「cookie（多瓣花形）」官方形状库；
/// 瓣数/谷径比无规范数值出处 → 拍板推导（大厂设计规范 §1.1 原则 4 口径）。
/// 外接半径取 [FloatingActionButton] regular 56×56 之半（M3 §7.2 尺寸档），
/// 花瓣尖与 FAB 外接圆重合；谷径比 0.86 → 谷径 ≈ 24（R=28 时）。壳层
/// BottomAppBar 显式传 notchMargin: 6（框架默认 4，固化拍板口径）→ 凹槽
/// 半径 = 外接半径 + 6 = 34，与花瓣尖之间留 6dp 间隙环透出页面底，花瓣
/// 完整不被凹槽裁切。
const int kSlimcaCookiePetals = 12;
const double kSlimcaCookieValleyRatio = 0.86;

/// 花瓣形（M3 Expressive「cookie」12 瓣）ShapeBorder——底栏重设计（§4.1
/// 原则 2「中央录入按钮 + 导航栏一体化」）的唯一自绘件。
///
/// 轮廓构造（scallop 花形，精确相交而非贝塞尔近似）：n 片花瓣各是一片圆弧，
/// 花瓣 i 的圆心距原点 d、半径 rp，瓣尖落在原点半径 R 处（d + rp = R）；
/// 相邻花瓣圆的外交点即瓣谷（谷径 Rv = kR）。由 Rv = d·cos(π/n) +
/// sqrt(rp² − d²·sin²(π/n)) 闭式解得
/// `d = R·(1 − k²) / (2·(1 − k·cos(π/n)))`，谷相对花瓣圆心的角偏移
/// `phi = atan2(Rv·sin(π/n), Rv·cos(π/n) − d)`，每片花瓣用一次
/// [Path.arcTo] 从谷到谷经瓣尖扫过 `2·phi`。
///
/// 约束（有效域，平方展开增根边界——改常量前必读）：闭式解只是「平方后
/// 方程」的无条件解，仅当 `kR ≥ d·cos(π/n)` 时才是原方程的根，等价边界为
/// `k > k_min(n) = cos(π/n) / (1 + sin(π/n))` 且 `k < 1`（n=12 → k>0.7673、
/// n=16 → k>0.8207、n=6 → k>0.5774；出厂 0.86 余量 0.093）。越界时谷点落到
/// 相邻花瓣圆的内交点、每瓣弧扫角 2φ > π 从花心内部绕行、轮廓自交——且
/// 路径仍闭合连续，「轮廓连续性」检查拦不住，故 [getOuterPath] 内置 debug
/// assert 兜底。[cookie_fab_shape_test.dart] 以瓣尖/谷径采样断言固化默认
/// 常量的几何。
///
/// lerpFrom/lerpTo 沿基类默认返回 null → [ShapeBorder.lerp] 在双非空时回退
/// 为「t < 0.5 取 a 否则取 b」的硬切（单侧 null 才走 scale+fade，而本类
/// [scale] 保形恒返回等值花瓣，连该路径也是瞬间全尺寸）——不参与 morph
/// （本期零新增动画路径，大厂设计规范 §9 MotionLevel 纪律）。P2 按压 morph
/// 须自行实现 lerpFrom/lerpTo，勿依赖框架回退。
class SlimcaCookieShapeBorder extends ShapeBorder {
  const SlimcaCookieShapeBorder({
    this.petals = kSlimcaCookiePetals,
    this.valleyRatio = kSlimcaCookieValleyRatio,
  });

  /// 瓣数（拍板：12 瓣）。
  final int petals;

  /// 谷径比 k（谷径 = k·外接半径，拍板：0.86）。
  final double valleyRatio;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final double radius = rect.shortestSide / 2;
    final Offset origin = rect.center;
    final double halfStep = math.pi / petals;
    final double k = valleyRatio;
    final double c = math.cos(halfStep);
    final double s = math.sin(halfStep);

    final double d = radius * (1 - k * k) / (2 * (1 - k * c));
    final double rp = radius - d;
    assert(
      k > 0 && k < 1,
      'valleyRatio 必须在 (0,1)：k≥1 时 d≤0 无花瓣、k≤0 无谷',
    );
    assert(
      k * radius >= d * c,
      'valleyRatio 低于有效下界 k_min(n)=cos(π/n)/(1+sin(π/n))（n=$petals 时 '
      '${(c / (1 + s)).toStringAsFixed(4)}）：闭式解成增根，轮廓自交',
    );
    final double phi = math.atan2(k * radius * s, k * radius * c - d);

    final Path path = Path();
    for (int i = 0; i < petals; i++) {
      final double theta = i * 2 * math.pi / petals;
      path.arcTo(
        Rect.fromCircle(
          center: Offset(
            origin.dx + d * math.cos(theta),
            origin.dy + d * math.sin(theta),
          ),
          radius: rp,
        ),
        theta - phi,
        2 * phi,
        i == 0,
      );
    }
    return path..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    // FAB 以 backgroundColor 填充并裁剪到外轮廓，无边框（side 空）；曜黑档
    // 若眼检需要描边兜底，走 Material shape side（几何常量），不在本类画。
  }

  @override
  ShapeBorder scale(double t) =>
      SlimcaCookieShapeBorder(petals: petals, valleyRatio: valleyRatio);

  @override
  bool operator ==(Object other) =>
      other is SlimcaCookieShapeBorder &&
      other.petals == petals &&
      other.valleyRatio == valleyRatio;

  @override
  int get hashCode => Object.hash(petals, valleyRatio);
}
