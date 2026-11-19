# feature_dashboard — 日期仪表盘

## 模块定位

Slimca 统一日期仪表盘的业务层实现（pub workspace 单包 `packages/feature_dashboard`）：日期大字 + SlimcaCalendar 日历（周条无限横滑 / 垂直形变展开月网格 / 今日锚定簇）+ 卡片墙（热量环 / 支出+本月累计 / 净热量 / 存钱进度）。数据源为 core_db 的 `day_summaries` 投影表，watch 流直驱、快照直出、全程无 spinner。

## 依赖关系

```
feature_dashboard
├── core_domain   → validateCalendarDay / formatCalendarDay（日期口径，见 ../core_domain/README.md）
├── core_db       → AppDatabase + day_summaries 投影表（见 ../core_db/README.md）
├── ui_kit        → SlimcaCalendar 组合容器、SlimcaSharedAxisSwitcher、SlimcaStaggerItem、
│                   SlimcaCalorieRing、SlimcaSpacing/Sizes/MotionConfig token（见 ../ui_kit/README.md）
└── drift ^2.20.0 → reactive stream / innerJoin / insertOnConflictUpdate（Drift 2.x API 口径）
```

被依赖方：无（没有任何包依赖本包，含 apps/mobile，详见 pitfalls#1）。

## 对外 API 索引

入口文件 `lib/feature_dashboard.dart` 一口气导出全部 5 个源文件。页面 + Provider 即对外 API 表面；本包**不含 Riverpod provider**（构造注入装配，接线归宿主）。

| 域 | 入口 | 详情 |
|---|---|---|
| 页面 | `DashboardPage`（真页）、`DashboardDayBody`（卡片墙主体） | [api-pages.md](api-pages.md) |
| 数据 | `DashboardRepository` 抽象（4 方法）+ `DriftDashboardRepository` 实现 | [api-pages.md](api-pages.md) |
| 模型 | `DashboardDaySummary` / `DashboardBudgetSnapshot` / `DashboardSavingsProgress` / `parseSavingsProgress` | [data-model.md](data-model.md) |
| 日历工具 | `DashboardCalendar`（归一化/周历/月网格几何/文案，全静态） | [api-pages.md](api-pages.md) |

## 关键数据流（仅此一条主线）

```
写路径（feature_capture/feature_ledger/... 落库）
  → core_db.DaySummaryProjection 重算 day_summaries 行（§5.6⑬）
  → DriftDashboardRepository.watchDay(date) / watchMonthSpendMinor(month) / watchRecordedDays()
  → StreamBuilder 直驱日期大字 / SlimcaCalendar 月格色点 / 卡片墙
```

- 页面是选中日唯一真值持有点（`_selectedDate`，§3.1 单一真值）；`SlimcaCalendar` 组件本身无选中态。
- 切日 = 外层以日期为 key 重建 `DashboardDayBody`，`SlimcaSharedAxisSwitcher` 承担 280ms 水平共享轴。
- 空态判定只在 `ConnectionState.active` 首值后进行——等待期按全零直出，绝不出加载态。

## 模块特定配置

- 无 dart-define / 环境变量；`uses-material-design: true`（卡片墙用 Material 图标）。
- 依赖版本纪律：drift 必须与 core_db 同为 2.x（解析 2.29）；join 用 `innerJoin()` 函数、upsert 用 `insertOnConflictUpdate`，勿引 Drift 3 的 `InnerJoin` 类写法。

## 详细文档

- [api-pages.md](api-pages.md) — 页面/仓储/日历工具 API 明细 + 数据流与宿主接线
- [data-model.md](data-model.md) — day_summary 投影的读侧模型与 JSON 快照形态
- [code-patterns.md](code-patterns.md) — 新增仪表盘卡片 / 新增 watch 方法的标准步骤
- [pitfalls.md](pitfalls.md) — 已知坑点（含 V1 UX 插曲新日历的手势/转场陷阱）
- [CHANGELOG.md](CHANGELOG.md) — 模块变更历史（真实 git 分析）

## 本模块已知坑点（Top 5，全表见 pitfalls.md）

1. **apps/mobile 并不依赖本包**——App 首页是壳自实现的 `TodayDashboardPage`；本包是包级参考实现 + 新日历 e2e 测试宿主。
2. **`DriftDashboardRepository.recomputeDay` 写 v1 平铺 budget_snapshot**，会覆盖降级 core_db v2 快照——生产写路径一律走 core_db 投影。
3. **切日转场 key 必须放在内层 `DashboardDayBody`**，放 `SlimcaSharedAxisSwitcher` 本体上会吞掉转场。
4. **冷启动 spring 必须包在切日 Switcher 之外**，否则每次切日重播展开动画。
5. **ListView 内双卡等高必须 `IntrinsicHeight`**——Row + `CrossAxisAlignment.stretch` 在无界高度下直接崩。
