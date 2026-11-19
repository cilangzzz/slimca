# 数据模型 — feature_ledger

全部为不可变值对象，wire 常量与 core_db 列口径一致（金额=分、kcal=整数、kind/direction/status 存 TEXT wire 值）。表结构真值见 ../core_db/README.md；本文只讲展示模型与「facet 行 → UI 呈现」的映射。

## entry_line facet 行在 UI 层的呈现（账单流）

一次录入在 DB 是一条 entries 主干 + N 条 entry_lines facet 行（§5.2②：一行一类型一方向一账本）。UI 层三级归并：

```
entry_lines（facet 行，join entries 主干 + categories 最新名）
  └→ LedgerBillLine   行投影：lineId/entryId/type/amount/direction/categoryId/Name/colorToken
      └→ LedgerBillEntry  按 entryId 归并的「一条账」：date/kind/title/status + 不可变 lines 列表
          └→ LedgerDayGroup   按 entries.date 聚组（降序）+ 当日 spend/income 合计
```

`LedgerBillEntry` 的派生 getter 是四种「类型×方向」组合的语义化（口径 §5.3/§2.1③）：

| type | direction | 语义 | 单位 | getter |
|------|-----------|------|------|--------|
| money | out | 支出 | 分 | `spendMinor` |
| money | in | 收入 | 分 | `incomeMinor` |
| calorie | in | 摄入 | kcal | `kcalIn` |
| burn | out | 运动消耗 | kcal | `kcalOut` |

`netKcal = kcalIn - kcalOut`。注意行上另有 categoryId（money 行=消费分类、calorie 行可挂餐饮子类）与 ledgerId（行必挂账本，多账本过滤的依据）——都挂在**行**而非账上。

## wire 常量（与 core_db 一致，勿硬编码字符串）

- `kCategoryKindExpense/Income` = expense/income（categories.kind）
- `kLedgerKindMoney/Kcal` = money/kcal（ledgers.kind）
- `kBudgetPeriodDaily/Monthly` = daily/monthly（budgets.period_type）
- `kLedgerColorTokens` = 9 个语义 token 白名单（primary/kcalIn/kcalOut/net/moneyIn/moneyOut/success/warn/danger）

`normalizeLedgerColorToken`：null/空白/白名单外 → 缺省 `primary`（白名单外的值不能进库——绕开语义 token 体系后主题切换会失色，§8.2）。渲染侧 `ledgerColorFromToken(SlimcaTheme, tokenName)`：token→Color 解析，未知 token 返回 null 由调用方回退中性色（实现于 ledger_colors.dart）。

## 日简报链（day_summary 投影直读）

```
day_summaries 行（date 主键、kcalIn/kcalOut/netKcal/spendMinor/incomeMinor、budgetSnapshot JSON）
  └→ LedgerDayBriefing   五个数值列直读 + budgets 解析结果
      ├→ spendBudget / kcalBudget  第一条「daily + 总预算」money/kcal 项（月度预算不混入）
      └→ hasAnyRecord  四值全零=无记录（不渲染目标行）
```

### parseBudgetSnapshot（三形态兼容，升级期关键）

```dart
List<LedgerBudgetItem> parseBudgetSnapshot(
  String? snapshotJson, {
  required int daySpendMinor,       // 平铺形态合成 used 用
  required int dayNetKcal,
  Set<String> kcalLedgerIds = const {},  // kcal 口径判定（快照只带 ledger_id）
});
```

| 形态 | 来源 | JSON 形状 | 处理 |
|------|------|-----------|------|
| v2 | core_db W15 | `{"v":2,"daily":[…],"monthly":[…,{carry_over,period_start,period_end}]}` | daily 缺省 daily 周期；monthly 项带周期窗口与结转 |
| v1 | core_db W2 | `{"daily":[…]}` | 全部项缺省 daily 周期，行为不变 |
| 平铺 | feature_dashboard 旧版 | `{"kcal_budget":int,"spend_budget_minor":int}` | 无 used/明细，按当日投影值合成 used/remaining |

解析失败（空/坏 JSON/形态不符/单项 amount 或 used 缺失）一律跳过或返回空列表——快照是派生数据，简报卡退化为「目标未设置」提示而非崩溃。`remaining` 缺失时按 amount-used 兜底。

## 管理域模型

- **LedgerBudgetItem**（快照项）：ledgerId（平铺形态 null）/categoryId（null=总预算）/isKcal（由 kcalLedgerIds 判定）/amount/used/remaining + periodType/periodStart/periodEnd/carryOver（v2 monthly 专用）。派生：isOver/isCategoryGoal/isMonthly。
- **LedgerDailyBudget**（budgets 行 + 账本/分类名回填）：管理页行模型，复用于 daily 与 monthly 两种周期。ledgerKind 判定 kcal 口径；dayOfMonthStart（1..28，daily 恒 1）；carryOver。
- **LedgerSwitchOption**（ledgers 行 + 默认徽标）：id/name/icon/currency（money=币种、kcal=kcal）/kind/isDefault（settings 指针比对）。
- **LedgerCategoryOption**（categories 行）：id/name/icon/kind/colorToken/isPreset。

## 报表域模型

- **ReportRange**：period + start（含）+ endExclusive（不含）+ byMonth（年档按月分桶）。由 `reportRangeFor(period, anchor)` 经 LedgerCalendar 解析。
- **ReportBucketPoint**：bucketKey（日 `yyyy-MM-dd`/月 `yyyy-MM`）+ spendMinor/incomeMinor/kcalIn/kcalOut，派生 netKcal。
- **ReportCategoryStack**：bucketKey × categoryId（null=未分类）+ categoryName/colorToken/spendMinor。

桶键为固定宽度 TEXT，字典序即时间序；`reportBucketKeys` 枚举全桶零填充（图表 x 轴完整、联动按索引寻址），见 [api-report.md](api-report.md)。

## 数字口径约定（§5.1）

- 金额一律 INTEGER 分，kcal 一律 INTEGER，展示层才格式化（`LedgerFormat.moneyMinor` → `¥1,234.50`，负数 `-¥8.50`，收入 `+¥…`）；全程无 double。
- 解析：`parseYuanToMinor` 接受 `10`/`10.5`/`10.50`（最多两位小数），非法/负数返回 null；`parseKcal` 仅接受 1..99999 正整数；`yuanInputText` 与 parseYuanToMinor 互逆（对话框回填）。
- 日期为本地自然日 TEXT `yyyy-MM-dd`（月前缀 `yyyy-MM`），固定宽度保证字典序=时间序；查询一律半开区间 `[start, endExclusive)`。`LedgerCalendar.monthRange` 对非法月前缀抛 ArgumentError（硬失败），而 `dayGroupTitle/dayLabel/dayAxisLabel/monthAxisLabel` 对脏数据原样返回不抛异常（防止单行脏数据炸整页渲染）——两处策略不同是有意为之。
