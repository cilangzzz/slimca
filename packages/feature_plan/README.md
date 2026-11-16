# feature_plan

Slimca 计划域 feature 包（§10.4 packages/feature_plan）：健身手动记录、待办、
存钱目标与健身计划占位（§3.5/§3.6/§5.5、§11.1 W5-6）。

## 功能（W5-6）

- **健身手动记录页** `FitnessLogPage`（§3.5 P0）：内置 MET 表类型选择 +
  强度档（低/中/高）+ 时长/体重 → 实时估算
  `kcal = MET × 体重kg × 时长h`（±20% 口径标注，§3.5 误差口径标注 P0）→
  经 `PlanGateway.submitFitnessSession` 同事务落三行（§5.5⑦）：
  - entries（kind=fitness、source=manual、status=confirmed，§5.2①）；
  - entry_lines（type=burn、direction=out、归集内置 kcal 账本、payload 记
    session_id 与 MET 参数，§5.2②）；
  - fitness_sessions（§5.5⑦ 列语义）。
  落库后 day_summary 投影同事务重算（kcal_out/net_kcal，§5.6）；列表按日
  查看、删除走软删墓碑 + 投影回落（§5.1/§5.6）。
- **待办完整雏形** `TodoPage`（§3.6 P0）：今日待办/收集箱双视图
  （§5.5⑩ date NULL=收集箱）；勾选经 `TodoDao.setDone`（done_at 只前进合并，
  §6.5）联动重算 day_summary.todo_done/todo_total（§5.6）；收集箱项
  「加入今日」回填计划日。
- **存钱目标占位页** `SavingsPage`（W13 全量）：读侧已接通
  （目标 + Σ contributions 进度，§5.5⑪⑫ append-only），空态引导文案。
- **健身计划占位页** `FitnessPlanPage`（W14 全量）：读侧已接通
  （fitness_plans 流，§5.5⑧），空态引导文案。
- **计划域组合页** `PlanHubPage`（§4.2 计划 Tab 默认实现）：四卡入口
  （待办/健身/存钱/健身计划），摘要直读 day_summary 投影；卡片级联入场
  （§9.3#1）+ 共享轴页面跳转（§9.3#2），只引用 ui_kit 既有 token/转场。

## 宿主装配（§10.4 壳负责装配）

```dart
// apps/mobile bootstrap：
planGatewayProvider.overrideWithValue(
  createPlanGateway(db: appDatabase, clock: hlcClock),
)
```

`HlcClock` 必须是应用级单例（§6.3 HLC 单调性是全设备唯一全序来源）。
未 override 直接读 `planGatewayProvider` 即抛 `UnimplementedError`——
装配遗漏在开发期立刻暴露。

分层边界：持久化语义全部复用 core_db（`DriftEntryRepository` /
`DriftEntryLineRepository` / `TodoDao` / `DaySummaryProjection`），本包只做
feature 层编排与视图；主题/动效只引用 ui_kit 语义 token 与转场
（§8.2/§9.2，禁裸色值/裸时长）。

## 测试

`test/`（内存真库 `AppDatabase(NativeDatabase.memory())`，禁真实网络/
平台通道）：

- `fitness_met_table_test.dart`：MET 估算纯单元（30 分钟慢跑·中强度·70kg
  = 245 kcal）；
- `fitness_flow_test.dart`：W5-6 验收主线——记 30 分钟慢跑 →
  fitness_sessions + burn 行落库、投影 kcal_out=245；删除 → 墓碑 +
  kcal_out 回落；
- `todo_flow_test.dart`：新增/勾选联动投影 todo_done；收集箱不进日投影、
  加入今日后联动；
- `plan_pages_test.dart`：Hub 四卡与占位页空态。

Windows 宿主缺 sqlite3 运行库（sqlite3.dll）时 widget 测试温和跳过。
