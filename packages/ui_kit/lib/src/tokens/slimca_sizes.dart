import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// 约束 token 层——尺寸/命中/行高/圆角/状态层（UI-规范与重设计.md §2.2 新增
/// token 表、§1.4 触碰目标与状态层、§1.5 行高与列表约束、§3.3 日历组件参数、
/// §4.2 菜单行规格）。
///
/// 所有数值为官方刻度值（来源逐项标注），推导项显式标注；组件层（第 3 层）
/// 只允许引用本层取值，禁止裸尺寸字面量（§8.2 第 3 层）。
class SlimcaSizes extends ThemeExtension<SlimcaSizes> {
  const SlimcaSizes({
    this.minTouchTarget = 48.0,
    this.pointerTarget = 44.0,
    this.targetGap = 8.0,
    this.iconVisual = 24.0,
    this.iconVisualMax = 40.0,
    this.rowSingleLine = 56.0,
    this.rowTwoLine = 72.0,
    this.rowThreeLine = 88.0,
    this.dayCellVisual = 40.0,
    this.weekStripHeight = 72.0,
    this.radiusCard = 16.0,
    this.radiusGroupCard = 12.0,
    this.monthGridMaxRows = 6,
    this.stateLayerHover = 0.08,
    this.stateLayerFocus = 0.10,
    this.stateLayerPressed = 0.10,
    this.stateLayerDragged = 0.16,
  });

  /// 默认档（全部为官方刻度值）；宿主主题未挂载本扩展时的回退值。
  static const SlimcaSizes standard = SlimcaSizes();

  // ── 触碰目标（§1.4：M3 structure + flutter kMinInteractiveDimension）──
  /// 触屏目标下限 48×48dp（≈9mm，推荐 7-10mm；Flutter `kMinInteractiveDimension`
  /// 注释直引 material.io 无障碍规范，同值）。
  final double minTouchTarget;

  /// 指针目标（鼠标/笔）下限 44×44dp（§1.4 M3 structure）。
  final double pointerTarget;

  /// 相邻目标最小间距 ≥8dp（§1.4；亦即 SlimcaSpacing.space100 档）。
  final double targetGap;

  // ── 图标尺寸（§4.2「leading 视觉 24dp，容器按 48dp 命中布局；视觉上限 40」）──
  /// leading/trailing/chevron 图标视觉尺寸 24dp（M3 structure「24dp 图标+留白凑
  /// 48dp 目标」）。
  final double iconVisual;

  /// leading/trailing 视觉高度上限 40dp（§1.5 flutter list_tile.dart 源码口径）。
  final double iconVisualMax;

  // ── 行高（§1.5：Flutter list_tile.dart 实现口径——1 行 56 / 2 行 72 / 3 行 88）──
  /// 单行（菜单/列表行）行高 56dp（§4.2「行高 单行 56dp；不用 dense」）。
  final double rowSingleLine;

  /// 两行（标题+副标题）行高 72dp（§4.2；亦为周条折叠态高度基准，见
  /// [weekStripHeight]）。
  final double rowTwoLine;

  /// 三行行高 88dp（§1.5 源码口径补全，备用）。
  final double rowThreeLine;

  // ── 日历（§3.3 组件参数定稿值）────────────────────────────────────
  /// 月网格日期格视觉 40×40dp（material-web date-picker token，§1.5/§3.3）。
  final double dayCellVisual;

  /// 周条折叠态高度 72dp（§3.3 推导值，标注非规范原文：容纳星期标签+日期号+
  /// 今日点两行结构）。
  final double weekStripHeight;

  // ── 圆角档（M3 shape scale，§4.2/§5#1）───────────────────────────
  /// 卡片圆角 16（M3 shape large；§5#1 `_DashboardCard`/确认卡合规基线）。
  final double radiusCard;

  /// 分组卡圆角 12（M3 shape medium，§4.2「分组卡 圆角 12」）。
  final double radiusGroupCard;

  /// 月网格最多 6 行（§1.5 M3 date-picker 解剖「月网格最多 6 行」）。
  final int monthGridMaxRows;

  // ── 状态层透明度四档（§1.4 M3 state-layers：hover/focus/pressed/dragged；
  //    状态层用 on 色、一次只叠一层——「组件切换效果没经过设计」的直接解药）──
  /// hover 状态层透明度 0.08。
  final double stateLayerHover;

  /// focus 状态层透明度 0.10。
  final double stateLayerFocus;

  /// pressed 状态层透明度 0.10（§4.2 按压统一 state layer 10%）。
  final double stateLayerPressed;

  /// dragged 状态层透明度 0.16。
  final double stateLayerDragged;

