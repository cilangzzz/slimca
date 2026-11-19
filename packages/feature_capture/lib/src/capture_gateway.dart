/// 录入网关：组合 core_db 的仓库实现 + 手动记账/修正闭环（W2）+ AI 双解析
/// 写路径（W3-4）的 feature 层编排（§3.3、§11.1 W2/W3-4、§10.4 分层）。
///
/// 分层边界（§10.4「接口在 core_domain、实现在 core_db」）：持久化语义
/// （软删墓碑、money 行不可变守卫、supersede 事务、day_summary 投影联动）
/// 全部由 core_db 的 `DriftEntryRepository` / `DriftEntryLineRepository`
/// 承担；本库不重复实现仓库，只做 feature 层编排：
/// - W2 手动写路径：entries(kind=expense) + entry_lines(type=money) 的实体
///   构造与同事务落库（§5.2 facet 拆行），HLC 由注入的 [dom.HlcClock]
///   签发（§6.3 定宽编码）；
/// - W2 修正闭环编排：主干字段与金额行的变更分流 + corrections 审计行落库
///   （§5.6⑮ 明确「审计行由调用方落库」，仓库层无从得知字段级前后值）；
/// - W3-4 AI 写路径（§11.1「AI 双解析闭环（文本）」）：确认卡/复记/降级
///   提交 → entries + calorie/money 行 + food_items + ai_parses（留痕与
///   input_hash 缓存，§5.6⑭）+ corrections 差异审计（AI 初值 vs 用户确认，
///   §5.6⑮ source=ai_corrected）同事务落库；
/// - 出网纪律（§6.2 写路径，W5-6 集成披露的补课项）：本网关触达的全部
///   同步真值表写入（entries/entry_lines/food_items/corrections/ledgers）
///   一律经 core_db `SyncOutboxWriter` 在**同一事务内**读回行快照入队
///   sync_outbox（§5.6⑯）——applyMoneyCorrection 修正路径的全量写入集
///   （主干行、旧行 superseded、新修正行、confirmed→edited 联动、审计行）
///   亦同；入队去重由 writer 折叠同 (table,row) 的未 ack 出网行；
/// - 选项装载：money 账本/kcal 账本/按方向过滤分类/分类建议命中/最近记录
///   chips（§2.4）/编辑回填目标。
///
/// 宿主装配（§10.4 壳负责装配）：override [captureGatewayProvider]，其中
/// [dom.HlcClock] 必须是应用级单例（HLC 单调性是全设备唯一全序来源）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_models.dart';
import 'capture_parser.dart';

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
        outbox = cdb.SyncOutboxWriter(database),
        entries = cdb.DriftEntryRepository(database, projection: projection),
        entryLines = cdb.DriftEntryLineRepository(database, projection: projection);

  final cdb.AppDatabase db;

  /// 应用级单例时钟（§6.3）：本网关签发的所有行 HLC 皆源于此。
  final dom.HlcClock clock;

  /// 出网入队器（§5.6⑯/§6.2）：本网关全部真值表写入经它在业务事务内
  /// 读回行快照入队 sync_outbox（W5-6 补课：含 food_items/corrections/
  /// 修正路径/惰性账本）。
  final cdb.SyncOutboxWriter outbox;

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

  /// 追加一条 corrections 审计行（§5.6⑮ append-only）。
  ///
  /// [source]：W2 手动修正链='user'；W3-4「AI 初值 vs 用户确认差异」=
  /// 'ai_corrected'（W3-4 主线任务口径；§5.6⑮ 的 TEXT source 列允许扩展，
  /// 供 P2 校准闭环区分「AI 预填被确认改动」与纯人工修正）。
  /// §6.2 写路径纪律：corrections 为同步真值表，审计行快照同事务入队
  /// sync_outbox（W5-6 补课）。
  Future<void> _insertCorrectionAudit({
    required String entryId,
    String? lineId,
    required String field,
    required String oldValue,
    required String newValue,
    required String source,
  }) async {
    final id = _newId();
    await db.into(db.corrections).insert(cdb.Correction(
          id: id,
          entryId: entryId,
          lineId: lineId,
          field: field,
          oldValue: oldValue,
          newValue: newValue,
          source: source,
          createdAt: _nowMs,
          updatedAt: _nowMs,
          deletedAt: null,
          hlc: clock.now().format(),
          revision: 1,
          schemaVer: dom.kCurrentSchemaVer,
          deviceId: clock.deviceId,
        ));
    await outbox.enqueueRow('corrections', id);
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
    // §6.2 写路径纪律：entries/entry_lines 行快照与业务行同事务入队 outbox
    // （经 SyncOutboxWriter 读回终态，payload 与落库行同源，§5.6⑯）。
    await db.transaction(() async {
      await entries.upsert(entry);
      await entryLines.upsert(line);
      await outbox.enqueueRow('entries', entry.id);
      await outbox.enqueueRow('entry_lines', line.id);
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
  /// - 无真实变更时不产生任何行（修正=新增行仅对变更生效）；
  /// - §6.2 写路径纪律（W5-6 补课）：全部真值表写入（entries 主干、旧行
  ///   superseded、新修正行、审计行）在同一事务内读回终态入队 sync_outbox；
  ///   任一步失败整体回滚，无半途出网项。
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

      // 本次事务内「entries 主干行是否被真实写 over」标记（§6.2：只对真实
      // 发生的真值行写入入队，未变更行不产出冗余出网项）：
      // - entryChanged → 主干 upsert；
      // - 仅 lineChanged 且父事件此前为 confirmed → supersede 的
      //   confirmed→edited 联动写（core_db 仓库事务内）。
      var entryRowWritten = false;

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
        entryRowWritten = true;

        // ② 主干级审计（§5.6⑮ line_id 可空=主干字段修正）。
        if (oldEntry.date != request.date) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'date',
            oldValue: oldEntry.date,
            newValue: request.date,
            source: 'user',
          );
        }
        if (oldEntry.tzOffsetMin != request.tzOffsetMin) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'tz_offset_min',
            oldValue: '${oldEntry.tzOffsetMin}',
            newValue: '${request.tzOffsetMin}',
            source: 'user',
          );
        }
        if (oldEntry.title != request.title) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'title',
            oldValue: oldEntry.title,
            newValue: request.title,
            source: 'user',
          );
        }
        if ((request.note ?? '') != (oldEntry.note ?? '')) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            field: 'note',
            oldValue: oldEntry.note ?? '',
            newValue: request.note ?? '',
            source: 'user',
          );
        }
      }

      // ③ 金额行修正：新增行 + 旧行 superseded + 行级审计（§3.4/§5.2②）。
      if (lineChanged) {
        // 主干此前未被本次修正改写且仍为 confirmed：supersede 会联动写
        // confirmed→edited（core_db 仓库事务内），须入队（§6.2）。
        if (!entryRowWritten && oldEntry.status == dom.EntryStatus.confirmed) {
          entryRowWritten = true;
        }
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
            source: 'user',
          );
        }
        if (oldLine.direction != request.direction) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'direction',
            oldValue: oldLine.direction.wire,
            newValue: request.direction.wire,
            source: 'user',
          );
        }
        if (oldLine.categoryId != request.categoryId) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'category',
            oldValue: oldLine.categoryId ?? '',
            newValue: request.categoryId ?? '',
            source: 'user',
          );
        }
        if (oldLine.ledgerId != request.ledgerId) {
          await _insertCorrectionAudit(
            entryId: oldEntry.id,
            lineId: oldLine.id,
            field: 'ledger',
            oldValue: oldLine.ledgerId ?? '',
            newValue: request.ledgerId,
            source: 'user',
          );
        }

        // §6.2 写路径纪律（W5-6 补课）：supersede 修正链的全部真值行写入
        // 同事务读回终态入队——旧行（status=superseded）与新修正行
        // （correction_of 指向旧行）各一条出网项（§5.6⑯/§5.2②）。
        await outbox.enqueueRow('entry_lines', request.oldLineId);
        await outbox.enqueueRow('entry_lines', correction.id);
      }

      // ④ 主干行快照入队（§6.2）：entryChanged 的 upsert 与 supersede 的
      // confirmed→edited 联动写的是同一行——同 (table,row) 的未 ack 出网项
      // 经 SyncOutboxWriter 去重折叠为一条，payload=读回终态（§5.6⑯）。
      if (entryRowWritten) {
        await outbox.enqueueRow('entries', request.entryId);
      }
      return request.entryId;
    });
  }

  // ── W3-4 AI 双解析写路径（§11.1 W3-4「AI 双解析闭环（文本）」）────

  /// AI 确认卡 / 最近 chip 复记 / 失败降级手填的统一提交路径。
  ///
  /// 同事务落库（§5.2 facet 拆行、§6.2 写路径）：
  /// - entries：kind 由行集合推导（双行=mixed、仅热量=food、仅金额=expense，
  ///   §5.2①；任务口径「expense/meal 相应」中文档枚举无 meal，餐食=food）、
  ///   status=confirmed（用户已在确认卡确认）、source 取请求值
  ///   （text/chip/manual，§5.2①）、ai_parse_id 溯源（§5.2①）；
  /// - entry_lines：calorie 行（amount=kcal、direction=in、归集内置 kcal
  ///   账本，§5.2②）+ money 行（amount=分、direction 请求值、ledger 必填），
  ///   AI 产出行带 confidence（§5.2②「AI 产出行必填」），chip/manual 行
  ///   confidence=null（人工语义）；
  /// - food_items：calorie 行菜品明细逐行落库（§7.3 items[] 映射）；
  /// - corrections：[CaptureAiSubmitRequest.aiInitials] 非空时写「AI 初值 vs
  ///   用户确认」差异审计行（§5.6⑮，source=ai_corrected，append-only）；
  /// - §6.2 写路径纪律：全部真值表行（entries/entry_lines/food_items/
  ///   corrections）同事务读回行快照入队 sync_outbox（§5.6⑯，W5-6 补课补齐
  ///   food_items 与 corrections 两类）；ai_parses 为本地件、永不同步。
  ///
  /// 金额不可变语义自确认起生效：后续修改一律走 W2 [applyMoneyCorrection]
  /// （新增 correction 行，§3.4）。
  Future<String> submitAiCapture(CaptureAiSubmitRequest request) async {
    assert(!request.hasMoney || request.ledgerId != null,
        'money 行必填账本（§5.2② ledger_id）');
    assert(!request.hasCalorie || (request.kcal! >= 0),
        'kcal 非负（§5.2② amount）');
    return db.transaction<String>(() async {
      final kind = request.hasCalorie && request.hasMoney
          ? dom.EntryKind.mixed
          : request.hasCalorie
              ? dom.EntryKind.food
              : dom.EntryKind.expense;
      final entry = dom.Entry(
        id: _newId(),
        date: request.date,
        tzOffsetMin: request.tzOffsetMin,
        occurredAt: _nowMs,
        kind: kind,
        source: request.source,
        title: request.title,
        note: request.note,
        status: dom.EntryStatus.confirmed,
        aiParseId: request.aiParseId,
        meta: _newMeta(),
      );
      await entries.upsert(entry);
      // §6.2 写路径纪律：主干行快照同事务入队（§5.6⑯，读回终态入队）。
      await outbox.enqueueRow('entries', entry.id);

      String? calorieLineId;
      String? moneyLineId;
      if (request.hasCalorie) {
        final kcalLedger = await ensureKcalLedger();
        // 行级明细 payload：菜品数组摘要 + 份量倍率（§5.2② payload「菜品
        // 数组摘要」；菜品全量落 food_items 行，此处为行级快照）。
        final payload = jsonEncode(<String, Object?>{
          'items': [for (final item in request.items) _itemToJson(item)],
          'portion_multiplier': request.portionMultiplier,
        }..removeWhere((k, v) => v == null));
        final line = dom.EntryLine(
          id: _newId(),
          entryId: entry.id,
          type: dom.LineType.calorie,
          amount: request.kcal!,
          direction: dom.LineDirection.income, // calorie=in（§5.2②）
          ledgerId: kcalLedger.id,
          categoryId: request.categoryId,
          currency: null,
          confidence: request.kcalConfidence,
          payload: payload,
          correctionOf: null,
          status: dom.LineStatus.active,
          meta: _newMeta(),
        );
        await entryLines.upsert(line);
        await outbox.enqueueRow('entry_lines', line.id);
        calorieLineId = line.id;
        // food_items 逐菜品（§7.3「items[] → food_items 逐菜品」）。
        // §6.2 写路径纪律（W5-6 补课）：food_items 为同步真值表（§5.2③），
        // 每行同事务读回快照入队 sync_outbox（§5.6⑯）。
        for (final item in request.items) {
          final itemId = _newId();
          await db.into(db.foodItems).insert(cdb.FoodItem(
                id: itemId,
                entryId: entry.id,
                lineId: line.id,
                name: item.name,
                portionG: item.portionG,
                kcal: item.kcal,
                proteinG: item.proteinG,
                carbG: item.carbG,
                fatG: item.fatG,
                refSource: item.refSource,
                refId: item.refId,
                confidence: item.confidence,
                userAdjusted: false,
                createdAt: _nowMs,
                updatedAt: _nowMs,
                deletedAt: null,
                hlc: clock.now().format(),
                revision: 1,
                schemaVer: dom.kCurrentSchemaVer,
                deviceId: clock.deviceId,
              ));
          await outbox.enqueueRow('food_items', itemId);
        }
      }
      if (request.hasMoney) {
        // money 行币种：显式传入 > 所选账本 > 默认 CNY（§5.2② currency 行）。
        var currency = request.currency;
        currency ??= await _ledgerCurrency(request.ledgerId!);
        final line = dom.EntryLine(
          id: _newId(),
          entryId: entry.id,
          type: dom.LineType.money,
          amount: request.amountMinor!,
          direction: request.moneyDirection,
          ledgerId: request.ledgerId,
          categoryId: request.categoryId,
          currency: currency,
          confidence: request.moneyConfidence,
          payload: null,
          correctionOf: null,
          status: dom.LineStatus.active,
          meta: _newMeta(),
        );
        await entryLines.upsert(line);
        await outbox.enqueueRow('entry_lines', line.id);
        moneyLineId = line.id;
      }

      // corrections 差异审计（§5.6⑮）：AI 初值 vs 用户确认，source=ai_corrected。
      // 仅 AI/缓存路径携带初值快照；chip 复记与手动降级无初值、不产审计行。
      // 审计行落库即入队（_insertCorrectionAudit 内，§6.2）。
      final initials = request.aiInitials;
      if (initials != null) {
        if (initials.title != request.title) {
          await _insertCorrectionAudit(
            entryId: entry.id,
            field: 'title',
            oldValue: initials.title,
            newValue: request.title,
            source: 'ai_corrected',
          );
        }
        if (request.hasCalorie &&
            initials.kcal != null &&
            initials.kcal != request.kcal) {
          await _insertCorrectionAudit(
            entryId: entry.id,
            lineId: calorieLineId,
            field: 'kcal',
            oldValue: '${initials.kcal}',
            newValue: '${request.kcal}',
            source: 'ai_corrected',
          );
        }
        if (request.hasMoney &&
            initials.moneyMinor != null &&
            initials.moneyMinor != request.amountMinor) {
          await _insertCorrectionAudit(
            entryId: entry.id,
            lineId: moneyLineId,
            field: 'amount',
            oldValue: '${initials.moneyMinor}',
            newValue: '${request.amountMinor}',
            source: 'ai_corrected',
          );
        }
        if (initials.categoryId != request.categoryId) {
          await _insertCorrectionAudit(
            entryId: entry.id,
            lineId: moneyLineId ?? calorieLineId,
            field: 'category',
            oldValue: initials.categoryId ?? '',
            newValue: request.categoryId ?? '',
            source: 'ai_corrected',
          );
        }
      }
      return entry.id;
    });
  }

  /// 确认卡菜品提交载荷 → food_items 行快照 JSON（payload 摘要用）。
  Map<String, Object?> _itemToJson(CaptureConfirmedItem item) =>
      <String, Object?>{
        'name': item.name,
        'portion_g': item.portionG,
        'kcal': item.kcal,
        'protein_g': item.proteinG,
        'carb_g': item.carbG,
        'fat_g': item.fatG,
        'ref_source': item.refSource,
        'ref_id': item.refId,
        'confidence': item.confidence,
      };

  /// 落一条 ai_parses 留痕行（§5.6⑭），返回行 id（entries.ai_parse_id 溯源）。
  ///
  /// raw_output 存解析结果 JSON（缓存回放键，§3.3「相同输入 7 天内直接复用」）；
  /// raw_input 上云开关默认关=即用即焚，原文不落任何表（§3.3）。
  Future<String> saveAiParse({
    required CaptureParseResult result,
    required String inputHash,
    required String inputKind,
  }) async {
    final id = cdb.generateUuidV7();
    await db.into(db.aiParses).insert(cdb.AiParse(
          id: id,
          inputKind: inputKind,
          inputHash: inputHash,
          provider: result.provider,
          model: result.model,
          rawOutput: jsonEncode(result.toJson()),
          latencyMs: result.latencyMs,
          cost: result.costMicro,
          confidence: result.confidence,
          promptVersion: result.promptVersion,
        ));
    return id;
  }

  /// input_hash 缓存查找（§3.3「相同输入 7 天内直接复用解析结果」、§5.6⑭）。
  ///
  /// 命中条件：同 input_hash + 同 input_kind，且 ai_parses.id（UUIDv7）内嵌
  /// 时间戳距今 <7 天（§5.6⑭「7 天时效判断可由 UUIDv7 id 内嵌时间戳得出，
  /// 故不另设时间列」）。返回命中的行 id 与反序列化结果；坏缓存视同未命中
  /// （§7.4 健壮性）。
  Future<({String parseId, CaptureParseResult result})?> findCachedParse({
    required String inputHash,
    required String inputKind,
    Duration maxAge = const Duration(days: 7),
  }) async {
    final rows = await (db.select(db.aiParses)
          ..where((t) =>
              t.inputHash.equals(inputHash) & t.inputKind.equals(inputKind))
          ..orderBy([(t) => OrderingTerm.desc(t.id)])) // UUIDv7 字典序=时间序
        .get();
    final nowMs = _nowMs;
    for (final row in rows) {
      final tsMs = _uuidV7TimestampMs(row.id);
      if (tsMs == null || nowMs - tsMs > maxAge.inMilliseconds) continue;
      try {
        final json = jsonDecode(row.rawOutput) as Map<String, Object?>;
        return (
          parseId: row.id,
          result: CaptureParseResult.fromJson(json),
        );
      } on FormatException {
        return null; // 坏缓存：视同未命中，重新解析覆盖
      }
    }
    return null;
  }

  /// UUIDv7 id 内嵌时间戳（48 位 unix 毫秒，§5.6⑭ 缓存时效判据）。
  ///
  /// 非法/非 UUIDv7 形态返回 null（不据此判过期）。48 位毫秒在 Dart int
  /// 表示范围内（<2^53），无精度损失。
  static int? _uuidV7TimestampMs(String id) {
    final hex = id.replaceAll('-', '');
    if (hex.length < 12) return null;
    return int.tryParse(hex.substring(0, 12), radix: 16);
  }

  /// category_hint → 内置分类 id（§7.3「命中内置分类；未命中挂『其他』并
  /// 建议新建」）：先按名称精确匹配，未命中回退「其他支出/其他收入」。
  Future<String?> matchCategoryByHint(String? hint,
      {required bool expense}) async {
    if (hint == null || hint.trim().isEmpty) return null;
    final kind = expense ? 'expense' : 'income';
    final rows = await (db.select(db.categories)
          ..where((t) => t.kind.equals(kind) & t.deletedAt.isNull()))
        .get();
    final target = hint.trim();
    for (final row in rows) {
      if (row.name == target) return row.id;
    }
    final fallbackName = expense ? '其他支出' : '其他收入';
    for (final row in rows) {
      if (row.name == fallbackName) return row.id;
    }
    return null;
  }

  /// 内置 kcal 账本（§5.2②「kcal 行归集到内置 kcal 账本」、§5.4④「不可删除
  /// 不可多开」）：seed 保证恰一个，此处兜底惰性创建（幂等）。
  /// §6.2 写路径纪律：ledgers 为同步真值表——惰性创建与行快照入队同事务
  /// 提交（无半途 outbox）；嵌套调用（submitAiCapture 事务内）join 外层事务。
  Future<cdb.Ledger> ensureKcalLedger() async {
    final rows = await (db.select(db.ledgers)
          ..where((t) => t.kind.equals('kcal') & t.deletedAt.isNull()))
        .get();
    if (rows.isNotEmpty) return rows.first;
    final row = cdb.Ledger(
      id: _newId(),
      name: '热量账本',
      icon: 'local_fire_department',
      currency: 'kcal',
      kind: 'kcal',
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
    await db.transaction(() async {
      await db.into(db.ledgers).insert(row);
      await outbox.enqueueRow('ledgers', row.id);
    });
    return row;
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

  /// money 行币种兜底解析（§5.2② currency 行）：取所选账本币种；账本行
  /// 不存在（防御路径）回退 CNY，money 行 currency 永不为空。
  Future<String> _ledgerCurrency(String ledgerId) async {
    final row = await (db.select(db.ledgers)
          ..where((t) => t.id.equals(ledgerId)))
        .getSingleOrNull();
    return row?.currency ?? 'CNY';
  }

  /// MVP「恒默认账本」（§3.4 单账本 MVP、§5.4④）：缺 money 账本时惰性创建
  /// 一个，保证「记一笔」开箱可用；幂等（已有即直接返回第一条）。空库首次
  /// 打开时 core_db 的 seedDefaultData 已建默认账本，此处是兜底路径。
  /// §6.2 写路径纪律：惰性创建与行快照入队同事务（ledgers 为同步真值表，
  /// 无半途 outbox）。
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
    await db.transaction(() async {
      await db.into(db.ledgers).insert(row);
      await outbox.enqueueRow('ledgers', row.id);
    });
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
