/// 应用级依赖注入（§10.4 apps/mobile：路由 + DI + 主题装配）。
///
/// W2 Riverpod 接线（§11 W2）：`Provider<AppDatabase>` 单例 + HlcClock 单例 +
/// 各 repository providers——页面/用例只经 provider 取依赖，且依赖抽象
/// （core_domain 仓库接口）而非 Drift 实现（§10.4 分层纪律）。
///
/// AI 解析装配（W3-4 收敛后）：feature_capture 的 captureGatewayProvider /
/// captureParserProvider 由 bootstrap() override 注入（见 lib/app/
/// bootstrap.dart）；解析器工厂在 lib/ai/capture_parser_factory.dart
/// （dart-define SLIMCA_AI_BASE/KEY/MODEL → core_ai adapter，缺省 Fake）。
///
/// W7-8 接线（§11.1「崩溃/性能与漏斗埋点、托管 Supabase 接入、双轨变现
/// 骨架」）：遥测 / raw_input 上云开关 / 计费 / 同步引擎与协调器 providers——
/// 均由 bootstrap() override 注入（AppRuntime 持有，见 lib/app/bootstrap.dart）。
///
/// 装配方式：`bootstrap()`（lib/app/bootstrap.dart）在 runApp 前 await 完成
/// 异步初始化（开库、device_id、内置账本种子），以 override 注入单例；
/// 运行期读取全部同步、零等待（§2.3 全程零等待空屏）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:feature_ledger/feature_ledger.dart'
    show
        DriftLedgerAdminRepository,
        DriftLedgerManageRepository,
        DriftReportRepository,
        LedgerAdminRepository,
        LedgerCategoryOption,
        LedgerManageRepository,
        ReportRepository;
import 'package:feature_sync/feature_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/drift_repositories.dart';
import '../data/workout_log_service.dart' show WorkoutLogService;
import '../notifications/flutter_local_reminder_scheduler.dart'
    show FlutterLocalReminderScheduler;
import '../notifications/reminder_scheduler.dart' show ReminderScheduler;
import '../settings/ai_api_setting.dart' show AiApiConfig;
import '../settings/raw_input_setting.dart';
import '../sync/sync_backend_factory.dart';
import '../sync/sync_coordinator.dart';
import '../telemetry/telemetry.dart';
import '../workout/keep_awake_service.dart' show KeepAwakeService;
import '../workout/flutter_local_workout_timer_notifier.dart'
    show FlutterLocalWorkoutTimerNotifier;
import '../workout/rest_timer_notifier.dart' show WorkoutTimerNotifier;
import '../workout/wakelock_plus_keep_awake.dart'
    show WakelockPlusKeepAwakeService;

export '../billing/billing_provider.dart' show billingServiceProvider;

// ── W16 装配再导出（§11.2 W16 主题应用链路；页面/编辑器经本枢纽取依赖）────
export '../theme/theme_providers.dart'
    show
        corePaletteLoaderProvider,
        currentThemePackNameProvider,
        initialThemeSettingsProvider,
        platformCorePaletteProvider,
        resolvedThemeProfileProvider,
        slimcaDarkThemeProvider,
        slimcaLightThemeProvider,
        slimcaThemeModeProvider,
        themeProfileRepositoryProvider,
        themeProfilesStreamProvider,
        themeSettingsControllerProvider,
        ThemeSettingsController;

/// 应用主库单例（§10.1 数据层选型 Drift）。
///
/// 生产路径：缺省执行器 = core_db `driftDatabase('slimca')`（按平台落
/// path_provider 目录，§5.1）；测试路径：override 为
/// `AppDatabase(NativeDatabase.memory())` 内存库。
final appDatabaseProvider = Provider<db.AppDatabase>((ref) {
  final database = db.AppDatabase();
  ref.onDispose(database.close);
  return database;
});

/// HLC 混合逻辑时钟单例（§6.3：物理段取 max、同 ms 计数器自增、
/// 定宽编码字典序=全序、回拨不影响全序）。
///
/// 必须由 bootstrap() override 后使用：device_id 需异步读 settings 表
/// （§5.6⑲）才能构造时钟，而 Provider 构造是同步的——启动期一次性装配。
/// 读取方（写路径用例、删键按钮）一律 ref.read 即取即用，每次发号单调
/// （§6.3 全序纪律）。
final hlcClockProvider = Provider<HlcClock>((ref) {
  throw StateError(
    'hlcClockProvider 未装配：必须由 bootstrap() override 后使用'
    '（device_id 依赖异步读 settings，见 lib/app/bootstrap.dart）',
  );
});

/// 事件主干仓库 provider（§5.2① entries；接口定义 core_domain/repository.dart）。
final entryRepositoryProvider = Provider<EntryRepository>((ref) {
  return DriftEntryRepository(ref.watch(appDatabaseProvider));
});

