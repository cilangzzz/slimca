/// Slimca 本地数据库层（core_db）。
///
/// 职责（§10.4）：Drift schema + DAO + day_summary 投影。本库只暴露
/// schema 与数据库类；DAO/投影 W2 起按 feature 需求增量补充。
library;

export 'src/app_database.dart';
export 'src/tables/event_tables.dart';
export 'src/tables/infra_tables.dart';
export 'src/tables/ledger_tables.dart';
export 'src/tables/plan_tables.dart';
export 'src/tables/sync_columns.dart';
