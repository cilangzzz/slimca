/// 录入网关全写路径 sync_outbox 覆盖测试（§6.2 写路径纪律 / §5.6⑯；
/// W5-6 集成披露的补课项——W7-8 双设备一致率的写路径基础）。
///
/// 覆盖（feature_capture 名下真值表写路径，每条断言出网行数与 payload
/// 完整性，payload 与落库行读回逐键一致=回放一致性）：
/// 1. W2 手动记账 [CaptureGateway.submitMoneyCapture]：entries+entry_lines
///    双行快照同事务入队；
/// 2. W3-4 AI 双解析 [CaptureGateway.submitAiCapture]：food_items 与
///    corrections 审计行快照同事务入队（W5-6 补课补齐的两类）；
/// 3. W2 修正链 [CaptureGateway.applyMoneyCorrection]（标题+金额）：
///    旧行 superseded/新修正行/主干 edited/审计行全部同事务入队；
/// 4. 修正链（仅金额）：supersede 的 confirmed→edited 联动写同样入队；
/// 5. 无真实变更：不产生任何写、也不入队；
/// 6. 坏 oldLineId：前置校验快速失败、无半途 outbox（§6.2 事务一致性）；
/// 7. kcal 账本懒建：ledgers 行快照同事务入队。
///
/// 运行前提：集成阶段已 `flutter pub get`（内存库经 drift/native 即可用）；
/// 宿主缺 sqlite3 运行库时温和跳过（同 capture_flow_test 策略）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
// BooleanExpressionOperators：`&` 谓词组合是 drift 扩展方法，需显式导入；
// Variable：rawRow 直读原始行快照的绑定参数（§6.2 回放一致性比对用）。
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, Variable;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter_test/flutter_test.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// §6.3 定宽 HLC 编码：13 位毫秒:6 位计数器:12 位 hex。
final RegExp _hlcPattern = RegExp(r'^\d{13}:\d{6}:[0-9A-Fa-f]{12}$');

/// 测试夹具：内存真库 + 注入 HlcClock + 录入网关（无 widget、纯网关层）。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  CaptureGateway? _gateway;

  cdb.AppDatabase get db => _db!;
  CaptureGateway get gateway => _gateway!;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，capture outbox 测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(deviceId: '3F8A12C0B7D4');
    _gateway = createCaptureGateway(db: db, clock: _clock!);
    return true;
  }

  Future<void> close() async {
    await _db?.close();
  }

  /// 按名称取内置分类 id（beforeOpen seed 的内置分类，§5.4⑤）。
  Future<String> presetCategoryId(String name, {required String kind}) async {
    final rows = await (db.select(db.categories)
          ..where((t) => t.name.equals(name) & t.kind.equals(kind)))
        .get();
    return rows.single.id;
  }
}

