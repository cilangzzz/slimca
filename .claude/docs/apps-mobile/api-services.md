# apps-mobile 服务与 Provider 注册表

> 壳层是全仓唯一的「装配点」（§10.4）：所有跨包依赖在此 override 注入，页面只经
> provider 取依赖、依赖抽象而非实现。生产装配由 `bootstrap()` 一次性完成；
> 测试一律 override 注入 Fake（禁真实平台通道/网络/计时器）。

## 1. bootstrap() override 清单（lib/app/bootstrap.dart）

缺省 Provider 未 override 会 throw `StateError` 的三个入口用 ⚠ 标注。

| Provider | 生产值 | 测试注入 | 说明 |
|----------|--------|----------|------|
| `appDatabaseProvider` | `AppDatabase()`（driftDatabase 'slimca'） | `AppDatabase(NativeDatabase.memory())` | 主库单例（providers.dart 缺省可自建，但 bootstrap 统一注入同一实例） |
| `hlcClockProvider` ⚠ | `HlcClock(deviceId)` | 可控时钟 | HLC 全序时钟；device_id 依赖异步读 settings，构造必须异步 |
| `captureGatewayProvider` | `createCaptureGateway(db, clock, projection)` | 包内 Fake | feature_capture 录入域网关；投影注入=记一笔后快照同事务重算 |
| `daySummaryProjectionProvider` | `DaySummaryProjection(database)` | 同左 | 投影单例：读路径与写路径共用同一实例 |
| `planGatewayProvider` | `createPlanGateway(db, clock)` | 包内 Fake | feature_plan 网关（模板建档/开练/组明细） |
| `captureParserProvider` | 装饰链（见下） | 包内 Fake | 三层装饰：Telemetry→RawInputGate→工厂 |
| `captureImageSourceProvider` | `ImagePickerCaptureImageSource` | `FakeImageSource` | image_picker 薄封装（拾取参数内压缩 1280/q80） |
| `captureImageCompressorProvider` | `PickerCompressedCaptureCompressor` | `FakeImageCompressor` | 规范化收口：mime 归一 + sha256 content_hash |
| `capturePhotoParserProvider` | `createCapturePhotoParser()` | `FakeCapturePhotoParser` | 百度先行→Vision 兜底 fallback 组合 |
| `captureAttachmentStoreProvider` | `DriftPhotoAttachmentStore` | 包内 Fake | 附件即焚存储 + content_hash 去重 + 本机留档 |
| `captureRawInputCloudEnabledProvider` | `() => policy.enabled` | lambda | 拍照通道闸门（与文本闸门同源开关） |
| `capturePhotoTelemetryProvider` | `FileTelemetryService` | `NoopTelemetryService` | 拍照漏斗（缺省 null=不发事件） |
| `photoBurnPolicyProvider` | `PhotoBurnPolicy()`（装载 settings） | 直接构造 | 即焚开关持有器（默认开） |
| `telemetryServiceProvider` | `FileTelemetryService`（失败回落 Noop） | `NoopTelemetryService` | 遥测（缺省 Noop=零副作用） |
| `rawInputPolicyProvider` | `RawInputPolicy()`（装载 settings） | 直接构造 | raw_input 上云开关持有器（默认关） |
| `syncEngineProvider` ⚠ | `LocalSyncEngine(backend, outbox, store, …)` | 包内 Fake | 必须由 bootstrap override（缺省会误导「已同步」） |
| `syncCoordinatorProvider` ⚠ | `SyncCoordinator(engine, registry, telemetry)` | 直接构造 | 同步生命周期协调器 |
| `reminderSchedulerProvider` | `FlutterLocalReminderScheduler` | `FakeReminderScheduler` | 本地通知调度（真实通道） |
| `initialThemeSettingsProvider` | `loadThemeSettings()` 预载值 | `ThemeSettings(...)` 缺省 | 主题偏好启动初值（首帧零闪跳的关键） |
| `keepAwakeProvider` | `WakelockPlusKeepAwakeService` | `FakeKeepAwakeService` | 训练常亮（Android FLAG_KEEP_SCREEN_ON 免权限） |
| `workoutTimerNotifierProvider` | `FlutterLocalWorkoutTimerNotifier` | `FakeWorkoutTimerNotifier` | 训练常驻通知（渠道 workout_timer） |

## 2. providers.dart 声明（装配枢纽，部分 re-export）

