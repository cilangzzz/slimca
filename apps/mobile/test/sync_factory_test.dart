/// 同步装配工厂与托管后端接线测试（§11.1 W7-8「SupabaseSyncBackend 构造 +
/// 缺省回环」任务验收；§10.4 壳负责装配）。
///
/// 覆盖：
/// - 工厂配置分支（dart-define 缺省态 = 本地回环，待用户凭据；URL+key 齐 =
///   SupabaseSyncBackend；仅给其一 = 回环）；
/// - 托管后端经 mock transport（禁真实网络，§6.7）的线协议回环：push 请求
///   形状（payload 解包为 jsonb、base_revision 仅非空携带）、acks/rejections
///   映射（reason 枚举）、pull 变更映射、fetchRow 契约、registerDevice 参数、
///   传输失败原样上抛（§6.1 原则 1 引擎侧降级）；
/// - TelemetrySyncBackend 装饰器：同步 push/pull 成败漏斗（§12 验收口径）。
library;

import 'package:core_domain/core_domain.dart';
import 'package:feature_sync/feature_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/sync/sync_backend_factory.dart';
import 'package:slimca/sync/telemetry_sync_backend.dart';

import 'test_support.dart';

/// 脚本化 mock transport（记录调用、注入响应/异常；禁真实网络，§6.7）。
class FakeSyncTransport implements SyncRpcTransport {
  FakeSyncTransport({this.rpcResponse, this.rpcError, this.row, this.rowError});

  /// call() 的脚本化返回（jsonb 原样透传）。
  Object? rpcResponse;

  /// call() 注入的异常（原样抛出）。
  Object? rpcError;

  /// readRow() 的脚本化返回（null=行不存在契约）。
  Object? row;

  /// readRow() 注入的异常。
  Object? rowError;

  final List<({String fn, Map<String, Object?> params})> calls = [];

  @override
  Future<Object?> call(String fnName, Map<String, Object?> params) async {
    calls.add((fn: fnName, params: params));
    final error = rpcError;
    if (error != null) {
      throw error;
    }
    return rpcResponse;
  }

  @override
  Future<Object?> readRow(String tableName, String rowId) async {
    if (rowError != null) {
      throw rowError!;
    }
    return row;
  }
}

/// 记录型 stub 后端（TelemetrySyncBackend 装饰器断言用）。
class StubBackend implements SyncBackend {
  Object? pushError;
  Object? pullError;
  int pushCalls = 0;
  int pullCalls = 0;

  @override
  Future<SyncPushResult> push(
    List<OutboxEntry> batch, {
    required String deviceId,
  }) async {
    pushCalls++;
    final error = pushError;
    if (error != null) {
      throw error;
    }
    return const SyncPushResult(acks: [], rejections: []);
  }

  @override
  Future<SyncPullResult> pull(
    SyncPullCursors since, {
    required String deviceId,
  }) async {
    pullCalls++;
    final error = pullError;
    if (error != null) {
      throw error;
    }
    return const SyncPullResult(
      changes: [],
      nextCursors: {},
      hasMore: false,
    );
  }

  @override
  Future<RemoteChange?> fetchRow({
    required String tableName,
    required String rowId,
  }) async =>
      null;

  @override
  Future<void> registerDevice(
    DeviceRegistration registration, {
    required String deviceId,
  }) async {}
}

OutboxEntry _entry({int? baseRevision}) => OutboxEntry(
      id: 'ob-1',
      tableName: 'entries',
      rowId: 'row-1',
      op: OutboxOp.upsert,
      payload: '{"id":"row-1","title":"x"}',
      baseRevision: baseRevision,
      hlc: '0001ABCDEFGH:000001:0000',
      createdAt: 1700000000000,
    );

