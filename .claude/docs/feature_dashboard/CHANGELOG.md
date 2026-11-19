# Changelog - feature_dashboard

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。
> 范围：`packages/feature_dashboard/`；行数来自 `git show --numstat` 实测。

---

## [2026-11-18] V1 UX 插曲：大厂规范驱动的日历重设计+菜单页重设计+组件约束体系化

**类型**: feat
**提交**: d6650f8
**风险**: HIGH

首页日历整页重做：接入 ui_kit 语义组件 `SlimcaCalendar`（周条无限横滑翻周 + 垂直手势形变展开月网格 + 今日锚定簇），替换原固定七天周条；新增月格色点数据源 API；卡片墙间距/尺寸全面 token 化。

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/widgets/dashboard_page.dart | +226/-156 | 整页重做：换 SlimcaCalendar 接线（selectedDate/recordCounts/expanded 受控）；页头加「今天」pill（离开今天浮现，点击回今日+卡片墙滚顶+280ms SharedAxis 回位）与「月历图标」展开入口；新增 `_ColdStartSpring`（冷启动 scale 0.92→1 只播一次，包在切日 Switcher 外）；「左右滑切日」手势收敛到卡片墙区域（与周条「翻周不切日」双语义分离，速度阈值 120 px/s） |
| lib/src/dashboard_repository.dart | +29/-0 | 新增 `watchRecordedDays()`——全投影表 watch 返回「有记录日」集合，月格 Compact 色点数据源（V1 一点=有记录） |
| lib/src/calendar.dart | +27/-0 | 日历工具补 `parse`/`monthTitle`/`startOfMonth`/`daysInMonth`/`monthGridRows`（月网格几何与文案） |
| lib/src/widgets/day_cards.dart | +33/-22 | 约束审计修正：卡片 radius/padding/间距改引 `sizes.radiusCard`/`spacing.inline`/`spacing.cardInner` token，卡内命中 ≥48 修正 |
| test/dashboard_calendar_test.dart | +444/-0 | 新日历 e2e 5 用例：切日/无限翻周/展开月网格选日/回今日/MotionLevel=off 降级/几何约束断言 |
| test/dashboard_repository_test.dart | +7/-0 | watchRecordedDays 用例 |
| test/dashboard_page_test.dart | +8/-1 | 适配新页头结构 |
| CHANGELOG.md（包级） | +16/-1 | pub 包变更记录补插曲条目 |
| lib/feature_dashboard.dart | +1/-1 | 导出注释更新 |

### 影响范围

- **API**: `DashboardRepository` 新增方法 `watchRecordedDays()`（接口+实现+导出，破坏性无——纯增量）；`DashboardPage` 新增可选参数 `today`/`weekStart`（缺省兼容）
- **跨模块**: 同一提交大改 **ui_kit**（SlimcaCalendar/SlimcaMonthGrid/SlimcaCalendarStrip 组件族、SlimcaSpacing/SlimcaSizes 新 token 层、MotionConfig 增 curveExpand/curveCollapse/curveEffectsStandard）与 **apps/mobile**（设置页 IA 重排、菜单组件族）；其余各包仅测试口径修正。本包页面行为依赖 ui_kit 同批组件——回滚须三包联动（见下）
- **数据模型**: 无 schema 变更（仅读侧新聚合）
- **配置**: 无

### 回滚指南（HIGH）

- 回滚: `git revert d6650f8`（该提交横跨 ui_kit/feature_dashboard/apps/mobile，只能整提交 revert，不可只回本包——页面 import 的新 ui_kit 组件与 token 会一起消失）
- 检查文件: `lib/src/widgets/dashboard_page.dart`、`lib/src/dashboard_repository.dart`（watchRecordedDays 若被新代码引用需一并处理）、三份测试
- 副作用: 回到旧固定七天周条；月格色点 API 移除；ui_kit token 层（Spacing/Sizes/曲线对）同步消失会影响依赖它的设置页改版

---

## [2026-11-16] W2 主线：day_summary 投影/仓储/seed + 手动记账 CRUD 全链路 + 仪表盘真页

**类型**: feat
**提交**: 1ee4ab4
**风险**: HIGH

