# data-model — 同步域数据模型

> outbox 行结构、HLC 定宽时钟、同步状态机、14 表策略目录、游标与投递水位。客户端 Drift schema 在 core_db（见 [../core_db/README.md](../core_db/README.md)），服务端 Postgres schema 在 server-supabase。

## 1. sync_outbox — 出网队列（§5.6⑯，「一切出网必经之路」）

客户端本地件（不上云，服务端只留 id 作幂等键）：

| 列 | 类型 | 说明 |
|----|------|------|
| `id` | TEXT PK | **幂等键**：服务端据此去重，重试不重复入账 |
| `table_name` | TEXT | 目标真值表名（14 表白名单之一）；Dart getter 名为 `targetTable`，经 `.named('table_name')` 冻结 SQL 列名（规避 drift 框架钩子冲突） |
| `row_id` | TEXT | 目标行主键（UUIDv7） |
| `op` | TEXT | `upsert` / `delete` |
| `payload` | TEXT(JSON) | 行快照（与实体 toJson 同构；含 §5.1 公共列 hlc/revision/schema_ver/deleted_at） |
| `base_revision` | BIGINT? | 乐观校验基线（null=首次写入） |
| `hlc` | TEXT | 本条出网事件的定宽 HLC |
| `created_at` | BIGINT | 入队时刻（出队序第一序） |
| `acked_at` | BIGINT? | 服务端确认时刻；null=待发 |

写入纪律：**业务行与 outbox 行必须同事务**（core_db `SyncOutboxWriter` 统一落点，同事务重复折叠、跨事务 pending 收敛到最新快照）。`enqueue` 由写入方在事务内调用；引擎侧只 dequeue/markAcked/drop。已 ack 行留存（不删），pending 判定恒按 `acked_at IS NULL`。

## 2. HLC 定宽时钟（实现在 core_domain，本包消费）

编码 `physicalMs(13 位) : counter(6 位) : deviceId(12 位 hex)` → 定宽字符串**字典序=时间全序**（§6.3）。这是 LWW 仲裁、游标比较、出队序的全部基础——比较一律用字符串 `compareTo`，禁止解析成整数比较。

- 引擎持有 `HlcClock` 但**只 `recvEncoded()` 不 `now()`**：发戳方（UI 写路径）与同步层必须共享同一实例（bootstrap 装配点保证），否则本地写与远端 recv 两条线各自跳变、HLC 不再单调。
- pull 到的远端时间戳逐行 `recvEncoded`（跳变跟上，FormatException 坏值不吃）；采纳服务端行后同样 recv。

## 3. 同步状态机

```
SyncPhase: idle → pushing → pulling → done
                       ↘ error（任一阶段捕获异常；只降级回调，不抛出）
```

一轮 `syncOnce` 的推进规则：

1. **push 循环**（≤10 轮）：每轮 dequeue 批次（≤batchLimit，序 created_at→hlc）→ push → ack/作废减少 pending。终止条件：批空 / pending=0 / 本批全部暂缓（无 ack 且拒绝全为 rowMissing/unknown）——绝不自旋。
2. **pull 循环**（≤50 轮）：读游标 → pull → 落库 → 游标**严格大于才推进** → `hasMore` 续拉。
3. **投影自愈**：apply 收集的 dirtyDates → `markDatesDirty` → `recomputeDirty`（只重算 dirty=1 的日）。day_summary 永不同步（§6.1 原则 3），全靠 dirty 自愈。

落库结论四分类：`applied`（落库/合并）/ `skipped`（LWW 败者、墓碑保护、超档、坏载荷——确定性，游标照常推进）/ `deferred`（父行未到等暂态——**该表游标停在本条之前**，整批未处理行下轮重拉）/ 意外异常（按暂态保守重拉一次）。

## 4. 同步状态表目录（kSyncTables，14 张冻结）

| 表 | conflictClass | rank | parentTable/Key | 脏日来源 |
|----|--------------|------|-----------------|----------|
| entries | entryLww | 0 | — | ownDateKey=`date` |
| entry_lines | facetRowLww | 1 | entries/entry_id | 经 entry_id 解析 |
| food_items | scalarLww | 2 | entries/entry_id | 经 entry_id 解析 |
| ledgers | scalarLww | 0 | — | **marksAllDatesDirty** |
| categories | scalarLww | 0 | — | marksAllDatesDirty |
| budgets | scalarLww | 0 | — | marksAllDatesDirty |
| todos | todoDoneForward | 0 | — | ownDateKey=`date` |
| fitness_sessions | scalarLww | 0 | — | ownDateKey=`date` |
| fitness_plans | scalarLww | 0 | — | — |
| exercise_sets | scalarLww | 1 | fitness_sessions/session_id | — |
| savings_goals | scalarLww | 0 | — | — |
| savings_contributions | appendOnly | 1 | savings_goals/goal_id | ownDateKey=`date` |
| corrections | appendOnly | 1 | **无父检查**（审计永可插入）/entry_id | 经 entry_id 解析 |
| theme_profiles | scalarLww | 0 | — | — |

明确**不在**目录（永不同步）：day_summary、ai_parses、sync_outbox、sync_cursors、settings、devices、attachments。未知表名在 `syncTableSpec()` 与 InMemory backend 双侧直接拒绝。

## 5. 游标与投递水位

- **sync_cursors**（客户端本地件）：PK(device_id, table_name)，`pull_hlc` = 该表已确定性处理到的最大 hlc。推进条件：整表批内无暂态失败，且新值 `compareTo` 严格大于旧值。
- **服务端双轨资格**（0002_sync_rpc.sql）：`hlc > 游标` OR `revision > 投递水位（last_op_seq）`。低 hlc 迟到行（他端在本端游标推进后才上送）靠第二轨补投——只有 hlc 水位会漏行。
- **投递簿**（InMemorySyncBackend 的镜像实现）：deviceId→表→已投递行 id 集；水位之下但未投递过的行补投一次，重投递经 LWW 仲裁安全去重。
- **游标单调三层对齐**：服务端 `GREATEST(v_cursor, v_max_hlc)`；InMemory 行预算 break 前 clamp；引擎侧严格大于才推进。任一层回退都会整段重投已投递区间（增量语义破坏），详见 [pitfalls.md](pitfalls.md)。

## 6. 服务端承载表（server/supabase/migrations/0001_init.sql）

14 张真值表 + `devices`（服务端为主件，含 revoked_at 吊销位——RPC 前置校验吊销设备一律拒绝）+ `sync_ops`（outbox_id 幂等账，ON CONFLICT DO NOTHING 命中即原回执重放）+ `sync_delivery`（per-device/table 投递水位）。每表带 `user_id`（RLS 行级隔离，客户端无此列）与 CHECK 约束（hlc 格式 `^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$` 等）。类型映射：Drift INTEGER→BIGINT、REAL→DOUBLE PRECISION、bool→BOOLEAN。

## 7. 墓碑（软删）约定

`deleted_at`（UTC ms，null=存活）。墓碑行 pull 照常投递（op=delete）；「墓碑拒绝复活」在**三处**强制：服务端 push 校验（tombstoneConflict 拒绝）、引擎 resolve（删除恒胜，与 hlc 新旧无关）、core_db 仓库 upsert（本地校验挡下）。90 天物理 GC 属服务端后续迁移职责，客户端与 InMemory 均不 GC。
