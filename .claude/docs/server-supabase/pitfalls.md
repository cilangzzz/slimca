# 坑点 — server-supabase

> 排序按跨模块价值。前 3 条直接决定真实端点联调成败，第 4-6 条是同步正确性语义。

## 1. RPC 命名错位：客户端调 `push_batch`，服务端叫 `sync_push_batch`（HIGH，待联调必炸）

- 服务端函数：`sync_push_batch` / `sync_pull_changes` / `register_device`（0002 头注释声称「与客户端冻结命名一致」——**实际不一致**）。
- 客户端常量（`supabase_sync_backend.dart`）：`pushRpcName = 'push_batch'`、`pullRpcName = 'pull_changes'`、`registerRpcName = 'register_device'`。
- 测试全绿掩盖了它：mock 的 `FakeSupabaseRpcServer` 按客户端命名镜像（`supabase_fakes.dart`），全程无真实网络；真实端点上 push/pull 会 PGRST202（function not found），仅 register_device 恰好同名可用。
- 处置：联调前二选一——改客户端三常量为带前缀名，或服务端加同名别名函数；改哪侧都行，但**两侧 + fakes 镜像要一起改**。

## 2. 迁移顺序：0002 必须在 0001 之后；已应用迁移禁改

- `0002` 的 DO 块从 `information_schema` 按 0001 实际表结构生成列白名单，0001 未先应用会 RAISE EXCEPTION（完整性断言兜底，但仍应按序 `db push`）。
- CLI 按文件名字典序应用；`supabase db reset` 才能本地重放，托管库**没有 reset**——回滚要新增反向迁移或从备份恢复。
- `config.toml` 与 supabase CLI 版本耦合：仓库未预置（首次 `supabase init` 生成后须提交）；CLI 版本不匹配会解析失败。
- 冻结期纪律（§6.4）：v1-v3 禁破坏性迁移；settings 表上云等新需求一律增量迁移新文件。

## 3. SECURITY DEFINER 的属主纪律：每条语句必须显式带 `user_id = auth.uid()`

- RPC 绕过 RLS，若漏一行属主过滤即是越权面。既有实现的关键防线：行锁读 `WHERE id=$1 AND user_id=$2 FOR UPDATE`；父行存在性查他用户行无效；upsert `ON CONFLICT … WHERE <t>.user_id = auth.uid()`；跨用户 id 占用显式拒绝（UUIDv7 撞 id 概率趋零，此为纵深防御）。
- 新增 RPC 时照抄该模式，勿依赖 RLS 兜底（definer 下 RLS 不生效）。

## 4. pull 双轨资格与「单调只进不退」（W7-8 真实回归教训）

- 资格 = `hlc > 游标 OR revision > 投递水位`：只按游标会漏「他端离线迟到的低 hlc 行」（投递洞）；水位轨用 op_seq 接受序兜底。
- 服务端输出游标取 `GREATEST(入参游标, 本批 max hlc)`——水位补投的迟到行 hlc 低于既有游标，直接取本批 max 会**回退**游标，下轮整段重投已投递区间。
- 客户端引擎（LocalSyncEngine）侧同规则：本地游标「严格大于才推进」；三层（SQL / InMemory backend / 引擎 + fakes 镜像）必须一致改——W7-8 集成修复就是三层一起 clamp 的。
- 改 pull 语义时先跑 `packages/feature_sync/test/offline_regression_test.dart`（飞行模式 ①② 两场景）。

## 5. push 校验的次序与「逐条拒绝、不整批回滚」

- 校验序固定：结构 → 表白名单 → schema_ver → 幂等重放 → hlc 单调 → todos set 胜 → baseRevision → 墓碑 → 父行 → id 占用。乱动次序会改变拒绝 reason（wire 契约，客户端按 reason 分类处置）。
- 整批只有写区（sync_ops + 行 upsert）包异常护栏：意外约束冲突（如最小 delete 快照缺 NOT NULL 列）单条归 `unknown` 拒绝，**不影响同批其他 op**。
- `base_revision` 用 `::numeric` 而非 `::bigint`：jsonb number 可能是小数/巨数，文本强转 bigint 会炸整批；schema_ver 比较直接用 jsonb 数值比较同理。
- 迭代级状态必须复位：循环开头 `v_op_seq := NULL`——`ON CONFLICT DO NOTHING` 空返回不赋值，残留旧 op_seq 会让「并发重复重放」分支失效、以旧值当 revision 写行。

## 6. HLC 比较语义：服务端只比 phys:ctr 两段，正则才是全约束

- push 的单调校验用 `split_part(hlc,':',1/2)::bigint` 比较（物理钟+逻辑钟），**不含节点段**——同节点同毫秒多 op 靠逻辑钟递增保证严格递增；节点段合法性由 CHECK 正则 `^[0-9]{13}:[0-9]{6}:[0-9A-Fa-f]{12}$` 把关。
- 客户端生成 hlc 必须满足定宽（否则 push 结构层即拒 `unknown`）；服务端从不生成/改写 hlc。
- todos set 胜（勾选永不丢失）：并发 unset（baseRevision 不命中现值）时服务端保留 `done_at` 并 **ACK 而非拒绝**——客户端别把该 ACK 当「取消成功」。

## 7. payload 契约：未知键忽略、但 id/hlc 必须与信封一致

- `jsonb_populate_record(NULL::<table>, $1)` 自动丢弃 payload 未知键（新客户端新列→老服务端不炸）；但 `payload.id ≠ row_id` 或 `payload.hlc ≠ 信封 hlc` 是结构拒绝。
- op=delete 的 payload 可以是最小快照（只有 id/hlc/deleted_at）；缺 `deleted_at` 服务端补 now。**delete 走 upsert 语义**（幂等 upsert + ON CONFLICT），不是物理 DELETE——所有同步表行一旦入云只软删。

## 8. 凭据与端点：仓库无任何密钥，注入走 dart-define

- 凭据键名：`SLIMCA_SUPABASE_URL` / `SLIMCA_SUPABASE_ANON_KEY`（`apps/mobile/lib/sync/sync_backend_factory.dart`）；缺任一 → 回退 `LocalLoopbackBackend`（本地回环，同步功能静默降级而非报错——排查「同步没生效」先查 describeSyncBackend 状态行）。
- anon key 是客户端公钥，安全性全靠 RLS + RPC 内 auth.uid() 约束；**service_role key 永远不进客户端**。
- 文档/代码中不落真实项目 URL；托管项目 ref 用 `<PROJECT_REF>` 占位。
