# core_domain 可复用编码套路

> 本包虽小，但「单侧定义双侧生成」约定让每类改动都有固定套路。改错位置 = 同步协议漂移。

## 1. wire 枚举（新增枚举值 / 新枚举）

所有持久化枚举用 `wire` 文本 + `fromWire` 单向映射，不存 Dart 枚举名：

```dart
enum EntryKind {
  food('food'), ...
  const EntryKind(this.wire);
  final String wire;
  static EntryKind fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 EntryKind: $value'),
      );
}
```

新增值三步：① 本包加枚举成员（wire 文本勿改既有值）；② `core_db` 对应 Dao/迁移的合法值集合；③ server 迁移的表白名单 + `schema_ver` 升档。参见 [../core_db/README.md](../core_db/README.md)。

## 2. copyWith 哨兵（新增可空字段）

可空字段区分「不改动」与「置 null」，用包内统一哨兵：

```dart
static const Object _unchanged = Object();

EntryLine copyWith({Object? payload = _unchanged, ...}) =>
    EntryLine(..., payload: identical(payload, _unchanged)
        ? this.payload : payload as String?, ...);
```

非可空字段用普通 `??`。字段加进构造体后记得同步 `toJson`/`fromJson`（见套路 3）。

## 3. 新增实体字段（三层同构检查单）

一个业务字段必须同时出现在四处，键名按 camelCase→snake_case：

1. 领域实体字段 + 构造校验（本包 `entry.dart` / `entry_line.dart`）；
2. `toJson()` 键 + `fromJson()` 解析；若属公共列语义则并入 `SyncMeta`；
3. `core_db` 对应 Table 列 + （若是同步真值表）`SyncColumns` 已覆盖的公共列不必重复；
4. server 迁移同名列（行快照按 JSON 键直存，缺列 = push 被服务端结构校验拒收）。

行快照 payload 结构 = `entity.toJson()`，缺任何一侧键名会在服务端结构校验处暴露，但本地 Drift 侧漂移只会表现为静默丢数据。

## 4. HLC 发号（写路径标准动作）

```dart
final clock = HlcClock(deviceId: Hlc.nodeIdFromUuidV7(uuidV7));
final h = clock.now();                    // 本地事件
await repo.upsert(entry.copyWith(meta: meta.copyWith(hlc: h.format())));
await outbox.enqueue(entry);              // 抽象接口（core_domain SyncOutboxStore），实现见套路 5
```

- 合并远端用 `clock.recv(Hlc.parse(remoteHlc))` 或 `recvEncoded(remoteHlc)`；
- 软删墓碑的 hlc 是**本次删除操作**的时间戳：`repo.softDelete(id, hlc: clock.now().format())`；
- 同一事务内取「刚签发」值用 `clock.lastIssued`，不要二次调 `now()`（会推高 counter）。

## 5. 同事务入队（outbox 纪律）

业务行 + outbox 行**必须同一事务**，enqueue 是同步语义而非异步通道：

```dart
await appDb.transaction(() async {
  await dao.upsertRow(row);
  // payload/op/hlc 不手工传：enqueueRow 读回该行最终状态动态构建，
  // 读不到行即抛错回滚（防止「本地已写、出网指空」）
  await syncOutboxWriter.enqueueRow('entries', id);
});
```

漏队 = 变更永不出网（静默分叉）；只有入队后异常才可能「本地已写、出网缺失」，测试可断言 pendingCount。参考实现：core_db `SyncOutboxWriter`。

## 6. 实现一个 core_domain 接口（新实现检查单）

为新端/测试 Fake 实现五个接口时逐条核对（语义出处见 [pitfalls.md](pitfalls.md) 第 12 条）：

1. 删除 = 软删墓碑（`deletedAt` + 新 hlc），不物理删；
2. 写入 HLC 单调，遵守定宽编码；
3. confirmed money 行 upsert 拦截 → 抛 `MoneyLineImmutableException`，修正走 `supersede`；
4. `SyncOutboxStore.drop` 与 `markAcked` 分开（drop 的条目未被服务端确认）；
5. `SyncEngine.pull` 落库成功才推进游标、`hasMore` 循环拉；
6. `TelemetryService` 先过 `TelemetryPrivacy.sanitizeProps`，方法内部兜底不抛。

## 7. 冲突仲裁按 ConflictClass 分发

SyncEngine 实现按 `ConflictClass`（七类）选择策略，**不按表名硬编码**——新表接入同步时在类目表中登记自己的 `ConflictClass`（scalarLww / entryLww / facetRowLww / immutableMoney / appendOnly / todoDoneForward / tombstone），仲裁逻辑零改动。矩阵语义见 [../feature_sync/README.md](../feature_sync/README.md)。
