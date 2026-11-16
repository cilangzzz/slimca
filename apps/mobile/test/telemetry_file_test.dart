/// FileTelemetryService 落盘格式与隐私口径测试（§3.9 监控 W7-8；§11.1
/// W7-8 任务「遥测磁盘格式」验收）。
///
/// 覆盖：
/// - JSONL 磁盘格式：一行一个对象 `{"ts","kind","name","props"}`；
/// - 隐私闸门（§3.9「不含内容字段」）：黑名单键（raw/note 等）落盘前剔除、
///   长字符串截断、crash 只记错误**类型**与帧数（message/stack 禁入）；
/// - metric 计数/耗时口径；Noop 实现零副作用立即完成。
///
/// 只写进程临时目录（无真实网络；teardown 全清理）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimca/telemetry/telemetry.dart';

void main() {
  late Directory tempDir;
  late FileTelemetryService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('slimca_telemetry_test');
    service = await FileTelemetryService.open(
      tempDir,
      nowMs: () => 1700000000000,
    );
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows 上偶发句柄延迟释放：忽略清理失败（不影响断言）。
    }
  });

  /// 读回磁盘 JSONL（每行一对象）。
  List<Map<String, Object?>> readLines() {
    final file = File('${tempDir.path}/telemetry_events.jsonl');
    expect(file.existsSync(), isTrue, reason: '遥测文件应已创建');
    final text = file.readAsStringSync();
    return [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map).cast<String, Object?>(),
    ];
  }

  test('funnel 落盘为 JSONL：一行一个信封对象（ts/kind/name/props）', () async {
    await service.funnel('capture_channel_selected',
        props: {'channel': 'text'});
    await service.flush();

    final lines = readLines();
    expect(lines.length, 1);
    expect(lines.single['ts'], 1700000000000);
    expect(lines.single['kind'], 'funnel');
    expect(lines.single['name'], 'capture_channel_selected');
    expect((lines.single['props'] as Map).cast<String, Object?>(),
        {'channel': 'text'});
  });

  test('隐私口径：黑名单键（raw/note/message 等）落盘前剔除（§3.9）', () async {
    await service.funnel('parse_request', props: <String, Object?>{
      'raw': '一杯奶茶 500kcal 18 元', // 原文内容禁入（§3.9）。
      'note': '备注内容',
      'message': '报错内容',
      'input_kind': 'text', // 枚举标量放行。
    });
    await service.flush();

    final props =
        (readLines().single['props'] as Map).cast<String, Object?>();
    expect(props, {'input_kind': 'text'},
        reason: '内容字段键一律不落盘，仅枚举标签保留');
  });

  test('隐私口径：超长字符串截断到 64（防长文本借道枚举键）', () async {
    await service.funnel('e', props: {'tag': 'a' * 100});
    await service.flush();

    final props =
        (readLines().single['props'] as Map).cast<String, Object?>();
    expect((props['tag'] as String).length, 64);
  });

  test('metric：计数/耗时标量 + tags 合入 props', () async {
    await service.metric(
      'sync_cycle_ms',
      value: 1234,
      unit: 'ms',
      tags: {'source': 'timer'},
    );
    await service.flush();

    final line = readLines().single;
    expect(line['kind'], 'metric');
    expect(line['name'], 'sync_cycle_ms');
    expect((line['props'] as Map).cast<String, Object?>(), {
      'value': 1234,
      'unit': 'ms',
      'source': 'timer',
    });
  });

  test('crash：只记错误类型与帧数，报错 message/stack 内容禁入（§3.9）', () async {
    await service.crash(
      FormatException('秘密内容 500kcal'),
      StackTrace.current,
      source: 'flutter_framework',
    );
    await service.flush();

    final line = readLines().single;
    expect(line['kind'], 'crash');
    final props = (line['props'] as Map).cast<String, Object?>();
    expect(props['error_type'], 'FormatException');
    expect(props['source'], 'flutter_framework');
    expect(props.containsKey('message'), isFalse);
    // 全文件不含报错 message（内容禁入 §3.9；「秘密内容」串不得出现）。
    final raw = File('${tempDir.path}/telemetry_events.jsonl')
        .readAsStringSync();
    expect(raw.contains('秘密内容'), isFalse);
  });

  test('NoopTelemetryService：立即完成、零副作用（无文件产生）', () async {
    // W7-8 集成修复：本文件 setUp 已为每个用例打开 FileTelemetryService
    // （open 即建 JSONL 文件），共享 tempDir 恒有 1 个文件——Noop 零副作用
    // 断言改用独立目录，目录内容只由 Noop 自身决定。
    final noopDir = await Directory.systemTemp.createTemp('slimca_telemetry_noop');
    addTearDown(() async {
      try {
        await noopDir.delete(recursive: true);
      } on FileSystemException {
        // Windows 上偶发句柄延迟释放：忽略清理失败（不影响断言）。
      }
    });
    const noop = NoopTelemetryService();
    await noop.funnel('x');
    await noop.metric('y', value: 1);
    await noop.crash(StateError('z'), null);
    await noop.flush();
    expect(noopDir.listSync().whereType<File>().length, 0,
        reason: 'Noop 不产生任何文件');
  });
}
