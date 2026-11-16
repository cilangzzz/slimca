/// 待办全链路 widget 测试（§11.1 W5-6 主线任务 2 验收、§3.6、§5.5⑩、
/// §5.6、§6.5）。
///
/// 内存真库（NativeDatabase.memory）；断言勾选联动 day_summary 投影：
/// 1. 今日待办：新增 → todos 落行（date=今天）→ 勾选 → todo_done=1 →
///    取消 → todo_done=0（本地 unset 无并发时生效，§6.5）；
/// 2. 收集箱：date IS NULL、不进日投影（§5.5⑩）→「加入今日」→ 投影
///    todo_total=1 → 勾选 → todo_done=1。
///
/// 运行前提：集成阶段已 `flutter pub get`；宿主缺 sqlite3 运行库时温和跳过。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_plan/feature_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 测试夹具：内存真库 + 注入 HlcClock + 计划域网关。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  PlanGateway? _gateway;

  cdb.AppDatabase get db => _db!;
  PlanGateway get gateway => _gateway!;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(
      // closeStreamsSynchronously：drift 流取消的清缓存 Timer 在 fake_async
      // 区无人清空会挂起测试（与 apps/mobile widget_test 同口径）。
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，待办流程测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(deviceId: '3F8A12C0B7D4');
    _gateway = createPlanGateway(db: db, clock: _clock!);
    return true;
  }

  Future<void> close() async {
    await _db?.close();
  }
}

/// 泵 TodoPage（ProviderScope 覆盖注入网关）并等待输入区装载。
Future<void> _pumpTodoPage(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        planGatewayProvider.overrideWithValue(harness.gateway),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const TodoPage(),
      ),
    ),
  );
  await _pumpUntilFound(tester, find.byKey(todoInputKey));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待控件超时: $finder');
}

/// 轮询直到 [probe] 为真（投影重算为异步桥接，§5.6）。
///
/// 命中后补两拍再返回：DB 写入先于 Drift 流再投递/组件重建一拍，直接
/// tap 后续控件会打在旧 UI 上（勾选框旧 value 取反、新瓦片尚未渲染）。
Future<void> _pumpUntilDb(
  WidgetTester tester,
  Future<bool> Function() probe,
) async {
  for (var i = 0; i < 150; i++) {
    if (await probe()) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('等待数据库状态超时');
}

/// 全表待办行（无 drift 导入：生成 API 的 select/get 即可，过滤在 Dart 侧）。
Future<List<cdb.Todo>> _allTodos(_Harness harness) async =>
    harness.db.select(harness.db.todos).get();

/// 今日投影行（无行返回 null）。
Future<cdb.DaySummary?> _summaryFor(_Harness harness, String date) async {
  final rows = await harness.db.select(harness.db.daySummaries).get();
  for (final row in rows) {
    if (row.date == date) return row;
  }
  return null;
}

void main() {
  testWidgets(
    '今日待办：新增→勾选→投影 todo_done 更新→取消→回落（§11.1 W5-6 / §5.5⑩ / §5.6）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final today = dom.formatCalendarDay(DateTime.now());

      await _pumpTodoPage(tester, harness);

      // ① 新增（今日视图默认档）。
      await tester.enterText(find.byKey(todoInputKey), '买菜');
      await tester.tap(find.byKey(todoAddKey));
      await _pumpUntilDb(
        tester,
        () async => (await _allTodos(harness))
            .any((t) => t.title == '买菜' && t.date == today),
      );
      final todo =
          (await _allTodos(harness)).firstWhere((t) => t.title == '买菜');
      expect(todo.date, today);
      expect(todo.doneAt, isNull);
      expect(todo.deletedAt, isNull);
      expect(todo.hlc, isNotEmpty);

      // ② 投影先建立（todo_total=1、todo_done=0，§5.6）。
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.todoTotal == 1,
      );

      // ③ 勾选 → todo_done=1（done_at 只前进合并 set 侧，§6.5）。
      await tester.tap(find.byKey(todoCheckKey(todo.id)));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.todoDone == 1,
      );
      final doneTodo =
          (await _allTodos(harness)).firstWhere((t) => t.id == todo.id);
      expect(doneTodo.doneAt, isNotNull);

      // ④ 取消 → 本地单写者 unset 生效、todo_done 回落 0（§6.5）。
      await tester.tap(find.byKey(todoCheckKey(todo.id)));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.todoDone == 0,
      );
    },
  );

  testWidgets(
    '收集箱：date IS NULL 不进日投影→加入今日→投影计数→勾选联动'
    '（§5.5⑩ / §3.6 / §5.6）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);

      final today = dom.formatCalendarDay(DateTime.now());

      await _pumpTodoPage(tester, harness);

      // ① 切收集箱视图并新增（date=NULL，§5.5⑩）。
      await tester.tap(find.text('收集箱'));
      await tester.pump();
      await tester.enterText(find.byKey(todoInputKey), '随手记的想法');
      await tester.tap(find.byKey(todoAddKey));
      await _pumpUntilDb(
        tester,
        () async => (await _allTodos(harness))
            .any((t) => t.title == '随手记的想法' && t.date == null),
      );
      final inboxTodo = (await _allTodos(harness))
          .firstWhere((t) => t.title == '随手记的想法');
      expect(inboxTodo.date, isNull);

      // ② 收集箱不进任何日投影（§5.5⑩/§5.6）：今日投影行尚不存在。
      expect(await _summaryFor(harness, today), isNull);

      // ③「加入今日」→ 回填计划日 → 投影 todo_total=1。
      await tester.tap(find.byKey(todoMoveTodayKey(inboxTodo.id)));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _allTodos(harness))
                .any((t) => t.id == inboxTodo.id && t.date == today) &&
            (await _summaryFor(harness, today))?.todoTotal == 1,
      );

      // ④ 勾选 → 投影 todo_done=1。加入今日后收集箱不再持有该项
      // （date 非 NULL 出收集箱流，§5.5⑩），切回今日视图勾选；切档后
      // 待办流异步重投，轮询等瓦片渲染完成再点勾选框。
      await tester.tap(find.text('今日待办'));
      await _pumpUntilFound(tester, find.byKey(todoCheckKey(inboxTodo.id)));
      await tester.tap(find.byKey(todoCheckKey(inboxTodo.id)));
      await _pumpUntilDb(
        tester,
        () async =>
            (await _summaryFor(harness, today))?.todoDone == 1,
      );
    },
  );
}
