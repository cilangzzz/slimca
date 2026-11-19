# Changelog - feature_plan

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。
> 范围限定 `packages/feature_plan/`；同一提交对公共包/壳层的改动在「影响范围-跨模块」标注。

---

## [2026-11-19] 计划域 IA 重设计收敛：双实现归一 + 今日为纲 L0 + 漏斗随网关

**类型**: refactor+feat
**提交**: (本次会话，待提交)
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/plan_gateway.dart | +60/-8 | ①telemetry 注入点（createPlanGateway 新参数，缺省 null）——W13 三漏斗（savings_goal_created/coin_in/todo_recurrence_created）跟随唯一写路径在网关侧记；②submitFitnessSession 补三行 outbox 同事务入队（原 W5-6 口径「壳层 FitnessService 自带入队」已随壳层收敛删除，漏入队=静默丢同步）；③contributeToGoal 幂等预查（findEffective）支撑 coin_in 只记真实新增 |
| lib/src/widgets/plan_sheet_sizing.dart | +26/-0 | 新文件：planSheetHeight 稳定抽屉高度（captureSheetHeight 同源公式包内复刻，避免 feature_plan→feature_capture 依赖边） |
| lib/src/widgets/todo_editor_sheet.dart | 重构 | 稳定高度外框+主 CTA 钉底（唯一填充按钮）+编辑模式删除按钮（危险项具体动词确认弹窗）+收集箱重复待办显式锚点=保存日（修 TodoDao date=null 不回填锚点的潜伏缺陷）+文案去 § 锚点 |
| lib/src/widgets/savings_goal_editor_sheet.dart | 重构 | 稳定高度+CTA 钉底+文案清理 |
| lib/src/widgets/fitness_plan_editor_sheet.dart | 重构 | 稳定高度+CTA 钉底+文案清理 |
| lib/src/pages/todo_page.dart | 重写 | 收集箱化：去今日视图（今日待办唯一承载=壳层计划 Tab「今日待办」卡，单一入口）；保留 todo_input/todo_add/todo_advanced/todo_check/todo_delete/todo_move_today 全部键 |
| lib/src/pages/fitness_log_page.dart | +40 | AppBar「历史」文字按钮（fitnessHistoryKey 自 FitnessPlanPage 迁入——消灭二级页图标暗门）+活动 chip 键（fitness_type_<id>）+估算键 fitness_estimate+文案清理 |
| lib/src/pages/fitness_plan_page.dart | -80 | 摘除卡内「开练」按钮与 _startWorkout（开练单点化到壳层今日健身卡排期行）、AppBar 历史图标移除、文案清理 |
| lib/src/pages/savings_page.dart | 微 | 空态文案清理 |
| lib/src/pages/savings_goal_detail_page.dart | 微 | 弹窗/历史文案清理 |
| lib/src/pages/fitness_history_page.dart | 微 | 空态文案清理 |
| lib/src/pages/plan_hub_page.dart | 删除 | 死 UI（8 页中唯一从未接线的组合页，宿主真实计划 Tab=壳层 PlanPage） |
| lib/src/pages/fitness_workout_page.dart | 删除 | 包版开练页（引擎统一壳层 WorkoutRunnerPage；壳引擎持久化升级=后续独立加固步） |
| lib/src/fitness_workout_controller.dart | 删除 | 随包版开练页退役 |
| lib/src/widgets/rest_timer.dart | 删除 | 随包版开练页退役（壳层有独立 rest_timer_notifier） |
| lib/feature_plan.dart | 重写 | barrel 对齐真实接线口径（移除 hub/开练流导出，fitnessHistoryKey 迁挂 fitness_log_page 导出） |
| core_domain/lib/src/telemetry.dart | +22 | TelemetryFunnel 收编 W13 三事件名（原壳层常量平移，既定迁移点） |

### 影响范围

