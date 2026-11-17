import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 约束 token 层测试（W17 插曲 UI-规范与重设计.md §2.2 新增 token 表 /
/// §1.3 间距尺度 / §1.4 触碰目标与状态层 / §1.5 行高与列表约束）：
/// SlimcaSpacing 8dp 全档、SlimcaSizes 命中/图标/行高/圆角/状态层、
/// buildTheme 装配挂载与回退。
void main() {
  group('SlimcaSpacing 8dp 全档（§1.3 M3 官方刻度 8 档）', () {
    test('canonical 档位值', () {
      const SlimcaSpacing s = SlimcaSpacing.standard;
      expect(s.space50, 4.0, reason: 'M3 space50');
      expect(s.space100, 8.0, reason: 'M3 space100 基线档');
      expect(s.space150, 12.0, reason: '卡内 padding / 分组卡内 tile 水平');
      expect(s.space200, 16.0, reason: '行内水平 / 卡间');
      expect(s.space250, 20.0, reason: 'M3 space250');
      expect(s.space300, 24.0, reason: '组间 / 页边');
      expect(s.space400, 32.0, reason: '区块间');
      expect(s.space600, 48.0, reason: '区段间大档');
    });

    test('梯度别名 xs/s/m/l/xl/xxl（任务定稿映射）', () {
      const SlimcaSpacing s = SlimcaSpacing.standard;
      expect(s.xs, s.space50, reason: 'xs=4 微间距');
      expect(s.s, s.space100, reason: 's=8 基线');
      expect(s.m, s.space150, reason: 'm=12 卡内');
      expect(s.l, s.space200, reason: 'l=16 行内');
      expect(s.xl, s.space300, reason: 'xl=24 组间/页边');
      expect(s.xxl, s.space400, reason: 'xxl=32 区块间');
    });

    test('语义位（§1.3 Slimca 落点防错档）', () {
      const SlimcaSpacing s = SlimcaSpacing.standard;
      expect(s.cardInner, 12.0, reason: '卡内 12');
      expect(s.inline, 16.0, reason: '行内水平 16');
      expect(s.groupGap, 24.0, reason: '分组间 24');
      expect(s.pageMargin, 24.0, reason: '页边 24');
      expect(s.sectionGap, 32.0, reason: '区块间 32');
    });

    test('copyWith / == / lerp（ThemeExtension 契约，§8.3）', () {
      const SlimcaSpacing s = SlimcaSpacing.standard;
      expect(s.copyWith(space150: 14.0).space150, 14.0);
      expect(s.copyWith(space150: 14.0), isNot(s));
      final SlimcaSpacing mid = s.lerp(
        const SlimcaSpacing(space100: 12.0),
        0.5,
      );
      expect(mid.space100, 10.0, reason: '(8+12)/2');
      expect(s.lerp(null, 0.5), same(s));
      expect(SlimcaSpacing.standard, const SlimcaSpacing());
    });
  });

  group('SlimcaSizes 官方刻度值（§1.4/§1.5/§3.3/§4.2）', () {
    test('触碰目标（§1.4：M3 structure + flutter kMinInteractiveDimension）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.minTouchTarget, 48.0);
      expect(
        s.minTouchTarget,
        kMinInteractiveDimension,
        reason: '与 Flutter 常量同值',
      );
      expect(s.pointerTarget, 44.0, reason: '指针目标（鼠标/笔）');
      expect(s.targetGap, 8.0, reason: '目标间距 ≥8dp');
    });

    test('图标尺寸（§4.2 leading 视觉 24 / 上限 40）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.iconVisual, 24.0);
      expect(s.iconVisualMax, 40.0);
    });

    test('行高三档（§1.5 flutter list_tile.dart 源码口径）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.rowSingleLine, 56.0, reason: '§4.2 单行 56 不用 dense');
      expect(s.rowTwoLine, 72.0, reason: '§4.2 两行 72');
      expect(s.rowThreeLine, 88.0, reason: '三行 88 补全');
    });

    test('日历与圆角（§3.3/§4.2/§5#1）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.dayCellVisual, 40.0, reason: '月格视觉 40×40 material-web token');
      expect(s.weekStripHeight, 72.0, reason: '周条折叠高度（推导值）');
      expect(s.radiusCard, 16.0, reason: 'M3 shape large');
      expect(s.radiusGroupCard, 12.0, reason: 'M3 shape medium 分组卡');
      expect(s.monthGridMaxRows, 6, reason: '月网格最多 6 行');
    });

    test('状态层透明度四档（§1.4 M3 state-layers）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.stateLayerHover, 0.08);
      expect(s.stateLayerFocus, 0.10);
      expect(s.stateLayerPressed, 0.10, reason: '§4.2 按压统一 10%');
      expect(s.stateLayerDragged, 0.16);
    });

    test('copyWith / == / lerp（ThemeExtension 契约）', () {
      const SlimcaSizes s = SlimcaSizes.standard;
      expect(s.copyWith(minTouchTarget: 44.0).minTouchTarget, 44.0);
      expect(s.copyWith(minTouchTarget: 44.0), isNot(s));
      final SlimcaSizes mid = s.lerp(
        const SlimcaSizes(minTouchTarget: 40.0),
        0.5,
      );
      expect(mid.minTouchTarget, 44.0, reason: '(48+40)/2');
      expect(mid.monthGridMaxRows, 6, reason: '行数档不插值取整');
      expect(s.lerp(null, 0.4), same(s));
    });
  });

  group('约束 token 层装配（buildTheme 挂载与回退）', () {
    testWidgets('buildTheme 挂载 SlimcaSpacing/SlimcaSizes 进主题 extensions', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        Theme.of(captured).extension<SlimcaSpacing>(),
        isNotNull,
        reason: '§2.2「进 ui_kit token 层」——与 SlimcaTheme/MotionConfig 同层装配',
      );
      expect(Theme.of(captured).extension<SlimcaSizes>(), isNotNull);
      // 装配值 = 官方刻度默认档
      expect(captured.spacing.groupGap, 24.0);
      expect(captured.sizes.minTouchTarget, 48.0);
    });

    testWidgets('宿主未挂载时回退默认档（防御第三方 ThemeData 缺省）', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(captured.spacing, SlimcaSpacing.standard);
      expect(captured.sizes, SlimcaSizes.standard);
    });
  });
}
