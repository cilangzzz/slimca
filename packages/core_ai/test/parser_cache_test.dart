/// input_hash 缓存测试（§5.6⑭ ai_parses、§7.1 缓存命中 <7 天回放）。
///
/// 覆盖：命中直接回放（不调 LLM）、过期（7 天时效 + UUIDv7 id 内嵌时间）、
/// prompt_version 闸门、单边模式键隔离、损坏缓存行回退实时管线、hash 口径
/// 单测，以及 DriftAiParseCache 落库实现（宿主缺 sqlite3 运行库时温和跳过）。
library;

import 'dart:math';

import 'package:core_ai/core_ai.dart';
import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

LlmAiParser makeParser(List<Object> script, AiParseCache cache,
    {int Function()? nowMs}) {
  final adapter = FakeLlmAdapter.scripted(script);
  return LlmAiParser(
    adapter: adapter,
    cache: cache,
    nowMs: nowMs ?? fakeNowMs,
    newParseId: makeIdSeq(),
  );
}

/// 造一条指定内嵌时间的留痕记录（缓存预置用）。
AiParseRecord makeRecord({
  required String inputHash,
  required int timestampMs,
  String promptVersion = kPromptVersion,
  String rawOutput = kLanzhouParseJson,
  double confidence = 0.62,
}) {
  final id = cdb.generateUuidV7(timestampMs: timestampMs, random: Random(7));
  return AiParseRecord(
    id: id,
    inputKind: 'text',
    inputHash: inputHash,
    provider: 'fake',
    model: 'fake-model',
    rawOutput: rawOutput,
    latencyMs: 42,
    costMicro: 7,
    confidence: confidence,
    promptVersion: promptVersion,
  );
}

