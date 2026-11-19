# data-model — feature_plan 三域数据模型

> 本包**不建表**：21 张 Drift 表全部在 core_db（见 [../core_db/README.md](../core_db/README.md)）。
> 本文件记录计划域相关的行模型、feature 层 JSON 形状约定、值对象与投影联动。
> 涉及的表：`todos`、`fitness_sessions`、`fitness_plans`、`exercise_sets`、
> `savings_goals`、`savings_contributions`、`entries`、`entry_lines`、
> `settings`、`day_summary`。所有同步行带 §5.1 公共列（hlc/revision/
> schema_ver/device_id/软删墓碑 deleted_at）。

## 一、待办域

### todos 基行（核心列）

| 列 | 类型 | 口径 |
|----|------|------|
| `title` / `note` / `dueAt` | TEXT / TEXT? / INT?(UTC ms) | 基础字段 |
| `date` | TEXT? | `yyyy-MM-dd` 计划日；**NULL=收集箱** |
| `repeat_rule` | TEXT? | RFC5545 v1 子集文本（`FREQ=DAILY/WEEKLY/MONTHLY;INTERVAL;BYDAY;BYMONTHDAY`） |
| `rrule_anchor_date` | TEXT? | DTSTART 展开锚点（W13 v1 内补列，旧库由 `backfillTodoRruleAnchorColumn` 幂等回填，schemaVersion 保持 1） |
| `remind_at` | INT? | 提醒时刻 UTC ms（真实通知由壳层调度） |
| `done_at` | INT? | **只前进合并**（set 胜）；重复待办的「最近一次勾选」痕迹 |

### TodoDayInstance（虚拟实例，不落行）

查询时展开的当日实例：`todo`（基行）/ `date`（实例日，收集箱为 null）/ `done`（**非重复 = done_at 非空；重复 = done_at 落在实例日**）/ `recurring` / `repeatLabel`（中文摘要）。展开策略取舍见 [pitfalls.md](pitfalls.md)。

## 二、健身域

### fitness_sessions（手动记录与计划实例共用行模型）

| 列 | 口径 |
|----|------|
| `date` / `tz_offset_min` | 归属日 + 时区偏移（§5.1 按 date 归日聚合，杜绝 UTC 错日） |
| `start_at` | 手动记录：仅当日回填 `now - duration`；计划实例：开练时刻真值 |
| `duration_s` / `kcal_burn` | 手动记录落库即定值；计划实例先落 0、完成训练时汇总 |
| `type` | `strength/cardio/hiit/other` 或 `template_instance`（计划实例） |
| `source` | `manual` 或 `plan` |
| `plan_day_id` | 逻辑前向引用 plan id（v1 无独立排期日表，排期日语义 = (plan_day_id, date) 二元组） |
| `entry_id` | 联动事件 id；手动记录即时回填，计划实例完成汇总时回填（**幂等标记**） |

### fitness_plans（模板 = 名称 + 动作列表 + 周排期掩码）

| 列 | 口径 |
|----|------|
| `weekday_mask` | bit0=周一…bit6=周日；空掩码=纯模板（可开练、无排期日） |
| `exercises` | JSON 文本，形状见下 |
| `start_date` / `active` | 起始日（缺省本地今日）/ 启用位 |

**exercises JSON**（`kFitnessPlanTemplateVer = 1`，新增字段只加键）：

```json
{"ver":1,"exercises":[
  {"name":"卧推","sets":3,"target_reps":10,"target_weight_kg_x10":400,"rest_s":90}
]}
```

- `target_weight_kg_x10`：重量 ×10 定点整数（避免浮点同步问题），自重取 0；
- `PlanExercise.tryParseJson` 坏行回退保守默认（1 组 10 次自重 0 休息）；
- `FitnessPlanTemplate.decode` 坏 JSON/形状不符 → 空模板，坏行逐条过滤。

### exercise_sets（组明细，append-only）

`session_id` / `exercise_ref`（v1 落动作名，动作库未上线）/ `weight_kg_x10`（×10 定点）/ `reps` / `rpe` / `rest_s` / `done_at`（**完成标记 = 非空**，W14 只在完成时落行）/ `sort`（会话内全局组序，缺省存活组数+1）。游标不落状态：断点续挂凭存活行数恢复。

