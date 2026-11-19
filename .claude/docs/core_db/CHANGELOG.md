# Changelog - core_db

> 模块变更历史。最新变更在最上方。
> 排查问题时优先阅读本文件。

---

## [2026-11-17] W15 多账本+预算体系+统计报表（周/月/年+钱-热量双轴）

**类型**: feat
**提交**: fd9d619
**风险**: HIGH

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/budgets_dao.dart | +248/-0 | 新建：预算 CRUD（daily/monthly 双周期、按账本/分类、月度起点 1..28、结转开关）；同 (ledger,category,period) 唯一现行行契约；写事务联动 markBudgetSnapshotDirty+recomputeDirtyDays |
| lib/src/dao/day_summary_projection.dart | +256/-74 | budget_snapshot 升级 **v2**：daily+monthly 双周期快照、kcal 账本「吃=支出/运动=再入账」口径、carry_over 单步结转、月度窗口折算 |
| lib/src/dao/ledger_dao.dart | +276/-10 | 多账本写路径：createLedger（仅 money 口）/renameLedger/setLedgerArchived（归档≠墓碑、kcal 拒绝归档、默认指针自动重指）/setDefaultLedger/defaultLedgerId/watchDefaultLedgerId/getActive/watchActive |
| lib/core_db.dart | +8/-0 | 导出 budgets_dao |
| test/budget_snapshot_v2_test.dart、test/budgets_dao_test.dart、test/ledger_dao_multiledger_test.dart、test/day_summary_projection_test.dart | +333/-0、+322/-0、+188/-0、+6/-2 | 预算快照 v2 形状/结转/越线翻转、预算 CRUD、多账本生命周期专项 |

### 影响范围
- **API**: 新增 BudgetsDao 全部方法；LedgerDao 新增 8 个多账本方法；DaySummaryProjection.budget_snapshot 输出形状 v2（读取端须三形态兼容）
- **跨模块**: 同提交也改了 apps/mobile、feature_ledger（报表页/多账本切换/支出卡余超翻转）
- **数据模型**: budgets 表启用（W1 建表、功能后启用策略），无新表
- **回滚指南**: `git revert fd9d619`；检查文件：budgets_dao.dart、ledger_dao.dart、day_summary_projection.dart；副作用：budget_snapshot 旧快照行重算后回到 v1 形状（投影自愈），多账本写路径消失但 seed 默认账本不受影响

---

## [2026-11-17] W13 待办完整版（RRULE+提醒调度）+ 存钱目标（365/52周/自定义+投币打卡）

**类型**: feat
**提交**: cc86213
**风险**: HIGH

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/savings_dao.dart | +474/-0 | 新建：SavingsGoalsDao（create/updateDetails/softDelete/watchAll/watchActive）+ SavingsContributionsDao（append append-only、幂等键 (goal_id,date,source)、sumByGoal/watchSumByGoal）；目标/贡献写路径同事务入 outbox + 联动 savings_progress 快照 |
| lib/src/dao/day_summary_projection.dart | +120/-3 | savings_progress 快照实装（当日有效目标、贡献累计口径 date<=快照日）+ markSavingsProgressDirty + parseSavingsProgress 解包 |
| lib/src/dao/todo_dao.dart | +66/-1 | create/updateDetails 增补重复规则三字段（repeat_rule/rrule_anchor_date/remind_at，互不联动）；backfillTodoRruleAnchorColumn 幂等回填 |
| lib/src/tables/plan_tables.dart | +20/-2 | todos.rrule_anchor_date 补列；savings_contributions.source 补列（默认 'manual'） |
| lib/src/app_database.dart | +9/-0 | beforeOpen 挂回填（先补列后 seed） |
| lib/src/app_database.g.dart | +160/-4 | build_runner 重新生成 |
| lib/core_db.dart | +9/-1 | 导出 savings_dao |
| test/savings_dao_test.dart、test/savings_projection_test.dart、test/w13_column_backfill_test.dart、test/todo_dao_test.dart、test/day_summary_projection_test.dart | +418/-0、+305/-0、+159/-0、+84/-1、+3/-1 | 存钱 CRUD/幂等/求和、投影进度快照、回填幂等、RRULE 字段专项 |

