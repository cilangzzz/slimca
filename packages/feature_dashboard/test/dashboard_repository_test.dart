/// day_summary 投影 v1 仓储测试（§5.6⑬、§11.1 W2「day_summary 投影 v1」）。
///
/// 内存真库：插入 entry + entry_lines（facet 拆行，§5.2/§5.3）→ recomputeDay
/// → 断言投影行与 watch 流（环/支出卡的数据源，§3.2 快照直出）。Windows 宿主
/// 缺 sqlite3 运行库时温和跳过（与 core_db schema 冒烟测试同一守卫）。
library;

import 'package:core_db/core_db.dart';
import 'package:drift/native.dart';
import 'package:feature_dashboard/feature_dashboard.dart';
import 'package:flutter_test/flutter_test.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见）。
bool _isSqliteLibraryMissing(Object error) {
  final String msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库并探测 sqlite3 动态库可用性，随后执行 [body]；缺库时跳过。
Future<void> _runSkippable(Future<void> Function(AppDatabase db) body) async {
  final AppDatabase db = AppDatabase(NativeDatabase.memory());
  try {
    await db.customSelect('SELECT 1').getSingle(); // 探针：触发动态库加载
    await body(db);
  } catch (error) {
    if (_isSqliteLibraryMissing(error)) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，day_summary 投影测试未执行（$error）');
      return;
    }
    rethrow;
  } finally {
    await db.close();
  }
}

const String _device = '3F8A12C0B7D4';
const int _t0 = 1763251200000;

Future<void> _insertEntry(
  AppDatabase db, {
  required String id,
  required String date,
  required String kind,
  int? deletedAt,
}) => db
    .into(db.entries)
    .insert(
      Entry(
        id: id,
        date: date,
        tzOffsetMin: 480,
        occurredAt: _t0,
        kind: kind,
        source: 'manual',
        title: '测试事件 $id',
        note: null,
        status: 'confirmed',
        aiParseId: null,
        createdAt: _t0,
        updatedAt: _t0,
        deletedAt: deletedAt,
        hlc: '000$_t0:000001:$_device',
        revision: 1,
        schemaVer: 1,
        deviceId: _device,
      ),
    );

Future<void> _insertLine(
  AppDatabase db, {
  required String id,
  required String entryId,
  required String type,
  required int amount,
  required String direction,
  String status = 'active',
}) => db
    .into(db.entryLines)
    .insert(
      EntryLine(
        id: id,
        entryId: entryId,
        type: type,
        amount: amount,
        direction: direction,
        ledgerId: type == 'money' ? 'ledger-money' : 'ledger-kcal',
        categoryId: null,
        currency: type == 'money' ? 'CNY' : null,
        confidence: null,
        payload: null,
        correctionOf: null,
        status: status,
        createdAt: _t0 + 1,
        updatedAt: _t0 + 1,
        deletedAt: null,
        hlc: '000$_t0:000002:$_device',
        revision: 1,
        schemaVer: 1,
        deviceId: _device,
      ),
    );

