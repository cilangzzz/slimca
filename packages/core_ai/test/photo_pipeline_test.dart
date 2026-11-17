/// PhotoParser 管线编排测试（W11-12 任务：主成功/主失败兜底/双失败降级、
/// 缓存回放、fixture 图片端到端 PhotoParser）。
///
/// 全部离线：识别供应商经 FakeDishAdapter（脚本化候选/异常），压缩机为
/// PureDartImageCompressor（fixture 小图真实 codec）或注入异常桩，缓存为
/// InMemoryAiParseCache——禁止真实网络/相机（任务硬规则）。
library;

import 'package:core_ai/core_ai.dart';
import 'package:core_domain/core_domain.dart' as dom;
import 'package:flutter_test/flutter_test.dart';

import 'photo_test_support.dart';
import 'test_support.dart';

/// 构造拍照解析器（脚本化供应商优先级清单 + 注入时钟/序列 id）。
PhotoParser makeParser({
  required List<ImageDishAdapter> providers,
  ImageCompressor? compressor,
  AiParseCache? cache,
  DishRefLookup? refLookup,
}) =>
    PhotoParser(
      providers: providers,
      compressor: compressor ?? const PureDartImageCompressor(),
      cache: cache ?? InMemoryAiParseCache(),
      refLookup: refLookup ?? const PassthroughDishRefLookup(),
      nowMs: fakeNowMs,
      newParseId: makeIdSeq(),
    );

