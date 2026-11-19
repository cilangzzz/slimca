# api-savings — 存钱域 API

> W13 留存钩子。贡献行 append-only + `(goal_id, date, source)` 幂等打卡
> （core_db `SavingsGoalsDao`/`SavingsContributionsDao`），写路径同事务驱动
> `day_summary.savings_progress`。**存钱与账本流水 V1 不联动**（开放问题 #9
> 待拍板，声明点在 plan_gateway.dart 存钱小节注释）。

## PlanGateway 存钱方法（10 个）

### 写路径（4）

| 方法 | 签名要点 | 语义 |
|------|----------|------|
| `createSavingsGoal(SavingsGoalDraft)` | `→ Future<SavingsGoal>` | 三种存钱法见下；挑战目标金额由格子数推导（`effectiveTargetMinor`）、rhythm 由 `rhythmJson()` 生成；`startedOn` 缺省=网关落库时取设备本地今日（第 1 格锚点）。经 DAO：outbox 同事务入队 + 投影重算 |
| `contributeToGoal` | `({required String goalId, required String date, int? amountMinor, int? slot, String? note}) → Future<SavingsContribution>` | 投币打卡。`amountMinor` 缺省时按存钱法推当日格子（`savingsLadderStep`）；目标无此行抛 `StateError`；未开跑/rhythm 不可推算抛 `StateError`（不猜默认值）。**真正防重复在 DAO 幂等键** `(goal_id, date, source='manual')`——已有存活行 no-op 返回既有行，UI 置灰只是提示 |
| `deleteSavingsGoal(id)` | `→ Future<void>` | 软删墓碑（归档），投影同事务联动 |
| `markGoalCompleted(id)` | `→ Future<void>` | status `active→completed`；**达成判定由上层决策**（详情页按 `watchGoalProgress` 判 Σ贡献 ≥ 目标后写回），DAO 读路径零副作用 |

### 读路径（6）

| 方法 | 返回 | 语义 |
|------|------|------|
| `watchSavingsGoalViews()` | `Stream<List<SavingsGoalView>>` | 目标 + Σ贡献 **单条响应式联查**（LEFT JOIN + GROUP BY，`readsFrom` 双表）——贡献追加/目标变更任一发生即重发；墓碑行与墓碑目标均排除 |
| `watchGoalById(id)` | `Stream<SavingsGoal?>` | 详情页目标行 |
| `watchGoalProgress(goalId)` | `Stream<int>` | Σ 贡献求和流（进度环/达成判定直驱） |
| `watchTodayManualContribution({goalId, date})` | `Stream<SavingsContribution?>` | 当日人工投币行（非空=今日已投币 → 按钮置灰）；source 与幂等键三元组同口径 |
| `watchContributionsByGoal(goalId)` | `Stream<List<SavingsContribution>>` | 贡献历史时间线；**含远端墓碑行**（供「撤销」痕迹渲染，上层自行过滤） |
| `savingsStepForDay({goal, day})` | `({int amountMinor, int? slot, String? label})?` | 当日格子推算（打卡按钮文案直驱）；未开跑/不可推算返回 null |

## 存钱法模型（plan_models.dart）

### SavingsGoalDraft（三个 const 定向构造器）

| 构造器 | 必填 | 推导 |
|--------|------|------|
| `SavingsGoalDraft.daily365(name, unitMinor, startedOn?)` | 每格基数 | 目标 = 基数 × Σ(1..365) = 基数 × 66795；`rhythm = {"kind":"daily365","unit_minor":N}` |
| `SavingsGoalDraft.week52(name, unitMinor, startedOn?)` | 每格基数 | 目标 = 基数 × Σ(1..52) = 基数 × 1378；`rhythm = {"kind":"week52","unit_minor":N}` |
| `SavingsGoalDraft.custom(name, targetMinor, dailyAmountMinor, deadline?)` | 目标额 + 每日投币额 | `rhythm = {"kind":"custom","daily_amount_minor":N}` |

构造器内 assert 金额为正（debug 生效）。rhythm 列 JSON 形状约定为本包独有（DB 层只存文本），见 [data-model.md](data-model.md)。

### savingsLadderStep（当日格子推算）

- daily365：第 N 天 = 起始日起第 N 个自然日，金额 N×基数，slot=N；
- week52：第 N 周 = 起始日起第 N 个自然周（`diff ~/ 7`），金额 N×基数，slot=N；
- custom：每日固定额，slot=null；
- `day < started_on`（未开跑）或 rhythm 坏 JSON/缺键 → **null**（不可推算时不投币、不猜默认值）；
- 格子号越顶（>365/52）钳制到末格，label 标注「已收官」。

### SavingsGoalView（列表视图）

`goal` 行 + `contributedMinor`（Σ 贡献）；`progress` 钳 0-1（无目标额为 0）；`targetYuan/contributedYuan` 分→元展示串。

## Providers（5 个 reactive 读侧）

| Provider | family key | 返回 |
|----------|-----------|------|
| `savingsGoalsProvider` | — | `List<SavingsGoalView>` 列表页直驱 |
| `savingsGoalDetailProvider` | `String`（goalId） | `SavingsGoal?` |
| `savingsGoalProgressProvider` | `String` | `int` Σ贡献 |
| `savingsGoalContributionsProvider` | `String` | `List<SavingsContribution>` 历史 |
| `todayManualContributionProvider` | `(String, String)` record（goalId, date） | `SavingsContribution?` 今日已投 |

## 页面与组件

### SavingsPage

- 目标卡列表（`savingsGoalsProvider`）：方法标签 `savingsMethodLabel`、状态 `savingsStatusLabel`、档位 `savingsSlotLabel`（导出常量，供测试/宿主复用）；空态引导创建。
- 锚点：`savingsCreateKey` `savingsEmptyCreateKey` `savingsGoalCardKey(goalId)`。

### SavingsGoalDetailPage

- 进度头（进度环 + 已存/目标元）+ 贡献历史时间线 + 操作：标记达成（达成判定达标才可点 → `markGoalCompleted`）、归档（`deleteSavingsGoal`）。
- 锚点：`savingsCompleteKey` `savingsDeleteKey` `savingsContributionKey`。

### SavingsGoalEditorSheet（弹簧抽屉）

三档方法 chips（365 天挑战 / 52 周挑战 / 自定义）→ 构造对应 `SavingsGoalDraft` → `createSavingsGoal`；挑战只需名称 + 每格基数，自定义需目标额 + 每日投币额 + 可选截止日。
锚点：`savingsNameFieldKey` `savingsMethodChipKey` `savingsUnitFieldKey` `savingsTargetFieldKey` `savingsDailyFieldKey` `savingsDeadlinePickKey` `savingsGoalSubmitKey`。

### SavingsCheckInButton

- 状态由 `todayManualContributionProvider` 直驱：今日已有人工投币行 → 置灰「已投」；否则显示 `savingsStepForDay` 推算的当日格子文案（「第 N 天 ¥N」）。
- 点击 → `contributeToGoal(goalId, date: today)`（金额缺省推格子）。
- 锚点：`savingsCheckInKey`。

### SlimcaProgressRing

无状态进度环（进度 0-1），列表卡/详情页/仪表盘复用；accent 色由调用方传（存钱用 `tokens.moneyIn`）。

## 数据模型

见 [data-model.md](data-model.md)（savings_goals / savings_contributions 两表、rhythm JSON 形状、幂等键、投影联动）。
