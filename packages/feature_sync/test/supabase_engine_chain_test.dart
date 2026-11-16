/// W7-8 全链路测试（§11.1 W7-8「SupabaseSyncBackend + LocalSyncEngine 全链路
/// push→ack→pull→cursor advance 绿」+ §6.7 mock transport 双轨）。
///
/// 轨道安排：
/// - **Supabase-mock 轨道**（本文件主体）：[SupabaseSyncBackend] 注入
///   [FakeSupabaseRpcServer]（`0002_sync_rpc.sql` 线级镜像），全链路
///   push→ack→pull→游标推进、拒绝三分类处置、todos set 胜合并 ACK、
///   低水位迟到行（水位补漏）、传输层故障降级与恢复；
/// - **InMemory 轨道对照**：双设备收敛场景同脚本跑
///   InMemorySyncBackend 与 Supabase-mock 两轨（§6.2「可换后端不动 schema」
///   的验收面：引擎对后端实现零感知）。
///
/// 全程禁真实网络（§6.7）；宿主缺 sqlite3 运行库时温和跳过（同 core_db 策略）。
library;

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

import 'package:feature_sync/feature_sync.dart';

import 'supabase_fakes.dart';
import 'test_support.dart';

const String kDeviceA = 'A1B2C3D4E5F6';
const String kDeviceB = 'F6E5D4C3B2A1';
const String kFakeUrl = 'https://fake.supabase.co';

/// Supabase-mock 轨道夹具：共享 FakeSupabaseRpcServer 的双设备（与
/// [SyncHarness] 的 InMemory 轨道同构，§6.7 双轨）。
class _FakeHarness {
  _FakeHarness._(this.server, this.backend, this.devices, this.serverWall);

  final FakeSupabaseRpcServer server;
  final SupabaseSyncBackend backend;
  final List<SyncDeviceFixture> devices;
  final VirtualWall serverWall;

  SyncDeviceFixture device(int index) => devices[index];

  Future<void> close() async {
    for (final d in devices) {
      await d.close();
    }
  }
}

Future<_FakeHarness?> _openFakeHarness(List<String> deviceIds) async {
  final probe = await tryOpenTestDatabase();
  if (probe == null) {
    return null;
  }
  await probe.close();
  final serverWall = VirtualWall(kHarnessBaseWallMs);
  final server = FakeSupabaseRpcServer(nowMs: serverWall.take);
  final backend = SupabaseSyncBackend(
    config: const SyncConfig(url: kFakeUrl, anonKey: 'anon'),
    transport: server,
  );
  final devices = <SyncDeviceFixture>[];
  for (final id in deviceIds) {
    devices.add(await SyncDeviceFixture.open(backend, id, kHarnessBaseWallMs));
  }
  return _FakeHarness._(server, backend, devices, serverWall);
}

/// 双轨收敛脚本的轨道抽象（InMemory / Supabase-mock 同脚本复用）。
abstract interface class _Track {
  SyncDeviceFixture device(int index);
  Future<void> close();
}

class _InMemoryTrack implements _Track {
  _InMemoryTrack(this.harness);

  final SyncHarness harness;

  @override
  SyncDeviceFixture device(int index) => harness.device(index);

  @override
  Future<void> close() => harness.close();
}

class _SupabaseTrack implements _Track {
  _SupabaseTrack(this.harness);

  final _FakeHarness harness;

  @override
  SyncDeviceFixture device(int index) => harness.device(index);

  @override
  Future<void> close() => harness.close();
}