- **API**: createPlanGateway 新增 telemetry 可选参数（bootstrap 已注入）；PlanGateway 方法数不变；barrel 移除 PlanHubPage/FitnessWorkoutPage/FitnessWorkoutController/rest_timer 导出，新增 todoEditorDeleteKey/fitnessEstimateKey/fitness_type chip 键
- **行为变更**: ①默认体重 60→70 统一（双基线消除，e2e kcal 断言 210→245/-10→-12 同步）；②TodoPage 今日视图移除（收集箱单页）；③收集箱重复待办锚点=保存日（此前 anchor=NULL 永不展开——缺陷修复）；④手动记录三行 outbox 同事务入队（同步不再依赖壳层服务）
- **跨模块**: apps/mobile plan_page.dart 整页重写（今日待办/今日健身四态/今日存钱三卡）、plan_state 瘦身（待办/存钱读侧收敛包 providers）、router /plan/fitness 路由删除 + todos/savings 新增、fitness_service.dart 瘦身为壳引擎估算工具、savings_service.dart 删除（漏斗迁网关）、仪表盘存钱空态补 onTap
- **数据模型**: 无 schema 变更
- **回滚**: revert 本提交即回旧四卡版面；gateway telemetry/outbox 为纯增量可单独回退

### 回滚指南

M 级单提交回滚即可；注意 core_domain TelemetryFunnel 三常量为纯增量，回滚无害。

---

## [2026-11-17] W14 健身计划：模板排期+组间计时（锁屏骨架）+组明细联动 burn

**类型**: feat
**提交**: b367a6c
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/plan_gateway.dart | +454/-4 | 健身计划全量写路径：createFitnessPlan/updateFitnessPlanDetails/deleteFitnessPlan（Object 哨兵 + 幂等 no-op + 墓碑入队）、startWorkoutSession（开练即建会话行，type=template_instance/source=plan/start_at 真值）、logExerciseSet（done_at=完成标记，sort 缺省存活组数+1）、finishWorkoutSession（单事务汇总时长/中档 MET kcal + 联动 entry+burn 行 + 三行快照入队，entry_id 回填幂等）、组明细/历史读流 |
| lib/src/fitness_plan_models.dart | +187/-0 | 新文件：PlanExercise（×10 定点）/FitnessPlanTemplate（ver=1 JSON 编解码，坏行逐条过滤）/周排期掩码辅助 |
| lib/src/fitness_workout_controller.dart | +234/-0 | 新文件：开练流控制器——游标纯推导（前缀和+completedCount，断点续挂凭组明细行数）、防双击、finish 汇总 |
| lib/src/pages/fitness_workout_page.dart | +482/-0 | 新文件：开练页——目标预填可改、PopScope 退出守卫（零组软删会话/有组自动 finish）、组间计时面板接线 |
| lib/src/pages/fitness_plan_page.dart | +342/-53 | 占位页升级为真页：计划卡+排期条+编辑抽屉+一键开练+历史入口 |
| lib/src/pages/fitness_history_page.dart | +228/-0 | 新文件：训练历史按日/按计划双维度分组 |
| lib/src/widgets/fitness_plan_editor_sheet.dart | +396/-0 | 新文件：计划编辑抽屉（名称/星期掩码/动作行增删） |
| lib/src/widgets/rest_timer.dart | +200/-0 | 新文件：组间计时器——心跳源/完成反馈双 provider 注入（测试禁真实 Timer）、懒订阅、Noop 缺省 |
| lib/feature_plan.dart | +23/-6 | barrel 增 W14 导出（模型/控制器/组件/页面/Key） |
| lib/src/plan_providers.dart | +31/-1 | 增 5 个 provider：fitnessPlans/fitnessPlanDetail/allFitnessSessions/exerciseSetsBySession/setCountBySession |
| lib/src/pages/plan_hub_page.dart | +1/-1 | 计划卡入口指向真页 |
| pubspec.yaml | +1/-1 | 版本注释更新（W14） |
| test/w14_fitness_plan_test.dart | +581/-0 | 新文件：W14 专项验收 |
| test/plan_pages_test.dart | +11/-6 | 适配计划真页 |

### 影响范围

- **API**: PlanGateway 新增 12 个方法（健身计划 CRUD 3 + 开练流 3 + 读流 6）；providers +5；页面 +4（FitnessWorkout/FitnessHistory 新增，FitnessPlan 重做）
- **跨模块**: apps/mobile 同提交接线（router 挂 /plan 路由 +242 行 plan_page、workout_runner_page +409、workout_session_controller +326、keep-awake/timer 壳实现 7 文件、W14 埋点、bootstrap/providers DI +67）；本提交未改任何公共包
- **数据模型**: 无 schema 变更（fitness_plans/exercise_sets 自 schema v1 已建），仅 feature 层定义 exercises JSON 形状（ver=1）
- **配置**: apps/mobile/pubspec.yaml +12（wakelock_plus 等壳层依赖）

---

## [2026-11-17] W13 待办完整版（RRULE+提醒调度）+ 存钱目标（365/52周/自定义+投币打卡）

