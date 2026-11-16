/// raw_input 上云开关 + 解析装饰链测试（§3.7 数据主权、§3.3 默认关=即用即焚、
/// §12 漏斗「解析请求/成功/失败降级」；§11.1 W7-8 任务验收）。
///
/// 覆盖：
/// - settings 表存取：缺省关 → 写读回环 → 坏 JSON/非布尔回落关（本地件自愈）；
/// - RawInputGateCaptureParser：关=原文不出设备（rawText 被替换为规范化最小
///   集）、开=原文随请求上传；normalized/hash/kind 恒透传；
/// - TelemetryCaptureParser：parse_request / parse_success / parse_fallback
///   事件与 props（仅枚举/开关位/耗时标量，§3.9）。
///
/// 内存 Drift 库（禁真实 IO/网络）；宿主缺 sqlite3 运行库时温和跳过。
library;

import 'dart:async';
import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/ai/raw_input_gate_capture_parser.dart';
import 'package:slimca/ai/telemetry_capture_parser.dart';
import 'package:slimca/settings/raw_input_setting.dart';
import 'package:slimca/telemetry/telemetry.dart' show TelemetryFunnel;

import 'test_support.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误（复刻 widget_test 口径）。
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

/// 录入型解析器：记录收到的请求、可注入成功/失败。
class FakeParser implements CaptureParser {
  CaptureParseRequest? lastRequest;
  Object? throwOnParse;

  CaptureParseResult get _defaultResult => const CaptureParseResult(
        title: '测试标题',
        lines: [
          CaptureParsedLine(
            typeWire: 'money',
            confidence: 0.9,
            amountMinor: 1800,
          ),
        ],
        provider: 'fake',
        model: 'fake-model',
        promptVersion: 'v0',
        latencyMs: 42,
        costMicro: 0,
        confidence: 0.9,
      );

  @override
  Future<CaptureParseResult> parse(CaptureParseRequest request) async {
    lastRequest = request;
    final failure = throwOnParse;
    if (failure != null) {
      throw failure;
    }
    return _defaultResult;
  }
}

/// 原文（含未规范化空白）与规范化文本（§7.1 normalize 折叠空白）可区分。
CaptureParseRequest _request() => const CaptureParseRequest(
      rawText: '  一杯奶茶  500kcal 花了 18 元  ',
      normalizedText: '一杯奶茶 500kcal 花了 18 元',
      inputHash: 'deadbeef',
      inputKind: 'text',
    );

