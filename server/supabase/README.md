# server/supabase — Supabase 服务端（W1）

依据 `docs/design/产品设计文档.md`：

- **§6.2 架构与读写路径**：托管 Supabase（Postgres + Auth + RPC）起步；表结构与客户端 Drift schema 同构；RLS 按 `user_id` 行级隔离；`op seq（BIGSERIAL）+ outbox.id 唯一键`保证幂等。
- **§5 数据模型**：schema v1 表清单（同步真值 14 张 + 本地件 5 张 + 服务端为主 2 张）。
- **§10.1 技术选型**：托管起步、可 `pg_dump` 整体迁自托管（§6.1 原则 4 数据主权）。

## 目录

```
server/supabase/
├─ README.md
└─ migrations/
   └─ 0001_init.sql   # schema v1：14 张同步真值表 + devices/attachments + sync_ops + RLS 策略骨架
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
supabase db reset  # 回滚并按文件名顺序重放 migrations/*（即应用 0001_init.sql）；可反复执行
supabase stop      # 停止本地栈
```

验证：

- 打开 Studio <http://127.0.0.1:54323>：应看到 17 张表（14 同步真值 + devices + attachments + sync_ops），每张同步表均 enable RLS 且有 `*_owner_all` 策略。
- RLS 生效验证：anon（未登录）默认全拒；需注册 auth 用户后携带其 JWT 才能按 `user_id = auth.uid()` 读写。

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

## 后续迁移占位（不在 0001 范围内）

- `sync_push` / `sync_pull` RPC（§6.2 读写路径）：幂等键 = `outbox.id`（命中 `sync_ops` 唯一键）、hlc 单调校验、签发权威 seq。
- `todos.done_at`「只前进不回退：set 胜」合并规则（§6.5）在 sync_push 内实现。
- 墓碑 90 天物理清理 GC 定时任务（§5.1 / §6.5）。

## 数据主权（§6.1 原则 4）

- 托管库可 `supabase db dump` / `pg_dump` 整体迁出至自托管（P2 docker-compose 部署，§3.7）。
- 投影/统计/余额/进度从不在服务端（§6.1 原则 3），迁出文件即全部同步真值。
