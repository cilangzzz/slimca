# Changelog - core_domain

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件（坑点语义见 [pitfalls.md](pitfalls.md)）。

---

## [2026-11-16] W9-10 v1.0 公测就绪：北极星埋点核对与补齐（M2 闸门）

**类型**: feat
**提交**: f955652
**风险**: LOW

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/telemetry.dart | +47/-2 | `TelemetryFunnel` 新增 `firstOpen`（次日留存 D0 锚）与 `appOpen`（每次启动，props.day_offset=日历日偏移）；新增 `captureOpen`（录入漏斗「打开」起点，W7-8 缺口）；`TelemetryMetricName` 新增 `captureOpenToConfirmMs` / `frameRasterMs` / `frameDropped` / `syncCycleMs` 四个指标名常量；文件头补北极星三项口径说明 |

### 影响范围
- **API**: 仅新增常量（纯 Dart 静态字符串），无破坏性；事件名是壳层埋点接线的契约——apps/mobile 同提交按这些名字接线并有 `northstar_telemetry_test` 防回归断言。
- **跨模块**: 同提交大改 `apps/mobile`（`lib/telemetry/frame_telemetry.dart` 新增 +117 行、`bootstrap.dart` +104、`router.dart` +61）、`apps/mobile/lib/sync/sync_coordinator.dart` 指标名一并收敛。
- **数据模型**: 无。
- **配置**: 无。

---

## [2026-11-16] W7-8 同步一期：遥测抽象与隐私闸门入包

**类型**: feat
**提交**: d13c27d
**风险**: MEDIUM

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/telemetry.dart | +198 | 新增 `TelemetryKind` / `TelemetryEvent`（JSONL 统一格式，坏行 fromJson 返 null）/ `TelemetryFunnel`（13 个漏斗事件名）/ `TelemetryMetricName` / `TelemetryPrivacy`（13 键黑名单 + 非标量剔除 + 字符串截 64）/ `TelemetryService`（funnel/metric/crash/flush，永不阻塞纪律） |
| lib/core_domain.dart | +6/-2 | barrel 导出 `src/telemetry.dart`；头注声明遥测属主收敛——壳层按公开路径引用，不再经 src 实现路径 |

### 影响范围
- **API**: 包级新增 6 个导出符号；`TelemetryPrivacy` 是所有实现方的强制闸门（合规要求）。
- **跨模块**: 同提交 `apps/mobile` 落地 `FileTelemetryService`/`NoopTelemetryService` 实现与 main 崩溃钩子/漏斗接线；`core_db` 新增 `sync_outbox_writer.dart` +177 行（全写路径同事务入队）；`feature_sync` 新增 SupabaseSyncBackend。
- **数据模型**: 无（遥测本地 JSONL 落盘，不进 21 表）。
- **配置**: 无 dart-define 键变化。

---

## [2026-11-16] W5-6 同步引擎：拒绝分类回处理协议扩展（M1 功能项）

**类型**: feat
**提交**: 3022e4d
**风险**: HIGH

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/sync_engine.dart | +18 | `SyncOutboxStore` 接口新增 `drop(String outboxId)` 方法（与 `markAcked` 区分：drop 的条目未被服务端确认，仅停止重试）；`SyncRejectionReason` 枚举新增 `baseRevisionConflict('base_revision_conflict')`（乐观校验失败，出网作废经 pull 采纳服务端行）与 `tombstoneConflict('tombstone_conflict')`（墓碑拒绝复活必须在服务端强制，否则删端双端分叉） |

### 影响范围
- **API**: **接口破坏性扩展**——`SyncOutboxStore` 新增抽象方法，所有实现（含测试 Fake）必须补实现；拒绝枚举新增两个值改变 push 回执分类语义。
- **跨模块**: 同提交 `feature_sync`（新包）实现 `LocalSyncEngine` +803 行与拒绝分类回处理；`core_db/lib/src/dao/entry_line_repository.dart` +4/-2 修复投影联动误传 date；`apps/mobile` 壳装配与语音 Fake 链路大改。
- **数据模型**: 无新列；`tombstoneConflict` 强化既有 deletedAt 墓碑语义的服务端执行点。
- **配置**: 无。

### 回滚指南
- 回滚: `git revert 3022e4d`（仅取 core_domain 部分则 `git checkout 3b1f64c -- packages/core_domain/lib/src/sync_engine.dart`，但需同步回退 feature_sync 实现侧）
- 检查文件: `packages/core_domain/lib/src/sync_engine.dart`、`packages/feature_sync/lib/src/local_sync_engine.dart`（`drop` 调用点与拒绝分类 switch）
- 副作用: 回滚后 baseRevision/tombstone 冲突会退化为 `unknown` 拒绝，feature_sync 的「冲突四用例」测试与双端收敛保证失效；墓碑复活防护仅剩本地闸门。

---

## [2026-11-16] W1 环境与地基：core_domain 初建（31 例单测）

**类型**: feat
**提交**: 3b1f64c
**风险**: HIGH

### 变更文件
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/hlc.dart | +342 | `Hlc` 定宽编码（13:6:12，字典序=全序，修复「999>1000」隐藏 bug）+ `HlcClock` 发号器（now/recv 语义、counter 进位、回拨 >60s 告警） |
| lib/src/entry_line.dart | +232 | `EntryLine` + `LineType`/`LineDirection`/`LineStatus`；amount 恒非负、confidence ∈ [0,1] 构造期校验 |
| lib/src/entry.dart | +191 | `Entry` + `EntryKind`/`EntrySource`/`EntryStatus`；date 本地日历日构造期校验 |
| lib/src/sync_engine.dart | +271 | `SyncEngine` 三方法抽象、`OutboxEntry`/`SyncOutboxStore`、push/pull 结果值对象、`ConflictClass` 七类矩阵 |
| lib/src/common.dart | +136 | `SyncMeta` 公共列值对象（toRowJson/fromRowJson 平铺 snake_case）+ 日历日工具 + `kCurrentSchemaVer` |
| lib/src/repository.dart | +85 | `EntryRepository`/`EntryLineRepository` 接口 + `MoneyLineImmutableException` |
| lib/core_domain.dart | +14 | 包级 barrel |
| test/hlc_test.dart | +447 | 31 例：定宽编码/字典序=时间序/解析往返/now/recv/进位/回拨/长会话全序不变量 |
| pubspec.yaml、.gitignore、.metadata、CHANGELOG.md、LICENSE、README.md、analysis_options.yaml | +116 | 包脚手架 |

### 影响范围
- **API**: 包全量 API（40 个导出符号）于此提交定型；后续提交均为增量。
- **跨模块**: 本提交是整仓初建——同提交创建 `core_db`（Drift 21 表，`SyncColumns` 与 `SyncMeta` 对齐）、`ui_kit`、`apps/mobile`、`server/supabase`（0001_init.sql）、CI；core_domain 是其中唯一零依赖层。
- **数据模型**: 21 表 schema v1 与本包实体/公共列一字不差对齐（W1 冻结）。
- **配置**: pub workspace 分包结构建立。

### 回滚指南
- 回滚: `git revert 3b1f64c` 不可行——它是后续全部提交的祖先，回滚等于删除领域层；如需回退个别文件用 `git checkout 3b1f64c -- packages/core_domain/` 后跑全仓测试。
- 检查文件: 全部 7 个 lib 文件与 test/hlc_test.dart。
- 副作用: HLC 全序、facet 拆行、墓碑语义是同步正确性的地基；任何回退必须连带 server/supabase 迁移与 core_db schema 一起评估。
