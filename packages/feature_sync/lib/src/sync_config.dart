/// SyncConfig — 托管 Supabase 连接配置（W7-8，§11.1「托管 Supabase 接入」、
/// §6.2「服务端：托管 Supabase（Postgres + Auth + RPC）」）。
///
/// 装配契约（§10.4 壳负责装配）：宿主 bootstrap 从自己的配置源注入本对象，
/// 同步层不读环境变量/不内置凭据——用户尚未提供 Supabase 项目凭据，真实端点
/// 联调「待用户凭据」；测试注入 mock transport，不构造真实连接（§6.7）。
library;

/// 托管（或自托管 P2 docker-compose，§3.7）Supabase 项目连接参数。
class SyncConfig {
  /// 项目根 URL，形如 `https://<project-ref>.supabase.co`（自托管为自建域）。
  final String url;

  /// anon/publishable key（客户端侧公钥；RLS 保证行级隔离，§6.2）。
  final String anonKey;

  /// 附加默认请求头（可选；透传给 SupabaseClient）。
  final Map<String, String> headers;

  /// 单次 RPC 的超时上限（§6.1 原则 1：同步失败永不阻塞 UI）。
  final Duration timeout;

  const SyncConfig({
    required this.url,
    required this.anonKey,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
  });
}
