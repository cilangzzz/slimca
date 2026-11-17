/// SlimcaMenuGroup / SlimcaMenuTile——设置/菜单页的分组卡与行组件
/// （《UI-规范与重设计》§4.1/§4.2 行组件规格定稿）。
///
/// 规格（§4.2 行组件规格表，来源逐条标注）：
/// - **分组卡**：圆角 12（M3 shape medium）、卡底 surfaceCard、组内行间 0
///   （由行高自撑）；组间 24dp / 页边 24dp 由页面组合层负责（space300，§1.3）；
/// - **行**：M3 ListTile 口径——单行 56dp / 两行（标题+副标题）72dp，不用
///   dense（flutter `list_tile.dart` 源码口径，§1.5）；卡内 tile 水平 padding
///   12dp（NavigationDrawer 口径，§4.2「定稿用分组卡→12」）；
/// - **字号**：行标题 Title Medium 16/24/500；副标题 Body Medium 14/20/400
///   onSurfaceVariant 语义（§4.2 m3 type scale）；分组头 Label Large 14/20/500；
/// - **leading 图标**：视觉 24dp——整行即命中容器（行高 ≥56），图标自身不再
///   独立扩大（M3 structure「24dp 图标+留白凑 48dp 目标」的行内变体，§1.4）；
/// - **trailing**：导航类行缺省 `chevron_right` 24dp；状态类行由调用方传
///   Switch（轨道 32/手柄 16，框架默认即合规，§2.2）或 pill；
/// - **按压反馈**：统一 InkWell 默认 pressed state layer 10% on 色（§4.2
///   「不逐行调色」、§1.4 状态层四档），分组卡以 `clipBehavior` 裁剪涟漪进圆角；
/// - **危险项**：[SlimcaMenuTile.danger] 置红字（SlimcaTheme.danger 语义
///   token，§8.2 组件层禁裸色值；§4.3「红色文字按钮，不做填充块」）。
///
/// 本组件属 apps/mobile 壳层（§10.4）；若后续升级进 ui_kit 语义组件层，
/// 以本文件规格为准平移（注释即规格书）。
library;

import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart' show SlimcaTheme, SlimcaThemeBuildContext;

/// 分组卡（§4.1 IA 分组 / §4.2 分组卡规格）。
///
/// 可选 [header] 为分组头（Label Large 14/20/500，onSurfaceMuted 语义），
/// 渲染于卡内顶部；[children] 为一组 [SlimcaMenuTile]（组内行间 0）。
class SlimcaMenuGroup extends StatelessWidget {
  const SlimcaMenuGroup({super.key, this.header, required this.children});

  /// 分组头文案（null=无头，如尾部低频组/危险项独立组）。
  final String? header;

  /// 组内行（[SlimcaMenuTile] 列表）。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Material(
      // 卡底 surfaceCard + 圆角 12（M3 shape medium，§4.2）；antiAlias 把
      // 行按压 state layer 裁进圆角（§1.4 状态层视觉边界=卡形状）。
      color: tokens.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (header != null)
            Padding(
              // 分组头内边距：水平 16（space200）/上 12（space150）/下 4
              // （space50）——全部落在 §1.3 SlimcaSpacing 8dp 刻度档。
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                header!,
                // 分组头 Label Large 14/20/500（§4.2 定稿口径）。
                style: textTheme.labelLarge
                    ?.copyWith(color: tokens.onSurfaceMuted),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// 菜单行（§4.2 行组件规格的 M3 ListTile 封装）。
///
/// - [onTap] 为 null → 非导航行：无按压态、无 chevron（如占位行「数据导出」）；
/// - [trailing] 缺省（且 [onTap] 非 null）→ 导航类行自动补 `chevron_right`
///   24dp（§4.2 trailing 规格表）；
/// - [danger] → 标题/图标取 SlimcaTheme.danger 红字（§4.3 危险项样式）。
class SlimcaMenuTile extends StatelessWidget {
  const SlimcaMenuTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  /// 行标题（Title Medium 16/24/500，§4.2）。
  final String title;

  /// 行副标题（Body Medium 14/20/400 onSurfaceMuted 语义；子级 Text 不带
  /// style 即继承本样式——调用方可传 FutureBuilder 等任意 Widget）。
  final Widget? subtitle;

  /// leading 图标（视觉 24dp，§4.2）。
  final IconData? icon;

  /// trailing 控件（Switch/pill 等；null 且行可点 → 自动 chevron）。
  final Widget? trailing;

  /// 点击回调（null=非导航行）。
  final VoidCallback? onTap;

  /// 危险项：红字呈现（§4.3；确认弹窗与独立分组由页面层负责）。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final SlimcaTheme tokens = context.slimca;
    final TextTheme textTheme = Theme.of(context).textTheme;
    // 危险项红字取语义 token（SlimcaTheme.danger 与 colorScheme.error 同源，
    // buildTheme 装配映射，§8.2 三层架构：组件层禁裸色值）。
    final Color contentColor = danger ? tokens.danger : tokens.onSurface;
    return ListTile(
      // 卡内 tile 水平 padding 12（§4.2 定稿「分组卡→12」，NavigationDrawer
      // 口径）；不用 dense → 行高 56（单行）/72（标题+副标题），§1.5
      // flutter list_tile.dart 源码口径。
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: icon == null
          ? null
          : Icon(icon, size: 24, color: contentColor),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 行标题 Title Medium 16/24/500（§4.2 m3 type scale）。
        style: textTheme.titleMedium?.copyWith(color: contentColor),
      ),
      subtitle: subtitle == null
          ? null
          : DefaultTextStyle(
              // 副标题 Body Medium 14/20/400 onSurfaceMuted 语义（§4.2）；
              // DefaultTextStyle 让子级 Text/FutureBuilder 无样式继承。
              style: (textTheme.bodyMedium ?? const TextStyle())
                  .copyWith(color: tokens.onSurfaceMuted),
              child: subtitle!,
            ),
      // trailing 缺省且行可点 → 导航类 chevron_right 24dp（§4.2）。
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right,
                  size: 24, color: tokens.onSurfaceMuted)
              : null),
      // 按压反馈统一 InkWell 默认 state layer（pressed 10% on 色，§1.4/
      // §4.2「不逐行调色」）；onTap 为 null 时 ListTile 自带禁用态。
      onTap: onTap,
    );
  }
}
