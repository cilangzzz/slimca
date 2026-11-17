/// Slimca 计划域（feature_plan，§10.4 packages/feature_plan）。
///
/// 职责（§3.5/§3.6/§5.5、§11.1 W5-6、§11.2 W13）：
/// - 健身手动记录页 [FitnessLogPage]：内置 MET 表类型选择 + 强度档 + 时长
///   → kcal = MET × 体重 × 时长（±20% 口径标注，§3.5）→ 同事务落
///   entries(kind=fitness) + entry_lines(type=burn,out) + fitness_sessions
///   （§5.5⑦，经 [PlanGateway]），投影联动重算（§5.6）；列表按日查看/删除；
/// - 待办完整版 [TodoPage]（W13，§3.6/§11.2 主线）：今日待办/收集箱双视图；
///   重复待办按 anchor **查询时展开当日实例、不预生成行**（§5.5⑩
///   repeat_rule/rrule_anchor_date，展开与取舍见 `rrule.dart`）；提醒时刻
///   落 remind_at 字段（真实通知由壳层调度）；勾选联动
///   day_summary.todo_done（§5.6，done_at 只前进合并 §6.5）；
/// - 存钱目标（W13，§3.6 留存钩子）：目标列表页 [SavingsPage]（进度环
///   moneyIn token + 投币打卡）+ 新建目标抽屉（365 天挑战/52 周挑战/
///   自定义）+ 目标详情 [SavingsGoalDetailPage]（进度/贡献历史/标记达成/
///   归档）；写路径经 SavingsGoalsDao/SavingsContributionsDao（append-only
///   + 幂等防重复，§5.5⑪⑫），同事务驱动 day_summary.savings_progress
///   （§5.6⑬ W13 实装）；存钱与账本流水 V1 不联动（开放问题 #9，待拍板）；
/// - 健身计划占位页 [FitnessPlanPage]（W14）：读侧 reactive 已接通、空态
///   引导；
/// - 计划域组合页 [PlanHubPage]（§4.2 计划 Tab 默认实现，宿主可拆卡嵌入）。
///
/// 依赖注入契约（§10.4 壳负责装配）：宿主必须 override
/// ```dart
/// planGatewayProvider.overrideWithValue(
///   createPlanGateway(db: appDatabase, clock: hlcClock),
/// )
/// ```
/// 其中 HlcClock 必须是应用级单例（§6.3 HLC 单调性）。未 override 直接读
/// 即抛 [UnimplementedError]——装配遗漏开发期立刻暴露。
///
/// 分层边界（§10.4）：持久化语义全部复用 core_db（DriftEntryRepository /
/// DriftEntryLineRepository / TodoDao / SavingsGoalsDao /
/// SavingsContributionsDao / DaySummaryProjection），本包只做 feature 层
/// 编排与视图；主题/动效只引用 ui_kit 既有 token 与转场（§8.2/§9.2，
/// 禁裸色值/裸时长）。
library;

// ── 网关与 DI 点（宿主装配入口，§10.4）──────────────────────────────
export 'src/plan_gateway.dart' show PlanGateway, createPlanGateway, planGatewayProvider, kSettingBodyWeightKg, kDefaultBodyWeightKg;

// ── MET 表与估算（§3.5）────────────────────────────────────────────
export 'src/fitness_met_table.dart';

// ── 值对象与表单状态（§3.5/§3.6/§5.5）──────────────────────────────
export 'src/plan_models.dart';

// ── RRULE v1 子集与提醒时刻换算（§3.6 待办完整版 W13、§5.5⑩）────────
export 'src/rrule.dart';

// ── 表单控制器（§10.1）────────────────────────────────────────────
export 'src/fitness_form_controller.dart' show FitnessFormController, fitnessFormControllerProvider;

// ── reactive 读侧（§10.1 Drift watch 直驱）─────────────────────────
export 'src/plan_providers.dart';

// ── 域内组件（§3.6 存钱进度环 moneyIn 变体 / W13 编辑抽屉）──────────
export 'src/widgets/progress_ring.dart' show SlimcaProgressRing;
export 'src/widgets/todo_editor_sheet.dart' show TodoEditorSheet, todoEditorTitleKey, todoEditorNoteKey, todoEditorSaveKey, todoRepeatChipKey, todoWeekdayChipKey, todoEditorMonthDayKey, todoEditorIntervalKey, todoEditorRemindToggleKey, todoEditorRemindPickKey, todoEditorRemindClearKey;
export 'src/widgets/savings_goal_editor_sheet.dart' show SavingsGoalEditorSheet, savingsNameFieldKey, savingsMethodChipKey, savingsUnitFieldKey, savingsTargetFieldKey, savingsDailyFieldKey, savingsDeadlinePickKey, savingsGoalSubmitKey;
export 'src/widgets/savings_check_in_button.dart' show SavingsCheckInButton, savingsCheckInKey;

// ── 页面（§4.2 计划 Tab / §3.5 / §3.6）─────────────────────────────
export 'src/pages/plan_hub_page.dart' show PlanHubPage;
export 'src/pages/fitness_log_page.dart' show FitnessLogPage, fitnessSubmitKey, fitnessDurationFieldKey, fitnessWeightFieldKey, fitnessDeleteKey;
export 'src/pages/todo_page.dart' show TodoPage, todoInputKey, todoAddKey, todoAdvancedKey, todoCheckKey, todoDeleteKey, todoMoveTodayKey;
export 'src/pages/savings_page.dart' show SavingsPage, savingsCreateKey, savingsEmptyCreateKey, savingsGoalCardKey, savingsMethodLabel, savingsStatusLabel, savingsSlotLabel;
export 'src/pages/savings_goal_detail_page.dart' show SavingsGoalDetailPage, savingsCompleteKey, savingsDeleteKey, savingsContributionKey;
export 'src/pages/fitness_plan_page.dart' show FitnessPlanPage;
