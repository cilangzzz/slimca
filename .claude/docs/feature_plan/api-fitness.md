# api-fitness — 健身域 API

> 覆盖四个子块：手动记录（W5-6）、身体档案体重、健身计划模板/排期（W14）、
> 开练流（会话 + 组明细 + 组间计时器）+ 训练历史。代码文件前缀 `fitness_*`。

## PlanGateway 健身方法（19 个）

### 手动记录（W5-6 路径，**不入 outbox**）

| 方法 | 签名要点 | 语义 |
|------|----------|------|
| `submitFitnessSession(FitnessSessionDraft)` | `→ Future<String>`（sessionId） | 同事务落三行：`entries(kind=fitness, source=manual, status=confirmed)` + `entry_lines(type=burn, direction=out, confidence=null, payload 记 session_id/MET 参数)` + `fitness_sessions`；burn 行归集内置 kcal 账本（惰性 seed 兜底）。`start_at` 仅当日记录回填 `now - duration`，非当日留 null。投影同事务重算 kcal_out/net_kcal |
| `deleteFitnessSession(sessionId)` | `→ Future<void>` | 会话行打墓碑 + 关联事件 `entries.softDelete`（投影 kcal_out 即时回落）；幂等 no-op |
| `watchSessionsByDate(date)` | `→ Stream<List<FitnessSession>>` | 某日会话列表（未删，最近录入在前） |

### 身体档案体重（2）

| 方法 | 语义 |
|------|------|
| `loadBodyWeightKg()` | `→ Future<double>`；settings 缺失/坏值回退 `kDefaultBodyWeightKg`（70） |
| `saveBodyWeightKg(weightKg)` | settings UPSERT（value 为 JSON 文本）；表单提交前自动持久化 |

### 健身计划 CRUD（6）

| 方法 | 签名要点 | 语义 |
|------|----------|------|
| `createFitnessPlan` | `({required String name, required int weekdayMask, required List<PlanExercise> exercises, String? startDate, bool active = true}) → Future<FitnessPlan>` | `exercises` 经 `FitnessPlanTemplate.encode` 落 JSON 列；`weekdayMask` bit0=周一…bit6=周日，空掩码=纯模板（可开练、无排期日）；`startDate` 缺省=设备本地今日。**行快照同事务入队 outbox** |
| `updateFitnessPlanDetails` | `({required String id, Object? name, Object? weekdayMask, Object? exercises, Object? active, Object? startDate})` | **Object 哨兵口径**：缺省传「不改动」；`exercises` 传 `List<PlanExercise>` 内部编码。无此计划抛 `StateError`。入队 outbox |
| `deleteFitnessPlan` | `(String id)` | 软删墓碑 + 墓碑快照入队；既有会话不受影响（`plan_day_id` 为逻辑前向引用）；幂等 no-op |
| `watchFitnessPlans()` | `Stream<List<FitnessPlan>>` | 未删，起始日倒序 |
| `watchPlanById(id)` / `findPlanById(id)` | Stream / Future 单行 | 编辑预填 / 一次性读取 |

### 开练流（W14，一律 outbox 同事务入队）

