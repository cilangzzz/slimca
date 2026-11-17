/// W11-12 拍照通道 widget 测试（§11.2 W11-12 主线、§3.3 拍照通道、§3.7
/// 数据主权、§5.6㉑ attachments、§5.6⑭ ai_parses photo 缓存）。
///
/// 硬规则（§11.2）：测试禁止真实网络/相机——[FakeImageSource] 返回 fixture
/// 字节（可落**真实临时文件**验证即焚删除）、[FakeImageCompressor] 透传 +
/// sha256（生产同源键口径）、[FakeCapturePhotoParser] 脚本化识别、
/// [FakeCaptureOnDeviceEstimator] 脚本化端侧粗估；attachments 行断言走
/// [DbCaptureAttachmentStore]→core_db [cdb.AttachmentsDao] 真桥接（内存
/// 真库），即焚状态机 active→burned 与文件删除全链路可断言。
///
/// 用例：
/// 1. 拍照主链路（上云开）：入口→压缩→识别→确认卡→确认落库——entry
///    (source=photo, kind=mixed) + calorie/money 行 + food_items +
///    ai_parses(input_kind=photo, input_hash=sha256(压缩字节)) + attachments
///    burned 行（blob_ref NULL）+ 临时文件已删 + 漏斗三事件与 ≤15s 护栏
///    metric（§11.2 任务 2/3/5）；
/// 2. input_hash 缓存复用（§5.6⑭）：同字节第二次拍照不再调解析器、徽标
///    「缓存复用」、两次落库共享 ai_parses 行、两份临时文件均焚；
/// 3. 上云关（§3.7 默认）+端侧粗估可用：解析器零调用（字节不出端）、无
///    ai_parses 行、端侧粗估徽标、落库 kind=food、确认后照常即焚；
/// 4. 上云关+端侧无法估计：自动转人工确认表单；确认前即焚**未发生**（临时
///    文件仍在、无附件行——§11.2 任务 4「绝不丢已拍数据」），手填落库
///    source=photo 后才焚；
/// 5. 识别失败（§7.4）：降级手填、确认前原件保留、确认后焚毁，漏斗
///    outcome=fallback 带错误**类型**码（§3.9 隐私口径）；
/// 6. 相册选择路径：pickGallery 分流、photo_capture_open from_camera=false。
///
/// 运行前提：集成阶段已 `flutter pub get`；宿主缺 sqlite3 运行库时温和跳过。
library;

import 'dart:io';

import 'package:core_db/core_db.dart' as cdb;
import 'package:core_domain/core_domain.dart' as dom;
// BooleanExpressionOperators：`&` 谓词组合是 drift 扩展方法，需显式导入。
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（Windows 桌面测试常见）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// fixture 图片字节的内容哈希（§5.6㉑/§5.6⑭：sha256(压缩字节) 一址两用）。
final String _fixtureHash = sha256.convert(kFakePhotoBytes).toString();

/// 拍照识别结果夹具（§7.3 受约束输出形态）：calorie 550 kcal（置信度 0.62，
/// 带菜品明细触发 food_items 落库）+ money ¥18.00（置信度 0.55，
/// category_hint 命中内置「餐饮-正餐」）。
CaptureParseResult _photoParseResult() => CaptureParseResult(
      title: '牛肉拉面',
      parseNotes: '拍照识别：份量按标准碗估计',
      provider: 'fake-photo',
      model: 'fake-vision-1',
      promptVersion: 'w11-12-test-v1',
      latencyMs: 120,
      costMicro: 15,
      confidence: 0.72,
      lines: [
        const CaptureParsedLine(
          typeWire: 'calorie',
          amountKcal: 550,
          confidence: 0.62,
          items: [
            CaptureParsedItem(
              name: '牛肉拉面',
              portionG: 450,
              kcal: 500,
              proteinG: 25,
              carbG: 65,
              fatG: 12,
              confidence: 0.6,
              refSource: 'baidu',
            ),
          ],
        ),
        const CaptureParsedLine(
          typeWire: 'money',
          amountMinor: 1800,
          confidence: 0.55,
          categoryHint: '餐饮-正餐',
        ),
      ],
    );

