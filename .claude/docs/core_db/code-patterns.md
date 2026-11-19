# core_db 编码模式 — 新增表 / 新增 DAO / schema 迁移

## 模式 1：新增一张表（同步真值表为例）

1. **定义表类**：在 `lib/src/tables/` 对应域文件（event/ledger/plan/infra_tables.dart）新建 `class XxxTable extends Table with SyncColumns`。每表自行声明 UUIDv7 主键 `id`（`@override Set<Column> get primaryKey => {id}`）；列文档注释写清 wire 值枚举与引用语义（逻辑引用不建外键）。
2. **登记进 AppDatabase**：`app_database.dart` 的 `@DriftDatabase(tables: [...])` 加入表类。
3. **重新生成**：仓库根（pub workspace）执行
   ```bash
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   ```
   生成物 `lib/src/app_database.g.dart`（数据类/Companion/TableInfo）必须随 schema 变更重跑并提交。
4. **登记出网**：`dao/sync_outbox_writer.dart` 的 `_infos` map 加入 `'xxx_table': _db.xxxTable`（14 张冻结表集之外无出网语义，漏登记会在入队时抛 ArgumentError）。
5. **登记同步策略**：feature_sync `lib/src/sync_table_catalog.dart` 的 `kSyncTables` 加入 `SyncTableSpec`（conflictClass / rank=落库依赖序 / parentTable / ownDateKey / marksAllDatesDirty）。
6. **服务端联动**（详见 pitfalls「改表联动清单」）：`server/supabase/migrations/` 新增迁移建服务端同名表（带 §5.1 公共列 + RLS），并更新 `sync_table_registry`。
7. **测试**：`test/` 新增 DAO 测试（内存库）+ 必要时 `schema_smoke_test` 补断言。

## 模式 2：新增一个 DAO

照 `savings_dao.dart` / `budgets_dao.dart` 的模板写（同口径纪律最完整）：

1. 构造签名 `XxxDao(this._db, {LocalWriteClock? clock, this.projection})`——clock 缺省自建，projection 可空（同步 pull 侧纯落库用法跳过投影）。
2. 持有 `SyncOutboxWriter`，**每个写路径**（create/update/softDelete）都在 `_db.transaction` 内完成：业务行写入 → `_clock.next()` 发戳（revision+1、hlc、updated_at）→ `_outbox.enqueueRow('表名', id)`。
3. no-op 分支（重复勾选/幂等命中/已墓碑）直接 return，**不产生任何写、也不入队**。
4. 删除一律软删墓碑；幂等保留首次墓碑时刻（`deletedAt: Value(row.deletedAt ?? stamp.updatedAtMs)`）。
5. 响应式查询用 `.watch()`；聚合查询用 `customSelect(..., readsFrom: {表})` 保持流活性。
6. 若该表影响投影：写事务内联动 `markXxxDirty` + `recompute`（参照 BudgetsDao._linkProjection / SavingsContributionsDao._touchProjectionForContribution）。
7. 可选字段更新用 `_unchanged` 哨兵（`Object? x = _unchanged`，`Value.absent()` 表示不动）——照抄 TodoDao.updateDetails。

## 模式 3：schema 迁移（两条路径）

### 路径 A：冻结期「v1 内补列」（现行做法，W11-12/W13 用过三次）

前提：V1 未发布、`schemaVersion` 保持 1、变更仅为**只加列**（可空列或带默认值列）。

1. 表类加列：可空列直接加；非空列必须 `withDefault(const Constant(...))`（SQLite 加列语义下存量行一次性落到默认值）。
2. 写幂等回填函数（照 `backfillAttachmentBurnColumns` 模板，放在对应 DAO 文件底部）：
   ```dart
   Future<void> backfillXxxColumn(AppDatabase db) async {
     final info = await db.customSelect('PRAGMA table_info(表名)').get();
     if (info.isEmpty) return; // 表不存在：交给建表流程
     final columns = info.map((row) => row.data['name'] as String).toSet();
     if (columns.contains('新列')) return; // 新库已含：幂等 no-op
     await db.customStatement('ALTER TABLE 表名 ADD COLUMN 新列 ...');
   }
   ```
3. 在 `app_database.dart` `migration.beforeOpen` 中调用（次序：先补列后 seed）。
4. 跑 build_runner 重新生成；新增 `test/w13_column_backfill_test.dart` 式回填测试。

取舍依据：冻结期禁破坏性迁移（§6.4），「v1 内补列+默认值+幂等回填」无版本号变化、对存量开发库文件自愈。若发生在已发布版本上，正规路径是 schemaVersion=N+1 + onUpgrade 迁移步 + 迁移测试。

### 路径 B：破坏性变更（未来）

`schemaVersion` 只加不改原则下，破坏性变更走「新表并存 + 双写过渡 + 全量重拉重建本地库」，不写 onUpgrade 数据搬运。

## 模式 4：测试布局

- 内存库：`AppDatabase(NativeDatabase.memory())`；统一走 `test_support.dart` 的 `tryOpenTestDatabase()`（宿主缺 sqlite3.dll 返回 null，调用方 `skip` 温和跳过——Windows CI/本地无 DLL 时不红）。
- 断言「本次业务写出网行数」前先 `drainSeedOutbox(db)`：beforeOpen 的 seed 会入队 24 行（categories 22 + ledgers 2）。
- 确定性：`TestClock`（物理毫秒自增）作行戳源；`generateUuidV7(timestampMs:, random:)` 注入固定种子；`markBurned(id, atMs:)` / `purgeExpired(nowMs:)` 注入时刻。
- 现有 15 个测试文件按 DAO 命名；投影专项：day_summary_projection / savings_projection / budget_snapshot_v2 / w13_column_backfill / seed_idempotency / outbox_write_path / schema_smoke。

## 模式 5：上层模块如何接入

```dart
final db = AppDatabase();                       // 壳装配一次，Riverpod Provider 注入
final projection = DaySummaryProjection(db);
final repo = DriftEntryRepository(db, projection: projection);   // 写后即时联动投影
final todoDao = TodoDao(db, projection: projection);
// UI 直驱：
StreamBuilder(DaySummaryProjection(db).watchDaySummary(today))  // 仪表盘卡片零业务查询
```

- core_domain 接口（EntryRepository 等）经 Riverpod override 绑定 Drift 实现；装配示例见 apps/mobile 与 [../core_domain/README.md](../core_domain/README.md)。
- 同步 pull 侧（feature_sync）直接用表信息整行落库 + markDayDirty，**不经业务 DAO**（避免回声入队）。
