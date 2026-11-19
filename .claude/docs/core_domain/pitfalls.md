# core_domain 坑点（跨模块）

> 排查同步/记账/统计类问题时优先阅读。多数坑点源于「三层同构」约定被某一侧破坏。

## 1. HLC 定宽编码是字典序=全序的唯一保证（13:6:12）

- 编码 `13位物理ms : 6位counter : 12位hex节点`，全部补零；**任何缺位/超宽输入一律拒绝**（`Hlc.parse` 抛 `FormatException`）。自行手拼 hlc 字符串（如 `${ms}:${counter}` 不补零）会让 SQLite/Postgres TEXT 比较的字典序与时间序错位——裸十进制下 `"999" > "1000"`，这正是定宽修复的 bug。
- 节点段统一**大写** hex；构造与 `parse` 都会规范化。若从 DB 直读绕过 `SyncMeta.fromRowJson`，遇到小写节点段的行不会报错但破坏编码唯一性约定。
- 节点标识 = UUIDv7 的**前 12 个 hex 字符**（`Hlc.nodeIdFromUuidV7`），不是完整 UUID。把 36 位 UUID 全文塞进 device_id 会在 `parse`/构造时直接抛错。
- 计数器单毫秒上限 999,999；耗尽时**物理 +1、counter 归零**进位。比较/排序逻辑不要假设「物理相同则 counter 更大者更新」跨进位边界成立。

## 2. 已确认 money 行的 amount 不可变——必须走修正链

接口只是注释约束，**强制点在各实现层**（`core_db` 的 `DriftEntryLineRepository.upsert`）。confirmed/edited 后的 money 行若原地改 amount/type/status，实现必须抛 `MoneyLineImmutableException`；唯一合法路径是 `EntryLineRepository.supersede(oldLineId, correction)`——同一事务内新增 correction 行（`correctionOf` 指向旧行）+ 旧行 status→superseded。上层 feature_ledger 修金额时走错路径（直接 upsert）会抛异常或破坏审计链。

## 3. amount 恒非负，正负语义在 direction

`EntryLine.amount` 为负直接抛错。expense=out / income=in；calorie=in、burn=out。**统计/汇总必须按 direction 计算**，不要按 amount 符号——按符号求和恒为正、会把支出和收入加在一起。

## 4. date 一律本地日历日 `yyyy-MM-dd`，不是 UTC / ISO 时间戳

`Entry` 构造期校验并抛 `ArgumentError`。生成用 `formatCalendarDay(本地 DateTime)`，**不要用 `toIso8601String()`**（会带时间部分且 UTC 时带 Z 后缀，校验不过、聚合错日）。跨午夜补录「昨天的事」时 date 填事件归属日而非今天。

## 5. copyWith 的可空字段用 `_unchanged` 哨兵——传 null 是「置空」不是「不改动」

`Entry` / `EntryLine` / `SyncMeta.copyWith` 中可空字段（occurredAt/note/aiParseId/deletedAt/ledgerId/confidence/payload/correctionOf…）默认哨兵 `Object()` 区分两种意图：**显式传 null 会清空该字段**。把 `copyWith(note: xxx)` 误写成 `copyWith(note: maybeNull)` 会把备注静默清掉。软删墓碑经 `SyncMeta.copyWith(deletedAt: ...)` 改，不在实体层。

## 6. 枚举 wire 文本与 DB/服务端白名单一字不差

七个枚举（EntryKind/EntrySource/EntryStatus/LineType/LineDirection/LineStatus/OutboxOp）的 `wire` 值 W1 冻结，`fromWire` 未知值抛 `ArgumentError`。新增枚举值 = 同时改 Drift 层 + server 表白名单 + 各端 schema_ver 升档，否则旧端 `fromWire` 崩、服务端 schema_ver 校验拒收。

## 7. 业务行与 outbox 行必须同事务；drop ≠ markAcked

- `SyncOutboxStore.enqueue` 是**同步语义**，必须在业务写事务内调用（漏队 = 该变更永不出网，双端静默分叉）；core_db 的 `SyncOutboxWriter` 已封装该纪律。
- `drop`：条目**未被服务端确认**，只是不再重试（schema_ver 超档、baseRevision/tombstone 冲突、delete 幂等等——服务端已有更新版本，由 pull 采纳）。`markAcked`：服务端确认成功。把冲突条目误 markAcked 会让服务端权威行永远无法被本地采纳。

## 8. pull 游标只在整批落库成功后推进；hasMore=true 必须续拉

`SyncPullResult.nextCursors` 是「各表推进后的游标」——落库失败必须保持原游标重拉，否则丢变更。`hasMore=true` 时调用方循环 `pull` 直到 false，一次拉取只代表一批。游标语义是「严格大于才推进」：水位补投的低 hlc 迟到行若把游标回拉，会整段重投已投递区间（W7-8 曾修此 bug）。

## 9. 遥测必经 TelemetryPrivacy 闸门；error_type 可记、error message 禁入

实现方写入/上报前必须 `sanitizeProps`：黑名单键（raw/text/content/message/note/title/payload/stack/error…）剔除、非标量剔除、字符串截 64。`error_type`/`error_code` 是允许字段（错误**类型**），`error`/`message`/堆栈内容禁入。crash 只记 runtimeType 与堆栈帧数。给 props 顺手塞业务原文 = 合规事故（§3.9）。

## 10. 时钟回拨告警基于墙钟高水位；远端跳变不算回拨

`HlcClock._observeWall` 只在**墙钟自身后退**（且幅度 >60s）时触发 `onClockRollback`（边沿触发一次）。收到远端未来时间戳导致「墙钟落后于已见物理」是 recv 跳变的正常结果，不告警——给告警接入方排障时不要把这类场景当故障。

## 11. payload 撞名：EntryLine.payload ≠ OutboxEntry.payload

`EntryLine.payload` 是行级明细引用 JSON **串**（菜品/商户/MET 参数）；`OutboxEntry.payload` 是整行快照 JSON **串**（即对应实体 `toJson()` 的结果）。两者都是 String 而非 Map，嵌套层级不同；日志里看到 payload 先确认是哪一层的。

## 12. 上层实现接口时的三条硬纪律（§10.4）

实现 `EntryRepository` / `EntryLineRepository` / `SyncOutboxStore` / `SyncEngine` / `TelemetryService` 的新实现（测试 Fake、未来替换 PowerSync 等）必须遵守：① 删除一律软删墓碑，不物理删；② 写入携带 HLC 且单调（同步游标依赖 (updated_at)/(hlc) 索引）；③ 同步失败只影响状态提示，永不阻塞 UI。漏掉任何一条在真实双端场景都会静默分叉。
