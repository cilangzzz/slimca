import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// W17 插曲菜单组件族测试（UI-规范与重设计.md §4 定稿）：
/// SlimcaMenuGroup/SlimcaMenuTile/SlimcaMenuPill——行高 56/72、leading 48 命中
/// 容器/24 视觉、chevron 24、分组头 Label Large 14/500、分组卡圆角 12 +
/// surfaceCard、危险项红字、点击回调。
void main() {
  final ThemeData fullTheme = buildTheme(brightness: Brightness.light);
  final SlimcaTheme guarded = enforceSlimcaAa(SlimcaTheme.light);

  late DateTime? tapped;

  Widget host() => MaterialApp(
    theme: fullTheme,
    home: Scaffold(
      body: ListView(
        // 页边 24（space300，§4.2）；组间 24 由多分组时以 SizedBox 排布
        padding: EdgeInsets.all(SlimcaSpacing.standard.pageMargin),
        children: <Widget>[
          SlimcaMenuGroup(
            header: '数据与隐私',
            tiles: <Widget>[
              SlimcaMenuTile(
                title: '同步',
                leading: const Icon(Icons.sync),
                showChevron: true,
                onTap: () => tapped = DateTime(0),
              ),
              SlimcaMenuTile(
                title: '主题',
                subtitle: '墨·浅色',
                leading: const Icon(Icons.palette),
              ),
            ],
          ),
          SlimcaMenuGroup(
            header: '低频与危险',
            tiles: <Widget>[
              SlimcaMenuTile(
                title: '清空数据',
                destructive: true,
                onTap: () => tapped = DateTime(1),
              ),
            ],
          ),
          // 顶部账号卡 Pro 状态 pill（§4.1：不占整行的小字 pill）
          const SlimcaMenuPill(label: '已升级 Pro'),
        ],
      ),
    ),
  );

  setUp(() {
    tapped = null;
  });

  testWidgets('行高 56/72（§4.2：单行 56、两行 72，不用 dense）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final List<SlimcaMenuTile> tiles = tester
        .widgetList<SlimcaMenuTile>(find.byType(SlimcaMenuTile))
        .toList();
    expect(tiles.length, 3);
    expect(
      tester.getSize(find.byWidget(tiles[0])).height,
      56.0,
      reason: '单行（同步）=rowSingleLine 56',
    );
    expect(
      tester.getSize(find.byWidget(tiles[1])).height,
      72.0,
      reason: '两行（主题+副标题）=rowTwoLine 72',
    );
  });

  testWidgets('leading：24 视觉图标包在 48 命中容器内（§4.2）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // 视觉 24（Icon 默认 IconTheme 24=iconVisual 口径）
    expect(tester.getSize(find.byIcon(Icons.sync)).width, 24.0);
    // 命中容器 48×48（SizedBox width/height = minTouchTarget；leading 容器是
    // 标题文本的兄弟节点，须在 tile 子树内找）
    final SizedBox leadingBox = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.ancestor(
              of: find.text('同步'),
              matching: find.byType(SlimcaMenuTile),
            ),
            matching: find.byType(SizedBox),
          ),
        )
        .firstWhere((SizedBox s) => s.width == 48.0 && s.height == 48.0);
    expect(leadingBox.width, 48.0);
    expect(leadingBox.height, 48.0);
  });

  testWidgets('导航行 chevron_right 24dp（§4.2 trailing 规格）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final Icon chevron = tester.widget<Icon>(find.byIcon(Icons.chevron_right));
    expect(chevron.size, 24.0);
  });

  testWidgets('点击回调（InkWell 默认 state layer 10% 按压，§4.2）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步'));
    await tester.pumpAndSettle();
    expect(tapped, DateTime(0));
  });

  testWidgets('危险项红字（§4.3：红色文字按钮层级，不做填充块）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final Text danger = tester.widget<Text>(find.text('清空数据'));
    expect(danger.style?.color, guarded.danger);
    // 常规行不覆盖色（TextStyle.copyWith(color: null) 保留 titleMedium 底色）
    final Text normal = tester.widget<Text>(find.text('同步'));
    expect(
      normal.style?.color,
      Theme.of(
        tester.element(find.text('同步')),
      ).textTheme.titleMedium?.color,
      reason: '常规行无覆盖色（继承 titleMedium 底色）',
    );
  });

  testWidgets('分组头 Label Large 14/500（§4.2；现 titleSmall 口径修正）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final Text header = tester.widget<Text>(find.text('数据与隐私'));
    expect(header.style?.fontSize, 14.0);
    expect(header.style?.fontWeight, FontWeight.w500);
    expect(header.style?.color, guarded.onSurfaceMuted);
  });

  testWidgets('分组卡：圆角 12 + surfaceCard 卡底（§4.2 shape medium）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final ClipRRect clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byType(SlimcaMenuGroup).first,
        matching: find.byType(ClipRRect),
      ),
    );
    expect(
      clip.borderRadius,
      BorderRadius.circular(SlimcaSizes.standard.radiusGroupCard),
    );
    final Material card = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SlimcaMenuGroup).first,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.color, guarded.surfaceCard);
  });

  testWidgets('SlimcaMenuPill：Stadium 小字 pill（§4.1 Pro 状态收进账号卡）', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final Text pillText = tester.widget<Text>(find.text('已升级 Pro'));
    expect(pillText.style?.fontSize, 11.0, reason: 'labelSmall 11/16 小字');
    expect(pillText.style?.color, guarded.onSurfaceMuted);
  });

  testWidgets('行标题 Title Medium 16/24/500（§4.2 字号口径）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final Text title = tester.widget<Text>(find.text('同步'));
    expect(title.style?.fontSize, 16.0);
    expect(title.style?.fontWeight, FontWeight.w500);
    final Text subtitle = tester.widget<Text>(find.text('墨·浅色'));
    expect(subtitle.style?.fontSize, 14.0, reason: '副标题 Body Medium 14/20');
    expect(subtitle.style?.color, guarded.onSurfaceMuted);
  });
}
