# 代码模式 — feature_ledger

本模块有四类可复用套路。核心约束先行：**页面只依赖抽象仓库接口 + 构造注入**（无 Riverpod Provider，装配在 apps/mobile）；**读路径 watch 流直驱**（StreamBuilder，无手写加载态）；**写路径能委托 core_db DAO 就委托**（outbox 入队/约束校验由 DAO 强制）。

## 新增一种统计视图（报表卡片）的完整步骤

以「在 ReportPage 加一种图卡」为例（W15 的堆叠条/折线/双轴三卡均按此套路）：

1. **数据模型**（`report_models.dart`）：新增不可变值对象；桶键口径与 ReportBucketPoint 一致（日 `yyyy-MM-dd`/月 `yyyy-MM`，固定宽度 TEXT）。若只是既有桶数据的另一种呈现，直接复用 `watchBucketSeries` 跳到第 3 步。
2. **仓库方法**（`report_repository.dart`）：接口加 `watchXxx` + Drift 实现。SQL 模板要点：
   - customSelect + `.watch()`；**必须显式 `readsFrom`**（涉及的全部表；UNION 子查询的表变更才会触发重跑）；
   - 半开区间 `e.date >= ? AND e.date < ?`，变量顺序与 SQL 占位符严格对应；
   - 过滤口径与投影一致（l.status='active'、行/事件未删、draft 计入）——直读/兜底可互换；
   - per-账本可选过滤：`ledgerFilter` 字符串条件拼入 + variables 同步条件追加，**分支不拼时变量也不传**（fd9d619 修过 Expected 5 got 3）。
3. **卡片 Widget**（`report_page.dart`）：`Container(surfaceCard) → 标题 + 副题 → StreamBuilder → SizedBox(key: 测试锚点) → LayoutBuilder → GestureDetector(onTapUp 用 _ChartGeometry.bucketIndexAt 换算桶索引) → CustomPaint`。
4. **画笔**：CustomPainter，颜色全部由调用方经 `SlimcaTheme` token 解析后构造传入（画笔无主题依赖）；`shouldRepaint` 对比 selectedBucket/数据/配色；柱宽 clamp 用手写比较（num.clamp 返回 num，隐式下转型分析器报错）。
5. **联动注册**：卡片接 `selectedBucket` + `onSelect(_selectBucket)`，自动并入三面板联动；数据流复用同一 watch 方法时可共享 StreamBuilder（如折线卡与双轴卡各订一次，Drift 流共享底层查询）。
6. **测试锚点**：SizedBox 挂 `ValueKey('report_xxx_chart')`，页级测试按 key 定位。

## 新增一种账单过滤维度的套路（双改点）

账单流（predicate 风格）与分类汇总（SQL 字符串风格）都要加；参考 W15 ledgerId 过滤的既有实现：

1. 接口方法加可选命名参数（`String? xxxId`）；
2. `watchMonthBillGroups`：`predicate = predicate & _db.entryLines.xxxId.equals(...)`（行级过滤，过滤集合互斥由行级字段保证）；`_groupRows` 无需改（归并不依赖过滤维度）；
3. `watchMonthCategorySums`：SQL 拼 `AND l.xxx_id = ?` 条件 + `variables` 同步条件追加 `drift.Variable.withString(...)`——**条件字符串与变量列表必须同进退**；
4. 调用侧（LedgerPage 的筛选条与 _BillList/_CategorySummaryCard）透传同一状态。

## 新增管理写路径的套路（先找 DAO）

1. **先查 core_db 是否已有 DAO**：budgets→`BudgetsDao`、ledgers→`LedgerDao`。有则本仓库方法只是「解析目标账本/分类 → 校验 → 调 DAO」的薄壳（参考 `setDailySpendGoal`→`_requireMoneyLedger`→`_budgets.upsertBudget`）。outbox 入队、快照联动、单现行预算折叠全部由 DAO 事务保证，本包**禁止直写这些表**（W5-6 直写漏入队是已修事故）。
2. 无 DAO 的新表（如 categories）：在本仓库直写但必须——`_clock.next()` 取 WriteStamp（revision+1、updatedAt、hlc、deviceId）→ 软删用 `deletedAt=stamp.updatedAtMs` → 先查先校验（幂等删除：不存在/已删直接 return）。
3. 逻辑引用（无外键）的字段写前人工校验目标存在且未删（参考 `setCategoryDailyGoal`）。
4. 清除类方法全部幂等软删墓碑，不物理删。

## 新增页面的装配套路

1. 页面构造注入抽象仓库（可空仓库/回调 = 渐进启用入口，参考 LedgerPage 的三组 `_canOpenXxx`）；
2. 主体 ListView + `SlimcaStaggerItem(index:)` 分段入场（ui_kit 转场体系，见 ../ui_kit/README.md）；
3. 数据块 = StreamBuilder(stream: repo.watchXxx()) 直驱；无数据渲染空占位不转圈（§3.2）；
4. 颜色一律 `context.slimca` 语义 token；图标文案带 tooltip；
5. 导航暴露 `onOpenXxx` 覆写回调（宿主自定义转场），缺省 MaterialPageRoute push 本包子页；
6. 测试锚点：页面级常量 Key（如同屏大量同名文本的管理页）或 `ValueKey('前缀_<id>')` 行级锚点，导出为顶层常量供壳侧集成测试复用。

## 宿主接线（apps/mobile 视角）

```dart
// apps/mobile 装配（伪码，见 ../apps-mobile/README.md）
final db = AppDatabase(...);
LedgerPage(
  repository: DriftLedgerRepository(db),
  adminRepository: DriftLedgerAdminRepository(db),
  manageRepository: DriftLedgerManageRepository(db),
  reportRepository: DriftReportRepository(db),
  onEditEntry: (entryId) => showCaptureSheet(
    seed: CaptureSeed(editEntryId: entryId),  // 编辑=correction supersede 链
  ),
)
```

编辑入口经 `onEditEntry` 回调由壳唤起录入抽屉；本包不 import feature_capture。

## 设计模式用法

- **仓库模式 + 接口隔离**：每个域一个 abstract interface class（LedgerRepository/ReportRepository/LedgerAdminRepository/LedgerManageRepository），页面只 import 接口；Drift 实现可替换（测试用真 Drift 内存库，不做 mock 仓库）。
- **薄壳委托**：写路径仓库 = 校验/解析薄壳 + core_db DAO（BudgetsDao/LedgerDao），避免事务纪律双实现漂移。
- **单流响应式**：需要跨表联动的读取（账本+默认徽标、投影+兜底）并成一条 customSelect/UNION watch，而非多条流 combine——规避竞态（见 pitfalls.md）。
