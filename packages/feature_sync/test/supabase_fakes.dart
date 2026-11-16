/// W7-8 契约测试替身（§6.7「测试策略」：单元/契约测试禁止真实网络）。
///
/// 三个层次（由内到外）：
/// - [ScriptedRpcTransport]：脚本化回放——按入队顺序返回响应或抛异常，
///   供 [SupabaseSyncBackend] 的解析/守卫契约测试（响应结构与六类 reason
///   映射、畸形响应→protocol）；
/// - [FakeSupabaseRpcServer]：线级服务端模拟——按 `0002_sync_rpc.sql` 的
///   三个 RPC 语义逐条镜像（幂等重放 / 校验清单 / todos set 胜合并 /
///   水位+游标双轨 pull / 设备注册），供 SupabaseSyncBackend +
///   [LocalSyncEngine] 全链路轨道（与 InMemory 轨道同夹具双轨对照）；
/// - [FakeHttpTransport]：package:http 层脚本——供 [SupabaseRpcTransport]
///   的真实传输栈测试（rpc 参数编码、PostgrestException→protocol、
///   ClientException→network、TimeoutException→timeout），注入
///   `SupabaseClient(httpClient: …)`，全程不出网。
library;

import 'dart:async';
import 'dart:convert';

import 'package:core_domain/core_domain.dart' as domain;
import 'package:http/http.dart' as http;

import 'package:feature_sync/feature_sync.dart';

// ═══════════════════════════════════════════════════════════════════════════
// 一、脚本化传输（响应结构/解析契约）
// ═══════════════════════════════════════════════════════════════════════════

/// 脚本化 [SyncRpcTransport]：call/readRow 按入队顺序消费脚本项——
/// 非 [Exception] 原样作为响应返回，[Exception] 原样抛出（模拟
/// [SupabaseRpcTransport] 映射后的网络/超时/协议错，§6.7 mock seam）。
class ScriptedRpcTransport implements SyncRpcTransport {
  // W7-8 集成注：脚本项可空——readRow 的「行不存在」脚本即 null（§5.6⑰）。
  final List<Object?> _script = [];
  final List<Object?> _rowScript = [];

  /// 已发生的 RPC 调用记录（fnName + 原始参数，线协议形状断言用）。
  final List<({String fnName, Map<String, Object?> params})> calls = [];

  /// 已发生的单行直读记录。
  final List<({String tableName, String rowId})> rowCalls = [];

  /// 入队一次 call 的响应或异常（按序消费）。
  void enqueue(Object? responseOrError) => _script.add(responseOrError);

  /// 入队一次 readRow 的响应或异常（按序消费）。
  void enqueueRow(Object? responseOrError) => _rowScript.add(responseOrError);

  @override
  Future<Object?> call(String fnName, Map<String, Object?> params) async {
    calls.add((fnName: fnName, params: params));
    if (_script.isEmpty) {
      throw StateError('ScriptedRpcTransport 脚本耗尽：$fnName');
    }
    final item = _script.removeAt(0);
    if (item is Exception) {
      throw item;
    }
    return item;
  }

