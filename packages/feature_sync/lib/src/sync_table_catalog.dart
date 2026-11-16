/// 同步真值表目录（§5.1 表分组「同步真值表 14 张」× §6.5 冲突矩阵行）。
///
/// LocalSyncEngine 不按表名硬编码策略（core_domain `ConflictClass` 文档
/// 「实现按此类分发，而不是按表名硬编码」）：每张表在此登记
/// - 冲突归属类 [SyncTableSpec.conflictClass]（§6.5 矩阵行）；
/// - 落库依赖序 [SyncTableSpec.rank]（app_database 注释「pull 需按父表→
///   子表依赖序落库」：entries 先于 entry_lines/food_items，满足
///   entry_lines.entry_id 的数据库外键，§5.2②）；
/// - 服务端行存在性检查的父表（§6.2 校验项「行存在性」）；
/// - day_summary 脏标记的日期来源（§5.6⑬ 重建规则「任何 entry_line /
///   corrections 变更 → 标记当日 dirty」）。
///
/// 明确不在目录内（永不同步，§5.1/§6.1 原则 3）：day_summary、ai_parses、
/// sync_outbox、sync_cursors、settings、devices、attachments。
library;

import 'package:core_domain/core_domain.dart';

/// 单张同步真值表的同步策略登记。
class SyncTableSpec {
  /// SQL 表名（drift `entityName`，与 §5.1 表清单 snake_case 一致）。
  final String name;

  /// §6.5 冲突矩阵行（仲裁按类分发，§6.5）。
  final ConflictClass conflictClass;

  /// 依赖序：rank 小者先落库（0=无父依赖；同 rank 内按表名排序保证确定性）。
  final int rank;

  /// 服务端「行存在性」检查的父表；null=不检查（如 corrections——审计日志
  /// 必须永可插入、不受跨表顺序影响，§5.6⑮）。
  final String? parentTable;

  /// [parentTable] 的引用键在本行快照中的键名（entry_id/session_id/goal_id）。
  final String? parentKey;

  /// 行快照自带的本地日历日键（yyyy-MM-dd，§5.1）：pull 落库后据此标记
  /// day_summary dirty（§5.6 重建规则）。
  final String? ownDateKey;

  /// 维度行（账本/分类/预算）变更影响所有已有投影日的 budget_snapshot，
  /// 落库后对全部 day_summary 行标 dirty（§5.6⑬ budget_snapshot 行）。
  final bool marksAllDatesDirty;

  const SyncTableSpec({
    required this.name,
    required this.conflictClass,
    required this.rank,
    this.parentTable,
    this.parentKey,
    this.ownDateKey,
    this.marksAllDatesDirty = false,
  });
}

/// §5.1「同步真值表 14 张」的策略目录（声明序=文档表序）。
const List<SyncTableSpec> kSyncTables = [
  // ① entries：事件主干——行级 LWW + 字段保留集（§6.5 第 2 行）。
  SyncTableSpec(
    name: 'entries',
    conflictClass: ConflictClass.entryLww,
    rank: 0,
    ownDateKey: 'date',
  ),
  // ② entry_lines：facet 拆行——不同 facet 行结构性免冲突；同 facet 行同
  //   字段并发=行级 LWW（§5.3/§6.5 第 3 行）。真实外键引用 entries（§5.2②）。
  SyncTableSpec(
    name: 'entry_lines',
    conflictClass: ConflictClass.facetRowLww,
    rank: 1,
    parentTable: 'entries',
    parentKey: 'entry_id',
  ),
  // ③ food_items：calorie 行子表（§5.2③）。
  SyncTableSpec(
    name: 'food_items',
    conflictClass: ConflictClass.scalarLww,
    rank: 2,
    parentTable: 'entries',
    parentKey: 'entry_id',
  ),
  // ④ ledgers：账本维度行，行级 LWW（§6.5 第 1 行口径）；影响预算快照。
  SyncTableSpec(
    name: 'ledgers',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
    marksAllDatesDirty: true,
  ),
  // ⑤ categories：分类维度行，同上。
  SyncTableSpec(
    name: 'categories',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
    marksAllDatesDirty: true,
  ),
  // ⑥ budgets：预算行，同上（ledger_id 仅逻辑引用不建外键，§5.4⑥——
  //   与 ledgers 同 rank 落库顺序不构成硬依赖）。
  SyncTableSpec(
    name: 'budgets',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
    marksAllDatesDirty: true,
  ),
  // ⑩ todos：done_at 完成事件只前进、set 胜（§6.5 第 6 行、§5.5⑩）。
  SyncTableSpec(
    name: 'todos',
    conflictClass: ConflictClass.todoDoneForward,
    rank: 0,
    ownDateKey: 'date',
  ),
  // ⑦ fitness_sessions：健身会话（自带 date，§5.5⑦）。
  SyncTableSpec(
    name: 'fitness_sessions',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
    ownDateKey: 'date',
  ),
  // ⑧ fitness_plans：健身计划（P1）。
  SyncTableSpec(
    name: 'fitness_plans',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
  ),
  // ⑨ exercise_sets：组明细（P1；依赖 fitness_sessions，§5.5⑨）。
  SyncTableSpec(
    name: 'exercise_sets',
    conflictClass: ConflictClass.scalarLww,
    rank: 1,
    parentTable: 'fitness_sessions',
    parentKey: 'session_id',
  ),
  // ⑪ savings_goals：存钱目标（P1）。
  SyncTableSpec(
    name: 'savings_goals',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
  ),
  // ⑫ savings_contributions：存钱贡献——append-only 并集（§6.5 第 5 行）。
  SyncTableSpec(
    name: 'savings_contributions',
    conflictClass: ConflictClass.appendOnly,
    rank: 1,
    parentTable: 'savings_goals',
    parentKey: 'goal_id',
    ownDateKey: 'date',
  ),
  // ⑮ corrections：修正审计——append-only 并集（§6.5 第 5 行）；审计日志
  //   永可插入，不做父行存在性检查（§5.6⑮）。日期经 entry_id 解析。
  SyncTableSpec(
    name: 'corrections',
    conflictClass: ConflictClass.appendOnly,
    rank: 1,
    parentKey: 'entry_id',
  ),
  // ⑳ theme_profiles：主题包一等同步实体——标量配置行级 LWW（§6.5 第 1 行）。
  SyncTableSpec(
    name: 'theme_profiles',
    conflictClass: ConflictClass.scalarLww,
    rank: 0,
  ),
];

/// 按表名取登记项；未知表名抛错（同步协议表集 W1 冻结，§5.1）。
SyncTableSpec syncTableSpec(String tableName) {
  for (final spec in kSyncTables) {
    if (spec.name == tableName) {
      return spec;
    }
  }
  throw ArgumentError.value(
    tableName,
    'tableName',
    '不是 §5.1 同步真值表（14 张冻结表之外无同步语义）',
  );
}

/// 落库依赖序（rank 升序、同序按表名典序）：父表先于子表（§6.2）。
List<SyncTableSpec> get syncTablesInApplyOrder {
  final list = [...kSyncTables]..sort((a, b) {
      final r = a.rank.compareTo(b.rank);
      if (r != 0) return r;
      return a.name.compareTo(b.name);
    });
  return list;
}
