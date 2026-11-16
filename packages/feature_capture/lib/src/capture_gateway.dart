/// 录入网关：组合 core_db 的仓库实现 + 手动记账/修正闭环的 W2 写路径
/// （§3.3 手动路径、§3.4 记账、§10.4 分层）。
///
/// 分层边界（§10.4「接口在 core_domain、实现在 core_db」）：持久化语义
/// （软删墓碑、money 行不可变守卫、supersede 事务、day_summary 投影联动）
/// 全部由 core_db 的 `DriftEntryRepository` / `DriftEntryLineRepository`
/// 承担；本库不重复实现仓库，只做 feature 层编排：
/// - 写路径组装：entries(kind=expense) + entry_lines(type=money) 的实体
///   构造与同事务落库（§5.2 facet 拆行），HLC 由注入的 [dom.HlcClock]
///   签发（§6.3 定宽编码）；
/// - 修正闭环编排：主干字段与金额行的变更分流 + corrections 审计行落库
///   （§5.6⑮ 明确「审计行由调用方落库」，仓库层无从得知字段级前后值）；
/// - 选项装载：money 账本/按方向过滤分类/编辑回填目标（§3.3/§5.4）。
///
/// 宿主装配（§10.4 壳负责装配）：override [captureGatewayProvider]，其中
/// [dom.HlcClock] 必须是应用级单例（HLC 单调性是全设备唯一全序来源）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_models.dart';

/// 依赖注入点（§10.4：壳负责装配）。宿主必须 override：
/// `captureGatewayProvider.overrideWithValue(createCaptureGateway(db, clock))`。
/// 未 override 直接读即抛错——装配遗漏在开发期立刻暴露，而非静默错库。
final Provider<CaptureGateway> captureGatewayProvider = Provider<CaptureGateway>(
  (ref) => throw UnimplementedError(
    '宿主必须 override captureGatewayProvider（§10.4 壳负责装配）：'
    'captureGatewayProvider.overrideWithValue('
    'createCaptureGateway(db: AppDatabase, clock: HlcClock))',
  ),
);

/// 构造录入网关（宿主装配入口）。
///
/// [projection] 可选注入 day_summary 投影（§5.6⑬）：非空时仓库写后同事务
/// 重算受影响日期，支撑 W2 验收「手动记一笔→仪表盘环/支出卡即时更新」。
CaptureGateway createCaptureGateway({
  required cdb.AppDatabase db,
  required dom.HlcClock clock,
  cdb.DaySummaryProjection? projection,
}) =>
    CaptureGateway._(database: db, clock: clock, projection: projection);

/// 录入域网关：core_db 双仓库 + W2 手动记账/修正编排（§11.1 W2）。
class CaptureGateway {
  CaptureGateway._({
    required cdb.AppDatabase database,
    required this.clock,
    cdb.DaySummaryProjection? projection,
  })  : db = database,
        entries = cdb.DriftEntryRepository(database, projection: projection),
        entryLines = cdb.DriftEntryLineRepository(database, projection: projection);

  final cdb.AppDatabase db;

  /// 应用级单例时钟（§6.3）：本网关签发的所有行 HLC 皆源于此。
  final dom.HlcClock clock;

  /// 事件主干仓库（core_db 实现，§10.4）。
  final cdb.DriftEntryRepository entries;

  /// 产出行仓库（core_db 实现，含 supersede 事务与 money 不可变守卫）。
  final cdb.DriftEntryLineRepository entryLines;

  /// 供宿主把同一实现注册为全局仓库（§10.4：feature 依赖抽象而非实现）。
  dom.EntryRepository get asEntryRepository => entries;
  dom.EntryLineRepository get asEntryLineRepository => entryLines;

  // ── 内部签发辅助（§5.1 公共列 / §6.3 HLC）─────────────────────────

  int get _nowMs => clock.wallClock();

  String _newId() => cdb.generateUuidV7();

  /// 新行的公共列（§5.1）：hlc 由 HlcClock 签发、revision 本地自增起步=1。
  /// [createdAt]/[revision] 显式传旧行值用于「旧行重建」场景（created_at 不随
  /// 修正变化、revision 在旧值上递增）。
  dom.SyncMeta _newMeta({int? createdAt, int? revision}) => dom.SyncMeta(
        createdAt: createdAt ?? _nowMs,
        updatedAt: _nowMs,
        hlc: clock.now().format(),
        revision: revision ?? 1,
        deviceId: clock.deviceId,
      );

