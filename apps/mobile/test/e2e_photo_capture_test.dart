// Slimca W11-12 拍照通道 e2e（§11.2 W11-12「拍照通道」、§3.3 拍照通道、
// §3.7 数据主权、§5.6㉑ attachments）：
//
// 壳层冒烟断言「通道 sheet『拍』段可达」+ 拍照路径全链路两条分支：
//
// ① raw_input 关（§3.7 默认）→ 字节不出端 → 端侧无法估计（缺省
//    NoOnDeviceEstimator 最严兜底）→ 转人工降级（§7.4/§11.2 任务 4「绝不丢
//    已拍数据」）→ 跨通道接续：切「写」通道降级手填表单 → 保存 →
//    source=photo 落库 + 附件登记即焚（FakeCaptureAttachmentStore）+ 临时
//    文件删除 + 拍照漏斗（photo_capture_open/manual/photo_confirm + ≤15s
//    护栏 metric）；
// ② raw_input 开 → 云端识别（FakeCapturePhotoParser 脚本化，§7.4）→ 确认卡
//    复用（§9.3#4）→ 确认落库 → source=photo/kind=mixed + ai_parses 留痕
//    （input_kind=photo、input_hash=sha256(压缩字节) §5.6⑭）+ 即焚同上 +
//    漏斗 success 分支。
//
// 测试装配与 e2e_voice 同口径：内存 Drift 库 + 固定 device_id HlcClock
// override + bootstrap() 同款网关工厂；拍照注入点全部 Fake（fixture 字节
// kFakePhotoBytes + 脚本化解析器 + 内存附件表 + 录制型遥测），硬规则：测试
// 禁止真实相机/网络（§11.2）。

import 'dart:io';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart'
    show
        FakeCaptureAttachmentStore,
        FakeCapturePhotoParser,
        FakeImageCompressor,
        FakeImageSource,
        captureAttachmentStoreProvider,
        captureGatewayProvider,
        captureImageCompressorProvider,
        captureImageSourceProvider,
        captureParserProvider,
        capturePhotoParserProvider,
        capturePhotoTelemetryProvider,
        captureRawInputCloudEnabledProvider,
        createCaptureGateway,
        CaptureParsedItem,
        CaptureParsedLine,
        CaptureParseResult,
        kFakePhotoBytes;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slimca/ai/capture_parser_factory.dart';
import 'package:slimca/app/bootstrap.dart' show ensureDefaultLedgers;
import 'package:slimca/app/providers.dart';
import 'package:slimca/main.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻既有测试口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
///
/// `closeStreamsSynchronously: true`：与 widget_test 同口径——drift 流取消
/// 后的延迟清缓存 Timer 在 fake_async 区无人清空会挂起测试。
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

