/// SyncBackend 抽象实现的单元测试（无 sqlite、纯内存）。
///
/// 覆盖 §6.2 服务端校验清单的服务端半边（InMemorySyncBackend Fake）：
/// 幂等键重放、hlc 单调、baseRevision 乐观校验、墓碑拒绝复活、行存在性、
/// schema_ver 超档、未知表、pull 游标/排序/墓碑 op/分批 hasMore、分区异常、
/// fetchRow 采纳源；以及 LocalLoopbackBackend 的缺省装配语义（§6.1）。
/// 全程 Fake，禁真实网络（§6.7）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';

import 'package:feature_sync/feature_sync.dart';

const String kDevice = 'A1B2C3D4E5F6';
const String kOther = 'F6E5D4C3B2A1';

String hlcOf(int physicalMs, int counter, String device) =>
    domain.Hlc(physicalMs: physicalMs, counter: counter, deviceId: device)
        .format();

/// 造一条出网项（默认挂 ledgers 表——无父依赖、便于直测校验矩阵）。
domain.OutboxEntry op({
  String id = 'ob-1',
  String tableName = 'ledgers',
  String rowId = 'l1',
  domain.OutboxOp operation = domain.OutboxOp.upsert,
  int? schemaVer,
  int? deletedAt,
  required String hlc,
  int? baseRevision,
  Map<String, Object?> extra = const {},
}) {
  final payload = <String, Object?>{
    'id': rowId,
    'hlc': hlc,
    if (schemaVer != null) 'schema_ver': schemaVer,
    if (deletedAt != null) 'deleted_at': deletedAt,
    ...extra,
  };
  return domain.OutboxEntry(
    id: id,
    tableName: tableName,
    rowId: rowId,
    op: operation,
    payload: jsonEncode(payload),
    baseRevision: baseRevision,
    hlc: hlc,
    createdAt: domain.Hlc.parse(hlc).physicalMs,
  );
}

