/// Slimca 同步域（§10.4 packages/feature_sync）。
///
/// W5-6 主线（§11.1 W5-6「HLC 时钟+outbox+push/pull 实现；冲突测试集四用例」、
/// §6 同步设计）：
/// - [LocalSyncEngine]：outbox 批量上送（幂等键=outbox.id、baseRevision 乐观
///   校验、拒绝分类回处理，§6.2 写路径）+ per-table 游标增量拉取（§6.2 读路径、
///   §5.6⑱）+ 远端行落库走与本地写同一校验（墓碑拒绝复活、schema_ver 兼容、
///   §6.5/§6.4）+ §6.5 冲突矩阵仲裁（LWW/facet 免冲突/append-only 并集/
///   todo set 胜/墓碑胜）+ day_summary 由 dirty 自愈重算（投影不同步，§6.1
///   原则 3）；
/// - [SyncBackend] 抽象：可整体替换为 PowerSync/CRDT/Supabase RPC 而不动
///   schema（§6.2 评审胜出点）；[InMemorySyncBackend] 内存模拟远端（可注入
///   延迟/分区）、[LocalLoopbackBackend] 本地回环（无服务端缺省装配）；
/// - [DeviceRegistry]：设备注册（devices 表，§5.6⑰）；
/// - [DriftSyncOutboxStore]：sync_outbox 队列实现（§5.6⑯）；
/// - [DriftSyncLocalStore]：pull 落库/游标/revision 回写（§5.6⑱）。
///
/// DI 契约（§10.4 壳负责装配）：AppDatabase + HlcClock（与 UI 写路径共享
/// 同一时钟实例，§6.3）在宿主 bootstrap 注入；本库不建 Riverpod provider
/// ——调度触发（启动即拉/前台切回/15 分钟兜底）属 W7-8 接入 Supabase 时的
/// 壳层编排（§6.2 触发时机）。
library;

export 'src/device_registry.dart';
export 'src/drift_sync_local_store.dart';
export 'src/drift_sync_outbox_store.dart';
export 'src/in_memory_sync_backend.dart';
export 'src/local_loopback_backend.dart';
export 'src/local_sync_engine.dart';
export 'src/sync_backend.dart';
export 'src/sync_table_catalog.dart';
