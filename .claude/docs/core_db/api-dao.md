# core_db API — DAO 方法索引

按业务域分组，覆盖 `lib/src/dao/` 全部 13 个文件。返回形态约定：`Future` 一次性读/写，`Stream` 为 Drift reactive stream（表变更自动重发，UI 直驱）。

## 事件与产出行（仓库实现，实现 core_domain 接口）

### DriftEntryRepository（`entry_repository.dart`）— events 主干

| 方法 | 用途 | 返回 |
|------|------|------|
| `findById(id)` | 按主键查事件（含墓碑） | `Future<Entry?>` |
| `findByDate(date)` | 某日事件列表（排除墓碑，按 created_at/hlc 排序） | `Future<List<Entry>>` |
| `findByDateRange(start, end, {kinds})` | 区间查询；kinds 过滤命中 `(kind,date)` 复合索引 | `Future<List<Entry>>` |
| `upsert(entry)` | 插入/整行更新；墓碑拒绝复活（删后编辑保留 deletedAt）；事件改日后新旧两日投影都重算 | `Future<void>` |
| `softDelete(id, {hlc})` | 软删墓碑（hlc 定宽校验、updated_at 取 hlc 物理段） | `Future<void>` |
| `watchByDate(date)` | 某日事件响应式流（排除墓碑） | `Stream<List<Entry>>` |

构造：`DriftEntryRepository(db, {projection})`；projection 非空时写后同事务重算受影响日的 day_summary。

### DriftEntryLineRepository（`entry_line_repository.dart`）— facet 行

| 方法 | 用途 | 返回 |
|------|------|------|
| `findById(id)` | 按主键查行 | `Future<EntryLine?>` |
| `findByEntryId(entryId)` | 一件事全部产出行（含 superseded/void，修正链展示用；仅排除行墓碑） | `Future<List<EntryLine>>` |
| `findByDate(date)` | **day_summary 重算入口**：只返回计入聚合的行（active + 行/事件均未删，join entries.date 归日） | `Future<List<EntryLine>>` |
| `findActiveByLedger(ledgerId)` | 账本视角活跃行（kcal/钱账本共用入口） | `Future<List<EntryLine>>` |
| `findByCorrectionOf(lineId)` | 修正链查询：谁引用了旧行 | `Future<List<EntryLine>>` |
| `upsert(line)` | 插入/更新；已确认事件的 money 行业务字段不可变（违反抛 `MoneyLineImmutableException`，唯一合法改径是 supersede） | `Future<void>` |
| `supersede(oldLineId, correction)` | 修正=新增行：同事务置旧行 superseded + 落修正行 + 父事件 confirmed→edited；仅 active 行可被修正 | `Future<void>` |

## 账本 / 分类 / 预算域

### LedgerDao（`ledger_dao.dart`）

| 方法 | 用途 | 返回 |
|------|------|------|
| `seedDefaults()` | 空库 seed：默认 money 账本 + 内置 kcal 账本 + default_ledger_id 设置（幂等，同事务入 outbox） | `Future<void>` |
| `findById(id)` | 按主键查账本 | `Future<Ledger?>` |
| `defaultMoneyLedger()` | 首个可用 money 账本（settings 指针失效时的回退口径） | `Future<Ledger?>` |
| `kcalLedger()` | 内置 kcal 账本（不可删不可多开） | `Future<Ledger?>` |
| `getAll()` / `watchAll()` | 全量未删账本（含归档），sort 稳定排序 | `Future` / `Stream<List<Ledger>>` |
| `getActive()` / `watchActive()` | 未删未归档账本（切换抽屉/录入选择数据源） | `Future` / `Stream<List<Ledger>>` |
| `createLedger({name, icon, currency, sort})` | 新建 money 账本（kcal 不开放建口）；name 必须非空 | `Future<Ledger>` |
| `renameLedger(id, {name})` | 重命名（kcal 账本也允许改名/图标） | `Future<void>` |
| `setLedgerArchived(id, {archived})` | 归档/恢复；kcal 拒绝归档；归档默认账本时自动改指剩余首个 money 账本 | `Future<void>` |
| `setDefaultLedger(ledgerId)` | 切默认账本（仅 money 可设；settings 本地件，不出网） | `Future<void>` |
| `defaultLedgerId()` / `defaultLedger()` | 当前默认账本 id/行（指针校验 + 回退链） | `Future<String?>` / `Future<Ledger?>` |
| `watchDefaultLedgerId()` | 默认账本 id 响应式（发 raw 值，不校验有效性） | `Stream<String?>` |

注意：**归档 ≠ 墓碑**（is_archived 置位，不落 deleted_at）；真删除无 DAO 入口（墓碑语义保留给同步 GC）。

### CategoryDao（`category_dao.dart`）

| 方法 | 用途 | 返回 |
|------|------|------|
| `seedPresets()` | 内置 22 条中文分类 seed（expense 16 + income 6，幂等按 kind+name 查缺补插，同事务入 outbox） | `Future<void>` |
| `findById(id)` | 按主键查分类 | `Future<Category?>` |
| `getAll()` | 全量未删分类，expense 在前 | `Future<List<Category>>` |
| `watchByKind(kind)` | 按 kind（expense/income）响应式分类列表（九宫格数据源） | `Stream<List<Category>>` |

