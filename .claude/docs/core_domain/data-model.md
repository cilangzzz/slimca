# core_domain 数据模型

> 本包只定义领域模型与协议值对象；持久化在 `core_db`（Drift 21 表），服务端在 Supabase。三层（领域实体 toJson ↔ Drift 行 ↔ outbox payload / 服务端行）按平铺 snake_case 键名同构，键名漂移 = 同步协议断裂。

## 三层同构约定（§6.2「单侧定义双侧生成」）

```
领域实体（本包 Entry/EntryLine）          Drift 行（core_db 表）           服务端行（Supabase 同步真值表）
  toJson() ───────键名一一对应────────→  DataClass 列（camelCase 属性）   TEXT/INTEGER 列（snake_case）
      │                                      ↑                                ↑
      └──────── sync_outbox.payload（JSON 字符串）─→ push 上送 ────────────────┘
```

- 键名规则：领域字段 camelCase → JSON/DB 列 snake_case（`tzOffsetMin` ↔ `tz_offset_min`）。
- 公共列不逐实体重复定义：实体组合 `SyncMeta`，Drift 表 `with SyncColumns`（`core_db/lib/src/tables/sync_columns.dart`），二者逐列对齐。

## SyncMeta — 所有同步表公共列（§5.1，W1 冻结）

| 字段 | 类型 | JSON/DB 键 | 语义 |
|------|------|-----------|------|
| `createdAt` / `updatedAt` | int | `created_at` / `updated_at` | UTC 毫秒 |
| `deletedAt` | int? | `deleted_at` | 软删墓碑；null=存活。双端对齐后保留 90 天再物理清理 |
| `hlc` | String | `hlc` | 定宽 HLC 编码（33 字符）；LWW 与同步游标的基石 |
| `revision` | int | `revision` | 本地自增起步，push 后升级为服务端权威版本 |
| `schemaVer` | int | `schema_ver` | 行级 schema 版本，默认 `kCurrentSchemaVer`=1 |
| `deviceId` | String | `device_id` | 最后写入设备；entries 表兼任「创建设备」语义 |

- `fromRowJson` 读侧即校验：缺必需键抛 `ArgumentError`，hlc 必须通过定宽解析并规范化（节点段转大写）入库。
- 对应 Drift：`SyncColumns` mixin（同 7 列，`schemaVer` 默认 1）；`core_db` 14 张同步真值表全部 `with SyncColumns`。

## Entry — 事件主干（§5.2①，对应 entries 表）

「一件事」= 一切记录的原子。一次输入=一条事件；产出的钱/热量维度拆在 EntryLine。

| 字段 | 类型 | 键 | 要点 |
|------|------|-----|------|
| `id` | String | `id` | 主键 UUIDv7（TEXT 存储、时间有序、同步友好） |
| `date` | String | `date` | **本地日历日** `yyyy-MM-dd`（构造期校验）；聚合按 date 分组，杜绝 UTC 错日 |
| `tzOffsetMin` | int | `tz_offset_min` | 录入时本地时区偏移（分钟） |
| `occurredAt` | int? | `occurred_at` | 发生时刻 UTC ms，可早于录入时刻 |
| `kind` | EntryKind | `kind` | food/fitness/expense/mixed/note |
| `source` | EntrySource | `source` | text/voice/photo/receipt/chip/manual |
| `title` / `note` | String / String? | `title` / `note` | |
| `status` | EntryStatus | `status` | draft（AI 字段可被新解析覆盖）/ confirmed / edited |
| `aiParseId` | String? | `ai_parse_id` | → ai_parses.id 溯源 |
| `meta` | SyncMeta | 平铺 7 键 | |

索引（core_db）：`(date)`、`(kind, date)`。

## EntryLine — 产出行 facet 行（§5.2②，对应 entry_lines 表）

facet 拆行是差异化的物理落点：手机改金额、平板改热量是两行各自的 hlc，多数冲突在结构层被消灭。

