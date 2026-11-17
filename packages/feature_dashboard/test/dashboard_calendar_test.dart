/// SlimcaCalendar 日历交互 e2e + 组件约束断言（UI-规范与重设计.md §3 定稿、
/// §11.1 W2 验收线延伸）。
///
/// 流程：内存真库 → 插入含热量与金额行的 entry → recomputeDay 重建投影 →
/// pump DashboardPage（构造注入 DriftDashboardRepository，§10.4）→ 按定稿
/// 手势阶梯断言：
/// 1. 点选周历切日 → 投影数据切换（共享轴转场后新一天快照直出，§9.3#2）；
/// 2. 周条无限翻周（翻周不切日，§3.2 设计决策）+ 翻周后点选切日；
/// 3. 下拉展开月网格（形变式）→ 点月格选日 → 数据切换 → 点收起箭头收起；
/// 4. 今日锚定簇：离开今天后「今天」pill 浮现，点击回今日（§3.2）；
/// 5. MotionLevel=off：展开/收起降级（100ms 淡入淡出，§2.2/§9.6）；
/// 6. 约束断言（§3.3/§1.4/§1.5）：折叠态 72dp、周格命中 48×72、月格命中
///    48×48 + 视觉 40×40、展开态 376dp（token 推导）、月格色点=有记录日。
///
/// Windows 宿主缺 sqlite3 运行库时温和跳过（与 core_db 冒烟测试同一守卫）。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:ui_kit/ui_kit.dart';