  /// 追加一条 corrections 审计行（§5.6⑮ append-only；W2 手动路径 source=user）。
  Future<void> _insertCorrectionAudit({
    required String entryId,
    String? lineId,
    required String field,
    required String oldValue,
    required String newValue,
  }) async {
    await db.into(db.corrections).insert(cdb.Correction(
          id: _newId(),
          entryId: entryId,
          lineId: lineId,
          field: field,
          oldValue: oldValue,
          newValue: newValue,
          source: 'user',
          createdAt: _nowMs,
          updatedAt: _nowMs,
          deletedAt: null,
          hlc: clock.now().format(),
          revision: 1,
          schemaVer: dom.kCurrentSchemaVer,
          deviceId: clock.deviceId,
        ));
  }

  // ── W2 手动记账写路径（§11.1 W2「手动记账 CRUD 全链路（无 AI）」）──

  /// 新记一笔钱：entries(kind=expense) + entry_lines(type=money) 同事务落库
  /// （§5.2 facet 拆行），两行 HLC 均由 HlcClock 签发（§6.3）。
  ///
  /// kind 取 `expense`：§5.2① kind 枚举（food/fitness/expense/mixed/note）
  /// 没有单金额「income」语义，收入方向由行级 direction=in 表达（§5.2②）。
  /// source=manual、status=confirmed（手动路径无 AI 覆盖语义，不走 draft）。
  Future<String> submitMoneyCapture({
    required String date,
    required int tzOffsetMin,
    required String title,
    String? note,
    required int amountMinor,
    required dom.LineDirection direction,
    required String ledgerId,
    String? categoryId,
    String? currency,
    int? occurredAt,
  }) async {
    assert(amountMinor > 0, '金额必须为正数（分）；方向由 direction 表达（§5.2②）');
    // money 行币种：显式传入 > 所选账本 > 默认 CNY（§5.2② currency 行）。
    String? resolvedCurrency = currency;
    if (resolvedCurrency == null) {
      for (final row in await _loadMoneyLedgerRows()) {
        if (row.id == ledgerId) resolvedCurrency = row.currency;
      }
    }
    resolvedCurrency ??= 'CNY';

    final entry = dom.Entry(
      id: _newId(),
      date: date,
      tzOffsetMin: tzOffsetMin,
      occurredAt: occurredAt ?? _nowMs,
      kind: dom.EntryKind.expense,
      source: dom.EntrySource.manual,
      title: title,
      note: note,
      status: dom.EntryStatus.confirmed,
      aiParseId: null,
      meta: _newMeta(),
    );
    final line = dom.EntryLine(
      id: _newId(),
      entryId: entry.id,
      type: dom.LineType.money,
      amount: amountMinor,
      direction: direction,
      ledgerId: ledgerId,
      categoryId: categoryId,
      currency: resolvedCurrency,
      confidence: null, // 人工行无置信度（§5.2② confidence AI 产出行必填）
      payload: null,
      correctionOf: null,
      status: dom.LineStatus.active,
      meta: _newMeta(),
    );
    // 写路径经仓库接口落库（§3.3「提交经 EntryRepository 落库」）；
    // Drift 嵌套事务：内层（仓库自身的 transaction）join 外层事务。
    await db.transaction(() async {
      await entries.upsert(entry);
      await entryLines.upsert(line);
    });
    return entry.id;
  }