**类型**: feat
**提交**: cc86213
**风险**: HIGH

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/plan_gateway.dart | +333/-38 | 待办 W13 三字段透传（repeat_rule/rrule_anchor_date/remind_at）+ watchTodoDayInstances 查询时展开；存钱全量：createSavingsGoal（挑战目标推导）/contributeToGoal（幂等打卡+格子推算）/watchSavingsGoalViews 改单条联查（LEFT JOIN+GROUP BY+readsFrom 双表，修复 W5-6 占位实现打卡不刷新）/watchTodayManualContribution/markGoalCompleted 等 |
| lib/src/rrule.dart | +315/-0 | 新文件：RRULE v1 子集（DAILY/WEEKLY BYDAY/MONTHLY BYMONTHDAY/INTERVAL）+ TodoRepeatSpec 五档 + rruleOccursOn 展开 + 提醒时刻换算 + DST 安全 dayDiff |
| lib/src/plan_models.dart | +195/-1 | TodoDayInstance 虚拟实例、SavingsGoalDraft 三构造器（rhythm JSON 约定）、savingsLadderStep 格子推算（未开跑/坏 JSON→null，越顶钳「已收官」） |
| lib/src/pages/todo_page.dart | +102/-30 | 今日视图改读实例流；进阶编辑入口 |
| lib/src/widgets/todo_editor_sheet.dart | +334/-0 | 新文件：重复五档+提醒时刻编辑抽屉（收集箱隐藏重复档） |
| lib/src/pages/savings_page.dart | +211/-62 | 占位页升级为真页（目标卡+创建） |
| lib/src/pages/savings_goal_detail_page.dart | +282/-0 | 新文件：详情页（进度/贡献历史/标记达成/归档） |
| lib/src/widgets/savings_goal_editor_sheet.dart | +284/-0 | 新文件：三种存钱法编辑抽屉 |
| lib/src/widgets/savings_check_in_button.dart | +92/-0 | 新文件：投币打卡按钮（今日已投置灰，文案=格子推算） |
| lib/src/widgets/progress_ring.dart | +135/-0 | 新文件：SlimcaProgressRing |
| lib/feature_plan.dart | +30/-10 | barrel 增 W13 导出 |
| lib/src/plan_providers.dart | +40/-1 | 增 6 个 provider（todoDayInstances/savingsGoals/detail/progress/contributions/todayManual） |
| test/w13_todo_rrule_savings_test.dart | +519/-0 | 新文件：W13 专项（跨两天单 anchor 行两日各一实例等） |
| test/rrule_test.dart | +299/-0 | 新文件：RRULE 子集解析/展开 |
| test/plan_pages_test.dart | +11/-6 | 适配 |

### 影响范围

- **API**: PlanGateway 待办 5 方法签名扩展（+3 可选参数）+ 存钱 10 方法新增；providers +6；页面 +3（Savings 重做、SavingsGoalDetail 新增、Todo 增强）；组件 +4
- **跨模块**: **core_db 同提交变更（关键）**——todos 补列 rrule_anchor_date、savings_contributions 补列 source（v1 内只加列 + beforeOpen 幂等回填，schemaVersion 保持 1）；新增 SavingsGoalsDao/SavingsContributionsDao（+474）；TodoDao 扩展（+67）；DaySummaryProjection 增 savings_progress 重算（+123）；apps/mobile 同提交接线本地通知调度（ReminderSyncCoordinator/ReminderPlanner/FlutterLocalReminderScheduler 适配器、Android 13+ POST_NOTIFICATIONS）+ 仪表盘存钱卡接真数据 + W13 埋点
- **数据模型**: 2 处 v1 内补列（幂等回填，旧库安全）；risk HIGH 的主因——DB 层与投影联动改动影响 feature_ledger/feature_dashboard 读取口径
- **配置**: apps/mobile AndroidManifest 加通知权限

### 回滚指南

