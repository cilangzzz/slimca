/// §5.6 投影、审计与同步基础设施。
///
/// 分组（§5.1 表分组）：corrections/theme_profiles 为同步真值表（携 §5.1
/// 公共列）；day_summary/ai_parses/sync_outbox/sync_cursors/settings 为
/// 本地件、永不同步；devices/attachments 为服务端为主件——三者均不携
/// 公共列。
library;

import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// ⑮ corrections — 修正审计日志（append-only，同步真值）（§5.6）。
///
/// 「确认后金额不可变、修正=新增行」的数据底座：既是审计（账目可信）也是
/// 个人校准资产（P2 喂个性化系数，§5.6）。entry_id/line_id 仅逻辑引用不建
/// 外键：审计日志必须永可插入，不受跨表 pull 顺序影响（§6.2）。
@DataClassName('Correction')
class Corrections extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 修正对象所在事件。
  TextColumn get entryId => text()();

  /// 修正对象所在产出行（可空）。
  TextColumn get lineId => text().nullable()();

  /// kcal / amount / category / portion / …
  TextColumn get field => text()();

  /// 字段级前值（TEXT 序列化）。
  TextColumn get oldValue => text()();

  /// 字段级后值（TEXT 序列化）。
  TextColumn get newValue => text()();

  /// user / ai_recalib。
  TextColumn get source => text()();

  // created_at 由 SyncColumns 提供（§5.1 公共列，与文档字段清单一致）。

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑳ theme_profiles — 主题包（一等同步实体，换设备主题跟随）（§5.6/§8.1）。
@DataClassName('ThemeProfile')
class ThemeProfiles extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 主题包名（内置 6 套：墨/纸/霓虹/奶油/森野/曜黑，§8.3）。
  TextColumn get name => text()();

  /// 语义 token 集 JSON（§8.2 三层架构第 2 层）。
  TextColumn get tokens => text()();

  /// 动效等级：off/reduced/full（§9.2 MotionLevel）。
  TextColumn get motionLevel => text()();

  /// 字体 id（可空）。
  TextColumn get fontId => text().nullable()();

  /// 内置包不可删。
  BoolColumn get isPreset => boolean()();

  /// 排序。
  IntColumn get sort => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑬ day_summary — 当日聚合投影（本地物化，永不同步）（§5.6）。
///
/// 派生量永不存储到同步表、永不同步（§5.1/§6.1 原则 3），双端从明细行各自
/// 重建、永远自愈（§6.5）。重建规则：任何 entry_line / corrections 变更 →
/// 标记当日 dirty → 后台重算；仪表盘冷启动首帧直读本表、零业务查询（§5.6）。
@DataClassName('DaySummary')
class DaySummaries extends Table {
  /// 本地日历日 `yyyy-MM-dd` 作主键（一天一投影行）。
  TextColumn get date => text()();

  /// 时区偏移（分钟）。
  IntColumn get tzOffsetMin => integer()();

  /// 摄入 kcal。
  IntColumn get kcalIn => integer()();

  /// 消耗 kcal。
  IntColumn get kcalOut => integer()();

  /// 净 kcal。
  IntColumn get netKcal => integer()();

  /// 支出（分）。
  IntColumn get spendMinor => integer()();

  /// 收入（分）。
  IntColumn get incomeMinor => integer()();

  /// 待办完成数。
  IntColumn get todoDone => integer()();

  /// 待办总数。
  IntColumn get todoTotal => integer()();

  /// 预算余量快照 JSON。
  TextColumn get budgetSnapshot => text()();

  /// 存钱目标进度快照 JSON（goal_id→{contributed_minor,target_minor}），
  /// P1 存钱上线后启用（§5.6）。
  TextColumn get savingsProgress => text().nullable()();

  /// 构建时刻 UTC ms。
  IntColumn get builtAt => integer()();

  /// 重建标记（bool 存 INTEGER）。
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {date};
}

