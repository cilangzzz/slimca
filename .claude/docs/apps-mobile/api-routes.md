# apps-mobile 路由表与页面入口

> 全部路由定义于单一全局单例 `slimcaRouter`（`lib/app/router.dart`），`MaterialApp.router` 消费。
> 4 Tab 由 `StatefulShellRoute.indexedStack` 承载，各 Tab 独立导航栈并保留滚动位置；
> 中央悬浮「+」为录入抽屉（非路由页面）。

## 1. 路由表（go_router）

| 路径 | 页面 | 所属包 | 转场 | 说明 |
|------|------|--------|------|------|
| `/` | `TodayDashboardPage` | apps/mobile `features/dashboard/` | 默认 | Tab 1 今天：唯一首页，日期仪表盘（无 spinner 冷启动承诺） |
| `/ledger` | `LedgerPage` | apps/mobile `features/ledger/` | 默认 | Tab 2 账本：多账本切换器+分类筛选条+按日分组流水 |
| `/ledger/budgets` | `BudgetSettingsPage` | apps/mobile `features/ledger/` | `SlimcaSharedAxisPage` | 预算设置：每日总额/每日热量/分类每日/月度四区块；分支栈内 push |
| `/plan` | `PlanPage` | apps/mobile `features/plan/` | 默认 | Tab 3 计划：待办/健身/存钱/健身计划四卡 |
| `/plan/fitness` | `FitnessLogPage` | apps/mobile `features/plan/` | `SlimcaSharedAxisPage` | 健身手动记录表单 |
| `/plan/workout` | `WorkoutRunnerPage` | apps/mobile `features/workout/` | `SlimcaSharedAxisPage` | 训练中页（排期卡「开始训练」置态后推入） |
| `/plan/plans` | `FitnessPlanPage` | **packages/feature_plan** | `SlimcaSharedAxisPage` | 健身计划模板管理（壳内不重复建档 UI） |
| `/settings` | `SettingsPage` | apps/mobile `features/settings/` | 默认 | Tab 4 我的：IA 分组卡（账号/AI 服务/外观/数据/低频组/危险组）；「数据与隐私」开关组已移除（底层策略保留） |
| `/stats` | `StatsReportScreen` | apps/mobile `features/stats/`（壳装配屏）+ **packages/feature_ledger** `ReportPage`（页面本体） | `SlimcaSharedAxisPage` | 统计报表：壳外全屏路由（返回回账本 Tab 栈） |

路由级转场纪律：接入子路由时一律显式注入 `SlimcaSharedAxisPage`（ui_kit Page 包装，
`pageBuilder` 契约要求返回 Page 而非 Route）；禁止裸 `MaterialPageRoute`。

## 2. 非路由页面入口（sheet/抽屉）

| 入口 | 触发点 | 内容 | 所属包 |
|------|--------|------|--------|
| `showCaptureChannelsSheet` | 底栏中央 FAB（任意 Tab） | 录入通道抽屉：写/说/拍三通道切换条 + 通道体 | 壳层 `features/capture/`；「写」通道体 = feature_capture `CapturePage` |
| └ 写通道 | 通道条「写」chip | 文本录入（唯一录入 UI 纪律） | feature_capture `CapturePage` |
| └ 说通道 | 通道条「说」chip | `VoiceCapturePanel`（Fake 转写链路） | 壳层 + voice/ |
| └ 拍通道 | 通道条「拍」chip | `PhotoCapturePanel`（拍照/相册路径） | 壳层 + photo/ + ai/ |
| `showCaptureSheet`（feature_capture） | 账本页点条目 / 仪表盘今日记录卡 | 编辑表单（修正链：编辑=新增 correction 行） | feature_capture |
| `showThemeEditorPanel` | 设置页「外观→主题」行 | `ThemeEditorSheet`：6 内置包网格+自定义包+dynamic 开关+深浅覆盖 | 壳层宿主 + ui_kit `ThemeEditorPanel` 本体 |

三通道共享同一 `CaptureSeed` → 同一 `captureControllerProvider(seed)` 实例
（family by seed，sheet 顶层 watch 保活）——通道切换不丢输入/解析中间态/待焚原件。

## 3. 导航关联动作（跨页面数据面）

| 动作 | 行为 |
|------|------|
| FAB 按下 | 记 `captureOpen` 漏斗（起点）；`onSubmitted` 记 `captureConfirm` 漏斗（终点）+ `capture_open_to_confirm_ms` 指标 |
| `/stats` 图元下钻「看当日」 | `selectedDateProvider.select(bucketKey)` 置位 → `go('/')` 回唯一首页 |
| 仪表盘支出卡「per-分类明细」 | `ledgerCategoryFilterProvider.select(categoryId)` 预选 → `/ledger`（筛选态跨 Tab 保持） |
| 设置页「同步」行 | 手动 `syncCoordinatorProvider.syncNow()`（非路由） |
| 账本页点条目 | `showCaptureSheet` 编辑抽屉（source 不变，修正链） |

## 4. Tab 结构（§4.2 定稿）

- Tab 1 今天 `/`、Tab 2 账本 `/ledger`、Tab 3 计划 `/plan`、Tab 4 我的 `/settings`；
- 底栏 `NavigationBar` + `FloatingActionButtonLocation.centerDocked`；
- 切 Tab 走 `navigationShell.goBranch`（IndexedStack 不重建、保留栈内状态）；
- 训练中态卡（仪表盘）读 `workoutSessionProvider`——默认 keepAlive，切 Tab 不丢进行中训练。
