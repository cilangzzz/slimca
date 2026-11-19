# Changelog - server-supabase

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。

---

## [2026-11-16] W7-8 同步一期：Supabase 后端（RLS+RPC 幂等）+ 全写路径 outbox 补课 + 遥测/raw_input 开关/IAP 骨架 + 软著与备案材料

**类型**: feat
**提交**: d13c27d
**风险**: HIGH

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| server/supabase/migrations/0002_sync_rpc.sql | +700 | 新增：3 个 SECURITY DEFINER RPC（sync_push_batch/sync_pull_changes/register_device）+ sync_pull_watermarks（per-device 投递水位）+ sync_table_registry（表白名单，cols 由 DO 块从 information_schema 生成）+ 14 张 `(user_id, revision)` 索引 + EXECUTE 权限收口（REVOKE PUBLIC/anon、GRANT authenticated）。校验链：结构/表白名单/schema_ver/幂等重放/hlc 严格单调/todos set 胜/baseRevision/墓碑拒绝复活/父行存在/跨用户 id 占用；pull 双轨资格 + 水位 GREATEST 单调 + 游标 `GREATEST(v_cursor, v_max_hlc)` 单调（W7-8 集成修复 1，治「二次同步无增量」回归） |
| server/supabase/README.md | +71/-9 | 补同步 RPC 语义章节：push/pull/register 线协议、拒绝三分类→引擎处置表、RLS 强化审计（决策 A/H）、投递水位补漏说明、待用户凭据边界 |

### 影响范围

- **API**: 服务端 RPC 表面从 0 → 3（幂等键=outbox_id 唯一键，权威 revision=BIGSERIAL op_seq）；客户端对接实现在同一提交：`packages/feature_sync/lib/src/supabase_sync_backend.dart`(+296)、`supabase_rpc_transport.dart`(+108，异常三分类 network/timeout/protocol)、`sync_config.dart`(+29)。
- **跨模块**: 同一提交大改多个模块（60 文件 +8149）——core_db 出网写路径补课（SyncOutboxWriter + TodoDao 四写路径 + seed 行入队）、feature_capture 录入全路径入队、core_domain TelemetryService、apps/mobile dart-define 装配（`SLIMCA_SUPABASE_URL`/`SLIMCA_SUPABASE_ANON_KEY`，缺省回退 LocalLoopbackBackend）。pull 游标单调修复为**三层对齐**：本迁移 SQL + `in_memory_sync_backend.dart`(+10) + `local_sync_engine.dart`(+8/-1) 必须同改。
- **数据模型**: 云端新增 2 张基础设施表（watermarks/registry）+ sync_ops 索引强化；既有 17 表结构未动。
- **配置**: 无服务端配置文件入库（config.toml 待首次 `supabase init` 生成）。

### 回滚指南（HIGH）

- 回滚: `git revert d13c27d`（会连带回滚客户端 SupabaseSyncBackend——RPC 表面与客户端常量须同进退）。
- 托管库额外步骤: revert 不回滚已应用的迁移，需手工 `DROP FUNCTION sync_push_batch(text, jsonb); DROP FUNCTION sync_pull_changes(text, jsonb, integer); DROP FUNCTION register_device(text, text, text, bigint); DROP TABLE sync_pull_watermarks; DROP TABLE sync_table_registry;`（保留 0001 的 17 表与数据）；本地库直接 `supabase db reset`。
- 检查文件: migrations/0002_sync_rpc.sql、packages/feature_sync/lib/src/supabase_*.dart、apps/mobile/lib/sync/sync_backend_factory.dart。
- 副作用: 回滚后双端同步仅剩 InMemory/Loopback 轨道；core_db outbox 写路径若保留而服务端 RPC 消失，outbox 会持续积压 pending（无出网口）。

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: feat
**提交**: 3b1f64c
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| server/supabase/migrations/0001_init.sql | +695 | schema v1 建库：14 同步真值表 + devices/attachments + sync_ops（BIGSERIAL op_seq + outbox_id 唯一键）+ 全表 RLS enable + `<t>_owner_all` 策略骨架（`auth.uid()` 用 `(SELECT …)` 包裹）；类型映射 TEXT↔TEXT、INTEGER↔BIGINT、REAL↔DOUBLE PRECISION；全表 hlc CHECK 正则；文件头注明 8 条总体设计决策与两侧对齐判断标注 |
| server/supabase/README.md | +108 | 部署手册：前置条件（Node≥20 + Supabase CLI）、首次 init、本地栈（start/db reset/stop + Studio 验证 19 表）、托管库 link/db push 流程、迁移与 Drift 对应、数据主权（pg_dump 迁出） |

### 影响范围

- **API**: 无 RPC（0002 才有）；REST 直读 + RLS 自本迁移起可用。
- **跨模块**: 本提交为 monorepo 首建（189 文件 +34710），同时创建 packages/core_db 的 Drift schema v1（21 表）——云端 0001 与端侧 Drift 以同一份设计文档 §5.1 手工对齐，此后任何一侧改列须检查另一侧（对齐判断标注见迁移文件头）。
- **数据模型**: 云端 17 表首次落库；本地件 5 张（day_summary/ai_parses/sync_outbox/sync_cursors/settings）明确不建服务端表。
- **配置**: 无（config.toml 未入库，README 记录生成步骤）。

### 回滚指南

不适用（初始创建，直接删文件即可；托管库若已应用需 drop 全部表并清 supabase_migrations，涉及数据丢失，先 pg_dump）。
