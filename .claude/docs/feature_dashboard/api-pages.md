# feature_dashboard API 明细

对外表面 = 页面（Widget 构造参数）+ 仓储抽象（4 方法）+ 日历工具（静态成员）。全经 `lib/feature_dashboard.dart` 导出。本包无 REST/gRPC/CLI 端点，也无 Riverpod provider（见下文「宿主接线」）。

## 1. 页面域

### DashboardPage（真页，首页唯一候选）

`StatefulWidget`，构造参数：

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `repository` | `DashboardRepository` | 是 | 投影数据源，构造注入（页面不触碰 AppDatabase） |
| `initialDate` | `DateTime?` | 否 | 初始选中日，缺省今天（内部 `DashboardCalendar.normalize` 归一化） |
| `today` | `DateTime?` | 否 | 「今天」锚点，缺省本地今天；测试注入冻结保证确定性 |
| `weekStart` | `int?` | 否 | 周起始 1=周一..7=周日，缺省 locale 驱动；透传给 SlimcaCalendar |
| `onStartCapture` | `VoidCallback?` | 否 | 空态引导「立即记录」CTA 回调；缺省只展示文案 |

内部状态（即「Provider 语义」的等价物——选中日单一真值在本页持有）：
- `_selectedDate`：日期大字 / SlimcaCalendar / 卡片墙三视图共享；
- `_calendarExpanded`：月网格展开态（受控），页头「月历图标」与组件内手势共用；
- `_recordedDays`：State 级 `late final` 缓存的 `watchRecordedDays()` 流，避免每次 build 重订阅导致月格色点闪烁。

### DashboardDayBody（卡片墙主体）

`StatelessWidget`：`date`（DateTime）+ `repository` + `onStartCapture?`。以 `watchDay(formatCalendarDay(date))` 流为唯一数据源，渲染热量环卡 / 支出+净热量双卡（`IntrinsicHeight` 等高）/ 存钱卡 / 空态引导，全部包在 `SlimcaStaggerItem`（index 0..n，80ms 级联）中。

路由名：本包**不定义 go_router 路由**；路由接线归宿主。参考壳实现见 [../apps-mobile/README.md](../apps-mobile/README.md)（App 现状是用自实现首页，未接本包，见 pitfalls#1）。

## 2. 数据域：DashboardRepository（抽象接口）

```dart
abstract interface class DashboardRepository {
  Stream<DashboardDaySummary?> watchDay(String date);
  Stream<int> watchMonthSpendMinor(String month);
  Stream<Set<String>> watchRecordedDays();
  Future<void> recomputeDay(String date);
}
```

| 方法 | 入参口径 | 返回/行为 |
|---|---|---|
| `watchDay` | 本地日历日 `yyyy-MM-dd`，非法抛 `ArgumentError`（经 `core_domain.validateCalendarDay`） | 单日投影行 watch；当日尚未重建过投影时发 `null` |
| `watchMonthSpendMinor` | 月前缀 `yyyy-MM`（正则校验，非法抛 `ArgumentError`） | 当月逐日 `spend_minor` 求和（分）；区间按 TEXT 定宽字典序 `[yyyy-MM-01, 下月-01)` |
| `watchRecordedDays` | 无 | 全投影表 watch → 有任一钱/热量记录的日期集合（与 `DashboardDaySummary.hasAnyRecord` 同口径）；月格色点数据源 |
| `recomputeDay` | 本地日历日 `yyyy-MM-dd`，非法抛 `ArgumentError` | 事务内：entry_lines ⋈ entries 明细聚合（剔除 entry/行墓碑与非 active 行）→ 待办完成度 → 每日预算 → upsert 投影行、dirty 清零。**坑点见 pitfalls#2，生产写路径勿用** |

### DriftDashboardRepository（唯一实现）

`DriftDashboardRepository(db.AppDatabase)`：构造接 core_db 的 `AppDatabase`。月格色点流为全表 watch——规模假设：投影表一天一行、本地单用户，代价有界。

## 3. 日历工具域：DashboardCalendar（abstract final，全静态）

