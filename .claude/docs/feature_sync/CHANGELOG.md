# Changelog - feature_sync

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。

---

## [2026-11-16] W7-8 同步一期：Supabase 后端（RLS+RPC 幂等）+ 全写路径 outbox 补课 + 遥测/raw_input 开关/IAP 骨架 + 软著与备案材料

**类型**: feat
**提交**: d13c27d
**风险**: HIGH

### 变更文件（feature_sync 范围，12 文件 +2610/-5）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/supabase_sync_backend.dart | +296 | 新增：SyncBackend 的托管 Supabase RPC 实现（push_batch/pull_changes/register_device 三 RPC + REST 单行 fetchRow + 响应结构守卫 → protocol 异常） |
| lib/src/supabase_rpc_transport.dart | +108 | 新增：SyncRpcTransport 传输缝（TimeoutException→timeout、PostgrestException→protocol、ClientException→network 三分类） |
| lib/src/sync_config.dart | +29 | 新增：连接参数对象（宿主注入，本包不读环境变量） |
| lib/src/local_sync_engine.dart | +8/-2 | pull 自算游标改「严格大于才推进」（W7-8 集成修复：水位补投低 hlc 迟到行原会把游标拉回，破坏增量语义） |
| lib/src/in_memory_sync_backend.dart | +10 | pull 行预算 break 前游标 clamp（与 SQL 侧 GREATEST 对齐） |
| lib/feature_sync.dart | +7/-1 | barrel 导出新增三个 Supabase 相关文件 |
| pubspec.yaml | +6 | 新增依赖 supabase ^2.13.4（纯 Dart core 包，锁 2.13.x 因 2.14+ 要求 Dart ≥3.9）、http ^1.2.0 |
| test/supabase_contract_test.dart | +703 | 线协议编解码、六类 reason 映射、真实传输栈异常三分类、幂等线级契约 |
| test/supabase_engine_chain_test.dart | +585 | SupabaseSyncBackend × FakeSupabaseRpcServer 全链路双轨收敛 |
| test/supabase_fakes.dart | +579 | ScriptedRpcTransport / FakeSupabaseRpcServer 测试替身 |
| test/offline_regression_test.dart | +261 | 飞行模式回归：分区→离线写→补传收敛；低 hlc 迟到行补漏收敛 |
| test/test_support.dart | +23/-2 | 夹具修复：SyncDeviceFixture 开夹具即清空 24 条 seed 出网项（seed 真实墙钟戳污染 hlc 全序曾致 21 用例误判） |

### 影响范围

- **API**: 新增 `SupabaseSyncBackend` / `SyncRpcTransport` / `SupabaseRpcTransport` / `SyncConfig` 公开面；RPC 函数名常量 `pushRpcName='push_batch'`、`pullRpcName='pull_changes'`、`registerRpcName='register_device'` 与服务端迁移 0002 冻结命名一致。
- **跨模块**: 同一提交还改了 `server/supabase/migrations/0002_sync_rpc.sql`（+700，RLS + SECURITY DEFINER RPC + 幂等/双轨投递水位）、`core_db`（SyncOutboxWriter 全写路径补课 + TodoDao/seed 行入队）、`core_domain`（TelemetryService 系列）、`feature_capture`（录入网关入队）、`apps/mobile`（sync_backend_factory.dart +66 / sync_coordinator.dart +113 / telemetry_sync_backend.dart +87 装配层）。全部 60 文件 +8149/-157。
- **数据模型**: 服务端新增 devices/sync_ops/sync_delivery 表语义（0001 已建表、0002 加 RPC）；客户端 schema 无变更。
- **配置**: 新增 dart-define `SLIMCA_SUPABASE_URL` / `SLIMCA_SUPABASE_ANON_KEY`（缺省缺失→LocalLoopbackBackend，静默降级）。

### 回滚指南（HIGH）

- 回滚: `git revert d13c27d`（注意会连带回滚 server 迁移 0002、core_db SyncOutboxWriter 与壳层装配——revert 后同步退回 W5-6 的 InMemory/Loopback-only 状态）。
- 检查文件: `server/supabase/migrations/0002_sync_rpc.sql`、`packages/core_db/lib/src/outbox/`、`apps/mobile/lib/sync/`、`packages/feature_sync/lib/src/supabase_*.dart`。
- 副作用: 已部署环境若执行过 0002 迁移，回滚代码不会回滚数据库，需手工 drop RPC 函数；outbox 中已入队的行在回滚版只能靠 Loopback 本地 ack 消化，切回 Supabase 后重放幂等。

---

## [2026-11-16] W5-6 记账完整化+语音(Fake链路)+健身+同步引擎（M1 功能项）

**类型**: feat
**提交**: 3022e4d
**风险**: HIGH