bool _isSqliteLibraryMissing(Object error) {
  final String msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

const String _device = '3F8A12C0B7D4';
const int _t0 = 1763251200000;

/// 测试冻结口径（§11.1 成文周：2026-11-16 周一）：
/// 今天=11-17、选中日初始=11-16、周起始=周一。
final DateTime _today = DateTime(2026, 11, 17);

Future<void> _insertEntryWithLines(
  AppDatabase db, {
  required String entryId,
  required String date,
  required String kind,
  required List<({String id, String type, int amount, String direction})> lines,
}) async {
  await db
      .into(db.entries)
      .insert(
        Entry(
          id: entryId,
          date: date,
          tzOffsetMin: 480,
          occurredAt: _t0,
          kind: kind,
          source: 'manual',
          title: '一碗牛肉面',
          note: null,
          status: 'confirmed',
          aiParseId: null,
          createdAt: _t0,
          updatedAt: _t0,
          deletedAt: null,
          hlc: '000$_t0:000001:$_device',
          revision: 1,
          schemaVer: 1,
          deviceId: _device,
        ),
      );
  for (final ({String id, String type, int amount, String direction}) line
      in lines) {
    await db
        .into(db.entryLines)
        .insert(
          EntryLine(
            id: line.id,
            entryId: entryId,
            type: line.type,
            amount: line.amount,
            direction: line.direction,
            ledgerId: line.type == 'money' ? 'ledger-money' : 'ledger-kcal',
            categoryId: null,
            currency: line.type == 'money' ? 'CNY' : null,
            confidence: null,
            payload: null,
            correctionOf: null,
            status: 'active',
            createdAt: _t0 + 1,
            updatedAt: _t0 + 1,
            deletedAt: null,
            hlc: '000$_t0:000002:$_device',
            revision: 1,
            schemaVer: 1,
            deviceId: _device,
          ),
        );
  }
}

Future<void> _pumpDashboard(
  WidgetTester tester,
  DashboardRepository repo, {
  MotionConfig? motion,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // §8.2/§9.2：token 挂载（motion 可注入 off 档降级用例）。
      theme: buildTheme(brightness: Brightness.light, motion: motion),
      home: Scaffold(
        body: DashboardPage(
          repository: repo,
          initialDate: DateTime(2026, 11, 16),
          today: _today,
          weekStart: DateTime.monday, // §11.1 成文口径：周一为一周起点
        ),
      ),
    ),
  );
  // 投影流首值 + 冷启动 spring/级联推进（§9.3#1）。
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// 周条作用域内的日号 finder（组合容器两层栈常驻，月格同号需排除）。
Finder _stripDay(String day) => find.descendant(
  of: find.byType(SlimcaCalendarStrip),
  matching: find.text(day),
);

/// 月网格作用域内的日号 finder。
Finder _monthDay(String day) =>
    find.descendant(of: find.byType(SlimcaMonthGrid), matching: find.text(day));

void main() {
  testWidgets('约束：折叠态 72dp/周格命中 48×72；点选周历切日→投影数据切换', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle(); // 探针：sqlite3 可用性
      final DashboardRepository repo = DriftDashboardRepository(db);

      // 11-16 mixed 事件：calorie 650 + money 1850（facet 拆行 §5.2②）。
      await _insertEntryWithLines(
        db,
        entryId: 'e-1',
        date: '2026-11-16',
        kind: 'mixed',
        lines: const <({String id, String type, int amount, String direction})>[
          (id: 'l-1', type: 'calorie', amount: 650, direction: 'in'),
          (id: 'l-2', type: 'money', amount: 1850, direction: 'out'),
        ],
      );
      // 11-17 expense 事件：money 500。
      await _insertEntryWithLines(
        db,
        entryId: 'e-2',
        date: '2026-11-17',
        kind: 'expense',
        lines: const <({String id, String type, int amount, String direction})>[
          (id: 'l-3', type: 'money', amount: 500, direction: 'out'),
        ],
      );
      await repo.recomputeDay('2026-11-16');
      await repo.recomputeDay('2026-11-17');

      await _pumpDashboard(tester, repo);

      // ── 约束断言（§3.3 折叠态高度 72=weekStripHeight 推导值）──
      expect(find.byType(SlimcaCalendar), findsOneWidget);
      expect(
        tester.getSize(find.byType(SlimcaCalendar)).height,
        72,
        reason: '折叠态高度=weekStripHeight（§3.3）',
      );
      // 周格命中区：≥48dp 高 × ≥48dp 宽（§1.4 minTouchTarget；测试面 800 宽 →
      // 7 列全幅出血 114px/列 ≥48；命中高由折叠态 72 内的格内容保证 ≥48）。
      final Rect stripCell = tester.getRect(
        find
            .ancestor(of: _stripDay('17'), matching: find.byType(InkWell))
            .first,
      );
      expect(
        stripCell.height,
        greaterThanOrEqualTo(48),
        reason: '周格命中 ≥48dp（§1.4）',
      );
      expect(
        stripCell.width,
        greaterThanOrEqualTo(48),
        reason: '周格命中宽 ≥48dp（§1.4 minTouchTarget）',
      );

      // ── 切日 e2e：点选 11-17 → 共享轴转场后新一天快照直出（§9.3#2/§3.2）──
      await tester.tap(_stripDay('17'));
      await tester.pumpAndSettle();
      expect(find.text('11月17日'), findsOneWidget);
      expect(find.text('¥5.00'), findsOneWidget, reason: '11-17 当日支出');
      expect(find.text('¥18.50'), findsNothing, reason: '旧日卡片墙已切换');
      // 环心净热量归零（11-17 无热量行）。
      expect(find.text('0'), findsOneWidget);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，日历 e2e 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('周条无限翻周：翻周不切日；翻周后点选他周日期', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final DashboardRepository repo = DriftDashboardRepository(db);
      await _pumpDashboard(tester, repo);

      // 左滑翻周 → 下一周（11-23..11-29）进入视口；选中日仍 11-16（§3.2
      // 「翻周不切日」设计决策——避免与卡片墙切日手势双重语义）。
      await tester.fling(
        find.byType(SlimcaCalendarStrip),
        const Offset(-600, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(_stripDay('25'), findsOneWidget, reason: '下一周日期可见');
      expect(find.text('11月16日'), findsOneWidget, reason: '翻周不切日');

      // 翻周后点选 11-25 → 切日（周条点格=切日，§3.2 手势阶梯第 1 行）。
      await tester.tap(_stripDay('25'));
      await tester.pumpAndSettle();
      expect(find.text('11月25日'), findsOneWidget);
      // 11-25 无投影记录 → 支出卡 ¥0.00 + 空态引导出现（§3.2 快照直出）。
      expect(find.text('¥0.00'), findsOneWidget);
      expect(find.text('今天还没有记录'), findsOneWidget);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，日历 e2e 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('下拉展开月网格（形变式）→ 点月格选日 → 点收起箭头收起；约束 48/40/376', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final DashboardRepository repo = DriftDashboardRepository(db);
      await _insertEntryWithLines(
        db,
        entryId: 'e-1',
        date: '2026-11-16',
        kind: 'mixed',
        lines: const <({String id, String type, int amount, String direction})>[
          (id: 'l-1', type: 'calorie', amount: 650, direction: 'in'),
          (id: 'l-2', type: 'money', amount: 1850, direction: 'out'),
        ],
      );
      await repo.recomputeDay('2026-11-16');
      await _pumpDashboard(tester, repo);

      // 下拉展开（§3.2 垂直手势）：拖拽 250px > 总形变量一半（304/2）→ 过半
      // 判定展开；松手 280ms（=dur.l）补间。
      await tester.drag(find.byType(SlimcaCalendar), const Offset(0, 250));
      await tester.pumpAndSettle();

      // ── 约束断言（§3.3 展开=头部簇 48 + 标签行 40 + 6×48=376）──
      expect(
        tester.getSize(find.byType(SlimcaCalendar)).height,
        376,
        reason: '展开态高度=token 推导（§3.3 月网格最多 6 行）',
      );
      // 月格命中区 48×48（§3.3 a11y 硬指标）。
      final Rect monthCell = tester.getRect(
        find
            .ancestor(of: _monthDay('20'), matching: find.byType(InkWell))
            .first,
      );
      expect(monthCell.height, 48, reason: '月格命中高 48dp（§3.3）');
      expect(monthCell.width, greaterThanOrEqualTo(48));
      // 月格视觉 40×40（material-web date-picker token，§3.3）。
      final Size visual = tester.getSize(
        find
            .descendant(
              of: find
                  .ancestor(of: _monthDay('20'), matching: find.byType(InkWell))
                  .first,
              matching: find.byType(Container),
            )
            .first,
      );
      expect(visual, const Size(40, 40), reason: '月格视觉 40×40（§3.3）');
      // 今日锚定簇（§3.2）：月网格头部行 [‹] 月份 [›] [今天]。
      expect(
        find.descendant(
          of: find.byType(SlimcaMonthGrid),
          matching: find.text('今天'),
        ),
        findsOneWidget,
      );
      // 月格 Compact 色点=有记录日（§3.2/§3.3 secondaryContainer 色点）。
      final ColorScheme scheme = Theme.of(
        tester.element(find.byType(SlimcaMonthGrid)),
      ).colorScheme;
      expect(
        find.descendant(
          of: find.byType(SlimcaMonthGrid),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    scheme.secondaryContainer,
          ),
        ),
        findsWidgets,
        reason: '11-16/11-17 有记录 → 月格色点（§3.3）',
      );

      // 点月格 11-20 → selectedDate ← 该日（无第二次选择，§3.1④）。
      await tester.tap(_monthDay('20'));
      await tester.pumpAndSettle();
      expect(find.text('11月20日'), findsOneWidget);

      // 点收起箭头（§3.2 手势阶梯「或点收起箭头」）→ 回周条折叠态。
      await tester.tap(find.byTooltip('收起月历'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SlimcaCalendar)).height,
        72,
        reason: '收起后回折叠态 72dp（§3.3）',
      );
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，日历 e2e 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('今日锚定簇：离开今天后「今天」pill 浮现；点击回今日', (WidgetTester tester) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final DashboardRepository repo = DriftDashboardRepository(db);
      await _pumpDashboard(tester, repo);

      // 初始选中 11-16 ≠ 今天(11-17) → pill 已浮现（§3.2「横滑离开今天后浮现」）。
      Finder pillOpacity() => find.ancestor(
        of: find.byKey(const ValueKey('dashboard_today_pill')),
        matching: find.byType(AnimatedOpacity),
      );
      expect(
        tester.widget<AnimatedOpacity>(pillOpacity()).opacity,
        1,
        reason: '选中日≠今天 → pill 浮现（§3.2）',
      );

      // 回到今天（点月网格「今天」按钮构造「已今天」态）→ pill 隐没。
      await tester.drag(find.byType(SlimcaCalendar), const Offset(0, 250));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(SlimcaMonthGrid),
          matching: find.text('今天'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(pillOpacity()).opacity,
        0,
        reason: '选中日=今天 → pill 隐没（§3.2）',
      );

      // 切离今天（点 11-20）→ pill 浮现；点击 pill → 回今日 + 数据切换。
      await tester.tap(_monthDay('20'));
      await tester.pumpAndSettle();
      expect(find.text('11月20日'), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(pillOpacity()).opacity,
        1,
        reason: '选中日≠今天 → pill 浮现（§3.2）',
      );
      await tester.tap(find.byKey(const ValueKey('dashboard_today_pill')));
      await tester.pumpAndSettle();
      expect(find.text('11月17日'), findsOneWidget, reason: '回今日（§3.2）');
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，日历 e2e 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });

  testWidgets('MotionLevel=off：展开/收起降级为 100ms 淡入淡出（§2.2/§9.6）', (
    WidgetTester tester,
  ) async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
      final DashboardRepository repo = DriftDashboardRepository(db);
      await _pumpDashboard(
        tester,
        repo,
        motion: MotionConfig.forLevel(MotionLevel.off),
      );

      // off 档：曲线对线性化 + durL=100ms（MotionConfig.off 表值，§2.2）——
      // 手势与状态机不变，仅时长/曲线降级；断言终态一致。
      await tester.drag(find.byType(SlimcaCalendar), const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 376);

      await tester.drag(find.byType(SlimcaCalendar), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(SlimcaCalendar)).height, 72);
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，日历 e2e 测试未执行（$error）');
        return;
      }
      rethrow;
    } finally {
      await db.close();
    }
  });
}
