/// Slimca 本地数据库层（core_db）。
///
/// 职责（§10.4）：Drift schema + DAO + 仓库实现 + day_summary 投影。
/// - schema（W1 冻结）：21 张表，见 `src/tables/`；
/// - 仓库实现（W2）：`DriftEntryRepository` / `DriftEntryLineRepository`
///   实现 core_domain 的接口（软删墓碑、watch 流、supersede 事务语义、
///   money 行不可变，§5.2/§5.3/§6.5）；
/// - 投影（W2）：`DaySummaryProjection`——day_summary v1 重算与自愈
///   （§5.6⑬），仪表盘快照直出（§3.2）；
/// - DAO（W2）：LedgerDao/CategoryDao/TodoDao 及空库默认数据 seed
///   （§5.4、§3.4、§5.5⑩）；
/// - 出网入队（W5-6 补课/W7-8）：`SyncOutboxWriter`——§6.2 写路径纪律
///   「真值表行快照与业务行同事务入队 sync_outbox」的统一落点；
/// - 拍照通道（W11-12，§11.2 主线）：`AttachmentsDao`——附件引用登记与
///   「解析后即焚」状态机（active→burned 单向、>7 天残留强制清理，§5.6㉑/
///   §3.3）；`FoodItemsDao`——菜品明细 CRUD 与按 entry 查询（§5.2③，写
///   路径同事务入队 outbox 与 §6.2 纪律同口径）；
/// - 存钱目标（W13，§11.2 主线「待办完整版+存钱目标」）：`SavingsGoalsDao`/
///   `SavingsContributionsDao`——目标 CRUD 与归档（软删）、贡献 append-only
///   追加（幂等按 goal+date+source，§5.5⑫/§6.1）、按目标求和进度；
///   `DaySummaryProjection` 的 savings_progress 快照实装（§5.6⑬，
///   goal_id→{contributed_minor,target_minor} 多目标）与
///   `parseSavingsProgress` 解包辅助；`TodoDao` 增补重复规则三字段
///   （repeat_rule/rrule_anchor_date/remind_at，§5.5⑩）。
/// - 多账本+预算体系（W15，§11.2 主线）：`LedgerDao` 扩展账本生命周期写
///   路径——建账本/重命名/归档软删/切换默认（kcal 账本不可删不可多开，
///   §5.4④/§3.4 多账本 P1）；`BudgetsDao`——预算 CRUD（按账本/按分类/
///   总预算，周期 daily/monthly，§5.4⑥）与投影联动；
///   `DaySummaryProjection` 的 budget_snapshot **v2** 实装（§5.6⑬：
///   daily+monthly 双周期，daily 项键形向后兼容 v1，迁移注记见
///   day_summary_projection.dart）。
library;

export 'src/app_database.dart';
export 'src/dao/attachments_dao.dart';
export 'src/dao/budgets_dao.dart';
export 'src/dao/category_dao.dart';
export 'src/dao/day_summary_projection.dart';
export 'src/dao/default_seed.dart';
export 'src/dao/entry_line_repository.dart';
export 'src/dao/entry_repository.dart';
export 'src/dao/food_items_dao.dart';
export 'src/dao/ledger_dao.dart';
export 'src/dao/local_write_clock.dart';
export 'src/dao/savings_dao.dart';
export 'src/dao/sync_outbox_writer.dart';
export 'src/dao/todo_dao.dart';
export 'src/tables/event_tables.dart';
export 'src/tables/infra_tables.dart';
export 'src/tables/ledger_tables.dart';
export 'src/tables/plan_tables.dart';
export 'src/tables/sync_columns.dart';
export 'src/uuid_v7.dart';