### 影响范围
- **API**: 新增 SavingsGoalsDao/SavingsContributionsDao；TodoDao.create/updateDetails 新增 3 个可选参数；DaySummaryProjection 新增 markSavingsProgressDirty
- **跨模块**: 同提交也改了 apps/mobile、feature_plan（存钱打卡 UI、RRULE 展开、提醒调度）
- **数据模型**: **v1 内补列 ×2**（schemaVersion 保持 1，幂等回填）；⚠️ 服务端 0001_init.sql 与 sync_table_registry 未同步这两列，push payload 相关键被服务端静默忽略（见 pitfalls.md §5）
- **回滚指南**: `git revert cc86213`；检查文件：savings_dao.dart、todo_dao.dart、plan_tables.dart、app_database.dart；副作用：存量库文件已补的列不随回滚删除（ALTER TABLE 已生效），Drift 表类回滚后 g.dart 不再含列但库文件列残留（无害）；存钱功能与 RRULE 字段整体消失

---

## [2026-11-17] W11-12 拍照通道：双供应商识别管线+端侧压缩+即焚+确认卡复用（V1 留存钩子）

**类型**: feat
**提交**: 19d439b
**风险**: HIGH

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/attachments_dao.dart | +257/-0 | 新建：附件审计元数据登记 + 「解析后即焚」状态机（active→burned 单向，先焚内容后落状态）+ purgeExpired（>7 天残留强制焚毁，UUIDv7 id 内嵌时间戳判残留，非 UUIDv7 保守跳过）+ backfillAttachmentBurnColumns |
| lib/src/dao/food_items_dao.dart | +253/-0 | 新建：菜品明细 CRUD（同事务入 outbox）；updateDetails 事实变化自动置 user_adjusted、无真实变化 no-op 不入队 |
| lib/src/tables/infra_tables.dart | +32/-3 | attachments 补即焚两列 status（默认 'active'）/burned_at |
| lib/src/uuid_v7.dart | +14/-0 | uuidV7TimestampMs（id 内嵌时间戳提取，「时间可由 id 得出就不另设时间列」判据） |
| lib/src/app_database.dart | +8/-0 | beforeOpen 挂 backfillAttachmentBurnColumns |
| lib/src/app_database.g.dart | +147/-4 | build_runner 重新生成 |
| lib/core_db.dart | +7/-1 | 导出两个新 DAO |
| test/attachments_dao_test.dart、test/food_items_dao_test.dart、test/outbox_write_path_test.dart | +433/-0、+261/-0、+117/-1 | 即焚状态机/清扫/焚毁器注入、菜品 CRUD/outbox、food_items 写路径补用例 |

### 影响范围
- **API**: 新增 AttachmentsDao/FoodItemsDao 全部方法；常量 kAttachmentKind*/kAttachmentStatus*、kAttachmentBurnRetention；typedef AttachmentContentCleaner
- **跨模块**: 同提交也改了 apps/mobile、core_ai（识别管线/端侧压缩）、feature_capture（确认卡复用）
- **数据模型**: attachments v1 内补列 ×2（即焚生命周期为设备本地审计列、有意不出网）；attachments 仍属「服务端为主 2 张」不携公共列
- **配置**: 焚毁器可注入（缺省删本地文件，测试注 Fake）
- **回滚指南**: `git revert 19d439b`；检查文件：attachments_dao.dart、food_items_dao.dart、infra_tables.dart、app_database.dart；副作用：已焚行/残留文件不随回滚恢复；拍照通道上层调用点需同步回滚

---

## [2026-11-16] W7-8 同步一期：Supabase 后端（RLS+RPC 幂等）+ 全写路径 outbox 补课 + 遥测/raw_input 开关/IAP 骨架

