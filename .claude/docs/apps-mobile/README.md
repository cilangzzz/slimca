# apps-mobile（Flutter 主应用壳）

> 位置 `apps/mobile`；pub workspace 成员包 `slimca`，version 1.1.0+2。
> 定位：**组装壳**（§10.4）——路由 + DI + 主题装配 + 平台通道接线；不承载业务逻辑，
> 业务都在 packages/feature_* 与 core_* 包。

## 1. 模块概述

- 技术栈：Flutter 3.32 + Dart 3.8 / Riverpod 3 / go_router 16 / Drift 2.29（经 core_db）；
- 72 个 Dart 文件（lib/），分层目录：
  `app/`（bootstrap/router/providers/theme）、`ai/`（解析装配）、`billing/`（IAP 骨架，
  UI 不露出）、`data/`（壳层写服务+仓库）、`features/`（薄粘合页面）、`ledger/`（多账本）、
  `notifications/`、`photo/`、`settings/`（本地开关）、`sync/`、`telemetry/`、`theme/`、
  `voice/`、`workout/`、`common/`（格式化）；
- 冷启动承诺：`bootstrap()` 在 runApp 前完成全部异步装配，运行期依赖同步可读、
  页面零等待、无 spinner。

## 2. 依赖地图

壳层 path 依赖（装配目标）：`ui_kit`（主题/动效 token）、`core_domain`（实体+HLC+遥测抽象）、
`core_db`（Drift 21 表+DAO+投影+OutboxWriter，见 [../core_db/README.md](../core_db/README.md)）、
`feature_capture`（唯一录入 UI）、`core_ai`（LLM 管线底座）、`feature_sync`（同步引擎，
见 [../feature_sync/README.md](../feature_sync/README.md)）、`feature_plan`、`feature_ledger`；
直接插件：drift、uuid、path_provider、image_picker、crypto、http、flutter_local_notifications、
timezone、wakelock_plus ^1.4.0、material_color_utilities、package_info_plus。

启动链：`main()` → `bootstrap()`（开库→device_id→HLC→账本种子→投影→主题预载→包种子→
遥测→留存锚→两开关→同步栈→附件清扫→通知调度→计时器底座）→ 崩溃钩子 →
`ProviderScope(overrides: runtime.overrides)` → `MaterialApp.router` + SlimcaThemeMorph。
装配顺序是硬约束，详见 [pitfalls.md](pitfalls.md) §3.1。

## 3. 对外 API 索引（按域）

| 域 | 详情 | 要点 |
|----|------|------|
| 路由表 | [api-routes.md](api-routes.md) | 9 条 go_router 路由 + 3 类 sheet 入口 + 转场纪律（SlimcaSharedAxisPage） |
| 服务/Provider | [api-services.md](api-services.md) | bootstrap 21 项 override + providers.dart 声明 + 页面数据流 + 通知/计费/语音/遥测/主题/健身/同步服务入口 |
| 数据模型与配置键 | [data-model.md](data-model.md) | settings 本地键 10 个 + dart-define 键 10 个 + 壳层视图模型 + JSON 形状约定 |
| 代码模式 | [code-patterns.md](code-patterns.md) | 「新增 feature 页面并接线」6 步 + 装饰器链 + 抽象/适配器/Fake 三件套 + 写路径纪律 |
| 坑点 | [pitfalls.md](pitfalls.md) | 出包目录/Gradle 镜像/dart-define 静默回落/IAP 不露出/装配顺序/测试纪律 |
| 变更历史 | [CHANGELOG.md](CHANGELOG.md) | W1→V1 UX 插曲全量提交分析 |

上游模块文档：[../core_domain/README.md](../core_domain/README.md) ·
[../ui_kit/README.md](../ui_kit/README.md) · [../core_db/README.md](../core_db/README.md) ·
[../feature_capture/README.md](../feature_capture/README.md) ·
[../feature_sync/README.md](../feature_sync/README.md) ·
[../feature_ledger/README.md](../feature_ledger/README.md) ·
[../feature_plan/README.md](../feature_plan/README.md) ·
[../core_ai/README.md](../core_ai/README.md) ·
[../feature_dashboard/README.md](../feature_dashboard/README.md) ·
[../server-supabase/README.md](../server-supabase/README.md)

## 4. 关键服务流程（仅非平凡者）

