/// 手动记账写路径用例（§11 W2 主线：手动记账 CRUD 全链路（无 AI））。
///
/// 落库规则（逐条对文档）：
/// - 一件事 = entries 主干 + 产出行 facet 行（§5.2/§5.3）：热量行、金额行
///   各自成行、各自 HLC（§5.3 多端并发改不同维度互不覆盖）；
/// - 手动录入即确认（status=confirmed，§2.3 步 2）——金额不可变自此生效
///   （§6.5 money 行）；
/// - 编辑：主干 LWW 更新（status→edited，§5.2①）+ 金额行走修正链新增
///   correction 行（§2.1②/§6.5），热量行同口径；
/// - 删除：软删墓碑（§5.1/§6.5），由 [EntryRepository.softDelete] 落地；
/// - 业务行 + sync_outbox 同事务（§6.2，由 Drift 仓库实现保证）。
library;

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
// BooleanExpressionOperators：`&` 谓词组合是 drift 扩展方法，需显式导入。
import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../app/providers.dart';

/// 手动录入入参（§5.2①）。
class ManualEntryInput {
  const ManualEntryInput({
    required this.date,
    required this.title,
    this.kcal = 0,
    this.amountMinor = 0,
  });

  /// 归属日 `yyyy-MM-dd`（§5.1 本地日历日，一切聚合按 date 分组）。
  final String date;

  /// 一句话描述（§5.2① title：AI 生成或用户输入；手动通道=用户输入）。
  final String title;

  /// 摄入 kcal（0=未记录；§5.1 热量一律 INTEGER）。
  final int kcal;

  /// 支出（分；0=未记录；§5.1 金额一律 INTEGER 分）。
  /// W2 手动通道只出账；收入随 W5-6 分类/每日目标体系一并接入（§11 W5-6）。
  final int amountMinor;
}

/// 用例服务 provider：主库（事务壳）+ 两仓库 + HLC 时钟（§6.3 发号）。
final manualEntryServiceProvider = Provider<ManualEntryService>((ref) {
  return ManualEntryService(
    ref.watch(appDatabaseProvider),
    ref.watch(entryRepositoryProvider),
    ref.watch(entryLineRepositoryProvider),
    ref.watch(hlcClockProvider),
  );
});

/// 手动记账用例（§11 W2：手动记一笔 → 仪表盘环/支出卡即时更新）。
class ManualEntryService {
  ManualEntryService(this._db, this._entries, this._lines, this._clock);

  final db.AppDatabase _db;
  final EntryRepository _entries;
  final EntryLineRepository _lines;
  final HlcClock _clock;

  static const Uuid _uuid = Uuid();

  /// 新建手动记账，返回事件 id。
  Future<String> saveNew(ManualEntryInput input) async {
    final entry = Entry(
      id: _uuid.v7(),
      date: input.date,
      tzOffsetMin: DateTime.now().timeZoneOffset.inMinutes,
      occurredAt: DateTime.now().millisecondsSinceEpoch,
      kind: _deriveKind(input),
      source: EntrySource.manual,
      title: input.title,
      status: EntryStatus.confirmed,
      meta: _stampMeta(),
    );
    final moneyLedgerId = await _builtinLedgerId('money');
    final kcalLedgerId = await _builtinLedgerId('kcal');

    // 单事务：主干 + 各 facet 行（§5.3 拆行；§6.2 同事务写 outbox 由仓库保证）。
    await _db.transaction(() async {
      await _entries.upsert(entry);
      if (input.kcal > 0) {
        await _lines.upsert(
          _calorieLine(entryId: entry.id, kcal: input.kcal, ledgerId: kcalLedgerId, meta: _stampMeta()),
        );
      }
      if (input.amountMinor > 0) {
        await _lines.upsert(
          _moneyLine(
            entryId: entry.id,
            amountMinor: input.amountMinor,
            ledgerId: moneyLedgerId,
            meta: _stampMeta(),
          ),
        );
      }
    });
    return entry.id;
  }

