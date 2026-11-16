# server/supabase — Supabase 服务端（W1 建库；W7-8 同步 RPC）

依据 `docs/design/产品设计文档.md`：

- **§6.2 架构与读写路径**：托管 Supabase（Postgres + Auth + RPC）起步；表结构与客户端 Drift schema 同构；RLS 按 `user_id` 行级隔离；`op seq（BIGSERIAL）+ outbox.id 唯一键`保证幂等。
- **§5 数据模型**：schema v1 表清单（同步真值 14 张 + 本地件 5 张 + 服务端为主 2 张）。
- **§10.1 技术选型**：托管起步、可 `pg_dump` 整体迁自托管（§6.1 原则 4 数据主权）。
- **§11.1 W7-8**：托管 Supabase 接入 + RLS 强化 + 幂等 RPC（`0002_sync_rpc.sql`，本 README「同步 RPC」一节）。

## 目录

```
server/supabase/
├─ README.md
└─ migrations/
   ├─ 0001_init.sql          # schema v1：14 张同步真值表 + devices/attachments + sync_ops + RLS 策略骨架
   └─ 0002_sync_rpc.sql      # W7-8：push_batch / pull_changes / register_device 三个 RPC
                             #        + sync_pull_watermarks（per-device 投递水位）+ sync_table_registry（表登记白名单）
```

## 服务端表范围（与客户端 Drift 表的对应）

客户端 Drift schema v1 共 21 张（§5.1），服务端只承载会同步的部分：

| 分组（§5.1） | 表 | 服务端 | 客户端 Drift 表 |
|---|---|---|---|
| 同步真值表（14） | entries / entry_lines / food_items / ledgers / categories / budgets / todos / fitness_sessions / fitness_plans / exercise_sets / savings_goals / savings_contributions / corrections / theme_profiles | 建表，字段与 Drift 同构 | packages/core_db 同名表 |
| 服务端为主（2） | devices / attachments | 建表；devices 行由注册 RPC 写入，attachments 为引用登记 | packages/core_db 同名表 |
| 本地件（5） | day_summary / ai_parses / sync_outbox / sync_cursors / settings | **不建**（见下） | packages/core_db 同名表 |

本地件不建服务端表的原因：

- `day_summary`：投影永不同步（§5.6⑬ / §6.1 原则 3），双端从明细各自重建、永远自愈。
- `ai_parses`：本地缓存与留痕（§5.6⑭），`entries.ai_parse_id` 只存 id 溯源。
- `sync_outbox`：客户端出网队列（§5.6⑯），服务端只留其 `outbox.id` 作幂等键（见服务端 `sync_ops` 表）。
- `sync_cursors`：客户端 per-table 拉取游标（§5.6⑰）。
- `settings`：§5.1 归为本地件，本迁移按冻结清单不建。注意 §6.5 冲突矩阵把 settings 列入标量 LWW 类，若后续决定标量配置上云，以增量迁移补表（勿改 0001，§6.4 冻结期禁破坏性变更）。

另有 `sync_ops`（§6.2 同步基础设施，非 §5 清单表）：权威 `op_seq BIGSERIAL` + `outbox_id` 唯一键，重试不重复入账；客户端回写 `revision = op_seq`。

## 前置条件

- Node ≥ 20（开发机实况 Node 24.19，§10.3）与 npm。
- Supabase CLI（`npm i -g supabase` 或用 `npx supabase`），CLI 版本需与其生成的 `config.toml` schema 匹配。

## 首次初始化（一次性）

`config.toml` 与 CLI 版本耦合，故本骨架未预置；首次执行者生成并提交进仓库：

```bash
cd server
supabase init      # 在 server/ 下生成 supabase/（即本目录）的 config.toml；
                   # 会识别已存在的 migrations/，不会覆盖 0001_init.sql
git add supabase/config.toml   # 路径即 server/supabase/config.toml，提交
```

## 本地开发栈（本地 Supabase）

```bash
cd server
supabase start     # 启动本地栈：API :54321 / DB :54322 / Studio :54323
supabase db reset  # 回滚并按文件名顺序重放 migrations/*（0001 建库 → 0002 建 RPC）；可反复执行
supabase stop      # 停止本地栈
```

验证：

- 打开 Studio <http://127.0.0.1:54323>：应看到 19 张表（14 同步真值 + devices + attachments + sync_ops + sync_pull_watermarks + sync_table_registry），每张同步表均 enable RLS 且有 `*_owner_all` 策略。
- RPC 应可见 `sync_push_batch` / `sync_pull_changes` / `register_device` 三个函数（SECURITY DEFINER、`REVOKE FROM PUBLIC/anon`、仅 `authenticated` 可执行）。
- RLS 生效验证：anon（未登录）默认全拒；需注册 auth 用户后携带其 JWT 才能按 `user_id = auth.uid()` 读写。RPC 内部即使 DEFINER 绕过 RLS，也逐语句显式按 `auth.uid()` 过滤（见下文强化审计）。

## 托管库初始化与迁移应用（对照 §6.2）