void main() {
  group('管线编排（§7.4 第 4 级：百度先行 → Vision 兜底 → StructuredFailure）', () {
    test('主成功：百度先行候选 → ParseSuccess + ai_parses 留痕 + 缓存写入',
        () async {
      final primary = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'baidu_test', modelId: 'dish_v2');
      final fallback = FakeDishAdapter.scripted(<Object>[]);
      final cache = InMemoryAiParseCache();
      final parser = makeParser(
        providers: [primary, fallback],
        cache: cache,
      );

      final result = await parser.parse(makePhotoRequest(makeJpegFixture()));

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      expect(success.fromCache, isFalse);
      expect(success.title, '宫保鸡丁、米饭');
      expect(success.kind, dom.EntryKind.food,
          reason: '§5.2① 拍照恒餐食');
      expect(success.lines, hasLength(1));
      expect(success.lines.single.amount, 750, reason: 'Σitems kcal（§7.2）');
      expect(success.lines.single.items.map((i) => i.name).toList(),
          ['宫保鸡丁', '米饭']);
      // ai_parses 留痕（§5.6⑭）：provider/model/input_kind/prompt_version。
      expect(success.record.provider, 'baidu_test');
      expect(success.record.model, 'dish_v2');
      expect(success.record.inputKind, AiInputKind.photo.wire);
      expect(success.record.promptVersion, kPhotoPromptVersion);
      expect(success.record.confidence, closeTo(0.56, 1e-9));
      expect(success.record.latencyMs, greaterThanOrEqualTo(0));
      // 缓存写入（§7.1：命中 <7 天直接复用）。
      expect(cache.cachedHashes, contains(success.inputHash));
      // notes：双供应商语境 + 隐私口径（§3.3 即用即焚）。
      expect(success.notes.join('；'), contains('baidu_test 先行成功'));
      expect(success.notes.join('；'), contains('即用即焚'));
      // 兜底供应商未被调用（成功短路）。
      expect(fallback.images, isEmpty);
    });

    test('主失败（异常）兜底：百度抛限流 → Vision 兜底成功', () async {
      final primary = FakeDishAdapter.scripted(
        <Object>[
          const LlmRateLimitException('百度 QPS 限流（测试）'),
        ],
        providerId: 'baidu_test',
      );
      final fallback = FakeDishAdapter.scripted(
        <Object>[
          const [
            DishCandidate(name: '牛肉拉面', grams: 450, confidence: 0.55),
          ],
        ],
        providerId: 'vision_test',
        modelId: 'qwen-vl-test',
      );
      final parser = makeParser(providers: [primary, fallback]);

      final result =
          await parser.parse(makePhotoRequest(makeJpegFixture()));

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      expect(success.record.provider, 'vision_test',
          reason: '§7.4：双供应商 fallback 记账到实际成功的供应商');
      expect(success.record.inputKind, AiInputKind.photo.wire);
      expect(success.lines.single.items.single.name, '牛肉拉面');
      // 主侧收到的压缩规范形 → 失败；兜底侧收到同图。
      expect(primary.images, hasLength(1));
      expect(fallback.images, hasLength(1));
    });

    test('主侧空结果 → 兜底成功（空结果=正常业务分支，§7.4）', () async {
      final primary = FakeDishAdapter.scripted(<Object>[<DishCandidate>[]],
          providerId: 'baidu_test');
      final fallback = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'vision_test');
      final parser = makeParser(providers: [primary, fallback]);

      final result = await parser.parse(makePhotoRequest(makeJpegFixture()));

      expect(result, isA<ParseSuccess>());
      expect((result as ParseSuccess).record.provider, 'vision_test');
    });

    test('双失败降级：百度断网 + Vision 断网 → deferredQueue（§7.4 二级）',
        () async {
      final primary = FakeDishAdapter.scripted(
        <Object>[const LlmNetworkException('断网（测试）')],
        providerId: 'baidu_test',
      );
      final fallback = FakeDishAdapter.scripted(
        <Object>[const LlmNetworkException('断网（测试）')],
        providerId: 'vision_test',
      );
      final parser = makeParser(providers: [primary, fallback]);

      final result = await parser.parse(makePhotoRequest(makeJpegFixture()));

      expect(result, isA<StructuredFailure>());
      final failure = result as StructuredFailure;
      expect(failure.reason, AiFailureReason.network);
      expect(failure.degradeLevel, AiDegradeLevel.deferredQueue,
          reason: '§7.4：断网 → 记录落 draft + 延迟解析队列');
      expect(failure.attempts, 2);
      expect(failure.errors, hasLength(2));
      expect(failure.errors.first, contains('[baidu_test]'));
      expect(failure.errors.last, contains('[vision_test]'));
      expect(failure.context.mode, ParseMode.kcalOnly,
          reason: '拍照通道恒单边热量口径（§3.3）');
      expect(failure.rawInput, startsWith('photo:'),
          reason: '原图即用即焚，raw_input 只落描述符（§3.3）');
      expect(failure.cause, isA<LlmNetworkException>());
    });

    test('双失败降级：百度额度耗尽 + Vision 超时 → quotaNotice（§7.4 三级）',
        () async {
      final primary = FakeDishAdapter.scripted(
        <Object>[const LlmQuotaException('百度额度耗尽（测试）')],
        providerId: 'baidu_test',
      );
      final fallback = FakeDishAdapter.scripted(
        <Object>[const LlmTimeoutException('Vision 超时（测试）')],
        providerId: 'vision_test',
      );
      final parser = makeParser(providers: [primary, fallback]);

      final failure = await parser.parse(makePhotoRequest(makeJpegFixture()))
          as StructuredFailure;

      expect(failure.reason, AiFailureReason.timeout,
          reason: '失败原因取末个供应商（最后尝试）');
      expect(failure.degradeLevel, AiDegradeLevel.quotaNotice,
          reason: '先行侧已报额度耗尽 → 额度提示优先级保留（§7.4 三级语义在途）');
    });

    test('双失败降级：单供应商装配（兜底缺位）→ 手填（装配不以 Fake 充数）',
        () async {
      final primary = FakeDishAdapter.scripted(
        <Object>[const LlmServerException('百度故障（测试）')],
        providerId: 'baidu_test',
      );
      final parser = makeParser(providers: [primary]);

      final failure = await parser.parse(makePhotoRequest(makeJpegFixture()))
          as StructuredFailure;

      expect(failure.reason, AiFailureReason.providerError);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
      expect(failure.attempts, 1);
    });

    test('压缩失败 → 一级降级手填，供应商零调用（§7.4）', () async {
      final primary = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'baidu_test');
      final parser = makeParser(
        providers: [primary],
        compressor: const ThrowingCompressor(),
      );

      final failure = await parser.parse(makePhotoRequest(makeJpegFixture()))
          as StructuredFailure;

      expect(failure.reason, AiFailureReason.invalidRequest);
      expect(failure.degradeLevel, AiDegradeLevel.manualForm);
      expect(failure.attempts, 0);
      expect(failure.errors.single, contains('压缩失败'));
      expect(primary.images, isEmpty);
    });

    test('空供应商装配 → StructuredFailure（装配遗漏显式暴露）', () async {
      final parser = makeParser(providers: const <ImageDishAdapter>[]);
      final failure = await parser.parse(makePhotoRequest(makeJpegFixture()))
          as StructuredFailure;
      expect(failure.reason, AiFailureReason.invalidRequest);
      expect(failure.errors.single, contains('未装配任何识别供应商'));
    });

    test('非法日期入口 → ArgumentError（§5.1 日历日契约）', () async {
      final parser = makeParser(
        providers: [FakeDishAdapter.scripted(<Object>[kFixtureDishes])],
      );
      await expectLater(
        parser.parse(makePhotoRequest(makeJpegFixture(), date: '2026/11/30')),
        throwsArgumentError,
      );
    });
  });

  group('缓存回放（§7.1/§5.6⑭：input_hash 命中 <7 天 → 复用 raw_output）', () {
    test('命中：供应商零调用、fromCache=true、回放草稿与首发一致', () async {
      final cache = InMemoryAiParseCache();
      const compressor = PureDartImageCompressor();
      final fixtureBytes = makeJpegFixture(width: 16, height: 12);

      // 预放缓存：压缩规范形 → input_hash → §7.2 raw_output。
      final compressed =
          await compressor.compress(PhotoImageInput(bytes: fixtureBytes, mime: 'image/jpeg'));
      final inputHash = computePhotoInputHash(compressed.bytes, compressed.mime);
      final rawOutput = assembleDishParseJson(
        dishes: kFixtureDishes,
        refLookup: const PassthroughDishRefLookup(),
        fallbackRefSource: FoodRefSource.baidu,
      );
      await cache.save(AiParseRecord(
        id: makeIdSeq()(),
        inputKind: AiInputKind.photo.wire,
        inputHash: inputHash,
        provider: 'baidu_test',
        model: 'dish_v2',
        rawOutput: rawOutput,
        latencyMs: 11,
        costMicro: 0,
        confidence: 0.56,
        promptVersion: kPhotoPromptVersion,
      ));

      // 脚本为空：任何供应商调用都会抛 StateError（显式暴露意外调用）。
      final primary = FakeDishAdapter.scripted(<Object>[], providerId: 'baidu_test');
      final parser = PhotoParser(
        providers: [primary],
        compressor: compressor,
        cache: cache,
        nowMs: fakeNowMs,
        newParseId: makeIdSeq(),
      );

      final result = await parser.parse(makePhotoRequest(fixtureBytes));

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      expect(success.fromCache, isTrue);
      expect(success.record.id, isNot(equals('')),
          reason: '回放携带原 ai_parses 行');
      expect(success.inputHash, inputHash);
      expect(success.title, '宫保鸡丁、米饭');
      expect(success.lines.single.amount, 750);
      expect(success.notes.join('；'), contains('缓存命中'));
      expect(primary.images, isEmpty, reason: '缓存命中不调供应商（§7.1）');
    });

    test('prompt_version 不同 → 视为未命中（回放兼容性闸门，§5.6⑭）', () async {
      final cache = InMemoryAiParseCache();
      const compressor = PureDartImageCompressor();
      final fixtureBytes = makeJpegFixture(width: 16, height: 12);
      final compressed =
          await compressor.compress(PhotoImageInput(bytes: fixtureBytes, mime: 'image/jpeg'));
      final inputHash = computePhotoInputHash(compressed.bytes, compressed.mime);
      await cache.save(AiParseRecord(
        id: makeIdSeq()(),
        inputKind: AiInputKind.photo.wire,
        inputHash: inputHash,
        provider: 'legacy',
        model: 'legacy',
        rawOutput: assembleDishParseJson(
          dishes: kFixtureDishes,
          refLookup: const PassthroughDishRefLookup(),
          fallbackRefSource: FoodRefSource.baidu,
        ),
        latencyMs: 5,
        costMicro: 0,
        confidence: 0.56,
        promptVersion: 'w3-4-v1',
      ));

      final primary = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'baidu_test');
      final parser = PhotoParser(
        providers: [primary],
        compressor: compressor,
        cache: cache,
        nowMs: fakeNowMs,
        newParseId: makeIdSeq(),
      );

      final result = await parser.parse(makePhotoRequest(fixtureBytes));
      expect(result, isA<ParseSuccess>());
      expect((result as ParseSuccess).fromCache, isFalse);
      expect(primary.images, hasLength(1), reason: '版本闸门未命中 → 走实时管线');
    });

    test('同一 fixture 二次解析直接命中缓存（端到端确定性）', () async {
      final cache = InMemoryAiParseCache();
      final primary = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'baidu_test');
      final parser = makeParser(providers: [primary], cache: cache);
      final fixtureBytes = makeJpegFixture(width: 16, height: 12);

      final first = await parser.parse(makePhotoRequest(fixtureBytes));
      expect(first, isA<ParseSuccess>());
      expect((first as ParseSuccess).fromCache, isFalse);

      final second = await parser.parse(makePhotoRequest(fixtureBytes));
      expect(second, isA<ParseSuccess>());
      final success = second as ParseSuccess;
      expect(success.fromCache, isTrue);
      expect(success.title, first.title);
      expect(success.lines.single.amount, first.lines.single.amount);
      expect(primary.images, hasLength(1), reason: '第二次零供应商调用');
    });
  });

  group('fixture 图片端到端 PhotoParser（真实压缩 + 脚本供应商，§3.3 全口径）', () {
    test('原图 → 压缩规范形（≤1280 JPEG）→ 候选 → 草稿 → ParseSuccess', () async {
      // 超限 fixture：1280×720 缩放口径在端到端链路中真实发生。
      final rawBytes = makeJpegFixture(width: 1600, height: 900);
      final primary = FakeDishAdapter.scripted(<Object>[kFixtureDishes],
          providerId: 'baidu_test');
      final parser = makeParser(providers: [primary]);

      final result = await parser.parse(makePhotoRequest(rawBytes));

      expect(result, isA<ParseSuccess>());
      final success = result as ParseSuccess;
      // 端侧压缩口径（§3.3）：供应商收到长边 1280 的 JPEG 规范形。
      final seen = primary.images.single;
      expect(seen.mime, 'image/jpeg');
      expect(seen.widthPx, 1280);
      expect(seen.heightPx, 720);
      expect(seen.bytes.length, lessThan(rawBytes.length));
      // input_hash 基于压缩规范形（§7.1 规范化=压缩规范形）。
      expect(success.inputHash,
          computePhotoInputHash(seen.bytes, seen.mime));
      // food_items 草稿（§5.2③）。
      final items = success.lines.single.items;
      expect(items.map((i) => i.name).toList(), ['宫保鸡丁', '米饭']);
      for (final item in items) {
        expect(item.kcal, inInclusiveRange(0, 5000));
        expect(item.portionG, greaterThan(0));
        expect(item.confidence, inInclusiveRange(0, 1));
      }
      // 即用即焚（§3.3）：留痕只有描述符与结构化结果。
      expect(success.record.rawOutput, startsWith('{"title"'));
      expect(success.record.rawOutput, isNot(contains('base64')));
    });
  });
}
