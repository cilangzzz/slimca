import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 约束 token 层——间距尺度（UI-规范与重设计.md §2.2 新增 token 表、§1.3 间距尺度
/// 8dp 全档；本插曲「补全」三层架构，不破坏既有 SlimcaTheme/MotionConfig）。
///
/// 取值全部落在 M3 官方间距刻度（m3.material.io/styles/spacing/tokens 枚举
/// 0/2/4/6/8/10/12/14/16/20/24/32/36/40/48/56/64/72）与 TDesign `t_spacers.dart`
/// 同刻度档（8/12/16/24/32/48，源码验证），不发明新值；「够用原则」只取 8 档。
///
/// Slimca 落点（§1.3）：卡内 12 / 卡间与行内水平 16 / 分组间 24 / 页边 24 /
/// 区块间 32——组件按用途取语义位（[cardInner]/[inline]/[groupGap]…）防错档；
/// 任务定稿的 xs/s/m/l/xl/xxl 梯度别名见对应 getter（映射到 canonical 档位，
/// space250=20 / space600=48 仅按 canonical 名取用）。
///
/// 本扩展与 SlimcaTheme / MotionConfig 同属第 2 层语义 token，经 buildTheme
/// 挂进主题；组件层（第 3 层）只允许引用本层取值，禁止裸间距字面量（§8.2）。
class SlimcaSpacing extends ThemeExtension<SlimcaSpacing> {
  const SlimcaSpacing({
    this.space50 = 4.0,
    this.space100 = 8.0,
    this.space150 = 12.0,
    this.space200 = 16.0,
    this.space250 = 20.0,
    this.space300 = 24.0,
    this.space400 = 32.0,
    this.space600 = 48.0,
  });

  /// 默认档（§1.3 全档官方值）；宿主主题未挂载本扩展时的回退值。
  static const SlimcaSpacing standard = SlimcaSpacing();

  /// 4dp——色点直径、微内衬（M3 space50）。
  final double space50;

  /// 8dp——基线档：触控目标间最小间距（§1.4 ≥8dp）、图标/文字间（M3 space100）。
  final double space100;

  /// 12dp——卡内 padding、分组卡内 tile 水平 padding（§4.2 NavigationDrawer 口径）。
  final double space150;

  /// 16dp——卡间与行内水平 padding（M3 Expressive small padding，§4.2）。
  final double space200;

  /// 20dp——宽松行内/卡间备选档（M3 space250）。
  final double space250;

  /// 24dp——分组卡之间、页边（§4.2 组间 24/页边 24 = space300；M3 search 容器
  /// 水平 margin 官方 24dp，spacing/overview）。
  final double space300;

  /// 32dp——区块之间（§1.3 区块间 32 = space400）。
  final double space400;

  /// 48dp——大区段间/页边大档（M3 space600；亦等于 minTouchTarget 量级）。
  final double space600;

  // ── 梯度别名（任务定稿「8dp grid 档位：xs/s/m/l/xl/xxl」→ canonical 映射）──
  /// xs = 4：微间距（色点、紧凑内衬）。
  double get xs => space50;

  /// s = 8：基线间距（目标间距、图标与文字间）。
  double get s => space100;

  /// m = 12：卡内 padding。
  double get m => space150;

  /// l = 16：行内水平/卡间。
  double get l => space200;

  /// xl = 24：分组间/页边。
  double get xl => space300;

  /// xxl = 32：区块间。
  double get xxl => space400;

  // ── 语义位（§1.3 Slimca 落点，按用途取值）────────────────────────────
  /// 卡内 padding / 分组卡内 tile 水平 padding = 12（§4.2 定稿「分组卡→12」）。
  double get cardInner => space150;

  /// 行内水平 / 卡与卡之间 = 16（§5#1「卡间距 12（space150）保留」之上的
  /// 行内水平基线，§1.3 落点「卡间与行内水平 16」）。
  double get inline => space200;

  /// 分组卡之间 = 24（§4.2「组间 24dp」）。
  double get groupGap => space300;

  /// 页边 = 24（§4.2「页边 24dp（space300）」）。
  double get pageMargin => space300;

  /// 区块之间 = 32（§1.3「区块间 32」）。
  double get sectionGap => space400;

  /// 拷贝并替换字段（ThemeExtension 契约）。
  @override
  SlimcaSpacing copyWith({
    double? space50,
    double? space100,
    double? space150,
    double? space200,
    double? space250,
    double? space300,
    double? space400,
    double? space600,
  }) => SlimcaSpacing(
    space50: space50 ?? this.space50,
    space100: space100 ?? this.space100,
    space150: space150 ?? this.space150,
    space200: space200 ?? this.space200,
    space250: space250 ?? this.space250,
    space300: space300 ?? this.space300,
    space400: space400 ?? this.space400,
    space600: space600 ?? this.space600,
  );

  /// 主题切换 morph 的插值（§8.3「ThemeExtensionTween 自实现 lerp」同契约）。
  @override
  SlimcaSpacing lerp(covariant ThemeExtension<SlimcaSpacing>? other, double t) {
    if (identical(this, other) || other == null) return this;
    final SlimcaSpacing o = other as SlimcaSpacing;
    return SlimcaSpacing(
      space50: lerpDouble(space50, o.space50, t)!,
      space100: lerpDouble(space100, o.space100, t)!,
      space150: lerpDouble(space150, o.space150, t)!,
      space200: lerpDouble(space200, o.space200, t)!,
      space250: lerpDouble(space250, o.space250, t)!,
      space300: lerpDouble(space300, o.space300, t)!,
      space400: lerpDouble(space400, o.space400, t)!,
      space600: lerpDouble(space600, o.space600, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SlimcaSpacing &&
        other.space50 == space50 &&
        other.space100 == space100 &&
        other.space150 == space150 &&
        other.space200 == space200 &&
        other.space250 == space250 &&
        other.space300 == space300 &&
        other.space400 == space400 &&
        other.space600 == space600;
  }

  @override
  int get hashCode => Object.hash(
    space50,
    space100,
    space150,
    space200,
    space250,
    space300,
    space400,
    space600,
  );

  @override
  String toString() =>
      'SlimcaSpacing(space50: $space50, space300: $space300, space400: $space400)';
}

/// 间距 token 读取入口；宿主主题未挂载时回退 [SlimcaSpacing.standard]
/// （防御第三方 ThemeData 缺省，与 SlimcaTheme/MotionConfig 回退惯例一致）。
extension SlimcaSpacingBuildContext on BuildContext {
  SlimcaSpacing get spacing =>
      Theme.of(this).extension<SlimcaSpacing>() ?? SlimcaSpacing.standard;
}
