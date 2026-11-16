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
///   （§5.4、§3.4、§5.5⑩）。
library;

export 'src/app_database.dart';
export 'src/dao/category_dao.dart';
export 'src/dao/day_summary_projection.dart';
export 'src/dao/default_seed.dart';
export 'src/dao/entry_line_repository.dart';
export 'src/dao/entry_repository.dart';
export 'src/dao/ledger_dao.dart';
export 'src/dao/local_write_clock.dart';
export 'src/dao/todo_dao.dart';
export 'src/tables/event_tables.dart';
export 'src/tables/infra_tables.dart';
export 'src/tables/ledger_tables.dart';
export 'src/tables/plan_tables.dart';
export 'src/tables/sync_columns.dart';
export 'src/uuid_v7.dart';
