# apps-mobile 代码模式与扩展指南

## 1. 新增一个 feature 页面并接线（完整步骤）

以「在计划 Tab 下新增子页面」为例（既有样例：`/plan/fitness`、`/plan/workout`）：

**步骤 1 — 页面实现落点（决定谁写页面）**

- 业务逻辑重、可复用 → 写进对应 `packages/feature_*` 包（如模板管理=`FitnessPlanPage`），
  壳层只做装配屏（参照 `features/stats/stats_report_screen.dart`：注入仓库 + 漏斗埋点 +
  下钻接线，零业务逻辑）；
- 纯壳层页面（路由/转场/跨 Tab 编排）→ 落 `apps/mobile/lib/features/<域>/xxx_page.dart`。

**步骤 2 — 数据流（页面状态与聚合）**

- 聚合数据一律 reactive stream 从明细/真值行重建（§6.1 原则 3，不读投影表做业务聚合），
  参照 `dashboard_state.dart` / `ledger_state.dart` 的 `StreamProvider.autoDispose.family`；
- 家族参数用值对象并实现 `==`/`hashCode`（如 `LedgerBillQuery`），否则 family 缓存失效；
- 全局选择态（选中日/筛选/作用域）用 `NotifierProvider` 非 autoDispose（跨 Tab 保持）；
- 归属日取 `selectedDateProvider`（一切围绕日期）。

**步骤 3 — router 注册（lib/app/router.dart）**

```dart
GoRoute(
  path: 'fitness',
  // 路由级转场一律显式 PageRouteBuilder（§9.5）：go_router pageBuilder 要 Page 不要 Route
  pageBuilder: (context, state) => SlimcaSharedAxisPage(
    name: state.matchedLocation,
    builder: (_) => const FitnessLogPage(),
  ),
),
```

- Tab 内子路由挂到对应 `StatefulShellBranch` 的 `routes:` 下（分支栈内 push，底栏保持）；
- 壳外全屏页挂顶层（参照 `/stats`）；
- push 用 `context.push('/plan/fitness')`，下钻回首页用 `GoRouter.of(context).go('/')`。

**步骤 4 — DI 接线（三选一）**

- 依赖 core_db 表 → 在 `providers.dart` 声明 `Provider`，DAO 挂投影则传
  `ref.watch(daySummaryProjectionProvider)`（写路径同事务联动）；
- 依赖 platform 通道/插件 → 抽象 + 真实适配器 + Fake 三件套（见 §2），provider 缺省绑
  真实适配器（构造零副作用），测试 override Fake；
- 跨包网关（feature_capture/feature_plan）→ provider 缺省 throw `StateError`，
  由 `bootstrap()` override 注入（返回 `AppRuntime.overrides` 列表）。

**步骤 5 — 漏斗埋点（如有验收口径）**

- 新事件名落壳层常量 `lib/telemetry/wNN_funnel_events.dart`（core_domain 表冻结于 W7-8，
  见 §3）；props 只带标量枚举/计数，内容禁入。

**步骤 6 — 测试**

- 新增测试文件落 `apps/mobile/test/`，`ProviderScope(overrides: [...])` 注 Fake 集；
- E2E 参照 `test_support.dart` 的装配辅助；禁真实计时器（用 `workoutClockProvider` 注入时钟
  + `tester.pump` 推进）、禁真实平台通道/网络。

## 2. 设计模式用法

### 2.1 装饰器链（AI 解析三层 + 同步后端一层）

```
captureParserProvider = TelemetryCaptureParser(        ← 最外层埋点（读真实开关位）
  inner: RawInputGateCaptureParser(                    ← raw_input 闸门（关=仅发规范化文本）
    inner: createCaptureParser()))                     ← dart-define 工厂（core_ai 管线桥）
```

- 装饰顺序约束：埋点必须在最外层（`raw_input_cloud` 才反映当次真实经过的闸门状态）；
- 装饰器不吞异常：失败原样上抛（上层降级），只旁路记事件；
- 装饰器不叠加自身 timeout（外层控制器已施加，双超时会晚一拍）。
- 同构用法：`TelemetrySyncBackend(inner: createSyncBackend(), telemetry)` 装饰同步后端
  （push/pull 成败漏斗，异常 rethrow 交 LocalSyncEngine 捕获）。

### 2.2 抽象 + 真实适配器 + Fake 三件套（壳层固定套路）

W13 通知、W14 计时器、语音、计费全部同构：

```
xxx.dart          抽象 interface + 值对象 + 常量（渠道 id/通知 id 派生函数）
xxx_provider.dart 或 providers.dart  注入点（缺省=真实适配器）
flutter_local_xxx.dart / wakelock_plus_xxx.dart  真实适配器（惰性初始化、构造零副作用、
                  平台异常静默吞掉不向上抛——缺失不伤业务 §6.1）
fake_xxx.dart     记录型 Fake（scheduled/cancelled/calls 序列供断言，activeById 存活视图）
```

要点：真实适配器**构造必须零副作用**（平台通道在首方法调用时惰性初始化）——测试误注入
也不会触发通道；实现纪律=异常不向上抛。

### 2.3 开关持有器模式（同步读取的运行期开关）

`RawInputPolicy` / `PhotoBurnPolicy`：可变持有器（非 StreamProvider）——解析/登记路径
同步读取即可，不需要响应式重建；bootstrap 装载初值 override，设置页写「持有器 + settings
落库」两步（先改持有器即刻生效，再异步落库，失败 SnackBar 不回滚页面态）。

### 2.4 写路径纪律（所有壳层写服务共同遵守）

- 业务行 + sync_outbox **同一事务**：优先复用 core_db `SyncOutboxWriter.enqueueRow`
  （写后读回快照入队）；自写仓库则事务内显式 insert outbox（参照 drift_repositories）；
- money 行确认后不可变：改写抛 `MoneyLineImmutableException`，唯一合法路径 supersede
  新增 correction 行；删除一律软删墓碑；
- 每行独立 HLC 发号（`_clock.now()`，行级同步）；UUIDv7 主键应用层生成。

## 3. 扩展点

| 扩展点 | 操作路径 |
|--------|----------|
| 新 LLM 供应商（文本） | 实现 core_ai `LlmAdapter` → capture_parser_factory 分支选择；凭据走新 dart-define 键（命名 `SLIMCA_*`） |
| 新拍照供应商 | 实现 feature_capture `CapturePhotoParser` → photo_parser_factory 组合进 `CapturePhotoParserFallback`（primary/fallback 位次序即优先级） |
| 新漏斗事件 | wNN_funnel_events.dart 增常量 → 业务点埋（props 标量）→ core_domain 收编时平移 |
| 新通知渠道 | rest_timer_notifier.dart 模式：抽象+适配器+Fake；渠道 id 常量；通知 id 派生函数（FNV-1a） |
| 新 settings 开关 | lib/settings/ 新文件（键常量+持有器+load/save 函数，坏值回落更严档）→ 设置页 Switch 行 → bootstrap 装载 override |
| 真实 IAP | 实现 `BillingService` → `billingServiceProvider` 替换（调用方不动）；注意 UI 已移除（见 pitfalls） |
| 真实语音 ASR | 实现 `SpeechTranscriber`（通道名 `slimca/speech_transcriber` 已冻结）→ `speechTranscriberProvider` 按平台探测装配 |
| 端侧小票 OCR | core_ai `ReceiptOcrAdapter`（dart-define 工厂装配）——W16 骨架，真实识别待平台通道 |
