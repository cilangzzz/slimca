# 数据模型 — 云端表与端侧 Drift 表对应

> 云端 DDL：`server/supabase/migrations/0001_init.sql`（17 表：14 同步真值 + devices/attachments/sync_ops + RLS）+ `0002_sync_rpc.sql`（追加 2 张基础设施表/索引）。
> 端侧 21 张 Drift 表的字段级定义见 [../core_db/README.md](../core_db/README.md)，本文只写对应关系与云端特有约定。

## 表清单与对应关系

| 分组 | 云端表 | 端侧 Drift 表 | 说明 |
|---|---|---|---|
| 同步真值（14） | entries / entry_lines / food_items / ledgers / categories / budgets / todos / fitness_sessions / fitness_plans / exercise_sets / savings_goals / savings_contributions / corrections / theme_profiles | `packages/core_db` 同名表（带 SyncColumns mixin） | 字段同构；行随 sync 协议双向流动 |
| 服务端为主（2） | devices / attachments | 同名表 | devices 行由 `register_device` RPC 写入、不走行同步（无 hlc/revision 公共列）；attachments 服务端 DDL 携带 §5.1 公共列，但**客户端当前不 push/pull 它**——`SyncOutboxWriter._infos` 与 `kSyncTables` 均不含 attachments，即焚生命周期只留在设备本地（见 [../core_db/pitfalls.md](../core_db/pitfalls.md)） |
| 云端基础设施（3） | sync_ops / sync_pull_watermarks / sync_table_registry | 无对应（客户端只有 outbox/cursors 语义） | sync_ops：权威 op_seq + outbox_id 幂等键；watermarks：per-device 投递水位；registry：表白名单+列白名单（服务端自用） |
| 本地件（5，**云端不建**） | — | day_summary / ai_parses / sync_outbox / sync_cursors / settings | 投影永不同步；AI 本地缓存；出网队列/游标是客户端协议态；settings 若后续上云须**增量迁移**补表（勿改 0001） |

## 公共列约定（同步真值表通用）

- `id TEXT` = 客户端生成的 UUIDv7，服务端不生成主键。
- `user_id uuid`：**云端专用列**，端侧 Drift 无此列；仅供 RLS 与 RPC 属主过滤，交付行快照时被剥离（`to_jsonb(t) - 'user_id'`）。
- `hlc TEXT`：定宽 13:6:12 段位（物理钟:逻辑钟:节点），CHECK 正则全表一致；字典序=全序。
- `revision BIGINT DEFAULT 0`：0=服务端未签发；push 接受后回写 `sync_ops.op_seq`。
- `schema_ver INTEGER DEFAULT 1`：行级版本，超档整条拒绝（§6.4）。
- `created_at/updated_at/deleted_at BIGINT`（UTC ms，客户端写入）；**刻意不建 updated_at 触发器**——服务端改写会破坏 LWW 序。
- `device_id TEXT NOT NULL`：最后写入设备。

## 类型映射（Drift/SQLite ↔ Postgres）

| Drift/SQLite | Postgres | 原因 |
|---|---|---|
| TEXT | TEXT | id=UUIDv7 亦为 TEXT |
| INTEGER | BIGINT | SQLite INTEGER 64 位而 PG INTEGER 32 位；毫秒时间戳与 revision 均超 32 位 |
| REAL | DOUBLE PRECISION | 8 字节 IEEE 浮点一一对应 |
| INTEGER(bool) | BOOLEAN | — |
| TEXT(JSON) | TEXT | 两侧同为 TEXT 存 JSON 字符串 |

## FK / 约束要点

- `user_id` 全部 `REFERENCES auth.users(id) ON DELETE CASCADE`（用户注销级联清数据）。
- 业务 FK（entry_lines→entries、food_items→line、corrections→entry 等）**不级联物理删**：软删不级联，物理清理由后续 GC 任务统一处理。
- `todos.goal_link`、`fitness_sessions.plan_day_id` 多态引用不设 FK；`corrections.field` 开放枚举不设 CHECK。
- 金额单位：money 恒为「分」（*_minor / amount），kcal 恒为整数 kcal；`entry_lines.amount >= 0`，正负由 `direction` 承载；`exercise_sets.weight_kg_x10` ×10 定点。
- 日期一律 `TEXT 'yyyy-MM-dd'` 本地日历日（杜绝 UTC 错日），CHECK 正则校验。

## RLS 与索引

- 全部 17 张 0001 表 + watermarks ENABLE ROW LEVEL SECURITY；统一策略 `<table>_owner_all`：`FOR ALL TO authenticated USING/WITH CHECK (user_id = (SELECT auth.uid()))`——`(SELECT …)` 包裹是 Supabase 性能建议（避免逐行重求值）。
- `sync_table_registry` ENABLE RLS 且**不建策略**：direct REST 全拒（含 authenticated），仅 RPC（definer）读写。
- 索引双前缀：每张真值表都有 `(user_id, updated_at)`、`(user_id, hlc)`；0002 追加 `(user_id, revision)` 14 张——为 pull 的「revision > 水位」资格分支命中（与 0001 的 hlc 索引各补一半）。
- `sync_ops`：`UNIQUE(outbox_id)`（幂等根）+ `(user_id, op_seq)`、`(user_id, table_name, row_id)`。

## 两侧对齐的判断标注（迁移文件内已注明）

- `food_items.confidence` / `corrections.old_value` 取可空（文档未标「?」但存在合法空值场景）；若 Drift 侧为 NOT NULL 需两侧对齐。
- `exercise_sets.weight_kg_x10` NOT NULL（自重=0 兜底）；`theme_profiles.motion_level` 默认 `'full'`（文档未指定）。
- `devices.platform` 不设 CHECK 枚举（Linux CI golden 测试会注册测试设备）。
- 演进目标：由 Drift schema 生成 SQL 迁移（单侧定义双侧生成）落地前，两侧以 §5.1 约定手工对齐。