  /// 编辑既有记录（§3.4 金额不可变）：主干字段更新 + 金额行走修正链。
  ///
  /// - 主干（date/tz/title/note 变更）：实体重建（status→edited、meta bump、
  ///   created_at 保持）后经 [entries.upsert] 更新（§5.2① edited=含修正）；
  /// - 金额行（amount/direction/category/ledger 变更）：新增 correction 行
  ///   经 [entryLines.supersede] 同事务替换旧行（金额永不原地改，§3.4）；
  /// - 字段级变更落 corrections 审计行（§5.6⑮：主干字段 line_id=NULL）；
  /// - 无真实变更时不产生任何行（修正=新增行仅对变更生效）。
  Future<String> applyMoneyCorrection(CaptureCorrectionRequest request) {
    return db.transaction<String>(() async {
      final oldEntry = await entries.findById(request.entryId);
      if (oldEntry == null) {
        throw StateError('applyMoneyCorrection: entries 无此行 ${request.entryId}');
      }
      if (oldEntry.isDeleted) {
        throw StateError('已删墓碑事件不可修正（§6.5 删除行）');
      }
      final oldLine = await entryLines.findById(request.oldLineId);
      if (oldLine == null || oldLine.entryId != oldEntry.id) {
        throw ArgumentError(
          'correction 目标行 ${request.oldLineId} 不属于事件 ${request.entryId}'
          '（§5.2② entry_id）',
        );
      }
      if (oldLine.type != dom.LineType.money) {
        throw ArgumentError('仅 money 行走金额修正（§3.4）');
      }
      if (oldLine.status != dom.LineStatus.active) {
        throw StateError(
          '仅 active 行可被修正，${oldLine.id} 当前为 ${oldLine.status.wire}'
          '（§5.2② 修正链线性）',
        );
      }
      if (oldLine.isDeleted) {
        throw StateError('已删墓碑行不可修正（§6.5 删除行）');
      }

      final entryChanged = request.date != oldEntry.date ||
          request.tzOffsetMin != oldEntry.tzOffsetMin ||
          request.title != oldEntry.title ||
          (request.note ?? '') != (oldEntry.note ?? '');
      final lineChanged = oldLine.amount != request.amountMinor ||
          oldLine.direction != request.direction ||
          oldLine.categoryId != request.categoryId ||
          oldLine.ledgerId != request.ledgerId;
      if (!entryChanged && !lineChanged) {
        return request.entryId;
      }

      // ① 主干行：实体重建（§5.1 created_at 不变、revision 本地自增）。
      if (entryChanged) {
        final editedEntry = oldEntry.copyWith(
          date: request.date,
          tzOffsetMin: request.tzOffsetMin,
          title: request.title,
          note: request.note,
          status: dom.EntryStatus.edited,
          meta: _newMeta(
            createdAt: oldEntry.meta.createdAt,
            revision: oldEntry.meta.revision + 1,
          ),
        );
        await entries.upsert(editedEntry);

        // ② 主干级审计（§5.6⑮ line_id 可空=主干字段修正）。
        if (oldEntry.date != request.date) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'date',
            oldValue: oldEntry.date,
            newValue: request.date,
          );
        }
        if (oldEntry.tzOffsetMin != request.tzOffsetMin) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'tz_offset_min',
            oldValue: '${oldEntry.tzOffsetMin}',
            newValue: '${request.tzOffsetMin}',
          );
        }
        if (oldEntry.title != request.title) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'title',
            oldValue: oldEntry.title,
            newValue: request.title,
          );
        }
        if ((request.note ?? '') != (oldEntry.note ?? '')) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'note',
            oldValue: oldEntry.note ?? '',
            newValue: request.note ?? '',
          );
        }
      }

      // ③ 金额行修正：新增行 + 旧行 superseded + 行级审计（§3.4/§5.2②）。
      if (lineChanged) {
        final correction = dom.EntryLine(
          id: _newId(),
          entryId: oldEntry.id,
          type: dom.LineType.money,
          amount: request.amountMinor,
          direction: request.direction,
          ledgerId: request.ledgerId,
          categoryId: request.categoryId,
          currency: oldLine.currency, // W2 币种跟随账本、不可变
          confidence: null,
          payload: oldLine.payload,
          correctionOf: request.oldLineId,
          status: dom.LineStatus.active,
          meta: _newMeta(),
        );
        // supersede（core_db 事务）：旧行→superseded、confirmed→edited 联动、
        // 金额不可变守卫（§5.2②/§3.4）。
        await entryLines.supersede(request.oldLineId, correction);

        if (oldLine.amount != request.amountMinor) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'amount',
            oldValue: '${oldLine.amount}',
            newValue: '${request.amountMinor}',
          );
        }
        if (oldLine.direction != request.direction) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'direction',
            oldValue: oldLine.direction.wire,
            newValue: request.direction.wire,
          );
        }
        if (oldLine.categoryId != request.categoryId) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'category',
            oldValue: oldLine.categoryId ?? '',
            newValue: request.categoryId ?? '',
          );
        }
        if (oldLine.ledgerId != request.ledgerId) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'ledger',
            oldValue: oldLine.ledgerId ?? '',
            newValue: request.ledgerId,
          );
        }
      }
      return request.entryId;
    });
  }

  // ── 选项装载（账本/分类/编辑回填，§3.3/§5.4）────────────────────

  /// money 账本列表（未归档、未软删，按 sort 排序；§5.4④）。
  Future<List<CaptureLedgerOption>> loadMoneyLedgers() async {
    final rows = await _loadMoneyLedgerRows();
    return [
      for (final row in rows)
        CaptureLedgerOption(id: row.id, name: row.name, currency: row.currency),
    ];
  }

  Future<List<cdb.Ledger>> _loadMoneyLedgerRows() {
    return (db.select(db.ledgers)
          ..where((t) =>
              t.kind.equals('money') &
              t.isArchived.equals(false) &
              t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
  }

  /// MVP「恒默认账本」（§3.4 单账本 MVP、§5.4④）：缺 money 账本时惰性创建
  /// 一个，保证「记一笔」开箱可用；幂等（已有即直接返回第一条）。空库首次
  /// 打开时 core_db 的 seedDefaultData 已建默认账本，此处是兜底路径。
  Future<CaptureLedgerOption> ensureDefaultLedger() async {
    final existing = await _loadMoneyLedgerRows();
    if (existing.isNotEmpty) {
      final row = existing.first;
      return CaptureLedgerOption(
          id: row.id, name: row.name, currency: row.currency);
    }
    final row = cdb.Ledger(
      id: _newId(),
      name: '默认账本',
      icon: 'wallet',
      currency: 'CNY',
      kind: 'money',
      sort: 0,
      openingBalanceMinor: 0,
      isArchived: false,
      createdAt: _nowMs,
      updatedAt: _nowMs,
      deletedAt: null,
      hlc: clock.now().format(),
      revision: 1,
      schemaVer: dom.kCurrentSchemaVer,
      deviceId: clock.deviceId,
    );
    await db.into(db.ledgers).insert(row);
    return CaptureLedgerOption(id: row.id, name: row.name, currency: row.currency);
  }

  /// 按方向装载分类：expense=out / income=in（§5.4⑤ categories.kind）。
  Future<List<CaptureCategoryOption>> loadCategories(
      dom.LineDirection direction) async {
    final kind = direction == dom.LineDirection.outcome ? 'expense' : 'income';
    final rows = await (db.select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return [
      for (final row in rows)
        CaptureCategoryOption(
          id: row.id,
          name: row.name,
          icon: row.icon,
          colorToken: row.colorToken,
          isPreset: row.isPreset,
        ),
    ];
  }

  /// 编辑模式回填目标：entry + 其 active money 行；不存在/已删/无金额行
  /// 返回 null（调用方退化为新建）。
  Future<CaptureEditTarget?> loadEditTarget(String entryId) async {
    final entryRow =
        await (db.select(db.entries)..where((t) => t.id.equals(entryId)))
            .getSingleOrNull();
    if (entryRow == null || entryRow.deletedAt != null) return null;
    final rows = await (db.select(db.entryLines)
          ..where((t) =>
              t.entryId.equals(entryId) &
              t.type.equals(dom.LineType.money.wire) &
              t.status.equals(dom.LineStatus.active.wire) &
              t.deletedAt.isNull()))
        .get();
    if (rows.isEmpty) return null;
    final line = rows.first;
    return CaptureEditTarget(
      entryId: entryRow.id,
      oldLineId: line.id,
      amountMinor: line.amount,
      direction: dom.LineDirection.fromWire(line.direction),
      categoryId: line.categoryId,
      ledgerId: line.ledgerId,
      currency: line.currency,
      date: entryRow.date,
      tzOffsetMin: entryRow.tzOffsetMin,
      title: entryRow.title,
      note: entryRow.note,
    );
  }
}
