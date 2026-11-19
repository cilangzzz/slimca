# feature_dashboard 已知坑点

按跨模块价值排序。1-2 条涉及其他模块的正确性，最优先阅读。

## 1. apps/mobile 不依赖本包——首页是壳自实现的「平行仪表盘」

全仓（含 apps/mobile 的 pubspec 与所有 dart 文件）没有任何对 `feature_dashboard` 的 import；App 首页 Tab 渲染的是 `apps/mobile/lib/features/dashboard/today_dashboard_page.dart`（自带 `DashboardDay`/Riverpod provider 群，直读 core_db）。本包 `DashboardPage` 是包级参考实现 + 新日历 e2e 测试宿主（W2 起「双轨」并存）。改本包页面**不会**改变 App 实际首页；反之 App 侧改版也不回写本包。接包或收敛二轨时，以 [../apps-mobile/README.md](../apps-mobile/README.md) 的现状为准。

## 2. DriftDashboardRepository.recomputeDay 会把 budget_snapshot 覆写为 v1 平铺形态

本包 `recomputeDay` 的预算快照只取「每日全类目预算」（kcal 账本→kcal_budget、money 账本→spend_budget_minor），upsert 时整行覆写 `budget_snapshot`。而生产写路径（feature_capture/feature_ledger/feature_plan/feature_sync）一律走 core_db `DaySummaryProjection`（W15 起 **v2** 形态：daily+monthly 逐项 used/remaining/carry_over）。若对本包 `recomputeDay` 的当日调用发生在 v2 重算之后，该日快照被**降级覆写**，v2 读取端（统计/预算页）丢失逐项数据。core_db 已将此列为 W15 集成披露项——新代码一律调 core_db 投影，本包方法仅测试使用。

## 3. 切日转场的 key 必须放在内层 DashboardDayBody

`SlimcaSharedAxisSwitcher` 的 AnimatedSwitcher 依赖 child key 变化触发转场。key 若放 Switcher 本体，切日时 Switcher 整体重挂载，转场被吞（无动画硬切）。正确写法：

```dart
SlimcaSharedAxisSwitcher(
  child: DashboardDayBody(key: ValueKey<String>(dateKey), ...),
)
```

## 4. 冷启动 spring 必须包在切日 Switcher 之外

`_ColdStartSpring` 是 TweenAnimationBuilder，只要子树不重建就只播一次。若被放进切日 Switcher 内层，每次切日都会重播展开动画。页面结构：`_ColdStartSpring(SlimcaSharedAxisSwitcher(日期大字 Row))`——spring 包外、共享轴包内，两层动画职责分离。

## 5. SlimcaCalendar 受控展开：受控值变更不回发，宿主勿自造环

`expanded` + `onExpandedChanged` 是受控组合容器契约：组件只在**手势/收起箭头**触发变更时回发，宿主 setState 造成的受控值变化不回发。宿主侧（页头「月历图标」）只需 `setState(() => _calendarExpanded = !_calendarExpanded)`，不要在 `onExpandedChanged` 里再 setState 同一值以外的逻辑引发二次重建环。组件侧的拖拽/取消守卫坑（`onVerticalDragCancel` 幽灵事件）见 [../ui_kit/README.md](../ui_kit/README.md)。

## 6. ListView 内双卡等高必须 IntrinsicHeight

卡片墙在 `ListView` 里（子项高度无界）。支出/净热量双卡 `Row + CrossAxisAlignment.stretch` 直接拿无限高度约束崩溃——必须包 `IntrinsicHeight` 取双卡固有高度作有界约束。W1 骨架踩过并修复，新增并排卡片同坑。

## 7. 空态判定必须等 ConnectionState.active 首值

投影行未重建时 `watchDay` 先发 `null`。若拿 `summary == null` 直接判空态，冷启动首帧会误闪「今天还没有记录」。正确口径：`connectionState == ConnectionState.active && (summary == null || !summary.hasAnyRecord)` 才出空态引导；等待期按全零直出、无任何 spinner（§3.2 快照直出红线）。

## 8. 日期/月份串校验是 fail-fast 的，区间查询依赖定宽字典序

`watchDay`/`recomputeDay` 对非 `yyyy-MM-dd`、`watchMonthSpendMinor` 对非 `yyyy-MM` 直接抛 `ArgumentError`（不静默回退）。月区间 = `[yyyy-MM-01, 下月-01)` 的 TEXT 比较——若有人改成非定宽日期（如 `yyyy-M-dd`）字典序即失效。跨模块约定同 core_domain 口径（[../core_domain/README.md](../core_domain/README.md)）。

## 9. watchRecordedDays 是全表 watch

月格色点数据源 watch 整张 `day_summaries`（每次投影行变更全量重发 Set）。成立前提：本地单用户、一天一行、规模有界。若未来做多用户/长年份数据（万行级），先改逐月订阅再谈色点扩展（V1 一点=有记录；点数/分类色映射是 W17 预留）。

## 10. 测试宿主差异：Windows 缺 sqlite3 → 温和跳过；手势口径有三条例外

- 三份测试都带 `_isSqliteLibraryMissing` 探针守卫（`sqlite3.dll` 动态库缺失 → print SKIP 而非红 CI）——统计测试数时注意 skipped 不计入绿数；
- 周条/月网格横滑必须 `tester.flingFrom` 多采样；形变容器垂直拖必须多段短位移——日格 InkWell 在场时单次大位移手动拖拽的首段会被并入 drag start；
- 断言前先 `pumpAndSettle` 收敛动画，否则命中测试落在动画中段 miss。