/// 小步轮询等待控件出现（拍照呼吸态/确认卡 count-up 为循环动画，
/// pumpAndSettle 永不收敛——与 widget_test 同策略）。
///
/// 每轮在 pump 之外补一次 runAsync 短暂逃出：拍照链含真实文件 IO（Fake
/// 落盘/即焚删除），testWidgets 的 FakeAsync zone 不投递 IO 事件——runAsync
/// 让真实事件循环推进一拍，pump 再冲刷其后的 fake-zone 微任务链，两者交替。
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder,
) async {
  for (var i = 0; i < 240; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('等待控件超时: $finder');
}

/// 拍照提交链收口桥：photo_confirm 终点在「登记即焚 + 临时文件删除（真实
/// IO）」之后发出（§11.2 任务 3/5）。FakeAsync zone 不投递 IO 事件——
/// runAsync 逃出交给真实事件循环、pump 冲刷其后的 fake-zone 微任务链，
/// 交替至漏斗终点可断言；随后由调用方 pumpAndSettle 收拢抽屉收起帧。
Future<void> _waitForPhotoConfirm(
  WidgetTester tester,
  RecordingTelemetry telemetry,
) async {
  for (var i = 0; i < 240; i++) {
    if (telemetry.funnels.any((r) => r.$1 == 'photo_confirm')) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('拍照提交链未收口：photo_confirm 漏斗终点未发出');
}

/// 录制型遥测（§11.2 任务 5「拍照漏斗接 FileTelemetryService」的接缝断言）：
/// 实现 core_domain TelemetryService 同款接口，只录制不落盘——断言事件名/
/// props 形状（标量枚举/耗时，§3.9 隐私口径）。
class RecordingTelemetry implements TelemetryService {
  /// funnel 事件按序录制（name, props）。
  final List<(String, Map<String, Object?>?)> funnels = [];

  /// metric 按序录制（name, value, tags）。
  final List<(String, num, Map<String, Object?>?)> metrics = [];

  @override
  Future<void> funnel(String name, {Map<String, Object?>? props}) async {
    funnels.add((name, props));
  }

  @override
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  }) async {
    metrics.add((name, value, tags));
  }

  @override
  Future<void> crash(
    Object error,
    StackTrace? stackTrace, {
    String? source,
  }) async {}

  @override
  Future<void> flush() async {}

  /// 按事件名取漏斗事件（缺省第一条）。
  Map<String, Object?>? propsOf(String name, [int index = 0]) {
    final rows = funnels.where((r) => r.$1 == name).toList();
    if (rows.length <= index) return null;
    return rows[index].$2;
  }
}

/// 唤起通道抽屉并切「拍」段（§11.2 任务 2「『拍』段可达」壳层冒烟锚）。
Future<void> _openPhotoChannel(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  await tester.pumpAndSettle();
  // 三通道切换条（写/说/拍，§3.3）：拍段 chip 可达。
  expect(find.byKey(const Key('capture_channel_text')), findsOneWidget);
  expect(find.byKey(const Key('capture_channel_voice')), findsOneWidget);
  expect(find.byKey(const Key('capture_channel_photo')), findsOneWidget);
  await tester.tap(find.byKey(const Key('capture_channel_photo')));
  await tester.pumpAndSettle();
  // 拍通道面板渲染（§11.2 任务 2）：标题 + 拍照/相册双入口 + 隐私提示。
  expect(find.text('拍一笔'), findsOneWidget);
  expect(find.byKey(const Key('capture_photo_camera')), findsOneWidget);
  expect(find.byKey(const Key('capture_photo_gallery')), findsOneWidget);
  expect(find.byKey(const Key('capture_photo_privacy_hint')), findsOneWidget);
}