/// ⑭ ai_parses — AI 留痕与缓存（本地，不同步）（§5.6）。
///
/// input_hash=sha256(规范化输入) 即缓存键，命中且 <7 天直接复用；7 天时效
/// 判断可由 UUIDv7 id 内嵌时间戳得出（id 时间有序，§5.1），故不另设时间列。
/// provider/model 可 A/B 对比；cost 以微元计、成本可审计（§5.6）。
@DataClassName('AiParse')
class AiParses extends Table {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// text / voice / photo。
  TextColumn get inputKind => text()();

  /// sha256(规范化输入)=缓存键。
  TextColumn get inputHash => text()();

  /// 供应商（可 A/B 对比）。
  TextColumn get provider => text()();

  /// 模型名。
  TextColumn get model => text()();

  /// 原始结构化输出 JSON（可回放排查）。
  TextColumn get rawOutput => text()();

  /// 延迟（毫秒）。
  IntColumn get latencyMs => integer()();

  /// 成本（微元计，可审计）。
  IntColumn get cost => integer()();

  /// 解析置信度。
  RealColumn get confidence => real()();

  /// 提示词版本。
  TextColumn get promptVersion => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑯ sync_outbox — 出网队列（一切出网必经之路）（§5.6/§6.2）。
///
/// 写路径：UI → Drift 事务提交（业务行 + sync_outbox 同事务写入，§6.2）；
/// id 即幂等键，服务端据此去重。outbox 本身是本地件、永不再同步。
@DataClassName('SyncOutboxItem')
class SyncOutbox extends Table {
  /// 幂等键（服务端据此去重，§6.2）。
  TextColumn get id => text()();

  /// 目标表名。
  ///
  /// Dart getter 名不能叫 `tableName`——drift 的 `Table.tableName` 是框架
  /// 自有成员（自定义 SQL 表名钩子），列 getter 与之冲突会破坏生成代码；
  /// 故 getter 取 `targetTable`，用 `.named('table_name')` 冻结 SQL 列名
  /// 与文档 §5.6 表结构一致。
  TextColumn get targetTable => text().named('table_name')();

  /// 目标行 id。
  TextColumn get rowId => text()();

  /// upsert / delete。
  TextColumn get op => text()();

  /// 行快照 JSON。
  TextColumn get payload => text()();

  /// 乐观校验用基线版本。
  IntColumn get baseRevision => integer().nullable()();

  /// 入队时 HLC（定宽编码，§6.3）。
  TextColumn get hlc => text()();

  /// 入队时刻 UTC ms。
  IntColumn get createdAt => integer()();

  /// 确认时刻（NULL=未 ack；§6.2 写路径回写）。
  IntColumn get ackedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑱ sync_cursors — per-table 增量拉取游标（§5.6/§6.2）。
@DataClassName('SyncCursor')
class SyncCursors extends Table {
  /// 设备 id。
  TextColumn get deviceId => text()();

  /// 表名。
  ///
  /// 同 [SyncOutbox.targetTable]：getter 避让 drift `Table.tableName` 钩子，
  /// SQL 列名经 `.named('table_name')` 保持 §5.6 文档口径。
  TextColumn get targetTable => text().named('table_name')();

  /// 已拉取到的 HLC 水位（§6.2 since_hlc）。
  TextColumn get pullHlc => text()();

  @override
  Set<Column> get primaryKey => {deviceId, targetTable};
}

/// ⑲ settings — 本地键值配置（§5.6）。
///
/// 内容：身体档案（体重）/默认账本/AI 开关/raw_input 上云开关/动效等级/
/// 当前主题（§5.6）。标量配置冲突走行级 LWW——但其同步由服务端 settings
/// 表承担，本地件仅存键值（§6.5）。
@DataClassName('Setting')
class Settings extends Table {
  /// 配置键。
  TextColumn get key => text()();

