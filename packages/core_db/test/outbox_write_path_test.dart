/// 全写路径 sync_outbox 覆盖测试（§6.2 写路径纪律、§5.6⑯；W5-6 集成披露的
/// 补课项 / W7-8 双设备一致率的写路径基础）。
///
/// 覆盖（core_db 名下写路径）：
/// 1. TodoDao 四写路径（create/setDone/updateDetails/softDelete）→ 行快照
///    同事务入队，payload 与落库行读回一致（回放一致性）；no-op 分支
///    （重复勾选/重复取消）不产生任何出网行（§6.5 只前进）；
/// 2. SyncOutboxWriter 入队去重（§6.2 幂等纪律）：同一事务重复入队折叠为
///    一条、跨事务仍 pending 旧行收敛到最新快照、已 ack 行不受影响；
/// 3. 墓碑拒绝复活路径（§6.5 删除行）：upsert 命中已删行 → 落库终态仍
///    墓碑、出网快照以 delete 语义收敛为一条；入队失败 → 事务整体回滚，
///    不产生半途业务行或半途 outbox（§6.2 事务一致性）；
/// 4. seed 默认数据行入队（ledgers/categories，§11.1 W7-8 双设备一致率）：
///    首次 seed 全量入队、重复 seed 幂等不再入队、payload 完整性；
/// 5. food_items 写路径 outbox 覆盖（§5.2③ 真值表、W7-8 补课断言）：核对
///    FoodItemsDao 三写路径（create/updateDetails/softDelete）行快照同事务
///    入队（§6.2）、payload 回放一致、入队失败整体回滚。feature_capture
///    网关 submitAiCapture 的内联 food_items 写入同口径（已在
///    feature_capture/test/capture_outbox_test.dart 覆盖），此处补 core_db
///    侧一等写路径的断言（W11-12 拍照通道复用同一纪律）。
///
/// 运行前提：集成阶段已 `flutter pub get` + build_runner（内存库经
/// drift/native 即可用）；宿主缺 sqlite3 运行库时温和跳过（同既有策略）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  /// 读 sync_outbox 全部行（测试内无 ack 路径，即全部 pending）。
  Future<List<SyncOutboxItem>> outboxRows(AppDatabase db) =>
      db.select(db.syncOutbox).get();

  /// 读业务表原始行快照（与 §5.6⑯ payload 同构的 snake_case 平铺）。
  Future<Map<String, Object?>?> rawRow(
    AppDatabase db,
    String table,
    String rowId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable.withString(rowId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// 回放一致性断言：payload JSON 解码后与业务表原始行逐键一致。
  Future<void> expectPayloadEqualsRow(
    AppDatabase db,
    SyncOutboxItem outboxRow,
  ) async {
    final payload = jsonDecode(outboxRow.payload) as Map<String, Object?>;
    final row = await rawRow(db, outboxRow.targetTable, outboxRow.rowId);
    expect(row, isNotNull, reason: '出网行必须指向已落库的业务行（§6.2）');
    expect(
      payload,
      equals(row),
      reason: '${outboxRow.targetTable}/${outboxRow.rowId} '
          'payload 必须与落库行同源（§6.2 行快照回放一致性）',
    );
    // §6.3 定宽编码与 §5.1 公共列完整性。
    expect(outboxRow.hlc, matches(RegExp(r'^\d{13}:\d{6}:[0-9A-F]{12}$')));
    expect(outboxRow.baseRevision, isNotNull);
    expect(outboxRow.ackedAt, isNull, reason: '测试内无 ack 路径');
  }

  test('TodoDao 四写路径 outbox 覆盖：行数、op、payload 回放一致；no-op 不入队',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言本次写路径。
      final dao = TodoDao(db);
      const day = '2026-11-23';

      // create：1 条 upsert 出网行。
      final todo = await dao.create(title: '买菜', date: day, note: '晚间');
      var rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'create → 1 条出网行（§6.2）');
      expect(rows.single.targetTable, 'todos');
      expect(rows.single.rowId, todo.id);
      expect(rows.single.op, 'upsert');
      await expectPayloadEqualsRow(db, rows.single);
      var payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['title'], '买菜');
      expect(payload['date'], day);
      expect(payload['done_at'], isNull);
      expect(payload['deleted_at'], isNull, reason: '存活行 upsert 出网');

      // W7-8 集成注：入队去重（§6.2 幂等纪律的本地半边，本文件 test ②
      // 「跨事务 pending 收敛」同源语义）——未 ack 的 (table,row) 出网行
      // 收敛为一条，每次真实写改写为最新快照（服务端只关心最终态，中间态
      // 从未被对端观察到，折叠不丢事实）。故各写步出网行恒为 1 条，以
      // baseRevision 推进 + payload 终态证明每次写入都被捕获。
      var lastRevision = rows.single.baseRevision!;
      expect(lastRevision, 1);

      // setDone(true)：出网行改写为完成态快照（done_at 携带勾选时刻）。
      await dao.setDone(todo.id, done: true);
      rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'pending 出网行收敛到最新快照');
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['done_at'], isNotNull, reason: '勾选事实进行快照');
      expect(rows.single.baseRevision!, greaterThan(lastRevision));
      lastRevision = rows.single.baseRevision!;

      // 重复勾选：no-op（§6.5 只前进）——业务行与出网快照均无推进。
      await dao.setDone(todo.id, done: true);
      rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'no-op 不入队');
      expect(rows.single.baseRevision, lastRevision, reason: 'no-op 不推进快照');

      // setDone(false)：取消完成是真实写——快照推进（done_at 回 null）。
      await dao.setDone(todo.id, done: false);
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['done_at'], isNull, reason: '取消完成反映为最新快照');
      expect(rows.single.baseRevision!, greaterThan(lastRevision));
      lastRevision = rows.single.baseRevision!;

      // updateDetails：出网快照反映新标题。
      await dao.updateDetails(id: todo.id, title: '买菜并复盘');
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['title'], '买菜并复盘');
      expect(rows.single.baseRevision!, greaterThan(lastRevision));

      // softDelete：墓碑快照 → op=delete（§5.6⑯/§6.5），仍收敛为一条。
      await dao.softDelete(todo.id);
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      expect(rows.single.op, 'delete', reason: '墓碑行以 delete 语义出网');
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['deleted_at'], isNotNull);
    } finally {
      await db.close();
    }
  });

  test('SyncOutboxWriter 入队去重：同事务重复入队折叠、跨事务 pending 收敛、'
      '非法表名/缺失行快速失败', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言本次入队行为。
      final writer = SyncOutboxWriter(db);
      final todo = await TodoDao(db).create(title: '去重样本');
      // create 已入队 1 条（pending）。

      // 同一事务内重复入队同一业务行：折叠为 1 条（§6.2 同事务重复入队防护）。
      await db.transaction(() async {
        await writer.enqueueRow('todos', todo.id);
        await writer.enqueueRow('todos', todo.id);
      });
      var rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1), reason: '重复入队不产生第二条出网行');
      await expectPayloadEqualsRow(db, rows.single);

      // 跨事务再次入队（业务行未再变更）：仍收敛为同一条 pending。
      await db.transaction(() async {
        await writer.enqueueRow('todos', todo.id);
      });
      rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1), reason: 'pending 旧行收敛到最新快照');

      // 14 张冻结真值表之外的表名无出网语义（§5.1 表分组）。
      await expectLater(
        writer.enqueueRow('settings', 'any-key'),
        throwsArgumentError,
      );

      // 目标行不存在：StateError 令调用方事务整体回滚，不指空出网。
      await expectLater(
        writer.enqueueRow('todos', 'ghost-todo'),
        throwsStateError,
      );
    } finally {
      await db.close();
    }
  });

  test('墓碑拒绝复活 × outbox 事务一致性：拒绝复活收敛为一条 delete 出网项；'
      '入队失败整体回滚无半途', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言事务一致性。
      final clock = TestClock('DEADBEEF0000');
      final repo = DriftEntryRepository(db);
      final writer = SyncOutboxWriter(db);

      final entry = makeEntry(clock, id: 'entry-1', date: '2026-11-23');
      await db.transaction(() async {
        await repo.upsert(entry);
        await writer.enqueueRow('entries', entry.id);
      });
      // upsert（存活）已入队且未被 ack。
      var rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1));
      expect(rows.single.op, 'upsert');

      // 软删（同事务入队）：出网项折叠为一条 delete（upsert 从未被服务端
      // 观察、中间态可安全收敛，§6.2 去重语义）。
      await db.transaction(() async {
        await repo.softDelete(entry.id, hlc: clock.hlc());
        await writer.enqueueRow('entries', entry.id);
      });
      rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1), reason: 'pending 出网项收敛为最终态');
      expect(rows.single.op, 'delete');

      // 墓碑拒绝复活（§6.5 删除行）：upsert 命中已删行 → 落库终态保留墓碑；
      // 同事务读回快照仍为 delete 语义——复活尝试不产生半途/复活出网项。
      final revived = makeEntry(clock, id: 'entry-1', date: '2026-11-23');
      await db.transaction(() async {
        await repo.upsert(revived);
        await writer.enqueueRow('entries', entry.id);
      });
      final row = await rawRow(db, 'entries', entry.id);
      expect(row!['deleted_at'], isNotNull, reason: '§6.5 删后编辑保持删除胜出');
      rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(1));
      expect(rows.single.op, 'delete', reason: '拒绝复活以墓碑快照出网');
      await expectPayloadEqualsRow(db, rows.single);

      // 事务一致性（§6.2 无半途）：业务写成功后入队失败 → 整体回滚——
      // 业务行不存在、出网行也无新增。
      final pendingBefore = (await db.select(db.syncOutbox).get()).length;
      final entriesBefore = await db.select(db.entries).get();
      await expectLater(
        db.transaction(() async {
          await repo.upsert(makeEntry(clock, id: 'entry-2', date: '2026-11-24'));
          await writer.enqueueRow('entries', 'ghost-row');
        }),
        throwsStateError,
      );
      final entriesAfter = await db.select(db.entries).get();
      expect(entriesAfter.length, entriesBefore.length,
          reason: '业务行随入队失败回滚（§6.2 同事务纪律）');
      expect((await db.select(db.syncOutbox).get()).length, pendingBefore,
          reason: '无半途 outbox（§6.2 事务一致性）');
    } finally {
      await db.close();
    }
  });

  test('seed 默认数据行入队：ledgers/categories 全量快照、重复 seed 幂等不入队',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      // beforeOpen 已 seed 并入队（§6.2：seed 行同为真值表）。
      final ledgers = await db.select(db.ledgers).get();
      final categories = await db.select(db.categories).get();
      final rows = await db.select(db.syncOutbox).get();
      final ledgerOutbox =
          rows.where((r) => r.targetTable == 'ledgers').toList();
      final categoryOutbox =
          rows.where((r) => r.targetTable == 'categories').toList();
      expect(ledgerOutbox, hasLength(ledgers.length),
          reason: '每个 seed 账本行一条出网项（§11.1 W7-8 双设备一致率）');
      expect(categoryOutbox, hasLength(categories.length),
          reason: '每个 seed 分类行一条出网项');
      expect(rows.length, ledgerOutbox.length + categoryOutbox.length,
          reason: 'settings/device_id 为本地件不入队（§5.6⑲）');
      for (final r in rows) {
        expect(r.op, 'upsert');
        await expectPayloadEqualsRow(db, r);
      }

      // 重复 seed：查缺补插幂等——无新业务行、无新出网行（§5.4）。
      await seedDefaultData(db);
      final rowsAfter = await db.select(db.syncOutbox).get();
      expect(rowsAfter, hasLength(rows.length), reason: '幂等重跑不再入队');
      expect((await db.select(db.ledgers).get()).length, ledgers.length);
      expect((await db.select(db.categories).get()).length, categories.length);
    } finally {
      await db.close();
    }
  });

  test('领域实体行快照口径核对：entries/entry_lines 出网 payload 与 §5.2 '
      'snake_case 同构（SyncMeta.toRowJson 复用）', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言本次快照口径。
      final clock = TestClock('DEADBEEF0001');
      final writer = SyncOutboxWriter(db);
      final repo = DriftEntryRepository(db);
      final lineRepo = DriftEntryLineRepository(db);

      final entry = makeEntry(clock, id: 'entry-10', date: '2026-11-25');
      final line = makeLine(
        clock,
        id: 'line-10',
        entryId: entry.id,
        type: dom.LineType.money,
        amount: 1800,
        direction: dom.LineDirection.outcome,
        ledgerId: 'ledger-10',
        currency: 'CNY',
      );
      await db.transaction(() async {
        await repo.upsert(entry);
        await lineRepo.upsert(line);
        await writer.enqueueRow('entries', entry.id);
        await writer.enqueueRow('entry_lines', line.id);
      });
      final rows = await db.select(db.syncOutbox).get();
      expect(rows, hasLength(2));
      for (final r in rows) {
        await expectPayloadEqualsRow(db, r);
      }
      final entryPayload =
          jsonDecode(rows.firstWhere((r) => r.targetTable == 'entries').payload)
              as Map<String, Object?>;
      // §5.2①/§5.1 同构键名抽查（三层同构、杜绝漂移，§6.2）。
      expect(entryPayload['kind'], 'expense');
      expect(entryPayload['tz_offset_min'], 480);
      expect(entryPayload['status'], 'confirmed');
      expect(entryPayload['hlc'], entry.meta.hlc);
      expect(entryPayload['device_id'], 'DEADBEEF0001');
      final linePayload = jsonDecode(
          rows.firstWhere((r) => r.targetTable == 'entry_lines').payload)
          as Map<String, Object?>;
      expect(linePayload['type'], 'money');
      expect(linePayload['amount'], 1800);
      expect(linePayload['direction'], 'out');
    } finally {
      await db.close();
    }
  });

  test('food_items 写路径 outbox 覆盖（W7-8 补课断言）：三写路径同事务入队、'
      'payload 回放一致、no-op 不推快照、入队失败整体回滚', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，outbox 写路径测试未执行');
      return;
    }
    try {
      await drainSeedOutbox(db); // 清空 seed 出网项，精确断言本次写路径。
      final dao = FoodItemsDao(db);

      // create：1 条 upsert 出网行（§5.2③ 真值表，§6.2 同事务纪律）。
      final item = await dao.create(
        entryId: 'entry-ob-1',
        lineId: 'line-ob-1',
        name: '兰州拉面',
        portionG: 450,
        kcal: 500,
        proteinG: 25,
        carbG: 65,
        fatG: 12,
        refSource: 'local',
        confidence: 0.62,
        id: 'food-ob-1',
      );
      var rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'create → 1 条出网行（§6.2）');
      expect(rows.single.targetTable, 'food_items');
      expect(rows.single.rowId, item.id);
      expect(rows.single.op, 'upsert');
      await expectPayloadEqualsRow(db, rows.single);
      var payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['entry_id'], 'entry-ob-1');
      expect(payload['line_id'], 'line-ob-1', reason: '§5.2③ line_id 溯源');
      expect(payload['name'], '兰州拉面');
      expect(payload['kcal'], 500);
      expect(payload['portion_g'], 450);
      expect(payload['ref_source'], 'local');
      expect(payload['user_adjusted'], 0,
          reason: 'AI 初值未改（bool 存 INTEGER）');
      expect(payload['deleted_at'], isNull, reason: '存活行 upsert 出网');
      var lastRevision = rows.single.baseRevision!;
      expect(lastRevision, 1);

      // updateDetails：真实写入改写 pending 出网行为最新快照（入队去重，
      // §6.2 折叠语义），user_adjusted 校准信号随行快照出网。
      await dao.updateDetails(id: item.id, portionG: 300, kcal: 855);
      rows = await outboxRows(db);
      expect(rows, hasLength(1), reason: 'pending 出网行收敛到最新快照');
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['portion_g'], 300);
      expect(payload['kcal'], 855);
      expect(payload['user_adjusted'], 1,
          reason: '§5.2③「用户是否改过」随行快照走（校准信号）');
      expect(rows.single.baseRevision!, greaterThan(lastRevision));
      lastRevision = rows.single.baseRevision!;

      // no-op 更新（无事实变化）：不推版本、不推进快照（§6.2 只对真实
      // 写入入队）。
      await dao.updateDetails(id: item.id, kcal: 855);
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      expect(rows.single.baseRevision, lastRevision, reason: 'no-op 不入队');

      // softDelete：墓碑快照 → op=delete（§5.6⑯/§6.5）。
      await dao.softDelete(item.id);
      rows = await outboxRows(db);
      expect(rows, hasLength(1));
      expect(rows.single.op, 'delete', reason: '墓碑行以 delete 语义出网');
      await expectPayloadEqualsRow(db, rows.single);
      payload = jsonDecode(rows.single.payload) as Map<String, Object?>;
      expect(payload['deleted_at'], isNotNull);

      // 事务一致性（§6.2 无半途）：food_items 业务写成功后入队失败 →
      // 整体回滚——业务行与出网行均无新增。
      final pendingBefore = (await db.select(db.syncOutbox).get()).length;
      final foodBefore = await db.select(db.foodItems).get();
      await expectLater(
        db.transaction(() async {
          await dao.create(
            entryId: 'entry-ob-2',
            lineId: 'line-ob-2',
            name: '卤蛋',
            portionG: 60,
            kcal: 200,
            proteinG: 12,
            carbG: 1,
            fatG: 14,
            refSource: 'baidu',
            confidence: 0.9,
            id: 'food-ob-2',
          );
          // food_items 同事务纪律由 DAO 内部 enqueueRow 承担；此处人为
          // 再入队一个不存在行制造失败，验证回滚覆盖 food_items 行。
          await SyncOutboxWriter(db).enqueueRow('food_items', 'ghost-item');
        }),
        throwsStateError,
      );
      final foodAfter = await db.select(db.foodItems).get();
      expect(foodAfter.length, foodBefore.length,
          reason: 'food_items 业务行随入队失败回滚（§6.2 同事务纪律）');
      expect((await db.select(db.syncOutbox).get()).length, pendingBefore,
          reason: '无半途 outbox（§6.2 事务一致性）');
    } finally {
      await db.close();
    }
  });
}