**类型**: feat（含 W5-6 遗漏的写路径补课修复）
**提交**: d13c27d
**风险**: HIGH

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/sync_outbox_writer.dart | +177/-0 | 新建：SyncOutboxWriter.enqueueRow——业务写事务内读回行终态整行入队（op 按墓碑自动判定 upsert/delete；同 (table,row) 未 ack 行折叠收敛；14 张真值表冻结集之外抛错） |
| lib/src/dao/category_dao.dart | +15/-2 | seedPresets 补课：seed 行同事务入 outbox（双设备各自 seed 的两套默认分类经出网收敛） |
| lib/src/dao/ledger_dao.dart | +17/-2 | seedDefaults 补课：同上（否则他端 entry_lines.ledger_id 引用失配） |
| lib/src/dao/todo_dao.dart | +41/-20 | 四个写路径（create/setDone/updateDetails/softDelete）统一接入 enqueueRow；no-op 分支不入队 |
| lib/core_db.dart | +4/-1 | 导出 sync_outbox_writer |
| test/outbox_write_path_test.dart | +361/-0 | 全写路径出网行数/折叠/delete 语义专项 |
| test/test_support.dart | +11/-0 | drainSeedOutbox 辅助（清 seed 的 24 行出网） |

### 影响范围
- **API**: 新增 SyncOutboxWriter.enqueueRow（出网纪律统一落点）；TodoDao 写路径语义不变、仅补出网
- **跨模块**: 同提交也改了 apps/mobile、core_domain、feature_capture、feature_sync、server/supabase（sync_push_batch/sync_pull_changes/register_device RPC、投递水位）——本模块的 enqueueRow 是该提交同步链路的本地半边
- **数据模型**: 无表变更；sync_outbox 开始承载全部真值表出网
- **配置**: 无
- **回滚指南**: `git revert d13c27d`；检查文件：sync_outbox_writer.dart、category_dao.dart、ledger_dao.dart、todo_dao.dart；副作用：seed 行与 todos 写路径回到「只落业务行不出网」（W5-6 状态），双设备不再收敛——不可单独回滚 seed 入队部分

---

## [2026-11-16] W5-6 记账完整化+语音(Fake链路)+健身+同步引擎（M1 功能项）— core_db 部分

**类型**: fix
**提交**: 3022e4d
**风险**: MEDIUM

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/entry_line_repository.dart | +3/-1 | upsert 投影联动修正：`_recomputeDay` 由传 parent.date 改为传 line.entryId——`_requireParent` 以 entryId 查父行，误传 date 会拿日期查 entries.id 抛「父事件不存在」 |

### 影响范围
- **API**: DriftEntryLineRepository.upsert 行为修复（投影联动恢复）；调用方无感
- **跨模块**: 该提交主体在 feature_capture/feature_plan/apps/mobile（语音链路、健身、同步引擎）；本模块仅此一处修复
- **数据模型**: 无
- **配置**: 无

---

## [2026-11-16] W2 主线：day_summary 投影/仓储/seed + 手动记账 CRUD 全链路 + 仪表盘真页 + Riverpod 接线

**类型**: feat
**提交**: 1ee4ab4
**风险**: HIGH

### 变更文件（packages/core_db/）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/dao/entry_repository.dart | +202/-0 | 新建：DriftEntryRepository（软删墓碑、墓碑拒绝复活、watch 流、kind+date 复合索引对齐、投影联动） |
| lib/src/dao/entry_line_repository.dart | +300/-0 | 新建：DriftEntryLineRepository（supersede 事务语义、money 行不可变守卫 MoneyLineImmutableException、聚合口径查询） |
| lib/src/dao/day_summary_projection.dart | +295/-0 | 新建：投影 v1（重算/标记 dirty/recomputeDirtyDays/recomputeAll/watchDaySummary） |
| lib/src/dao/local_write_clock.dart | +77/-0 | 新建：LocalWriteClock（device_id 持久化 + HlcClock 发戳，updated_at=hlc 物理段同源单调） |
| lib/src/dao/ledger_dao.dart | +161/-0 | 新建：LedgerDao（seed 双账本、defaultMoneyLedger/kcalLedger/watchAll） |
| lib/src/dao/category_dao.dart | +142/-0 | 新建：CategoryDao（22 条内置中文分类 seed，幂等按 kind+name） |
| lib/src/dao/default_seed.dart | +26/-0 | 新建：seedDefaultData 编排（device_id 先行 → 账本 → 分类） |
| lib/src/dao/todo_dao.dart | +209/-0 | 新建：TodoDao 基础 CRUD（done_at 只前进合并、收集箱流、投影联动） |
| lib/src/uuid_v7.dart | +49/-0 | 新建：UUIDv7 生成/generateDeviceIdHex12 |
| lib/core_db.dart | +18/-2 | 导出全部新 DAO |
| lib/src/app_database.dart | +5/-0 | beforeOpen 挂 seedDefaultData |
| pubspec.yaml | +6/-0 | 补 publish_to: none |
| test/entry_repository_test.dart、test/day_summary_projection_test.dart、test/todo_dao_test.dart、test/seed_idempotency_test.dart、test/test_support.dart | +526/-0、+459/-0、+229/-0、+154/-0、+129/-0 | 仓库语义/投影自愈/待办/seed 幂等专项 + 测试支撑（tryOpenTestDatabase/TestClock） |