### 变更文件（feature_sync 范围，14 文件 +3801/-55）

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/local_sync_engine.dart | +803 | 新增：LocalSyncEngine 编排（push 循环 maxPushRounds/全暂缓终止 → pull 续拉 maxPullRounds → 拒绝分类回处理 → §6.5 矩阵 resolve → day_summary 自愈；分区只降级不抛出） |
| lib/src/in_memory_sync_backend.dart | +412 | 新增：服务端校验矩阵 Fake（幂等键=outbox.id 原回执重放、hlc 严格递增、baseRevision 乐观校验、墓碑拒复活、父行存在性、schema_ver 超档）+ 投递簿补漏 + 分区/恢复 + fetchRow 采纳源 |
| lib/src/drift_sync_local_store.dart | +236 | 新增：pull 落库（entries/entry_lines 走 core_db 仓库同校验；其余表通用 upsert 未知列过滤）/游标/revision 回写/day_summary 脏自愈 |
| lib/src/sync_table_catalog.dart | +185 | 新增：14 张真值表策略登记（conflictClass/rank/parentTable/ownDateKey/marksAllDatesDirty）+ 落库依赖序 |
| lib/src/sync_backend.dart | +103 | 新增：SyncBackend 四方法抽象 + SyncBackendException + DeviceRegistration |
| lib/src/local_loopback_backend.dart | +90 | 新增：无服务端缺省装配（push 全 ack、pull 恒空、fetchRow null） |
| lib/src/drift_sync_outbox_store.dart | +85 | 新增：SyncOutboxStore 的 Drift 实现（enqueue 同事务契约/出队序 created_at→hlc） |
| lib/src/device_registry.dart | +99 | 新增：设备注册（本地 devices 引用行幂等 upsert + 服务端登记，分区时本地照常） |
| lib/feature_sync.dart | +36/-5 | barrel 收敛 11 个导出 + DI 契约注释 |
| pubspec.yaml | +48/-55 | workspace 依赖声明（core_domain/core_db/drift） |
| test/local_sync_engine_test.dart | +931 | 冲突四用例真实执行 + ⑤双端各离线写 50 条三轮收敛 100% 一致 + 读写路径回归 7 例 + resolve 单测 3 例 |
| test/sync_backend_test.dart | +359 | InMemory 校验矩阵 / pull 语义 / Loopback 缺省三组 |
| test/test_support.dart | +457 | 双设备夹具 + HLC 虚拟墙钟 |
| test/feature_sync_test.dart | -12 | 删除 W1 占位 smoke 测试 |

### 影响范围

- **API**: 本包核心 API 面全部在此建立（LocalSyncEngine/SyncBackend/双 Store/DeviceRegistry/目录）。
- **跨模块**: 同一提交还改了 `core_domain`（SyncEngine/OutboxEntry/ConflictClass/HlcClock 契约 +31 例单测）、`core_db`（schema v1 部分列/仓库）、`feature_plan`（健身+todo）、`feature_capture`（语音 Fake 链路）等。全部 84 文件 +14787/-2768。
- **数据模型**: 消费 core_db 的 sync_outbox/sync_cursors/devices 三同步设施表（同提交建立）。
- **配置**: 包加入 pub workspace。

### 回滚指南（HIGH）

- 回滚: `git revert 3022e4d`（会整体移除本包核心与 core_domain 契约——需连同依赖它的壳层装配一并回滚，实际等于退回 W1）。
- 检查文件: 本包全部 lib/src、`packages/core_domain/lib/src/sync_engine.dart`、`apps/mobile/lib/app/bootstrap.dart`。
- 副作用: revert 后一切写路径若无 outbox 入队则数据永不上送；HLC 公共列仍在 schema 中（无害）。

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: chore
**提交**: 3b1f64c
**风险**: LOW

### 变更文件（feature_sync 范围，9 文件 +160）

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +55 | 包脚手架（workspace 成员、SDK ^3.8.0） |
| .gitignore / .metadata / analysis_options.yaml / LICENSE / CHANGELOG.md | +46 | 标准包文件 |
| lib/feature_sync.dart | +5 | 空 barrel 占位 |
| test/feature_sync_test.dart | +12 | 占位 smoke（W5-6 移除） |
| README.md | +39 | flutter create 生成占位 |

### 影响范围

- **API**: 无（仅包骨架，无同步代码）。
- **跨模块**: 仓库初始提交，全部 189 文件 +34710（单仓分包结构、core_db schema v1、core_domain HLC 层、CI、server/supabase/migrations/0001_init.sql +695 均在此提交建立）。
- **数据模型**: 无本包侧变更（消费侧表在 core_db）。
- **配置**: pub workspace 建立。

---
