/// §5.5 健身、计划与目标。
library;

import 'package:drift/drift.dart';

import 'sync_columns.dart';

/// ⑦ fitness_sessions — 健身会话（§5.5）。
///
/// entry_id 联动：会话落库时同事务生成 entry(kind=fitness) +
/// entry_lines(type=burn)，burn 行 payload 记 session_id——消耗行与
/// 钱/热量行共用同一 facet 行同步模型（§2.2/§5.5/§5.7）。
@DataClassName('FitnessSession')
class FitnessSessions extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 归属日 `yyyy-MM-dd`（§5.1 日期约定）。
  TextColumn get date => text()();

  /// 录入时本地时区偏移（分钟）。
  IntColumn get tzOffsetMin => integer()();

  /// 开始时刻 UTC ms。
  IntColumn get startAt => integer().nullable()();

  /// 时长（秒）。
  IntColumn get durationS => integer()();

  /// strength / cardio / hiit / other / template_instance。
  TextColumn get type => text()();

  /// MET 表估算（MET × 体重 × 时长），UI 按 ±20% 口径标注（§5.5）。
  IntColumn get kcalBurn => integer()();

  /// → entries.id：经此对应 entries(kind=fitness) 1:1 产出
  /// entry_lines(type=burn)（§5.7）。逻辑引用不建外键：会话与其 entry
  /// 同事务生成（§2.2），但跨设备 pull 顺序不定（§6.2）。
  TextColumn get entryId => text().nullable()();

  /// manual / timer / plan。
  TextColumn get source => text()();

  /// → 健身计划排期日（P1）。v1 无独立排期日表（21 表清单未含），
  /// 故为逻辑前向引用、不建外键（§5.5）。
  TextColumn get planDayId => text().nullable()();

  /// 备注。
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑧ fitness_plans — 健身计划（P1）（§5.5）。
@DataClassName('FitnessPlan')
class FitnessPlans extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 计划名。
  TextColumn get name => text()();

  /// bit0=周一…bit6=周日 排期掩码。
  IntColumn get weekdayMask => integer()();

  /// 排期模板 JSON：动作/组数/重量配比/休息秒。
  TextColumn get exercises => text()();

  /// 起始日 `yyyy-MM-dd`。
  TextColumn get startDate => text()();

  /// 启用（bool 存 INTEGER）。
  BoolColumn get active => boolean()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑨ exercise_sets — 组明细（P1 功能启用；同步真值表，含 §5.1 公共列，
/// W1 随 schema 建表、P1 启用——与 ledgers 同策略）（§5.5）。
@DataClassName('ExerciseSet')
class ExerciseSets extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// → fitness_sessions.id。逻辑引用不建外键（pull 依赖序，§6.2）。
  TextColumn get sessionId => text()();

  /// 动作库 id 或名称。
  TextColumn get exerciseRef => text()();

  /// 重量 ×10 定点（避免浮点同步问题，§5.5）。
  IntColumn get weightKgX10 => integer()();

  /// 次数。
  IntColumn get reps => integer()();

  /// 强度 RPE。
  RealColumn get rpe => real().nullable()();

  /// 休息秒。
  IntColumn get restS => integer().nullable()();

  /// 完成时刻 UTC ms。
  IntColumn get doneAt => integer()();

  /// 组序。
  IntColumn get sort => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑩ todos — 待办（计划族，独立于事件模型）（§5.5）。
///
/// done_at 合并规则只前进不回退：并发 set vs unset → set 胜
/// （勾选永不丢失，§5.5/§6.5）；该规则由同步层执行，schema 仅存列。
@DataClassName('Todo')
class Todos extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 标题。
  TextColumn get title => text()();

  /// 备注。
  TextColumn get note => text().nullable()();

  /// 计划日；NULL=无日期收集箱（§5.5）。
  TextColumn get date => text().nullable()();

  /// 完成时刻；合并只前进不回退（§6.5）。
  IntColumn get doneAt => integer().nullable()();

  /// 截止时刻 UTC ms。
  IntColumn get dueAt => integer().nullable()();

  /// RRULE（RFC5545，P1）。
  TextColumn get repeatRule => text().nullable()();

  /// 提醒时刻（P1）。
  IntColumn get remindAt => integer().nullable()();

  /// → savings_goals / fitness_plans（联动）。多态引用（目标可指向两类
  /// 表），无法建数据库外键，仅逻辑引用（§5.5）。
  TextColumn get goalLink => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑪ savings_goals — 存钱目标（P1）（§5.5）。
@DataClassName('SavingsGoal')
class SavingsGoals extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// 目标名。
  TextColumn get name => text()();

  /// 目标金额（分，INTEGER，§5.1）。
  IntColumn get targetMinor => integer()();

  /// 截止日 `yyyy-MM-dd`。
  TextColumn get deadline => text().nullable()();

  /// daily365 / week52 / custom。
  TextColumn get method => text()();

  /// 阶梯表或每日额（JSON）。
  TextColumn get rhythm => text()();

  /// active / completed / abandoned。
  TextColumn get status => text()();

  /// 起始日 `yyyy-MM-dd`。
  TextColumn get startedOn => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// ⑫ savings_contributions — 存钱贡献（P1，append-only 只增不改）（§5.5）。
///
/// 目标进度=Σ贡献行（本地投影），append-only 天然免同步冲突
/// （§5.5/§6.1 append-first）。行仍带 §5.1 公共列以参与统一同步协议。
@DataClassName('SavingsContribution')
class SavingsContributions extends Table with SyncColumns {
  /// UUIDv7 主键（应用层生成，§5.1）。
  TextColumn get id => text()();

  /// → savings_goals.id。逻辑引用不建外键（pull 依赖序，§6.2）。
  TextColumn get goalId => text()();

  /// 打卡日 `yyyy-MM-dd`。
  TextColumn get date => text()();

  /// 金额（分，INTEGER，§5.1）。
  IntColumn get amountMinor => integer()();

  /// 365/52 周存钱法格子号。
  IntColumn get slot => integer().nullable()();

  /// 备注。
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