/// 产出行（facet 行）仓库 provider（§5.2②/§5.3 entry_lines）。
final entryLineRepositoryProvider = Provider<EntryLineRepository>((ref) {
  return DriftEntryLineRepository(ref.watch(appDatabaseProvider));
});

/// 待办 DAO provider（§5.5⑩ todos、§3.6 待办基础 P0；W5-6 计划 Tab 接入）。
///
/// TodoDao 内部经 LocalWriteClock 惰性解析 device_id/HLC（core_db，§6.3）：
/// 与 bootstrap() 写入 settings 的同一 device_id 键（kSettingDeviceId），
/// 全库共享同一设备标识。
///
/// W13：DAO 挂投影（§5.6 重建规则「业务行 + 投影同事务」）——待办增改删
/// 联动重算当日 day_summary（todo_done/todo_total），与 feature_plan 网关
/// 装配口径一致。
final todoDaoProvider = Provider<db.TodoDao>((ref) {
  return db.TodoDao(
    ref.watch(appDatabaseProvider),
    projection: ref.watch(daySummaryProjectionProvider),
  );
});

// ── W13 装配（§11.2 W13：待办完整版+存钱目标+本地通知）────────────────

/// day_summary 投影单例（§5.6⑬；仪表盘/存钱卡快照直出与写路径同事务联动
/// 共用同一实例）。
final daySummaryProjectionProvider = Provider<db.DaySummaryProjection>((ref) {
  return db.DaySummaryProjection(ref.watch(appDatabaseProvider));
});

/// 存钱目标 DAO provider（§5.5⑪；W13 写路径同事务联动投影 savings_progress）。
final savingsGoalsDaoProvider = Provider<db.SavingsGoalsDao>((ref) {
  return db.SavingsGoalsDao(
    ref.watch(appDatabaseProvider),
    projection: ref.watch(daySummaryProjectionProvider),
  );
});

/// 存钱贡献 DAO provider（§5.5⑫ append-only；同事务联动投影）。
final savingsContributionsDaoProvider =
    Provider<db.SavingsContributionsDao>((ref) {
  return db.SavingsContributionsDao(
    ref.watch(appDatabaseProvider),
    projection: ref.watch(daySummaryProjectionProvider),
  );
});

/// 提醒调度器注入点（§11.2 W13 任务 3，§10.4 壳负责装配）。
///
/// 缺省 = [FlutterLocalReminderScheduler]（真实通道；平台交互惰性初始化，
/// 构造零副作用）。测试一律 override 记录型 Fake（FakeReminderScheduler，
/// 禁真实通知/平台通道）。
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return FlutterLocalReminderScheduler();
});

// ── W15 装配（§11.2 W15：多账本+预算体系+统计报表）────────────────────

/// 账本管理仓库 provider（feature_ledger 抽象 §10.4 分层纪律）：分类管理页、
/// 每日目标（budgets period=daily §5.4⑥）与分类筛选条共用。
final ledgerAdminRepositoryProvider = Provider<LedgerAdminRepository>((ref) {
  return DriftLedgerAdminRepository(ref.watch(appDatabaseProvider));
});

/// 分类选项流（§5.4⑤；筛选条/预算设置页的分类清单共用）。
final ledgerCategoryOptionsProvider =
    StreamProvider<List<LedgerCategoryOption>>((ref) {
  return ref.watch(ledgerAdminRepositoryProvider).watchCategoryOptions();
});

/// 现行每日目标流（budgets period=daily 且未删，§5.4⑥；预算设置页数据源）。
final ledgerDailyBudgetsProvider = StreamProvider((ref) {
  return ref.watch(ledgerAdminRepositoryProvider).watchDailyBudgets();
});

/// 现行月度预算流（budgets period=monthly，§5.4⑥ P1；W15 预算设置页；
/// W15 收口：feature_ledger admin 仓库 → core_db BudgetsDao 写路径）。
final monthlyBudgetsProvider = StreamProvider((ref) {
  return ref.watch(ledgerAdminRepositoryProvider).watchMonthlyBudgets();
});

/// 报表仓库 provider（W15 统计报表：feature_ledger `ReportRepository`，
/// day_summary 直读 + entry_lines 兜底，§5.6⑬；/stats 页装配）。
final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return DriftReportRepository(ref.watch(appDatabaseProvider));
});

/// 账本管理仓库 provider（W15 多账本生命周期：feature_ledger
/// `LedgerManageRepository`——建档/重命名/归档/设默认，写路径委托 core_db
/// LedgerDao §5.4④；账本管理页装配）。
final ledgerManageRepositoryProvider = Provider<LedgerManageRepository>((ref) {
  return DriftLedgerManageRepository(ref.watch(appDatabaseProvider));
});

// ── W14 装配（§11.2 W14：健身计划/组间计时器/漏斗）────────────────────

