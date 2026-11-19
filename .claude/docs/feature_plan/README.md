# feature_plan — 计划域（待办 / 健身 / 存钱 / 健身计划）

> 源码：`packages/feature_plan`（pub workspace 包，Flutter 业务层）。
> 本文为索引；API 详情、数据模型、代码模式、坑点见「详细文档」章节。
> **接线口径（2026-11-19 IA 重设计后）**：计划 Tab 默认页=壳层 TodayPlan
> （apps/mobile `features/plan/plan_page.dart`，今日待办/今日健身/今日存钱
> 三卡）；本包页面为 L1 域管理页，由宿主逐页接线（router 子路由或
> Navigator.push）。早期版本「PlanHubPage 是计划 Tab 默认实现」为失真口径
> （该页从未被接线，已删除）。

## 模块概述

计划域承载 Slimca 的三大留存钩子 + 待办主线，共四个子域：

| 子域 | 入口页 | 核心能力 |
|------|--------|----------|
| 待办收集箱 | `TodoPage` | 收集箱（date IS NULL 未排期池）：快加/「加入今日」/编辑/删除；**今日待办由壳层计划 Tab「今日待办」卡承载**（单一入口）。RRULE 重复待办（查询时展开虚拟实例，不预生成行）；提醒时刻落 `remind_at`（真实通知由壳层调度）。重复待办在收集箱建档时锚点=保存日（TodoDao 对 date=null 不回填锚点，编辑抽屉显式传） |
| 健身手动记录 | `FitnessLogPage` | 内置 MET 表 + 强度档 + 时长/体重 → `kcal = MET × 体重kg × 时长h`（±20% 口径标注）→ 同事务落 entries + burn 行 + fitness_sessions **+ 三行 outbox 入队**；AppBar「历史」= 训练历史唯一入口 |
| 存钱目标 | `SavingsPage` / `SavingsGoalDetailPage` | 365 天挑战 / 52 周挑战 / 自定义；投币打卡（幂等）；进度 = Σ 贡献行（append-only）；一键投币组件 `SavingsCheckInButton` 同时用于壳层今日存钱卡 |
| 健身计划（模板） | `FitnessPlanPage` / `FitnessHistoryPage` | 模板（动作列表 JSON）+ 按周排期掩码——**纯管理页，无开练入口**（开练唯一入口=壳层今日健身卡排期行，引擎=壳层 WorkoutRunnerPage）；训练历史按日/按计划双维度，会话行可删 |

W13 三留存钩子漏斗（savings_goal_created / coin_in / todo_recurrence_created）
跟随唯一写路径在 `PlanGateway` 记（`createPlanGateway(telemetry:)` 注入，
缺省 null 零副作用）；事件名常量已收编 core_domain `TelemetryFunnel`。

## 模块边界与依赖

- **依赖**：`core_domain`（SyncMeta/HlcClock/Entry 领域实体）、`core_db`（Drift 表/DAO/投影/outbox）、`ui_kit`（token 与转场）、`flutter_riverpod` 3、`drift`。**不依赖**其他 feature 包，不反向依赖壳。
- **被消费**：仅 `apps/mobile`（路由接线 + DI 装配 + 提醒调度壳实现）。
- **分层纪律**：持久化语义全部复用 core_db 的仓库/DAO（DriftEntryRepository / DriftEntryLineRepository / TodoDao / SavingsGoalsDao / SavingsContributionsDao / DaySummaryProjection），本包只做 feature 层编排与视图；主题/动效只引用 ui_kit 既有 token。

## 宿主装配（DI 契约）

```dart
// apps/mobile/lib/app/bootstrap.dart
planGatewayProvider.overrideWithValue(
  createPlanGateway(db: database, clock: clock, telemetry: telemetry), // HlcClock 必须应用级单例；telemetry 缺省 null
)
```

未 override 直接读 `planGatewayProvider` 抛 `UnimplementedError`（装配遗漏开发期即暴露）。缺省自动创建 `DaySummaryProjection`，所有写路径同事务联动投影重算。

## 对外 API 索引

完整签名/参数/错误语义见各域 api 文件；此处只列清单。

### PlanGateway（37 个方法，按域归档）

- 待办（8）：`createTodo` `updateTodoDetails` `setTodoDone` `deleteTodo` `moveTodoToToday` `watchTodosByDate` `watchInboxTodos` `watchTodoDayInstances` → [api-todo.md](api-todo.md)
- 健身（19）：`submitFitnessSession` `deleteFitnessSession` `saveBodyWeightKg` `loadBodyWeightKg` `watchSessionsByDate` `createFitnessPlan` `updateFitnessPlanDetails` `deleteFitnessPlan` `watchFitnessPlans` `watchPlanById` `findPlanById` `startWorkoutSession` `logExerciseSet` `finishWorkoutSession` `findSessionById` `setsForSession` `watchSetsBySession` `watchAllSessions` `watchSetCountsBySession` → [api-fitness.md](api-fitness.md)
- 存钱（10）：`createSavingsGoal` `contributeToGoal` `deleteSavingsGoal` `markGoalCompleted` `watchSavingsGoalViews` `watchGoalById` `watchGoalProgress` `watchTodayManualContribution` `watchContributionsByGoal` `savingsStepForDay` → [api-savings.md](api-savings.md)

