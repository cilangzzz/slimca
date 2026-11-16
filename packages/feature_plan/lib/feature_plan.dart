/// Slimca 计划域（feature_plan，§10.4 packages/feature_plan）。
///
/// 职责（§3.5/§3.6/§5.5、§11.1 W5-6）：
/// - 健身手动记录页 [FitnessLogPage]：内置 MET 表类型选择 + 强度档 + 时长
///   → kcal = MET × 体重 × 时长（±20% 口径标注，§3.5）→ 同事务落
///   entries(kind=fitness) + entry_lines(type=burn,out) + fitness_sessions
///   （§5.5⑦，经 [PlanGateway]），投影联动重算（§5.6）；列表按日查看/删除；
/// - 待办完整雏形 [TodoPage]：今日待办/收集箱双视图（§3.6），勾选联动
///   day_summary.todo_done（§5.6，done_at 只前进合并 §6.5）；
/// - 存钱目标占位页 [SavingsPage]（W13 全量）与健身计划占位页
///   [FitnessPlanPage]（W14）：读侧 reactive 已接通、空态引导；
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
/// DriftEntryLineRepository / TodoDao / DaySummaryProjection），本包只做
/// feature 层编排与视图；主题/动效只引用 ui_kit 既有 token 与转场
/// （§8.2/§9.2，禁裸色值/裸时长）。
library;

// ── 网关与 DI 点（宿主装配入口，§10.4）──────────────────────────────
export 'src/plan_gateway.dart' show PlanGateway, createPlanGateway, planGatewayProvider, kSettingBodyWeightKg, kDefaultBodyWeightKg;

// ── MET 表与估算（§3.5）────────────────────────────────────────────
export 'src/fitness_met_table.dart';

// ── 值对象与表单状态（§3.5/§5.5）───────────────────────────────────
export 'src/plan_models.dart';

// ── 表单控制器（§10.1）────────────────────────────────────────────
export 'src/fitness_form_controller.dart' show FitnessFormController, fitnessFormControllerProvider;

// ── reactive 读侧（§10.1 Drift watch 直驱）─────────────────────────
export 'src/plan_providers.dart';

// ── 页面（§4.2 计划 Tab / §3.5 / §3.6）─────────────────────────────
export 'src/pages/plan_hub_page.dart' show PlanHubPage;
export 'src/pages/fitness_log_page.dart' show FitnessLogPage, fitnessSubmitKey, fitnessDurationFieldKey, fitnessWeightFieldKey, fitnessDeleteKey;
export 'src/pages/todo_page.dart' show TodoPage, todoInputKey, todoAddKey, todoCheckKey, todoDeleteKey, todoMoveTodayKey;
export 'src/pages/savings_page.dart' show SavingsPage;
export 'src/pages/fitness_plan_page.dart' show FitnessPlanPage;