void main() {
  /// 按目标表过滤出网行（§5.6⑯ target_table）。
  Future<List<cdb.SyncOutboxItem>> rowsFor(cdb.AppDatabase db, String table) async {
    final rows = await db.select(db.syncOutbox).get();
    return rows.where((r) => r.targetTable == table).toList();
  }

  /// 读业务表原始行快照（§5.1 snake_case 平铺，与 payload 同源）。
  Future<Map<String, Object?>?> rawRow(
    cdb.AppDatabase db,
    String table,
    String rowId,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM "$table" WHERE id = ?',
          variables: [Variable.withString(rowId)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// 回放一致性：payload 解码后与业务表原始行逐键一致（§6.2）。
  Future<void> expectPayloadEqualsRow(
    cdb.AppDatabase db,
    cdb.SyncOutboxItem outboxRow,
  ) async {
    final payload = jsonDecode(outboxRow.payload) as Map<String, Object?>;
    expect(payload['id'], outboxRow.rowId, reason: '快照 id 与 row_id 一致');
    final row = await rawRow(db, outboxRow.targetTable, outboxRow.rowId);
    expect(row, isNotNull, reason: '出网行必须指向已落库的业务行（§6.2）');
    expect(
      payload,
      equals(row),
      reason: '${outboxRow.targetTable}/${outboxRow.rowId} '
          'payload 必须与落库行同源（§6.2 行快照回放一致性）',
    );
  }

  /// 全量出网行健康校验：op 枚举合法、HLC 定宽（§6.3）、payload 完整。
  Future<void> expectAllRowsHealthy(cdb.AppDatabase db) async {
    for (final r in await db.select(db.syncOutbox).get()) {
      expect(r.op, anyOf('upsert', 'delete'), reason: '§5.6⑯ op 枚举');
      expect(r.hlc, matches(_hlcPattern), reason: '§6.3 定宽 HLC');
      expect(r.baseRevision, isNotNull, reason: '基线版本随快照');
      expect(r.ackedAt, isNull, reason: '测试内无 ack 路径');
      await expectPayloadEqualsRow(db, r);
    }
  }

  test('W2 手动记账：entries+entry_lines 双行快照同事务入队（§6.2）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final breakfast = await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
    final ledgerOutboxBefore = (await rowsFor(harness.db, 'ledgers')).length;

    final entryId = await harness.gateway.submitMoneyCapture(
      date: '2026-11-10',
      tzOffsetMin: 480,
      title: '早餐',
      amountMinor: 1850,
      direction: dom.LineDirection.outcome,
      ledgerId: ledger.id,
      categoryId: breakfast,
      currency: 'CNY',
    );

    // ensureDefaultLedger 命中 seed（行已存在）→ 懒建不重复入队（§6.2）。
    expect((await rowsFor(harness.db, 'ledgers')).length, ledgerOutboxBefore,
        reason: '账本已存在时懒建不写行、也不入队');
    expect(await rowsFor(harness.db, 'food_items'), isEmpty);
    expect(await rowsFor(harness.db, 'corrections'), isEmpty);

    // 双行各一条出网项（§5.2 facet 拆行，§6.2 同事务入队）。
    final entryRows = await rowsFor(harness.db, 'entries');
    final lineRows = await rowsFor(harness.db, 'entry_lines');
    expect(entryRows, hasLength(1));
    expect(lineRows, hasLength(1));
    expect(entryRows.single.rowId, entryId);
    expect(entryRows.single.op, 'upsert');

    final entryPayload =
        jsonDecode(entryRows.single.payload) as Map<String, Object?>;
    expect(entryPayload['kind'], 'expense', reason: '§5.2① kind 枚举');
    expect(entryPayload['source'], 'manual');
    expect(entryPayload['status'], 'confirmed');
    expect(entryPayload['title'], '早餐');
    expect(entryPayload['date'], '2026-11-10');
    expect(entryPayload['device_id'], '3F8A12C0B7D4');

    final linePayload =
        jsonDecode(lineRows.single.payload) as Map<String, Object?>;
    expect(linePayload['entry_id'], entryId, reason: '§5.2② entry_id');
    expect(linePayload['type'], 'money');
    expect(linePayload['amount'], 1850, reason: '§5.1 金额整数分');
    expect(linePayload['direction'], 'out');
    expect(linePayload['ledger_id'], ledger.id);
    expect(linePayload['category_id'], breakfast);
    expect(linePayload['currency'], 'CNY');
    expect(linePayload['status'], 'active');
    expect(linePayload['correction_of'], isNull);

    await expectAllRowsHealthy(harness.db);
  });

  test('W3-4 AI 双解析：food_items 与 corrections 审计行快照同事务入队'
      '（W5-6 补课补齐的两类，§5.2③/§5.6⑮/§6.2）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final zhengcan = await harness.presetCategoryId('餐饮-正餐', kind: 'expense');

    final entryId = await harness.gateway.submitAiCapture(
      CaptureAiSubmitRequest(
        date: '2026-11-10',
        tzOffsetMin: 480,
        title: '牛肉面加蛋',
        source: dom.EntrySource.text,
        aiParseId: 'parse-x', // 逻辑引用 ai_parses（本地件、永不同步 §5.6⑭）
        kcal: 600,
        kcalConfidence: 0.7,
        moneyConfidence: 0.9,
        items: [
          const CaptureConfirmedItem(
            name: '牛肉拉面',
            portionG: 450,
            kcal: 400,
            confidence: 0.6,
            proteinG: 20,
            carbG: 55,
            fatG: 10,
          ),
          const CaptureConfirmedItem(
            name: '卤蛋',
            portionG: 60,
            kcal: 200,
            confidence: 0.55,
          ),
        ],
        portionMultiplier: 1.5,
        amountMinor: 2000,
        moneyDirection: dom.LineDirection.outcome,
        ledgerId: ledger.id,
        categoryId: zhengcan,
        currency: 'CNY',
        aiInitials: CaptureAiInitials(
          title: '兰州拉面',
          kcal: 550,
          kcalConfidence: 0.62,
          moneyMinor: 1800,
          moneyConfidence: 0.93,
          categoryId: zhengcan, // 与确认一致 → 不产 category 审计
        ),
      ),
    );

    // 出网行数：entries 1 + entry_lines 2 + food_items 2 + corrections 3。
    final entryRows = await rowsFor(harness.db, 'entries');
    final lineRows = await rowsFor(harness.db, 'entry_lines');
    final foodRows = await rowsFor(harness.db, 'food_items');
    final auditRows = await rowsFor(harness.db, 'corrections');
    expect(entryRows, hasLength(1));
    expect(lineRows, hasLength(2), reason: 'calorie+money 双行各一条');
    expect(foodRows, hasLength(2), reason: '§7.3 items[] → food_items 逐菜品');
    expect(auditRows, hasLength(3), reason: 'title/kcal/amount 三处差异审计');

    // 主干行快照（§5.2①）。
    final entryPayload = jsonDecode(entryRows.single.payload)
        as Map<String, Object?>;
    expect(entryPayload['kind'], 'mixed', reason: '双行=mixed（§5.2①）');
    expect(entryPayload['source'], 'text');
    expect(entryPayload['status'], 'confirmed');
    expect(entryPayload['title'], '牛肉面加蛋');
    expect(entryPayload['ai_parse_id'], 'parse-x', reason: '§5.2① ai_parse_id');
    expect(entryRows.single.rowId, entryId);

    // 行快照与行级 payload 摘要（§5.2② payload「菜品数组摘要」）。
    final lines = await (harness.db.select(harness.db.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get();
    final kcalLine = lines.singleWhere((l) => l.type == 'calorie');
    final moneyLine = lines.singleWhere((l) => l.type == 'money');
    final kcalRow =
        lineRows.singleWhere((r) => r.rowId == kcalLine.id);
    final moneyRow =
        lineRows.singleWhere((r) => r.rowId == moneyLine.id);
    final kcalPayload = jsonDecode(kcalRow.payload) as Map<String, Object?>;
    final moneyPayload = jsonDecode(moneyRow.payload) as Map<String, Object?>;
    expect(kcalPayload['amount'], 600);
    expect(kcalPayload['direction'], 'in', reason: '§5.2② calorie=in');
    expect(kcalPayload['ledger_id'], (await harness.gateway.ensureKcalLedger()).id,
        reason: 'kcal 行归集内置 kcal 账本（§5.2②）');
    expect(moneyPayload['amount'], 2000, reason: '§5.1 金额整数分');
    expect(moneyPayload['currency'], 'CNY');
    expect(moneyPayload['payload'], isNull, reason: 'money 行无明细摘要');
    final lineDetail = jsonDecode(kcalPayload['payload']! as String)
        as Map<String, Object?>;
    expect(lineDetail['portion_multiplier'], 1.5);
    final detailItems = lineDetail['items']! as List<Object?>;
    expect(detailItems, hasLength(2), reason: '菜品数组摘要随行快照');

    // food_items 快照（§5.2③）：逐菜品完整、业务键齐全。
    final foods = await harness.db.select(harness.db.foodItems).get();
    final egg = foods.singleWhere((f) => f.name == '卤蛋');
    final eggOutbox = foodRows.singleWhere((r) => r.rowId == egg.id);
    final eggPayload = jsonDecode(eggOutbox.payload) as Map<String, Object?>;
    expect(eggPayload['entry_id'], entryId);
    expect(eggPayload['line_id'], kcalLine.id, reason: '§5.2③ line_id 溯源');
    expect(eggPayload['kcal'], 200);
    expect(eggPayload['portion_g'], 60);
    expect(eggPayload['ref_source'], 'local');
    expect(eggOutbox.op, 'upsert');

    // corrections 快照（§5.6⑮ append-only，source=ai_corrected）。
    final audits = await harness.db.select(harness.db.corrections).get();
    final titleAudit = audits.singleWhere((a) => a.field == 'title');
    final kcalAudit = audits.singleWhere((a) => a.field == 'kcal');
    final amountAudit = audits.singleWhere((a) => a.field == 'amount');
    expect(titleAudit.oldValue, '兰州拉面');
    expect(titleAudit.newValue, '牛肉面加蛋');
    expect(titleAudit.lineId, isNull, reason: '主干字段审计 line_id=NULL');
    expect(kcalAudit.oldValue, '550');
    expect(kcalAudit.newValue, '600');
    expect(kcalAudit.lineId, kcalLine.id);
    expect(amountAudit.oldValue, '1800');
    expect(amountAudit.newValue, '2000');
    expect(amountAudit.lineId, moneyLine.id);
    for (final audit in audits) {
      final outboxAudit =
          auditRows.singleWhere((r) => r.rowId == audit.id);
      final auditPayload =
          jsonDecode(outboxAudit.payload) as Map<String, Object?>;
      expect(auditPayload['source'], 'ai_corrected', reason: '§5.6⑮ W3-4 口径');
      expect(outboxAudit.op, 'upsert');
    }

    // ai_parses 为本地件（§5.6⑭）：永不出网——全集恰为 seed 的
    // ledgers/categories + 本流的 4 类真值行。
    final targets = (await harness.db.select(harness.db.syncOutbox).get())
        .map((r) => r.targetTable)
        .toSet();
    expect(targets, {'entries', 'entry_lines', 'food_items', 'corrections',
      'ledgers', 'categories'}, reason: 'seed 账本/分类 + 本流真值行');

    await expectAllRowsHealthy(harness.db);
  });

  test('W2 修正链（标题+金额）：旧行 superseded/新修正行/主干 edited/审计行 '
      '全部同事务入队（§3.4 金额不可变 / §6.2）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final breakfast = await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
    final entryId = await harness.gateway.submitMoneyCapture(
      date: '2026-11-10',
      tzOffsetMin: 480,
      title: '早餐',
      amountMinor: 1850,
      direction: dom.LineDirection.outcome,
      ledgerId: ledger.id,
      categoryId: breakfast,
      currency: 'CNY',
    );
    final oldLine = (await (harness.db.select(harness.db.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get()).single;
    // 修正前基线：entries 1 + entry_lines 1（submit 已入队）。
    expect((await rowsFor(harness.db, 'entries')), hasLength(1));
    expect((await rowsFor(harness.db, 'entry_lines')), hasLength(1));

    await harness.gateway.applyMoneyCorrection(CaptureCorrectionRequest(
      entryId: entryId,
      oldLineId: oldLine.id,
      amountMinor: 2000,
      direction: dom.LineDirection.outcome,
      categoryId: breakfast,
      ledgerId: ledger.id,
      title: '早餐加蛋',
      note: null,
      date: '2026-11-10',
      tzOffsetMin: 480,
    ));

    // 主干：1 条出网项（upsert 读回终态 status=edited）。
    final entryRows = await rowsFor(harness.db, 'entries');
    expect(entryRows, hasLength(1), reason: '主干只有一次读回终态入队（§6.2）');
    final entryPayload =
        jsonDecode(entryRows.single.payload) as Map<String, Object?>;
    expect(entryPayload['title'], '早餐加蛋');
    expect(entryPayload['status'], 'edited', reason: '§5.2① edited=含修正');

    // 修正行（§5.2②）：旧行快照收敛为 superseded、新行 correction_of 指向旧行。
    // 旧行在 submit 时已入队且未 ack（pending）——修正重写同一 (table,row)
    // 的出网项，折叠收敛为一条最终态（§6.2 入队去重语义）。
    final lineRows = await rowsFor(harness.db, 'entry_lines');
    expect(lineRows, hasLength(2), reason: '旧行 1 条（收敛）+ 新修正行 1 条');
    final oldOutbox =
        lineRows.singleWhere((r) => r.rowId == oldLine.id);
    final oldPayload = jsonDecode(oldOutbox.payload) as Map<String, Object?>;
    expect(oldPayload['status'], 'superseded', reason: '§5.2② 旧行 status');
    expect(oldPayload['amount'], 1850, reason: '旧行金额原样保留（§3.4）');
    expect(oldPayload['revision'], 2, reason: '旧行 revision 本地自增');
    final newLine = (await harness.db.select(harness.db.entryLines).get())
        .singleWhere((l) => l.correctionOf == oldLine.id);
    final newOutbox =
        lineRows.singleWhere((r) => r.rowId == newLine.id);
    final newPayload = jsonDecode(newOutbox.payload) as Map<String, Object?>;
    expect(newPayload['correction_of'], oldLine.id, reason: '§5.2② correction_of');
    expect(newPayload['amount'], 2000);
    expect(newPayload['status'], 'active');

    // 审计行（§5.6⑮）：title（主干级）+ amount（行级）各一条。
    final auditRows = await rowsFor(harness.db, 'corrections');
    expect(auditRows, hasLength(2));
    final audits = await harness.db.select(harness.db.corrections).get();
    final titleAudit = audits.singleWhere((a) => a.field == 'title');
    final amountAudit = audits.singleWhere((a) => a.field == 'amount');
    expect(titleAudit.lineId, isNull);
    expect(titleAudit.source, 'user', reason: 'W2 手动修正链=user（§5.6⑮）');
    expect(amountAudit.lineId, oldLine.id);
    expect(amountAudit.oldValue, '1850');
    expect(amountAudit.newValue, '2000');

    await expectAllRowsHealthy(harness.db);
  });

  test('W2 修正链（仅金额）：supersede 的 confirmed→edited 联动写同样入队'
      '（§6.2 只对真实发生的真值行写入入队）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final breakfast = await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
    final entryId = await harness.gateway.submitMoneyCapture(
      date: '2026-11-10',
      tzOffsetMin: 480,
      title: '早餐',
      amountMinor: 1850,
      direction: dom.LineDirection.outcome,
      ledgerId: ledger.id,
      categoryId: breakfast,
      currency: 'CNY',
    );
    final oldLine = (await (harness.db.select(harness.db.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get()).single;

    // 仅改金额：主干字段未变，但 confirmed→edited 联动写是真实写入 → 入队。
    await harness.gateway.applyMoneyCorrection(CaptureCorrectionRequest(
      entryId: entryId,
      oldLineId: oldLine.id,
      amountMinor: 2000,
      direction: dom.LineDirection.outcome,
      categoryId: breakfast,
      ledgerId: ledger.id,
      title: '早餐', // 与原值一致
      note: null,
      date: '2026-11-10',
      tzOffsetMin: 480,
    ));

    final entryRows = await rowsFor(harness.db, 'entries');
    expect(entryRows, hasLength(1), reason: '联动写同事务读回入队（§6.2）');
    final entryPayload =
        jsonDecode(entryRows.single.payload) as Map<String, Object?>;
    expect(entryPayload['status'], 'edited', reason: 'confirmed→edited 联动');
    expect(entryPayload['title'], '早餐');

    final lineRows = await rowsFor(harness.db, 'entry_lines');
    expect(lineRows, hasLength(2));
    final oldPayload =
        jsonDecode(lineRows.singleWhere((r) => r.rowId == oldLine.id).payload)
            as Map<String, Object?>;
    expect(oldPayload['status'], 'superseded');

    // 仅金额一处变更 → 恰一条审计行（§5.6⑮ 字段级）。
    final auditRows = await rowsFor(harness.db, 'corrections');
    expect(auditRows, hasLength(1));
    final auditPayload =
        jsonDecode(auditRows.single.payload) as Map<String, Object?>;
    expect(auditPayload['field'], 'amount');
    expect(auditPayload['source'], 'user');

    await expectAllRowsHealthy(harness.db);
  });

  test('无真实变更：不产生任何写、也不入队（§6.2 只对真实写入入队）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final breakfast = await harness.presetCategoryId('餐饮-早餐', kind: 'expense');
    final entryId = await harness.gateway.submitMoneyCapture(
      date: '2026-11-10',
      tzOffsetMin: 480,
      title: '早餐',
      amountMinor: 1850,
      direction: dom.LineDirection.outcome,
      ledgerId: ledger.id,
      categoryId: breakfast,
      currency: 'CNY',
    );
    final oldLine = (await (harness.db.select(harness.db.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get()).single;
    final outboxBefore = (await harness.db.select(harness.db.syncOutbox).get())
        .map((r) => '${r.targetTable}/${r.rowId}')
        .toSet();

    await harness.gateway.applyMoneyCorrection(CaptureCorrectionRequest(
      entryId: entryId,
      oldLineId: oldLine.id,
      amountMinor: 1850, // 与原值一致
      direction: dom.LineDirection.outcome,
      categoryId: breakfast,
      ledgerId: ledger.id,
      title: '早餐',
      note: null,
      date: '2026-11-10',
      tzOffsetMin: 480,
    ));

    final outboxAfter = (await harness.db.select(harness.db.syncOutbox).get())
        .map((r) => '${r.targetTable}/${r.rowId}')
        .toSet();
    expect(outboxAfter, outboxBefore, reason: 'no-op 修正不产出网项（§6.2）');
  });

  test('坏 oldLineId：前置校验快速失败、无半途 outbox（§6.2 事务一致性）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    final ledger = await harness.gateway.ensureDefaultLedger();
    final entryId = await harness.gateway.submitMoneyCapture(
      date: '2026-11-10',
      tzOffsetMin: 480,
      title: '早餐',
      amountMinor: 1850,
      direction: dom.LineDirection.outcome,
      ledgerId: ledger.id,
      currency: 'CNY',
    );
    final outboxBefore = (await harness.db.select(harness.db.syncOutbox).get())
        .map((r) => '${r.targetTable}/${r.rowId}')
        .toSet();

    await expectLater(
      harness.gateway.applyMoneyCorrection(CaptureCorrectionRequest(
        entryId: entryId,
        oldLineId: 'ghost-line',
        amountMinor: 2000,
        direction: dom.LineDirection.outcome,
        categoryId: null,
        ledgerId: ledger.id,
        title: '早餐',
        note: null,
        date: '2026-11-10',
        tzOffsetMin: 480,
      )),
      throwsArgumentError,
      reason: '修正目标行不存在 → ArgumentError（§5.2②）',
    );

    // 前置校验失败：无任何业务写入、出网行集合原样（§6.2 无半途）。
    final outboxAfter = (await harness.db.select(harness.db.syncOutbox).get())
        .map((r) => '${r.targetTable}/${r.rowId}')
        .toSet();
    expect(outboxAfter, outboxBefore);
    expect(await harness.db.select(harness.db.entryLines).get(), hasLength(1));
  });

  test('kcal 账本懒建：ledgers 行快照同事务入队（§6.2）', () async {
    final harness = _Harness();
    if (!await harness.init()) return;
    addTearDown(harness.close);
    // 物理删除 seed 的 kcal 账本（entry_lines.ledger_id 仅逻辑引用，无外键
    // 约束 §5.2②），触发网关兜底惰性创建。
    // W7-8 集成注：beforeOpen seed 会把 seed 账本行快照同事务入队（§6.2
    // 全写路径补课）——seed 行被物理删除后其出网快照成为「指空」孤儿，
    // expectAllRowsHealthy 的回放一致性校验必然失败。物理删除前先取行 id，
    // 同步清掉对应出网快照，保持「出网行 ⇔ 落库行」的测试前提。
    final seedKcal = await (harness.db.select(harness.db.ledgers)
          ..where((t) => t.kind.equals('kcal')))
        .get();
    await (harness.db.delete(harness.db.ledgers)
          ..where((t) => t.kind.equals('kcal')))
        .go();
    for (final removed in seedKcal) {
      await (harness.db.delete(harness.db.syncOutbox)
            ..where((t) =>
                t.targetTable.equals('ledgers') & t.rowId.equals(removed.id)))
          .go();
    }
    final ledgerOutboxBefore = (await rowsFor(harness.db, 'ledgers')).length;

    final ledger = await harness.gateway.ensureKcalLedger();
    expect(ledger.kind, 'kcal');
    expect(ledger.currency, 'kcal');

    final ledgerRows = await rowsFor(harness.db, 'ledgers');
    expect(ledgerRows.length, ledgerOutboxBefore + 1, reason: '懒建同事务入队');
    final lazyRow =
        ledgerRows.singleWhere((r) => r.rowId == ledger.id);
    expect(lazyRow.op, 'upsert');
    final payload = jsonDecode(lazyRow.payload) as Map<String, Object?>;
    expect(payload['name'], '热量账本');
    expect(payload['currency'], 'kcal');
    expect(payload['kind'], 'kcal');

    await expectAllRowsHealthy(harness.db);
  });
}
