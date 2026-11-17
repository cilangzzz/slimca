import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart'
    show Hct;
import 'package:ui_kit/ui_kit.dart';

/// ThemeEditorPanel 冒烟测试（§8.4：种子色 / 四滑杆 / AA 反馈条 / 预览 / 保存）。
void main() {
  late ThemeProfile preset;

  setUp(() {
    preset = kSlimcaPresetThemeProfiles.first; // 墨（默认包）
  });

  Widget host({
    required ThemeProfile initial,
    ValueChanged<ThemeProfile>? onChanged,
    ValueChanged<ThemeProfile>? onSave,
  }) => MaterialApp(
    theme: buildTheme(brightness: Brightness.light),
    home: Scaffold(
      body: SizedBox(
        width: 420,
        child: ThemeEditorPanel(
          initial: initial,
          onChanged: onChanged,
          onSave: onSave,
        ),
      ),
    ),
  );

  testWidgets('冒烟：反馈条 + 预览 + 种子区 + 四滑杆 + MotionLevel 全部在场', (tester) async {
    await tester.pumpWidget(host(initial: preset));
    await tester.pumpAndSettle();

    // §8.4 AA 反馈条：内置包经护栏全达标
    expect(find.text('WCAG AA 全部达标'), findsOneWidget);
    // §8.4 实时预览：仪表盘微缩版（热量环 + 支出 + 待办 + 净热量）
    expect(find.byType(SlimcaCalorieRing), findsOneWidget);
    expect(find.text('支出 ¥68.50'), findsOneWidget);
    expect(find.text('待办 3/5'), findsOneWidget);
    expect(find.text('净热量 800 kcal'), findsOneWidget);
    // §8.4 四滑杆（radiusScale/density/fontScale/motionScale）+ 种子微调滑杆
    final int sliderCount = tester
        .widgetList<Slider>(find.byType(Slider))
        .length;
    expect(sliderCount, greaterThanOrEqualTo(4));
    // MotionLevel 分档（§9.2 off/reduced/full）
    expect(find.text('减弱'), findsOneWidget);
    expect(find.text('完整'), findsOneWidget);
    // 包名编辑（§8.4 命名与同步）
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('保存：内置包名 + AA 达标 → 可保存并回调草稿', (tester) async {
    ThemeProfile? saved;
    await tester.pumpWidget(
      host(
        initial: preset.copyWith(name: '我的墨'),
        onSave: (ThemeProfile p) {
          saved = p;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.name, '我的墨');
    expect(saved!.id, preset.id);
  });

  testWidgets('名称为空 → 保存禁用（§8.4 命名与同步）', (tester) async {
    ThemeProfile? saved;
    await tester.pumpWidget(
      host(
        initial: preset.copyWith(name: ''),
        onSave: (ThemeProfile p) {
          saved = p;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final FilledButton button = tester.widget<FilledButton>(
      find.byType(FilledButton),
    );
    expect(button.onPressed, isNull, reason: '空名禁保存');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(saved, isNull);
  });

  testWidgets('四滑杆改动：回调草稿携带新值（§8.2 形状/密度/字重/动效强度）', (tester) async {
    final List<ThemeProfile> changes = <ThemeProfile>[];
    await tester.pumpWidget(host(initial: preset, onChanged: changes.add));
    await tester.pumpAndSettle();

    // 滑杆排序（面板从上到下）：种子区滑杆在前，四滑杆在后；
    // 四滑杆 = 最后 4 个 Slider（圆角/密度/字重/动效强度）
    final List<Slider> sliders = tester
        .widgetList<Slider>(find.byType(Slider))
        .toList();
    final int n = sliders.length;
    expect(n, greaterThanOrEqualTo(8));
    // 拖拽圆角滑杆（倒数第 4 个）向左：radiusScale 下降并触发回调
    final Finder radiusSlider = find.byType(Slider).at(n - 4);
    await tester.ensureVisible(radiusSlider);
    await tester.pumpAndSettle();
    final Offset center = tester.getCenter(radiusSlider);
    final TestGesture gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-120, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.radiusScale, lessThan(preset.radiusScale));
  });

  testWidgets('MotionLevel 切换：草稿档位更新并回调（§9.2）', (tester) async {
    final List<ThemeProfile> changes = <ThemeProfile>[];
    await tester.pumpWidget(host(initial: preset, onChanged: changes.add));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('关'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关'));
    await tester.pumpAndSettle();
    expect(changes.last.motionLevel, MotionLevel.off);
    // 预览卡内动效提示同步
    expect(find.textContaining('动效：off'), findsOneWidget);
  });

  testWidgets('种子色预设 chips：点击改 kcal 饱和度，草稿种子变化（§8.4）', (tester) async {
    final List<ThemeProfile> changes = <ThemeProfile>[];
    await tester.pumpWidget(host(initial: preset, onChanged: changes.add));
    await tester.pumpAndSettle();
    // kcal 通道第一颗预设 chip（色相 150 锚定，饱和度 45，展示色 tone 50）
    final Color chipColor = seedFromHct(kKcalAnchorHue, 45, 50);
    final Finder chip = find.byWidgetPredicate(
      (Widget w) =>
          w is Container &&
          (w.decoration is BoxDecoration) &&
          (w.decoration! as BoxDecoration).color == chipColor,
    );
    expect(chip, findsOneWidget);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    final Color before = preset.lightSeeds.kcal;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(changes, isNotEmpty);
    expect(changes.last.lightSeeds.kcal, isNot(before));
    // 双主色锚定：改动后种子仍为绿域（G 通道占优，§8.2）
    expect(
      changes.last.lightSeeds.kcal.g,
      greaterThan(changes.last.lightSeeds.kcal.r),
    );
    // 草稿滑杆联动：kcal 饱和度变为 45（chip 载荷）
    expect(
      Hct.fromInt(changes.last.lightSeeds.kcal.toARGB32()).chroma.round(),
      45,
    );
  });
}