  /// 拷贝并替换字段（ThemeExtension 契约）。
  @override
  SlimcaSizes copyWith({
    double? minTouchTarget,
    double? pointerTarget,
    double? targetGap,
    double? iconVisual,
    double? iconVisualMax,
    double? rowSingleLine,
    double? rowTwoLine,
    double? rowThreeLine,
    double? dayCellVisual,
    double? weekStripHeight,
    double? radiusCard,
    double? radiusGroupCard,
    int? monthGridMaxRows,
    double? stateLayerHover,
    double? stateLayerFocus,
    double? stateLayerPressed,
    double? stateLayerDragged,
  }) => SlimcaSizes(
    minTouchTarget: minTouchTarget ?? this.minTouchTarget,
    pointerTarget: pointerTarget ?? this.pointerTarget,
    targetGap: targetGap ?? this.targetGap,
    iconVisual: iconVisual ?? this.iconVisual,
    iconVisualMax: iconVisualMax ?? this.iconVisualMax,
    rowSingleLine: rowSingleLine ?? this.rowSingleLine,
    rowTwoLine: rowTwoLine ?? this.rowTwoLine,
    rowThreeLine: rowThreeLine ?? this.rowThreeLine,
    dayCellVisual: dayCellVisual ?? this.dayCellVisual,
    weekStripHeight: weekStripHeight ?? this.weekStripHeight,
    radiusCard: radiusCard ?? this.radiusCard,
    radiusGroupCard: radiusGroupCard ?? this.radiusGroupCard,
    monthGridMaxRows: monthGridMaxRows ?? this.monthGridMaxRows,
    stateLayerHover: stateLayerHover ?? this.stateLayerHover,
    stateLayerFocus: stateLayerFocus ?? this.stateLayerFocus,
    stateLayerPressed: stateLayerPressed ?? this.stateLayerPressed,
    stateLayerDragged: stateLayerDragged ?? this.stateLayerDragged,
  );

  /// 主题切换 morph 的插值（§8.3 同契约；行数档位取整防碎片高度）。
  @override
  SlimcaSizes lerp(covariant ThemeExtension<SlimcaSizes>? other, double t) {
    if (identical(this, other) || other == null) return this;
    final SlimcaSizes o = other as SlimcaSizes;
    return SlimcaSizes(
      minTouchTarget: lerpDouble(minTouchTarget, o.minTouchTarget, t)!,
      pointerTarget: lerpDouble(pointerTarget, o.pointerTarget, t)!,
      targetGap: lerpDouble(targetGap, o.targetGap, t)!,
      iconVisual: lerpDouble(iconVisual, o.iconVisual, t)!,
      iconVisualMax: lerpDouble(iconVisualMax, o.iconVisualMax, t)!,
      rowSingleLine: lerpDouble(rowSingleLine, o.rowSingleLine, t)!,
      rowTwoLine: lerpDouble(rowTwoLine, o.rowTwoLine, t)!,
      rowThreeLine: lerpDouble(rowThreeLine, o.rowThreeLine, t)!,
      dayCellVisual: lerpDouble(dayCellVisual, o.dayCellVisual, t)!,
      weekStripHeight: lerpDouble(weekStripHeight, o.weekStripHeight, t)!,
      radiusCard: lerpDouble(radiusCard, o.radiusCard, t)!,
      radiusGroupCard: lerpDouble(radiusGroupCard, o.radiusGroupCard, t)!,
      monthGridMaxRows: t <= 0.5 ? monthGridMaxRows : o.monthGridMaxRows,
      stateLayerHover: lerpDouble(stateLayerHover, o.stateLayerHover, t)!,
      stateLayerFocus: lerpDouble(stateLayerFocus, o.stateLayerFocus, t)!,
      stateLayerPressed: lerpDouble(stateLayerPressed, o.stateLayerPressed, t)!,
      stateLayerDragged: lerpDouble(stateLayerDragged, o.stateLayerDragged, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SlimcaSizes &&
        other.minTouchTarget == minTouchTarget &&
        other.pointerTarget == pointerTarget &&
        other.targetGap == targetGap &&
        other.iconVisual == iconVisual &&
        other.iconVisualMax == iconVisualMax &&
        other.rowSingleLine == rowSingleLine &&
        other.rowTwoLine == rowTwoLine &&
        other.rowThreeLine == rowThreeLine &&
        other.dayCellVisual == dayCellVisual &&
        other.weekStripHeight == weekStripHeight &&
        other.radiusCard == radiusCard &&
        other.radiusGroupCard == radiusGroupCard &&
        other.monthGridMaxRows == monthGridMaxRows &&
        other.stateLayerHover == stateLayerHover &&
        other.stateLayerFocus == stateLayerFocus &&
        other.stateLayerPressed == stateLayerPressed &&
        other.stateLayerDragged == stateLayerDragged;
  }

  @override
  int get hashCode => Object.hash(
    minTouchTarget,
    pointerTarget,
    targetGap,
    iconVisual,
    iconVisualMax,
    rowSingleLine,
    rowTwoLine,
    rowThreeLine,
    dayCellVisual,
    weekStripHeight,
    radiusCard,
    radiusGroupCard,
    monthGridMaxRows,
    stateLayerHover,
    stateLayerFocus,
    stateLayerPressed,
    stateLayerDragged,
  );

  @override
  String toString() =>
      'SlimcaSizes(minTouchTarget: $minTouchTarget, radiusGroupCard: $radiusGroupCard)';
}

/// 尺寸约束 token 读取入口；宿主主题未挂载时回退 [SlimcaSizes.standard]
/// （与 SlimcaTheme/MotionConfig/SlimcaSpacing 回退惯例一致）。
extension SlimcaSizesBuildContext on BuildContext {
  SlimcaSizes get sizes =>
      Theme.of(this).extension<SlimcaSizes>() ?? SlimcaSizes.standard;
}