| 方法 | 签名要点 | 语义 |
|------|----------|------|
| `startWorkoutSession` | `({required String planId, required String date, int? tzOffsetMin}) → Future<FitnessSession>` | **开练即建会话行**：`type=template_instance`、`source=plan`、`start_at=开练时刻`、`duration_s/kcal_burn=0`、`plan_day_id=planId`（v1 无独立排期日表，排期日语义 = (plan_day_id, date) 二元组）；不预生成空会话。计划不存在/已删抛 `StateError` |
| `logExerciseSet` | `({required String sessionId, required String exerciseRef, required int reps, required int weightKgX10, int? restS, double? rpe, int? sort}) → Future<ExerciseSet>` | 每完成一组落一行，**完成标记 = done_at 非空**（append-only）；`sort` 缺省 = 存活组数+1；`exercise_ref` v1 落动作名（动作库未上线）；assert `reps≥1`、`weightKgX10≥0`（仅 debug 生效）；会话不存在/已删抛 `StateError` |
| `finishWorkoutSession` | `({required String sessionId, required double weightKg, String? note}) → Future<FitnessSession>` | 单事务汇总：① `duration_s = start_at` 起算真实墙钟秒；② kcal 走 MET 逻辑（固定 `strength_training` 中档；时长 0 → 0 kcal 不走估算）；③ 联动 `entries(kind=fitness)` + `entry_lines(burn,out)`（payload 记 session_id/plan_id/组数）+ 投影重算；④ 会话回填 + 三行快照入队。**幂等**：entry_id 已非空直接返回既有行；无组明细抛 `StateError`（空会话由退出路径软删）；weightKg ≤ 0 抛 `ArgumentError` |
| `findSessionById` / `setsForSession` / `watchSetsBySession` | 单行 / 组明细（sort 升序）Future / Stream | 控制器装载与断点续挂（已完成组数 = 存活组明细行数） |
| `watchAllSessions()` | `Stream<List<FitnessSession>>` | 历史页数据源（手动记录与计划实例共用行模型，按日/按计划分组由页面承担） |
| `watchSetCountsBySession()` | `Stream<Map<String, int>>` | GROUP BY 单查询的会话 → 存活组数映射（历史页徽标） |

## MET 表与估算（fitness_met_table.dart）

| 符号 | 语义 |
|------|------|
| `kFitnessActivities` | 内置 10 项活动（快走/慢跑/骑行/游泳/跳绳/HIIT/力量训练/瑜伽/球类/其他），每项三档 MET |
| `FitnessActivity.metFor(intensity)` | 取档位 MET；`estimateKcalBurn({activity, intensity, durationS, weightKg})` → `kcal = MET × 体重kg × 时长h` 四舍五入整数；**非正时长/体重抛 `ArgumentError`** |
| `FitnessIntensity` | `low/mid/high`（wire 写入 burn 行 payload） |
| `FitnessType` | `strength/cardio/hiit/other`（= fitness_sessions.type 枚举；`template_instance` 是 W14 会话类型，不在此列） |
| `findFitnessActivity(id)` | 未命中返回 null（payload 回放防御） |

## 健身计划模板模型（fitness_plan_models.dart）

| 符号 | 语义 |
|------|------|
| `PlanExercise` | 动作行：`name/sets/targetReps/targetWeightKgX10/restS`（assert 组数次数 ≥1、重量休息 ≥0）；`toJson/tryParseJson`（坏行回退保守默认：1 组 10 次自重 0 休息，不静默丢动作） |
| `FitnessPlanTemplate` | exercises 列 JSON 编解码：`{"ver":1,"exercises":[...]}`；`decode` 坏 JSON/形状不符 → 空模板，坏行逐条过滤；`totalSets` = Σ 组数 |
| `planWeekdayBitOf(day)` / `planMaskCovers(mask, day)` / `planMaskSummary(mask)` | 掩码位序 bit0=周一…bit6=周日；空掩码摘要返回 null（纯模板） |

## 控制器

### FitnessFormController（`fitnessFormControllerProvider`，AsyncNotifier family）

- family key = `FitnessSeed(initialDate?)`（须 ==/hashCode）。
- build 异步装载身体档案体重；方法：`selectActivity` `selectIntensity` `setDurationText` `setWeightText` `setNote` `setDate` `shiftDate(±days)`。
- `submit()`：体重有改动先 `saveBodyWeightKg` → 网关落三行；成功清空时长/备注并返回会话 id；失败写 `errorText` 返回 null（不打断表单）。输入合法性在 `FitnessFormState.durationMinutes`（钳 1-1440）/`weightKg`（钳 25-300）。

### FitnessWorkoutController（`fitnessWorkoutControllerProvider`，AsyncNotifier family）