| Provider | 类型 | 说明 |
|----------|------|------|
| `entryRepositoryProvider` / `entryLineRepositoryProvider` | `Drift*Repository` | 事件主干/facet 行仓库（软删墓碑、money 行不可变闸门） |
| `todoDaoProvider` / `savingsGoalsDaoProvider` / `savingsContributionsDaoProvider` | core_db DAO | 均挂投影（写路径同事务重算 day_summary） |
| `savingsServiceProvider` | `SavingsService` | 存钱写路径编排（rhythm/slot/建议额 + W13 漏斗） |
| `ledgerAdminRepositoryProvider` | feature_ledger 抽象 | 预算/分类写路径（BudgetsDao 收口） |
| `ledgerCategoryOptionsProvider` / `ledgerDailyBudgetsProvider` / `monthlyBudgetsProvider` | StreamProvider | 预算设置页/筛选条数据源 |
| `reportRepositoryProvider` | `DriftReportRepository` | 统计报表仓库（day_summary 直读+兜底） |
| `ledgerManageRepositoryProvider` | `DriftLedgerManageRepository` | 账本生命周期（建档/重命名/归档/设默认） |
| `workoutClockProvider` | `DateTime Function()` | 训练域注入时钟（测试 pump 可控） |
| `workoutLogServiceProvider` | `WorkoutLogService` | 训练完成落库（单事务 5 表 + 投影） |
| `fitnessServiceProvider` | `FitnessService` | 健身手动记录写路径 |
| `manualEntryServiceProvider` | `ManualEntryService` | 手动记账写路径（saveNew/editEntry/deleteEntry） |
| `syncBackendLabelProvider` | String | settings 页同步装配描述（dart-define 只读） |
| `billingServiceProvider`（re-export） | `FakeBillingService` | IAP 注入点——真实通道待商店账号，UI 已移除 |

## 3. 页面数据流 providers（features/）

| Provider | 文件 | 说明 |
|----------|------|------|
| `selectedDateProvider` | dashboard_state | 全局选中日（Notifier，切日跨 Tab 一致；周一为一周起点） |
| `dashboardDayProvider` / `dashboardTodosProvider` | dashboard_state | 当日聚合/待办计数（family by date，join entries×entry_lines） |
| `dashboardSavingsProgressProvider` / `dashboardBudgetSnapshotProvider` | dashboard_state | day_summary 快照直读（零业务查询，坏形状自愈为空） |
| `dailyBudgetProvider` / `categoryNamesProvider` | dashboard_state | kcal 每日目标流 / 分类名回填 |
| `ledgerCategoryFilterProvider` / `ledgerDayGroupsProvider` | ledger_state | 全局分类筛选（非 autoDispose）/ 按日分组流水（family by `LedgerBillQuery`） |
| `planTodosProvider` / `planSessionsProvider` / `planSavingsGoalsProvider` / `planScheduleProvider` / `activeFitnessPlansProvider` / `bodyWeightKgProvider` | plan_state | 计划 Tab 全部数据流（reactive stream，墓碑不入） |
| `workoutSessionProvider` | workout_session_controller | 进行中训练（默认 keepAlive；null=无训练） |
| `themeSettingsControllerProvider` / `resolvedThemeProfileProvider` / `slimcaLight|DarkThemeProvider` / `slimcaThemeModeProvider` / `platformCorePaletteProvider` / `themeProfilesStreamProvider` | theme/theme_providers | 主题装配链（settings→包解析→三步装配→MaterialApp+morph） |

## 4. 域服务入口与职责

### 4.1 通知（lib/notifications/）
- `ReminderScheduler`（抽象）→ `FlutterLocalReminderScheduler` / `FakeReminderScheduler`：
  `ensurePermission` / `schedule` / `cancel`；渠道 `todo_reminders`；zonedSchedule 用 UTC
  绝对瞬间（TZDateTime.from(utc, tz.UTC)），`inexactAllowWhileIdle` 不申请精确闹钟权限。
- `planTodoReminders`（纯函数）：一次性未过期 1 条；重复待办 RRULE 在
  max(锚点,今天)→今天+30 天 窗口展开、单待办上限 32 实例。
- `notificationIdFor(todoId, instanceDate)`：FNV-1a 稳定派生（**不用 hashCode**——跨重启不稳定）。
- `ReminderSyncCoordinator.start/stop`：todos 流→重规划→按通知 id 差异对账
  （新增/变更→schedule，消失→cancel）；权限被拒不阻塞、失败静默自愈。
- `expandRruleInstances`（rrule_expand）：RFC5545 子集 DAILY/WEEKLY/MONTHLY +
  INTERVAL/COUNT/UNTIL/BYDAY；未知部件降级忽略不抛错。