  /// 配置值（JSON）。
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// ⑰ devices — 设备注册（服务端为主，本地引用登记）（§5.6）。
///
/// 一键下线/远程清空（P1/P2）。服务端为主件，不携 §5.1 公共列。
@DataClassName('Device')
class Devices extends Table {
  /// = device_id（与 §5.1 公共列 device_id 同域）。
  TextColumn get id => text()();

  /// 设备名。
  TextColumn get name => text()();

  /// 平台（ios/android/…）。
  TextColumn get platform => text()();

  /// 注册时刻 UTC ms。
  IntColumn get createdAt => integer()();

  /// 最后在线时刻 UTC ms。
  IntColumn get lastSeenAt => integer()();

  /// 下线/吊销时刻（NULL=未吊销）。
  IntColumn get revokedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ㉑ attachments — 附件引用登记（P1，服务端为主）（§5.6）。
///
/// 拍照通道（§11.2 W11-12、§3.3「原图解析后即焚不落存储」、§5.6「默认
/// 『解析后即焚』：原图不落服务端；仅结构化引用可同步」）的本地审计台账：
/// - 行只登记元数据（路径/哈希/字节大小/mime），内容本体在文件系统；
/// - 即焚状态机（§3.3 拍照通道）：`active`（本地内容存在）→ `burned`
///   （内容已焚毁），单向、不可逆（恢复无意义——内容已销毁）；
/// - burned 行保留全部审计元数据（hash/size/mime/local_path/burned_at），
///   只焚毁内容不抹除痕迹（合规审计：照片曾在、何时焚毁，§3.9 隐私自查）；
/// - 同步口径：attachments 不在 §5.1「同步真值表 14 张」内（§5.6 表分组
///   「服务端为主 2 张」），即焚生命周期 status/burned_at 为设备本地审计
///   列、不参与同步——服务端 schema（server/supabase 0001_init.sql）的
///   attachments 为结构化引用登记，客户端焚毁动作不出网。
///
/// schema 演进注记（§6.4「行级 schema_ver 只加列前向兼容」）：status 带
/// 默认值 'active'、burned_at 可空——v1 内补列（schemaVersion 保持 1），
/// 旧 v1 库文件由 `backfillAttachmentBurnColumns` 幂等补列（见
/// dao/attachments_dao.dart），规避 v1-v3 冻结期的迁移风险。
@DataClassName('Attachment')
class Attachments extends Table {
  /// UUIDv7 主键（应用层生成，§5.1）。
  ///
  /// id 内嵌 48 位 unix 毫秒——即焚清理（>7 天残留强制焚毁）的「残留
  /// 时长」判据由此得出，不另设 created_at 列（§5.6⑭ ai_parses「7 天时效
  /// 判断可由 UUIDv7 id 内嵌时间戳得出，故不另设时间列」同一口径）。
  TextColumn get id => text()();

  /// 所属事件（可空：拍照先于事件落库）；逻辑引用不建外键
  /// （服务端为主、pull 顺序不定）。
  TextColumn get entryId => text().nullable()();

  /// 去重键（sha256 内容哈希；去重由应用层查重保证，§5.6）。
  TextColumn get contentHash => text()();

  /// photo / receipt。
  TextColumn get kind => text()();

  /// MIME 类型。
  TextColumn get mime => text()();

  /// 字节数。
  IntColumn get sizeBytes => integer()();

  /// 本地文件路径。
  ///
  /// 即焚后保留（审计元数据：内容曾在此、已焚毁），不代表内容仍存在。
  TextColumn get localPath => text()();

  /// 服务端 blob 引用（可空；默认即焚为 NULL——原图不落服务端，§5.6）。
  TextColumn get blobRef => text().nullable()();

  /// 即焚状态机（§3.3）：active（本地内容存在）/ burned（内容已焚毁）。
  /// 列默认值 'active'：v1 内补列的迁移风险规避（§6.4 只加列）。
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// 即焚时刻 UTC ms（NULL=未焚毁）——审计元数据（保留时刻、不保留内容）。
  IntColumn get burnedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