```bash
cd server
supabase login
# 在 supabase.com Dashboard（或 supabase projects create）建好项目后：
supabase link --project-ref <PROJECT_REF>
supabase db push --dry-run   # 预览将应用的迁移
supabase db push             # 按序应用未应用的迁移到托管库
```

- 迁移文件命名 `NNNN_描述.sql`（CLI 按字典序应用，`0001_` 前缀与 `db push` 兼容）。
- `db push` 会按序应用 `0001_init.sql`（建库 + RLS 骨架）与 `0002_sync_rpc.sql`（三 RPC + sync_pull_watermarks + sync_table_registry），无需额外步骤。
- **已应用的迁移不可修改**（§6.4：v1-v3 冻结期禁破坏性迁移）；新变更一律新增文件（`supabase migration new <name>`）。
- 回滚本地库用 `supabase db reset`；托管库回滚需新增反向迁移或从备份恢复。

## 迁移与 Drift schema 的对应（§6.2「单侧定义双侧生成」）

- W1 现状：`0001_init.sql` 为按 §5 手写的骨架；`packages/core_db` 的 Drift 表按同一份 §5 清单建表，两侧以 §5.1 约定对齐。
- 类型映射速查（详见迁移文件头注释）：

  | Drift/SQLite | Postgres | 说明 |
  |---|---|---|
  | TEXT | TEXT | id=UUIDv7 亦为 TEXT（§5.1） |
  | INTEGER（毫秒时间戳/计数/revision） | BIGINT | SQLite INTEGER 64 位，PG INTEGER 32 位，毫秒时间戳超 32 位 |
  | REAL | DOUBLE PRECISION | 8 字节 IEEE 浮点 |
  | INTEGER(bool) | BOOLEAN | — |
  | TEXT(JSON) | TEXT | 两侧同为 TEXT 存 JSON 字符串 |

- 演进目标（§6.2 原文）：由 Drift schema 生成 SQL 迁移、单侧定义双侧生成，杜绝手写漂移；该机制落地时更新本节。
- 两侧已知需要对齐的判断标注（均在迁移文件内注明）：`food_items.confidence`、`corrections.old_value` 取可空（文档未标「?」但存在合法空值场景）；`exercise_sets.weight_kg_x10` NOT NULL（自重=0）；`theme_profiles.motion_level` 默认 `'full'`。

## 同步 RPC（W7-8，`0002_sync_rpc.sql`）

三个 plpgsql RPC（函数名与客户端 `SupabaseSyncBackend` 冻结命名一致），jsonb 进/出：

| RPC | 签名 | 返回 |
|---|---|---|
| `sync_push_batch` | `(p_device_id text, p_ops jsonb)` | `{acks:[{outbox_id, revision, acked_at}], rejections:[{outbox_id, reason, message}]}` |
| `sync_pull_changes` | `(p_device_id text, p_cursors jsonb, p_limit int)` | `{changes:[{table_name, row_id, op, row, hlc, revision, schema_ver}], cursors:{表→hlc}, has_more:bool}` |
| `register_device` | `(p_device_id text, p_name text, p_platform text, p_created_at bigint)` | `{device:{...}, server_now:bigint}` |

push 的 `p_ops` 元素：`{outbox_id, table_name, row_id, op(upsert|delete), payload(行 jsonb 对象), hlc, base_revision?}`。

### push 语义（§6.2 写路径 + §6.5 服务端半边）

- **幂等键 = `outbox.id`**（§5.6⑯）：命中 `sync_ops` 唯一键即原回执重放；并发重复由 `ON CONFLICT DO NOTHING` 兜底（后到者重放先到者的 op_seq）——重试不重复入账。
- **校验逐条拒绝、不整批回滚**（§6.2 校验清单）：结构非法→`unknown`；非同步表（§5.1 冻结表集）→`unknown`；`schema_ver` 超档→`schema_ver`（§6.4）；hlc 非严格递增→`hlc_non_monotonic`（§6.3 定宽字典序分段比较）；baseRevision 不匹配→`base_revision_conflict`；墓碑复活→`tombstone_conflict`（§6.5 第 7 行）；父行缺失→`row_missing`；跨用户 id 占用→`unknown`。
- **权威 revision**（决策 C）：接受即写 `sync_ops` 取 BIGSERIAL `op_seq`，业务行以 `existing || payload || overlay` 合并 upsert（overlay = revision/user_id/device_id，服务端签发、不信任客户端）。
- **todos set 胜**（决策 G，§6.5 第 6 行）：「取消完成」仅当 baseRevision 命中服务端现值（无并发）时生效；并发 unset 由服务端保留 `done_at` 并 **ACK（非拒绝）**——勾选永不丢失，客户端经回显仲裁收敛。
- 动态 SQL 列名全部来自 `sync_table_registry.cols`（从 information_schema 按 0001 实际表结构生成，单侧真值）；客户端 payload 未知键经 `jsonb_populate_record` 自动忽略——正是 §6.4「老服务端忽略新列」的前向兼容对侧（决策 F）。

### pull 语义（§6.2 读路径 + 投递水位补漏）