  /// 编辑已确认事件（§6.5：confirmed 后金额不可变，修正=新增行）。
  Future<void> editEntry({
    required String entryId,
    required ManualEntryInput input,
  }) async {
    final old = await _entries.findById(entryId);
    if (old == null) {
      throw StateError('待编辑事件 $entryId 不存在');
    }
    if (old.isDeleted) {
      throw StateError('墓碑拒绝复活：事件 $entryId 已删除（§6.5）');
    }

    final moneyLedgerId = await _builtinLedgerId('money');
    final kcalLedgerId = await _builtinLedgerId('kcal');

    // 主干：保留 created_at、revision 自增（§5.1），新发 HLC（§6.3 单调）。
    final meta = SyncMeta(
      createdAt: old.meta.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      hlc: _clock.now().format(),
      revision: old.meta.revision + 1,
      schemaVer: kCurrentSchemaVer,
      deviceId: _clock.deviceId,
    );
    final edited = old.copyWith(
      title: input.title,
      kind: _deriveKind(input),
      status: EntryStatus.edited, // 含修正（§5.2① status 行）
      meta: meta,
    );

    final oldLines = (await _lines.findByEntryId(entryId))
        .where((l) => !l.isDeleted && l.status == LineStatus.active)
        .toList();
    final oldMoney = _firstOfType(oldLines, LineType.money);
    final oldCalorie = _firstOfType(oldLines, LineType.calorie);

    await _db.transaction(() async {
      await _entries.upsert(edited);

      // 金额行（§6.5 money 行：confirmed 后唯一合法路径=新增 correction 行）。
      if (oldMoney != null) {
        if (oldMoney.amount != input.amountMinor) {
          await _lines.supersede(
            oldMoney.id,
            _moneyLine(
              entryId: entryId,
              // 作废修正行保留原金额作审计锚点（§5.6⑮ 修正审计口径）。
              amountMinor: input.amountMinor > 0 ? input.amountMinor : oldMoney.amount,
              ledgerId: oldMoney.ledgerId ?? moneyLedgerId,
              meta: _stampMeta(),
              status: input.amountMinor > 0 ? LineStatus.active : LineStatus.void_,
              correctionOf: oldMoney.id,
            ),
          );
        }
      } else if (input.amountMinor > 0) {
        await _lines.upsert(
          _moneyLine(
            entryId: entryId,
            amountMinor: input.amountMinor,
            ledgerId: moneyLedgerId,
            meta: _stampMeta(),
          ),
        );
      }

      // 热量行（§5.3 facet 行独立变更，同口径修正链）。
      if (oldCalorie != null) {
        if (oldCalorie.amount != input.kcal) {
          await _lines.supersede(
            oldCalorie.id,
            _calorieLine(
              entryId: entryId,
              kcal: input.kcal > 0 ? input.kcal : oldCalorie.amount,
              ledgerId: oldCalorie.ledgerId ?? kcalLedgerId,
              meta: _stampMeta(),
              status: input.kcal > 0 ? LineStatus.active : LineStatus.void_,
              correctionOf: oldCalorie.id,
            ),
          );
        }
      } else if (input.kcal > 0) {
        await _lines.upsert(
          _calorieLine(
            entryId: entryId,
            kcal: input.kcal,
            ledgerId: kcalLedgerId,
            meta: _stampMeta(),
          ),
        );
      }
    });
  }

  /// 软删墓碑（§5.1/§6.5：墓碑拒绝复活，删后编辑保持删除胜出）。
  Future<void> deleteEntry(String entryId) async {
    await _entries.softDelete(entryId, hlc: _clock.now().format());
  }

  // ── 内部装配 ────────────────────────────────────────────────────

  /// kind 推导（§5.2① kind 列：food/fitness/expense/mixed/note）。
  EntryKind _deriveKind(ManualEntryInput input) {
    if (input.kcal > 0 && input.amountMinor > 0) return EntryKind.mixed;
    if (input.kcal > 0) return EntryKind.food;
    if (input.amountMinor > 0) return EntryKind.expense;
    return EntryKind.note;
  }

  /// 新行公共列（§5.1）：HLC 新发号（§6.3 单调）、revision 本地自增起步=1。
  SyncMeta _stampMeta() {
    final hlc = _clock.now();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return SyncMeta(
      createdAt: nowMs,
      updatedAt: nowMs,
      hlc: hlc.format(),
      revision: 1,
      schemaVer: kCurrentSchemaVer,
      deviceId: _clock.deviceId,
    );
  }

  /// 摄入行（§5.2② calorie=in；人工行 confidence=NULL）。
  EntryLine _calorieLine({
    required String entryId,
    required int kcal,
    required String? ledgerId,
    required SyncMeta meta,
    LineStatus status = LineStatus.active,
    String? correctionOf,
  }) =>
      EntryLine(
        id: _uuid.v7(),
        entryId: entryId,
        type: LineType.calorie,
        amount: kcal,
        direction: LineDirection.income,
        ledgerId: ledgerId,
        status: status,
        correctionOf: correctionOf,
        meta: meta,
      );

  /// 金额行（§5.2② money 行：amount=分，默认 CNY；W2 支出=out）。
  EntryLine _moneyLine({
    required String entryId,
    required int amountMinor,
    required String? ledgerId,
    required SyncMeta meta,
    LineStatus status = LineStatus.active,
    String? correctionOf,
  }) =>
      EntryLine(
        id: _uuid.v7(),
        entryId: entryId,
        type: LineType.money,
        amount: amountMinor,
        direction: LineDirection.outcome,
        ledgerId: ledgerId,
        currency: 'CNY',
        status: status,
        correctionOf: correctionOf,
        meta: meta,
      );

  EntryLine? _firstOfType(List<EntryLine> lines, LineType type) {
    for (final line in lines) {
      if (line.type == type) return line;
    }
    return null;
  }

  /// 内置账本 id（§5.4：money=默认账本、kcal=系统内置热量账本；W2 恒默认）。
  Future<String?> _builtinLedgerId(String kind) async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals(kind) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first.id;
  }
}