本包从 W1 空壳变为完整实现：投影读侧模型 + Drift 仓储 + 日期仪表盘真页（热量环/支出/净热量/存钱占位/空态引导）+ 周历切日共享轴 + 三份测试。

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/widgets/day_cards.dart | +526/-0 | 新建卡片墙：热量环卡/支出卡（本月累计独立 StreamBuilder）/净热量卡/存钱占位卡/空态引导，SlimcaStaggerItem 80ms 级联；`_formatMoneyMinor` 分→元展示与千位分组 |
| lib/src/widgets/dashboard_page.dart | +289/-0 | 新建真页：日期大字+周历条+卡片墙，SlimcaSharedAxisSwitcher 切日、构造注入仓库、selectedDate 单一真值 |
| lib/src/dashboard_repository.dart | +225/-0 | 新建 `DashboardRepository` 抽象 + `DriftDashboardRepository`：watchDay/watchMonthSpendMinor/recomputeDay（明细聚合剔墓碑+非 active 行、预算快照、upsert 投影行） |
| lib/src/dashboard_models.dart | +158/-0 | 新建 DashboardDaySummary/DashboardBudgetSnapshot（v1 平铺 tryParse）/DashboardSavingsProgress/parseSavingsProgress，坏 JSON 回退空值不阻塞直出 |
| lib/src/calendar.dart | +64/-0 | 新建 DashboardCalendar 静态工具（归一化/周历/月前缀/文案） |
| lib/feature_dashboard.dart | +26/-5 | 导出全部源文件 |
| test/dashboard_repository_test.dart | +350/-0 | 投影行与 watch 流断言（含墓碑/跨日用例） |
| test/dashboard_page_test.dart | +209/-0 | 内存真库→recomputeDay→页面数值断言 + 切日断言 |
| pubspec.yaml | +15/-36 | workspace 依赖接线（core_db/core_domain/ui_kit/drift） |
| test/feature_dashboard_test.dart | 0/-12 | 删除 W1 占位测试 |

### 影响范围

- **API**: 本包 API 表面全部在此提交建立（1 页面 + 1 卡片墙主体 + 3 仓储方法 + 5 模型类型 + 日历工具）
- **跨模块**: 同一提交还建了 **core_db**（EntryRepository/EntryLineRepository、`DaySummaryProjection` v1、LedgerDao/CategoryDao/TodoDao、seed）、**feature_capture** 全包（CapturePage/CaptureGateway）、**apps/mobile**（bootstrap/Riverpod 装配/路由/E2E）。注意：apps/mobile 自此用**自实现**首页，未依赖本包（见 pitfalls#1）
- **数据模型**: core_db 新增 `day_summaries` 投影表读写（本包只读+重算，无 schema 变更）
- **配置**: pubspec 接入 workspace path 依赖

### 回滚指南（HIGH）

- 回滚: `git revert 1ee4ab4`（整提交横跨 core_db/feature_capture/apps/mobile，包间互相依赖，不可单包回滚）
- 检查文件: 本包全部 lib/ 源文件（本提交新建）+ 三份测试
- 副作用: core_db 投影/仓库与 capture 录入链路一起消失；apps/mobile bootstrap/路由接线同步回退

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层 + 主题动效 token + App 壳

**类型**: chore
**提交**: 3b1f64c
**风险**: LOW（对本模块仅骨架；整提交回滚属全仓级 HIGH，见跨模块标注）

本包以 Flutter 包骨架形式创建（占位 library 文件 + 包级 README/CHANGELOG/analysis_options），无业务代码。

### 变更文件

| 文件 | 变更 | 说明 |
|------|------|------|
| pubspec.yaml | +55/-0 | 包定义：workspace 成员、包描述 |
| README.md（包级） | +39/-0 | Flutter 默认包说明 |
| lib/feature_dashboard.dart | +5/-0 | 占位 library 声明 |
| test/feature_dashboard_test.dart | +12/-0 | 占位冒烟测试 |
| analysis_options.yaml | +4/-0 | lint 配置 |
| .gitignore / .metadata / CHANGELOG.md / LICENSE | +31/+10/+3/+1 | 包脚手架 |

### 影响范围

- **API**: 无（占位）
- **跨模块**: 同一提交建立了全仓地基——**core_db** Drift schema v1（21 表 9 索引）、**core_domain** HLC/事件模型、**ui_kit** token/动效库、**apps/mobile** 壳、CI 与 Supabase 迁移。对本模块无运行时影响
- **数据模型**: 无本模块变更
- **配置**: workspace 分包结构自此确立

---

## 维护说明

- 条目新→旧排列；同一功能的连续提交已合并为单条（本模块 3 个提交各自独立成条，无合并需要）。
- 提交信息多为中文：修复→fix、新增/支持→feat、优化→perf、调整→refactor。
- 新条目追加到本文件顶部「---」分隔线之下第一的位置。