void main() {
  group('input_hash 口径（§7.1 sha256(规范化输入)、§5.6⑭ 缓存键）', () {
    test('同一输入规范化后 hash 稳定（多空格/换行不破缓存）', () {
      final a = computeInputHash(
          normalizeParseInput('中午吃了兰州拉面花了 18'), ParseMode.both);
      final b = computeInputHash(
          normalizeParseInput(' 中午吃了兰州拉面花了\n18　 '), ParseMode.both);
      expect(a, b);
      expect(a, hasLength(64), reason: 'sha256 hex');
    });

    test('单边模式参与哈希（同文本不同模式不串缓存，§3.3）', () {
      final both = computeInputHash('咖啡 18', ParseMode.both);
      final money = computeInputHash('咖啡 18', ParseMode.moneyOnly);
      final kcal = computeInputHash('咖啡 18', ParseMode.kcalOnly);
      expect(money, isNot(both));
      expect(kcal, isNot(both));
      expect(kcal, isNot(money));
    });

    test('规范化实现：全角空格与连续空白折叠', () {
      expect(normalizeParseInput('  a　 b\n\tc  '), 'a b c');
      expect(normalizeParseInput('　　'), '', reason: '纯空白 → 空（入口拦截）');
    });
  });

  group('UUIDv7 内嵌时间（§5.6⑭：7 天时效由 id 判定，不另设时间列）', () {
    test('core_db generateUuidV7 的时间戳可被提取还原', () {
      const ts = 1763251200000;
      final id = cdb.generateUuidV7(timestampMs: ts, random: Random(7));
      expect(uuidV7TimestampMs(id), ts);
    });

    test('不同时间戳生成不同 id 且时间有序（字典序=时间序，§5.1）', () {
      final a = cdb.generateUuidV7(timestampMs: 1000, random: Random(1));
      final b = cdb.generateUuidV7(timestampMs: 2000, random: Random(1));
      expect(uuidV7TimestampMs(a), 1000);
      expect(uuidV7TimestampMs(b), 2000);
      expect(a.compareTo(b), isNegative);
    });

    test('非 v7 布局抛 FormatException（坏 id 不静默降级）', () {
      expect(() => uuidV7TimestampMs('not-a-uuid'), throwsFormatException);
      // RFC 4122 v4 形态（version 位=4）不是 UUIDv7。
      expect(
        () => uuidV7TimestampMs('550e8400-e29b-41d4-a716-446655440000'),
        throwsFormatException,
      );
    });

    test('AiParseRecord.isFreshAt：<7 天内新鲜、负年龄/超龄过期', () {
      final fresh = makeRecord(inputHash: 'h', timestampMs: kBaseMs - 1);
      expect(fresh.isFreshAt(kBaseMs), isTrue);
      expect(fresh.isFreshAt(kBaseMs + 1), isTrue);

      final stale = makeRecord(
          inputHash: 'h', timestampMs: kBaseMs - kAiParseCacheTtl.inMilliseconds - 1);
      expect(stale.isFreshAt(kBaseMs), isFalse);

      final future = makeRecord(inputHash: 'h', timestampMs: kBaseMs + 1);
      expect(future.isFreshAt(kBaseMs), isFalse, reason: '时钟回拨保守不回放');
    });
  });

  group('缓存命中与过期（InMemoryAiParseCache × LlmAiParser）', () {
    test('未命中 → 调 LLM → 成功并写留痕（记录字段 §5.6⑭ 全对齐）', () async {
      final cache = InMemoryAiParseCache();
      final parser = makeParser([kLanzhouParseJson], cache);
      final result = await parser.parse(makeParseInput());

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      expect(success.fromCache, isFalse);

      final hash = computeInputHash(
          normalizeParseInput(kLanzhouInputText), ParseMode.both);
      final record = await cache.find(hash);
      expect(record, isNotNull);
      expect(record!.id, success.record.id);
      expect(record.inputKind, 'text');
      expect(record.inputHash, hash);
      expect(record.provider, 'fake');
      expect(record.model, 'fake-model');
      expect(record.rawOutput, kLanzhouParseJson, reason: 'raw_output 可回放');
      expect(record.latencyMs, 0);
      expect(record.costMicro, 0);
      expect(record.confidence, 0.62,
          reason: '全行最小置信度（0.62 vs 0.93）——最弱 facet 决定高亮档');
      expect(record.promptVersion, kPromptVersion);
      expect(uuidV7TimestampMs(record.id), fakeNowMs(),
          reason: 'id 内嵌时间=解析时刻（7 天时效判定依据）');
    });

    test('命中（<7 天）→ 直接回放 raw_output，不调 LLM', () async {
      final cache = InMemoryAiParseCache();
      final parser = makeParser([kLanzhouParseJson], cache);

      final first = await parser.parse(makeParseInput()) as ParseSuccess;
      final second = await parser.parse(makeParseInput()) as ParseSuccess;

      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1),
          reason: '§7.1：命中直接复用 raw_output，LLM 只调一次');
      expect(second.fromCache, isTrue);
      expect(second.record.id, first.record.id,
          reason: '回放复用同一条 ai_parses 记录（entries.ai_parse_id 溯源同 id）');
      expect(second.lines, hasLength(2));
      expect(second.lines.first.amount, first.lines.first.amount, reason: '回放结果一致');
      expect(second.confidence, first.confidence);
    });

    test('过期（>7 天）→ 视为未命中，重新解析并写入新留痕', () async {
      final hash = computeInputHash(
          normalizeParseInput(kLanzhouInputText), ParseMode.both);
      final cache = InMemoryAiParseCache();
      await cache.save(makeRecord(
        inputHash: hash,
        timestampMs: fakeNowMs() - kAiParseCacheTtl.inMilliseconds - 1,
      ));

      final parser = makeParser([kLanzhouParseJson], cache);
      final result = await parser.parse(makeParseInput()) as ParseSuccess;

      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1),
          reason: '过期记录不回放');
      expect(result.fromCache, isFalse);
      final newRecord = await cache.find(hash);
      expect(newRecord!.createdAtMs, greaterThanOrEqualTo(fakeNowMs()),
          reason: '新留痕已写入且内嵌时间=当前');
    });

    test('TTL 边界：恰好 7 天过期（<7 天才命中）', () async {
      final hash = 'boundary-hash';

      final almostExpired = makeRecord(
          inputHash: hash, timestampMs: fakeNowMs() - kAiParseCacheTtl.inMilliseconds + 1);
      expect(almostExpired.isFreshAt(fakeNowMs()), isTrue);

      final exactlyExpired = makeRecord(
          inputHash: hash, timestampMs: fakeNowMs() - kAiParseCacheTtl.inMilliseconds);
      expect(exactlyExpired.isFreshAt(fakeNowMs()), isFalse);
    });

    test('prompt_version 不同 → 未命中（提示词语义已变，回放不安全）', () async {
      final hash = computeInputHash(
          normalizeParseInput(kLanzhouInputText), ParseMode.both);
      final cache = InMemoryAiParseCache();
      await cache.save(makeRecord(
        inputHash: hash,
        timestampMs: fakeNowMs(),
        promptVersion: 'w0-old',
      ));

      final parser = makeParser([kLanzhouParseJson], cache);
      final result = await parser.parse(makeParseInput()) as ParseSuccess;
      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1));
      expect(result.fromCache, isFalse);
      expect(result.record.promptVersion, kPromptVersion);
    });

    test('损坏的缓存行（raw_output 非法）→ 回退实时管线', () async {
      final hash = computeInputHash(
          normalizeParseInput(kLanzhouInputText), ParseMode.both);
      final cache = InMemoryAiParseCache();
      await cache.save(makeRecord(
        inputHash: hash,
        timestampMs: fakeNowMs(),
        rawOutput: '{{{ 不是 JSON',
      ));

      final parser = makeParser([kLanzhouParseJson], cache);
      final result = await parser.parse(makeParseInput()) as ParseSuccess;
      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1));
      expect(result.fromCache, isFalse);
    });

    test('单边模式键隔离：both 与 moneyOnly 各自解析、互不命中', () async {
      final cache = InMemoryAiParseCache();
      final adapter = FakeLlmAdapter.scripted([kLanzhouParseJson, kLanzhouParseJson]);
      final parser = LlmAiParser(
        adapter: adapter,
        cache: cache,
        nowMs: fakeNowMs,
        newParseId: makeIdSeq(),
      );

      final both = await parser.parse(makeParseInput(mode: ParseMode.both));
      final moneyOnly = await parser.parse(makeParseInput(mode: ParseMode.moneyOnly));

      expect(adapter.requests, hasLength(2), reason: '不同模式不同缓存键');
      expect((both as ParseSuccess).fromCache, isFalse);
      expect((moneyOnly as ParseSuccess).fromCache, isFalse);
      expect(moneyOnly.lines, hasLength(1), reason: 'moneyOnly 模式只保留 money 行');
      expect(cache.cachedHashes, hasLength(2));
    });

    test('语音通道与文本通道同文本共享缓存（hash 不含通道）', () async {
      final cache = InMemoryAiParseCache();
      final parser = makeParser([kLanzhouParseJson], cache);

      final text = await parser.parse(makeParseInput(kind: AiInputKind.text));
      final voice =
          await parser.parse(makeParseInput(kind: AiInputKind.voice));

      expect((parser.adapter as FakeLlmAdapter).requests, hasLength(1));
      expect((voice as ParseSuccess).fromCache, isTrue);
      expect((text as ParseSuccess).record.id, voice.record.id);
      // 留痕的 input_kind 记录的是**首次解析**的通道（§5.6⑭ input_kind）。
      expect(voice.record.inputKind, 'text');
    });

    test('失败解析不写留痕（raw_output 只存成功解析）', () async {
      final cache = InMemoryAiParseCache();
      final parser = makeParser([
        const LlmTimeoutException('超时'),
      ], cache);
      await parser.parse(makeParseInput());
      expect(cache.cachedHashes, isEmpty);
    });
  });

  group('DriftAiParseCache（core_db ai_parses 表落库实现）', () {
    test('save→find 往返 + 同 hash 多记录取最新（ORDER BY id DESC）', () async {
      final db = cdb.AppDatabase(NativeDatabase.memory());
      try {
        await db.customSelect('SELECT 1').getSingle();

        final cache = DriftAiParseCache(db);
        final hash = computeInputHash('查缓存', ParseMode.both);

        // 旧记录（3 天前）。
        final older = makeRecord(
          inputHash: hash,
          timestampMs: fakeNowMs() - 3 * 86400000,
          confidence: 0.5,
        );
        await cache.save(older);
        expect(await cache.find(hash), older);

        // 新记录（现在）：同 hash 第二次解析 → id 时间序更大 → 命中最新。
        final newer = makeRecord(inputHash: hash, timestampMs: fakeNowMs());
        await cache.save(newer);
        final found = await cache.find(hash);
        expect(found!.id, newer.id);
        expect(found.createdAtMs, greaterThan(older.createdAtMs));

        // 无关 hash 查不到。
        expect(await cache.find('nope'), isNull);

        // 幂等 upsert（同 id 再存 → 整行替换）。
        final replaced = AiParseRecord(
          id: newer.id,
          inputKind: 'voice',
          inputHash: hash,
          provider: newer.provider,
          model: newer.model,
          rawOutput: newer.rawOutput,
          latencyMs: newer.latencyMs,
          costMicro: newer.costMicro,
          confidence: 0.7,
          promptVersion: newer.promptVersion,
        );
        await cache.save(replaced);
        final afterReplace = await cache.find(hash);
        expect(afterReplace!.confidence, 0.7);
        expect(afterReplace.inputKind, 'voice');

        // 行真实落在 ai_parses 表（§5.6⑭ 21 表之一）。
        final rows = await db.select(db.aiParses).get();
        expect(rows, hasLength(2), reason: 'older + newer 两条留痕');
      } catch (error) {
        if (_isSqliteLibraryMissing(error)) {
          // ignore: avoid_print
          print('SKIP：宿主缺 sqlite3 运行库，DriftAiParseCache 测试未执行（$error）');
          return;
        }
        rethrow;
      } finally {
        await db.close();
      }
    });
  });
}
