# feature_dashboard 数据模型

本层模型是「core_db `day_summaries` 投影行 → UI」的轻量映射，标量字段与投影表列一一对应；两个 JSON 快照列在此解析为强类型。行结构与重建规则（§5.6⑬）见 [../core_db/README.md](../core_db/README.md)；日期/金额口径见 [../core_domain/README.md](../core_domain/README.md)。

## 1. DashboardDaySummary（单日投影的 UI 映射）

| 字段 | 类型 | 对应投影列 | 口径 |
|---|---|---|---|
| `date` | `String` | `date` | 本地日历日 `yyyy-MM-dd` |
| `kcalIn` | `int` | `kcal_in` | entry_lines `type=calorie direction=in` 聚合 |
| `kcalOut` | `int` | `kcal_out` | burn 行（direction=out，运动再入账） |
| `netKcal` | `int` | `net_kcal` | 摄入 − 消耗 |
| `spendMinor` | `int` | `spend_minor` | money direction=out（分） |
| `incomeMinor` | `int` | `income_minor` | money direction=in（分） |
| `todoDone` / `todoTotal` | `int` | `todo_done` / `todo_total` | 待办完成/总数（待办不算「记录」） |
| `budget` | `DashboardBudgetSnapshot` | `budget_snapshot` JSON | 预算快照（坏数据回退全空） |
| `savings` | `Map<String, DashboardSavingsProgress>?` | `savings_progress` JSON | null=尚无目标（P1 已实装，见 core_db） |

派生：
- `hasAnyRecord`：四项标量任一非零 → 空态判定唯一依据（待办不计入）；
- `DashboardSavingsProgress.fraction`：`contributed/target` clamp 到 0-1；target ≤ 0 时恒 0。

## 2. DashboardBudgetSnapshot（budget_snapshot 的读侧解析）

**本包只认 v1 平铺形态**：`{"kcal_budget": <int>, "spend_budget_minor": <int>}`。

- `tryParse(String?)`：空/null/非 Map/键非 int/`FormatException` 一律回退全空快照——坏数据不阻塞快照直出，自愈靠投影重建（§5.6）。
- `encode()`：只写已设置的键（写侧，仅被本包 `recomputeDay` 的 upsert 使用）。
- `_asInt` 严格 `value is int`：JSON 中的 double/null/字符串键值直接丢弃，不做宽化。

**三形态兼容背景**（W15 起）：core_db `DaySummaryProjection` 已升级 v2 形态（`{"v":2,"daily":[...],"monthly":[...]}`）。本包解析器看不见 `v`/`monthly` 键、daily 项键形也不同——因此本包对 v2 行的 `budget` 解析结果恒为全空（显示「未设置」），不会崩。读取端如需 v2 完整解析，用 feature_ledger 的 `parseBudgetSnapshot`（参考实现，见 [../feature_ledger/README.md](../feature_ledger/README.md)）。

## 3. parseSavingsProgress（savings_progress 的读侧解析）

形态：`{ "<goal_id>": {"contributed_minor": int, "target_minor": int}, ... }`。

- 返回 `Map<String, DashboardSavingsProgress>`；空/null/坏 JSON/无有效条目 → `null` → 存钱卡走占位空态。
- 单条目 contributed 或 target 非法（非 int）时**仅丢弃该条**，不影响其他条目。

## 4. 与 core_db 投影表的关系

- 本包**不定义**表结构，只通过 Drift 生成的 `DaySummary` 行类读取（`day_summaries`：一天一行、`dirty`/`built_at` 维护重建、`tz_offset_min` 保留时区）。
- 投影行「永不同步」（本地派生列）——同步引擎不搬运，见 [../feature_sync/README.md](../feature_sync/README.md)。
- 金额一律整数分（minor）存储；展示层的 元/千位分组/负号 在本包 `_formatMoneyMinor`（展示专用，不参与存储/同步）。

## 5. 日期口径约定

- `yyyy-MM-dd` 定宽 TEXT，字典序 = 时间序——月区间查询（`watchMonthSpendMinor`）依赖此性质，字段必须保持定宽（月份补零）。
- 周一起始为成文口径（`weekday-1`）；`DashboardCalendar` 全部基于本地时区运算，禁止 UTC 转换。
