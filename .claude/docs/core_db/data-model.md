# core_db 数据模型 — 21 表 + facet 拆行 + 同步机制

## 表分组（§5.1 三分法，schema v1 冻结）

| 组 | 表 | 公共列 | 同步 |
|----|----|--------|------|
| 同步真值表 14 张 | entries, entry_lines, food_items, ledgers, categories, budgets, todos, fitness_sessions, fitness_plans, exercise_sets, savings_goals, savings_contributions, corrections, theme_profiles | 携 SyncColumns（7 列） | 双向（push 经 outbox，pull 经 feature_sync） |
| 本地件 5 张 | day_summaries, ai_parses, sync_outbox, sync_cursors, settings | 无 | **永不同步** |
| 服务端为主 2 张 | devices, attachments | 无 | 本地引用登记（attachments 即焚生命周期不出网） |

## 关系图

```
entries ①（事件主干，date 归日）
  ├─ entry_lines ②（facet 产出行）      FK: entry_id → entries.id（唯一物理外键）
  │     └─ food_items ③（菜品明细）      逻辑引用 entry_id / line_id
  ├─ ai_parses ⑭                        ai_parse_id 仅逻辑引用（本地件，pull 回的行无对应行）
  └─ corrections ⑮（修正审计）           逻辑引用 entry_id / line_id（审计必须永可插入）

ledgers ④ ── 逻辑引用 ←── entry_lines.ledger_id / categories.ledger_id / budgets.ledger_id
categories ⑤ ── 逻辑引用 ←── entry_lines.category_id / budgets.category_id
budgets ⑥（ledger+category+period 唯一现行行）

fitness_sessions ⑦ ── 逻辑引用 → entries.id（burn 行 payload 记 session_id）
  └─ exercise_sets ⑨（组明细）          逻辑引用 session_id
fitness_plans ⑧（排期掩码+模板 JSON）
todos ⑩ ── goal_link 多态逻辑引用 → savings_goals / fitness_plans
savings_goals ⑪
  └─ savings_contributions ⑫（append-only）  逻辑引用 goal_id
theme_profiles ⑳（语义 token JSON）

本地件：day_summaries ⑬（PK=date）、sync_outbox ⑯（PK=outbox.id 幂等键）、
        sync_cursors ⑱（PK=device+table）、settings ⑲（PK=key）、ai_parses ⑭（PK=id）
服务端为主：devices ⑰（PK=device_id）、attachments ㉑（PK=UUIDv7，内嵌时间戳）
```

**外键纪律**：仅 `entry_lines.entry_id` 建物理外键（NO ACTION 不级联）；其余全部**逻辑引用不建外键**——跨设备 pull 顺序不定，外键会阻止「子行先于父行到达」的落库。pull 按父表→子表依赖序落库（feature_sync `SyncTableSpec.rank`）；物理 GC（墓碑 90 天）先删子行再删父墓碑。

## facet 拆行模型（本库的核心设计）

「同一条事件的多维度」拆成 entry_lines 行而非 entry 宽表列：

- 一条 entry（一件事，kind=food/fitness/expense/mixed/note）产出 1..N 条 entry_lines：`type=calorie`（摄入）/ `burn`（运动消耗）/ `money`（金额）。
- **每行独立携带 7 个公共列**：手机改金额、平板改热量产生两行各自的 updated_at/hlc，同步合并互不覆盖——多数冲突在数据结构层被消灭，而非靠 LWW 补救（§5.3）。
- 行状态机：`active` / `superseded`（被修正）/ `void`（作废）；修正=新增行（correction_of 指向旧行），旧行原地置 superseded，父事件 confirmed→edited 联动。
- **money 行不可变**（确认后）：仓库层强制（`MoneyLineImmutableException`），唯一合法改径是 supersede；draft 事件下的行不设防（AI 字段可被新解析覆盖）。
- 派生量不进同步表：kcal/支出汇总只存 day_summaries（本地投影），双端从明细行各自重建。

## SyncColumns — 7 个同步公共列（`tables/sync_columns.dart`）