/// 端侧粗估夹具（§3.7 关=端侧粗估+人工确认）：仅热量 480 kcal，无 money 行
/// → 确认落库 kind=food（§5.2①）；无云端解析 → ai_parses 不落行（§5.6⑭）。
const CaptureParseResult _onDeviceEstimateResult = CaptureParseResult(
  title: '家常豆腐',
  provider: 'on_device',
  model: '端侧粗估',
  promptVersion: 'on-device',
  latencyMs: 30,
  costMicro: 0,
  confidence: 0.5,
  lines: [
    CaptureParsedLine(
      typeWire: 'calorie',
      amountKcal: 480,
      confidence: 0.55,
      items: [
        CaptureParsedItem(
          name: '家常豆腐',
          portionG: 300,
          kcal: 450,
          confidence: 0.5,
          refSource: 'on_device',
        ),
      ],
    ),
  ],
);

/// 遥测录制器（§11.2 任务 5：漏斗三事件 + ≤15s 护栏 metric 的断言数据源）。
class RecordingTelemetry implements dom.TelemetryService {
  /// 按发生顺序录制的全部事件（funnel + metric）。
  final List<dom.TelemetryEvent> events = [];

  @override
  Future<void> funnel(String name, {Map<String, Object?>? props}) async {
    events.add(dom.TelemetryEvent(
      kind: dom.TelemetryKind.funnel,
      name: name,
      atMs: DateTime.now().millisecondsSinceEpoch,
      props: props ?? const {},
    ));
  }

  @override
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  }) async {
    events.add(dom.TelemetryEvent(
      kind: dom.TelemetryKind.metric,
      name: name,
      atMs: DateTime.now().millisecondsSinceEpoch,
      props: {'value': value, if (tags != null) ...tags},
    ));
  }

  @override
  Future<void> crash(Object error, StackTrace? stackTrace,
      {String? source}) async {}

  @override
  Future<void> flush() async {}
}

/// 测试夹具：内存真库 + 注入 HlcClock + 录入网关 + AttachmentsDao + §3.7
/// 上云开关（[rawInputOpen] 运行中可切）。
class _Harness {
  cdb.AppDatabase? _db;
  dom.HlcClock? _clock;
  CaptureGateway? _gateway;
  cdb.AttachmentsDao? _attachmentsDao;

  cdb.AppDatabase get db => _db!;
  CaptureGateway get gateway => _gateway!;
  cdb.AttachmentsDao get attachmentsDao => _attachmentsDao!;

  /// §3.7 raw_input 上云开关（true=识别可携字节上云；false=字节不出端）。
  bool rawInputOpen = true;

  /// 初始化；宿主缺 sqlite3 运行库时返回 false（测试温和跳过）。
  Future<bool> init() async {
    final db = cdb.AppDatabase(NativeDatabase.memory());
    try {
      await db.customSelect('SELECT 1').getSingle();
    } catch (error) {
      if (_isSqliteLibraryMissing(error)) {
        // ignore: avoid_print
        print('SKIP：宿主缺 sqlite3 运行库，拍照通道测试未执行（$error）');
        return false;
      }
      rethrow;
    }
    _db = db;
    _clock = dom.HlcClock(deviceId: '3F8A12C0B7D4');
    _gateway = createCaptureGateway(db: db, clock: _clock!);
    _attachmentsDao = cdb.AttachmentsDao(db);
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

/// 泵 CapturePage（ProviderScope 覆盖注入网关 + 拍照通道全套 Fake，§10.4
/// DI 契约的测试形态）并等待输入区就绪。
Future<void> _pumpPhotoCapture(
  WidgetTester tester,
  _Harness harness, {
  required FakeImageSource source,
  required FakeImageCompressor compressor,
  required FakeCapturePhotoParser photoParser,
  required FakeCaptureOnDeviceEstimator estimator,
  required RecordingTelemetry telemetry,
}) async {
  // 放大视口：抽屉内容一屏放下，免滚动命中。
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        captureGatewayProvider.overrideWithValue(harness.gateway),
        // §11.2 任务 1：ImageSource 抽象（壳注入 image_picker 薄封装；
        // 测试注入 Fake）。
        captureImageSourceProvider.overrideWithValue(source),
        captureImageCompressorProvider.overrideWithValue(compressor),
        capturePhotoParserProvider.overrideWithValue(photoParser),
        captureOnDeviceEstimatorProvider.overrideWithValue(estimator),
        // §11.2 任务 3：即焚经 core_db AttachmentsDao 真桥接（内存真库）。
        captureAttachmentStoreProvider.overrideWithValue(
          DbCaptureAttachmentStore(harness.attachmentsDao),
        ),
        capturePhotoTelemetryProvider.overrideWithValue(telemetry),
        // §3.7 raw_input 上云开关（运行时可切的同步读取，同壳层装配形态）。
        captureRawInputCloudEnabledProvider
            .overrideWithValue(() => harness.rawInputOpen),
      ],
      child: MaterialApp(
        theme: buildTheme(brightness: Brightness.light),
        home: const Scaffold(body: CapturePage()),
      ),
    ),
  );

  await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
    // 拍照链含真实文件 IO（Fake 落盘/即焚删除）：testWidgets 的 FakeAsync
    // zone 不投递 IO 事件，runAsync 短暂逃出让真实事件循环推进一拍，pump
    // 再推进其后的 fake-zone 微任务链——两者交替直至控件出现。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('等待控件超时: $finder');
}