### 影响范围
- **API**: 本模块 DAO 层整体建立（此后各 DAO 均按本提交确立的「事务内写+发戳+幂等 no-op」模板扩展）
- **跨模块**: 该提交主体含 apps/mobile、feature_dashboard（仪表盘真页）、Riverpod 全仓接线；W2 集成修复亦涉及本包（Companion.insert 非空列取裸值口径在此确立）
- **数据模型**: 无新表（W1 已冻结 21 表）；day_summaries 从空表变为实际投影落点
- **回滚指南**: `git revert 1ee4ab4`；检查文件：dao/ 全部新建文件、uuid_v7.dart；副作用：seed 不再执行（空库无默认账本/分类），上层仓库接口无实现（core_domain 接口悬空），依赖本包的全部业务模块编译失败——必须整体回滚到 W1

---

## [2026-11-16] W1 环境与地基：单仓分包 + Drift schema v1 + HLC 领域层（core_db 初始）

**类型**: feat
**提交**: 3b1f64c
**风险**: HIGH

### 变更文件（packages/core_db/，全量新建）
| 文件 | 变更 | 说明 |
|------|------|------|
| lib/src/app_database.dart | +78/-0 | AppDatabase：21 表聚合（同步真值 14 + 本地件 5 + 服务端为主 2）、schemaVersion=1、PRAGMA foreign_keys=ON |
| lib/src/app_database.g.dart | +23943/-0 | drift_dev 生成物 |
| lib/src/tables/event_tables.dart | +156/-0 | entries/entry_lines/food_items + 9 索引（facet 拆行落点） |
| lib/src/tables/infra_tables.dart | +303/-0 | corrections/theme_profiles/day_summaries/ai_parses/sync_outbox/sync_cursors/settings/devices/attachments |
| lib/src/tables/ledger_tables.dart | +102/-0 | ledgers/categories/budgets |
| lib/src/tables/plan_tables.dart | +210/-0 | fitness_sessions/fitness_plans/exercise_sets/todos/savings_goals/savings_contributions |
| lib/src/tables/sync_columns.dart | +40/-0 | SyncColumns mixin：7 个同步公共列 |
| lib/core_db.dart、pubspec.yaml、analysis_options.yaml、.gitignore、.metadata、README.md、CHANGELOG.md、LICENSE | +12/-0、+30/-0、+4/-0、+31/-0、+10/-0、+39/-0、+3/-0、+1/-0 | 包骨架（合计 +100） |
| test/schema_smoke_test.dart | +152/-0 | schema 冒烟（21 表建表/索引/公共列断言） |

### 影响范围
- **API**: AppDatabase 构造（executor 注入）+ openConnection；无 DAO（W2 起建立）
- **跨模块**: 仓库初始提交（apps/mobile、core_domain、ui_kit、infra、server/supabase 全部同期建立）；本包自此被 core_ai/feature_*/apps/mobile 依赖
- **数据模型**: schema v1 冻结（21 表）；design 文档 §5.2 声明的物理外键仅 entry_lines.entry_id 一处
- **回滚指南**: 初始提交不可 revert（仓库地基）；后续如需回到纯 schema 状态以 W2 前为准