### 4.1 AI 解析装饰链（文本/语音/拍照共用）
`TelemetryCaptureParser`（埋点最外层）→ `RawInputGateCaptureParser`（开关关=仅发规范化文本，
缓存键不变）→ dart-define 工厂（无 KEY→core_ai HeuristicFakeLlmAdapter；有 KEY→
OpenAiCompatibleAdapter，文本超时 5s）。拍照路径另有 fallback 组合：
百度菜品识别（先行位，token→dish v2，内置快表粗估 kcal、置信度恒 0.35 强制校核）→
Vision LLM（兜底位，OpenAI 兼容多段 content，受约束 JSON）→ 离线桩。

### 4.2 本地通知对账（W13）
`ReminderSyncCoordinator.start()` 订阅 todos（remind_at 非空未删）watch 流 →
`planTodoReminders` 纯函数（重复待办 RRULE 展开 max(锚点,今天)→+30 天、单待办 ≤32 实例）→
按通知 id（FNV-1a 稳定派生）差异对账：新增/变更→schedule、消失→cancel。
权限请求一次性、被拒不阻塞；失败静默下轮自愈。

### 4.3 同步时机（W7-8）
`SyncCoordinator.start()` = 设备注册（幂等）→ 立即一轮 → 15 分钟周期；
前台切回由 `SyncLifecycleObserver`（resumed）触发；重入合并。engine.syncOnce 永不抛、
异常 → telemetry.crash，**同步永不冒泡到 UI**。

### 4.4 训练会话（W14）
`workoutSessionProvider`（keepAlive Notifier）：开练→常亮+常驻通知+漏斗；记组→绝对时刻
倒计时（restEndsAtMs，锁屏/冻结恢复按时钟重算）+原生 Chronometer 通知；结束→单事务落库
（会话+entries+burn+N 组明细+outbox+投影）→常亮 off+通知 cancel。

### 4.5 主题装配（W16）
settings 指针/动效/深浅/dynamic → `ThemeSettingsController` → 包解析（内置包 ui_kit 常量
清单，自定义包 theme_profiles 流）→ ui_kit 三步（toSlimcaTheme→SlimcaDynamicThemeMapper
两源映射→buildTheme）→ MaterialApp theme/darkTheme + builder 内 SlimcaThemeMorph 全屏
morph（300ms/off 100ms）。bootstrap 预载初值=首帧零闪跳。

## 5. 模块特定配置

- **dart-define（10 键，全部可选、缺省静默回落桩）**：SLIMCA_AI_BASE/KEY/MODEL、
  SLIMCA_BAIDU_API_KEY/SECRET_KEY、SLIMCA_VISION_BASE_URL/API_KEY/MODEL、
  SLIMCA_SUPABASE_URL/ANON_KEY——见 [data-model.md](data-model.md) §2；
- **settings 本地键**（永不同步、坏值自愈）：device_id、first_open_day、
  raw_input_cloud_enabled（默认关）、photo_burn_after_parse（默认开）、current_theme_id、
  motion_level、theme_mode_override、dynamic_color_enabled、body_weight_kg——
  见 [data-model.md](data-model.md) §1；
- **Android**：Gradle 阿里云镜像双处、core library desugaring 必开、权限分级清单——
  见 [pitfalls.md](pitfalls.md) §1。

## 6. 本模块已知坑点（速览，详见 pitfalls.md）

1. 出包必须 `cd apps/mobile`；
2. dart-define 缺键**静默**退化为离线桩/本地回环（不报错）；
3. bootstrap 装配顺序硬约束 + 三个 provider 缺省 throw StateError；
4. IAP 代码保留但 UI 不露出（别把付费墙加回来）；
5. 测试禁真实通道/计时器/网络——Fake 三件套注入；
6. raw_input 默认关、即焚默认开——坏值回落更严档。

## 7. 测试布局（结构性）

`apps/mobile/test/` 28 个文件：`e2e_*` 全链路验收（录入→仪表盘/拍照/语音/健身/账本切换/
计划训练）；`*_fake_test`（通知/计费/训练计时器 Fake 断言）；`benchmark/`（帧预算基准）；
manifest 权限测试；`test_support.dart` 装配辅助。口径：V1 收官时 apps/mobile 134 用例、
全仓 771 例全绿、analyze 0 issue。