### BudgetsDao（`budgets_dao.dart`）

| 方法 | 用途 | 返回 |
|------|------|------|
| `upsertBudget({ledgerId, categoryId, periodType, amount, dayOfMonthStart, carryOver, id})` | 设置/更新预算；同一 `(ledger,category,period)` 只允许一条现行预算（重复设置=原行改额）；月度起点限 1..28 | `Future<Budget>` |
| `softDeleteBudget(id)` | 清除预算=软删墓碑（幂等） | `Future<void>` |
| `findCurrent({ledgerId, categoryId, periodType})` | 现行预算查询（总预算按 `category_id IS NULL` 精确匹配） | `Future<Budget?>` |
| `getAll({periodType})` / `watchAll({periodType})` | 全部现行预算 | `Future` / `Stream<List<Budget>>` |

预算写路径联动：同事务 `markBudgetSnapshotDirty()` + `recomputeDirtyDays()`（预算影响所有已投影日）。

## 采集子实体

### FoodItemsDao（`food_items_dao.dart`）— 菜品明细（calorie 行子表，同步真值）

| 方法 | 用途 | 返回 |
|------|------|------|
| `create({...})` | 新建菜品行（同事务入 outbox） | `Future<FoodItem>` |
| `updateDetails({id, name, portionG, kcal, ...})` | 更新营养事实；任一事实真实变化自动置 user_adjusted=true；无真实变化 no-op（不推版本不入队）；`_unchanged` 哨兵=不改，显式 null=置空 | `Future<void>` |
| `softDelete(id)` | 软删墓碑（幂等，保留首次墓碑时刻） | `Future<void>` |
| `findById(id)` | 按主键查 | `Future<FoodItem?>` |
| `findByEntryId(entryId)` | 按事件查菜品（确认卡/详情页清单） | `Future<List<FoodItem>>` |
| `findByLineId(lineId)` | 按 calorie 行查菜品（行级溯源） | `Future<List<FoodItem>>` |

### AttachmentsDao（`attachments_dao.dart`）— 附件登记与「解析后即焚」状态机

同步边界：attachments 不在同步真值表 14 张内，即焚生命周期**不出网**。

| 方法 | 用途 | 返回 |
|------|------|------|
| `insert({contentHash, kind, mime, sizeBytes, localPath, entryId, id})` | 登记审计元数据，状态起步 active，blob_ref 恒 NULL | `Future<Attachment>` |
| `findById(id)` | 按主键查 | `Future<Attachment?>` |
| `findLatestByContentHash(hash)` | 内容哈希查重（UUIDv7 字典序=时间序，取最新一条） | `Future<Attachment?>` |
| `markBurned(id, {atMs})` | 即焚：**先删文件再落 burned**；单向不可逆；已 burned 幂等保留首次时刻；删文件失败上抛（行保持 active 可重试） | `Future<Attachment>` |
| `purgeExpired({nowMs, retention})` | >7 天残留强制焚毁兜底清扫（active 超龄强推 burned；burned 行残留文件防御性删除；非 UUIDv7 id 保守跳过）；逐行降级不裹事务 | `Future<({int forceBurned, int filesDeleted})>` |

内容焚毁器可注入（`AttachmentContentCleaner` typedef，缺省 `deleteAttachmentFile` 删本地文件）。

## 计划域（待办 / 存钱）

### TodoDao（`todo_dao.dart`）

| 方法 | 用途 | 返回 |
|------|------|------|
| `create({title, note, date, dueAt, goalLink, repeatRule, remindAt, rruleAnchorDate})` | 新建待办（date NULL=收集箱）；有 RRULE 未显式给锚点时锚点=计划日 | `Future<Todo>` |
| `setDone(id, {done})` | 勾选/取消；**只前进**：已完成重复勾选不覆盖首次完成时刻，未完成重复取消 no-op | `Future<void>` |
| `updateDetails({id, title, note, date, dueAt, goalLink, repeatRule, remindAt, rruleAnchorDate})` | 更新基础字段（哨兵/置空语义同上）；改计划日时新旧两日投影都重算；重复三字段互不联动 | `Future<void>` |
| `softDelete(id)` | 软删墓碑 | `Future<void>` |
| `findById(id)` | 按主键查 | `Future<Todo?>` |
| `watchByDate(date)` | 某日待办流（未完成在前——仪表盘待办卡数据源） | `Stream<List<Todo>>` |
| `watchInbox()` | 无日期收集箱流 | `Stream<List<Todo>>` |

### SavingsGoalsDao（`savings_dao.dart`）— 存钱目标