void main() {
  group('InMemorySyncBackend：§6.2 服务端校验矩阵', () {
    test('幂等键重放：同 outbox.id 重试原回执重放、不重复入账', () async {
      final backend = InMemorySyncBackend();
      final entry = op(hlc: hlcOf(1000, 0, kDevice));

      final first = await backend.push([entry], deviceId: kDevice);
      expect(first.acks.single.revision, 1);

      // 模拟重试：同一出网项再次上送 → 原回执重放（§5.6⑯ id 行）。
      final retry = await backend.push([entry], deviceId: kDevice);
      expect(retry.acks.single.revision, 1);
      expect(backend.rowCount('ledgers'), 1);
      expect(backend.lastSeq, 1); // 未重复签发 seq
    });

    test('hlc 单调：stale 写拒绝（LWW 后写者胜的服务端半边）', () async {
      final backend = InMemorySyncBackend();
      await backend.push(
        [op(hlc: hlcOf(2000, 0, kDevice))],
        deviceId: kDevice,
      );

      final stale = await backend.push(
        [op(id: 'ob-2', hlc: hlcOf(1000, 0, kOther))],
        deviceId: kDevice,
      );
      expect(stale.rejections.single.reason,
          domain.SyncRejectionReason.hlcNonMonotonic);
      // 相等同样拒绝（严格递增）。
      final equal = await backend.push(
        [op(id: 'ob-3', hlc: hlcOf(2000, 0, kOther))],
        deviceId: kDevice,
      );
      expect(equal.rejections.single.reason,
          domain.SyncRejectionReason.hlcNonMonotonic);
    });

    test('baseRevision 乐观校验：权威 revision 不符拒绝（§5.6⑯）', () async {
      final backend = InMemorySyncBackend();
      final first = await backend.push(
        [op(hlc: hlcOf(1000, 0, kDevice))],
        deviceId: kDevice,
      );
      expect(first.acks.single.revision, 1);

      // hlc 更新但 baseRevision 与服务端权威 revision 不符 → 拒绝。
      final conflict = await backend.push(
        [
          op(
            id: 'ob-2',
            hlc: hlcOf(2000, 0, kDevice),
            baseRevision: 99,
          ),
        ],
        deviceId: kDevice,
      );
      expect(conflict.rejections.single.reason,
          domain.SyncRejectionReason.baseRevisionConflict);

      // baseRevision 相符 → 接受并签发新 revision。
      final ok = await backend.push(
        [
          op(
            id: 'ob-3',
            hlc: hlcOf(3000, 0, kDevice),
            baseRevision: 1,
          ),
        ],
        deviceId: kDevice,
      );
      expect(ok.acks.single.revision, 2);
    });

    test('墓碑拒绝复活：已删行再收存活 upsert → tombstoneConflict（§6.5）',
        () async {
      final backend = InMemorySyncBackend();
      // 删除 op（payload 带墓碑时刻）。
      final delete = await backend.push(
        [
          op(
            id: 'ob-del',
            operation: domain.OutboxOp.delete,
            deletedAt: 1234,
            hlc: hlcOf(1000, 0, kDevice),
          ),
        ],
        deviceId: kDevice,
      );
      expect(delete.acks, hasLength(1));
      expect(backend.rowState('ledgers', 'l1')!.isTombstone, isTrue);

      // 存活 upsert（无 deleted_at、hlc 更新）→ 服务端拒绝复活。
      final revive = await backend.push(
        [op(id: 'ob-2', hlc: hlcOf(9000, 0, kOther))],
        deviceId: kDevice,
      );
      expect(revive.rejections.single.reason,
          domain.SyncRejectionReason.tombstoneConflict);
      // 墓碑保持——复活未得逞。
      expect(backend.rowState('ledgers', 'l1')!.isTombstone, isTrue);
    });

    test('行存在性：子表父行缺失拒绝（corrections 无父检查，§5.6⑮）', () async {
      final backend = InMemorySyncBackend();

      final missing = await backend.push(
        [
          op(
            id: 'ob-line',
            tableName: 'entry_lines',
            rowId: 'line-1',
            hlc: hlcOf(1000, 0, kDevice),
            extra: {'entry_id': 'no-such-entry'},
          ),
        ],
        deviceId: kDevice,
      );
      expect(missing.rejections.single.reason,
          domain.SyncRejectionReason.rowMissing);

      // corrections 表不声明父表（审计行永可插入，§5.6⑮）→ 接受。
      final audit = await backend.push(
        [
          op(
            id: 'ob-corr',
            tableName: 'corrections',
            rowId: 'corr-1',
            hlc: hlcOf(1000, 1, kDevice),
            extra: {'entry_id': 'no-such-entry'},
          ),
        ],
        deviceId: kDevice,
      );
      expect(audit.rejections, isEmpty);
      expect(backend.rowCount('corrections'), 1);
    });

    test('schema_ver 超档拒绝（§6.4）；未知表按 unknown 拒绝（表集 W1 冻结）',
        () async {
      final backend = InMemorySyncBackend();

      final overTier = await backend.push(
        [op(id: 'ob-1', schemaVer: 2, hlc: hlcOf(1000, 0, kDevice))],
        deviceId: kDevice,
      );
      expect(overTier.rejections.single.reason,
          domain.SyncRejectionReason.schemaVerRejected);
      expect(backend.rowCount('ledgers'), 0);

      final unknownTable = await backend.push(
        [
          op(
            id: 'ob-2',
            tableName: 'not_in_catalog',
            hlc: hlcOf(1000, 1, kDevice),
          ),
        ],
        deviceId: kDevice,
      );
      expect(unknownTable.rejections.single.reason,
          domain.SyncRejectionReason.unknown);
    });
  });

  group('InMemorySyncBackend：pull 与运维语义', () {
    test('pull：hlc 升序、墓碑以 delete op 交付、游标增量、分批 hasMore',
        () async {
      final backend = InMemorySyncBackend(maxPullRows: 2);
      await backend.push(
        [
          op(id: 'ob-1', rowId: 'l1', hlc: hlcOf(1000, 0, kDevice)),
          op(id: 'ob-2', rowId: 'l2', hlc: hlcOf(2000, 0, kDevice)),
          op(
            id: 'ob-3',
            rowId: 'l3',
            operation: domain.OutboxOp.delete,
            deletedAt: 3000,
            hlc: hlcOf(3000, 0, kDevice),
          ),
        ],
        deviceId: kDevice,
      );

      // 首拉（无游标）：上限 2 条，hlc 升序，hasMore=true。
      final first = await backend.pull(const {}, deviceId: kDevice);
      expect(first.changes, hasLength(2));
      expect(first.hasMore, isTrue);
      expect(first.nextCursors['ledgers'], hlcOf(2000, 0, kDevice));

      // 续拉：游标增量；墓碑行以 delete op 交付（§6.2 含墓碑行）。
      final second = await backend.pull(
        {'ledgers': hlcOf(2000, 0, kDevice)},
        deviceId: kDevice,
      );
      expect(second.changes, hasLength(1));
      expect(second.hasMore, isFalse);
      expect(second.changes.single.op, domain.OutboxOp.delete);
      expect(second.changes.single.rowId, 'l3');
      expect(second.nextCursors['ledgers'], hlcOf(3000, 0, kDevice));
    });

    test('分区：push/pull/register 一律不可达（§6.1 原则 1 的模拟源）', () async {
      final backend = InMemorySyncBackend();
      backend.partition(kDevice);

      await expectLater(
        backend.push([op(hlc: hlcOf(1000, 0, kDevice))], deviceId: kDevice),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'partitioned'),
        ),
      );
      await expectLater(
        backend.pull(const {}, deviceId: kDevice),
        throwsA(isA<SyncBackendException>()),
      );

      // 其他设备不受影响（设备级隔离；用不同行避免行级 hlc 相互干扰）。
      final ok = await backend.push(
        [
          op(
            id: 'ob-9',
            rowId: 'l2',
            hlc: hlcOf(1000, 0, kOther),
          ),
        ],
        deviceId: kOther,
      );
      expect(ok.acks, hasLength(1));

      // 恢复联网后可达。
      backend.restore(kDevice);
      final after = await backend.push(
        [op(id: 'ob-1', hlc: hlcOf(1000, 0, kDevice))],
        deviceId: kDevice,
      );
      expect(after.acks, hasLength(1));
    });

    test('fetchRow：采纳源返回行现值；缺失行返回 null', () async {
      final backend = InMemorySyncBackend();
      await backend.push(
        [op(hlc: hlcOf(1000, 0, kDevice), extra: {'name': '默认账本'})],
        deviceId: kDevice,
      );

      final row = await backend.fetchRow(tableName: 'ledgers', rowId: 'l1');
      expect(row, isNotNull);
      expect(row!.hlc, hlcOf(1000, 0, kDevice));
      expect(row.op, domain.OutboxOp.upsert);
      expect(
        (jsonDecode(row.payload) as Map<String, Object?>)['name'],
        '默认账本',
      );

      final missing =
          await backend.fetchRow(tableName: 'ledgers', rowId: 'nope');
      expect(missing, isNull);
    });

    test('registerDevice：幂等登记（重复注册=刷新，§5.6⑰）', () async {
      final backend = InMemorySyncBackend();
      final registration = DeviceRegistration(
        id: kDevice,
        name: '手机',
        platform: 'android',
        createdAt: 1000,
      );
      await backend.registerDevice(registration, deviceId: kDevice);
      await backend.registerDevice(registration, deviceId: kDevice);
      expect(backend.devices, hasLength(1));
      expect(backend.devices[kDevice]!.name, '手机');
    });
  });

  group('LocalLoopbackBackend：无服务端缺省装配（§6.1 本地优先）', () {
    test('push：本地签发递增 revision、幂等键重放；pull 恒空；fetchRow 恒 null',
        () async {
      final backend = LocalLoopbackBackend();
      final e1 = op(id: 'ob-1', rowId: 'l1', hlc: hlcOf(1000, 0, kDevice));
      final e2 = op(id: 'ob-2', rowId: 'l2', hlc: hlcOf(2000, 0, kDevice));

      final result = await backend.push([e1, e2], deviceId: kDevice);
      expect(result.rejections, isEmpty);
      expect(result.acks[0].revision, 1);
      expect(result.acks[1].revision, 2);

      // 重试重放：原回执原样返回。
      final replay = await backend.push([e1], deviceId: kDevice);
      expect(replay.acks.single.revision, 1);

      // pull 恒空（一切数据已在本地，无增量）。
      final pulled = await backend.pull(const {}, deviceId: kDevice);
      expect(pulled.changes, isEmpty);
      expect(pulled.hasMore, isFalse);

      // 无远端现值可采纳。
      expect(
        await backend.fetchRow(tableName: 'ledgers', rowId: 'l1'),
        isNull,
      );
    });
  });
}