| 字段 | 类型 | 键 | 要点 |
|------|------|-----|------|
| `id` | String | `id` | UUIDv7 |
| `entryId` | String | `entry_id` | → entries.id（FK；软删不级联物理删） |
| `type` | LineType | `type` | calorie（kcal in）/ burn（kcal out）/ money（分） |
| `amount` | int | `amount` | **恒非负**（构造期抛错）；calorie/burn=kcal、money=分；正负语义在 direction |
| `direction` | LineDirection | `direction` | in / out；expense=out、income=in |
| `ledgerId` | String? | `ledger_id` | money 行必填（默认账本）；kcal 行归集内置 kcal 账本 |
| `categoryId` | String? | `category_id` | money=消费分类；calorie 可挂餐饮子类 |
| `currency` | String? | `currency` | money 行，默认 `CNY` |
| `confidence` | double? | `confidence` | AI 置信度 ∈ [0,1]（构造期校验）；三色点口径 |
| `payload` | String? | `payload` | 行级明细引用 JSON 串（商户/支付方式/MET 参数/菜品摘要）——注意与 OutboxEntry.payload 撞名，语义不同 |
| `correctionOf` | String? | `correction_of` | 指向被修正旧行 id；修正=新增行，历史永不改写 |
| `status` | LineStatus | `status` | active / superseded / void |
| `meta` | SyncMeta | 平铺 | |

索引（core_db）：`(entry_id)`、`(ledger_id, updated_at)`、`(correction_of)`。

## 实体关系

```
Entry (1) ──── (N) EntryLine            entry_lines.entry_id FK
EntryLine ──→ EntryLine (correction_of)  修正链：旧行 status→superseded，历史不可改写
Entry.aiParseId ──→ ai_parses.id         AI 解析溯源
EntryLine.ledgerId ──→ ledgers.id        money 行必挂账本（kcal 行=内置 kcal 账本）
EntryLine.categoryId ──→ categories.id   消费分类
Entry(soft) ── 墓碑 deletedAt            删除一律软删，墓碑拒绝复活（§6.5）
```

计划族（todo / fitness_sessions / savings_goals）是独立实体族，**不**硬塞进事件模型（§2.1 边界声明）。

## Hlc / HlcClock — 不落表的运行时对象

- `Hlc` 是不可变值对象；持久化形态是各表 `hlc` TEXT 列与 outbox `hlc` 字段中的**定宽编码字符串**（13:6:12，总长 33）。
- `HlcClock` 是有状态发号器（每设备一个）：`now()` 本地事件、`recv()` 合并远端；`lastIssued` 供同一事务内取刚签发值。墙钟注入，测试用虚拟时钟。

## 同步协议值对象（不落端表，对应 server RPC）

| 值对象 | 对应设施 | 要点 |
|--------|---------|------|
| `OutboxEntry` | `sync_outbox` 表 | 「一切出网必经之路」；`id`=幂等键；`payload`=行快照 JSON **字符串**；`baseRevision` 乐观校验；`ackedAt` null=未确认 |
| `SyncPullCursors` | `sync_cursors` 表 | `Map<表名, HLC字符串>`；PK(device_id, table_name) |
| `RemoteChange` | pull 返回行 | op=delete 时 payload 可为墓碑占位（仅 hlc/deleted_at 有效） |
| `SyncPushAck` / `SyncPushRejection` | push 回执 | ack 携服务端权威 revision 回写业务行；拒绝六类见 README |
| `SyncConflict` / `SyncConflictResolution` | §6.5 仲裁 | `ConflictClass` 七类：scalarLww / entryLww / facetRowLww / immutableMoney / appendOnly / todoDoneForward / tombstone |

## 构造期校验清单（坏数据不进领域层）

| 校验 | 抛错点 |
|------|--------|
| date 非本地日历日 | `Entry` 构造 → `ArgumentError` |
| amount 负值 | `EntryLine` 构造 → `ArgumentError` |
| confidence ∉ [0,1] | `EntryLine` 构造 → `ArgumentError` |
| HLC 段超宽/节点非 12 位 hex | `Hlc` 工厂 → `ArgumentError`；`parse` → `FormatException` |
| 行快照缺必需键 / hlc 非定宽 | `SyncMeta.fromRowJson` → `ArgumentError` / `FormatException` |
| 枚举 wire 值未知 | 各 `fromWire` → `ArgumentError` |
