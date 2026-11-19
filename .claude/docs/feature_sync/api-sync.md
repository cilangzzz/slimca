# api-sync — 同步域 API 表面

> 接口方法 + 调用模式 + backend 切换。契约类型（`OutboxEntry`/`SyncPullCursors`/`SyncRejectionReason`/`ConflictClass`/`HlcClock`）定义在 core_domain，本页只列 feature_sync 侧的实现与扩展面。

## 1. SyncBackend — 远端对端抽象（`sync_backend.dart`）

LocalSyncEngine 只认此接口，backend 可整体替换（Loopback → Supabase → 未来 PowerSync/CRDT）而不动 schema。

| 方法 | 签名 | 语义 |
|------|------|------|
| `push` | `Future<SyncPushResult> push(List<OutboxEntry> batch, {required String deviceId})` | 写路径：服务端校验（schema_ver/hlc 单调/baseRevision/墓碑/父行存在）→ 签发权威 revision → 逐条回执 acks/rejections |
| `pull` | `Future<SyncPullResult> pull(SyncPullCursors since, {required String deviceId})` | 读路径：per-table 游标增量，含墓碑行，hlc 升序；`hasMore=true` 时调用方以 `nextCursors` 续拉 |
| `fetchRow` | `Future<RemoteChange?> fetchRow({required String tableName, required String rowId})` | 读单行现值（push 被拒后的采纳源）；行不存在返回 null |
| `registerDevice` | `Future<void> registerDevice(DeviceRegistration registration, {required String deviceId})` | 设备注册，幂等（重复=刷新 last_seen） |

- `DeviceRegistration`：`id`（12 位定长 hex，=HLC 节点段=device_id）/ `name` / `platform` / `createdAt`，带 `toJson`/`fromJson`。
- `SyncBackendException(code, message)`：唯一异常面。code：`partitioned`（设备分区）、`protocol`（协议级失败，重试无益）、`network`（可重试）、`timeout`（可重试）。调用方（引擎/协调器）捕获后只降级状态，永不阻塞 UI。

## 2. LocalSyncEngine — 引擎编排（`local_sync_engine.dart`）

构造注入：`backend` / `outbox`（`SyncOutboxStore`）/ `store`（`DriftSyncLocalStore`）/ `deviceId` / 可选 `clock`（缺省自建——**生产必须显式传共享实例**）/ `maxOutboxBatchSize=100` / `maxPullRounds=50` / `listener`。

| 方法 | 语义 |
|------|------|
| `push(batch)` | core_domain `SyncEngine` 契约：backend.push → ack 回写 revision/acked_at → 拒绝按原因分类回处理 |
| `pull(since)` | 契约：backend.pull → 按「父表→子表」依赖序落库 → 游标**严格大于才推进** → 远端时间戳并入时钟 → day_summary 自愈 |
| `resolve(conflict)` | §6.5 矩阵仲裁：LWW 各类 / todoDoneForward（set 胜 + done_at 只前进合并）/ tombstone（删除恒胜） |
| `syncOnce({outboxBatchSize, maxPushRounds=10})` | 一轮完整同步：push 循环（全暂缓即终止，绝不自旋）→ pull 续拉（≤maxPullRounds）→ 返回 `SyncCycleReport`。**永不抛出**：分区/断网只写 `report.error` + error 状态回调 |
| `pendingOutboxCount()` | 未确认出网条数（顶栏小圆点数据源） |

状态面：`SyncPhase { idle, pushing, pulling, done, error }`；`SyncStatus(phase, pending, error, at)` 经 `SyncStatusListener` 回调（壳层订阅驱动顶栏小圆点）。

`SyncCycleReport` 字段：`pushed/acked/rejections(Map<reason,int>)/droppedOutbox/pulled/applied/skipped/deferred/cursors/dirtyDates/error`——验收口径全部量化在此。

拒绝分类回处理（push 被拒后引擎自动执行）：

| reason | 处置 |
|--------|------|
| `schemaVerRejected` | 作废（drop）——本端永不理解该行 |
| `rowMissing` + delete | 幂等完成，作废 |
| `rowMissing` + upsert | **暂缓保留**，下轮重试（父行补送后转正） |
| `hlcNonMonotonic` / `baseRevisionConflict` / `tombstoneConflict` | 作废 + **立即 `fetchRow` 采纳服务端现值**（等 pull 会 LWW 惜败永不收敛，详见 [pitfalls.md](pitfalls.md)） |
| `unknown` | 保守重试 |

## 3. SyncRpcTransport — 传输缝（`supabase_rpc_transport.dart`）

| 方法 | 语义 |
|------|------|
| `call(fnName, params)` | 调用 Postgres RPC，jsonb 结果原样透传；失败一律抛 `SyncBackendException` |
| `readRow(tableName, rowId)` | REST 单行直读（RLS 过滤当前用户），行不存在返回 null |

`SupabaseRpcTransport` 异常映射：`TimeoutException` → `timeout`；`PostgrestException`（含服务端 RAISE）→ `protocol`；`http.ClientException` 及其余传输栈异常（TLS/DNS）→ `network`。

用 `supabase` 纯 Dart core 包（非 supabase_flutter）：同步层不依赖平台通道。

