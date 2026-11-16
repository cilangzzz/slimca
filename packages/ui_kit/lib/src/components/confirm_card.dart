import 'package:flutter/material.dart';

import '../tokens/slimca_theme.dart';
import '../transitions/stagger.dart';

/// 确认卡容器（§3.3「先拍后改确认卡」、§2.3 步骤 3「抽屉原地转为确认卡」）。
///
/// 职责边界：本组件只提供语义 token 卡面（§8.2 surfaceCard）与级联入场插槽
/// （§9.3#1 cascadeInterval 80ms，复用 [SlimcaStaggerItem]），确认卡内容——
/// 置信度三色点（SlimcaConfidenceDot，§7.3）、热量环 sweep（SlimcaCalorieRing
/// sweepEntrance，§9.3#4）、金额 count-up（SlimcaMoneyCountUp）——由业务以插槽
/// 组装；「单确认卡聚合多行状态、行级独立落库」的多行状态机归属 feature_capture
/// （§12.2#8 决策），本容器不感知行数。
///
/// 降级：插槽级联在 MotionLevel=off 时由 SlimcaStaggerItem 自动退化为
/// 100ms 淡入（§9.6），off 档 pumpAndSettle 必然收敛。
class SlimcaConfirmCard extends StatelessWidget {
  const SlimcaConfirmCard({
    super.key,
    required this.slots,
    this.header,
    this.footer,
    this.padding = const EdgeInsets.all(16),
    this.cascade = true,
    this.floatDistance = 16.0,
  });

  /// 卡体内容插槽列表（按序级联入场）：热量环行、金额行、分类九宫格、
  /// 账本/日期行等（§2.3 步骤 3/4）。
  final List<Widget> slots;

  /// 卡头（置信度三色点 + 标题区，§7.3）；静态在场，不参与级联。
  final Widget? header;

  /// 卡尾（确认/取消按钮区，§2.3 步骤 5）；静态在场，不参与级联。
  final Widget? footer;

  /// 卡面内边距。
  final EdgeInsetsGeometry padding;

  /// 是否级联入场（false → 插槽直接在场，供预览/降级场景，§9.6）。
  final bool cascade;

  /// 插槽上浮距离（几何常量，非动效 token；与卡内尺度匹配，小于卡片墙的 24）。
  final double floatDistance;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    return Container(
      // 语义 token 卡面（§8.2 surfaceCard）；圆角 16 为几何常量
      // （radiusScale 滑杆随 P1 主题编辑器接线，§8.3，与仪表盘卡片同口径）
      decoration: BoxDecoration(
        color: tokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.fromBorderSide(BorderSide(color: tokens.outline)),
      ),
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (header != null) header!,
          // 级联入场插槽（§9.3#1：按 index × cascadeInterval 依次上浮；
          // off 档内部退化为 100ms 淡入，§9.6）
          for (int i = 0; i < slots.length; i++)
            cascade
                ? SlimcaStaggerItem(
                    index: i,
                    floatDistance: floatDistance,
                    child: slots[i],
                  )
                : slots[i],
          if (footer != null) footer!,
        ],
      ),
    );
  }
}