日期口径一律本地时区年月日（§5.1「杜绝 UTC 错日」）；`yyyy-MM-dd` TEXT 与 core_domain `formatCalendarDay` 往返一致。

| 成员 | 签名 | 说明 |
|---|---|---|
| `normalize` | `DateTime → DateTime` | 丢弃时分秒，保留本地年月日 |
| `parse` | `String → DateTime` | `yyyy-MM-dd` → 本地日历日；先经 `validateCalendarDay` 校验 |
| `today` | `() → DateTime` | 今天的本地日历日 |
| `startOfWeek` | `DateTime → DateTime` | 所在周周一（周一起始成文口径） |
| `weekOf` | `DateTime → List<DateTime>`（7 元素） | 周一…周日，周历条数据源 |
| `shift` | `(DateTime, int days) → DateTime` | 相邻日平移（左右滑切日共用） |
| `monthPrefix` | `DateTime → String` | `yyyy-MM`（watchMonthSpendMinor 入参口径） |
| `dayTitle` | `DateTime → String` | `11月16日`（日期大字） |
| `monthTitle` | `DateTime → String` | `2026年11月`（月网格头部） |
| `startOfMonth` | `DateTime → DateTime` | 所在月首日 |
| `daysInMonth` | `DateTime → int` | 公历当月天数（本地运算） |
| `monthGridRows` | `DateTime → int` | 月网格行数（周一起始，最多 6 行） |
| `weekdayLong` | `const List<String>` | `周一`…`周日`（下标 = weekday-1） |
| `weekdayShort` | `const List<String>` | `一`…`日`（下标同上） |

## 4. 消费的 ui_kit 组件（只接线、不复制）

`DashboardPage` 对 [../ui_kit/README.md](../ui_kit/README.md) 的依赖面（组件语义与坑点归属 ui_kit 文档）：

| 组件 | 本包用法 |
|---|---|
| `SlimcaCalendar` | 组合容器：`selectedDate/onDaySelected` 受控选中、`recordCounts` 月格色点、`expanded/onExpandedChanged` 受控展开、`today`、`weekStart` |
| `SlimcaSharedAxisSwitcher` | 280ms 水平共享轴切日转场（key 放内层，pitfalls#3） |
| `SlimcaStaggerItem` | 卡片墙 80ms 级联入场（index 连续 0..n） |
| `SlimcaCalorieRing` | 热量环（size 108 / strokeWidth 10，spring 推进） |
| `context.slimca/spacing/sizes/motion` | 三层 token；卡片 radius/padding/间距禁裸字面量 |

## 5. 数据流与宿主接线

**Provider 入口现状**：本包零 Riverpod。装配契约 = 宿主组合根构造 `DriftDashboardRepository(appDatabase)` 注入 `DashboardPage.repository`。参考测试装配：内存真库 `AppDatabase(NativeDatabase.memory())` → 注入页面（test/ 三文件同款）。

**实际接线现状**：apps/mobile 未依赖本包（见 pitfalls#1）；App 首页的 provider 群在 [../apps-mobile/README.md](../apps-mobile/README.md) 的 `dashboard_state.dart`。

**完整数据流**（含写路径归属）：

1. 记一笔 → feature_capture/feature_ledger 写 entries/entry_lines → **core_db `DaySummaryProjection.recomputeDaySummary`**（写路径同事务/紧随重算，v2 快照）；
2. `day_summaries` 行变更 → Drift reactive stream 自动重发；
3. `watchDay` → `DashboardDaySummary`（JSON 快照解析失败回退空值，不阻塞直出）→ 卡片墙；
4. `watchMonthSpendMinor` → 支出卡「本月累计」行（独立 StreamBuilder，`initialData: 0`）；
5. `watchRecordedDays` → `recordCounts` 映射（V1：每个有记录日记 1 点）→ SlimcaCalendar 月格。

**刷新链路注意**：`recomputeDay` 的调用时机在写路径（core_db 仓库/网关）内闭环；本包方法存在但非生产调用点（pitfalls#2）。若宿主自行调用，注意它会把 budget_snapshot 覆写为 v1 平铺形态。
