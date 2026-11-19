# pitfalls — feature_plan 已知坑点

> 跨模块价值最高的排在前；排查同步/统计类 bug 优先读 1/2/5。

## 1. outbox 覆盖不对称（同步丢行的首要嫌疑）

同一网关两套写路径口径：
- `submitFitnessSession` / `deleteFitnessSession`（W5-6 手动记录路径）**不入** `sync_outbox`——先于 SyncOutboxWriter 落地，注释声明生产同步由 apps/mobile 的 FitnessService 链路承担；
- W14 起全部写路径（计划 CRUD、`startWorkoutSession`、`logExerciseSet`、`finishWorkoutSession`、存钱 DAO 写）一律业务行 + 行快照**同事务**入队。
排查「设备间健身行不同步」时先区分路径来源；改 W5-6 路径时勿想当然认为会自动入队。另注意：core_db 仓库写（entries/entryLines）本身不做 outbox，入队是网关侧装配纪律。

## 2. 重复待办的完成/删除语义（不物化实例行）

- 勾选作用于**基行**：`done_at` = 最近一次勾选时刻；当日实例「完成」= `done_at` 落在实例日（本地日历日）——昨日勾选不会让今日实例呈完成态，但历史多实例的完成痕迹不逐日回溯（v1 接受）；
- 删除作用于**整条 series**（v1 无「仅删当日实例」）；
- 排序沿用基行口径（done_at 反映最近勾选），跨日排序偶有偏差；
- 收集箱（date=NULL）不支持重复——无展开起点，编辑器入口已隐藏。
升级为逐实例物化前，任何「按日查询完成历史」的需求都不能基于 todos 表直接回答。

## 3. 存钱与账本不联动（开放问题 #9 待拍板）

`contributeToGoal` 只写 `savings_contributions`（append-only），**不生成** entries/entry_lines 转账流水（不双重记账）。凡「统计/流水页要看到存钱支出」的需求都是待拍板项；唯一声明点在 plan_gateway.dart 存钱小节注释，改动时先拍板再动 DAO。

## 4. MET 估算的输入校验与钳制分布在多层

- `estimateKcalBurn` 对非正时长/体重抛 `ArgumentError`（无默认值兜底）；
- `finishWorkoutSession` 时长 0 → 0 kcal **跳过估算**（不走公式）；计划实例 kcal 固定按 `strength_training` 中档 MET（模板语义=力量域），与实际动作组合无关——历史 kcal 对比时注意口径；
- 表单侧 `FitnessFormState` 钳制：时长 1-1440 分钟、体重 25-300 kg，越界 `durationMinutes/weightKg` 返回 null（提交与估算同时失效）。

## 5. 金额/重量定点与幂等键

- 金额一律分（minor）、重量一律 ×10 定点整数——浮点只存在于展示层（`/100`、`/10`）；
- 打卡防重复真正在 DAO 幂等键 `(goal_id, date, source='manual')`，UI 置灰只是提示；自定义目标 slot=null 不参与幂等冲突；
- `savingsLadderStep` 防御：未开跑（day < started_on）/坏 rhythm JSON/缺键 → null；`contributeToGoal` 对无格子日期抛 `StateError`（不猜默认值）——补投历史日期需显式传 `amountMinor`。

## 6. JSON 形状约定是 feature 层契约，DB 只存文本

`fitness_plans.exercises`（ver=1）、`savings_goals.rhythm`（daily365/week52/custom）、`settings.body_weight_kg`（JSON double）三处形状由本包定义。core_db 读到坏 JSON 时依赖本包防御解析（空模板/null/回退默认）——在 core_db 或其他包直接解析这些列会踩坑；新增字段只加键（ver 前向兼容）。

## 7. 开练流时序契约（先建行后进页）

- 开练入口必须先 `startWorkoutSession` 建会话行再 push `FitnessWorkoutPage`——控制器 build 时查不到会话行/plan_day_id 会直接抛 `StateError`；
- 「完成训练」幂等靠 `entry_id` 回填短路，双击 finish 无副作用；但**无组明细**的 finish 抛 `StateError`（空会话不入账）；
- 页面 PopScope 退出守卫：零组明细退出 → 自动软删会话；已有组未汇总 → 自动 finish 入账。绕过页面直调网关时需自行复刻这套清理逻辑。

## 8. Riverpod / 测试口径

- `planGatewayProvider` 未 override 即抛 `UnimplementedError`；`HlcClock` 必须应用级单例（HLC 单调性是全设备全序来源），测试里每用例新建 clock 会破坏合并序；
- provider 读态约定 `.value + null` 骨架帧；family Seed 必须实现 ==/hashCode 否则状态串味；
- 组间计时器**禁真实 Timer**：测试必须 override `restTickerFactoryProvider`；生产 ticker 是懒订阅（不进休息零 Timer），避免无关 widget 测试 fake_async 泄漏；
- 弹簧抽屉进场未整定即 tap 会落屏外 miss——widget 测试需泵满 `springSnappy` 220ms（W13 实测教训）；
- drift watch 流在 fake_async 下调度 Timer 会挂起——跨两天验收用 plain test（W13 实测教训）。

## 9. 日期与时区口径

- 一切聚合按 `date`（本地日历日 `yyyy-MM-dd`）分组，**不是** UTC 时间戳分组；
- `dayDiff` DST 安全（按小时差四舍五入），但 `DateTime.tryParse` 失败返回 null 的调用点各自回退——坏日期文本静默不展开；
- `remind_at` 以设备本地时区解包回显：跨时区 travel 后回显的时:分随偏移（v1 接受）；「今日」统一走 `featureLocalToday()`，勿各处 `DateTime.now()`。
