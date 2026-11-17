import 'package:flutter/material.dart';

import '../tokens/slimca_sizes.dart';
import '../tokens/slimca_spacing.dart';
import '../tokens/slimca_theme.dart';

/// 菜单/设置页组件族（UI-规范与重设计.md §4 定稿：IA 分组卡 + 行规格 +
/// 危险项；「升级 Slimca Pro」露出移除属宿主层产品决策，IAP 抽象代码保留）。
///
/// 行规格（§4.2 M3 ListTile 口径）：行高 56/72（不用 dense）、leading 图标视觉
/// 24dp/容器 48dp 命中、分组卡内 tile 水平 12dp、行标题 Title Medium 16/24/500、
/// 副标题 Body Medium 14/20/400、按压统一 InkWell 默认 state layer 10%（§1.4，
/// 不逐行调色）；分组卡圆角 12（radiusGroupCard）、卡底 surfaceCard。
///
/// 危险项（§4.3）：红字（destructive，SlimcaTheme.danger）+ 尾部独立分组 +
/// 具体动词确认弹窗——确认弹窗与 snackbar undo 归宿主层（§4.3 定稿语义）。

/// 分组卡（§4.1 IA「分组卡」形态：可选分组头 + surfaceCard 圆角卡）。
///
/// 组间 24/页边 24（space300）由宿主页面用 SlimcaSpacing 排布；组内行间 0
/// （由行高自撑，§4.2）。
class SlimcaMenuGroup extends StatelessWidget {
  const SlimcaMenuGroup({super.key, this.header, required this.tiles});

  /// 分组头文案（Label Large 14/20/500，§4.2；null=无头，如顶部账号卡组）。
  final String? header;

  /// 组内行（SlimcaMenuTile / SwitchListTile 等行组件，§4.1 迁入口径）。
  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSizes sizes = context.sizes;
    final SlimcaSpacing spacing = context.spacing;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (header != null)
          Padding(
            // 分组头与卡体留 8dp（space100 档，推导）；左缘对齐卡内 padding 口径
            padding: EdgeInsets.only(
              left: spacing.cardInner,
              bottom: spacing.space100,
            ),
            child: Text(
              header!,
              style: textTheme.labelLarge?.copyWith(
                color: tokens.onSurfaceMuted,
              ),
            ),
          ),
        // 分组卡：圆角 12（M3 shape medium）+ 卡底 surfaceCard（§4.2）；
        // ClipRRect 令行级 InkWell 状态层涟漪不出卡。
        ClipRRect(
          borderRadius: BorderRadius.circular(sizes.radiusGroupCard),
          child: Material(
            color: tokens.surfaceCard,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: tiles,
            ),
          ),
        ),
      ],
    );
  }
}

/// 菜单行（§4.2 行规格定稿）。
///
/// 行高：单行 56 / 两行（标题+副标题）72（不用 dense，§4.2）；leading 视觉 24dp
/// 包在 48dp 命中容器内；导航类 trailing=chevron_right 24dp（[showChevron]），
/// 状态类 trailing=Switch/pill（宿主自传）；危险项=红字（[destructive]，
/// §4.3「红色文字按钮」层级原则——不做填充块）。
class SlimcaMenuTile extends StatelessWidget {
  const SlimcaMenuTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.showChevron = false,
    this.destructive = false,
    this.onTap,
  });

  /// 行标题（Title Medium 16/24/500，§4.2）。
  final String title;

  /// 副标题（Body Medium 14/20/400 onSurfaceVariant 口径=onSurfaceMuted）。
  /// 传入后行高升为 72 两行档。
  final String? subtitle;

  /// leading 图标（业务传 24dp 视觉图标；本组件包 48dp 命中容器，§4.2）。
  final Widget? leading;

  /// trailing（状态类：Switch/pill 等宿主自传）。
  final Widget? trailing;

  /// 导航类行：trailing 渲染 chevron_right 24dp（§4.2）。
  final bool showChevron;

  /// 危险项红字（SlimcaTheme.danger，§4.3；宿主需配独立分组+具体动词确认弹窗）。
  final bool destructive;

  /// 点击回调（按压反馈=InkWell 默认 state layer 10% on 色，§1.4/§4.2）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSizes sizes = context.sizes;
    final SlimcaSpacing spacing = context.spacing;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final bool twoLine = subtitle != null;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        // 行高 56/72（§4.2 flutter list_tile.dart 口径，不用 dense）
        height: twoLine ? sizes.rowTwoLine : sizes.rowSingleLine,
        child: Padding(
          // 分组卡内 tile 水平 12dp（§4.2 NavigationDrawer 口径「分组卡→12」）
          padding: EdgeInsets.symmetric(horizontal: spacing.cardInner),
          child: Row(
            children: <Widget>[
              if (leading != null)
                SizedBox(
                  // leading 命中容器 48×48，图标 24 视觉居中（§4.2）
                  width: sizes.minTouchTarget,
                  height: sizes.minTouchTarget,
                  child: Center(child: leading!),
                ),
              if (leading != null) SizedBox(width: spacing.cardInner),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        // 危险项红字（§4.3）；常规行继承 onSurface 默认
                        color: destructive ? tokens.danger : null,
                      ),
                    ),
                    if (twoLine) ...<Widget>[
                      SizedBox(height: spacing.space50),
                      Text(
                        subtitle!,
                        style: textTheme.bodyMedium?.copyWith(
                          // §4.2 副标题 onSurfaceVariant → 本库口径 onSurfaceMuted
                          color: tokens.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
              if (showChevron)
                Padding(
                  padding: EdgeInsets.only(left: spacing.space100),
                  child: Icon(
                    Icons.chevron_right,
                    size: sizes.iconVisual, // chevron 24dp（§4.2）
                    color: tokens.onSurfaceMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 小字状态 pill（§4.1：Pro 状态收进顶部账号卡一行小字 pill，不占整行；
/// 无购买时不显示——显隐逻辑归宿主）。
///
/// pill 属非文本图形组件，按 WCAG 3:1 口径校验（§4.2「pill 不进对比度禁区」）；
/// 默认取中性灰组合（surfaceMuted 底 + onSurfaceMuted 字）。
class SlimcaMenuPill extends StatelessWidget {
  const SlimcaMenuPill({super.key, required this.label});

  /// pill 文案（如「已升级 Pro」）。
  final String label;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final SlimcaSpacing spacing = context.spacing;
    final TextTheme textTheme = Theme.of(context).textTheme;

    return Container(
      // 一行小字 pill：水平 8 / 竖直 4（space100/space50 档，推导）
      padding: EdgeInsets.symmetric(
        horizontal: spacing.space100,
        vertical: spacing.space50,
      ),
      decoration: ShapeDecoration(
        color: tokens.surfaceMuted,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(color: tokens.onSurfaceMuted),
      ),
    );
  }
}