### 4.2 计费（lib/billing/）——代码保留、UI 不露出
- `BillingService`（抽象）：`queryProducts` / `purchase` / `restore`；
  `FakeBillingService` 内存流（`failNextPurchase` 注错探针）。
- `kSlimcaSkuCatalog`：双轨四档（买断 98/128 元 + AI 订阅 12/18 元/月，价格待实测复核）。
- V1 UX 插曲后设置页不再渲染付费墙/恢复购买；真实 in_app_purchase 待商店开发者账号。

### 4.3 语音（lib/voice/）
- `SpeechTranscriber`（抽象）→ `FakeTranscriber`（缺省装配，语料轮转）/ `PlatformChannelSpeechTranscriber`（桩，调用即抛 UnimplementedError）。
- 通道契约名 `slimca/speech_transcriber`；转写超时 `kVoiceTranscribeTimeout=5s`。

### 4.4 遥测（lib/telemetry/）
- `TelemetryService`（core_domain 抽象：funnel/metric/crash/flush）→
  `FileTelemetryService`（JSONL 落盘 support/telemetry/telemetry_events.jsonl，串行写队列，
  经 `TelemetryPrivacy.sanitizeProps`）/ `NoopTelemetryService`。
- `FrameTelemetry.attach`：真机帧率埋点，**仅非 debug**装配（debug 数字失真）；
  批聚合 → frameRasterMs/frameDropped 两指标。
- 壳层漏斗事件常量（core_domain 表冻结于 W7-8，新事件落壳层常量）：
  W13 `W13TelemetryFunnel`（savings_goal_created/coin_in/todo_recurrence_created）、
  W14（workout_started/set_logged/workout_completed）、
  W15（report_viewed/budget_set/ledger_switched）、
  W16（theme_editor_opened/theme_changed）。

### 4.5 主题（lib/theme/ + data/）
- `DriftThemeProfileRepository`：theme_profiles 仓库（watchAll/ensureSeeded/saveCustom/softDelete），
  写路径经 `SyncOutboxWriter` 同事务入队；内置包不可删（is_preset 抛 StateError）。
- `ThemeSettingsController`：selectPack/setMotionLevel/setThemeMode/setDynamicColorEnabled——
  状态先行 → 异步落 settings（失败不回滚，本地件自愈）。
- `ensurePresetThemeProfiles`：6 内置包幂等种子（两端独立种子按 id 收敛）。

### 4.6 健身/训练（lib/workout/ + data/workout_log_service.dart）
- `KeepAwakeService`（抽象）→ wakelock_plus 适配器（异常静默降级）/ Fake。
- `WorkoutTimerNotifier`（抽象）→ flutter_local_notifications 适配器（固定 id
  `kWorkoutTimerNotificationId=0x5714`，Chronometer 原生倒计时）/ Fake。
- `WorkoutSessionController`（Riverpod Notifier）：startFromPlan/logCurrentSet/skipRest/
  syncRest/endWorkout——剩余休息秒以**绝对时刻**+注入时钟判定（锁屏可跑的正确性来源）。
- `WorkoutLogService.completeWorkout`：单事务写 fitness_sessions+entries+burn 行+
  N×exercise_sets+outbox+投影重算（组记录训练中内存累积，结束时整体落库）。

### 4.7 同步（lib/sync/）
- `createSyncBackend()`：dart-define 双键齐→`SupabaseSyncBackend`；缺→`LocalLoopbackBackend`。
- `TelemetrySyncBackend`：装饰器记 syncPushOk/Fail、syncPullOk/Fail（只记批次规模+错误类型）。
- `SyncCoordinator.start/syncNow/dispose`：设备注册→立即一轮→15 分钟周期；
  重入合并；`SyncLifecycleObserver`（resumed 触发）。同步异常永不冒泡到 UI。

### 4.8 数据服务（lib/data/）
- `ManualEntryService`：saveNew（confirmed 即金额不可变生效）/ editEntry（修正链 supersede）/
  deleteEntry（软删墓碑）。
- `FitnessService.saveSession`：会话+entries+burn 行+settings 体重同事务；
  `estimateBurnKcal` = MET×体重×时长（±20% 口径 UI 标注）。
- `SavingsService`：createGoal/coinIn（幂等：当日已投币返回既有行与 false）/
  slotForDay/suggestedAmountMinor（365/52 周法阶梯，坏 rhythm 兜底 ¥1）。
- `MultiLedgerService`：watchScopes/createMoneyLedger/switchDefaultLedger——
  指针写入 + **sort 桥接**（默认账本置 money 组首位，对齐 feature_capture 的 sort-first 预选）。