### 联动行（entries + entry_lines）

- 手动记录提交（`submitFitnessSession`）：`entries(kind=fitness, source=manual, status=confirmed)` + `entry_lines(type=burn, direction=out, ledger=内置 kcal 账本, confidence=null)`，payload：`{session_id, activity_id, activity_name, met, intensity, weight_kg}`；
- 计划实例完成汇总（`finishWorkoutSession`）：同构三行，payload 多记 `{plan_id, plan_name, duration_s, sets}`，`activity_id` 固定 `strength_training`（中档 MET）；
- 事件标题口径：`「${活动/计划名} ${分钟} 分钟」`。
- **outbox 覆盖不对称**：手动记录路径业务行未入 `sync_outbox`（W5-6 先于 SyncOutboxWriter 落地），W14 路径一律同事务 `outbox.enqueueRow`。详见 [pitfalls.md](pitfalls.md)。

### 身体档案

`settings` 表键 `body_weight_kg`，value 为 JSON 文本（`jsonEncode(70.0)` 形态）；MET 估算输入，缺省 70 kg。

### 控制器值对象

- `FitnessSessionDraft`：手动提交载荷（date/tzOffsetMin/activity/intensity/durationS/weightKg/note?/title?）；
- `FitnessFormState`：表单中态（文本输入以 String 持有；派生量 `durationMinutes` 钳 1-1440、`weightKg` 钳 25-300、`estimatedKcal` 实时估算、`canSubmit`）；
- `FitnessSeed` / `FitnessWorkoutSeed`：family key（须 ==/hashCode）。

## 三、存钱域

### savings_goals

| 列 | 口径 |
|----|------|
| `target_minor` | 目标金额（分）；挑战目标 = 基数 × Σ(1..N) 推导（365→×66795、52→×1378） |
| `method` | `daily365` / `week52` / `custom`（wire 值） |
| `rhythm` | JSON 文本，形状约定（feature 层定义，DB 只存文本）：`{"kind":"daily365","unit_minor":100}`、`{"kind":"week52","unit_minor":1000}`、`{"kind":"custom","daily_amount_minor":500}` |
| `started_on` | 第 1 格锚点日（缺省落库时取本地今日） |
| `deadline` | 可选截止日（挑战不适用） |
| `status` | `active` / `completed`（达成判定由上层按 Σ贡献 ≥ 目标决策后写回） |

### savings_contributions（append-only）

`goal_id` / `amount_minor`（分）/ `date` / `slot`（挑战格子号，custom 为 null）/ `source`（W13 补列，人工打卡=`manual`）/ `note`。**幂等键 `(goal_id, date, source)`**：已有存活行 no-op 返回既有行。历史流含远端墓碑行（供「撤销」痕迹渲染）。

### 值对象

- `SavingsGoalDraft`：三个 const 定向构造器（daily365/week52/custom），挑战推导目标额与 rhythm、自定义取显式金额；
- `SavingsGoalView`：goal + contributedMinor，`progress` 钳 0-1；
- `savingsLadderStep(goal, day)`：当日格子（金额/slot/中文 label）；未开跑或 rhythm 不可推算 → null；格子越顶钳末格「已收官」。

## 四、投影联动（day_summary）

| 写路径 | 联动 |
|--------|------|
| 健身 burn 行 upsert/软删 | `kcal_out` / `net_kcal` 同事务重算 |
| 待办勾选/新建/删除 | `todo_done` / `todo_total`（done_at 只前进合并） |
| 存钱目标/贡献写路径 | `savings_progress`（「写后重算当日」在 DAO 写事务内完成，§5.6⑬） |

投影由 `createPlanGateway` 缺省创建并注入全部 DAO/仓库；读侧 `planDaySummaryProvider(date)` 直出快照（与仪表盘同口径、独立实例）。

## 五、金额与单位口径（跨域统一）

- 金额一律**分**（minor，int）；元展示 = `/100` 两位小数；
- 重量一律 **×10 定点整数**（`weight_kg_x10`），还原 `/10`；
- kcal 一律 int（四舍五入）；时长秒（duration_s）、时刻 UTC ms；
- 日期一律本地日历日 `yyyy-MM-dd`（聚合按 date 分组，DST 安全 `dayDiff`）。
