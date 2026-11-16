/// W7-8 契约测试（§11.1 W7-8「契约测试：mock transport 模拟 Supabase RPC
/// 响应」+ §6.7 测试策略）。
///
/// 三个被测面（全程禁真实网络）：
/// 1. **线协议契约**（[SupabaseSyncBackend] × [ScriptedRpcTransport]）：
///    请求编码（p_ops/payload 解包/base_revision 省略）、响应解析
///    （acks/rejections 六类 wire reason ↔ 枚举映射，未知 reason 前向兼容）、
///    畸形响应 → protocol 异常、pull 变更/游标/has_more 解析、fetchRow、
///    设备注册；
/// 2. **真实传输栈**（[SupabaseRpcTransport] × [FakeHttpTransport]）：
///    rpc 参数走 `POST /rest/v1/rpc/<fn>`、单行直读走 GET，PostgrestException
///    → protocol、ClientException → network、TimeoutException → timeout
///    （§6.1 原则 1 的三分类异常面）；
/// 3. **服务端幂等线级契约**（[FakeSupabaseRpcServer] × 同一 backend）：
///    幂等键 = outbox.id 的重放（原回执重放、不重复签发 revision）。
///
/// 拒绝的三分类处置（作废/暂缓/幂等完成）在线协议面只验 reason 映射；
/// 端到端处置（drop/暂缓保留/采纳服务端现值）见 supabase_engine_chain_test。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as domain;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http_pkg;
import 'package:supabase/supabase.dart';

import 'package:feature_sync/feature_sync.dart';

import 'supabase_fakes.dart';

const String kDev = 'A1B2C3D4E5F6';
const int kBaseMs = 1763251200000; // 2026-11-16T00:00:00Z（13 位，§6.3）

String hlcOf(int physicalMs, int counter, [String device = kDev]) =>
    domain.Hlc(physicalMs: physicalMs, counter: counter, deviceId: device)
        .format();

// W7-8 集成注：core_domain 类型一律走 `domain.` 前缀——本文件与
// feature_sync barrel 并存导入，避免同步契约类型无前缀引用的歧义。
domain.OutboxEntry entryOp({
  String outboxId = 'ob-1',
  String tableName = 'entries',
  String rowId = 'row-1',
  domain.OutboxOp op = domain.OutboxOp.upsert,
  Object? payload,
  int? baseRevision,
  String? hlc,
}) =>
    domain.OutboxEntry(
      id: outboxId,
      tableName: tableName,
      rowId: rowId,
      op: op,
      // W7-8 集成注：缺省 payload 必须是空 **Map**（`<String, Object?>{}`）——
      // `<Object?>{}` 字面量是 Set，jsonEncode 不能编码 Set（集成联调修）。
      payload: payload is String ? payload : jsonEncode(payload ?? <String, Object?>{}),
      baseRevision: baseRevision,
      hlc: hlc ?? hlcOf(kBaseMs, 1),
      createdAt: kBaseMs,
    );

