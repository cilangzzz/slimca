# API — 同步 RPC 与 REST 直读

> 服务端函数定义：`server/supabase/migrations/0002_sync_rpc.sql`。
> 客户端实现：`packages/feature_sync/lib/src/supabase_sync_backend.dart`（线协议唯一对接方）。
> 传输：`POST /rest/v1/rpc/<fn>`，Header 携带 anon key + 登录用户 JWT；jsonb 进/出。
> 三函数均 `SECURITY DEFINER`，内部逐语句显式按 `auth.uid()` 过滤（定义者绕过 RLS，属主约束自己做）。

## RPC 总表

| RPC | 服务端签名 | 返回 jsonb | 调用方 |
|---|---|---|---|
| `sync_push_batch` | `(p_device_id text, p_ops jsonb)` | `{acks:[…], rejections:[…]}` | `SupabaseSyncBackend.pushBatch` |
| `sync_pull_changes` | `(p_device_id text, p_cursors jsonb DEFAULT '{}', p_limit int DEFAULT 200)` | `{changes:[…], cursors:{…}, has_more:bool}` | `SupabaseSyncBackend.pullChanges` |
| `register_device` | `(p_device_id text, p_name text DEFAULT NULL, p_platform text DEFAULT 'unknown', p_created_at bigint DEFAULT NULL)` | `{device:{…}, server_now:bigint}` | `SupabaseSyncBackend.registerDevice` |

执行权限：`REVOKE ALL FROM PUBLIC/anon` + `GRANT EXECUTE TO authenticated`；anon（无 JWT → `auth.uid()` 为 NULL）一律拒绝。

---

## sync_push_batch（写路径）

### 参数

- `p_device_id`：设备标识（客户端 device_id，UUIDv7 TEXT）。已吊销（`devices.revoked_at` 非空）→ 抛 42501；未注册 MVP 期放行（注册与首推可乱序）。
- `p_ops`：jsonb **数组**，元素结构：
  ```json
  { "outbox_id": "…", "table_name": "…", "row_id": "…",
    "op": "upsert|delete", "payload": {…行快照…}, "hlc": "0001…:000042:…",
    "base_revision": 12 }
  ```
  约束：`payload` 必须是 jsonb object 且 `payload.id`/`payload.hlc` 与信封字段一致；数值字段必须是 jsonb number（文本数字会触发结构拒绝）；`schema_ver > 1` → `schema_ver` 拒绝。

### 校验序（逐条拒绝、不整批回滚）

结构非法(unknown) → 表注册白名单(unknown) → schema_ver 超档(schema_ver) → 幂等重放（`sync_ops.outbox_id` 命中即原回执重放）→ hlc 严格递增(hlc_non_monotonic，仅比较 phys:ctr 两段) → todos set 胜判据（并发 unset 例外）→ baseRevision 乐观校验(base_revision_conflict) → 墓碑拒绝复活(tombstone_conflict) → 父行存在性(row_missing，`corrections` 无父检查) → 跨用户 id 占用(unknown) → 落行。

### 返回

- `acks`：`[{outbox_id, revision (=服务端 op_seq), acked_at (UTC ms)}]`；客户端 ack 后把 revision 回写本地行。
- `rejections`：`[{outbox_id, reason, message}]`，wire reason 与引擎处置对照：

| reason | 触发 | 客户端处置（LocalSyncEngine） |
|---|---|---|
| `schema_ver` | 行 schema_ver 超服务端档 | 作废 drop（永不重试） |
| `row_missing`(upsert) | 父行缺失 | 暂缓保留，父行补送后转正 |
| `row_missing`(delete) | 删除时行不存在 | 幂等完成 drop |
| `hlc_non_monotonic | base_revision_conflict | tombstone_conflict` | 乐观校验失败类 | drop + fetchRow 采纳服务端现值 |
| `unknown` | 结构非法/未知表/id 占用/意外约束 | 暂缓重试（前向兼容） |

### 服务端签发（不信任客户端）

接受即 `INSERT sync_ops`（`ON CONFLICT (outbox_id) DO NOTHING` 取 BIGSERIAL `op_seq`），行快照 = `existing || payload || overlay`，overlay 覆写 `revision/user_id/device_id`（+ delete 未带 `deleted_at` 时服务端补 now）。payload 未知键经 `jsonb_populate_record` 自动忽略（新客户端→老服务端前向兼容的对侧）。

---

## sync_pull_changes（读路径）

### 参数

- `p_device_id`：同上；已吊销拒绝。
- `p_cursors`：`{"表名": "该表已拉到的最大 hlc", …}`，缺表视为 `''`（全量）。
- `p_limit`：行预算，clamp 1..500，默认 200（客户端 `maxPullRows` 传 200）。

### 投递资格（双轨）

`hlc > 客户端游标 OR revision > 服务端投递水位`（`sync_pull_watermarks` per user/device/table）。水位轨兜住「他端离线迟到的低 hlc 新行」——op_seq 是服务端接受序，上一轮 pull 后被接受/改写的行必重新可见。

### 返回

- `changes`：`[{table_name, row_id, op(upsert|delete), row(行快照，已剥离 user_id 列), hlc, revision, schema_ver}]`；op 由 `deleted_at` 是否为 NULL 推导；墓碑行含在内。
- 排序：按注册表 `rank` 升序（父表先于子表），表内 revision 升序；全局行预算跨表共享，**预算耗尽保守 `has_more=true`**（未扫表宁可多一轮空拉）。
- `cursors`：每表 `GREATEST(入参游标, 本批最大 hlc)`——单调只进不退；**仅信息性**，客户端引擎自行合并游标后写本地 `sync_cursors`。
- 水位推进：`GREATEST(旧水位, 本批 max revision)` 单调；已投递行 revision ≤ 水位，不重投。

---

## register_device（设备注册）

- 幂等 upsert：已存在则刷新 `name/platform/last_seen_at`；`revoked_at` **永不复活**（吊销后重注册仍受 push/pull 拒绝）。
- 设备 id 被其他用户占用 → 抛 23505；本端已注册走刷新分支。
- 返回 `server_now`（UTC ms）供客户端校时参考。
- 建议首推前调用；与首推乱序亦安全（push 对未注册设备放行）。

---

## REST 单行直读（fetchRow）

- 形态：`GET /rest/v1/<table>?select=*&id=eq.<row_id>&limit=1`（RLS 自动按当前用户过滤，行不存在返回 null）。
- 用途：push 被拒（`hlc_non_monotonic`/`base_revision_conflict`/`tombstone_conflict`）后「采纳服务端现值」仲裁链路。
- 无专用 RPC——普通 RLS 直读即可，属主隔离由策略保证。

---

## 错误码（服务端 RAISE）

| ERRCODE | 场景 |
|---|---|
| `42501` | 未登录 / 设备已吊销 |
| `22023` | `p_device_id` 缺失、`p_ops` 非数组 |
| `23505` | 设备 id 被其他用户占用 |

传输层异常映射（客户端侧，`SupabaseRpcTransport`）：`ClientException→network`（可重试）、`TimeoutException→timeout`（可重试）、`PostgrestException→protocol`（含服务端 RAISE，重试无益）。其余传输栈异常归 network。

> 命名错位警示：客户端常量为 `push_batch`/`pull_changes`/`register_device`，而服务端函数名带 `sync_` 前缀——真实端点联调前必须统一，详见 [pitfalls.md](pitfalls.md) 第 1 条。