  @override
  Future<Object?> readRow(String tableName, String rowId) async {
    rowCalls.add((tableName: tableName, rowId: rowId));
    if (_rowScript.isEmpty) {
      throw StateError('ScriptedRpcTransport 行脚本耗尽：$tableName/$rowId');
    }
    final item = _rowScript.removeAt(0);
    if (item is Exception) {
      throw item;
    }
    return item;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 二、线级服务端模拟（0002_sync_rpc.sql 的 Dart 镜像）
// ═══════════════════════════════════════════════════════════════════════════

/// `0002_sync_rpc.sql` 三个 RPC 的线级模拟（jsonb 进/出，键名与 SQL 一致）。
///
/// 语义逐条镜像 SQL（§6.2/§6.5/§5.6⑯⑰）：
/// - push：结构→白名单→schema_ver→幂等重放→hlc 严格递增→todos set 胜
///   合并→baseRevision→墓碑拒绝复活→父行存在→跨用户 id 占用→签发 op_seq
///   + 合并行 upsert（existing || payload || overlay）；
/// - pull：`(hlc > cursor OR revision > watermark)` 双轨资格、表序
///   rank,table_name、表内 revision 升序、全局行预算、水位 GREATEST 单调、
///   预算耗尽保守 has_more=true；
/// - register：幂等注册=刷新 last_seen，revoked_at 永不复活。
///
/// 与 SQL 的已知刻意差异（均为测试等价性说明，非语义分歧）：
/// - 行存储为 Dart Map（jsonb 的内存形态），深拷贝边界用浅拷贝（行值全为标量）；
/// - hlc 单调用 [domain.Hlc.parse] 分段比较（SQL split_part 等价）；
/// - 多用户模拟仅覆盖「跨用户 id 占用」拦截（[seedForeignRow] 种子行，
///   RLS 语义：读不见、写拦截）。
class FakeSupabaseRpcServer implements SyncRpcTransport {
  /// 构造：[uid] 为 auth.uid() 模拟（null=未登录，全部 RPC 拒绝）；
  /// [nowMs] 服务端墙钟（确定性测试注入）；[maxPullRows] 单轮 pull 上限
  /// （SQL clamp 1..500 的缺省 200）。
  FakeSupabaseRpcServer({
    this.uid = '00000000-0000-0000-0000-000000000001',
    required int Function() nowMs,
    this.maxPullRows = 200,
  }) : _nowMs = nowMs;

  final String? uid;
  final int Function() _nowMs;
  final int maxPullRows;

  int _nextOpSeq = 1;

  /// sync_ops 幂等键 → op_seq（§6.2 幂等键 = outbox.id）。
  final Map<String, int> _opSeqByOutbox = {};

  /// 业务行真值：表 → 行 id → 行快照（含 user_id/revision 等服务端列）。
  final Map<String, Map<String, Map<String, Object?>>> _tables = {};

  /// 他端用户同 id 行（RLS 对侧：读不可见、写触发占用拦截，决策 A）。
  final Map<String, Set<String>> _foreignRowIds = {};

  /// sync_pull_watermarks：'$deviceId|$table' → last_op_seq。
  final Map<String, int> _watermarks = {};

  /// devices 表：id → 行快照（§5.6⑰）。
  final Map<String, Map<String, Object?>> _devices = {};

  /// 传输层故障注入：非空时下一次 call 弹出并抛出（模拟断网/超时——
  /// 服务端不可达时 Postgrest 层抛错，客户端映射为 SyncBackendException）。
  final List<Object> faults = [];

  /// 已发生的 RPC 函数名序（链路顺序断言用）。
  final List<String> rpcLog = [];

  // ── 服务端状态观察/种子（断言与场景布置用）────────────────────────────

  /// 服务端某行现值（含 user_id；不存在返回 null）。
  Map<String, Object?>? serverRow(String table, String id) {
    final row = _tables[table]?[id];
    return row == null ? null : Map<String, Object?>.of(row);
  }

  /// 种子一条他端用户同 id 行（跨用户占用拦截场景，决策 A）。
  void seedForeignRow(String table, String id) {
    (_foreignRowIds[table] ??= <String>{}).add(id);
  }

  /// 一键下线（§5.6⑰ revoked_at；服务端半边拒绝 push/pull）。
  void revokeDevice(String deviceId) {
    final row = _devices[deviceId];
    if (row != null) {
      row['revoked_at'] = _nowMs();
    }
  }

  bool deviceRegistered(String deviceId) => _devices.containsKey(deviceId);

  // ── SyncRpcTransport ═══════════════════════════════════════════════════

  @override
  Future<Object?> call(String fnName, Map<String, Object?> params) async {
    rpcLog.add(fnName);
    if (uid == null) {
      throw SyncBackendException('protocol', '42501: 需要已登录用户（§6.2）');
    }
    if (faults.isNotEmpty) {
      final fault = faults.removeAt(0);
      if (fault is Exception) {
        throw fault;
      }
      throw SyncBackendException('$fault', '注入的传输层故障');
    }
    switch (fnName) {
      case SupabaseSyncBackend.pushRpcName:
        return _push(params);
      case SupabaseSyncBackend.pullRpcName:
        return _pull(params);
      case SupabaseSyncBackend.registerRpcName:
        return _register(params);
      default:
        throw SyncBackendException('protocol', '未知 RPC：$fnName');
    }
  }

  @override
  Future<Object?> readRow(String tableName, String rowId) async {
    // REST 单行直读（RLS 按登录用户过滤）：他端用户行不可见（决策 A）。
    if (_foreignRowIds[tableName]?.contains(rowId) ?? false) {
      return null;
    }
    final row = _tables[tableName]?[rowId];
    return row == null ? null : Map<String, Object?>.of(row);
  }

  // ── push_batch（SQL ④ 镜像）════════════════════════════════════════════

  Object _push(Map<String, Object?> params) {
    final deviceId = params['p_device_id'] as String?;
    final ops = params['p_ops'];
    if (deviceId == null || deviceId.isEmpty) {
      throw SyncBackendException('protocol', '22023: 缺少 device_id（§6.3）');
    }
    if (_devices[deviceId]?['revoked_at'] != null) {
      throw SyncBackendException('protocol', '42501: 设备已被吊销（§5.6⑰）');
    }
    if (ops is! List) {
      throw SyncBackendException('protocol', '22023: p_ops 必须是数组');
    }

    final acks = <Object?>[];
    final rejections = <Object?>[];
    final ackedAt = _nowMs();

    void reject(String outboxId, String reason, String message) {
      rejections.add(<String, Object?>{
        'outbox_id': outboxId,
        'reason': reason,
        'message': message,
      });
    }

    void ack(String outboxId, int revision) {
      acks.add(<String, Object?>{
        'outbox_id': outboxId,
        'revision': revision,
        'acked_at': ackedAt,
      });
    }

    for (final raw in ops) {
      final op = raw as Map;
      final outboxId = op['outbox_id'] as String?;
      final table = op['table_name'] as String?;
      final rowId = op['row_id'] as String?;
      final opKind = op['op'] as String?;
      final payload = op['payload'];
      final hlc = op['hlc'] as String?;
      final baseRevRaw = op['base_revision'];
      final baseRev = baseRevRaw is int ? baseRevRaw : null;

      // ① 结构校验（SQL ① 镜像：unknown）。
      if (outboxId == null ||
          table == null ||
          rowId == null ||
          opKind == null ||
          hlc == null ||
          payload is! Map ||
          (opKind != 'upsert' && opKind != 'delete') ||
          !RegExp(r'^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$').hasMatch(hlc) ||
          (baseRevRaw != null && baseRevRaw is! int) ||
          (payload['schema_ver'] != null && payload['schema_ver'] is! int) ||
          payload['id'] != rowId ||
          payload['hlc'] != hlc) {
        reject(
          outboxId ?? '',
          'unknown',
          'op 结构非法（§5.6⑯）',
        );
        continue;
      }

      // ② 表白名单（§5.1 冻结表集）。
      SyncTableSpec spec;
      try {
        spec = syncTableSpec(table);
      } on ArgumentError {
        reject(outboxId, 'unknown', '未知同步表 $table（§5.1）');
        continue;
      }

      // ③ schema_ver 超档（§6.4）。
      final schemaVer = payload['schema_ver'] as int?;
      if (schemaVer != null && schemaVer > domain.kCurrentSchemaVer) {
        reject(outboxId, 'schema_ver', 'schema_ver 超出服务端当前档（§6.4）');
        continue;
      }

      // ④ 幂等重放（§6.2 幂等键 = outbox.id；拒绝不缓存）。
      final replay = _opSeqByOutbox[outboxId];
      if (replay != null) {
        ack(outboxId, replay);
        continue;
      }

      // 校验区（只读）：行锁读现值（单用户模拟；他端行不构成「现有」）。
      final existing = _tables[table]?[rowId];
      final found = existing != null;
      var todoMerge = false;

      if (found) {
        // ⑤ hlc 严格递增（§6.3 定宽段位比较）。
        final incoming = domain.Hlc.parse(hlc);
        final current = domain.Hlc.parse(existing['hlc'] as String);
        final monotonic = incoming.physicalMs > current.physicalMs ||
            (incoming.physicalMs == current.physicalMs &&
                incoming.counter > current.counter);
        if (!monotonic) {
          reject(outboxId, 'hlc_non_monotonic', 'hlc 单调校验失败（§6.2/§6.3）');
          continue;
        }

        // ⑥ todos set 胜合并判据（§6.5 第 6 行：并发 unset 保留 done_at）。
        todoMerge = table == 'todos' &&
            opKind == 'upsert' &&
            existing['done_at'] != null &&
            payload['done_at'] == null &&
            (baseRev == null || baseRev != (existing['revision'] as int));

        // ⑦ baseRevision 乐观校验（§5.6⑯）。
        if (!todoMerge &&
            baseRev != null &&
            baseRev != (existing['revision'] as int)) {
          reject(
              outboxId, 'base_revision_conflict', 'baseRevision 校验失败（§5.6⑯）');
          continue;
        }

        // ⑧ 墓碑拒绝复活（§6.5 第 7 行）。
        if (existing['deleted_at'] != null &&
            opKind == 'upsert' &&
            payload['deleted_at'] == null) {
          reject(outboxId, 'tombstone_conflict', '墓碑拒绝复活（§6.5）');
          continue;
        }
      }

      // ⑨ 父行存在性（§6.2；corrections 无父检查，§5.6⑮）。
      if (spec.parentTable != null) {
        final parentId = payload[spec.parentKey!] as String?;
        if (parentId != null && _tables[spec.parentTable]?[parentId] == null) {
          reject(outboxId, 'row_missing',
              '父行缺失：${spec.parentTable}/$parentId（§6.2）');
          continue;
        }
      }

      // ⑩ 跨用户 id 占用拦截（决策 A：SECURITY DEFINER 显式属主校验）。
      if (!found && (_foreignRowIds[table]?.contains(rowId) ?? false)) {
        reject(outboxId, 'unknown', 'row id 已被其他用户占用（§6.2 RLS 强化）');
        continue;
      }

      // 写区（SQL ⑪⑫⑬ 镜像）：签发 op_seq + 合并行 upsert + ack；
      // 写区意外失败单条回滚归 unknown（SQL EXCEPTION WHEN OTHERS）。
      try {
        final opSeq = _nextOpSeq++;
        _opSeqByOutbox[outboxId] = opSeq;
        final merged = <String, Object?>{
          ...?existing,
          ...payload.cast<String, Object?>(),
        };
        if (todoMerge) {
          merged['done_at'] = existing!['done_at'];
        }
        // 权威列覆盖（决策 A：服务端签发，不信任客户端）。
        merged['revision'] = opSeq;
        merged['user_id'] = uid;
        merged['device_id'] = deviceId;
        // delete 快照未带墓碑时刻：服务端兜底签发（§5.1 软删）。
        if (opKind == 'delete' && merged['deleted_at'] == null) {
          merged['deleted_at'] = _nowMs();
        }
        // 未知键保留原样以贴近 jsonb 行为（客户端列过滤在落库侧完成，
        // §6.4 老服务端忽略新列的对侧）。
        (_tables[table] ??= <String, Map<String, Object?>>{})[rowId] = merged;
        ack(outboxId, opSeq);
      } on Exception catch (e) {
        _opSeqByOutbox.remove(outboxId);
        reject(outboxId, 'unknown', '$e');
      }
    }

    return <String, Object?>{'acks': acks, 'rejections': rejections};
  }

  // ── pull_changes（SQL ⑤ 镜像）══════════════════════════════════════════

  Object _pull(Map<String, Object?> params) {
    final deviceId = params['p_device_id'] as String?;
    final cursorsIn = (params['p_cursors'] as Map?) ?? const {};
    final limitRaw = params['p_limit'];
    if (deviceId == null || deviceId.isEmpty) {
      throw SyncBackendException('protocol', '22023: 缺少 device_id（§6.3）');
    }
    if (_devices[deviceId]?['revoked_at'] != null) {
      throw SyncBackendException('protocol', '42501: 设备已被吊销（§5.6⑰）');
    }
    final limit = limitRaw is int ? limitRaw : 200;
    var remaining = limit < 1 ? 1 : (limit > 500 ? 500 : limit);

    final changes = <Object?>[];
    final cursorsOut = <String, Object?>{};
    var hasMore = false;

    for (final spec in syncTablesInApplyOrder) {
      if (remaining <= 0) {
        // 预算耗尽：后续表本轮未扫——保守置 has_more（宁可多一轮空拉，
        // 不可丢表，§6.2 分批语义）。
        hasMore = true;
        break;
      }
      final rows = _tables[spec.name];
      if (rows == null || rows.isEmpty) {
        continue;
      }
      final cursor = (cursorsIn[spec.name] as String?) ?? '';
      final wmKey = '$deviceId|${spec.name}';
      final wm = _watermarks[wmKey] ?? 0;

      // 双轨资格（§6.2 游标 + 投递水位补漏，§6.7 双端收敛关键）。
      final qualified = rows.entries
          .where((e) =>
              (e.value['hlc'] as String).compareTo(cursor) > 0 ||
              (e.value['revision'] as int) > wm)
          .map((e) => e.value)
          .toList()
        ..sort((a, b) =>
            (a['revision'] as int).compareTo(b['revision'] as int));
      if (qualified.isEmpty) {
        continue;
      }

      final delivered = qualified.length <= remaining
          ? qualified
          : qualified.sublist(0, remaining);
      if (delivered.length < qualified.length) {
        hasMore = true;
      }
      remaining -= delivered.length;

      var maxHlc = '';
      var maxSeq = 0;
      for (final row in delivered) {
        // 交付行剥离 user_id（SQL `to_jsonb(t) - 'user_id'`）。
        final json = Map<String, Object?>.of(row)..remove('user_id');
        changes.add(<String, Object?>{
          'table_name': spec.name,
          'row_id': json['id'],
          'op': json['deleted_at'] == null ? 'upsert' : 'delete',
          'row': json,
          'hlc': json['hlc'],
          'revision': json['revision'],
          'schema_ver': (json['schema_ver'] as int?) ?? domain.kCurrentSchemaVer,
        });
        final rowHlc = json['hlc'] as String;
        if (rowHlc.compareTo(maxHlc) > 0) {
          maxHlc = rowHlc;
        }
        final rowSeq = json['revision'] as int;
        if (rowSeq > maxSeq) {
          maxSeq = rowSeq;
        }
      }

      // 水位推进（GREATEST 单调：cursor 分支重投的老行不回退水位）。
      _watermarks[wmKey] = wm > maxSeq ? wm : maxSeq;
      // W7-8 集成修复：游标单调（与 0002_sync_rpc.sql 的
      // GREATEST(v_cursor, v_max_hlc) 对齐）——水位补投的低 hlc 迟到行
      // 不得把游标拉回既有游标之下，否则下轮整段重投已投递区间。
      cursorsOut[spec.name] = maxHlc.compareTo(cursor) > 0 ? maxHlc : cursor;
    }

    return <String, Object?>{
      'changes': changes,
      'cursors': cursorsOut,
      'has_more': hasMore,
    };
  }

  // ── register_device（SQL ⑥ 镜像）════════════════════════════════════════

  Object _register(Map<String, Object?> params) {
    final deviceId = params['p_device_id'] as String?;
    final name = params['p_name'] as String?;
    final platform = (params['p_platform'] as String?) ?? 'unknown';
    final createdAt = params['p_created_at'] as int?;
    if (deviceId == null || deviceId.isEmpty) {
      throw SyncBackendException('protocol', '22023: 缺少 device_id（§5.6⑰）');
    }
    final now = _nowMs();
    final existing = _devices[deviceId];
    if (existing != null) {
      // 幂等：刷新 name/platform/last_seen；revoked_at 永不复活。
      if (existing['user_id'] != uid) {
        throw SyncBackendException('protocol', '23505: 设备 id 已被其他用户占用');
      }
      existing['name'] = name;
      existing['platform'] = platform;
      existing['last_seen_at'] = now;
    } else {
      _devices[deviceId] = <String, Object?>{
        'id': deviceId,
        'user_id': uid,
        'name': name,
        'platform': platform,
        'created_at': createdAt ?? now,
        'last_seen_at': now,
        'revoked_at': null,
      };
    }
    return <String, Object?>{
      'device': Map<String, Object?>.of(_devices[deviceId]!)
        ..remove('user_id'),
      'server_now': now,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// 三、http 层脚本（真实传输栈测试）
// ═══════════════════════════════════════════════════════════════════════════

/// 「挂起」哨兵：send 永不返回（超时映射测试；由 [SyncConfig.timeout] 触发
/// TimeoutException，§6.1 原则 1）。
const Object hangForever = _Hang();

class _Hang {
  const _Hang();
}

/// package:http 层脚本客户端：按序返回 [http.StreamedResponse]/抛异常/挂起。
///
/// 注意 `request` 必须回填——supabase/postgrest 解析器读
/// `response.request!.method`（由其自行 `Response.fromStream` 装配），
/// 手工构造的 http.Response 不带 request。
class FakeHttpTransport extends http.BaseClient {
  /// 脚本项：http.Response / Exception / [hangForever]。
  final List<Object> script = [];

  /// 已发出的请求（URL/方法/头/体断言用）。
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    if (script.isEmpty) {
      throw StateError('FakeHttpTransport 脚本耗尽：${request.url}');
    }
    final item = script.removeAt(0);
    if (item is Exception) {
      throw item;
    }
    if (item is _Hang) {
      await Completer<void>().future; // 永不完成（测试由 timeout 唤醒）。
    }
    // W7-8 集成注：直接返回 [http.StreamedResponse]（http.BaseClient.send 的
    // 契约类型）；`request` 必须回填——supabase/postgrest 解析器读
    // `response.request!.method`，由 supabase 层自行 `Response.fromStream`
    // 装配成完整 http.Response。
    final response = item as http.Response;
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      request: request,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// 入队一个 JSON 响应。
  void enqueueJson(Object? body, {int status = 200}) {
    script.add(
      http.Response(
        jsonEncode(body),
        status,
        headers: const {'content-type': 'application/json'},
      ),
    );
  }

  /// 入队一个 PostgREST 风格错误响应（→ PostgrestException → protocol）。
  void enqueuePostgrestError(String message, {String code = 'P0001'}) {
    enqueueJson(<String, Object?>{
      'message': message,
      'code': code,
      'details': null,
      'hint': null,
    }, status: 400);
  }
}