void main() {
  group('① 线协议：请求编码（ScriptedRpcTransport 记录）', () {
    test('push 请求形状：p_ops 解包 payload、base_revision 按需省略', () async {
      final t = ScriptedRpcTransport();
      t.enqueue(<String, Object?>{'acks': <Object?>[], 'rejections': <Object?>[]});
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );

      await backend.push([
        entryOp(
          payload: <String, Object?>{
            'id': 'row-1',
            'title': '午餐',
            'hlc': hlcOf(kBaseMs, 1),
            'schema_ver': 1,
          },
          baseRevision: 7,
        ),
        entryOp(
          outboxId: 'ob-2',
          rowId: 'row-2',
          op: domain.OutboxOp.delete,
          hlc: hlcOf(kBaseMs, 2),
        ),
      ], deviceId: kDev);

      expect(t.calls, hasLength(1));
      final call = t.calls.single;
      expect(call.fnName, 'push_batch');
      expect(call.params['p_device_id'], kDev);
      final ops = call.params['p_ops']! as List<Object?>;
      expect(ops, hasLength(2));
      final op1 = ops[0]! as Map<String, Object?>;
      // payload 由 JSON 字符串解包为内嵌 jsonb 对象（§5.6⑯ 线协议）。
      expect(op1['payload'], <String, Object?>{
        'id': 'row-1',
        'title': '午餐',
        'hlc': hlcOf(kBaseMs, 1),
        'schema_ver': 1,
      });
      expect(op1['outbox_id'], 'ob-1');
      expect(op1['table_name'], 'entries');
      expect(op1['row_id'], 'row-1');
      expect(op1['op'], 'upsert');
      expect(op1['hlc'], hlcOf(kBaseMs, 1));
      expect(op1['base_revision'], 7);
      final op2 = ops[1]! as Map<String, Object?>;
      expect(op2['op'], 'delete');
      expect(op2.containsKey('base_revision'), isFalse);
    });

    test('push payload 非法 JSON：协议异常、不出传输层', () async {
      final t = ScriptedRpcTransport();
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );

      await expectLater(
        backend.push([
          domain.OutboxEntry(
            id: 'ob-bad',
            tableName: 'entries',
            rowId: 'row-x',
            op: domain.OutboxOp.upsert,
            payload: '{not-json',
            hlc: hlcOf(kBaseMs, 1),
            createdAt: kBaseMs,
          ),
        ], deviceId: kDev),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
      expect(t.calls, isEmpty);
    });
  });

  group('② 线协议：响应解析与六类 reason 映射（rejections 三分类）', () {
    Future<domain.SyncPushResult> pushOnce(
      ScriptedRpcTransport t, {
      required Object? body,
    }) {
      t.enqueue(body);
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );
      return backend.push([entryOp()], deviceId: kDev);
    }

    test('成功解析：acks 回执字段逐项落位', () async {
      final t = ScriptedRpcTransport();
      final result = await pushOnce(
        t,
        body: <String, Object?>{
          'acks': <Object?>[
            <String, Object?>{
              'outbox_id': 'ob-1',
              'revision': 3,
              'acked_at': 999,
            },
          ],
          'rejections': <Object?>[],
        },
      );
      expect(result.acks, hasLength(1));
      expect(result.acks.single.outboxId, 'ob-1');
      expect(result.acks.single.revision, 3);
      expect(result.acks.single.ackedAt, 999);
      expect(result.rejections, isEmpty);
    });

    test('六类 wire reason → 引擎枚举映射（§6.2 校验清单）', () async {
      final cases = <String, domain.SyncRejectionReason>{
        'schema_ver': domain.SyncRejectionReason.schemaVerRejected,
        'row_missing': domain.SyncRejectionReason.rowMissing,
        'hlc_non_monotonic': domain.SyncRejectionReason.hlcNonMonotonic,
        'base_revision_conflict':
            domain.SyncRejectionReason.baseRevisionConflict,
        'tombstone_conflict': domain.SyncRejectionReason.tombstoneConflict,
        'unknown': domain.SyncRejectionReason.unknown,
      };
      for (final entry in cases.entries) {
        final t = ScriptedRpcTransport();
        final result = await pushOnce(
          t,
          body: <String, Object?>{
            'acks': <Object?>[],
            'rejections': <Object?>[
              <String, Object?>{
                'outbox_id': 'ob-1',
                'reason': entry.key,
                'message': 'm',
              },
            ],
          },
        );
        expect(result.rejections, hasLength(1), reason: 'wire=${entry.key}');
        expect(result.rejections.single.outboxId, 'ob-1');
        expect(result.rejections.single.reason, entry.value,
            reason: 'wire=${entry.key}');
      }
    });

    test('未知 wire reason 前向兼容 → unknown（§6.4，引擎保守重试）', () async {
      final t = ScriptedRpcTransport();
      final result = await pushOnce(
        t,
        body: <String, Object?>{
          'acks': <Object?>[],
          'rejections': <Object?>[
            <String, Object?>{
              'outbox_id': 'ob-1',
              'reason': 'future_reason',
              'message': 'm',
            },
          ],
        },
      );
      expect(result.rejections.single.reason,
          domain.SyncRejectionReason.unknown);
    });

    test('畸形响应 → protocol：缺 acks 键 / revision 非整数 / 响应非对象', () async {
      final t = ScriptedRpcTransport();
      await expectLater(
        pushOnce(t, body: <String, Object?>{'rejections': <Object?>[]}),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );

      final t2 = ScriptedRpcTransport();
      await expectLater(
        pushOnce(
          t2,
          body: <String, Object?>{
            'acks': <Object?>[
              <String, Object?>{
                'outbox_id': 'ob-1',
                'revision': '3', // 非整数
                'acked_at': 999,
              },
            ],
            'rejections': <Object?>[],
          },
        ),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );

      final t3 = ScriptedRpcTransport();
      await expectLater(
        pushOnce(t3, body: <Object?>['not', 'an', 'object']),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });
  });

  group('③ 线协议：pull 响应解析（变更/游标/has_more）', () {
    Future<domain.SyncPullResult> pullOnce(
      ScriptedRpcTransport t, {
      required Object? body,
    }) {
      t.enqueue(body);
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );
      return backend.pull(<String, String>{'entries': 'h0'},
          deviceId: kDev);
    }

    test('成功解析：op upsert/delete、payload 行快照、游标、has_more', () async {
      final t = ScriptedRpcTransport();
      final result = await pullOnce(
        t,
        body: <String, Object?>{
          'changes': <Object?>[
            <String, Object?>{
              'table_name': 'entries',
              'row_id': 'e1',
              'op': 'upsert',
              'row': <String, Object?>{'id': 'e1', 'title': 't'},
              'hlc': hlcOf(kBaseMs + 1, 0),
              'revision': 2,
              'schema_ver': 1,
            },
            <String, Object?>{
              'table_name': 'entries',
              'row_id': 'e2',
              'op': 'delete',
              'row': <String, Object?>{'id': 'e2', 'deleted_at': 5},
              'hlc': hlcOf(kBaseMs + 2, 0),
              'revision': 3,
              'schema_ver': 1,
            },
          ],
          'cursors': <String, Object?>{'entries': hlcOf(kBaseMs + 2, 0)},
          'has_more': false,
        },
      );
      expect(result.changes, hasLength(2));
      expect(result.changes[0].tableName, 'entries');
      expect(result.changes[0].rowId, 'e1');
      expect(result.changes[0].op, domain.OutboxOp.upsert);
      expect(
        jsonDecode(result.changes[0].payload),
        <String, Object?>{'id': 'e1', 'title': 't'},
      );
      expect(result.changes[1].op, domain.OutboxOp.delete);
      expect(result.changes[1].revision, 3);
      expect(result.nextCursors,
          <String, String>{'entries': hlcOf(kBaseMs + 2, 0)});
      expect(result.hasMore, isFalse);
      // 请求形状：p_cursors 透传客户端游标（§6.2 per-table 增量）。
      expect(t.calls.single.fnName, 'pull_changes');
      expect(t.calls.single.params['p_cursors'],
          <String, String>{'entries': 'h0'});
      expect(t.calls.single.params['p_device_id'], kDev);
    });

    test('畸形响应 → protocol：未知 op / has_more 缺失 / 游标值非文本', () async {
      final t = ScriptedRpcTransport();
      await expectLater(
        pullOnce(
          t,
          body: <String, Object?>{
            'changes': <Object?>[
              <String, Object?>{
                'table_name': 'entries',
                'row_id': 'e1',
                'op': 'future-op',
                'row': <String, Object?>{'id': 'e1'},
                'hlc': hlcOf(kBaseMs, 0),
                'revision': 1,
                'schema_ver': 1,
              },
            ],
            'cursors': <String, Object?>{},
            'has_more': false,
          },
        ),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );

      final t2 = ScriptedRpcTransport();
      await expectLater(
        pullOnce(
          t2,
          body: <String, Object?>{
            'changes': <Object?>[],
            'cursors': <String, Object?>{},
            // 缺 has_more
          },
        ),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );

      final t3 = ScriptedRpcTransport();
      await expectLater(
        pullOnce(
          t3,
          body: <String, Object?>{
            'changes': <Object?>[],
            'cursors': <String, Object?>{'entries': 42}, // 游标必须文本
            'has_more': false,
          },
        ),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });
  });

  group('④ 线协议：fetchRow 与 registerDevice', () {
    test('fetchRow：存活行 → upsert；墓碑行 → delete；缺失 → null', () async {
      final t = ScriptedRpcTransport();
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );

      t.enqueueRow(<String, Object?>{
        'id': 'e1',
        'hlc': hlcOf(kBaseMs, 1),
        'revision': 4,
        'schema_ver': 1,
        'deleted_at': null,
        'title': '现值',
      });
      final alive = await backend.fetchRow(tableName: 'entries', rowId: 'e1');
      expect(alive, isNotNull);
      expect(alive!.op, domain.OutboxOp.upsert);
      expect(alive.revision, 4);
      expect(alive.hlc, hlcOf(kBaseMs, 1));

      t.enqueueRow(<String, Object?>{
        'id': 'e1',
        'hlc': hlcOf(kBaseMs, 2),
        'revision': 5,
        'deleted_at': 777,
      });
      final tomb = await backend.fetchRow(tableName: 'entries', rowId: 'e1');
      expect(tomb!.op, domain.OutboxOp.delete);

      t.enqueueRow(null);
      expect(
        await backend.fetchRow(tableName: 'entries', rowId: 'gone'),
        isNull,
      );
      expect(t.rowCalls, hasLength(3));
      expect(t.rowCalls.first.tableName, 'entries');
      expect(t.rowCalls.first.rowId, 'e1');
    });

    test('fetchRow 缺定宽 hlc → protocol（§5.1 公共列）', () async {
      final t = ScriptedRpcTransport();
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );
      t.enqueueRow(<String, Object?>{'id': 'e1', 'revision': 1});
      await expectLater(
        backend.fetchRow(tableName: 'entries', rowId: 'e1'),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });

    test('registerDevice：请求形状 p_device_id/p_name/p_platform/p_created_at',
        () async {
      final t = ScriptedRpcTransport();
      t.enqueue(<String, Object?>{
        'device': <String, Object?>{'id': kDev, 'platform': 'windows'},
        'server_now': 5,
      });
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: t,
      );
      await backend.registerDevice(
        const DeviceRegistration(
          id: kDev,
          name: '台式机',
          platform: 'windows',
          createdAt: kBaseMs,
        ),
        deviceId: kDev,
      );
      final call = t.calls.single;
      expect(call.fnName, 'register_device');
      expect(call.params['p_device_id'], kDev);
      expect(call.params['p_name'], '台式机');
      expect(call.params['p_platform'], 'windows');
      expect(call.params['p_created_at'], kBaseMs);
    });
  });

  group('⑤ 真实传输栈：SupabaseRpcTransport × FakeHttpTransport（异常三分类）',
      () {
    SupabaseRpcTransport buildTransport(FakeHttpTransport http) {
      return SupabaseRpcTransport(
        config: SyncConfig(
          url: 'https://fake.supabase.co',
          anonKey: 'anon-key',
          timeout: const Duration(milliseconds: 80),
        ),
        client: SupabaseClient(
          'https://fake.supabase.co',
          'anon-key',
          httpClient: http,
        ),
      );
    }

    test('rpc 成功：POST /rest/v1/rpc/<fn>、apikey 头、jsonb 解码', () async {
      final http = FakeHttpTransport();
      http.enqueueJson(<String, Object?>{'acks': <Object?>[]});
      final transport = buildTransport(http);

      final result = await transport.call('push_batch', <String, Object?>{
        'p_device_id': kDev,
        'p_ops': <Object?>[],
      });
      expect(result, <String, Object?>{'acks': <Object?>[]});

      final req = http.requests.single;
      expect(req.method, 'POST');
      expect(req.url.toString(),
          'https://fake.supabase.co/rest/v1/rpc/push_batch');
      expect(req.headers['apikey'], 'anon-key');
      expect(req.headers['Content-Type'], 'application/json');
    });

    test('PostgrestException（服务端 RAISE）→ protocol', () async {
      final http = FakeHttpTransport();
      http.enqueuePostgrestError('push_batch 需要已登录用户', code: 'P0001');
      final transport = buildTransport(http);

      await expectLater(
        transport.call('push_batch', <String, Object?>{}),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol')
              .having(
                (e) => e.message,
                'message',
                contains('push_batch 需要已登录用户'),
              ),
        ),
      );
    });

    test('ClientException（连接类失败）→ network（§6.1 可重试）', () async {
      final http = FakeHttpTransport();
      http.script.add(http_pkg.ClientException('连接被拒'));
      final transport = buildTransport(http);

      await expectLater(
        transport.call('push_batch', <String, Object?>{}),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'network'),
        ),
      );
    });

    test('响应超时 → timeout（§6.1 原则 1：同步失败永不阻塞）', () async {
      final http = FakeHttpTransport();
      http.script.add(hangForever);
      final transport = buildTransport(http);

      await expectLater(
        transport.call('pull_changes', <String, Object?>{}),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'timeout'),
        ),
      );
    });

    test('readRow：GET /rest/v1/<table>?id=eq.、空结果 → null、400 → protocol',
        () async {
      final http = FakeHttpTransport();
      http.enqueueJson(<Object?>[
        <String, Object?>{'id': 'e1', 'hlc': hlcOf(kBaseMs, 1)},
      ]);
      final transport = buildTransport(http);

      final row = await transport.readRow('entries', 'e1');
      expect(row, <String, Object?>{'id': 'e1', 'hlc': hlcOf(kBaseMs, 1)});
      final req = http.requests.single;
      expect(req.method, 'GET');
      expect(
        req.url.toString(),
        'https://fake.supabase.co/rest/v1/entries?select=%2A&id=eq.e1&limit=1',
      );

      http.enqueueJson(<Object?>[]);
      expect(await transport.readRow('entries', 'gone'), isNull);

      http.enqueuePostgrestError('permission denied', code: '42501');
      await expectLater(
        transport.readRow('entries', 'e1'),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });
  });

  group('⑥ 服务端幂等线级契约（FakeSupabaseRpcServer × 同一 backend）', () {
    test('幂等键 = outbox.id：重放原回执、revision 不再签发（§5.6⑯/§6.2）', () async {
      var now = kBaseMs;
      final server = FakeSupabaseRpcServer(nowMs: () => now);
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: server,
      );

      final op = entryOp(
        payload: <String, Object?>{
          'id': 'row-1',
          'title': '首版',
          'hlc': hlcOf(kBaseMs, 1),
          'created_at': kBaseMs,
          'updated_at': kBaseMs,
          'deleted_at': null,
          'revision': 0,
          'schema_ver': 1,
          'device_id': kDev,
        },
        hlc: hlcOf(kBaseMs, 1),
      );

      final first = await backend.push([op], deviceId: kDev);
      expect(first.acks.single.revision, 1);
      expect(server.serverRow('entries', 'row-1')!['revision'], 1);
      expect(server.serverRow('entries', 'row-1')!['title'], '首版');

      // 同 outbox_id 重试（网络重发场景）：原回执重放，不重复入账。
      final retry = await backend.push([op], deviceId: kDev);
      expect(retry.acks.single.revision, 1);
      expect(server.serverRow('entries', 'row-1')!['revision'], 1);
      expect(server.rpcLog.where((n) => n == 'push_batch'), hasLength(2));

      // 不同 outbox_id 同行写入（hlc 须严格递增）：签发下一个 op_seq。
      now = kBaseMs + 10;
      final second = await backend.push([
        entryOp(
          outboxId: 'ob-2',
          payload: <String, Object?>{
            'id': 'row-1',
            'title': '二版',
            'hlc': hlcOf(kBaseMs + 10, 1),
            'created_at': kBaseMs,
            'updated_at': kBaseMs + 10,
            'deleted_at': null,
            'revision': 1,
            'schema_ver': 1,
            'device_id': kDev,
          },
          baseRevision: 1,
          hlc: hlcOf(kBaseMs + 10, 1),
        ),
      ], deviceId: kDev);
      expect(second.acks.single.revision, 2);
      expect(server.serverRow('entries', 'row-1')!['title'], '二版');
    });

    test('未登录：全部 RPC → protocol（RLS 语义，§6.2）', () async {
      final server = FakeSupabaseRpcServer(uid: null, nowMs: () => kBaseMs);
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: server,
      );
      await expectLater(
        backend.push([entryOp()], deviceId: kDev),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });

    test('已吊销设备：push/pull → protocol（§5.6⑰ 服务端半边）', () async {
      final server = FakeSupabaseRpcServer(nowMs: () => kBaseMs);
      final backend = SupabaseSyncBackend(
        config: SyncConfig(url: 'https://fake.supabase.co', anonKey: 'k'),
        transport: server,
      );
      await backend.registerDevice(
        const DeviceRegistration(
          id: kDev,
          name: 'n',
          platform: 'windows',
          createdAt: kBaseMs,
        ),
        deviceId: kDev,
      );
      server.revokeDevice(kDev);

      await expectLater(
        backend.push([entryOp()], deviceId: kDev),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
      await expectLater(
        backend.pull(const <String, String>{}, deviceId: kDev),
        throwsA(
          isA<SyncBackendException>()
              .having((e) => e.code, 'code', 'protocol'),
        ),
      );
    });
  });
}