/// 唤醒锁注入点（W14 任务 2「KeepAwakeService 抽象 + wakelock_plus 适配器」，
/// §10.4 壳负责装配）。
///
/// 缺省 = [WakelockPlusKeepAwakeService]（wakelock_plus 真实适配器；构造
/// 零副作用，平台通道在首法调用时发生，异常内部静默降级）。测试一律
/// override 记录型 Fake（FakeKeepAwakeService，禁真实平台通道）。
final keepAwakeProvider = Provider<KeepAwakeService>((ref) {
  return const WakelockPlusKeepAwakeService();
});

/// 常驻计时通知注入点（W14 任务 2「通知常驻计时，复用 W13
/// flutter_local_notifications 适配器」，§10.4 壳负责装配）。
///
/// 缺省 = [FlutterLocalWorkoutTimerNotifier]（与 W13 同一插件、同款惰性
/// 初始化，独立渠道 workout_timer）。测试一律 override 记录型 Fake
/// （FakeWorkoutTimerNotifier，禁真实通知）。
final workoutTimerNotifierProvider = Provider<WorkoutTimerNotifier>((ref) {
  return FlutterLocalWorkoutTimerNotifier();
});

/// 训练域注入时钟（W14 任务 5「Fake/注入时钟」）：控制器与 UI 的一切时刻
/// 判定经本函数取 now——测试 override 可控时钟（pump 推进），禁真实计时器
/// 断言；生产缺省 = 设备墙钟。
final workoutClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// 训练完成落库服务（W14 组明细写路径：§5.5⑦⑨ + §6.2 outbox/投影，
/// 复用 core_db SyncOutboxWriter 与 DaySummaryProjection）。
final workoutLogServiceProvider = Provider<WorkoutLogService>((ref) {
  return WorkoutLogService(
    database: ref.watch(appDatabaseProvider),
    clock: ref.watch(hlcClockProvider),
    projection: ref.watch(daySummaryProjectionProvider),
  );
});

// ── W7-8 装配（§11.1：遥测 / raw_input 开关 / 计费 / 同步）────────────────

/// 遥测服务注入点（§3.9 监控、§10.4 壳负责装配）。
///
/// 缺省 = [NoopTelemetryService]（空实现）：并行测试与未 override 的环境
/// 零副作用；生产由 bootstrap() 装配 [FileTelemetryService]（本地 JSONL
/// 落盘，§3.9 隐私口径），装配失败亦回落 Noop（遥测缺失不伤业务）。
final telemetryServiceProvider = Provider<TelemetryService>(
  (ref) => const NoopTelemetryService(),
);

/// raw_input 上云开关运行期持有（§3.7 数据主权、§3.3 默认关=即用即焚）。
///
/// 缺省 = 新持有器（enabled=false 默认关）；bootstrap() 读 settings 表
/// （§5.6⑲）装入上次的用户选择并 override。设置页写回持有器 + 落库。
final rawInputPolicyProvider = Provider<RawInputPolicy>(
  (ref) => RawInputPolicy(),
);

/// AI 服务配置 seed（bootstrap 预载 settings 初值；null=测试/未装配缺省）。
final aiApiConfigSeedProvider =
    Provider<(AiApiConfig, bool)?>((ref) => null);

/// AI 服务配置运行期持有（用户拍板：默认空 = 离线确定性桩，配置后 =
/// OpenAI 兼容 adapter；「从未保存过」= dart-define 开发联调回退，
/// 见 ai_api_setting.dart 注）。settings 本地件、永不同步——key 只存本机。
class AiApiConfigController extends Notifier<(AiApiConfig, bool)> {
  @override
  (AiApiConfig, bool) build() =>
      ref.watch(aiApiConfigSeedProvider) ?? (const AiApiConfig(), false);

  /// 设置页保存后写回（captureParserProvider 响应式重装，下一次解析生效）。
  void save((AiApiConfig, bool) value) => state = value;
}

final aiApiConfigProvider =
    NotifierProvider<AiApiConfigController, (AiApiConfig, bool)>(
  AiApiConfigController.new,
);

/// 同步引擎注入点（§6.2 客户端引擎、§10.4 装配）。
///
/// 必须由 bootstrap() override（依赖开库、device_id 与后端装配——均异步）；
/// 无默认实现（缺省装配会误导「已同步」心智，§6.1 本地优先）。
final syncEngineProvider = Provider<LocalSyncEngine>((ref) {
  throw StateError(
    'syncEngineProvider 未装配：必须由 bootstrap() override 后使用'
    '（依赖 AppDatabase/device_id/同步后端，见 lib/app/bootstrap.dart）',
  );
});

/// 同步生命周期协调器注入点（§6.2 同步时机、§10.4 装配；main() start()）。
final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  throw StateError(
    'syncCoordinatorProvider 未装配：必须由 bootstrap() override 后使用'
    '（见 lib/app/bootstrap.dart）',
  );
});

/// 当前同步装配的面向用户描述（settings 页状态行；dart-define 只读常量）。
final syncBackendLabelProvider = Provider<String>((ref) {
  return describeSyncBackend();
});
