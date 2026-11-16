/// FileTelemetryService — 本地 JSONL 遥测落盘（§3.9「监控」W7-8 接入）。
///
/// 格式：每行一个 JSON 对象（JSONL）：
/// `{"ts":…,"kind":"funnel|metric|crash","name":…,"props":{…}}`
/// （§3.9 三类事件统一信封，见 core_domain TelemetryEvent）。
///
/// **隐私口径（§3.9：不含内容字段，仅计数/耗时/错误类型）**：
/// - 所有 props 写入前经 core_domain [TelemetryPrivacy.sanitizeProps]
///   （黑名单键剔除 + 非标量剔除 + 字符串截断）；
/// - crash 只记错误类型（runtimeType）与堆栈帧数，报错内容一律不落盘；
/// - 原文/标题/备注等业务字段没有任何进入遥测的通道（§1.6 合规底线）。
///
/// 可靠性：每条 append + flush（崩溃数据不丢缓冲）；写请求经串行队列防交错；
/// 磁盘失败静默丢弃并计数——遥测永不阻塞主流程（§6.1 原则 1 同款纪律）。
///
/// 上报通道：W7-8 仅本地落盘（文件供数据导出/合规材料归档，§3.9 合规专项）；
/// 真实上报端点待定（W8 起周报时以导出文件人工汇总，不接自动上传）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// W7-8 集成注：core_domain 包级 barrel 已收敛导出 src/telemetry.dart，
// 经公开路径引用（见 core_domain.dart「W7-8」注）。
import 'package:core_domain/core_domain.dart';

/// 本地 JSONL 遥测服务（§3.9）。
class FileTelemetryService implements TelemetryService {
  FileTelemetryService._({
    required File file,
    int Function()? nowMs,
    this.maxStringLength = 64,
  })  : _file = file,
        _nowMs = nowMs ?? _defaultNowMs;

  /// 打开（或创建）遥测文件：[directory] 须为应用专属目录（bootstrap 传
  /// path_provider 的 support 目录下 telemetry 子目录），缺省文件名
  /// [defaultFileName]。
  static Future<FileTelemetryService> open(
    Directory directory, {
    String fileName = defaultFileName,
    int Function()? nowMs,
    int maxStringLength = 64,
  }) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/$fileName');
    // 首次落盘前确保文件存在（空文件=空 JSONL，读取方按行解析兼容）。
    if (!file.existsSync()) {
      file.createSync();
    }
    return FileTelemetryService._(
      file: file,
      nowMs: nowMs,
      maxStringLength: maxStringLength,
    );
  }

  /// 缺省落盘文件名（JSONL；导出工具按行解析）。
  static const String defaultFileName = 'telemetry_events.jsonl';

  /// 字符串属性截断长度（TelemetryPrivacy 同口径默认值）。
  final int maxStringLength;

  final File _file;
  final int Function() _nowMs;

  /// 串行写队列：防止并发 append 行交错（JSONL 一行一事件，交错即坏行）。
  Future<void> _queue = Future<void>.value();

  /// 磁盘写入失败计数（自诊断 metric 口径；失败本身静默，不阻塞主流程）。
  int droppedWrites = 0;

  static int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  Future<void> funnel(String name, {Map<String, Object?>? props}) {
    return _enqueue(TelemetryEvent(
      kind: TelemetryKind.funnel,
      name: name,
      atMs: _nowMs(),
      props: TelemetryPrivacy.sanitizeProps(
        props,
        maxStringLength: maxStringLength,
      ),
    ));
  }

  @override
  Future<void> metric(
    String name, {
    required num value,
    String? unit,
    Map<String, Object?>? tags,
  }) {
    return _enqueue(TelemetryEvent(
      kind: TelemetryKind.metric,
      name: name,
      atMs: _nowMs(),
      props: <String, Object?>{
        'value': value,
        if (unit != null) 'unit': unit,
        ...TelemetryPrivacy.sanitizeProps(
          tags,
          maxStringLength: maxStringLength,
        ),
      },
    ));
  }

  @override
  Future<void> crash(Object error, StackTrace? stackTrace, {String? source}) {
    // §3.9 隐私口径：crash 只记错误**类型**与堆栈帧数，message/toString 禁入。
    final frames = stackTrace == null
        ? 0
        : stackTrace
            .toString()
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .length;
    return _enqueue(TelemetryEvent(
      kind: TelemetryKind.crash,
      name: 'crash',
      atMs: _nowMs(),
      props: TelemetryPrivacy.sanitizeProps(
        <String, Object?>{
          'error_type': error.runtimeType.toString(),
          'frames': frames,
          if (source != null) 'source': source,
        },
        maxStringLength: maxStringLength,
      ),
    ));
  }

  @override
  Future<void> flush() => _queue;

  /// 入队一条事件（串行防交错；失败静默丢弃并计数）。
  ///
  /// 返回本条事件的落盘完成 Future（链入 [_queue] 保序）——调用方
  /// （funnel/metric/crash）原样透传，满足「写入即返回本条完成时机」的
  /// 接口语义；失败已在链内兜底吞掉，永不上抛（§6.1 原则 1 同款纪律）。
  Future<void> _enqueue(TelemetryEvent event) {
    final write = _queue.then((_) async {
      try {
        final line = jsonEncode(event.toJson());
        await _file.writeAsString('$line\n',
            mode: FileMode.append, flush: true);
      } catch (_) {
        // 磁盘异常（权限/满）：丢本条保主流程（§3.9 监控不阻塞业务）。
        droppedWrites += 1;
      }
    });
    _queue = write;
    return write;
  }
}