- **资格 = `hlc > 客户端游标 OR revision > 投递水位`**（决策 E）：`sync_pull_watermarks`（per user/device/table）GREATEST 单调推进。只按游标会漏掉「他端离线迟到的低 hlc 新行」（投递洞）；op_seq 是服务端接受序，任何上一轮 pull 之后被接受/改写的行必然重新可见。
- 输出按 `rank, table_name` 表序（父表先于子表，§6.2 依赖序）、表内 revision 升序；全局行预算 `p_limit`（clamp 1..500）；**预算耗尽保守 `has_more=true`**（后续表本轮未扫——宁可多一轮空拉，不可丢表）。
- 服务端 `cursors` 输出仅信息性；客户端引擎自行合并 since 游标与增量游标后写 `sync_cursors`（§5.6⑰）。
- 交付行剥离 `user_id` 列（`to_jsonb(t) - 'user_id'`）；BOOLEAN 列在行快照中即 JSON `true/false`（与客户端 Entry/meta 编解码约定一致）。

### register_device（§5.6⑰）

幂等注册 = 刷新 name/platform/last_seen_at；`revoked_at` 永不复活；设备 id 被其他用户占用→23505 拒绝。

### 拒绝三分类 → 引擎处置（§6.2「拒绝分类回处理」）

| wire reason | 客户端 SyncRejectionReason | 处置（决策 D） |
|---|---|---|
| `schema_ver` | schemaVerRejected | 作废：drop outbox（本端永不理解，永不重试） |
| `row_missing`（op=upsert） | rowMissing | 暂缓：保留重试；父行补送后转正清账 |
| `row_missing`（op=delete） | rowMissing | 幂等完成：drop（删除幂等） |
| `hlc_non_monotonic` | hlcNonMonotonic | 作废：drop + fetchRow 采纳服务端现值 |
| `base_revision_conflict` | baseRevisionConflict | 作废：drop + 采纳服务端现值（LWW 后写者胜） |
| `tombstone_conflict` | tombstoneConflict | 作废：drop + 采纳服务端墓碑 |
| `unknown` / 未来 wire 值 | unknown | 暂缓重试（前向兼容） |

### RLS 强化审计（决策 A/H，对照 0001 头注释第 8 条）

- 三函数均 SECURITY DEFINER，但**逐语句显式按 `auth.uid()` 约束**：行锁读现值、父行存在检查、upsert 的 `WHERE user_id = auth.uid()`、水位/设备行读写全部自带属主过滤；anon（无 JWT → `auth.uid()` 为 NULL）一律拒绝。
- **跨用户 id 占用拦截**：新行 id 已被其他用户占用 → `unknown` 拒绝（UUIDv7 冲突概率趋零，此为纵深防御）。
- **已吊销设备**（`revoked_at` 非空）push/pull 一律拒绝（一键下线的服务端半边）；**未注册设备 MVP 期放行**（注册与首推可乱序，决策 H）。
- 权限收口：三函数 `REVOKE ALL FROM PUBLIC/anon` + `GRANT EXECUTE TO authenticated`；`sync_table_registry` 服务端自用（REVOKE FROM anon, authenticated）；`sync_pull_watermarks` 启用 RLS 仅本主可直读。
- 客户端直读单行（`fetchRow` 采纳服务端现值用）走 REST + RLS（`select=* & id=eq.<id> & limit=1`），同样按 `user_id = auth.uid()` 隔离。

### 客户端接入与待办

- `SupabaseSyncBackend(config: SyncConfig(url: …, anonKey: …))`：`supabase` dart 包仅用 core（**非 supabase_flutter**，§6.2 不引 Flutter 侧依赖）；`transport` 参数可注入替换（测试 seam，§6.7）。
- 设备注册 `registerDevice(DeviceRegistration(...), deviceId: …)` 建议首推前调用（幂等，与首推乱序亦安全）。
- **待用户凭据**：用户尚未提供 Supabase 项目凭据——`SyncConfig{url, anonKey}` 一切按宿主注入设计；真实端点联调（托管库 push/pull 往返、RLS 实测、`db push` 实跑）标注「待用户凭据」，当前以 mock transport 双轨（`FakeSupabaseRpcServer` 线级镜像 + `FakeHttpTransport` 传输栈脚本）覆盖契约与全链路（packages/feature_sync/test，禁真实网络）。

### 边界与后续迁移占位

- 维度引用（ledger_id/category_id 等）只做「存在且属本用户」校验；引用对象已被删的语义修复属客户端仲裁（§6.5），服务端不级联改写。
- 墓碑 90 天物理清理 GC 定时任务（§5.1/§6.5）：不在本期，后续以独立迁移 + 调度（pg_cron 或外部）补充。
- pull 分页游标目前按「游标 + 水位」双轨整表扫描（W7-8 规模 OK）；数据量增长后可加 `(user_id, table_name, revision)` 类索引优化（0002 已建 per-table `idx_<t>_user_revision`）。

## 数据主权（§6.1 原则 4）

- 托管库可 `supabase db dump` / `pg_dump` 整体迁出至自托管（P2 docker-compose 部署，§3.7）。
- 投影/统计/余额/进度从不在服务端（§6.1 原则 3），迁出文件即全部同步真值。
