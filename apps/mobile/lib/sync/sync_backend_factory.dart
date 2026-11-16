/// 同步后端装配工厂（§10.4 壳负责装配、§11.1 W7-8「托管 Supabase 接入」）。
///
/// 装配策略（任务口径 + SyncConfig 文档「宿主 bootstrap 从自己的配置源注入，
/// 同步层不读环境变量」）：
/// - dart-define 同时给出 SLIMCA_SUPABASE_URL + SLIMCA_SUPABASE_ANON_KEY →
///   [SupabaseSyncBackend]（feature_sync 的托管实现，§6.2 三个 RPC）；
/// - 任一缺失（用户尚未提供 Supabase 项目凭据的缺省态）→
///   [LocalLoopbackBackend]（本地回环，§6.1 本地优先，功能不受影响）。
///
/// **待用户凭据**：真实端点联调在用户提供项目 URL/anon key 后自然激活——
/// 无需改代码，仅 `--dart-define` 注入；settings 页展示当前装配描述。
///
/// 测试：可显式传 [createSyncBackend] 参数绕过 dart-define（const 只读），
/// 契约测试注入 mock transport（禁真实网络，§6.7）。
library;

import 'package:feature_sync/feature_sync.dart';

/// dart-define 键（W7-8 任务口径；凭据由用户在构建/运行时注入）。
const String kSlimcaSupabaseUrlDefine = 'SLIMCA_SUPABASE_URL';
const String kSlimcaSupabaseAnonKeyDefine = 'SLIMCA_SUPABASE_ANON_KEY';

/// dart-define 注入的连接参数（const 读取，AOT 常量折叠）。
const String kSlimcaSupabaseUrl = String.fromEnvironment(
  kSlimcaSupabaseUrlDefine,
);
const String kSlimcaSupabaseAnonKey = String.fromEnvironment(
  kSlimcaSupabaseAnonKeyDefine,
);

/// 当前同步装配的面向用户描述（settings 页状态行）。
String describeSyncBackend({String? supabaseUrl, String? anonKey}) {
  final url = supabaseUrl ?? kSlimcaSupabaseUrl;
  final key = anonKey ?? kSlimcaSupabaseAnonKey;
  if (url.isNotEmpty && key.isNotEmpty) {
    return 'Supabase 托管（端点已配置 · 真实联调待用户凭据验证）';
  }
  return '本地回环（缺省 · 服务端待用户凭据）';
}

/// 是否具备托管装配条件（URL + anon key 均非空）。
bool hasSupabaseConfig({String? supabaseUrl, String? anonKey}) {
  final url = supabaseUrl ?? kSlimcaSupabaseUrl;
  final key = anonKey ?? kSlimcaSupabaseAnonKey;
  return url.isNotEmpty && key.isNotEmpty;
}

/// 构建同步后端（§10.4）：凭据齐 → 托管 Supabase；缺 → 本地回环兜底。
///
/// [transport] 仅供测试注入 mock（禁真实网络，§6.7）；生产路径缺省由
/// SupabaseSyncBackend 自建 SupabaseRpcTransport。
SyncBackend createSyncBackend({
  String? supabaseUrl,
  String? anonKey,
  SyncRpcTransport? transport,
}) {
  final url = supabaseUrl ?? kSlimcaSupabaseUrl;
  final key = anonKey ?? kSlimcaSupabaseAnonKey;
  if (url.isEmpty || key.isEmpty) {
    return LocalLoopbackBackend();
  }
  return SupabaseSyncBackend(
    config: SyncConfig(url: url, anonKey: key),
    transport: transport,
  );
}