| 方法 | 用途 | 返回 |
|------|------|------|
| `create({name, targetMinor, method, rhythm, deadline, status, startedOn, id})` | 新建目标（startedOn 缺省设备本地今日；method 限 daily365/week52/custom） | `Future<SavingsGoal>` |
| `updateDetails({id, name, targetMinor, deadline, method, rhythm, status, startedOn})` | 更新目标字段；状态流转（completed/abandoned）由上层判定写入 | `Future<void>` |
| `softDelete(id)` | 归档=软删墓碑（区别于 status=abandoned 存活真值行；幂等） | `Future<void>` |
| `findById(id)` | 按主键查 | `Future<SavingsGoal?>` |
| `watchAll()` | 全部未归档目标流（计划页清单） | `Stream<List<SavingsGoal>>` |
| `watchActive()` | 打卡中目标流（进度卡数据源） | `Stream<List<SavingsGoal>>` |

### SavingsContributionsDao（`savings_dao.dart`）— 贡献（append-only）

| 方法 | 用途 | 返回 |
|------|------|------|
| `append({goalId, amountMinor, date, slot, note, source, id})` | 追加贡献；幂等键 **(goal_id, date, source)**，命中返回既有行（首写胜）；目标必须存在且未归档；刻意无 update/delete 方法 | `Future<SavingsContribution>` |
| `findById(id)` | 按主键查 | `Future<SavingsContribution?>` |
| `findEffective({goalId, date, source})` | 幂等探针（上层写前查重） | `Future<SavingsContribution?>` |
| `watchByGoal(goalId)` | 目标贡献时间线流（含远端墓碑行，上层自行过滤渲染撤销痕迹） | `Stream<List<SavingsContribution>>` |
| `sumByGoal(goalId)` | 按目标求和（排除墓碑） | `Future<int>` |
| `watchSumByGoal(goalId)` | 求和响应式流（进度环直驱） | `Stream<int>` |

## 基础设施

### DaySummaryProjection（`day_summary_projection.dart`）— 当日聚合投影

| 方法 | 用途 | 返回 |
|------|------|------|
| `recomputeDaySummary(date)` | 重算指定日并 UPSERT 投影行（幂等可重入；不自带事务，可在调用方事务内执行） | `Future<DaySummary>` |
| `watchDaySummary(date)` | 投影行响应式流（仪表盘卡片墙直驱，无行发 null） | `Stream<DaySummary?>` |
| `markDayDirty(date)` | 标 dirty（供绕过仓库直写的写入方——同步 pull 等） | `Future<void>` |
| `markSavingsProgressDirty({fromDate})` | 存钱快照联动标 dirty（只扫 savings_progress 非空行） | `Future<void>` |
| `markBudgetSnapshotDirty()` | 预算快照联动标 dirty（全量投影行） | `Future<void>` |
| `recomputeDirtyDays()` | 只重算 dirty=1 的日期（后台自愈/崩溃恢复入口） | `Future<void>` |
| `recomputeAll()` | 全量重建（自愈） | `Future<void>` |

顶层函数 `parseSavingsProgress(json)`：解包 savings_progress 快照（防御性解析，坏形状返回空 map 不抛错）。budget_snapshot v2 JSON 形状与三形态兼容口径见 [pitfalls.md](pitfalls.md)。

### SyncOutboxWriter（`sync_outbox_writer.dart`）— 出网入队器

| 方法 | 用途 | 返回 |
|------|------|------|
| `enqueueRow(tableName, rowId)` | **必须在业务写事务内、业务行写后调用**：读回行终态整行入队；op 自动判定（墓碑→delete）；同 (table,row) 未 ack 行折叠为最新快照；只接受 14 张同步真值表名 | `Future<void>` |

### LocalWriteClock（`local_write_clock.dart`）— 本地写入发戳点

| 成员 | 用途 | 返回 |
|------|------|------|
| `deviceId()` | 设备标识（settings 缺失时生成 12 位 hex 落库，懒加载缓存） | `Future<String>` |
| `next()` | 签发 WriteStamp（hlc 定宽编码 + updated_at=hlc 物理段，同源单调） | `Future<WriteStamp>` |

常量：`kSettingDeviceId`、`kSettingDefaultLedgerId`（settings 键名）。

### default_seed.dart

| 方法 | 用途 | 返回 |
|------|------|------|
| `seedDefaultData(db)` | 空库 seed 编排（AppDatabase.migration.beforeOpen 调用）：先 device_id → 账本 → 分类，全幂等 | `Future<void>` |

## 其他公共出口

| 出口 | 用途 |
|------|------|
| `AppDatabase([executor])` | 生产/测试通用构造；缺省 drift_flutter 打开平台目录 slimca.db |
| `openConnection()` | 生产 QueryExecutor（driftDatabase(name: 'slimca')） |
| `backfillAttachmentBurnColumns` / `backfillTodoRruleAnchorColumn` / `backfillSavingsContributionSourceColumn` | v1 内补列幂等回填（beforeOpen 调用，详见 [code-patterns.md](code-patterns.md)） |
| `generateUuidV7` / `generateDeviceIdHex12` / `uuidV7TimestampMs` | UUIDv7 生成（可注入时间/随机种子）、12 位 hex 设备标识、id 内嵌时间戳提取 |