void main() {
  testWidgets(
      'W11-12 拍照 e2e（raw_input 关）：拍段可达 → 端侧无法估计转人工 → 跨通道'
      '手填接续 → source=photo 落库 + 登记即焚 + 漏斗（§3.7/§11.2 任务 2/3/4/5）',
      (WidgetTester tester) async {
    // 放大视口：抽屉表单/降级表单一屏放下，免滚动命中（与既有 e2e 同口径）。
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) {
      // Windows 宿主缺 sqlite3.dll：跳过（集成机有库，e2e 照常执行）。
      return;
    }
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);
    await database.delete(database.syncOutbox).go();

    // Fake 注入集（§11.2 硬规则：禁真实相机/网络）：fixture 字节落真实临时
    // 文件（即焚「文件已删除」断言可验证）+ 内存附件表 + 录制型遥测；
    // raw_input 上云开关用缺省（关）+ 端侧粗估用缺省（NoOnDeviceEstimator=
    // 最严兜底）——不 override，测的就是缺省装配行为（§3.7/§6.1）。
    final imageSource = FakeImageSource(writeTempFile: true);
    final attachmentStore = FakeCaptureAttachmentStore();
    final telemetry = RecordingTelemetry();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider.overrideWithValue(
            createCaptureGateway(db: database, clock: clock),
          ),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          captureImageSourceProvider.overrideWithValue(imageSource),
          captureImageCompressorProvider
              .overrideWithValue(FakeImageCompressor()),
          captureAttachmentStoreProvider.overrideWithValue(attachmentStore),
          capturePhotoTelemetryProvider.overrideWithValue(telemetry),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Slimca'), findsOneWidget);

    // ── 拍段可达 + §3.7 默认口径隐私提示（原图不出端）──────────────────
    await _openPhotoChannel(tester);
    expect(
      find.textContaining('原图不出端'),
      findsOneWidget,
      reason: 'raw_input 关（§3.7 默认）隐私提示口径',
    );

    // ── 发起拍照（FakeImageSource 出 fixture 字节 + 真实临时文件）──────
    await tester.tap(find.byKey(const Key('capture_photo_camera')));
    await _pumpUntilFound(
      tester,
      find.byKey(const Key('photo_capture_fallback_banner')),
    );
    expect(imageSource.captureCalls, 1, reason: '拍照入口分流（from_camera=true）');
    expect(
      find.textContaining('原文上云已关闭'),
      findsOneWidget,
      reason: '端侧无法估计（缺省 NoOnDeviceEstimator）→ 转人工确认（§3.7）',
    );

    // ── 跨通道降级接续（§11.2 任务 4「切写通道手填，不丢已拍数据」）────
    await tester.tap(find.byKey(const Key('photo_capture_switch_text')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('capture_fallback_banner')),
      findsOneWidget,
      reason: '写通道复用共享控制器状态渲染降级表单（§7.4 原输入保留）',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('capture_fallback_title')),
        matching: find.byType(TextField),
      ),
      '拍照降级午餐',
    );
    await tester.pump();
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('capture_manual_kcal_field')),
        matching: find.byType(TextField),
      ),
      '550',
    );
    await tester.pump();
    expect(find.text('保存'), findsOneWidget);
    await tester.tap(find.text('保存'));
    // 提交链含真实文件 IO（即焚删除），收口以 photo_confirm 终点为判据。
    await _waitForPhotoConfirm(tester, telemetry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_fallback_banner')), findsNothing,
        reason: '提交成功后抽屉收起（§4.3）');

    // ── 落库口径（§5.2①②：source=photo 降级路径同样成立）────────────
    final entries = await database.select(database.entries).get();
    expect(entries.length, 1);
    final entry = entries.single;
    expect(entry.source, 'photo',
        reason: '拍照降级路径 pendingSource 记 photo（§5.2①/§11.2）');
    expect(entry.kind, 'food', reason: '仅热量行 → food（§5.2① kind 推导）');
    expect(entry.title, '拍照降级午餐');
    expect(entry.status, 'confirmed');
    expect(entry.aiParseId, isNull,
        reason: '降级手填无云端解析 → 无 ai_parses 溯源');

    final lines = await database.select(database.entryLines).get();
    expect(lines.length, 1, reason: '仅热量行（§5.3 facet 行）');
    expect(lines.single.type, 'calorie');
    expect(lines.single.amount, 550);

    // ── 即焚（§3.7/§11.2 任务 3）：确认落库成功 → 登记 burned + 文件删除
    expect(attachmentStore.drafts.length, 1, reason: '附件登记恰一次');
    final draft = attachmentStore.drafts.single;
    expect(draft.entryId, entry.id, reason: 'attachments.entry_id → 本次事件');
    expect(draft.contentHash, sha256.convert(kFakePhotoBytes).toString(),
        reason: 'content_hash=sha256(压缩字节)（§5.6㉑）');
    expect(draft.kind, 'photo');
    expect(attachmentStore.burnedIds, isNotEmpty, reason: '登记即 burned');
    expect(draft.localPath, isNotNull);
    expect(
      File(draft.localPath!).existsSync(),
      isFalse,
      reason: '临时文件已焚（即焚文件半边，§3.7）',
    );

    // ── 拍照漏斗（§11.2 任务 5）：open → manual → confirm + ≤15s 护栏 ──
    expect(telemetry.funnels.map((r) => r.$1).toList(), <String>[
      'photo_capture_open',
      'photo_parse_result',
      'photo_confirm',
    ], reason: '拍照漏斗三步按序');
    expect(telemetry.propsOf('photo_capture_open')?['from_camera'], isTrue);
    expect(telemetry.propsOf('photo_parse_result')?['outcome'], 'manual');
    expect(telemetry.propsOf('photo_confirm')?['within_guard'], isTrue,
        reason: '全程 ≤15s 护栏（§2.3 拍照路径）');
    expect(
      telemetry.metrics
          .where((m) => m.$1 == TelemetryMetricName.captureOpenToConfirmMs),
      isNotEmpty,
      reason: '护栏 metric 复用 capture_open_to_confirm_ms（tags.path=photo）',
    );
    expect(
      telemetry.metrics
          .firstWhere((m) => m.$1 == TelemetryMetricName.captureOpenToConfirmMs)
          .$3?['path'],
      'photo',
    );
  });

  testWidgets(
      'W11-12 拍照 e2e（raw_input 开）：相册 → 云端识别 → 确认卡复用 → 确认落库'
      '（kind=mixed + ai_parses 留痕 + 即焚 + 漏斗 success）（§3.7/§5.6⑭/§11.2）',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final database = await _tryOpenMemoryDatabase();
    if (database == null) return;
    addTearDown(database.close);

    const deviceId = 'ABCDEF123456';
    final clock = HlcClock(deviceId: deviceId);
    await ensureDefaultLedgers(database, clock);
    await database.delete(database.syncOutbox).go();

    final imageSource = FakeImageSource(writeTempFile: true);
    final photoParser = FakeCapturePhotoParser(const CaptureParseResult(
      title: '红烧肉套餐',
      parseNotes: '测试桩（§7.2 受约束输出形状）',
      lines: [
        CaptureParsedLine(
          typeWire: 'calorie',
          amountKcal: 600,
          confidence: 0.55,
          categoryHint: '餐饮',
          items: [
            CaptureParsedItem(
              name: '红烧肉',
              portionG: 200,
              kcal: 500,
              confidence: 0.5,
              refSource: 'baidu',
            ),
          ],
        ),
        CaptureParsedLine(
          typeWire: 'money',
          amountMinor: 2500,
          confidence: 0.5,
          categoryHint: '餐饮',
          currency: 'CNY',
        ),
      ],
      provider: 'fake-photo',
      model: 'fake-model',
      promptVersion: 'photo-w11-12',
      latencyMs: 100,
      costMicro: 0,
      confidence: 0.55,
    ));
    final attachmentStore = FakeCaptureAttachmentStore();
    final telemetry = RecordingTelemetry();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          hlcClockProvider.overrideWithValue(clock),
          captureGatewayProvider.overrideWithValue(
            createCaptureGateway(db: database, clock: clock),
          ),
          captureParserProvider.overrideWithValue(createCaptureParser()),
          captureImageSourceProvider.overrideWithValue(imageSource),
          captureImageCompressorProvider
              .overrideWithValue(FakeImageCompressor()),
          capturePhotoParserProvider.overrideWithValue(photoParser),
          captureAttachmentStoreProvider.overrideWithValue(attachmentStore),
          capturePhotoTelemetryProvider.overrideWithValue(telemetry),
          // §3.7 raw_input 开（用户显式选择）：允许本次识别携带压缩字节上云。
          captureRawInputCloudEnabledProvider.overrideWithValue(() => true),
        ],
        child: const SlimcaApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // ── 拍段可达 + 开关开启口径隐私提示 ───────────────────────────────
    await _openPhotoChannel(tester);
    expect(
      find.textContaining('原图仅用于本次识别'),
      findsOneWidget,
      reason: 'raw_input 开（§3.7 显式开启）隐私提示口径',
    );

    // ── 相册入口（FakeImageSource gallery 分流）→ 云端识别 → 确认卡 ──
    await tester.tap(find.byKey(const Key('capture_photo_gallery')));
    await _pumpUntilFound(tester, find.byKey(const Key('capture_confirm_submit')));
    expect(imageSource.galleryCalls, 1, reason: '相册入口分流（from_camera=false）');
    expect(photoParser.calls, 1, reason: '云端识别恰一次（闸门放行后）');
    expect(photoParser.requests.single.inputHash,
        sha256.convert(kFakePhotoBytes).toString(),
        reason: 'input_hash=sha256(压缩字节)（§5.6⑭ 缓存键口径）');
    // count-up 800ms 播完到终值（§9.3#4）。
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('红烧肉套餐'), findsOneWidget, reason: 'AI 初值预填标题');
    expect(find.text('600'), findsOneWidget, reason: '热量 count-up 终值');
    expect(find.text('¥25.00'), findsOneWidget, reason: '金额 count-up 终值');

    // ── 确认落库（共享控制器 submitPendingCapture：即焚收口）─────────
    await tester.tap(find.byKey(const Key('capture_confirm_submit')));
    // 提交链含真实文件 IO（即焚删除），收口以 photo_confirm 终点为判据。
    await _waitForPhotoConfirm(tester, telemetry);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('capture_confirm_submit')), findsNothing,
        reason: '提交成功后抽屉收起（§4.3）');

    // ── 落库口径（§5.2①②：source=photo、双行=mixed、ai_parses 留痕）──
    final entries = await database.select(database.entries).get();
    expect(entries.length, 1);
    final entry = entries.single;
    expect(entry.source, 'photo');
    expect(entry.kind, 'mixed', reason: 'calorie+money 双行=mixed（§5.2①）');
    expect(entry.status, 'confirmed');
    expect(entry.aiParseId, isNotNull, reason: '云路径 ai_parses 溯源');

    final lines = await database.select(database.entryLines).get();
    expect(lines.length, 2, reason: 'calorie 行 + money 行（§5.3 facet 拆行）');
    final calorieLine = lines.singleWhere((l) => l.type == 'calorie');
    final moneyLine = lines.singleWhere((l) => l.type == 'money');
    expect(calorieLine.amount, 600);
    expect(calorieLine.confidence, isNotNull, reason: 'AI 产出行必填（§5.2②）');
    expect(moneyLine.amount, 2500, reason: '分存储（§5.1）');

    final foodItems = await database.select(database.foodItems).get();
    expect(foodItems.single.name, '红烧肉', reason: '§5.2③ food_items 逐菜品');
    expect(foodItems.single.refSource, 'baidu');

    final parses = await database.select(database.aiParses).get();
    expect(parses.length, 1, reason: 'ai_parses 留痕（§5.6⑭）');
    expect(parses.single.inputKind, 'photo', reason: 'input_kind=photo');
    expect(parses.single.inputHash, sha256.convert(kFakePhotoBytes).toString());

    // ── 即焚（§3.7/§11.2 任务 3）────────────────────────────────────
    expect(attachmentStore.drafts.length, 1);
    final draft = attachmentStore.drafts.single;
    expect(draft.entryId, entry.id);
    expect(draft.contentHash, sha256.convert(kFakePhotoBytes).toString());
    expect(attachmentStore.burnedIds, isNotEmpty, reason: '登记即 burned');
    expect(File(draft.localPath!).existsSync(), isFalse, reason: '临时文件已焚');

    // ── 拍照漏斗（§11.2 任务 5）：open → success → confirm ───────────
    expect(telemetry.funnels.map((r) => r.$1).toList(), <String>[
      'photo_capture_open',
      'photo_parse_result',
      'photo_confirm',
    ]);
    expect(telemetry.propsOf('photo_capture_open')?['from_camera'], isFalse,
        reason: '相册入口 from_camera=false');
    expect(telemetry.propsOf('photo_parse_result')?['outcome'], 'success');
    expect(telemetry.propsOf('photo_confirm')?['within_guard'], isTrue);
    expect(
      telemetry.metrics
          .firstWhere((m) => m.$1 == TelemetryMetricName.captureOpenToConfirmMs)
          .$3?['path'],
      'photo',
    );
  });
}
