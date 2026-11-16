/// §5.4 账本、分类、预算。
library;

import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// ④ ledgers — 账本（§5.4）。
///
/// MVP：表建好但恒默认 money 账本（schema 先冻结、功能后启用）。
/// kcal 账本：系统内置一个、不可删除不可多开，币种=kcal，预算=收入、
/// 吃=支出、运动=再入账（§5.4）。
@DataClassName('Ledger')
class Ledgers extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 账本名。
  TextColumn get name => text()();

  /// 图标标识。
  TextColumn get icon => text()();

  /// 币种（money 账本如 CNY；kcal 账本=kcal）。
  TextColumn get currency => text()();

  /// money / kcal。
  TextColumn get kind => text()();

  /// 排序。
  IntColumn get sort => integer()();

  /// 期初余额（分或 kcal，INTEGER，§5.1）。
  IntColumn get openingBalanceMinor => integer()();

  /// 归档（bool 存 INTEGER）。
  BoolColumn get isArchived => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑤ categories — 分类（§5.4）。
///
/// color_token 引用语义 token 名而非裸色值——主题可换肤的工程前提（§8.2）。
@DataClassName('Category')
class Categories extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 分类名。
  TextColumn get name => text()();

  /// 图标标识。
  TextColumn get icon => text()();

  /// 排序。
  IntColumn get sort => integer()();

  /// NULL=全局分类；逻辑引用不建外键（pull 依赖序，§6.2）。
  TextColumn get ledgerId => text().nullable()();

  /// expense / income。
  TextColumn get kind => text()();

  /// 引用语义 token 名（如 success/warn），禁止裸色值（§8.2）。
  TextColumn get colorToken => text()();

  /// 内置 20+ 中文分类不可删。
  BoolColumn get isPreset => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑥ budgets — 预算（§5.4）。
@DataClassName('Budget')
class Budgets extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 预算归属账本（含 kcal 账本）；逻辑引用不建外键（pull 依赖序，§6.2）。
  TextColumn get ledgerId => text()();

  /// NULL=总预算。
  TextColumn get categoryId => text().nullable()();

  /// daily（P0：热量+支出每日预算）/ monthly（P1）。
  TextColumn get periodType => text()();

  /// money=分；kcal 账本=kcal（一律 INTEGER，§5.1）。
  IntColumn get amount => integer()();

  /// 月度周期起点（P1）。
  IntColumn get dayOfMonthStart => integer()();

  /// 结转开关（P1，bool 存 INTEGER）。
  BoolColumn get carryOver => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}