void main() {
  test('投影聚合：facet 行求和 + 墓碑/被修正旧行剔除 + watch 流', () async {
    await _runSkippable((AppDatabase db) async {
      final DashboardRepository repo = DriftDashboardRepository(db);

      // 11-16 mixed 事件：calorie 650 in + money 1850 out（facet 拆行 §5.2②）
      await _insertEntry(db, id: 'e-1', date: '2026-11-16', kind: 'mixed');
      await _insertLine(
        db,
        id: 'l-1',
        entryId: 'e-1',
        type: 'calorie',
        amount: 650,
        direction: 'in',
      );
      await _insertLine(
        db,
        id: 'l-2',
        entryId: 'e-1',
        type: 'money',
        amount: 1850,
        direction: 'out',
      );
      // 11-17 expense 事件：money 500 out
      await _insertEntry(db, id: 'e-2', date: '2026-11-17', kind: 'expense');
      await _insertLine(
        db,
        id: 'l-3',
        entryId: 'e-2',
        type: 'money',
        amount: 500,
        direction: 'out',
      );
      // 墓碑 entry（§5.1 软删行）：热量 999 不应计入
      await _insertEntry(
        db,
        id: 'e-3',
        date: '2026-11-16',
        kind: 'food',
        deletedAt: _t0 + 10,
      );
      await _insertLine(
        db,
        id: 'l-4',
        entryId: 'e-3',
        type: 'calorie',
        amount: 999,
        direction: 'in',
      );
      // 被修正旧行（superseded，§5.2② 修正=新增行）：金额 10000 不应重复计入
      await _insertEntry(db, id: 'e-4', date: '2026-11-16', kind: 'expense');
      await _insertLine(
        db,
        id: 'l-5',
        entryId: 'e-4',
        type: 'money',
        amount: 10000,
        direction: 'out',
        status: 'superseded',
      );

      await repo.recomputeDay('2026-11-16');
      await repo.recomputeDay('2026-11-17');

      // ── 投影行断言（§5.6⑬ 字段口径）──
      final DaySummary row = await (db.select(
        db.daySummaries,
      )..where((t) => t.date.equals('2026-11-16'))).getSingle();
      expect(row.kcalIn, 650);
      expect(row.kcalOut, 0);
      expect(row.netKcal, 650);
      expect(row.spendMinor, 1850);
      expect(row.incomeMinor, 0);
      expect(row.dirty, isFalse, reason: '重算完成即清 dirty（§5.6）');
      expect(row.builtAt, greaterThan(0));

      // ── watch 流断言（§5.6⑬ reactive stream 直驱）──
      final DashboardDaySummary? summary = await repo
          .watchDay('2026-11-16')
          .first;
      expect(summary, isNotNull);
      expect(summary!.kcalIn, 650);
      expect(summary.netKcal, 650);
      expect(summary.spendMinor, 1850);
      expect(summary.hasAnyRecord, isTrue);

      // 本月累计 = 18.50 + 5.00 = 23.50 元（逐日投影求和）
      expect(await repo.watchMonthSpendMinor('2026-11').first, 2350);

      // 有记录日集合（§3.3 月格色点数据源）：11-16/11-17 有记录、被墓碑
      // 剔除的 999 与 superseded 行不产生「有记录日」。
      expect(await repo.watchRecordedDays().first, <String>{
        '2026-11-16',
        '2026-11-17',
      });
    });
  });

  test('预算快照：daily 预算经账本 kind 区分（§5.4⑥/§5.6⑬ budget_snapshot）', () async {
    await _runSkippable((AppDatabase db) async {
      final DashboardRepository repo = DriftDashboardRepository(db);
      await _insertLedger(db, id: 'ledger-kcal', kind: 'kcal');
      await _insertLedger(db, id: 'ledger-money', kind: 'money');
      await db
          .into(db.budgets)
          .insert(
            Budget(
              id: 'b-kcal',
              ledgerId: 'ledger-kcal',
              categoryId: null,
              periodType: 'daily',
              amount: 1800,
              dayOfMonthStart: 1,
              carryOver: false,
              createdAt: _t0,
              updatedAt: _t0,
              deletedAt: null,
              hlc: '000$_t0:000003:$_device',
              revision: 1,
              schemaVer: 1,
              deviceId: _device,
            ),
          );
      await db
          .into(db.budgets)
          .insert(
            Budget(
              id: 'b-money',
              ledgerId: 'ledger-money',
              categoryId: null,
              periodType: 'daily',
              amount: 5000,
              dayOfMonthStart: 1,
              carryOver: false,
              createdAt: _t0,
              updatedAt: _t0,
              deletedAt: null,
              hlc: '000$_t0:000004:$_device',
              revision: 1,
              schemaVer: 1,
              deviceId: _device,
            ),
          );

      await _insertEntry(db, id: 'e-1', date: '2026-11-16', kind: 'mixed');
      await _insertLine(
        db,
        id: 'l-1',
        entryId: 'e-1',
        type: 'calorie',
        amount: 650,
        direction: 'in',
      );
      await _insertLine(
        db,
        id: 'l-2',
        entryId: 'e-1',
        type: 'money',
        amount: 1850,
        direction: 'out',
      );

      await repo.recomputeDay('2026-11-16');

      final DashboardDaySummary? summary = await repo
          .watchDay('2026-11-16')
          .first;
      expect(summary, isNotNull);
      expect(summary!.budget.kcalBudget, 1800);
      expect(summary.budget.spendBudgetMinor, 5000);
    });
  });

  test('待办完成度进投影（§5.6⑬ todo_done/todo_total）', () async {
    await _runSkippable((AppDatabase db) async {
      final DashboardRepository repo = DriftDashboardRepository(db);
      Future<void> insertTodo(String id, int? doneAt) => db
          .into(db.todos)
          .insert(
            Todo(
              id: id,
              title: '待办 $id',
              note: null,
              date: '2026-11-16',
              doneAt: doneAt,
              dueAt: null,
              repeatRule: null,
              remindAt: null,
              goalLink: null,
              createdAt: _t0,
              updatedAt: _t0,
              deletedAt: null,
              hlc: '000$_t0:000005:$_device',
              revision: 1,
              schemaVer: 1,
              deviceId: _device,
            ),
          );
      await insertTodo('todo-1', _t0);
      await insertTodo('todo-2', null);

      await repo.recomputeDay('2026-11-16');

      final DaySummary row = await (db.select(
        db.daySummaries,
      )..where((t) => t.date.equals('2026-11-16'))).getSingle();
      expect(row.todoTotal, 2);
      expect(row.todoDone, 1);
    });
  });

  test('空日自愈：无明细重建得全零投影行（§5.6 可随时全量重建）', () async {
    await _runSkippable((AppDatabase db) async {
      final DashboardRepository repo = DriftDashboardRepository(db);
      await repo.recomputeDay('2026-11-20');

      final DashboardDaySummary? summary = await repo
          .watchDay('2026-11-20')
          .first;
      expect(summary, isNotNull);
      expect(summary!.kcalIn, 0);
      expect(summary.spendMinor, 0);
      expect(summary.hasAnyRecord, isFalse, reason: '空日 → 仪表盘空态（§3.2）');
    });
  });
}

Future<void> _insertLedger(
  AppDatabase db, {
  required String id,
  required String kind,
}) => db
    .into(db.ledgers)
    .insert(
      Ledger(
        id: id,
        name: '账本 $id',
        icon: 'wallet',
        currency: kind == 'kcal' ? 'kcal' : 'CNY',
        kind: kind,
        sort: 0,
        openingBalanceMinor: 0,
        isArchived: false,
        createdAt: _t0,
        updatedAt: _t0,
        deletedAt: null,
        hlc: '000$_t0:000006:$_device',
        revision: 1,
        schemaVer: 1,
        deviceId: _device,
      ),
    );
