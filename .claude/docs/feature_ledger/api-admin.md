# API — 管理域（LedgerAdminRepository + LedgerManageRepository）

写路径仓库：分类增删改（categories）、每日/月度目标（budgets）、账本生命周期（ledgers）。页面依赖抽象接口，构造注入。

写路径纪律：

- 全部写入带 HLC 戳（core_db `LocalWriteClock` 发号：revision 自增、updatedAt/hlc 单调，SyncEngine 可无损上送）；
- **budgets 写路径经 core_db BudgetsDao**（W15 收口）：业务行与 outbox 行同事务入队 + budget_snapshot v2 投影联动由 DAO 强制——**禁止在本包直写 budgets 表**（W5-6 旧版直写漏入队是已修的补课项）；
- **ledgers 写路径委托 core_db LedgerDao**：outbox 入队与 kcal 账本保护（不可删不可多开）由 DAO 强制，本仓库不重复实现；
- 删除一律软删墓碑（幂等：不存在/已删直接返回）；墓碑拒绝复活/更新。

## LedgerAdminRepository（14 方法）

### 分类（categories，§5.4⑤）

```dart
Stream<List<LedgerCategoryOption>> watchCategoryOptions(); // 未删，kind→sort 排序
Future<String> createCategory({required String name, required String kind,
    String? icon, String? colorToken});                     // 返回新 id
Future<void> updateCategory({required String id,
    String? name, String? icon, String? colorToken});
Future<void> softDeleteCategory(String id);                 // 幂等软删
```

- `kind` 限 `expense`/`income`（非法抛 ArgumentError）；name 去首尾空白后必须非空。
- `colorToken` 经 `normalizeLedgerColorToken` 校验白名单，白名单外静默落缺省 `primary`（不抛错）。
- 新分类 `isPreset=false`，sort=当前最大值+1（内置分类占 0..N 不受影响），icon 缺省 `label`。
- 内置分类（is_preset）删除抛 StateError；已删墓碑更新抛 StateError。
- MVP 分类全局生效（ledgerId=NULL）；逻辑引用不建外键，删分类后历史账单行原样保留（join 落「未分类」）。

### 每日/月度目标（budgets，§5.4⑥）

```dart
Stream<List<LedgerDailyBudget>> watchDailyBudgets();    // period=daily 未删
Stream<List<LedgerDailyBudget>> watchMonthlyBudgets();  // period=monthly 未删
Future<void> setDailySpendGoal(int amountMinor);        // 挂默认 money 账本，总预算
Future<void> setDailyKcalGoal(int kcal);                // 挂内置 kcal 账本；kcal≤0 抛错
Future<void> setCategoryDailyGoal({required String categoryId, required int amountMinor});
Future<void> setMonthlySpendGoal(int amountMinor,
    {int dayOfMonthStart = 1, bool carryOver = false}); // 月起点 1..28 + 结转
Future<void> clearDailySpendGoal();
Future<void> clearDailyKcalGoal();
Future<void> clearCategoryDailyGoal(String categoryId);
Future<void> clearMonthlySpendGoal();
```

- 目标账本解析：每日/月度支出目标挂**默认 money 账本**（settings 指针优先，指针缺失/失效回退首个可用 money 账本）；热量目标挂**内置 kcal 账本**（恒存在，seed 保证；缺失抛 StateError）。
- `setCategoryDailyGoal` 写前人工校验分类存在且未删（逻辑引用无外键约束，不校验会挂出悬空目标）。
- upsert/清除语义（同 (ledger,category,period) 单现行预算折叠为原行更新）由 BudgetsDao 强制，见 ../core_db/README.md。
- watch 流 join 回 ledgers（取 kind 判定 kcal 口径）与 categories（分类名回填，已删分类显示「已删分类」）。

## LedgerManageRepository（6 方法）

```dart
Stream<List<LedgerSwitchOption>> watchSwitchOptions();   // 可用账本 + 默认徽标
Stream<List<LedgerSwitchOption>> watchArchivedOptions(); // 已归档（恢复入口）
Future<String> createLedger({required String name, String? icon, String? currency});
Future<void> renameLedger(String id, {required String name}); // kcal 允许改名
Future<void> setArchived(String id, {required bool archived}); // kcal 拒绝归档（DAO 强制）
Future<void> setDefault(String id);                     // 仅 money 账本
```

- `watchSwitchOptions` 单条 customSelect 联查 settings 默认指针（`kSettingDefaultLedgerId`）：**settings.value 为 JSON 字符串值**（如 `"abc"` 带引号），Dart 侧 jsonDecode 后比对 id；坏值防御性视为未设默认。`readsFrom` 显式声明 `{ledgers, settings}`——徽标随指针切换响应式更新。
- 归档=产品态软移除（is_archived），历史账单保留，可随时恢复；kcal 账本不可归档不可设默认（DAO 抛错，UI 层先行禁用入口）。
- 新建账本币种 v1 固定 CNY（多币种留待后续周目）。

## 页面：CategoryManagePage

分类管理页：每日目标卡（总支出/总热量/分类级清单 + W15 月度支出目标区）+ 分类清单卡（支出/收入分组，每行色点 + 内置徽标 + 日目标徽标 + 目标/编辑/删除操作）。

```dart
CategoryManagePage({required LedgerAdminRepository repository});
```

- 一条 `watchDailyBudgets` 流同时驱动目标卡与分类卡的日目标徽标。
- 内置分类**不渲染删除入口**（而非点了报错）；删除确认弹窗文案说明软删墓碑语义。
- 新建对话框含类型 ChoiceChip（仅新建可选，编辑时类型不可改——历史行已按 kind 归组）与 9 色语义 token 选择圆点。
- 月度目标对话框：金额 + 周期起点 ChoiceChip（1/10/15/20/25/28，范围 1..28）+ 结转 SwitchListTile。
- 输入解析全走 `LedgerFormat`：金额=元最多两位小数、kcal=1..99999 整数，非法由对话框展示错误，不做静默截断。

测试锚点常量（导出）：`ledgerSpendGoalSetKey` / `ledgerKcalGoalSetKey` / `ledgerMonthGoalSetKey` / `ledgerMonthGoalInputKey` / `ledgerMonthGoalCarryKey` / `ledgerMonthGoalSaveKey` / `ledgerGoalInputKey` / `ledgerGoalSaveKey` / `ledgerCategoryCreateKey` / `ledgerCategoryNameFieldKey` / `ledgerCategoryDialogSaveKey` / `ledgerCategoryConfirmDeleteKey`。

## 页面：LedgerManagePage

账本管理页：可用账本卡（默认徽标 + 重命名/设为默认/归档操作 + 新建按钮；kcal 行只读仅允许改名）+ 已归档卡（恢复入口）。

```dart
LedgerManagePage({required LedgerManageRepository repository});
```

测试锚点常量（导出）：`ledgerManageCreateKey` / `ledgerManageNameFieldKey` / `ledgerManageSaveKey` / `ledgerManageConfirmArchiveKey`；行级按 id 组合：`ledger_manage_rename_<id>` / `ledger_manage_default_<id>` / `ledger_manage_archive_<id>` / `ledger_manage_restore_<id>`。