/// 向带 key 的 [CaptureTextField] 输入文本（TextField 是其内部子控件）。
Future<void> _enterText(WidgetTester tester, Key fieldKey, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(fieldKey), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

/// 轮询等待 entries 达到 [count]，返回首个 entry id（提交落库的异步桥）。
Future<String> _waitForEntryCount(
  WidgetTester tester,
  _Harness harness,
  int count,
) async {
  for (var i = 0; i < 240; i++) {
    final rows = await harness.db.select(harness.db.entries).get();
    if (rows.length >= count) {
      return rows.first.id;
    }
    await tester.pump(const Duration(milliseconds: 20));
    // 真实 IO 桥（同 _pumpUntilFound：落库链后续的即焚删除仍待收口）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('提交未落库：entries 数量未达到 $count');
}

/// 轮询等待 attachments 达到 [count] 且全部 burned（登记即焚完成的异步桥），
/// 返回全部附件行。
///
/// 收口判据 = burned 行齐 + 各行临时文件所在临时目录已被清（即焚链的最后
/// 一步 `_deleteTempFile` 父目录删除完成）+ **photo_confirm 漏斗终点已发**
/// （终点埋点在即焚链收口后的同一微任务拍发出——把「事件已可断言」一并纳入
/// 轮询判据，规避「状态已到、终点微任务尚未冲刷」的窗口期假通过）。
Future<List<cdb.Attachment>> _waitForBurnedAttachments(
  WidgetTester tester,
  _Harness harness,
  int count, {
  required RecordingTelemetry telemetry,
}) async {
  bool settled = false;
  List<cdb.Attachment> rows = const [];
  for (var i = 0; i < 240; i++) {
    rows = await harness.db.select(harness.db.attachments).get();
    settled = rows.length >= count &&
        rows.every((r) => r.status == cdb.kAttachmentStatusBurned) &&
        rows.every(
          (r) => !Directory(File(r.localPath).parent.path).existsSync(),
        ) &&
        telemetry.events.any((e) =>
            e.kind == dom.TelemetryKind.funnel &&
            e.name == CapturePhotoFunnel.photoConfirm);
    if (settled) break;
    await tester.pump(const Duration(milliseconds: 20));
    // 真实 IO 桥（同 _pumpUntilFound：FakeAsync zone 不投递 IO 事件）。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  if (!settled) {
    fail('即焚未完成：attachments 未达 $count 条 burned 行（含临时目录清理与'
        'photo_confirm 终点）');
  }
  // 终点埋点先于提交收尾的 submitting:false 重建一拍：补两拍 pump 把收尾
  // 状态帧渲染完，避免随后的按钮交互（重新解析等）命中禁用态。
  await tester.pump();
  await tester.pump();
  return rows;
}

void main() {
  testWidgets(
    '拍照主链路（上云开）：拍照→压缩→识别→确认卡→落库'
    '（entry source=photo/kind=mixed+双行+food_items+ai_parses photo+'
    'attachments burned+临时文件已删+漏斗护栏）（§11.2 任务 2/3/5）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult());
      final estimator = FakeCaptureOnDeviceEstimator();
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      // 隐私提示（§3.7 上云开=本次识别可用字节，确认落库后即焚）。
      expect(find.text('原图仅用于本次识别，确认落库后即焚（§3.7/§11.2）'),
          findsOneWidget);

      // 入口「拍照」→ 压缩 → 识别 → 确认卡（Fake 即时返回，等待跨过呼吸态）。
      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      // ── 通道编排断言（§11.2 任务 1/2）──
      expect(source.captureCalls, 1);
      expect(source.galleryCalls, 0);
      expect(compressor.calls, 1, reason: '§3.3 端侧压缩先于识别');
      expect(parser.calls, 1, reason: '上云开 + 缓存未命中 → 云端识别');
      expect(parser.requests.single.inputHash, _fixtureHash,
          reason: '§7.1/§5.6⑭ input_hash=sha256(压缩字节)');
      expect(parser.requests.single.mime, 'image/jpeg',
          reason: '§3.3 压缩产物 JPEG q80 口径');

      // ── 确认卡断言（AI 初值预填复用 W3-4 确认卡，§11.2 任务 2）──
      expect(find.text('拍照识别初值（§11.2）'), findsOneWidget);
      expect(find.text('牛肉拉面'), findsOneWidget, reason: '标题预填识别建议');
      expect(find.text('550'), findsOneWidget, reason: '热量 count-up 终值');
      expect(find.text('¥18.00'), findsOneWidget, reason: '金额 count-up 终值');
      expect(find.text('置信度 62%'), findsOneWidget);
      expect(find.text('置信度 55%'), findsOneWidget);

      // 确认落库 → 即焚（§11.2 任务 3）。
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      // ── entries 断言（§5.2①）：source=photo、kind 由行集合推导（双行=mixed）──
      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.source, 'photo',
          reason: '§5.2① source：拍照通道（EntrySource.photo）');
      expect(entry.kind, 'mixed', reason: '§5.2① 双行=mixed');
      expect(entry.status, 'confirmed', reason: '用户已在确认卡确认（§3.3）');
      expect(entry.title, '牛肉拉面');
      expect(entry.aiParseId, isNotNull, reason: 'ai_parses.id 溯源（§5.2①）');

      // ── ai_parses 断言（§5.6⑭：input_kind=photo、input_hash=sha256(字节)）──
      final parses = await harness.db.select(harness.db.aiParses).get();
      expect(parses, hasLength(1));
      final parse = parses.single;
      expect(entry.aiParseId, parse.id);
      expect(parse.inputKind, 'photo', reason: '§5.6⑭ 拍照通道 input_kind');
      expect(parse.inputHash, _fixtureHash);
      expect(parse.provider, 'fake-photo');
      expect(parse.model, 'fake-vision-1');
      expect(parse.latencyMs, 120);
      expect(parse.cost, 15, reason: '成本微元留痕（§5.6⑭）');

      // ── entry_lines 断言（§5.2②）：calorie 行 + money 行 ──
      final lines = await (harness.db.select(harness.db.entryLines)
            ..where((t) => t.entryId.equals(entryId)))
          .get();
      expect(lines, hasLength(2));
      final kcalLine = lines.singleWhere((l) => l.type == 'calorie');
      final moneyLine = lines.singleWhere((l) => l.type == 'money');
      expect(kcalLine.amount, 550);
      expect(kcalLine.direction, 'in', reason: '§5.2② calorie=in（摄入）');
      expect(kcalLine.confidence, 0.62, reason: 'AI 产出行必填置信度（§5.2②）');
      expect(moneyLine.amount, 1800, reason: '§5.1 金额整数分（¥18.00）');
      expect(moneyLine.direction, 'out');
      expect(moneyLine.confidence, 0.55);
      expect(moneyLine.categoryId,
          await harness.presetCategoryId('餐饮-正餐', kind: 'expense'),
          reason: 'category_hint 命中内置分类（§7.3）');

      // ── food_items 逐菜品断言（§5.2③）──
      final foods = await harness.db.select(harness.db.foodItems).get();
      expect(foods, hasLength(1));
      expect(foods.single.entryId, entryId);
      expect(foods.single.lineId, kcalLine.id);
      expect(foods.single.name, '牛肉拉面');
      expect(foods.single.portionG, 450);
      expect(foods.single.kcal, 500);
      expect(foods.single.refSource, 'baidu');

      // ── 即焚断言（§3.7/§11.2 任务 3、§5.6㉑）──
      final atts = await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);
      final att = atts.single;
      expect(att.entryId, entryId, reason: '确认落库后登记（entry_id 非空）');
      expect(att.contentHash, _fixtureHash, reason: '§5.6㉑ content_hash 去重键');
      expect(att.kind, cdb.kAttachmentKindPhoto);
      expect(att.mime, 'image/jpeg');
      expect(att.sizeBytes, kFakePhotoBytes.length);
      expect(att.status, cdb.kAttachmentStatusBurned,
          reason: '登记即焚：attachments 行标记 burned（§11.2 任务 3）');
      expect(att.burnedAt, isNotNull, reason: '§3.3 即焚时刻留痕');
      expect(att.blobRef, isNull, reason: '§5.6㉑ 原图不落服务端（blob_ref 恒 NULL）');
      expect(att.localPath, source.createdPaths.single);
      expect(File(source.createdPaths.single).existsSync(), isFalse,
          reason: '§3.7/§11.2 本地临时文件已焚毁删除');

      // 等待漏斗终点（photo_confirm 在即焚与文件删除之后发出，§11.2 任务 5）。
      for (var i = 0; i < 150; i++) {
        final hasConfirm = telemetry.events.any((e) =>
            e.kind == dom.TelemetryKind.funnel &&
            e.name == CapturePhotoFunnel.photoConfirm);
        if (hasConfirm) break;
        await tester.pump(const Duration(milliseconds: 20));
      }

      // ── 漏斗埋点断言（§11.2 任务 5、§2.3 ≤15s 护栏）──
      final open = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoCaptureOpen);
      expect(open.props['from_camera'], true, reason: '拍照入口分流标记');
      final parseResultEvent = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoParseResult);
      expect(parseResultEvent.props['outcome'], 'success');
      final confirm = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoConfirm);
      expect(confirm.props['total_ms'], isA<int>());
      expect(confirm.props['within_guard'], true,
          reason: '§2.3 拍照路径全程 ≤15s 护栏');
      final metric = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.metric &&
          e.name == dom.TelemetryMetricName.captureOpenToConfirmMs);
      expect(metric.props['path'], 'photo',
          reason: 'metric 复用 capture_open_to_confirm_ms，tags.path 区分路径');
    },
  );

  testWidgets(
    'input_hash 缓存复用（§5.6⑭）：同字节第二次拍照解析器零调用、共享 ai_parses 行',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult());
      final estimator = FakeCaptureOnDeviceEstimator();
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      // 第一次拍照 → 确认落库（留下 ai_parses photo 行）。
      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      await _waitForEntryCount(tester, harness, 1);
      await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);

      // 重新解析 → 输入区 → 第二次拍照（同 fixture 字节 → 同 input_hash）。
      await tester.tap(find.byKey(captureReparseButtonKey));
      await _pumpUntilFound(tester, find.byKey(captureAiInputKey));
      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      // 缓存命中断言：解析器仍只被调用 1 次；徽标显示缓存复用（§3.3）。
      expect(parser.calls, 1, reason: '§5.6⑭ 相同 input_hash 7 天内直接复用');
      expect(find.text('AI 解析 · 缓存复用（§3.3）'), findsOneWidget);

      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      await _waitForEntryCount(tester, harness, 2);

      final rows = await harness.db.select(harness.db.entries).get();
      final parses = await harness.db.select(harness.db.aiParses).get();
      expect(parses, hasLength(1));
      expect(rows.map((r) => r.aiParseId).toSet(), {parses.single.id},
          reason: '缓存复用共享同一 ai_parses.id（§5.6⑭）');
      expect(rows.map((r) => r.source), everyElement('photo'));

      // 两次确认各登记一条附件行（逐笔审计元数据），内容哈希同源、均已焚。
      final atts = await _waitForBurnedAttachments(tester, harness, 2, telemetry: telemetry);
      expect(atts.map((a) => a.contentHash), everyElement(_fixtureHash));
      expect(source.createdPaths, hasLength(2),
          reason: '两次拍照各落一份临时文件');
      for (final path in source.createdPaths) {
        expect(File(path).existsSync(), isFalse, reason: '临时文件均已焚毁');
      }
    },
  );

  testWidgets(
    '上云关（§3.7 默认）+端侧粗估可用：解析器零调用（字节不出端）、无 ai_parses、'
    '落库 kind=food、确认后照常即焚',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      harness.rawInputOpen = false;
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult());
      final estimator = FakeCaptureOnDeviceEstimator(
        const [_onDeviceEstimateResult],
      );
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      // 隐私提示（§3.7 关=字节不出端口径文案）。
      expect(
          find.text('原图不出端（§3.7）：端侧粗估 + 人工确认，确认后即焚'),
          findsOneWidget);

      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      // ── 字节不出端断言（§3.7）：云端解析路径整体不可达 ──
      expect(parser.calls, 0,
          reason: '§3.7 raw_input 关：图片字节不出端，云端识别不可走');
      expect(estimator.calls, 1, reason: '§3.7 关=端侧粗估 + 人工确认');
      expect(estimator.requests.single.inputHash, _fixtureHash);
      expect(compressor.calls, 1, reason: '压缩在端侧完成（§3.3）');

      // ── 确认卡断言：端侧粗估徽标、仅热量初值 ──
      expect(find.text('拍照端侧粗估初值（§3.7）'), findsOneWidget);
      expect(find.text('480'), findsOneWidget);
      expect(find.text('家常豆腐'), findsOneWidget);

      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.source, 'photo');
      expect(entry.kind, 'food',
          reason: '§5.2① 仅热量=food（端侧粗估只产热量初值）');
      expect(entry.aiParseId, isNull,
          reason: '§3.7/§5.6⑭ 端侧路径无云端解析，ai_parses 不落行');

      // ai_parses 全空：粗估结果不进云端留痕（§3.7 关=仅落结构化结果）。
      expect((await harness.db.select(harness.db.aiParses).get()), isEmpty);

      // 即焚照常（原图即焚不受开关影响，§3.7）。
      final atts = await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);
      expect(atts.single.status, cdb.kAttachmentStatusBurned);
      expect(atts.single.entryId, entryId);
      expect(File(source.createdPaths.single).existsSync(), isFalse);

      // 漏斗 outcome=on_device（§11.2 任务 5）。
      final parseResultEvent = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoParseResult);
      expect(parseResultEvent.props['outcome'], 'on_device');
    },
  );

  testWidgets(
    '上云关+端侧无法估计：自动转人工确认；确认前即焚未发生（文件仍在、无附件行），'
    '手填落库 source=photo 后才焚（§3.7/§11.2 任务 4）',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      harness.rawInputOpen = false;
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult());
      // 无脚本 → 恒 null=无法端侧估计（缺省最严兜底）。
      final estimator = FakeCaptureOnDeviceEstimator();
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureFallbackBannerKey));
      expect(find.textContaining('原文上云已关闭'), findsOneWidget,
          reason: '§3.7 关=端侧粗估 + 人工确认的降级口径透出');

      // ── 绝不丢已拍数据（§11.2 任务 4）：确认前即焚未发生 ──
      expect((await harness.db.select(harness.db.attachments).get()), isEmpty,
          reason: '未确认不登记：无附件行');
      expect(source.createdPaths, hasLength(1));
      expect(File(source.createdPaths.single).existsSync(), isTrue,
          reason: '确认前原图不焚不丢：临时文件仍在');
      expect(parser.calls, 0, reason: '§3.7 关：云端解析不可达');
      expect(estimator.calls, 1);

      // 手填热量 + 金额 → 保存（source 记 photo：本笔来自拍照通道，§5.2①）。
      await _enterText(tester,
          const ValueKey('capture_manual_kcal_field'), '480');
      await _enterText(tester,
          const ValueKey('capture_manual_amount_field'), '18.50');
      await tester.tap(find.byKey(captureSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.source, 'photo',
          reason: '§11.2 任务 4：降级手填同样保留拍照通道语义');
      expect(entry.kind, 'mixed');
      expect(entry.aiParseId, isNull, reason: '人工确认无 AI 溯源');

      // 确认落库成功后才焚（行 + 文件）。
      final atts = await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);
      expect(atts.single.entryId, entryId);
      expect(atts.single.status, cdb.kAttachmentStatusBurned);
      expect(File(source.createdPaths.single).existsSync(), isFalse);

      // 漏斗 outcome=manual（§11.2 任务 5）。
      final parseResultEvent = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoParseResult);
      expect(parseResultEvent.props['outcome'], 'manual');
    },
  );

  testWidgets(
    '识别失败降级（§7.4/§11.2 任务 4）：自动手填、确认前原件保留不焚、确认后焚毁、'
    '漏斗 outcome=fallback 带错误类型码',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult())
        ..failure = const CaptureStructuredFailure(
          code: CaptureFailureCode.provider,
          message: '供应商不可用',
        );
      final estimator = FakeCaptureOnDeviceEstimator();
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      await tester.tap(find.byKey(capturePhotoCameraKey));
      await _pumpUntilFound(tester, find.byKey(captureFallbackBannerKey));
      expect(find.textContaining('供应商不可用'), findsOneWidget,
          reason: '§7.4 结构化失败文案透出（自动切换手填）');

      // ── 确认前即焚未发生（绝不丢已拍数据，§11.2 任务 4）──
      expect((await harness.db.select(harness.db.attachments).get()), isEmpty);
      expect(File(source.createdPaths.single).existsSync(), isTrue,
          reason: '失败路径原件保留：临时文件仍在（确认后才焚）');

      // 手填 → 保存。
      await _enterText(tester,
          const ValueKey('capture_manual_kcal_field'), '550');
      await _enterText(tester,
          const ValueKey('capture_manual_amount_field'), '18.50');
      await tester.tap(find.byKey(captureSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.source, 'photo');
      expect(entry.aiParseId, isNull, reason: '失败路径无 AI 溯源');

      // 确认后才焚。
      final atts = await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);
      expect(atts.single.entryId, entryId);
      expect(atts.single.status, cdb.kAttachmentStatusBurned);
      expect(File(source.createdPaths.single).existsSync(), isFalse);

      // 漏斗 outcome=fallback + 错误类型码（§3.9：只记类型不记内容）。
      final parseResultEvent = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoParseResult);
      expect(parseResultEvent.props['outcome'], 'fallback');
      expect(parseResultEvent.props['code'], 'provider');
    },
  );

  testWidgets(
    '相册选择路径（§11.2 任务 1/2）：pickGallery 分流、photo_capture_open '
    'from_camera=false、全程等价拍照语义',
    (tester) async {
      final harness = _Harness();
      if (!await harness.init()) return;
      addTearDown(harness.close);
      final source = FakeImageSource(writeTempFile: true);
      final compressor = FakeImageCompressor();
      final parser = FakeCapturePhotoParser(_photoParseResult());
      final estimator = FakeCaptureOnDeviceEstimator();
      final telemetry = RecordingTelemetry();

      await _pumpPhotoCapture(
        tester,
        harness,
        source: source,
        compressor: compressor,
        photoParser: parser,
        estimator: estimator,
        telemetry: telemetry,
      );

      // 入口「相册选择」→ 同一压缩/识别/确认链路。
      await tester.tap(find.byKey(capturePhotoGalleryKey));
      await _pumpUntilFound(tester, find.byKey(captureConfirmCardKey));
      await tester.pump(const Duration(milliseconds: 900));

      expect(source.galleryCalls, 1, reason: '相册分流（§11.2 任务 1）');
      expect(source.captureCalls, 0, reason: '拍照入口未被触发');
      expect(compressor.calls, 1);
      expect(parser.calls, 1);
      expect(find.text('拍照识别初值（§11.2）'), findsOneWidget);

      await tester.tap(find.byKey(captureConfirmSubmitKey));
      await tester.pump();
      final entryId = await _waitForEntryCount(tester, harness, 1);

      final entry = await (harness.db.select(harness.db.entries)
            ..where((t) => t.id.equals(entryId)))
          .getSingle();
      expect(entry.source, 'photo');

      final atts = await _waitForBurnedAttachments(tester, harness, 1, telemetry: telemetry);
      expect(atts.single.status, cdb.kAttachmentStatusBurned);
      expect(File(source.createdPaths.single).existsSync(), isFalse);

      final open = telemetry.events.singleWhere((e) =>
          e.kind == dom.TelemetryKind.funnel &&
          e.name == CapturePhotoFunnel.photoCaptureOpen);
      expect(open.props['from_camera'], false,
          reason: 'photo_capture_open 分流标记：相册=false');
    },
  );
}
