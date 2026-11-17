import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// W17 插曲日历组件族测试（UI-规范与重设计.md §3 定稿）：
/// SlimcaCalendarStrip v2（选日/无限滑动分页/今日锚定回位）、SlimcaMonthGrid
/// （选日/翻月/选中态/今日态/Compact 色点/48 命中/星期标签不可聚焦）、
/// SlimcaCalendar（展开/收起/拖拽跟手/受控同步/回今日/off 档降级）。
///
/// 日期基线：2026-11-17（周二）；周起始固定周一（DateTime.monday）保确定性。
void main() {
  final DateTime baseDay = DateTime(2026, 11, 17); // 周二
  final ThemeData fullTheme = buildTheme(brightness: Brightness.light);
  final ThemeData offTheme = buildTheme(
    brightness: Brightness.light,
    motion: MotionConfig.forLevel(MotionLevel.off),
  );

  group('SlimcaCalendarStrip v2（无限横滑翻周＋点格切日）', () {
    DateTime? lastSelected;
    DateTime? lastWeek;
    Widget host(ThemeData theme, {DateTime? selected}) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SlimcaCalendarStrip(
          selectedDate: selected ?? baseDay,
          onDaySelected: (DateTime d) => lastSelected = d,
          onWeekChanged: (DateTime w) => lastWeek = w,
          today: baseDay,
          weekStart: DateTime.monday,
        ),
      ),
    );

    setUp(() {
      lastSelected = null;
      lastWeek = null;
    });

    testWidgets('初始渲染：折叠高度 72、选中周 16-22 可见、点格切日（§3.2/§3.3）', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      // 折叠态高度 72dp（weekStripHeight，§3.3 推导值）
      expect(tester.getSize(find.byType(SlimcaCalendarStrip)).height, 72.0);
      // 初始锚定=选中日所在周（周一 11/16 起）
      expect(find.text('16'), findsOneWidget);
      expect(find.text('17'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      // 点格=切日（周条内横向滑=翻周不切日，点格才切日，§3.2）
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(lastSelected, DateTime(2026, 11, 20));
      expect(lastWeek, isNull, reason: '点格不触发翻周回调');
    });

    testWidgets('无限滑动分页：左滑翻下周、右滑翻上周（§3「无限双向横滑」）', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();

      // 左滑翻下周：fling 多采样高速释放（周条日格 InkWell 在场时，拖拽首段位移
      // 会并入 drag start 而非滚动更新——单次大位移手动拖拽不会翻页，fling 规避）
      await tester.flingFrom(const Offset(400, 36), const Offset(-600, 0), 1000);
      await tester.pumpAndSettle();
      expect(lastWeek, DateTime(2026, 11, 23), reason: '翻周回调参数=新周起始（周一 11/23）');
      expect(find.text('23'), findsOneWidget, reason: '下周 23-29 可见');

      // 右滑翻上周（初始锚定页居中，双向各 5000 周近似无限）
      await tester.flingFrom(const Offset(400, 36), const Offset(600, 0), 1000);
      await tester.pumpAndSettle();
      expect(lastWeek, DateTime(2026, 11, 16));
      expect(find.text('17'), findsOneWidget);
    });

    testWidgets('今日锚定回位：外部选中日跨周 → SharedAxis token 锚定回目标周', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      // 先滑到下周（页=11/23 周；fling 多采样规避首段位移并入 drag start）
      await tester.flingFrom(const Offset(400, 36), const Offset(-600, 0), 1000);
      await tester.pumpAndSettle();
      expect(lastWeek, DateTime(2026, 11, 23));

      // 外部把选中日改到 12/1（宿主「今天」pill 场景的镜像）→ 周条锚定回 11/30 周
      await tester.pumpWidget(host(fullTheme, selected: DateTime(2026, 12, 1)));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget, reason: '12/1 所在周（11/30-12/6）可见');
      // 再回 11/17（今天）→ 回到 11/16 周（§3.2 今日锚定簇）
      await tester.pumpWidget(host(fullTheme, selected: baseDay));
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);
    });

    testWidgets('今天=primary 对比色文字＋今日点；选中=primaryContainer 填充（§3.3）', (
      tester,
    ) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      final SlimcaTheme guarded = enforceSlimcaAa(SlimcaTheme.light);
      final ColorScheme scheme = Theme.of(
        tester.element(find.text('17')),
      ).colorScheme;
      // 选中日：primaryContainer 填充的 AnimatedContainer（§3.3）
      final AnimatedContainer selectedBox = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('17'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final BoxDecoration selectedDecoration =
          selectedBox.decoration! as BoxDecoration;
      expect(selectedDecoration.color, scheme.primaryContainer);
      // 普通日（18，非今天非选中）无覆盖色：TextStyle.copyWith(color: null)
      // 保留 titleMedium 底色（继承 onSurface，效果等价于无覆盖）
      final Text plainText = tester.widget<Text>(find.text('18'));
      expect(
        plainText.style?.color,
        Theme.of(
          tester.element(find.text('18')),
        ).textTheme.titleMedium?.color,
        reason: '18 是普通日：无覆盖色（继承 titleMedium 底色）',
      );
      final Text selectedText = tester.widget<Text>(find.text('17'));
      expect(
        selectedText.style?.color,
        scheme.onPrimaryContainer,
        reason: '17 同时是选中日与今天：选中态取 onPrimaryContainer',
      );
      // 装配主题的 primary 来自语义 token（AA 护栏后）
      expect(scheme.primary, guarded.primary);
    });

    testWidgets('off 档：点格切日仍可用（§9.6 降级不影响交互语义）', (tester) async {
      await tester.pumpWidget(host(offTheme));
      await tester.pumpAndSettle();
      await tester.tap(find.text('19'));
      await tester.pumpAndSettle();
      expect(lastSelected, DateTime(2026, 11, 19));
    });
  });

  group('SlimcaMonthGrid（展开月网格：选日/翻月/色点/命中）', () {
    DateTime? lastSelected;
    DateTime? lastMonth;
    Widget host({
      ThemeData? theme,
      required DateTime month,
      Map<DateTime, int> recordCounts = const <DateTime, int>{},
      DateTime? selected,
    }) => MaterialApp(
      // 月网格组件对第三方 ThemeData 具备 token 回退能力（缺省主题冒烟兼测）
      theme: theme ?? ThemeData(useMaterial3: true),
      home: Scaffold(
        body: SlimcaMonthGrid(
          month: month,
          selectedDate: selected ?? baseDay,
          onDaySelected: (DateTime d) => lastSelected = d,
          onMonthChanged: (DateTime m) => lastMonth = m,
          recordCounts: recordCounts,
          today: baseDay,
          weekStart: DateTime.monday,
        ),
      ),
    );

    setUp(() {
      lastSelected = null;
      lastMonth = null;
    });

    testWidgets('头部簇与网格渲染：[‹ November 2026 ›] [今天]、周一先行、6 行', (tester) async {
      await tester.pumpWidget(host(month: baseDay));
      await tester.pumpAndSettle();
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      // 周一先行（weekStart=DateTime.monday）：narrowWeekdays Sunday 开头数组
      expect(find.text('M'), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      // 11/1 周日、周一先行 → 行首空位为 10/26-10/31（域外淡化但仍渲染）
      expect(find.text('26'), findsNWidgets(2), reason: '10/26（域外）与 11/26（当月）');
      expect(find.text('31'), findsOneWidget);
      expect(find.text('30'), findsNWidgets(2), reason: '10/30 与 11/30');
    });

    testWidgets('点格切日（§3.1④ 无第二次选择）＋月格命中 48×48（§3.3 a11y）', (tester) async {
      await tester.pumpWidget(host(month: baseDay));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      expect(lastSelected, DateTime(2026, 11, 20));

      final Finder cellInkWell = find.ancestor(
        of: find.text('20'),
        matching: find.byType(InkWell),
      );
      final Size hit = tester.getSize(cellInkWell.first);
      expect(hit.height, 48.0, reason: '命中行高 48（§3.3 M3 行高）');
      expect(hit.width, greaterThanOrEqualTo(48.0), reason: '命中 ≥48×48');
    });

    testWidgets('Compact 色点：≤3 实心点＋溢出点（§3.2 V1 只做 Compact）', (tester) async {
      await tester.pumpWidget(
        host(
          month: baseDay,
          recordCounts: <DateTime, int>{
            DateTime(2026, 11, 20): 2,
            DateTime(2026, 11, 25): 5,
          },
        ),
      );
      await tester.pumpAndSettle();
      int dotCount(String dayText) => tester
          .widgetList<Container>(
            find.descendant(
              of: find.ancestor(
                of: find.text(dayText),
                matching: find.byType(InkWell),
              ),
              matching: find.byType(Container),
            ),
          )
          .where(
            // 色点直径 4dp=space50（Container width 落在 tightFor constraints；
            // 视觉圆为 40，不受干扰）
            (Container c) =>
                c.constraints?.minWidth == SlimcaSpacing.standard.space50,
          )
          .length;
      expect(dotCount('20'), 2, reason: '2 条记录 → 2 个色点');
      expect(dotCount('25'), 4, reason: '5 条记录 → 3 色点＋1 溢出点');
    });

    testWidgets('翻月：箭头回调目标月首日；受控切月经 SharedAxis 切换', (tester) async {
      // 受控宿主（§3.1）：onMonthChanged 后 setState 更新 month prop
      DateTime month = baseDay;
      await tester.pumpWidget(
        StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setState,
              ) => MaterialApp(
                theme: ThemeData(useMaterial3: true),
                home: Scaffold(
                  body: SlimcaMonthGrid(
                    month: month,
                    selectedDate: baseDay,
                    onDaySelected: (DateTime d) => lastSelected = d,
                    onMonthChanged: (DateTime m) {
                      lastMonth = m;
                      setState(() => month = m);
                    },
                    today: baseDay,
                    weekStart: DateTime.monday,
                  ),
                ),
              ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(lastMonth, DateTime(2026, 12, 1));
      expect(
        find.text('December 2026'),
        findsOneWidget,
        reason: '受控：宿主 setState 后头部随焦点月切换',
      );
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(lastMonth, DateTime(2026, 11, 1));
      expect(find.text('November 2026'), findsOneWidget);
    });

    testWidgets('网格水平拖=翻月（§3.2 手势阶梯第 1 行）', (tester) async {
      await tester.pumpWidget(host(month: baseDay));
      await tester.pumpAndSettle();
      // 左滑高速释放（月格 InkWell 在场：单次大位移手动拖拽的首段位移并入
      // drag start 不触发回调，fling 多采样保速度阈值判定）
      await tester.flingFrom(const Offset(400, 300), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(lastMonth, DateTime(2026, 12, 1), reason: '左滑=下月');
    });

    testWidgets('星期标签行不可聚焦（§3.3）→ ExcludeSemantics', (tester) async {
      await tester.pumpWidget(host(month: baseDay));
      await tester.pumpAndSettle();
      // 星期标签（narrowWeekdays）被 ExcludeSemantics 包裹即不可聚焦；头部簇
      // IconButtons 的 tooltip 各自带一个 ExcludeSemantics，故锁定标签祖先
      expect(
        find.ancestor(
          of: find.text('M'),
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );
    });

    testWidgets('今天未选中=primary 对比色、选中日=primaryContainer（§3.3 色语义）', (
      tester,
    ) async {
      await tester.pumpWidget(host(month: baseDay));
      await tester.pumpAndSettle();
      // 选中 11/20、今天 11/17 → 两者态分离（宿主受控更新 selectedDate）
      final ColorScheme scheme = Theme.of(
        tester.element(find.text('20')),
      ).colorScheme;
      await tester.pumpWidget(
        host(month: baseDay, selected: DateTime(2026, 11, 20)),
      );
      await tester.pumpAndSettle();
      final Text selectedText = tester.widget<Text>(find.text('20'));
      expect(
        selectedText.style?.color,
        scheme.onPrimaryContainer,
        reason: '选中日=onPrimaryContainer',
      );
      final Text todayText = tester.widget<Text>(find.text('17'));
      expect(
        todayText.style?.color,
        enforceSlimcaAa(SlimcaTheme.light).primary,
        reason: '今天=primary 对比色（§3.3；装配经 AA 护栏）',
      );
    });
  });

  group('SlimcaCalendar（周条↔月网格形变容器）', () {
    DateTime? lastSelected;
    final List<bool> expandedEvents = <bool>[];
    Widget host(ThemeData theme, {DateTime? selected, bool? expanded}) =>
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SlimcaCalendar(
              selectedDate: selected ?? baseDay,
              onDaySelected: (DateTime d) => lastSelected = d,
              onExpandedChanged: (bool v) => expandedEvents.add(v),
              expanded: expanded,
              today: baseDay,
              weekStart: DateTime.monday,
            ),
          ),
        );

    setUp(() {
      lastSelected = null;
      expandedEvents.clear();
    });

    testWidgets('非受控初始折叠：高度=72（weekStripHeight）', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 72.0);
      expect(expandedEvents, isEmpty);
    });

    testWidgets('下拉展开：拖拽跟手（中程高度）＋松手 dur.l+curveExpand 补间到位', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      // 展开态高度（token 推导）：头部簇 48 + 星期标签行 40 + 月格 48×6 = 376
      const double expandedHeight = 48.0 + 40.0 + 48.0 * 6;
      // 多段短位移下拉（拖拽首段位移并入 drag start 而非 update——单次大位移
      // 手动拖拽不触发跟手，多段采样规避）
      final TestGesture gesture = await tester.startGesture(
        const Offset(400, 36),
      );
      await tester.pump(const Duration(milliseconds: 16));
      const int steps = 6;
      for (int i = 0; i < steps; i++) {
        await gesture.moveBy(const Offset(0, 40));
        await tester.pump(const Duration(milliseconds: 40));
      }
      final double draggingHeight = tester
          .getSize(find.byType(SlimcaCalendar))
          .height;
      expect(draggingHeight, greaterThan(72.0), reason: '下拉即跟手');
      expect(draggingHeight, lessThan(expandedHeight));
      await tester.pump(const Duration(milliseconds: 300)); // 停顿 → 释放速度≈0
      await gesture.up(); // 过半（200/304≈0.66）→ 补间展开
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SlimcaCalendar)).height,
        expandedHeight,
      );
      expect(expandedEvents, <bool>[true]);
      // 展开=月网格在场：头部簇「今天」按钮可点（§3.2 今日锚定簇）
      await tester.tap(find.text('今天'));
      await tester.pumpAndSettle();
      expect(lastSelected, baseDay);
    });

    testWidgets('展开态点「收起月历」箭头 → curveCollapse 收回折叠（§3.2）', (tester) async {
      await tester.pumpWidget(host(fullTheme));
      await tester.pumpAndSettle();
      // 多段短位移下拉展开（同上，规避首段位移并入 drag start）
      final TestGesture gesture = await tester.startGesture(
        const Offset(400, 36),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (int i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up(); // 过半（250/304≈0.82）→ 补间展开
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 376.0);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 72.0);
      expect(expandedEvents, <bool>[true, false]);
    });

    testWidgets('受控 expanded：宿主驱动切换，不回发 onExpandedChanged', (tester) async {
      await tester.pumpWidget(host(fullTheme, expanded: false));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 72.0);
      await tester.pumpWidget(host(fullTheme, expanded: true));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 376.0);
      expect(expandedEvents, isEmpty, reason: '受控同步不回发');
      await tester.pumpWidget(host(fullTheme, expanded: false));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 72.0);
    });

    testWidgets('展开态：焦点月随选中月（§3.1④ 单选中日单一真值）＋点格切日', (tester) async {
      // 选中日在 10 月 → 展开即 10 月网格
      await tester.pumpWidget(
        host(fullTheme, selected: DateTime(2026, 10, 10), expanded: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      expect(lastSelected, DateTime(2026, 10, 15));
    });

    testWidgets('off 档：展开以 100ms 淡入淡出时长收敛（§9.6）', (tester) async {
      await tester.pumpWidget(host(offTheme));
      await tester.pumpAndSettle();
      // 多段短位移下拉（同上，规避首段位移并入 drag start）
      final TestGesture gesture = await tester.startGesture(
        const Offset(400, 36),
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (int i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up(); // 过半（250/304≈0.82）→ 100ms 淡入淡出展开
      await tester.pump(); // 补间起步（fadeOff=100ms）
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.getSize(find.byType(SlimcaCalendar)).height,
        376.0,
        reason: 'off 档 100ms 内到位（曲线线性化）',
      );
      await tester.pumpAndSettle();
    });
  });
}