## 4. SupabaseSyncBackend — 真实通道（`supabase_sync_backend.dart`）

RPC 函数名常量。**⚠️ 客户端与服务端迁移当前命名错位**（详见 [../server-supabase/pitfalls.md](../server-supabase/pitfalls.md) 第 1 条）：真实端点联调前必须二选一修齐——改客户端常量为带前缀名，或服务端加同名别名函数（两侧 + fakes 镜像一起改）；mock 通道（`FakeSupabaseRpcServer` 按客户端命名镜像）不暴露此问题：

| 常量 | 客户端调用 | 服务端实际函数名 | 请求参数 | 响应 |
|------|-----------|-----------------|----------|------|
| `pushRpcName` | `push_batch` ⚠️ | `sync_push_batch` | `p_device_id` + `p_ops`（数组，op 内 payload 为**内嵌 jsonb 对象**，非字符串） | `{acks:[{outbox_id,revision,acked_at}], rejections:[{outbox_id,reason}]}` |
| `pullRpcName` | `pull_changes` ⚠️ | `sync_pull_changes` | `p_device_id` + `p_cursors`（表名→hlc 水位）+ `p_limit` | `{changes:[{table_name,row_id,op,row,hlc,revision,schema_ver}], cursors, has_more}` |
| `registerRpcName` | `register_device` ✅ | `register_device` | `p_device_id/p_name/p_platform/p_created_at` | 回显体，以不抛异常为准 |

- reason 线协议值（wire）：`schema_ver` / `row_missing` / `hlc_non_monotonic` / `base_revision_conflict` / `tombstone_conflict` / `unknown`；未知新值兜底 `unknown`（前向兼容）。
- `fetchRow` 走 REST `from(table).select().eq('id', rowId)`；墓碑行以 delete op 交付。
- 响应结构守卫：畸形响应抛 `SyncBackendException('protocol')` 而非裸 TypeError。
- `maxPullRows=200`（服务端硬上限 500）。

## 5. SyncConfig（`sync_config.dart`）

`{url, anonKey, headers={}, timeout=30s}`。宿主 bootstrap 从自己的配置源注入；**本包不读环境变量、不内置凭据**。

## 6. DeviceRegistry（`device_registry.dart`）

| 方法 | 语义 |
|------|------|
| `ensureRegistered({name, platform})` | 三步：LocalWriteClock 取 deviceId → 本地 devices 行幂等 upsert（只刷新 last_seen，revoked 不复活）→ backend.registerDevice（分区时本地照常登记，返回 `ackedByServer=false`） |
| `listDevices()` | 本地 devices 全行（设备管理页数据源） |

返回 `DeviceRegistrationResult(deviceId, registeredLocally, ackedByServer)`。

## 7. 存储实现

**DriftSyncOutboxStore**（实现 core_domain `SyncOutboxStore`）：`enqueue`（insertOnConflictUpdate——同 id 重复入队=覆盖；**须在业务 Drift 事务内调用**）/ `dequeuePending(limit=100)`（出队序 created_at→hlc）/ `markAcked` / `drop` / `pendingCount`。

**DriftSyncLocalStore**（非接口，具体类）：

| 方法 | 语义 |
|------|------|
| `getRawRow(table, rowId)` | 本地行原始快照（snake_case 平铺，含墓碑），仲裁输入 |
| `applyEntry/applyLine(payload)` | 经 core_db 仓库落库（与 UI 写同一校验：墓碑拒复活、金额行不可变、投影联动） |
| `applyGenericRow(spec, payload)` | 其余 12 表通用 upsert：未知列过滤、bool→0/1、缺主键抛 ArgumentError；返回受影响日期集 |
| `readCursors/writeCursor` | sync_cursors 读写（PK=device_id+table_name） |
| `writeRevision(table, rowId, revision)` | push ack 的服务端权威 revision 回写业务行 |
| `markDatesDirty / markAllSummaryDatesDirty / recomputeDirty` | day_summary 自愈三件套 |

## 8. sync_table_catalog — 策略目录 API

- `kSyncTables`：14 张 `SyncTableSpec`（声明序=文档表序）。
- `syncTableSpec(name)`：按名取登记，**未知表名抛 ArgumentError**（表集冻结）。
- `syncTablesInApplyOrder`：rank 升序、同 rank 按表名典序的落库序列。
- `SyncTableSpec` 字段：`name/conflictClass/rank/parentTable/parentKey/ownDateKey/marksAllDatesDirty`。

## 9. backend 切换方式

切换发生在壳层工厂（`apps/mobile/lib/sync/sync_backend_factory.dart`），本包零改动：

- 构建期 `--dart-define=SLIMCA_SUPABASE_URL=<url>` + `--dart-define=SLIMCA_SUPABASE_ANON_KEY=<key>` 两者齐 → `SupabaseSyncBackend`；
- 任一缺失 → `LocalLoopbackBackend`（缺省态，功能不受影响）；
- 测试注入：`createSyncBackend(transport: mock)` 传入 mock `SyncRpcTransport` 绕过真实网络。

真实端点联调只需注入凭据，无需改代码；settings 页状态行由 `describeSyncBackend()` 展示当前装配。