| 列 | 类型 | 语义 |
|----|------|------|
| `created_at` / `updated_at` | INTEGER UTC ms | 不用 DateTime 规避时区歧义；updated_at 与 hlc 物理段同源单调（同步游标 `(updated_at)/(hlc)` 索引依赖该一致性） |
| `deleted_at` | INTEGER? | 软删墓碑；拒绝复活（upsert 命中已删行保留 deleted_at）；双端对齐后保留 90 天再物理 GC |
| `hlc` | TEXT | 定宽 HLC `physical_ms(13):counter(6):device_id(12)`，字典序=时间序，SQLite/Postgres 均 TEXT 比较即全序 |
| `revision` | INTEGER | 本地自增起步，ack 后升级为服务端 op_seq |
| `schema_ver` | INTEGER 默认 1 | 行级 schema 版本，同步层按此协商容忍 N-1、超档拒绝 |
| `device_id` | TEXT | 最后写入设备（12 位 hex，与 HLC 节点段同域） |

主键 `id`（UUIDv7，TEXT）不在 mixin 内——每表自行声明（day_summaries=date、sync_cursors=device+table、settings=key 等主键形态不同）。

## sync_outbox 机制（§5.6⑯/§6.2）

一切出网必经之路：

1. **入队**：业务行写后、同一事务内 `SyncOutboxWriter.enqueueRow(table, rowId)` 读回该行终态整行作 payload。读回而非调用方构造 → supersede/墓碑/多步写路径天然拿到权威终态；业务写回滚时 outbox 行随之回滚，绝不出现「业务行在、出网行指空」。
2. **op 自动判定**：快照带 deleted_at → `delete`，存活 → `upsert`（与服务端仲裁语义一致）。
3. **入队去重**：同 `(table_name, row_id)` 的未 ack 出网行折叠改写为最新快照（服务端只关心最终态）；已 ack 历史行不动。
4. **幂等键**：outbox.id 为本地 UUIDv7，服务端 `sync_ops.outbox_id` 唯一键去重（重试不重复入账），见 [../server-supabase/api-rpc.md](../server-supabase/api-rpc.md)。
5. **同步边界**：enqueueRow 只服务本地写路径；pull 落库侧（feature_sync `DriftSyncLocalStore`）不得调用——远端行已是服务端真值，再入队会造成回声循环。因此 outbox 入队留在 DAO/网关层而非仓库层。
6. 列名注意：目标表列 getter 名为 `targetTable`，SQL 列名经 `.named('table_name')` 冻结（drift `Table.tableName` 是框架自有成员，见 pitfalls）。

## day_summary 投影（§5.6⑬）

- 一日一行（PK=date）：kcal_in/kcal_out/net_kcal、spend_minor/income_minor、todo_done/todo_total、budget_snapshot、savings_progress、tz_offset_min、dirty。
- **重建规则**：任何 entry_lines/todos/budgets/savings 变更 → markDirty → 重算（core_db DAO 写路径已内置联动；同步 pull 落库后由 feature_sync 按 `SyncTableSpec.ownDateKey` 标 dirty）。
- **聚合口径**：只计 `l.status='active'` 且行/事件均未删的行；按 entries.date 归日；**draft 事件计入聚合**（过滤不含 entries.status）。
- budget_snapshot **v2 形状**：`{"v":2,"daily":[{ledger_id,category_id,amount,used,remaining}],"monthly":[...,carry_over,period_start,period_end]}`；读取端须兼容三形态（v1 daily / v2 daily+monthly / feature_dashboard v1 平铺），参考 feature_ledger.parseBudgetSnapshot。
- savings_progress：`{goal_id:{contributed_minor,target_minor}}` 多目标，贡献累计口径 date<=快照日；无有效目标保持 NULL。
- 自愈：`recomputeDirtyDays()`（崩溃恢复）与 `recomputeAll()`（全量重建）保证派生量永远可重建——投影行损坏无需迁移，重算即愈。

## 索引与查询形态

高频查询有显式索引：entries `(date)`/`(kind,date)`/`(updated_at)`/`(hlc)`；entry_lines `(entry_id)`/`(type)`/`(ledger_id,updated_at)`/`(correction_of)`/`(hlc)`。`findByDateRange` 的 kinds 过滤刻意生成 `kind IN (…) AND date BETWEEN …` 命中复合索引；新增查询形态时先对照既有索引。
