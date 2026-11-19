# code-patterns — 同步域编码模式

## 模式 A：新增一个同步实体（完整四步）

以「假设新增 `notes` 表成为一等同步实体」为例。四步缺一不可，顺序固定：

### 第 1 步：core_db 建表

- Drift 表类加进 `packages/core_db` 的 schema（21 表体系），带 §5.1 公共列：`device_id / created_at / updated_at / deleted_at / hlc / revision / schema_ver`（主键 id TEXT UUIDv7，客户端生成）。
- 服务端行快照与本地行必须同构（§6.2「单侧定义双侧生成」）；bool 列在 SQLite 存 INTEGER。
- 若有父表（如挂 entries），真实外键照建；`updated_at` 刻意不建触发器（同步语义列由客户端写）。
- 走 core_db 的 `SyncOutboxWriter` 给该表全部写路径补同事务入队——这是硬纪律：**没有 outbox 入队的写入=永远不会上送**。参见 [../core_db/README.md](../core_db/README.md)。

### 第 2 步：sync_table_catalog 登记

`packages/feature_sync/lib/src/sync_table_catalog.dart` 的 `kSyncTables` 追加一条 `SyncTableSpec`：

```dart
SyncTableSpec(
  name: 'notes',                      // 与 Drift entityName/snake_case 一致
  conflictClass: ConflictClass.scalarLww,  // 从 §6.5 矩阵七类中选
  rank: 0,                            // 有父表则父 rank+1（entries=0 → 子=1）
  parentTable: 'entries',             // 无父依赖省略
  parentKey: 'entry_id',
  ownDateKey: 'date',                 // 自带日期列的行才填
  marksAllDatesDirty: false,          // 维度行（账本/分类/预算类）才置 true
),
```

选型要点：审计/贡献类 append-only 表选 `ConflictClass.appendOnly`；todo 类「只前进」语义选 `todoDoneForward`；普通标量行选 `scalarLww`。**不要按表名硬编码策略**——引擎全靠目录分发。

### 第 3 步：Supabase migration

`server/supabase/migrations/` 新增迁移（对照 0001_init.sql 的类型映射）：

- `CREATE TABLE notes (... TEXT/BIGINT/DOUBLE PRECISION/BOOLEAN ...)`，必带：`user_id uuid NOT NULL DEFAULT auth.uid()`（RLS 隔离，客户端无此列）、公共列全套、CHECK 约束（hlc 格式正则照抄）。
- `(user_id, hlc)` / `(user_id, updated_at)` 索引（pull 资格判定走这两个索引）。
- RLS enable + 按 user_id 的策略（服务端 RPC 以 SECURITY DEFINER 绕过 RLS，自行承担校验）。

### 第 4 步：RPC 配合（通常零改动，逐一核对）

- `sync_push_batch`：核对表白名单（SQL 里 enum 数组）加入 `notes`；校验逻辑（schema_ver/hlc/baseRevision/墓碑/父行存在）按目录化的 `parent_table` 通用处理，一般无需改。
- `sync_pull_changes`：核对真值表集合加入 `notes`（双轨资格判定通用）。
- `DriftSyncLocalStore._infos` 映射表补 `'notes': _db.notes`——**这步容易漏**：漏了 `applyGenericRow` 会抛「不是同步真值表」。
- InMemory/Loopback/Fake 后端按 `kSyncTables` 目录工作，自动生效；`test_support.dart` 夹具若预置种子行需补登记。

自检：跑 `feature_sync` 全测试 + `supabase_engine_chain_test`（双轨收敛会覆盖新表），再跑 shell e2e 清 seed 出网项的断言。

## 模式 B：业务写路径接入 outbox（不在本包，但必须知道）

```dart
// 在 Drift 事务内（core_db SyncOutboxWriter 统一落点）：
await outboxWriter.enqueueForUpsert(db.entries, entryJson, baseRevision: null);
// 业务行 + outbox 行同事务提交；读回不到目标行即抛错令事务整体回滚。
```

入队去重语义：同事务重复折叠、跨事务 pending 收敛到最新快照（服务端只关心最终态）。

## 模式 C：引擎调用模式（壳层编排）

```dart
// bootstrap（apps/mobile/lib/app/bootstrap.dart）：
final clock = HlcClock(deviceId: deviceId);          // 与 UI 写路径共享同一实例！
final backend = TelemetrySyncBackend(inner: createSyncBackend(), telemetry: …);
final engine = LocalSyncEngine(
  backend: backend,
  outbox: DriftSyncOutboxStore(database),
  store: DriftSyncLocalStore(database, deviceId: deviceId),
  deviceId: deviceId,
  clock: clock,                                       // 显式传，勿用缺省自建
);
// 触发（SyncCoordinator）：start() = 注册设备 → syncNow → Timer.periodic(15min)；
// WidgetsBindingObserver resumed → syncNow()。重入合并：进行中跳过。
// 同步状态：engine.listener 回调 SyncStatus 或 pendingOutboxCount() 驱动顶栏小圆点。
```

调用纪律：业务代码**只触发 `syncOnce`/`syncNow`，不手动调 push/pull**（它们是 `SyncEngine` 契约方法，编排语义在 `syncOnce`）；`syncOnce` 返回 `SyncCycleReport` 供验收/调试，错误在 `report.error` 不走异常。

## 模式 D：测试替身

| 需求 | 替身 | 用法 |
|------|------|------|
| 单机快速收敛测试 | `InMemorySyncBackend` | 服务端校验全真实现；`partition(id)/restore(id)` 模拟断网；`seedServerRow()` 直种远端行（不占 seq、不校验）；`rowState()/lastSeq` 断言 |
| 无服务端语义验证 | `LocalLoopbackBackend` | push 全 ack、pull 恒空 |
| Supabase 线协议测试 | `ScriptedRpcTransport`（supabase_fakes.dart） | 注入脚本化响应/网络错，`SupabaseSyncBackend(config, transport: mock)` |
| Supabase 全链路 | `FakeSupabaseRpcServer` | 服务端幂等/双轨投递的线级镜像；与 InMemory 跑同一收敛脚本 |

双设备夹具 `SyncDeviceFixture`（test_support.dart）：**开夹具即清空 seed 出网项**——否则计数偏移 24 条且 seed 真实墙钟戳污染 hlc 全序（曾致 21 用例误判）。

## 模式 E：换/包一层后端

实现 `SyncBackend` 四方法即可整体替换（装饰器模式照抄 `TelemetrySyncBackend`：push/pull 处埋点、失败原样 rethrow、fetchRow/registerDevice 直通）。引擎与 schema 零改动。
