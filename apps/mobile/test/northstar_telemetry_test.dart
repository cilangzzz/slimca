// W9-10 北极星埋点核对配套测试（§11.1 W9-10「北极星实测」、§12 北极星口径）。
//
// 覆盖两块新增埋点的口径正确性（本机可测的部分；真机数字一律「待真机」）：
//
// 1. 次日留存锚点（ensureFirstOpenDay，§12「次日留存」）：
//    - 首次启动 → first_open（isFirstOpen=true、dayOffset=0、settings 落值）；
//    - 同日/次日/N 日后再启动 → app_open（dayOffset=0/1/N）；
//    - 存储值损坏 → 视同未存储重新锚定（settings ⑲ 本地件自愈）。
// 2. 真机帧率聚合（FrameStats / FrameTelemetry.reportBatch，§9.4 帧预算）：
//    - 丢帧判定（totalSpan > 1/60s）、build ≤8ms / raster ≤16ms 超预算计数；
//    - 批次聚合 metric 落盘：frame_raster_ms 恒发、frame_dropped 有丢帧才发；
//    - 标签只含标量（§3.9 隐私口径）。
//
// 内存 Drift 库（禁真实 IO/网络）；宿主缺 sqlite3 运行库时温和跳过
// （raw_input_switch_test 同口径）。FrameTiming 用 dart:ui 测试工厂构造
// （合成帧时间戳，纯 fake clock，跨宿主稳定）。

import 'dart:ui' show FrameTiming;

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/app/bootstrap.dart';
import 'package:slimca/telemetry/telemetry.dart';

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 raw_input_switch 口径）。
bool _isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库；宿主缺 sqlite3 运行库时返回 null（调用方跳过测试）。
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

/// 读取 settings 表 first_open_day 键的原值（无则 null）。
Future<String?> _storedFirstOpenDay(db.AppDatabase database) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals('first_open_day')))
      .getSingleOrNull();
  return row?.value;
}

