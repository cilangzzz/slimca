// W3-4 AI 录入管线单测（§11.1 W3-4 任务项 2/3：capture gateway 组合 parser、
// input_hash 缓存注入、corrections 落库路径打通）。
//
// 测试纪律（任务硬规则）：一律注入 Fake/Throwing 解析器，禁止真实网络调用；
// 库为内存真库（Drift NativeDatabase.memory，走真实 schema/迁移/种子链路）。
// Windows 宿主缺 sqlite3 运行库时温和跳过（与 app 冒烟/core_db 同策略）。

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/ai_parser.dart';
import 'package:slimca/ai/fake_parser.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/data/ai_capture_service.dart';
import 'package:slimca/data/ai_parse_cache.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 core_db test_support 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

Future<db.AppDatabase?> _tryOpenMemoryDatabase() async {
  final database = db.AppDatabase(
    DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
  );
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    if (_isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 恒抛解析失败的注入桩（§7.4 失败降级路径）。
class ThrowingParser implements AiParser {
  const ThrowingParser();

  @override
  Future<AiParseResult> parse(AiParseRequest request) async {
    throw const AiParserException('模拟超时（§7.4 文本 5s）');
  }
}

AiCaptureService _buildService(
  db.AppDatabase database, {
  AiParser parser = const FakeParser(),
}) =>
    AiCaptureService(
      db: database,
      entries: db.DriftEntryRepository(database),
      lines: db.DriftEntryLineRepository(database),
      clock: HlcClock(deviceId: 'ABCDEF123456'),
      parser: parser,
      cache: AiParseCache(database),
    );

void main() {
  late db.AppDatabase? maybeDb;

  setUp(() async {
    final database = await _tryOpenMemoryDatabase();
    maybeDb = database;
    if (database != null) {
      // 内置账本种子（§5.4）：确认落库的 ledgerId 依赖 money/kcal 内置账本。
      await ensureDefaultLedgers(database, HlcClock(deviceId: 'ABCDEF123456'));
    }
  });

  tearDown(() async {
    await maybeDb?.close();
    maybeDb = null;
  });

  test('UUIDv7 内嵌时间戳可解（7 天时效判定依据，§5.6⑭）', () {
    const stampMs = 1700000000000;
    final id = db.generateUuidV7(timestampMs: stampMs);
    expect(uuidV7TimestampMs(id), stampMs);
    expect(uuidV7TimestampMs('not-a-uuid'), isNull);
  });

  test('解析留痕 + 规范化同 hash + 7 天缓存命中复用 raw_output（§7.1）',
      () async {
    final database = maybeDb!;
    final service = _buildService(database);

    final d1 = await service.parseToDraft('午餐 500kcal 花了18');
    expect(d1.fromCache, isFalse);
    expect(d1.result.firstKcalLine?.amount, 500);
    expect(d1.result.firstMoneyLine?.amount, 1800);
    expect(d1.inputHash, aiInputHash(normalizeAiInput('午餐 500kcal 花了18')));

    // 同输入（多打空格规范化后同 hash）→ 命中复用（§7.1 命中率 ≥15% P0）。
    final d2 = await service.parseToDraft('午餐  500kcal  花了18 ');
    expect(d2.fromCache, isTrue);
    expect(d2.parseId, d1.parseId);
    expect(d2.result.firstKcalLine?.amount, 500);

    final rows = await database.select(database.aiParses).get();
    expect(rows, hasLength(1), reason: '命中不重复留痕（§5.6⑭）');
    expect(rows.single.inputKind, 'text');
    expect(rows.single.inputHash, d1.inputHash);
    expect(rows.single.provider, 'fake');
    // raw_output=canonical JSON，可回放解回同构结果（§5.6⑭ 可回放排查）。
    final replay = AiParseResult.tryDecode(rows.single.rawOutput);
    expect(replay, isNotNull);
    expect(replay!.firstKcalLine?.amount, 500);
    expect(replay.firstMoneyLine?.amount, 1800);
  });

  test('缓存过期（>7 天）→ 未命中重解析并新增留痕（§7.1 7 天窗口）', () async {
    final database = maybeDb!;
    final service = _buildService(database);
    final hash = aiInputHash(normalizeAiInput('过期输入 100kcal'));

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final day = 24 * 3600 * 1000;
    // 8 天前旧行（id 内嵌时间戳=8 天前，§5.6⑭ 时效判定）。
    await database.into(database.aiParses).insert(
          db.AiParse(
            id: db.generateUuidV7(timestampMs: nowMs - 8 * day),
            inputKind: 'text',
            inputHash: hash,
            provider: 'fake',
            model: 'old-model',
            rawOutput: jsonEncode(<String, Object?>{
              'title': '过期输入 100kcal',
              'kind': 'food',
              'lines': <Object?>[
                <String, Object?>{
                  'type': 'calorie',
                  'amount': 100,
                  'confidence': 0.9,
                },
              ],
              'confidence': 0.9,
              'provider': 'fake',
              'model': 'old-model',
              'prompt_version': 'fake-v1',
              'latency_ms': 0,
              'cost_micro': 0,
            }),
            latencyMs: 0,
            cost: 0,
            confidence: 0.9,
            promptVersion: 'fake-v1',
          ),
        );

    final draft = await service.parseToDraft('过期输入 100kcal');
    expect(draft.fromCache, isFalse, reason: '超 7 天窗口必须重解析（§7.1）');

    final rows = await database.select(database.aiParses).get();
    expect(rows, hasLength(2), reason: '过期行保留（溯源），新增新留痕行');
  });

  test('确认落库全链路：entries+facet 行（AI 带 confidence）+corrections 审计'
      '（§5.2/§5.6⑮/§7.3）', () async {
    final database = maybeDb!;
    final service = _buildService(database);

    final draft = await service.parseToDraft('午餐 500kcal 花了18');
    final entryId = await service.confirmAiCapture(
      AiConfirmInput(
        draft: draft,
        date: '2026-11-16',
        tzOffsetMin: 480,
        confirmedTitle: draft.result.title, // 标题未改 → 不落 title 审计
        confirmedKcal: 600, // 用户修正 500→600（确认卡可编辑 §3.3）
        confirmedAmountMinor: 1800, // 金额未改 → 不写 amount 审计
      ),
    );

    // 主干（§5.2①）：source=text（AI 文本通道）、confirmed、ai_parse_id 溯源。
    final entry =
        await (database.select(database.entries)
              ..where((t) => t.id.equals(entryId)))
            .getSingle();
    expect(entry.kind, 'mixed', reason: '热量+金额 → mixed（§5.2①）');
    expect(entry.source, 'text');
    expect(entry.status, 'confirmed');
    expect(entry.aiParseId, draft.parseId, reason: '§5.2① ai_parse_id→ai_parses');
    expect(entry.title, draft.result.title);

    // facet 行（§5.2②/§5.3）：AI 产出行必带 confidence。
    final lines = await (database.select(database.entryLines)
          ..where((t) => t.entryId.equals(entryId)))
        .get();
    final kcalLines = lines.where((l) => l.type == 'calorie').toList();
    final moneyLines = lines.where((l) => l.type == 'money').toList();
    expect(kcalLines, hasLength(1));
    expect(kcalLines.single.amount, 600);
    expect(kcalLines.single.direction, 'in');
    expect(kcalLines.single.confidence, 0.62, reason: 'FakeParser 确定性置信度');
    expect(moneyLines, hasLength(1));
    expect(moneyLines.single.amount, 1800);
    expect(moneyLines.single.confidence, 0.93);
    expect(moneyLines.single.currency, 'CNY');

    // corrections 审计（§5.6⑮）：仅 kcal 一处修正 → 一行，字段级 old/new。
    final corrections = await database.select(database.corrections).get();
    expect(corrections, hasLength(1), reason: '只修正了 kcal（§5.6⑮ append-only）');
    final audit = corrections.single;
    expect(audit.entryId, entryId);
    expect(audit.lineId, kcalLines.single.id, reason: '行级修正挂 line_id');
    expect(audit.field, 'kcal');
    expect(audit.oldValue, '500');
    expect(audit.newValue, '600');
    expect(audit.source, 'user');
  });

  test('确认卡未改动 → 零 corrections 行；改标题 → 主干审计 line_id=NULL',
      () async {
    final database = maybeDb!;
    final service = _buildService(database);

    final draft = await service.parseToDraft('咖啡 200kcal');
    final entryIdA = await service.confirmAiCapture(AiConfirmInput(
      draft: draft,
      date: '2026-11-16',
      tzOffsetMin: 480,
      confirmedTitle: draft.result.title, // 未改
      confirmedKcal: 200, // 未改
    ));
    expect(
      await database.select(database.corrections).get(),
      isEmpty,
      reason: '确认 ≠ 修正：未改动不落审计（§5.6⑮）',
    );

    final entryIdB = await service.confirmAiCapture(AiConfirmInput(
      draft: draft,
      date: '2026-11-16',
      tzOffsetMin: 480,
      confirmedTitle: '黑咖啡', // 改标题 → 主干审计（§5.6⑮ line_id 可空）
      confirmedKcal: 200,
    ));
    final corrections = await database.select(database.corrections).get();
    expect(corrections, hasLength(1));
    expect(corrections.single.entryId, entryIdB);
    expect(corrections.single.lineId, isNull);
    expect(corrections.single.field, 'title');
    expect(corrections.single.oldValue, draft.result.title);
    expect(corrections.single.newValue, '黑咖啡');
    expect(entryIdA, isNot(entryIdB));
  });

  test('解析失败 → AiParserException 原样上抛、无留痕（§2.4#3/§7.4 降级口）',
      () async {
    final database = maybeDb!;
    final service = _buildService(database, parser: const ThrowingParser());

    await expectLater(
      service.parseToDraft('任何输入'),
      throwsA(isA<AiParserException>()),
    );
    expect(
      await database.select(database.aiParses).get(),
      isEmpty,
      reason: '失败不留痕：确认前无半成品数据（§7.4 降级）',
    );
    expect(
      await database.select(database.entries).get(),
      isEmpty,
      reason: '降级路径不落库——原输入保留由 UI 层承接（§2.4#3）',
    );
  });

  test('空输入 → AiParserException（§7.1 规范化后无有效内容）', () async {
    final service = _buildService(maybeDb!);
    await expectLater(
      service.parseToDraft('   '),
      throwsA(isA<AiParserException>()),
    );
  });
}
