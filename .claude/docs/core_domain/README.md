# core_domain — 纯 Dart 领域层

> 基础层 · 零依赖（纯 Dart，无 Flutter）· 单一导出入口 `package:core_domain/core_domain.dart`
>
> 定位：统一事件模型（Entry / EntryLine facet 拆行）、HLC 混合逻辑时钟、仓库与同步引擎抽象、遥测抽象与隐私闸门。行快照 JSON 键名与 Drift 列同构——本包是「领域实体 / Drift 行 / outbox payload」三层同构的单侧定义点（§6.2）。

## 模块边界

- **依赖**：零运行时依赖；dev 依赖仅 `test` / `flutter_lints`。
- **被依赖**：`core_db`（Drift `SyncColumns` mixin 与 `SyncMeta` 逐列对齐）、`feature_sync`（实现 `SyncEngine` / `SyncOutboxStore`）、`apps/mobile`（实现仓库与遥测）、`core_ai` / `feature_*`（消费实体与枚举）。
- **不含**：任何 IO、数据库、序列化框架、Provider/状态管理。所有持久化与同步编排都在上层实现。

## 公共导出索引（按源文件分组，共 40 个符号）

### common.dart — 同步真值表公共约定（§5.1）

| 导出 | 类型 | 说明 |
|------|------|------|
| `SyncMeta` | 值对象 | 所有同步表公共列（createdAt/updatedAt/deletedAt/hlc/revision/schemaVer/deviceId），`toRowJson`/`fromRowJson` 平铺 snake_case |
| `kCurrentSchemaVer` | 常量 | 行级 schema 版本，当前 1 |
| `kCalendarDayPattern` / `isValidCalendarDay` / `validateCalendarDay` | 工具 | 本地日历日 `yyyy-MM-dd` 校验（非法抛 `ArgumentError`） |
| `formatCalendarDay` | 工具 | 本地 DateTime → `yyyy-MM-dd`（零填充定宽） |

### hlc.dart — HLC 混合逻辑时钟（§6.3）

| 导出 | 类型 | 说明 |
|------|------|------|
| `Hlc` | 值对象 | 定宽编码 `13位物理ms:6位counter:12位hex节点`（总长 33）；`format`/`parse`/`compareTo`；字符串字典序 = 时间全序 |
| `HlcClock` | 可变时钟 | 发号器：`now()`（本地事件）/ `recv()`（合并远端）/ `recvEncoded()`；墙钟注入；回拨 >60s 告警 |

### entry.dart — 事件主干（§5.2①）

| 导出 | 类型 | 说明 |
|------|------|------|
| `Entry` | 实体 | 「一件事」主干；构造期校验 date；`toJson`/`fromJson`；软删看 `isDeleted` |
| `EntryKind` | 枚举 | food / fitness / expense / mixed / note |
| `EntrySource` | 枚举 | text / voice / photo / receipt / chip / manual |
| `EntryStatus` | 枚举 | draft（AI 可覆盖）/ confirmed / edited |

### entry_line.dart — 产出行 facet 行（§5.2②）

| 导出 | 类型 | 说明 |
|------|------|------|
| `EntryLine` | 实体 | 热量/金额/消耗各自一行、独立同步；amount 恒非负、方向在 `direction` |
| `LineType` | 枚举 | calorie（kcal in）/ burn（kcal out）/ money（分） |
| `LineDirection` | 枚举 | in / out（money: expense=out, income=in） |
| `LineStatus` | 枚举 | active / superseded（被修正）/ void |

### repository.dart — 仓库抽象（§10.4，实现在 core_db/apps/mobile）

| 导出 | 类型 | 说明 |
|------|------|------|
| `EntryRepository` | 接口 | findById / findByDate / findByDateRange / upsert / softDelete / watchByDate |
| `EntryLineRepository` | 接口 | findById / findByEntryId / findByDate / findActiveByLedger / findByCorrectionOf / upsert / **supersede**（修正=新增行） |
| `MoneyLineImmutableException` | 异常 | 已确认 money 行被原地改 amount 时实现层必须抛 |

### sync_engine.dart — 同步抽象（§6.2 / §6.5，实现在 feature_sync）

| 导出 | 类型 | 说明 |
|------|------|------|
| `SyncEngine` | 接口 | 三方法：`push(batch)` / `pull(since)` / `resolve(conflict)` |
| `OutboxEntry` / `OutboxOp` | 值对象 | 出网队列行 + op 枚举（upsert/delete）；幂等键 = `id` |
| `SyncOutboxStore` | 接口 | enqueue（**业务事务内调用**）/ dequeuePending / markAcked / drop / pendingCount |
| `RemoteChange` / `SyncPullCursors` | 值对象 | pull 的原子变更行 + per-table HLC 游标 Map |
| `SyncPushResult` / `SyncPushAck` / `SyncPushRejection` / `SyncRejectionReason` | 值对象 | push 逐条回执；拒绝六类：schema_ver / row_missing / hlc_non_monotonic / base_revision_conflict / tombstone_conflict / unknown |
| `SyncPullResult` | 值对象 | changes + nextCursors + hasMore（true 必须续拉） |
| `ConflictClass` / `SyncConflict` / `SyncConflictResolution` / `ConflictWinner` | 值对象 | §6.5 冲突矩阵七类分级仲裁，不按表名硬编码 |

### telemetry.dart — 遥测抽象与隐私闸门（§3.9，实现在 apps/mobile）

| 导出 | 类型 | 说明 |
|------|------|------|
| `TelemetryService` | 接口 | funnel / metric / crash / flush；实现必须先过隐私闸门、永不阻塞主流程 |
| `TelemetryEvent` / `TelemetryKind` | 值对象 | JSONL 统一格式（ts/kind/name/props）+ funnel/metric/crash 三类 |
| `TelemetryPrivacy` | 工具 | 内容字段键黑名单 + 非标量剔除 + 字符串截断 64；实现方必经 |
| `TelemetryFunnel` / `TelemetryMetricName` | 常量集 | 漏斗事件名（cold_start_complete…capture_confirm、sync_push/pull）与指标名（frame_raster_ms 等） |

## 谁实现这些抽象（跨模块地图）

| core_domain 接口 | 实现位置 | 备注 |
|------|------|------|
| `EntryRepository` | `apps/mobile/lib/data/drift_repositories.dart` (`DriftEntryRepository`) | |
| `EntryLineRepository` | `core_db/lib/src/dao/entry_line_repository.dart` (`DriftEntryLineRepository`) | money 不可变强制点在此 |
| `SyncOutboxStore` | `feature_sync/lib/src/drift_sync_outbox_store.dart` (`DriftSyncOutboxStore`) | |
| `SyncEngine` | `feature_sync/lib/src/local_sync_engine.dart` (`LocalSyncEngine`) | push/pull/resolve 编排 |
| `TelemetryService` | `apps/mobile/lib/telemetry/file_telemetry_service.dart` / `noop_telemetry_service.dart` | JSONL 落盘 / 零副作用 |

## 详细文档

- [data-model.md](data-model.md) — 模型/值对象清单、字段要点、实体关系、与 core_db 表及 Supabase 行的三层同构对应
- [code-patterns.md](code-patterns.md) — wire 枚举、copyWith 哨兵、HLC 发号、同事务入队等可复用套路与扩展步骤
- [pitfalls.md](pitfalls.md) — 定宽编码、金额不可变、方向语义、游标推进等跨模块坑点（排查问题先看这里）
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（git 实证，最新在上）