/// 合成 FrameTiming（dart:ui 测试工厂；微秒时间戳，epoch 任取）。
///
/// 时间轴按真实帧物理序排布：vsync → build(buildUs) → raster(rasterUs)，
/// totalSpan = buildStart + buildUs + rasterUs = 1ms + buildUs + rasterUs
/// ——丢帧判定（>1/60s）、build/raster 预算（8ms/16ms）各由对应入参决定。
FrameTiming _frame({required int buildUs, required int rasterUs}) {
  final buildStart = 1000;
  final buildFinish = buildStart + buildUs;
  final rasterStart = buildFinish;
  final rasterFinish = rasterStart + rasterUs;
  return FrameTiming(
    vsyncStart: 0,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  group('次日留存锚点 ensureFirstOpenDay（§12 北极星，W9-10）', () {
    late db.AppDatabase? databaseRef;

    setUp(() async {
      databaseRef = await _tryOpenMemoryDatabase();
    });

    tearDown(() async {
      await databaseRef?.close();
    });

    test('首次启动：isFirstOpen=true、dayOffset=0，settings 落当日', () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      final anchor = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 11, 9, 30),
      );
      expect(anchor.isFirstOpen, isTrue);
      expect(anchor.dayOffset, 0);
      expect(anchor.firstOpenDay, '2027-01-11');
      expect(await _storedFirstOpenDay(database), '"2027-01-11"',
          reason: 'settings ⑲ value 一律 JSON（字符串带引号）');
    });

    test('同日/次日/N 日再启动：isFirstOpen=false，dayOffset 逐日递增', () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 11),
      );

      final sameDay = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 11, 23, 59),
      );
      expect(sameDay.isFirstOpen, isFalse, reason: '非首次启动 → app_open');
      expect(sameDay.dayOffset, 0);
      expect(sameDay.firstOpenDay, '2027-01-11');

      final nextDay = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 12),
      );
      expect(nextDay.dayOffset, 1, reason: '次日启动 → 次日留存分子的判定锚');

      final laterDay = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 24),
      );
      expect(laterDay.dayOffset, 13);
      expect(laterDay.firstOpenDay, '2027-01-11', reason: '锚点恒定不漂移');
    });

    test('存储值损坏：视同未存储，重新锚定为当日（本地件自愈）', () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      await database.into(database.settings).insertOnConflictUpdate(
            db.Setting(key: 'first_open_day', value: '不是 JSON'),
          );
      final anchor = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 11),
      );
      expect(anchor.isFirstOpen, isTrue, reason: '坏值 → 重新锚定');
      expect(anchor.dayOffset, 0);
      expect(anchor.firstOpenDay, '2027-01-11');
    });

    test('非法日历日（形状对但语义坏）：同样重新锚定', () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      await database.into(database.settings).insertOnConflictUpdate(
            db.Setting(key: 'first_open_day', value: '"9999-99-99"'),
          );
      final anchor = await ensureFirstOpenDay(
        database,
        now: () => DateTime(2027, 1, 11),
      );
      expect(anchor.isFirstOpen, isTrue, reason: '非法日历日视同未存储');
      expect(anchor.firstOpenDay, '2027-01-11');
    });
  });

  group('真机帧率聚合 FrameStats（§9.4 帧预算，数字待真机实测）', () {
    test('预算内帧：零丢帧、零超预算（60Hz 满帧基准）', () {
      // totalSpan = 1ms + buildUs + rasterUs：15ms / 11ms，均 < 16.67ms。
      final stats = FrameStats.of([
        _frame(buildUs: 4000, rasterUs: 10000),
        _frame(buildUs: 2000, rasterUs: 8000),
      ]);
      expect(stats.totalFrames, 2);
      expect(stats.droppedFrames, 0);
      expect(stats.buildOverBudgetFrames, 0);
      expect(stats.rasterOverBudgetFrames, 0);
      expect(stats.maxBuildMs, closeTo(4.0, 0.001));
      expect(stats.maxRasterMs, closeTo(10.0, 0.001));
    });

    test('超预算帧：丢帧（totalSpan>1/60s）、build>8ms、raster>16ms 分行计数', () {
      final stats = FrameStats.of([
        // 丢帧：totalSpan 17ms > 16.67ms；build/raster 本身都在预算内。
        _frame(buildUs: 4000, rasterUs: 12000),
        // raster 超 16ms（totalSpan 20ms 同帧必丢）。
        _frame(buildUs: 2000, rasterUs: 17000),
        // build 超 8ms（totalSpan 14ms 不丢帧）。
        _frame(buildUs: 9000, rasterUs: 4000),
      ]);
      expect(stats.totalFrames, 3);
      expect(stats.droppedFrames, 2, reason: '丢帧判定=totalSpan>1/60s（DevTools 同口径）');
      expect(stats.buildOverBudgetFrames, 1, reason: '§9.4 build ≤8ms');
      expect(stats.rasterOverBudgetFrames, 1, reason: '§9.4 raster ≤16ms');
      expect(stats.maxBuildMs, closeTo(9.0, 0.001));
      expect(stats.maxRasterMs, closeTo(17.0, 0.001));
    });

    test('reportBatch：frame_raster_ms 恒发、frame_dropped 有丢帧才发（标量标签）',
        () async {
      final dropped = RecordingTelemetryService();
      await FrameTelemetry.reportBatch(dropped, [
        // totalSpan 17ms：丢帧 1 帧；raster 12ms/build 4ms 均在预算内。
        _frame(buildUs: 4000, rasterUs: 12000),
        _frame(buildUs: 2000, rasterUs: 8000),
      ]);
      final raster = dropped.byName(TelemetryMetricName.frameRasterMs);
      expect(raster, hasLength(1));
      expect(raster.single.kind, TelemetryKind.metric);
      expect(raster.single.props['value'], closeTo(12.0, 0.001));
      expect(raster.single.props['unit'], 'ms');
      expect(raster.single.props['frames'], 2);
      expect(raster.single.props['dropped'], 1);
      expect(dropped.byName(TelemetryMetricName.frameDropped), hasLength(1),
          reason: '批内有丢帧 → 追加丢帧计数 metric');
      final droppedMetric = dropped.byName(TelemetryMetricName.frameDropped).single;
      expect(droppedMetric.props['value'], 1);
      expect(droppedMetric.props['frames'], 2);

      final clean = RecordingTelemetryService();
      await FrameTelemetry.reportBatch(clean, [
        _frame(buildUs: 4000, rasterUs: 10000),
      ]);
      expect(clean.byName(TelemetryMetricName.frameRasterMs), hasLength(1));
      expect(clean.byName(TelemetryMetricName.frameDropped), isEmpty,
          reason: '零丢帧批次不追加 frame_dropped（JSONL 防膨胀）');
    });

    test('reportBatch：空批次不落任何 metric', () async {
      final telemetry = RecordingTelemetryService();
      await FrameTelemetry.reportBatch(telemetry, const <FrameTiming>[]);
      expect(telemetry.events, isEmpty);
    });
  });

  group('北极星漏斗事件名覆盖（§11.1 W9-10 口径核对，防回归）', () {
    test('次日留存/录入漏斗/帧率三口径的事件名常量在位', () {
      // 次日留存：first_open（D0 锚）+ app_open（day_offset 每次启动）。
      expect(TelemetryFunnel.firstOpen, 'first_open');
      expect(TelemetryFunnel.appOpen, 'app_open');
      // 录入漏斗「打开→输入→解析→确认」：打开起点（W9-10 补齐）。
      expect(TelemetryFunnel.captureOpen, 'capture_open');
      // 护栏耗时指标：文字路径打开→确认 ≤8s（P50）。
      expect(
        TelemetryMetricName.captureOpenToConfirmMs,
        'capture_open_to_confirm_ms',
      );
      // 真机帧率指标（真机 profile/release 有效）。
      expect(TelemetryMetricName.frameRasterMs, 'frame_raster_ms');
      expect(TelemetryMetricName.frameDropped, 'frame_dropped');
    });
  });
}
