/// §5.2 核心实体：事件与产出行（facet 模型）。
///
/// 「同一条事件的多维度」拆成 entry_lines 行而非 entry 宽表列（§5.3）：
/// 手机改金额、平板改热量产生两行各自的 updated_at/hlc，同步合并互不覆盖，
/// 多数冲突在数据结构层被消灭，而非靠 LWW 补救。
library;

import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// ① entries — 事件主干（一件事）（§5.2）。
@DataClassName('Entry')
@TableIndex(name: 'idx_entries_date', columns: {#date})
@TableIndex(name: 'idx_entries_kind_date', columns: {#kind, #date})
@TableIndex(name: 'idx_entries_updated_at', columns: {#updatedAt})
@TableIndex(name: 'idx_entries_hlc', columns: {#hlc})
class Entries extends Table with SyncColumns {
  /// UUIDv7 主键，TEXT 存储（§5.1）；由应用层生成（时间有序、同步友好），
  /// 数据库层不设默认值。
  TextColumn get id => text()();

  /// 本地日历日 `yyyy-MM-dd`：事件归属日（可非今天）；一切聚合按 date 分组，
  /// 杜绝 UTC 错日（§5.1 日期约定）。
  TextColumn get date => text()();

  /// 录入时本地时区偏移（分钟），与 [date] 配对。
  IntColumn get tzOffsetMin => integer()();

  /// 事件发生时刻 UTC ms（可早于录入时刻）。
  IntColumn get occurredAt => integer().nullable()();

  /// food / fitness / expense / mixed（钱+热量）/ note。
  TextColumn get kind => text()();

  /// text / voice / photo / receipt / chip（复记）/ manual。
  TextColumn get source => text()();

  /// 一句话描述（AI 生成或用户输入）。
  TextColumn get title => text()();

  /// 备注。
  TextColumn get note => text().nullable()();

  /// draft（AI 字段可被新解析覆盖）/ confirmed / edited（含修正）。
  TextColumn get status => text()();

  /// → ai_parses.id 溯源。注意：ai_parses 是本地件、永不同步（§5.6），
  /// 因此这里只做逻辑引用、不建数据库外键——否则其他设备 pull 回的
  /// entries 行会因本地无对应 ai_parses 而无法插入（§6.2 per-table 拉取）。
  TextColumn get aiParseId => text().nullable()();

  // device_id（创建设备）由 SyncColumns 提供（§5.1 公共列）。

  @override
  Set<Column> get primaryKey => {id};
}

/// ② entry_lines — 产出行（facet 行，差异化的物理落点）（§5.2）。
@DataClassName('EntryLine')
@TableIndex(name: 'idx_entry_lines_entry_id', columns: {#entryId})
@TableIndex(name: 'idx_entry_lines_type', columns: {#type})
@TableIndex(name: 'idx_entry_lines_ledger_updated_at', columns: {#ledgerId, #updatedAt})
@TableIndex(name: 'idx_entry_lines_correction_of', columns: {#correctionOf})
@TableIndex(name: 'idx_entry_lines_hlc', columns: {#hlc})
class EntryLines extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// → entries.id。文档明确标注 FK、软删不级联物理删：默认 NO ACTION
  /// （不级联），物理 GC 时先删子行再删墓碑（§5.1）。
  /// 同步 pull 需保证父表行先于子表行落库（per-table 游标按依赖序处理，§6.2）。
  TextColumn get entryId => text().references(Entries, #id)();

  /// calorie（摄入）/ burn（运动消耗）/ money（金额）。
  TextColumn get type => text()();

  /// calorie/burn=kcal；money=分（正数）。金额一律最小货币单位、kcal 一律
  /// INTEGER（§5.1）。
  IntColumn get amount => integer()();

  /// in / out（calorie=in；burn=out；money 按 expense=out / income=in）。
  TextColumn get direction => text()();

  /// money 行必填（默认账本）；kcal 行归集到内置 kcal 账本（§5.4 ledgers.kind）。
  /// 仅逻辑引用，不建外键：账本可能尚在 pull 队列中。
  TextColumn get ledgerId => text().nullable()();

  /// money 行=消费分类；calorie 行可挂餐饮子类（面食等）。
  TextColumn get categoryId => text().nullable()();

  /// money 行，默认 CNY。
  TextColumn get currency => text().nullable()();

  /// AI 置信度 0-1（AI 产出行必填；人工行 NULL）。
  RealColumn get confidence => real().nullable()();

  /// 行级明细引用 JSON：商户/支付方式/MET 参数/菜品数组摘要。
  /// burn 行 payload 记 session_id（§5.5 fitness_sessions.entry_id 说明）。
  TextColumn get payload => text().nullable()();

  /// 指向被修正旧行 id；修正=新增行，旧行 status→superseded（§5.2/§6.5）。
  TextColumn get correctionOf => text().nullable()();

  /// active / superseded（被修正）/ void（作废）。
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ③ food_items — 菜品明细（calorie 行子表）（§5.2）。
@DataClassName('FoodItem')
class FoodItems extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// → entries.id（逻辑引用；pull 依赖序由同步层保证，见 §6.2）。
  TextColumn get entryId => text()();

  /// → entry_lines.id（逻辑引用，同上）。
  TextColumn get lineId => text()();

  /// 菜品名（中文优先）。
  TextColumn get name => text()();

  /// 份量（克），滑杆联动重算的基准。
  RealColumn get portionG => real()();

  /// 热量（kcal，一律 INTEGER，§5.1）。
  IntColumn get kcal => integer()();

  /// 蛋白质（克）。
  RealColumn get proteinG => real()();

  /// 碳水（克）。
  RealColumn get carbG => real()();

  /// 脂肪（克）。
  RealColumn get fatG => real()();

  /// 联查来源：usda / off / baidu / local / llm。
  TextColumn get refSource => text()();

  /// 来源库条目 id。
  TextColumn get refId => text().nullable()();

  /// 该菜品级置信度。
  RealColumn get confidence => real()();

  /// 用户是否改过（校准信号，bool 存 INTEGER）。
  BoolColumn get userAdjusted => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}