void main() {
  group('W7-8 全链路：SupabaseSyncBackend × FakeSupabaseRpcServer', () {
    test('①push→ack→pull→游标推进全链路绿（§6.2 读写路径）', () async {
      final h = await _openFakeHarness([kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      // 设备注册（§5.6⑰）：幂等 RPC，服务端登记可查。
      await a.backend.registerDevice(
        DeviceRegistration(
          id: a.deviceId,
          name: '台式机',
          platform: 'windows',
          createdAt: kHarnessBaseWallMs,
        ),
        deviceId: a.deviceId,
      );
      expect(h.server.deviceRegistered(a.deviceId), isTrue);

      // 本地写 → syncOnce：push ack 清账 + pull 自身回显 + 游标推进。
      final entryId = a.nextUuid();
      final lineId = a.nextUuid();
      final metas = await a.writeEntryWithLines(
        a.makeEntry(id: entryId, title: '全链路'),
        [
          a.makeLine(
            id: lineId,
            entryId: entryId,
            type: domain.LineType.calorie,
            amount: 300,
            direction: domain.LineDirection.income,
          ),
        ],
      );
      final report = await a.engine.syncOnce();
      expect(report.error, isNull);
      expect(report.pushed, 2);
      expect(report.acked, 2);
      expect(await a.pendingCount(), 0);
      // 权威 revision 回写业务行（§6.2 写路径末步）。
      expect((await a.rawRow('entries', entryId))!['revision'], 1);
      expect((await a.rawRow('entry_lines', lineId))!['revision'], 2);
      // 回显行经仲裁跳过、游标推进到最大 hlc（§6.2 确定性处理含跳过）。
      expect(report.skipped, 2);
      expect(report.cursors['entries'], metas.first.hlc);
      expect(report.cursors['entry_lines'], metas.last.hlc);
      // 服务端行 = 合并快照（payload + 权威列覆盖）。
      final serverEntry = h.server.serverRow('entries', entryId)!;
      expect(serverEntry['title'], '全链路');
      expect(serverEntry['device_id'], a.deviceId);

      // 二次同步无增量（游标/水位双轨都已越过）。
      final again = await a.engine.syncOnce();
      expect(again.pulled, 0);
      expect(again.acked, 0);
      expect(again.error, isNull);
    });

    test('②双设备收敛：InMemory 与 Supabase-mock 双轨同脚本（§6.2 可换后端）',
        () async {
      final inMemory = await SyncHarness.open(deviceIds: [kDeviceA, kDeviceB]);
      if (inMemory == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(inMemory.close);
      final fake = (await _openFakeHarness([kDeviceA, kDeviceB]))!;
      addTearDown(fake.close);

      await _convergeScenario(_InMemoryTrack(inMemory));
      await _convergeScenario(_SupabaseTrack(fake));
    });

    test('③拒绝三分类处置：作废/暂缓/幂等完成（§6.2 拒绝分类回处理）', () async {
      final h = await _openFakeHarness([kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      // 基线：A 写事件上送（服务端行 revision=1、hlc=H1）。
      final entryId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: entryId, title: '基线'),
      );
      await a.engine.syncOnce();
      final serverHlc = h.server.serverRow('entries', entryId)!['hlc'] as String;

      // ── 作废类一：stale hlc → hlc_non_monotonic → drop + 采纳服务端现值。
      final staleHlc = domain
          .Hlc(
            physicalMs: kHarnessBaseWallMs - 5000,
            counter: 0,
            deviceId: kDeviceA,
          )
          .format();
      await a.enqueueRaw(
        tableName: 'entries',
        rowId: entryId,
        payload: <String, Object?>{
          'id': entryId,
          'title': '陈旧标题',
          'hlc': staleHlc,
        },
        hlc: staleHlc,
      );
      final r1 = await a.engine.syncOnce();
      expect(
        r1.rejections[domain.SyncRejectionReason.hlcNonMonotonic],
        1,
      );
      expect(r1.droppedOutbox, 1);
      expect(await a.pendingCount(), 0);
      // 采纳服务端现值：本地标题未被陈旧写覆盖（§6.5 服务端权威仲裁）。
      expect((await a.rawRow('entries', entryId))!['title'], '基线');

      // ── 作废类二：schema_ver 超档 → drop（本端永不理解，永不重试）。
      final badId = a.nextUuid();
      final badMeta = a.stamp();
      final badPayload = a.makeEntry(id: badId, meta: badMeta).toJson()
        ..['schema_ver'] = domain.kCurrentSchemaVer + 1;
      await a.enqueueRaw(
        tableName: 'entries',
        rowId: badId,
        payload: badPayload,
        hlc: badMeta.hlc,
      );
      final r2 = await a.engine.syncOnce();
      expect(
        r2.rejections[domain.SyncRejectionReason.schemaVerRejected],
        1,
      );
      expect(r2.droppedOutbox, 1);
      expect(h.server.serverRow('entries', badId), isNull);
      expect(await a.pendingCount(), 0);

      // ── 暂缓类：rowMissing + upsert → 保留待重试；父行补送后转正清账。
      final entryId2 = a.nextUuid();
      final lineId = a.nextUuid();
      final lineMeta = a.stamp();
      await a.enqueueRaw(
        tableName: 'entry_lines',
        rowId: lineId,
        payload: a
            .makeLine(
              id: lineId,
              entryId: entryId2,
              type: domain.LineType.calorie,
              amount: 500,
              direction: domain.LineDirection.income,
              meta: lineMeta,
            )
            .toJson(),
        hlc: lineMeta.hlc,
      );
      final r3 = await a.engine.syncOnce();
      expect(r3.rejections[domain.SyncRejectionReason.rowMissing], 1);
      expect(await a.pendingCount(), 1); // 暂缓保留（父行未上送完成）
      expect(h.server.serverRow('entry_lines', lineId), isNull);

      // 父行补送（outbox 出队序：子行先入队在前、父行在后——同批先拒后 ack），
      // 引擎见 ack 非空继续下轮重试 → 父行已在服务端 → 转正清账（§6.2）。
      await a.writeEntryWithLines(
        a.makeEntry(id: entryId2, title: '迟到父行'),
      );
      final r4 = await a.engine.syncOnce();
      expect(r4.acked, 2);
      expect(r4.rejections[domain.SyncRejectionReason.rowMissing], 1);
      expect(await a.pendingCount(), 0);
      expect(h.server.serverRow('entry_lines', lineId), isNotNull);

      // ── 暂缓类的删除对侧：rowMissing + delete → 删除幂等完成 → drop。
      final ghostLineId = a.nextUuid();
      final ghostMeta = a.stamp();
      await a.enqueueRaw(
        tableName: 'entry_lines',
        rowId: ghostLineId,
        payload: <String, Object?>{
          'id': ghostLineId,
          'entry_id': 'missing-entry',
          'type': 'calorie',
          'amount': 1,
          'direction': 'income',
          'status': 'active',
          ...ghostMeta.toRowJson(),
        },
        hlc: ghostMeta.hlc,
        op: domain.OutboxOp.delete,
      );
      final r5 = await a.engine.syncOnce();
      expect(r5.rejections[domain.SyncRejectionReason.rowMissing], 1);
      expect(r5.droppedOutbox, 1);
      expect(await a.pendingCount(), 0);

      // ── 作废类三：baseRevision 乐观校验失败 → drop + 采纳服务端现值。
      final staleRow = (await a.rawRow('entries', entryId))!;
      final baseRev = staleRow['revision'] as int;
      a.wall.advance(30);
      final futureHlc = a.clock.now().format();
      await a.enqueueRaw(
        tableName: 'entries',
        rowId: entryId,
        payload: <String, Object?>{
          ...staleRow,
          'title': '基于旧版本的改写',
          'hlc': futureHlc,
          'updated_at': domain.Hlc.parse(futureHlc).physicalMs,
        },
        hlc: futureHlc,
        baseRevision: baseRev + 999, // 故意过期
      );
      final r6 = await a.engine.syncOnce();
      expect(
        r6.rejections[domain.SyncRejectionReason.baseRevisionConflict],
        1,
      );
      expect(r6.droppedOutbox, 1);
      expect(await a.pendingCount(), 0);
      // 采纳服务端现值：标题保持服务端版本（基线）。
      expect((await a.rawRow('entries', entryId))!['title'], '基线');
      expect(
        (await a.rawRow('entries', entryId))!['hlc'],
        serverHlc,
      );
    });

    test('④todos set 胜：服务端合并 ACK（非拒绝）+ 双端收敛到勾选态（§6.5 第 6 行）',
        () async {
      final h = await _openFakeHarness([kDeviceA, kDeviceB]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. A 建 todo（未完成）→ 上送 → 服务端 rev 1；B 拉取。
      final todoId = a.nextUuid();
      final todoMeta = a.stamp();
      await a.enqueueRaw(
        tableName: 'todos',
        rowId: todoId,
        payload: <String, Object?>{
          'id': todoId,
          'title': '买牛奶',
          'done_at': null,
          ...todoMeta.toRowJson(),
        },
        hlc: todoMeta.hlc,
      );
      await a.engine.syncOnce();
      await b.engine.syncOnce();
      expect(h.server.serverRow('todos', todoId)!['done_at'], isNull);

      // 2. B 勾选（done_at set，hlc 更新）→ 上送接受 → 服务端 done_at=set。
      b.wall.advance(10);
      final checkHlc = b.clock.now().format();
      final bRow = (await b.rawRow('todos', todoId))!;
      await b.enqueueRaw(
        tableName: 'todos',
        rowId: todoId,
        payload: <String, Object?>{
          ...bRow,
          'done_at': domain.Hlc.parse(checkHlc).physicalMs,
          'hlc': checkHlc,
          'updated_at': domain.Hlc.parse(checkHlc).physicalMs,
        },
        hlc: checkHlc,
        baseRevision: bRow['revision'] as int,
      );
      await b.engine.syncOnce();
      final serverDoneAt = h.server.serverRow('todos', todoId)!['done_at'];
      expect(serverDoneAt, isNotNull);
      final serverRev = h.server.serverRow('todos', todoId)!['revision'] as int;

      // 3. A 的取消完成 op 仍带旧 baseRevision（rev 1，服务端已到 rev 2）
      //    ——模拟「与 B 勾选并发」：服务端按 set 胜合并 → **ACK 而非拒绝**
      //    （勾选永不丢失，§6.5 第 6 行）。
      a.wall.advance(20);
      final unsetHlc = a.clock.now().format();
      await a.enqueueRaw(
        tableName: 'todos',
        rowId: todoId,
        payload: <String, Object?>{
          'id': todoId,
          'title': '买牛奶',
          'done_at': null,
          'hlc': unsetHlc,
        },
        hlc: unsetHlc,
        baseRevision: 1, // 旧版本（服务端已到 rev 2）→ 并发 unset
      );
      final reportA = await a.engine.syncOnce();
      expect(reportA.acked, 1); // 合并被接受（非拒绝）
      expect(reportA.rejections, isEmpty);
      final mergedRev = h.server.serverRow('todos', todoId)!['revision'] as int;
      expect(mergedRev, serverRev + 1);
      // 服务端合并快照：hlc = A 的 unset 戳（更晚），done_at = B 的勾选（保留）。
      final serverRow = h.server.serverRow('todos', todoId)!;
      expect(serverRow['hlc'], unsetHlc);
      expect(serverRow['done_at'], serverDoneAt);

      // 4. 双端 pull 收敛到同一合并结果：A 的合并回显已在 reportA 的 pull
      //    相位经 todoDoneForward 落库（本地 done_at null + 远端 set → set 胜
      //    ——syncOnce 恒含 pull，§6.2），故再拉无增量；B 经 LWW 前进。
      final reportA2 = await a.engine.syncOnce();
      expect(reportA2.applied, 0);
      await b.engine.syncOnce();
      for (final d in [a, b]) {
        final row = await d.rawRow('todos', todoId);
        expect(row!['done_at'], serverDoneAt, reason: '${d.deviceId} 未收敛');
        expect(row['hlc'], unsetHlc);
      }
    });

    test('⑤低水位迟到行：游标已越过的行经服务端水位补漏投递（§6.2/§6.7）', () async {
      final h = await _openFakeHarness([kDeviceA, kDeviceB]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);
      final b = h.device(1);

      // 1. B 先离线写（hlc = 基准墙钟，早于 A 的任何写入）。
      final lateId = b.nextUuid();
      await b.writeEntryWithLines(
        b.makeEntry(id: lateId, title: '迟到行'),
      );

      // 2. A 后写并上送：A 的游标推进到比「迟到行」hlc 更大的位置——
      //    纯游标 pull 从此看不见该行（投递洞），须靠 revision 水位补漏。
      final lateHlc = (await b.rawRow('entries', lateId))!['hlc'] as String;
      a.wall.advance(5000);
      final freshId = a.nextUuid();
      await a.writeEntryWithLines(
        a.makeEntry(id: freshId, title: '新行'),
      );
      final r1 = await a.engine.syncOnce();
      expect(r1.error, isNull);
      // 前提断言：游标已越过迟到行的 hlc（定宽字典序，§6.3）。
      expect(r1.cursors['entries']!.compareTo(lateHlc) > 0, isTrue);

      // 3. B 上送迟到行（服务端接受：新行无 hlc 单调约束）→ A 再拉：
      //    hlc ≤ 游标但 revision > 水位 → 补投一次 → 双端收敛。
      await b.engine.syncOnce();
      final r3 = await a.engine.syncOnce();
      expect(r3.applied, 1); // 迟到行落库（hlc 低于游标仍被补投）
      expect((await a.rawRow('entries', lateId)), isNotNull);
      expect(
        (await a.rawRow('entries', lateId))!['title'],
        '迟到行',
      );
      // 二次同步无增量（水位已推进，投递簿/水位双轨去重）。
      final r4 = await a.engine.syncOnce();
      expect(r4.pulled, 0);
    });

    test('⑥传输层故障：降级报错不抛出、outbox 保全、恢复后清账（§6.1 原则 1）',
        () async {
      final h = await _openFakeHarness([kDeviceA]);
      if (h == null) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，同步引擎测试未执行');
        return;
      }
      addTearDown(h.close);
      final a = h.device(0);

      await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));
      await a.writeEntryWithLines(a.makeEntry(id: a.nextUuid()));

      // 注入网络错（传输层 fault）：syncOnce 捕获为 report.error、不抛出。
      h.server.faults.add(SyncBackendException('network', '断网（模拟）'));
      final report = await a.engine.syncOnce();
      expect(report.error, isA<SyncBackendException>());
      expect(report.acked, 0);
      expect(await a.pendingCount(), 2);
      expect(a.statuses.last.phase, SyncPhase.error);
      expect(a.statuses.last.error, isNotNull);

      // 恢复（清除故障）：同一批出网项重试幂等清账（§5.6⑯ 幂等键）。
      h.server.faults.clear();
      final ok = await a.engine.syncOnce();
      expect(ok.error, isNull);
      expect(ok.acked, 2);
      expect(await a.pendingCount(), 0);
      expect(a.statuses.last.phase, SyncPhase.done);
    });
  });
}

/// 双设备收敛场景（双轨同脚本，§6.2「可换后端不动 schema」验收面）。
Future<void> _convergeScenario(_Track track) async {
  final a = track.device(0);
  final b = track.device(1);
  final ledgerA = await a.defaultLedgerId();
  final ledgerB = await b.defaultLedgerId();

  // 1. 双端各自写（A 3 条 + 金额行、B 2 条 + 金额行）——同一基准墙钟下
  //    双端 hlc 物理段相同（仅节点段区分），天然构造「B 的全部 hlc 低于
  //    A 游标」的投递洞场景，验收水位/投递簿补漏。
  for (var i = 0; i < 3; i++) {
    final id = a.nextUuid();
    await a.writeEntryWithLines(
      a.makeEntry(id: id, title: 'A-$i', date: kHarnessDate),
      [
        a.makeLine(
          id: a.nextUuid(),
          entryId: id,
          type: domain.LineType.money,
          amount: 100 + i,
          direction: domain.LineDirection.outcome,
          ledgerId: ledgerA,
          currency: 'CNY',
        ),
      ],
    );
  }
  for (var i = 0; i < 2; i++) {
    final id = b.nextUuid();
    await b.writeEntryWithLines(
      b.makeEntry(id: id, title: 'B-$i', date: kHarnessDate),
      [
        b.makeLine(
          id: b.nextUuid(),
          entryId: id,
          type: domain.LineType.money,
          amount: 500 + i,
          direction: domain.LineDirection.outcome,
          ledgerId: ledgerB,
          currency: 'CNY',
        ),
      ],
    );
  }

  // 2. 三轮同步：A 清账+回显 → B 落库 A + 清账 → A 补投 B 的低水位行。
  final r1 = await a.engine.syncOnce();
  expect(r1.error, isNull);
  expect(r1.acked, 6);
  expect(r1.skipped, 6); // 自身回显跳过（游标推进，§6.2）
  final r2 = await b.engine.syncOnce();
  expect(r2.error, isNull);
  expect(r2.acked, 4);
  expect(r2.applied, 6); // A 的 6 行落库
  expect(r2.skipped, 4); // 自身回显跳过
  final r3 = await a.engine.syncOnce();
  expect(r3.error, isNull);
  expect(r3.applied, 4); // B 的 4 行补投落库（hlc ≤ 游标，水位补漏）

  // 3. 行级一致（§6.7）：两张真值表逐行全字段相等（含权威 revision/hlc）。
  for (final table in const ['entries', 'entry_lines']) {
    final rowsA = await a.database
        .customSelect('SELECT * FROM "$table" ORDER BY id')
        .get();
    final rowsB = await b.database
        .customSelect('SELECT * FROM "$table" ORDER BY id')
        .get();
    expect(rowsA.length, 5, reason: '$table 行数');
    for (var i = 0; i < rowsA.length; i++) {
      expect(
        rowsA[i].data,
        equals(rowsB[i].data),
        reason: '$table 第 $i 行双轨不一致',
      );
    }
  }

  // 4. 双端清账、游标推进、投影自愈一致（§5.6⑬/§6.5 末行）。
  expect(await a.pendingCount(), 0);
  expect(await b.pendingCount(), 0);
  final summaryA = await a.daySummaryOf(kHarnessDate);
  final summaryB = await b.daySummaryOf(kHarnessDate);
  expect(summaryA, equals(summaryB));
  expect(summaryA['spend_minor'], 303 + 1001);
}
