# server-supabase — 托管 Supabase 服务端（数据层/云端）

> 源码：`server/supabase/`（纯 SQL 迁移 + README，无 Dart 代码）。
> 职责：承载 Slimca 的同步真值——表结构（RLS 行级隔离）+ 同步协议 RPC（push/pull/设备注册）。
> 定位：云端数据层。客户端唯一对接方为 `packages/feature_sync` 的 `SupabaseSyncBackend`。

## 模块边界

- **做什么**：按 `migrations/` 定义 19 张云表（14 同步真值 + devices/attachments + sync_ops + 0002 附加的 sync_pull_watermarks / sync_table_registry）；提供 3 个 SECURITY DEFINER RPC 与 1 个 REST 单行直读通道；RLS 按 `user_id = auth.uid()` 行级隔离。
- **不做什么**：投影/统计/余额（§6.1 原则 3，永不上云）；主键生成（id 由客户端生成 UUIDv7）；同步语义列（hlc/revision/时间戳由客户端写入，服务端只在 overlay 层签发 revision/user_id/device_id）；墓碑 90 天 GC、历史清理（后续独立迁移）。
- **演进纪律**：已应用的迁移不可修改（§6.4 冻结期禁破坏性迁移），新变更一律新增 `NNNN_*.sql`。

## 目录与文件

```
server/supabase/
├─ README.md                  # 部署/初始化/本地栈操作手册（仓库内，偏运维）
└─ migrations/
   ├─ 0001_init.sql           # schema v1：17 表（14 同步真值 + devices/attachments/sync_ops）+ RLS 策略骨架（W1）
   └─ 0002_sync_rpc.sql       # 3 个同步 RPC + 投递水位表 + 表注册表 + revision 索引（W7-8）
```

## 关键事实速查

| 项 | 值 |
|---|---|
| 表总数 | 19（Studio 可见；`sync_table_registry` RLS 无策略=全拒直读） |
| RPC | `sync_push_batch` / `sync_pull_changes` / `register_device`（SECURITY DEFINER，仅 authenticated） |
| 幂等键 | `sync_ops.outbox_id` 唯一键（= 客户端 outbox.id） |
| 权威 revision | `sync_ops.op_seq BIGSERIAL`，接受即回写业务行 |
| 客户端凭据注入 | `--dart-define=SLIMCA_SUPABASE_URL / SLIMCA_SUPABASE_ANON_KEY`（缺省回退本地回环后端） |
| 真实端点联调 | 待用户凭据；当前测试全走 mock transport（禁真实网络） |

## 调用方

- `packages/feature_sync/lib/src/supabase_sync_backend.dart` — 线协议唯一客户端实现；
- `packages/feature_sync/lib/src/supabase_rpc_transport.dart` — `POST /rest/v1/rpc/<fn>` 传输 + 异常三分类（network/timeout/protocol）；
- 装配：`apps/mobile/lib/sync/sync_backend_factory.dart`（dart-define 齐→托管，缺→`LocalLoopbackBackend`）。

## 详细文档

- [api-rpc.md](api-rpc.md) — 3 个 RPC 的签名/参数/返回/校验序/拒绝分类，REST 单行直读，错误码
- [data-model.md](data-model.md) — 云表 ↔ 端侧 Drift 表对应、类型映射、公共列约定、RLS 与索引
- [pitfalls.md](pitfalls.md) — 迁移顺序、RPC 命名错位、HLC 配合、水位/游标单调等坑点
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（真实 git 提交分析）

相关模块：[../core_db/README.md](../core_db/README.md)（端侧 21 表 Drift schema、outbox 写路径）、[../feature_sync/README.md](../feature_sync/README.md)（引擎与后端契约）。