- 回滚: `git revert cc86213`（会连带 core_db 补列与壳层通知调度；如只回滚 feature 层，需同时回退 core_db 的两个 backfill 调用点 app_database.dart beforeOpen，否则 analyze 失败）
- 检查文件: packages/core_db/lib/src/app_database.dart（回填调用序）、packages/core_db/lib/src/dao/savings_dao.dart、packages/core_db/lib/src/dao/todo_dao.dart、packages/feature_plan/lib/src/plan_gateway.dart、apps/mobile/lib/notifications/*
- 副作用: 旧 v1 库文件回滚后缺列（表定义仍带列会 schema 不匹配）；已产出的 savings_contributions/todos 重复行数据无降级路径；day_summary.savings_progress 列残留（无害）；本地通知计划残留在系统调度器需壳层清理

---

## [2026-11-16] W5-6 记账完整化+语音(Fake链路)+健身+同步引擎（M1 功能项）

**类型**: feat
**提交**: 3022e4d
**风险**: MEDIUM

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/plan_gateway.dart | +368/-0 | 新文件：计划域网关首版——submitFitnessSession（同事务三行 entries+burn+fitness_sessions，惰性 seed 内置 kcal 账本）、deleteFitnessSession（墓碑+投影回落）、待办 CRUD 透传 TodoDao、watchSessionsByDate/身体档案体重读写 |
| lib/src/fitness_met_table.dart | +193/-0 | 新文件：内置 MET 表 10 活动 × 三档 + estimateKcalBurn（kcal=MET×体重×时长h，非法入参抛 ArgumentError） |
| lib/src/fitness_form_controller.dart | +146/-0 | 新文件：健身表单控制器（AsyncNotifier family，build 装载体重，submit 先持久化体重再落库） |
| lib/src/plan_models.dart | +213/-0 | 新文件：FitnessSeed/FitnessSessionDraft/FitnessFormState（钳 1-1440 分钟、25-300 kg）/SavingsGoalView 占位 |
| lib/src/plan_providers.dart | +52/-0 | 新文件：首批 7 个 reactive provider |
| lib/src/pages/fitness_log_page.dart | +374/-0 | 新文件：手动记录页（表单卡+前后日导航+按日列表） |
| lib/src/pages/todo_page.dart | +226/-0 | 新文件：今日待办/收集箱双视图（W13 前基础版） |
| lib/src/pages/plan_hub_page.dart | +160/-0 | 新文件：计划 Tab 四卡组合页（级联入场+共享轴转场） |
| lib/src/pages/fitness_plan_page.dart | +84/-0 | 新文件：健身计划占位页（读侧接通） |
| lib/src/pages/savings_page.dart | +90/-0 | 新文件：存钱占位页（读侧接通） |
| lib/src/widgets/plan_text_field.dart | +86/-0 | 新文件：token 化输入框 |
| lib/feature_plan.dart | +49/-5 | barrel 从占位扩为全量导出 |
| pubspec.yaml | +17/-36 | workspace 依赖定稿（core_domain/core_db/ui_kit/drift） |
| README.md / CHANGELOG.md | +55/-32、+11/-1 | 包文档改写为 W5-6 全量说明 |
| test/fitness_flow_test.dart 等 4 个 | +301/+90/+153/+238/-12 | 健身流/MET 表/页面/待办流测试；删除 W1 占位测试 feature_plan_test.dart |

### 影响范围

- **API**: 本包 API 表面首次成形——PlanGateway 10 方法、MET 表估算、表单控制器、7 providers、6 页面
- **跨模块**: 同提交大幅改动 6 个公共/兄弟包（core_db entry_line_repository +3/-1、core_domain sync_engine +18、feature_sync 同步引擎首版 9 文件、feature_capture/feature_ledger 功能化、core_ai）以及 apps/mobile 31 文件——本包 burn 行落库契约（type=burn/direction=out/归集 kcal 账本）在此提交定型
- **数据模型**: 无 schema 变更（复用 schema v1 表）；本包定义 FitnessSessionDraft/FormState 值对象
- **配置**: pubspec workspace 定稿

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: chore
**提交**: 3b1f64c
**风险**: LOW

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +55/-0 | 包定义（workspace 成员、依赖声明） |
| lib/feature_plan.dart | +5/-0 | 占位 barrel（仅库注释） |
| test/feature_plan_test.dart | +12/-0 | 占位冒烟测试 |
| README.md / CHANGELOG.md / analysis_options.yaml / LICENSE / .gitignore / .metadata | +39/+3/+4/+1/+31/+10 | 包脚手架 |

### 影响范围

- **API**: 无（占位包）
- **跨模块**: 仓库初始提交（189 文件全仓建户）：core_domain/core_db（schema v1 含 plan 域 21 表定义）/ui_kit/server-supabase 迁移 0001 均在此提交建立——本包后续全部表契约源自此处的 schema v1
- **数据模型**: plan_tables.dart 等 21 表随 schema v1 建立（本包当时未引用）
- **配置**: workspace 根 pubspec.yaml +15