- family key = `FitnessWorkoutSeed(sessionId)`；**开练入口先 `startWorkoutSession` 建行再进页**，控制器不重复建会话。
- 「当前目标」= 模板前缀和 + `completedCount` **纯推导**（不落游标状态）；断点续挂凭组明细行数恢复。
- `completeCurrentSet({reps, weightKgX10})`：落组行 + 游标 +1；在途防双击（实例内 `_completing` 标志）；无可练目标/失败返回 null。
- `finish()`：经网关汇总；幂等；无组明细返回 null；失败写 `errorText`。

### 组间计时器（rest_timer.dart）

- `restTimerProvider`（Notifier，state null=未在休息）：`start(seconds)`（非正值直接收起）/`skip()`；剩余秒恒由心跳递减推导，UI 不挂 Timer。
- 注入点：`restTickerFactoryProvider`（生产=1s `Stream.periodic`，懒订阅；测试 override 手动 StreamController）+ `restFeedbackProvider`（`RestFeedback.onRestComplete` 完成音/震动；feature 层缺省 Noop，宿主注入实现）。
- `RestTimerPanel`：state null 时整块收起；测试锚点 `restTimerPanelKey` `restTimerSkipKey` `restTimerRemainKey`。

## Providers（7 个 reactive 读侧）

`fitnessSessionsProvider(date)`、`planDaySummaryProvider(date)`（day_summary 投影直出，计划 Tab 卡片摘要用）、`fitnessPlansProvider`、`fitnessPlanDetailProvider(id)`、`allFitnessSessionsProvider`、`exerciseSetsBySessionProvider(sessionId)`、`setCountBySessionProvider`。

## 页面

| 页面 | 要点 |
|------|------|
| `FitnessLogPage` | 表单卡（类型/强度/时长/体重，实时 kcal 估算 ±20% 标注）+ 前后日导航 + 按日会话列表（删除走软删）；锚点 `fitnessSubmitKey` `fitnessDurationFieldKey` `fitnessWeightFieldKey` `fitnessDeleteKey` |
| `FitnessPlanPage` | 计划卡列表 + 排期条（周掩码高亮）+ 编辑抽屉 + 一键开练（`startWorkoutSession` → push `FitnessWorkoutPage`）+ 训练历史入口 + 删除；锚点 `fitnessPlanCreateKey` `fitnessPlanEmptyCreateKey` `fitnessHistoryKey` `fitnessPlanStartKey` `fitnessPlanEditKey` `fitnessPlanDeleteKey` `fitnessPlanDayChipKey` |
| `FitnessWorkoutPage` | 目标卡（次数/重量预填模板目标可改）+ 组间计时面板 + 已落组明细；完成一组后若刚完成动作 `restS>0` 且有下一组 → 启动计时器；**PopScope 退出守卫**：零组明细退出 → 软删会话（空会话不入历史）；已有组未汇总 → 自动 `finish()` 入账；锚点 `fitnessWorkoutCompleteKey` `fitnessWorkoutFinishKey` `fitnessWorkoutRepsFieldKey` `fitnessWorkoutWeightFieldKey` |
| `FitnessHistoryPage` | 按日/按计划双维度分组（`allFitnessSessionsProvider` + `setCountBySessionProvider` + `fitnessPlansProvider`） |

编辑抽屉 `FitnessPlanEditorSheet`：名称 + 星期掩码 chips + 动作行（名称/组数/次数/重量/休息秒，增删）→ `createFitnessPlan` / `updateFitnessPlanDetails`；锚点 `fitnessPlanNameFieldKey` `fitnessPlanWeekdayChipKey` `fitnessPlanAddExerciseKey` `fitnessPlanExercise*Key` `fitnessPlanSubmitKey`。

## 数据模型

见 [data-model.md](data-model.md)（`FitnessSessionDraft`/`FitnessFormState`、fitness_sessions/fitness_plans/exercise_sets 三表联动、outbox 装配纪律）。
