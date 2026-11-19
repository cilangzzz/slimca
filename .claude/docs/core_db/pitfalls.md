# core_db 坑点清单（跨模块价值排序）

## 1. 出网入队顺序：enqueueRow 必须在业务写事务内、业务行写后调用

- `SyncOutboxWriter.enqueueRow` 靠**读回目标行终态**构造 payload：事务外调用或先入队后写行 → 读回不到行 → 抛 StateError 令事务整体回滚（宁可不发，不发指空的出网行）。
- **pull 落库侧（feature_sync `DriftSyncLocalStore`）严禁调用**——远端行已是服务端真值，再入队会造成回声循环。entries/entry_lines 的 pull 半边复用同一仓库实现，因此 outbox 入队必须留在 DAO/网关层而非仓库层。
- 新写路径忘记入队不会报错，只会静默丢同步（W5-6 曾因采集路径只落业务行不出网，语音 e2e outbox=0，W7-8 补课）。审查标准：每个真值表写路径的事务块里必须有 `enqueueRow`。

## 2. local_write_clock 与发戳一致性

- `updated_at` 必须取 **hlc 物理段**（`WriteStamp.updatedAtMs`），二者同源单调——同步游标 `(updated_at)/(hlc)` 索引的正确性依赖该一致性。手写 `DateTime.now()` 当 updated_at 会破坏游标单调假设。
- `device_id` 是懒加载单例（settings 键 `device_id`，12 位大写 hex）：seed 时必须**先** `clock.deviceId()` 再插业务行；同一设备所有行共享该标识，HLC 节点段与之同域。
- 同一次用户操作的多行写（supersede 的旧行+新行+父事件）戳取修正行的 hlc/updated_at，不要各自发新戳。

## 3. facet 拆行约定

- 多维度进 entry_lines 行，**不要往 entries 加维度列**（宽表列会让并发编辑互相覆盖， facet 拆行正是为消灭这类冲突）。
- 确认后 money 行业务字段不可变由仓库层强制（`MoneyLineImmutableException`）；绕过仓库直写 entry_lines（如同步 pull 整行落库是合法例外——服务端仲裁过的终态）会绕过守卫。
- 修正走 `supersede`（同事务：旧行 superseded + 新行落库 + 父事件 confirmed→edited）；corrections 审计行由调用方落库，仓库不管。
- 聚合口径：只计 active 且行/事件均未删；**draft 计入聚合**（day_summary 的过滤不含 entries.status）。任何绕过 core_db 直写明细的写入方（同步 pull、feature_dashboard 自带投影路径）必须自行 markDirty 触发重算，否则投影漂移。

## 4. default_seed：幂等 + 24 行出网

- beforeOpen 每次打开都会跑 seed（「缺什么补什么」）：money 账本、kcal 账本、22 条内置分类、device_id/default_ledger_id 设置。seed 行是同步真值行，**会入队 outbox（24 行）**——双设备各自 seed 产生两套不同 id 的默认分类，必须经出网收敛。
- 测试断言 outbox 行数前必须 `drainSeedOutbox`；不要在 seed 里做「已存在行」的修改（幂等=已有行不动，允许用户改名）。
- kcal 账本不可删/不可归档/不可多开（createLedger 只开 money 口）；归档 ≠ 墓碑（is_archived 置位、不落 deleted_at）；默认账本指针在 settings（本地件不出网），归档默认账本时自动重指。

## 5. 改表必须联动（最容易漏的一类）

改一张同步真值表/新增一张表，完整联动清单：

1. Drift 表类 + `@DriftDatabase` 登记 + `dart run build_runner build --delete-conflicting-outputs`（生成物必须提交）。
2. `SyncOutboxWriter._infos` 登记出网表名（漏登记入队即抛错，尚有提示）。
3. feature_sync `kSyncTables`（sync_table_catalog.dart）登记 SyncTableSpec（冲突类/依赖序/ownDateKey）。
4. **Supabase migration**：`server/supabase/migrations/` 加列/建表，并更新 `sync_table_registry`（其 cols 白名单在 0002 迁移时从 information_schema 生成；RPC 动态 SQL 只用白名单列，`jsonb_populate_record` 会**静默忽略** payload 里的未知键）。
5. 已知现状（截至 V1 收官）：W11-12/W13 的 v1 内补列（todos.rrule_anchor_date、savings_contributions.source）**只做了端侧**，服务端 0001_init.sql 与 sync_table_registry 均未含这两列——这两列的 push payload 键会被服务端静默丢弃、跨设备不同步。补服务端迁移前，跨设备重复待办锚点/贡献来源去重只在本设备有效。
6. attachments 即焚两列（status/burned_at）**有意不出网**（服务端为主件的本地审计列），不要把它们加进同步目录。

## 6. day_summary 快照的多形态兼容

- budget_snapshot 已是 v2 形状（`{"v":2,"daily":[...],"monthly":[...]}`），但读取端必须兼容三形态：v1 daily / v2 daily+monthly / feature_dashboard v1 平铺（`{"kcal_budget":...,"spend_budget_minor":...}`）——参考实现 feature_ledger.parseBudgetSnapshot。
- 已知边界：feature_dashboard 自己的投影重算路径仍以 v1 平铺形态覆写快照（W15 集成披露项）——新读取端不要假设全库快照都是 v2。
- `markSavingsProgressDirty` 只扫 savings_progress 非空行：**首个目标建档前**的 NULL 进度行覆盖不到，目标建档路径必须显式 recompute 当日（SavingsGoalsDao 已内置）；预算快照恒非 NULL 所以预算联动是全量标 dirty。

## 7. UUIDv7 id 兼作时间戳

「时间可由 id 得出就不另设时间列」：attachments 即焚保留期（>7 天）、ai_parses 缓存时效（<7 天）都从 id 前 12 hex 提取毫秒。含义：
- 主键必须用 `generateUuidV7()`（或显式传 timestampMs），自造非 UUIDv7 id 会让 purgeExpired **保守跳过**该行（时长不明绝不误焚）。
- 同 hash 查重按 id 字典序取「最新」依赖时间有序性；测试注入固定 timestampMs 构造超龄残留。

## 8. drift 框架名冲突与 SQL 列名冻结

同步出网表 `sync_outbox.target_table` / `sync_cursors.target_table` 的 Dart getter 不能叫 `tableName`（与 drift `Table.tableName` 框架钩子冲突破坏生成代码），故 getter 名 `targetTable` + `.named('table_name')` 冻结 SQL 列名。照抄这个写法，别改回 `tableName`。

## 9. 类型纪律（§5.1 冻结约定）

- 金额一律 INTEGER 分（minor unit）、kcal 一律 INTEGER、重量 ×10 定点（exercise_sets.weightKgX10）——禁 float 存金额。
- 日期一律本地日历日 `yyyy-MM-dd` TEXT（可非今天），一切聚合按 date 分组，杜绝 UTC 错日；UTC 时刻才用 INTEGER ms（occurredAt/dueAt/remindAt）。
- bool 存 INTEGER；settings.value 是 JSON 文本（读侧要 jsonDecode）。
- Companion.insert 里非空无默认列取裸值，`Value()` 只用于可空/带默认列——写错会编译失败，但值得知道原因。

## 10. Windows 测试环境

宿主缺 sqlite3.dll 时内存库打开会抛动态库加载错误——统一走 `tryOpenTestDatabase()` 返回 null 后 skip，不要裸开 `NativeDatabase.memory()` 写死断言（本地与 CI 环境差异会 false 红）。