void main() {
  group('工厂配置分支（§10.4；凭据待用户注入）', () {
    test('无凭据（dart-define 缺省态）→ 本地回环兜底（§6.1 本地优先）', () {
      // 测试进程无 dart-define 注入 → 缺省分支。
      expect(createSyncBackend(), isA<LocalLoopbackBackend>());
    });

    test('仅 URL 或仅 key（任一缺失）→ 本地回环', () {
      expect(
        createSyncBackend(
          supabaseUrl: 'https://example.supabase.co',
          anonKey: '',
        ),
        isA<LocalLoopbackBackend>(),
      );
      expect(
        createSyncBackend(
          supabaseUrl: '',
          anonKey: 'anon-key',
        ),
        isA<LocalLoopbackBackend>(),
      );
    });

    test('URL + anon key 齐 → SupabaseSyncBackend（mock transport 注入）', () {
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'anon-key',
        transport: FakeSyncTransport(),
      );
      expect(backend, isA<SupabaseSyncBackend>());
    });

    test('describeSyncBackend：装配描述标注「待用户凭据」', () {
      expect(
        describeSyncBackend(supabaseUrl: '', anonKey: ''),
        contains('本地回环'),
      );
      expect(describeSyncBackend(supabaseUrl: '', anonKey: ''),
          contains('待用户凭据'));
      expect(
        describeSyncBackend(
          supabaseUrl: 'https://example.supabase.co',
          anonKey: 'k',
        ),
        contains('Supabase 托管'),
      );
    });
  });

  group('托管后端线协议回环（mock transport；§6.2 读写路径）', () {
    test('push：请求形状（p_device_id/p_ops、payload 解包 jsonb、base_revision '
        '仅非空携带）+ acks/rejections 映射', () async {
      final transport = FakeSyncTransport(
        rpcResponse: <String, Object?>{
          'acks': [
            <String, Object?>{
              'outbox_id': 'ob-1',
              'revision': 12,
              'acked_at': 1700000001000,
            },
          ],
          'rejections': [
            <String, Object?>{'outbox_id': 'ob-2', 'reason': 'hlc_non_monotonic'},
          ],
        },
      );
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'anon-key',
        transport: transport,
      ) as SupabaseSyncBackend;

      final result = await backend.push([_entry()], deviceId: 'DEV000000001');

      // 请求形状（§6.2 POST /rpc/sync_push 的 RPC 命名与参数）。
      expect(transport.calls.single.fn, SupabaseSyncBackend.pushRpcName);
      final params = transport.calls.single.params;
      expect(params['p_device_id'], 'DEV000000001');
      final ops = params['p_ops']! as List<Object?>;
      expect(ops.length, 1);
      final op = ops.single! as Map<String, Object?>;
      expect(op['outbox_id'], 'ob-1');
      expect(op['table_name'], 'entries');
      expect(op['row_id'], 'row-1');
      expect(op['op'], 'upsert');
      expect(op['hlc'], '0001ABCDEFGH:000001:0000');
      // payload 由 JSON 字符串解包为内嵌 jsonb 对象（§5.6⑯，服务端按列同构展开）。
      expect(op['payload'], {'id': 'row-1', 'title': 'x'});
      expect(op.containsKey('base_revision'), isFalse, reason: 'null 不携带');

      // 回执映射：ack 权威 revision + rejection reason 枚举。
      expect(result.acks.single.outboxId, 'ob-1');
      expect(result.acks.single.revision, 12);
      expect(result.acks.single.ackedAt, 1700000001000);
      expect(result.rejections.single.reason, SyncRejectionReason.hlcNonMonotonic);

      // base_revision 非空 → 携带（§5.6⑯ 乐观校验）。
      await backend.push([_entry(baseRevision: 7)], deviceId: 'DEV000000001');
      final op2 = (transport.calls.last.params['p_ops']!
          as List<Object?>).single! as Map<String, Object?>;
      expect(op2['base_revision'], 7);
    });

    test('push：payload 非法 JSON → SyncBackendException(protocol)', () async {
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'k',
        transport: FakeSyncTransport(),
      ) as SupabaseSyncBackend;
      final bad = OutboxEntry(
        id: 'ob-bad',
        tableName: 'entries',
        rowId: 'row-bad',
        op: OutboxOp.upsert,
        payload: '{not-json',
        hlc: '0001ABCDEFGH:000002:0000',
        createdAt: 1700000000000,
      );
      await expectLater(
        backend.push([bad], deviceId: 'DEV000000001'),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });

    test('pull：变更映射（payload 重编码字符串、schema_ver 缺省补当前档）', () async {
      final row = <String, Object?>{'id': 'row-1', 'title': 'x'};
      final transport = FakeSyncTransport(
        rpcResponse: <String, Object?>{
          'changes': [
            <String, Object?>{
              'table_name': 'entries',
              'row_id': 'row-1',
              'op': 'upsert',
              'row': row,
              'hlc': '0001ZZZZZZZZ:000009:0000',
              'revision': 9,
              // schema_ver 缺省 → kCurrentSchemaVer 兜底。
            },
          ],
          'cursors': <String, String>{'entries': '0001ZZZZZZZZ:000009:0000'},
          'has_more': true,
        },
      );
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'k',
        transport: transport,
      ) as SupabaseSyncBackend;

      final result = await backend.pull(
        {'entries': '0001AAAA:000003:0000'},
        deviceId: 'DEV000000001',
      );

      expect(transport.calls.single.fn, SupabaseSyncBackend.pullRpcName);
      expect(
        transport.calls.single.params['p_cursors'],
        {'entries': '0001AAAA:000003:0000'},
      );
      expect(result.hasMore, isTrue);
      expect(result.nextCursors, {'entries': '0001ZZZZZZZZ:000009:0000'});
      final change = result.changes.single;
      expect(change.tableName, 'entries');
      expect(change.rowId, 'row-1');
      expect(change.op, OutboxOp.upsert);
      expect(change.revision, 9);
      expect(change.schemaVer, kCurrentSchemaVer);
      // payload 回到行快照 JSON 字符串（RemoteChange 契约，引擎侧解析）。
      expect(change.payload, '{"id":"row-1","title":"x"}');
    });

    test('传输异常原样上抛（引擎捕获降级，§6.1 原则 1）', () async {
      final transport = FakeSyncTransport(
        rpcError: const SyncBackendException('network', '断网'),
      );
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'k',
        transport: transport,
      ) as SupabaseSyncBackend;

      await expectLater(
        backend.push([_entry()], deviceId: 'DEV000000001'),
        throwsA(
          isA<SyncBackendException>().having((e) => e.code, 'code', 'network'),
        ),
      );
    });

    test('registerDevice：幂等注册参数（§5.6⑰）', () async {
      final transport = FakeSyncTransport(rpcResponse: <String, Object?>{});
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'k',
        transport: transport,
      ) as SupabaseSyncBackend;

      await backend.registerDevice(
        DeviceRegistration(
          id: 'DEV000000001',
          name: 'Slimca 移动端',
          platform: 'android',
          createdAt: 1700000000000,
        ),
        deviceId: 'DEV000000001',
      );

      expect(transport.calls.single.fn, SupabaseSyncBackend.registerRpcName);
      expect(transport.calls.single.params, {
        'p_device_id': 'DEV000000001',
        'p_name': 'Slimca 移动端',
        'p_platform': 'android',
        'p_created_at': 1700000000000,
      });
    });

    test('fetchRow：行不存在 → null；存在 → RemoteChange（含墓碑 op 映射）',
        () async {
      final backend = createSyncBackend(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'k',
        transport: FakeSyncTransport(),
      ) as SupabaseSyncBackend;

      // 行不存在（RLS 过滤/GC）→ null 契约。
      expect(
        await backend.fetchRow(tableName: 'entries', rowId: 'missing'),
        isNull,
      );
    });

    test('fetchRow：存活行 → upsert；软删行 → delete（墓碑语义一致）', () async {
      final transport = FakeSyncTransport(
        row: <String, Object?>{
          'id': 'row-1',
          'title': 'x',
          'hlc': '0001ABCDEFGH:000004:0000',
          'revision': 4,
          'schema_ver': 1,
          'deleted_at': null,
        },
      );
      final backend = SupabaseSyncBackend(
        config: const SyncConfig(url: 'https://example.supabase.co', anonKey: 'k'),
        transport: transport,
      );

      final change = await backend.fetchRow(tableName: 'entries', rowId: 'row-1');
      expect(change, isNotNull);
      expect(change!.op, OutboxOp.upsert);
      expect(change.hlc, '0001ABCDEFGH:000004:0000');
      expect(change.revision, 4);

      transport.row = <String, Object?>{
        'id': 'row-1',
        'hlc': '0001ABCDEFGH:000005:0000',
        'deleted_at': 1700000002000,
      };
      final tombstone =
          await backend.fetchRow(tableName: 'entries', rowId: 'row-1');
      expect(tombstone!.op, OutboxOp.delete);
    });
  });

  group('TelemetrySyncBackend 装饰器（§12 漏斗：同步 push/pull 成败）', () {
    test('push/pull 成功 → sync_push_ok / sync_pull_ok（计数 props）', () async {
      final telemetry = RecordingTelemetryService();
      final backend = TelemetrySyncBackend(
        inner: StubBackend(),
        telemetry: telemetry,
      );

      await backend.push([_entry()], deviceId: 'DEV000000001');
      await backend.pull({}, deviceId: 'DEV000000001');

      expect(telemetry.byName(TelemetryFunnel.syncPushOk).single.props,
          {'batch': 1, 'acked': 0});
      expect(telemetry.byName(TelemetryFunnel.syncPullOk).single.props,
          {'changes': 0});
    });

    test('push/pull 失败 → sync_push_fail / sync_pull_fail（只记错误类型）',
        () async {
      final telemetry = RecordingTelemetryService();
      final inner = StubBackend()
        ..pushError = const SyncBackendException('network', '断网内容')
        ..pullError = const SyncBackendException('timeout', '超时内容');
      final backend = TelemetrySyncBackend(
        inner: inner,
        telemetry: telemetry,
      );

      await expectLater(
        backend.push([_entry()], deviceId: 'DEV000000001'),
        throwsA(isA<SyncBackendException>()),
      );
      await expectLater(
        backend.pull({}, deviceId: 'DEV000000001'),
        throwsA(isA<SyncBackendException>()),
      );

      expect(inner.pushCalls, 1, reason: '异常原样上抛，装饰器只旁观（§6.1）');
      expect(
        telemetry.byName(TelemetryFunnel.syncPushFail).single.props,
        {'error_type': 'SyncBackendException'},
      );
      expect(
        telemetry.byName(TelemetryFunnel.syncPullFail).single.props,
        {'error_type': 'SyncBackendException'},
      );
      // 失败 message 内容禁入任何遥测（§3.9）。
      for (final event in telemetry.events) {
        expect(event.props.values.contains('断网内容'), isFalse);
        expect(event.props.values.contains('超时内容'), isFalse);
      }
    });
  });
}
