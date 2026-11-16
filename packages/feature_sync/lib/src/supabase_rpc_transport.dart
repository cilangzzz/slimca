/// SyncRpcTransport — 服务端 RPC 调用传输抽象（W7-8，§6.2 读写路径的传输缝）。
///
/// [SupabaseSyncBackend] 只认本接口，不直接依赖 `SupabaseClient`——契约测试
/// 用 mock transport 注入脚本化响应/网络错/超时，全程禁真实网络（§6.7）；
/// 生产装配由 [SupabaseRpcTransport] 经 supabase 纯 Dart core 包发出真实
/// POST `/rest/v1/rpc/<fn>` 调用（不用 supabase_flutter：同步层不引平台插件，
/// §6.1 本地优先、§10.1 移动端）。
///
/// 异常映射（§6.1 原则 1「同步失败仅顶栏小圆点提示、永不阻塞」）：
/// [SyncBackendException] 的 code 三分类——`network`（连接类失败，可重试）、
/// `timeout`（超时，可重试）、`protocol`（服务端拒绝/协议级失败，含 4xx 与
/// 服务端 RAISE 的约束错误，重试无益需上层处置）。
library;

import 'dart:async';

import 'package:http/http.dart' show ClientException;
import 'package:supabase/supabase.dart';

import 'sync_backend.dart';
import 'sync_config.dart';

/// 服务端 RPC 调用抽象（push_batch / pull_changes / register_device 与
/// 单行直读 fetch_row 源）。
abstract interface class SyncRpcTransport {
  /// 调用一个 Postgres RPC，返回其 jsonb 结果（对象/数组/标量原样透传）。
  /// 传输层失败一律抛 [SyncBackendException]（code 三分类见库注释）。
  Future<Object?> call(String fnName, Map<String, Object?> params);

  /// 按 (表, 行 id) 直读单行现值（RLS 按登录用户过滤，§6.2）；
  /// 行不存在返回 null。供 push 被拒后的「采纳服务端现值」链路使用。
  Future<Object?> readRow(String tableName, String rowId);
}

/// 生产传输：supabase 纯 Dart core 包实现。
class SupabaseRpcTransport implements SyncRpcTransport {
  /// [client] 缺省时按 [config] 构建 SupabaseClient；测试可注入自建实例。
  SupabaseRpcTransport({
    required SyncConfig config,
    SupabaseClient? client,
  })  : _config = config,
        _client = client ??
            SupabaseClient(
              config.url,
              config.anonKey,
              headers: config.headers.isEmpty ? null : config.headers,
            );

  final SyncConfig _config;
  final SupabaseClient _client;

  @override
  Future<Object?> call(String fnName, Map<String, Object?> params) async {
    try {
      return await _client
          .rpc<Object?>(fnName, params: params)
          .timeout(_config.timeout);
    } on TimeoutException catch (e) {
      throw SyncBackendException(
        'timeout',
        'RPC $fnName 超时（上限 ${_config.timeout}）：${e.message ?? ''}',
      );
    } on PostgrestException catch (e) {
      throw SyncBackendException(
        'protocol',
        'RPC $fnName 服务端拒绝：${e.message}（code=${e.code ?? 'n/a'}）',
      );
    } on ClientException catch (e) {
      throw SyncBackendException(
        'network',
        'RPC $fnName 网络不可达：${e.message}',
      );
    } on Exception catch (e) {
      // 其余传输栈异常（TLS/DNS 等）按网络类失败处置（§6.1 可重试）。
      throw SyncBackendException('network', 'RPC $fnName 传输失败：$e');
    }
  }

  @override
  Future<Object?> readRow(String tableName, String rowId) async {
    try {
      final rows = await _client
          .from(tableName)
          .select()
          .eq('id', rowId)
          .limit(1)
          .timeout(_config.timeout);
      return rows.isEmpty ? null : rows.first;
    } on TimeoutException catch (e) {
      throw SyncBackendException(
        'timeout',
        '读行 $tableName/$rowId 超时（上限 ${_config.timeout}）：${e.message ?? ''}',
      );
    } on PostgrestException catch (e) {
      throw SyncBackendException(
        'protocol',
        '读行 $tableName/$rowId 服务端拒绝：${e.message}（code=${e.code ?? 'n/a'}）',
      );
    } on ClientException catch (e) {
      throw SyncBackendException(
        'network',
        '读行 $tableName/$rowId 网络不可达：${e.message}',
      );
    } on Exception catch (e) {
      throw SyncBackendException('network', '读行 $tableName/$rowId 传输失败：$e');
    }
  }
}
