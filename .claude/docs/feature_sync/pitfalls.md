# pitfalls — 同步域坑点

## 1. push 被拒必须「立即采纳服务端现值」，等 pull 永不收敛（最关键）

`hlcNonMonotonic` / `baseRevisionConflict` / `tombstoneConflict` 三类拒绝的处置是 drop 出网项 + **马上 `fetchRow` 把服务端现值覆盖本地行**（`_adoptServerRow`）。如果只 drop 等 pull：本地行的 hlc 仍比服务端新，pull 时 LWW 惜败——本地永远保留被裁决作废的脏值，双端分叉。服务端是 LWW/墓碑的权威仲裁者，裁决已发生，本端 hlc 更新也属败者。

## 2. LWW / 冲突矩阵要点（§6.5）

- **比较一律用定宽 hlc 字符串 `compareTo`**：字典序=时间全序（13:6:12 定宽编码保证）。同刻决胜已编码在 device 段里，不要再写「先比毫秒再比 counter 再比 device」的展开逻辑——InMemory backend 的服务端单调准入按 (physicalMs, counter) 严格递增判定，与仲裁是两回事。
- **墓碑恒胜，与 hlc 新旧无关**：「删后编辑保持删除胜出」。任一方为墓碑 → 删除胜；双方皆墓碑才走 LWW。引擎在 `_applyOne` 里本地墓碑直接挡下（不经 resolve），服务端 push 校验同样拒绝复活（tombstoneConflict）。
- **todo.done set 胜 + done_at 只前进**：并发 set vs unset → set 胜（勾选永不丢失）；双 set 合并取较大 done_at；取消完成仅无并发时生效。合并结果走 `ConflictWinner.merged` 落库。
- **append-only 的「并集」是行级并存**：不同行各存（结构层免冲突）；**同 id 行分歧仍按 LWW 兜底**——不要以为 append-only 表无冲突。
- **facet 拆行免冲突发生在拆行层**（§5.3，core_db）：不同 facet 行天然不同 id，不经 resolve；resolve 只兜同 facet 行同字段并发。
- `immutableMoney` 类在目录里没有表用它——金额行不可变由 core_db 仓库守卫强制，见第 6 条。

## 3. 游标单调是三层对齐的，动任何一层都会破坏增量语义

服务端 `GREATEST(v_cursor, v_max_hlc)`（0002_sync_rpc.sql）、InMemorySyncBackend 行预算 break 前 clamp、引擎侧「严格大于才推进」。历史 bug：引擎用「不等于」守卫，水位补投的低 hlc 迟到行把本地游标**拉回**，下轮整段重投已投递区间。修改游标推进逻辑时三处必须同改，且任何「本批最大 hlc」都可能低于既有游标（补投场景），必须 clamp。

## 4. LocalLoopbackBackend 缺省的含义

无凭据时全 app 用的就是它：push 逐条立即 ack（revision=本地递增序，**幂等重放**）、pull 恒空、fetchRow 恒 null、registerDevice 进内存表（进程生命周期）。含义：

- 出网队列照常清空——pending=0 不代表「已上云」，只代表「本设备即远端」；
- 装上凭据切到 Supabase 后，这批本地 revision 与服务端 BIGSERIAL 无连续性——首次真同步靠 baseRevision=null 的行直接接受 + 服务端重新签发，无迁移断层；
- 它对 LocalSyncEngine 是透明替换，测试里不要依赖 `pendingCount` 判断「服务端状态」。

## 5. 凭据切换（dart-define）

- 键名：`SLIMCA_SUPABASE_URL` + `SLIMCA_SUPABASE_ANON_KEY`（apps/mobile/lib/sync/sync_backend_factory.dart 的 `String.fromEnvironment` const 读取，AOT 常量折叠）。
- **任一缺失 → LocalLoopbackBackend**，静默降级、无报错——排查「为什么没同步」先查构建命令是否带了两个 define。
- 切换无需改代码，仅构建参数；运行期不可切换（const）。文档/代码禁止写真实 key，一律占位符。
- 设备吊销（服务端 devices.revoked_at）：RPC 前置校验直接 RAISE，客户端表现为 protocol 异常——不是网络问题。

## 6. 金额行不可变有一个窄例外

confirmed 后的 money 行（entry_lines）不可变由 core_db 仓库抛 `MoneyLineImmutableException`。引擎侧例外：修正链的**状态位迁移**（active→superseded/void，金额事实不变）必须放行——`_isLineStatusOnlyTransition` 逐列比对 10 个事实列（entry_id/type/amount/direction/ledger_id/category_id/currency/confidence/payload/correction_of）全部一致才降级为通用部分列更新。改 factKeys 清单=改协议边界，两端语义要同步。

## 7. 幂等缓存只存 ack 不存 rejection

服务端（InMemory 与 0002 RPC 一致）：同一 outbox_id 重试命中幂等账 → **原回执重放**；但拒绝不缓存——同一 outbox_id 重试必须重新校验（rowMissing 的父行补上后重试应转正）。客户端复刻这套语义时别把 rejection 也缓存（过期拒绝被永久重放，出网队列无法收敛）。

## 8. schema_ver 兼容是双向不对称的

- push 方向：本端 payload 超档 → 服务端拒 `schemaVerRejected` → 引擎 drop 作废（本端永不理解该行）。
- pull 方向：远端行超档 → **确定性跳过但游标照常推进**（不阻断后续行、不重拉）。
- 未知列：通用落库只更新载荷出现的已知列（老客户端忽略新列）。加列不改 schema_ver 语义；破坏性变更才 bump。

## 9. rowMissing 的 upsert/delete 处置不同

delete 目标行不存在 = 删除幂等完成，drop；upsert 父行缺失 = **暂缓保留**（下轮重试，父行 ack 后转正）。push 循环的终止条件依赖这个区分：全暂缓批（无 ack 且拒绝全 rowMissing/unknown）才 break。把 upsert 也 drop 掉=子行永久丢失。

## 10. HlcClock 必须共享同一实例

引擎构造参数 `clock` 缺省会自建一个——bootstrap 必须显式传 UI 写路径用的那一个。两个时钟实例各自维护 counter/墙钟，recv 的跳变跟不上对方，定宽全序退化，LWW 结果错乱。引擎只调 `recvEncoded`，永不调 `now`（发戳是 UI 写路径的职责）。

## 11. 暂态与确定性失败的分类决定游标

父行未到（StateError 类）= 暂态：该表游标停在本条之前，下轮重拉；坏 JSON/缺主键/超档/编码非法 = 确定性：跳过但游标推进。误把确定性当暂态会死循环重拉（由 maxPullRounds 兜底但白耗），误把暂态当确定性会永久丢行。`_guard` 把意外的 ArgumentError/StateError 保守按暂态处理——新增异常类型时先归类再处理。

## 12. InMemory pull 的双轨资格是收敛测试的前提

只按 `hlc > 游标` 过滤会漏「他端在本端游标推进之后才上送的低水位行」（双端各离线写 50 条必现）。投递簿补投（未投递过的行投一次）+ 重投递经 LWW 安全去重。改 pull 过滤逻辑先跑 `offline_regression_test` ②（低 hlc 迟到行收敛）。
