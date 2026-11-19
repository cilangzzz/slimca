# feature_sync — 同步域（基础层·共享服务）

> 自研同步引擎：local-first（§6.1）+ outbox 批量上送 + per-table 游标增量拉取 + HLC 全序仲裁。
> 契约类型（`OutboxEntry`/`SyncEngine`/`ConflictClass` 等）在 core_domain，本包负责本地编排与后端实现。

## 模块边界

- **职责**：把 core_db 的 14 张同步真值表与远端对端收敛到一致（push/pull/仲裁）；设备注册；无服务端时全功能兜底。
- **不负责**：触发调度（启动/前台切回/15 分钟周期 → 壳层 `SyncCoordinator`，见 `apps/mobile/lib/sync/`）；outbox 同事务入队（业务写路径经 core_db `SyncOutboxWriter`）；Riverpod provider（本包零 provider，装配全在壳 bootstrap）。
- **依赖**：`core_domain`（契约+HlcClock）、`core_db`（AppDatabase/仓库/投影）、`drift`（事务与 custom SQL）、`supabase`（纯 Dart core 包，2.13.x 锁定）、`http`（ClientException 分类）。

## 组件地图

| 组件 | 文件 | 角色 |
|------|------|------|
| `LocalSyncEngine` | `local_sync_engine.dart` | 引擎编排：push 循环 → pull 续拉 → 拒绝分类回处理 → §6.5 矩阵仲裁 → day_summary 自愈 |
| `SyncBackend` / `SyncBackendException` | `sync_backend.dart` | 远端对端抽象（push/pull/fetchRow/registerDevice）+ `DeviceRegistration` |
| `LocalLoopbackBackend` | `local_loopback_backend.dart` | 无服务端缺省装配：push 全量 ack、pull 恒空、fetchRow 恒 null |
| `InMemorySyncBackend` | `in_memory_sync_backend.dart` | 内存模拟远端（测试/开发）：服务端校验清单全实现 + 分区/延迟注入 |
| `SupabaseSyncBackend` | `supabase_sync_backend.dart` | 托管 Supabase RPC 实现（三 RPC + REST 单行直读） |
| `SyncRpcTransport` / `SupabaseRpcTransport` | `supabase_rpc_transport.dart` | 传输缝：异常三分类 network/timeout/protocol |
| `SyncConfig` | `sync_config.dart` | 连接参数（url/anonKey/timeout）——宿主注入，本包不读环境变量 |
| `DeviceRegistry` | `device_registry.dart` | 设备注册：本地 devices 引用行 + 服务端幂等登记 |
| `DriftSyncOutboxStore` | `drift_sync_outbox_store.dart` | sync_outbox 队列实现（enqueue 须在业务事务内调用） |
| `DriftSyncLocalStore` | `drift_sync_local_store.dart` | pull 落库/游标/revision 回写/day_summary 脏自愈 |
| `SyncTableSpec` / `kSyncTables` | `sync_table_catalog.dart` | 14 张真值表的策略登记（冲突类/依赖序/父表/脏日来源） |

## 装配快照（壳 bootstrap 实际接线）

```
createSyncBackend()                    # apps/mobile/lib/sync/sync_backend_factory.dart
  凭据齐 → SupabaseSyncBackend(config)  # SLIMCA_SUPABASE_URL + SLIMCA_SUPABASE_ANON_KEY
  缺失  → LocalLoopbackBackend()
→ TelemetrySyncBackend(inner: …)       # 遥测装饰器（apps/mobile/lib/sync/）
→ LocalSyncEngine(backend, DriftSyncOutboxStore, DriftSyncLocalStore, deviceId, clock)
→ SyncCoordinator(engine, DeviceRegistry)  # start(): 注册 → syncNow → 15min 周期
```

关键纪律：`HlcClock` 单例与 UI 写路径共享（引擎只 `recv` 不 `now`）；`syncOnce` 永不抛出，失败只降级状态回调。

## 详细文档

- [api-sync.md](api-sync.md) — 全部公开 API：Backend/Transport/Engine/Store 接口方法、异常面、backend 切换方式、服务端 RPC 线协议
- [data-model.md](data-model.md) — outbox 行结构、HLC 定宽编码、同步状态机、14 表策略目录、游标与投递水位
- [code-patterns.md](code-patterns.md) — 「新增一个同步实体」四步完整流程 + 引擎调用模式 + 测试替身模式
- [pitfalls.md](pitfalls.md) — LWW/冲突矩阵要点、游标单调、Loopback 缺省语义、凭据切换、幂等缓存规则
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（真实 git 分析，最新在上）
- 契约类型细节：[../core_domain/README.md](../core_domain/README.md)；表 schema 与仓库：[../core_db/README.md](../core_db/README.md)；服务端 SQL：[../server-supabase/README.md](../server-supabase/README.md)

## 测试布局（`test/`）

| 文件 | 覆盖 |
|------|------|
| `local_sync_engine_test.dart` | 冲突四用例 + 双端 50×2 收敛 + 读写路径回归 + resolve 单测 |
| `sync_backend_test.dart` | InMemory 校验矩阵 / pull 语义 / Loopback 缺省 |
| `supabase_contract_test.dart` | 线协议编解码、六类 reason 映射、真实传输栈异常三分类 |
| `supabase_engine_chain_test.dart` | SupabaseSyncBackend × FakeSupabaseRpcServer 全链路 |
| `offline_regression_test.dart` | 分区→离线写→补传收敛；低 hlc 迟到行补漏 |
| `test_support.dart` / `supabase_fakes.dart` | 双设备夹具、Fake 传输/服务器 |
