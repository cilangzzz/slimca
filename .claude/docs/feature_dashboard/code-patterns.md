# feature_dashboard 代码模式

## 新增一张仪表盘卡片的步骤

以现有卡为模板（`lib/src/widgets/day_cards.dart`），按序：

1. **私有卡 Widget**：在 `day_cards.dart` 新增 `_XxxCard extends StatelessWidget`，数据入参为 `DashboardDaySummary? summary`（或自建 StreamBuilder 订阅新流）；
2. **容器纪律**：外层一律 `_DashboardCard`（内部统一 `surfaceCard` + `sizes.radiusCard` + `spacing.inline` padding，禁裸字面量）；
3. **挂载**：在 `DashboardDayBody` 的 Column 中插入 `SlimcaStaggerItem(index: n, child: _XxxCard(...))`——**index 必须连续 0..n**（级联序复核口径），卡间距用 `SizedBox(height: spacing.cardInner)`；
4. **数据语义色**：数值色取语义 token（`tokens.moneyOut/moneyIn/kcalIn/kcalOut/net/success/danger`），状态判定（如超支 danger）在 build 内算好再传色；
5. **空态**：若卡片有「无数据占位」形态，仿 `_SavingsCard`——`summary?.xxx == null` 时返回占位文案卡，不阻塞其他卡。

注意：双卡等高并排时外层必须 `IntrinsicHeight` + Row `CrossAxisAlignment.stretch`（pitfalls#6）。

## 新增一个 watch 仓储方法的步骤

1. **接口先行**：`dashboard_repository.dart` 的 `DashboardRepository` 加方法签名，doc 注明入参口径（`yyyy-MM-dd` 日 / `yyyy-MM` 月前缀）；
2. **Drift 实现**：`DriftDashboardRepository` 内用 `select(..)..where(...)` + `.watch()`（reactive 直驱）；跨表 join 用 **`drift.innerJoin()` 函数**（勿引 Drift 3 的 `InnerJoin` 类写法）；
3. **入参校验**：日期串经 `core_domain.validateCalendarDay(value, name: ...)`，月前缀经 `_monthPattern` 正则——非法即抛 `ArgumentError`（fail-fast 口径）；
4. **区间查询**：TEXT 定宽字典序比较 `isBiggerOrEqualValue(start) & isSmallerThanValue(end)`，月尾用「下月 1 日」开区间（勿写月末天数计算）；
5. **聚合读投影表**：一切聚合只读 `day_summaries`，禁止下钻明细表（§5.6「首帧直读本表、零业务查询」）；
6. **测试**：`dashboard_repository_test.dart` 加用例——内存真库插 entry+lines → `recomputeDay`/core_db 投影重建 → watch 断言（骨架见下节）。

## 装配模式（构造注入）

页面/卡片零依赖具体 DB 类型，宿主组合根一行装配：

```dart
DashboardPage(repository: DriftDashboardRepository(appDatabase), onStartCapture: ...)
```

测试同款：`AppDatabase(NativeDatabase.memory())` → 注入。若宿主用 Riverpod，Provider 只出现在宿主层（本包保持无状态管理依赖）。

## 测试骨架（三文件同款套路）

`test/` 共性（新测试直接复制骨架）：

1. **sqlite3 缺库守卫**：`_runSkippable` 先 `customSelect('SELECT 1')` 探针，命中 `_isSqliteLibraryMissing`（`failed to load dynamic library` / `sqlite3.dll`）→ print SKIP 温和跳过——Windows 宿主无 sqlite3 运行库时不红 CI；
2. **冻结口径**：`_today = DateTime(2026, 11, 17)`、周起始周一、`_device`/`_t0` 常量（HLC 定宽编码用）——时间相关断言全部注入固定值，不取 `DateTime.now()`；
3. **造数**：`_insertEntryWithFacetLines` 直接插 `entries` + `entry_lines`（facet 拆行：calorie/burn/money × direction），再经投影重建——不 mock 仓库；
4. **手势测试口径**（`dashboard_calendar_test.dart`）：
   - 周条/月网格横滑用 `tester.flingFrom` 多采样——日格 InkWell 在场时，单次大位移手动拖拽的首段位移会被并入 drag start，不产生滚动更新；
   - 形变容器垂直拖改**多段短位移**（跟手形变按段推进）；
   - 断言前先收敛动画（`pumpAndSettle`），否则命中测试落在动画中段会 miss。
5. **约束断言**：折叠态 72dp、周格命中 48×72、月格命中 ≥48（视觉 40）、月格色点=有记录日——几何约束按 §3.3 锁进测试（token 见 [../ui_kit/README.md](../ui_kit/README.md)）。

## 转场模式（切日/展开）

- **切日**：`SlimcaSharedAxisSwitcher(child: DashboardDayBody(key: ValueKey(dateKey)))`——key 只放内层（pitfalls#3），速度阈值 120 px/s 判方向；
- **展开月网格**：受控 `_calendarExpanded` + `onExpandedChanged` 回写（pitfalls#5 防环），展开时 SlimcaCalendar 内部把焦点月重置回选中日所在月；
- **冷启动**：`_ColdStartSpring`（scale 0.92→1 + 淡入，spring.soft；MotionLevel=off 退化为 100ms 淡入淡出）包在切日 Switcher **之外**（pitfalls#4）。
