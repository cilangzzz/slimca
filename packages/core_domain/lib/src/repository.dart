/// 仓库抽象（§10.4 core_domain「实体+仓库接口」）。
///
/// 接口只声明领域需要的读写能力，Drift 实现在 core_db（§10.4），
/// 上层 feature_* 依赖抽象而非实现。方法签名覆盖：
/// - 事件 CRUD（含软删墓碑）；
/// - 按日期查询（本地日历日 yyyy-MM-dd，§5.1）；
/// - 金额不可变的强制点（§3.4「不可变性由仓库层强制」、§6.5 money 行）。
///
/// 所有实现必须遵守：
/// - 删除一律软删墓碑（§5.1 删除行），不物理删；
/// - 写入必须携带 HLC 并保持单调（§6.3），同步游标依赖 (updated_at)/(hlc) 索引；
/// - confirmed 的 money 行 amount 不可变，修正走 [EntryLineRepository.supersede]。
library;

import 'entry.dart';
import 'entry_line.dart';

/// 违反「确认后金额不可变」时抛出（§3.4 金额不可变、§6.5 money 行）。
class MoneyLineImmutableException implements Exception {
  final String lineId;
  MoneyLineImmutableException(this.lineId);

  @override
  String toString() =>
      'MoneyLineImmutableException: 金额行 $lineId 已确认，'
      '禁止原地改 amount；修正=新增 correction 行（§3.4/§6.5）';
}

/// 事件主干仓库（§5.2① entries）。
abstract interface class EntryRepository {
  /// 按主键取单条；含墓碑行（调用方用 [Entry.isDeleted] 判断）。
  Future<Entry?> findById(String id);

  /// 按本地日历日查询（索引 (date)，§5.2①）。
  Future<List<Entry>> findByDate(String date);

  /// 闭区间日期段查询，可按 kind 过滤（索引 (kind, date)，§5.2①）。
  /// 统计报表周/月/年（§3.4）与双轴联动复盘都走这里。
  Future<List<Entry>> findByDateRange(
    String startDate,
    String endDate, {
    List<EntryKind>? kinds,
  });

  /// 插入或更新主干行（upsert）。不含产出行——行经
  /// [EntryLineRepository] 独立写，保证 facet 独立变更/同步（§5.3）。
  Future<void> upsert(Entry entry);

  /// 软删墓碑（§5.1 删除行）。[hlc] 为本次删除操作的时间戳，
  /// 墓碑拒绝复活：删后编辑保持删除胜出（§6.5 删除行）。
  Future<void> softDelete(String id, {required String hlc});

  /// 响应式按日查询：仪表盘卡片墙与切日由 reactive stream 直驱（§10.1 Drift 行）。
  Stream<List<Entry>> watchByDate(String date);
}

/// 产出行仓库（§5.2② entry_lines）。
abstract interface class EntryLineRepository {
  Future<EntryLine?> findById(String id);

  /// 一件事的全部产出行（索引 (entry_id)，§5.2②）。
  Future<List<EntryLine>> findByEntryId(String entryId);

  /// 按本地日历日查产出行（经 entries.date 关联；day_summary 重算入口，§5.6⑬）。
  Future<List<EntryLine>> findByDate(String date);

  /// 按账本查活跃行（索引 (ledger_id, updated_at)，§5.2②）。
  /// kcal 账本与钱账本共用本入口（§2.1③）。
  Future<List<EntryLine>> findActiveByLedger(String ledgerId);

  /// 修正链查询：谁引用了旧行（索引 (correction_of)，§5.2②）。
  Future<List<EntryLine>> findByCorrectionOf(String originalLineId);

  /// 插入或更新产出行（upsert）。
  ///
  /// 强制边界（§3.4/§6.5）：目标为已确认的 money 行且 [line.amount]（或
  /// [line.type]/[line.status]）试图改变既有金额事实时，实现必须抛
  /// [MoneyLineImmutableException]；唯一合法路径是 [supersede] 新增修正行。
  Future<void> upsert(EntryLine line);

  /// 修正=新增行（§2.1②、§5.2② correction_of）：同一事务内写入
  /// [correction]（correction_of 指向 [oldLineId]）并把旧行置为
  /// superseded，同时追加 corrections 审计由实现或调用方按 §5.6⑮ 落库。
  Future<void> supersede(String oldLineId, EntryLine correction);
}
