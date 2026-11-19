# core_db — Drift 端侧数据库层

## 模块定位

Slimca 的本地数据库层：Drift schema v1（21 张表）+ 13 个 DAO 文件 + 仓库实现 + day_summary 投影 + outbox 出网入队。所有业务数据在端侧的唯一落点，自研同步（outbox + HLC）的本地半边。

源码：`packages/core_db/`，公共出口 `lib/core_db.dart`（一次导出全部表、DAO、工具）。

## 层级与依赖

```
core_domain（接口/领域实体）  ←  core_db 依赖的唯一内部包
    ↑
core_db ──→ 被 6 包 + 壳依赖：core_ai / feature_capture / feature_dashboard /
             feature_ledger / feature_plan / feature_sync / apps/mobile
```

- 实现反转：`EntryRepository`/`EntryLineRepository` 接口在 core_domain，Drift 实现在本包（§10.4 装配纪律）。
- 同步分工：**push 半边**（业务写 → sync_outbox 同事务入队）在本包；**pull 半边**（服务端行落库 + 冲突仲裁）在 feature_sync（`DriftSyncLocalStore`），复用本包的表信息但不走本包 DAO。参见 [../feature_sync/README.md](../feature_sync/README.md)。
- 服务端表结构与 sync RPC：参见 [../server-supabase/README.md](../server-supabase/README.md)。

## 源码地图

| 路径 | 内容 |
|------|------|
| `lib/src/app_database.dart` | AppDatabase（21 表聚合，schemaVersion=1）+ `openConnection()` |
| `lib/src/tables/sync_columns.dart` | SyncColumns mixin：7 个同步公共列 |
| `lib/src/tables/event_tables.dart` | entries / entry_lines / food_items |
| `lib/src/tables/ledger_tables.dart` | ledgers / categories / budgets |
| `lib/src/tables/plan_tables.dart` | fitness_sessions / fitness_plans / exercise_sets / todos / savings_goals / savings_contributions |
| `lib/src/tables/infra_tables.dart` | corrections / theme_profiles / day_summaries / ai_parses / sync_outbox / sync_cursors / settings / devices / attachments |
| `lib/src/dao/` | 13 个 DAO 文件（见 [api-dao.md](api-dao.md)） |
| `lib/src/uuid_v7.dart` | UUIDv7 生成 / device_id / id 内嵌时间戳 |
| `lib/src/app_database.g.dart` | drift_dev 生成物（约 2.4 万行，schema 变更后必须重跑 build_runner） |
| `test/` | 15 个测试文件（内存库 + sqlite3 缺库温和跳过，见 [code-patterns.md](code-patterns.md)） |

## 关键不变量（一句话版，详见 pitfalls）

1. **写路径纪律**：同步真值表的每一次本地写，业务行与 `sync_outbox` 行快照**同一事务**提交（`SyncOutboxWriter.enqueueRow`）。
2. **投影永不同步**：day_summary 是本地物化派生量，双端各自重建、永远自愈；派生量绝不写进同步表。
3. **schema v1 冻结**：`schemaVersion` 只加不改；只加列变更走「v1 内补列 + beforeOpen 幂等回填」。
4. **金额一律 INTEGER 最小货币单位（分），kcal 一律 INTEGER，日期一律本地日历日 `yyyy-MM-dd` TEXT**。

## 测试速览

内存库 `AppDatabase(NativeDatabase.memory())`；`test_support.dart` 提供 `tryOpenTestDatabase`（宿主缺 sqlite3.dll 时返回 null 温和跳过）、`drainSeedOutbox`（清空 seed 出网行）、`TestClock`。全仓 771 例中 core_db 占 47 例（W15 收官口径）。

## 详细文档

| 文档 | 内容 |
|------|------|
| [api-dao.md](api-dao.md) | 13 个 DAO 文件按业务域分组的方法索引（方法名 / 用途 / 返回流） |
| [data-model.md](data-model.md) | 21 表清单 + 关系图 + facet 拆行模型 + sync_columns / outbox 机制 |
| [code-patterns.md](code-patterns.md) | 新增一张表 / 一个 DAO / 一次 schema 迁移的完整步骤（含生成命令） |
| [pitfalls.md](pitfalls.md) | 出网入队顺序、发戳一致性、seed、改表联动 Supabase 等跨模块坑点 |
| [CHANGELOG.md](CHANGELOG.md) | 模块变更历史（真实 git 条目，最新在上） |