### Riverpod Providers（15 个 reactive 读侧，plan_providers.dart）

`fitnessSessionsProvider` `planDaySummaryProvider` `todayTodosProvider` `inboxTodosProvider` `savingsGoalsProvider` `savingsGoalDetailProvider` `savingsGoalProgressProvider` `savingsGoalContributionsProvider` `todayManualContributionProvider` `todoDayInstancesProvider` `fitnessPlansProvider` `fitnessPlanDetailProvider` `allFitnessSessionsProvider` `exerciseSetsBySessionProvider` `setCountBySessionProvider` —— 全部 `StreamProvider.autoDispose`（family 按日/按 id），直读网关 watch 流。

### 控制器与注入点（2 个 Provider）

- `fitnessFormControllerProvider`（AsyncNotifier family，seed=`FitnessSeed`）→ [api-fitness.md](api-fitness.md)
- ~~`fitnessWorkoutControllerProvider` / `restTimerProvider`~~ 已随包版开练引擎退役（IA 重设计：开练引擎唯一在壳层 WorkoutRunnerPage，其注入点见 apps-mobile 文档）

### 页面入口（6 个）

`FitnessLogPage`（含 AppBar 历史入口）｜待办：`TodoPage`（收集箱）｜存钱：`SavingsPage` `SavingsGoalDetailPage`｜健身计划：`FitnessPlanPage`（纯管理）`FitnessHistoryPage`。均无路由依赖（由宿主 push/子路由接线），各页导出 `ValueKey` 测试锚点（如 `todoCheckKey(id)`、`fitnessSubmitKey`）。~~PlanHubPage / FitnessWorkoutPage~~ 已删除（IA 重设计）。

### 编辑抽屉/组件（5 个）

`TodoEditorSheet`（重复五档 + 提醒时刻 + 删除；稳定高度 `planSheetHeight` + 主 CTA 钉底）、`SavingsGoalEditorSheet`（三种存钱法；同口径）、`FitnessPlanEditorSheet`（动作行编辑；同口径）、`SavingsCheckInButton`（一键投币）、`SlimcaProgressRing`（进度环）。~~RestTimerPanel~~ 已退役。

## 模块特定配置

- `settings` 表键 `body_weight_kg`（JSON 文本存 double，MET 估算输入；缺省 70 kg）。
- 纯常量：`kSettingBodyWeightKg` `kDefaultBodyWeightKg` `kFitnessPlanTemplateVer` `kFitnessSessionTypeTemplateInstance` `kFitnessSessionSourcePlan` `kFitnessPlanMetActivityId` `kSavingsRhythmKind*`。

## 详细文档

- [api-todo.md](api-todo.md) — 待办域网关 API、RRULE 工具函数、TodoPage/TodoEditorSheet
- [api-fitness.md](api-fitness.md) — 健身手动记录 + 健身计划 + 开练流 + 组间计时器全量 API
- [api-savings.md](api-savings.md) — 存钱域网关 API、存钱法格子推算、编辑器/打卡按钮
- [data-model.md](data-model.md) — 三域模型、JSON 形状约定、投影联动与同步列
- [code-patterns.md](code-patterns.md) — 网关编排套路、新增标准域步骤、扩展点
- [pitfalls.md](pitfalls.md) — 已知坑点与防御口径
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（git 实证）

跨模块参考：[core_db](../core_db/README.md)（表结构/DAO 契约）、[core_domain](../core_domain/README.md)（HLC/SyncMeta）、[ui_kit](../ui_kit/README.md)（token）。

## 已知坑点（摘要）

1. ~~outbox 覆盖不对称~~ **已解决（2026-11-19 IA 收敛）**：`submitFitnessSession` 现已三行同事务入 `sync_outbox`（原「W5-6 手动记录路径不入 outbox、由壳层 FitnessService 自带入队」的双口径随壳层服务删除而消除）——网关全部写路径现在统一同事务入队。
2. **重复待办不物化实例行**：勾选/删除作用于基行；当日实例完成 = `done_at` 落在实例日。收集箱（date=null）重复待办的展开锚点由编辑抽屉显式传保存日（TodoDao 对 date=null 不回填锚点——漏传则永不展开）。
3. **存钱贡献不触账本表**（开放问题 #9 待拍板）：不生成 entries/entry_lines。
4. 金额一律分（minor）、重量 ×10 定点整数；坏 rhythm/exercises JSON 防御降级不抛错。
5. **包内测试缺省 telemetry=null**：W13 三漏斗只在注入 telemetry 的网关实例上记；壳层 e2e 用 `createPlanGateway(telemetry:)` 断言漏斗（见 apps/mobile savings_progress_card_test）。
