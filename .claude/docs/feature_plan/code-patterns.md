# code-patterns — feature_plan 代码模式

> 三域（待办/健身/存钱）共用同一套编写套路；本文件提炼为可复制的步骤与
> 扩展点。表结构/DAO 契约在 core_db（[../core_db/README.md](../core_db/README.md)）。

## 1. 新增一个标准域的完整步骤

以「存钱域（W13）」为样板，新增一个计划域子域的固定套路：

1. **表先行（core_db）**：在 `core_db/lib/src/tables/` 建表（带 SyncColumns 公共列）→ 跑 build_runner → DAO（写路径 outbox 同事务入队 + 投影联动 + 幂等键）→ export。若是 v1 内加列，走「只加列 + beforeOpen 幂等回填函数」模式（参照 `backfillTodoRruleAnchorColumn`），schemaVersion 不动。
2. **值对象（plan_models.dart 或新文件）**：纯 Dart 无 IO 无 Flutter——Draft（const 定向构造器 + assert）、View（行 + 本地聚合派生量）、family Seed（必须实现 ==/hashCode）。
3. **网关编排（plan_gateway.dart）**：新增小节注释块（引用 §编号 + 取舍注记），写路径 = `db.transaction` 内：读上下文行 → 校验（无行/非法抛 `StateError`/`ArgumentError`）→ DAO/仓库写 → `outbox.enqueueRow` → 返回重读行。读路径 = Drift `watch()` 流；跨表聚合用 `customSelect` + **必须声明 `readsFrom`**。
4. **Provider（plan_providers.dart）**：`StreamProvider.autoDispose[.family]` 包一层网关 watch 流，一行一个。
5. **页面 + 编辑抽屉**：页面 ConsumerWidget 读 provider（`.value + null` 骨架帧），抽屉 ConsumerStatefulWidget 经 `showSlimcaSpringSheet` 弹出、`ref.read(gateway).createXxx(...)` 提交；样式只引用 `context.slimca` token；测试锚点 ValueKey 常量导出（`xxxKey` / `xxxKey(id)`）。
6. **导出（feature_plan.dart）**：barrel 按「网关 → 模型 → 控制器 → 组件 → 页面」分组 export，组件/页面用 `show` 限定符号（含全部 Key 常量）。
7. **测试（test/）**：控制器/网关逻辑测试 + 页面 widget 测试（plan_pages_test.dart）+ 特性专项（wNN_ 前缀文件）；widget 测试禁真实计时器/异步洞见 [pitfalls.md](pitfalls.md)。

## 2. 网关写路径模板（三域统一）

```dart
Future<Row> writeSomething({required String id, ...}) {
  return db.transaction(() async {
    final row = await (db.select(db.tableX)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null || row.deletedAt != null) {
      throw StateError('writeSomething: 无此行 $id');   // 防御：不猜默认值
    }
    final stamp = _nextStamp();                        // HLC 戳（clock 单例）
    await /* DAO/仓库 写 */ ;
    await outbox.enqueueRow('table_x', id);            // §6.2 同事务入队
    return (db.select(db.tableX)..where((t) => t.id.equals(id))).getSingle();
  });
}
```

关键纪律：
- **「不改动」哨兵**：可变字段更新（`updateTodoDetails`/`updateFitnessPlanDetails`）沿用 TodoDao 口径——显式传 null=清除、缺省=保留，用 `static const Object _unchanged = Object()` + `identical` 判定，可空字段 copyWith 同法。
- **幂等双保险**：软删类操作（delete）行不存在/已删 = no-op；打卡类操作靠 DAO 幂等键；汇总类操作（finishWorkoutSession）靠 `entry_id` 非空短路返回。
- **错误分层**：无行/业务前置不满足 → `StateError`（调用方可捕）；入参非法 → `ArgumentError`；assert 只用于 debug 不变式（reps≥1 等）。UI 层提交失败一律写 errorText 返回 null，不抛穿表单（§3.7 本地优先）。

## 3. 「查询时展开，不预生成行」模式

重复待办（W13）与计划排期（W14）同一取向：

- DB 只存**规则基行**（repeat_rule + anchor / weekday_mask），不物化实例/空会话行；
- 某日清单 = 非重复行 ∪ 规则展开命中当日的**虚拟实例**（内存构造，如 `TodoDayInstance`）；
- 写操作（勾选/删除/开练）始终作用于基行或显式动作创建的行；
- 收益：同步行数 O(规则数)；代价：实例完成状态挂基行单列（见 pitfalls）。

新增任何「按日历展开」类功能（如月度账单周期）应复用此模式，而非生成日期行。

## 4. 可测性注入模式（feature 层不触平台能力）

| 平台能力 | 注入点 | 生产缺省 | 测试口径 |
|----------|--------|----------|----------|
| 时间心跳（组间倒计时） | `restTickerFactoryProvider` | `systemRestTicker`（1s periodic，懒订阅） | 手动 StreamController 逐枚触发 |
| 完成音/震动 | `restFeedbackProvider`（`RestFeedback` 接口） | `NoopRestFeedback` | 记录调用 |
| 本地通知调度 | 不在本包——壳层按 `remind_at` 消费 | — | — |
| WakeLock/前台服务 | 不在本包——壳层承担 | — | — |

新增涉平台能力时：接口 + `Provider` 注入点 + Noop 缺省放本包，真实实现放 apps/mobile。

## 5. 设计模式用法

- **网关门面（Facade）**：`PlanGateway` 聚合 5 个 core_db DAO/仓库 + outbox + 投影，页面/控制器只见网关；
- **Provider DI**：`planGatewayProvider` 抛 `UnimplementedError` 的「装配契约」写法——装配遗漏开发期即暴露而非静默错库；
- **纯推导状态**：控制器不落游标（`currentTarget` = 前缀和 + completedCount 推导），append-only 行数即状态，天然支持断点恢复；
- **防御解析（§7.4）**：远端可写本端不支持的形状——坏 JSON/坏规则一律降级（空模板/不展开/null），绝不抛错打断渲染；单行坏不炸整模板（`PlanExercise.tryParseJson` 逐行过滤）。

## 6. 扩展点

| 想加什么 | 操作路径 |
|----------|----------|
| 新增 MET 活动 | `fitness_met_table.dart` 的 `kFitnessActivities` 追加条目（id 稳定——已落历史 payload 的 activity_id 靠它回放） |
| 新增重复档位 | `rrule.dart`：`TodoRepeatKind` + `toRrule/fromRrule` 映射 + `parseRrule` 子集扩展 + `rruleOccursOn` 展开；编辑器 chips 加档 |
| 新增存钱法 | `plan_models.dart`：新 rhythm kind 常量 + `SavingsGoalDraft` 构造器 + `savingsLadderStep` 分支 + 编辑器档位；DAO 幂等键无需改 |
| 动作库（800+ 集合） | `PlanExercise.name` → 库 id；`exercise_sets.exercise_ref` 已预留「id 或名称」口径，模板 JSON 加字段走 ver 前向兼容 |
| 存钱联动账本流水 | 开放问题 #9 待拍板——改 `PlanGateway` 存钱小节（唯一声明点），在 DAO 事务内补 entries/entry_lines 转账行 |
| 逐实例物化重复待办 | 升级路径 = §6.4 只加表（实例行表），展开逻辑换数据源；当前「done_at 落实例日」口径随之退役 |
| 新计划 Tab 卡片 | `PlanHubPage` 追加 `_HubCard`（摘要直读投影/计数流），或宿主整页替换/拆卡嵌入 |