void main() {
  late db.AppDatabase? databaseRef;

  setUp(() async {
    databaseRef = await _tryOpenMemoryDatabase();
  });

  tearDown(() async {
    await databaseRef?.close();
  });

  group('settings 表存取（§5.6⑲ 本地键值、value 一律 JSON）', () {
    test('缺省关：无行/坏 JSON/非布尔 → false（§3.3 默认关=即用即焚）', () async {
      final database = databaseRef;
      if (database == null) return; // 宿主缺 sqlite3：跳过。

      expect(await loadRawInputCloudEnabled(database), isFalse);

      // 坏 JSON → false（本地件自愈，§6.1）。
      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(
              key: kSettingRawInputCloudEnabled,
              value: '{not-json',
            ),
          );
      expect(await loadRawInputCloudEnabled(database), isFalse);

      // 非布尔 JSON（数字 1）→ false（严格布尔语义）。
      await database.into(database.settings).insertOnConflictUpdate(
            db.SettingsCompanion.insert(
              key: kSettingRawInputCloudEnabled,
              value: '1',
            ),
          );
      expect(await loadRawInputCloudEnabled(database), isFalse);
    });

    test('写读回环：save(true) → load(true)，行值为 JSON true', () async {
      final database = databaseRef;
      if (database == null) return;

      await saveRawInputCloudEnabled(database, enabled: true);
      expect(await loadRawInputCloudEnabled(database), isTrue);

      final row = await (database.select(database.settings)
            ..where(
                (s) => s.key.equals(kSettingRawInputCloudEnabled)))
          .getSingle();
      expect(jsonDecode(row.value), isTrue, reason: 'settings.value 一律 JSON');

      await saveRawInputCloudEnabled(database, enabled: false);
      expect(await loadRawInputCloudEnabled(database), isFalse);
    });
  });

  group('RawInputGateCaptureParser（§3.7 数据主权闸门）', () {
    test('关（默认）：inner 收到 rawText=规范化文本，原文不出设备', () async {
      final inner = FakeParser();
      final gate = RawInputGateCaptureParser(
        inner: inner,
        policy: RawInputPolicy(), // enabled=false 默认关。
      );

      await gate.parse(_request());
      final received = inner.lastRequest!;
      expect(received.rawText, '一杯奶茶 500kcal 花了 18 元',
          reason: '仅发结构化最小集（规范化文本=管线消费形态，§7.1）');
      expect(received.rawText, isNot('  一杯奶茶  500kcal 花了 18 元  '),
          reason: '原文全息内容不出设备（§3.7）');
      expect(received.normalizedText, '一杯奶茶 500kcal 花了 18 元');
      expect(received.inputHash, 'deadbeef',
          reason: '缓存键透传，关闭开关不影响解析与命中（§5.6⑭）');
      expect(received.inputKind, 'text');
    });

    test('开：原文随请求上传（原文留档口径，§3.3）', () async {
      final inner = FakeParser();
      final policy = RawInputPolicy()..enabled = true;
      final gate = RawInputGateCaptureParser(inner: inner, policy: policy);

      await gate.parse(_request());
      expect(inner.lastRequest!.rawText, '  一杯奶茶  500kcal 花了 18 元  ',
          reason: '原文随请求上传（原文留档口径，§3.3）');
      expect(inner.lastRequest!.normalizedText, '一杯奶茶 500kcal 花了 18 元');
    });
  });

  group('TelemetryCaptureParser（§12 漏斗：解析请求/成功/失败降级）', () {
    test('成功：parse_request（开关位）+ parse_success（latency_ms）', () async {
      final telemetry = RecordingTelemetryService();
      final parser = TelemetryCaptureParser(
        inner: FakeParser(),
        telemetry: telemetry,
        rawInputCloud: () => false,
      );

      await parser.parse(_request());

      final request = telemetry.byName(TelemetryFunnel.parseRequest);
      expect(request.length, 1);
      expect(request.single.props, {'input_kind': 'text', 'raw_input_cloud': 0});

      final success = telemetry.byName(TelemetryFunnel.parseSuccess);
      expect(success.length, 1);
      expect(success.single.props, {'latency_ms': 42});
    });

    test('开关位透传：raw_input_cloud=true 记 1（§3.7 可观测）', () async {
      final telemetry = RecordingTelemetryService();
      final parser = TelemetryCaptureParser(
        inner: FakeParser(),
        telemetry: telemetry,
        rawInputCloud: () => true,
      );

      await parser.parse(_request());
      expect(
        telemetry.byName(TelemetryFunnel.parseRequest).single.props,
        {'input_kind': 'text', 'raw_input_cloud': 1},
      );
    });

    test('结构化失败：parse_fallback 记失败类型码并原样上抛（§7.4）', () async {
      final telemetry = RecordingTelemetryService();
      final inner = FakeParser()
        ..throwOnParse = const CaptureStructuredFailure(
          code: CaptureFailureCode.provider,
          message: '供应商故障',
        );
      final parser = TelemetryCaptureParser(
        inner: inner,
        telemetry: telemetry,
      );

      await expectLater(parser.parse(_request()),
          throwsA(isA<CaptureStructuredFailure>()));
      expect(
        telemetry.byName(TelemetryFunnel.parseFallback).single.props,
        {'code': 'provider'},
        reason: '只记失败类型码，message 禁入（§3.9）',
      );
      // 原文/报错内容不得进入任何遥测 props。
      for (final event in telemetry.events) {
        expect(event.props.values, isNot(contains('供应商故障')));
      }
    });

    test('控制器超时穿透：TimeoutException → parse_fallback code=timeout', () async {
      final telemetry = RecordingTelemetryService();
      final inner = FakeParser()..throwOnParse = TimeoutException('t');
      final parser = TelemetryCaptureParser(
        inner: inner,
        telemetry: telemetry,
      );

      await expectLater(parser.parse(_request()), throwsA(isA<TimeoutException>()));
      expect(
        telemetry.byName(TelemetryFunnel.parseFallback).single.props,
        {'code': 'timeout'},
      );
    });

    test('未分类异常 → parse_fallback code=error（§3.9 只记类型）', () async {
      final telemetry = RecordingTelemetryService();
      final inner = FakeParser()..throwOnParse = StateError('意外');
      final parser = TelemetryCaptureParser(
        inner: inner,
        telemetry: telemetry,
      );

      await expectLater(parser.parse(_request()), throwsA(isA<StateError>()));
      expect(
        telemetry.byName(TelemetryFunnel.parseFallback).single.props,
        {'code': 'error'},
      );
    });
  });
}
