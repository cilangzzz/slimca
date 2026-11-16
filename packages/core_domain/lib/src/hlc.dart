/// HLC 混合逻辑时钟（Hybrid Logical Clock）。
///
/// 对应设计文档 §6.3（含评审必修项「定宽编码修复」）与 §6.1 同步原则：
/// - hlc = (physical_ms, counter, device_id) 三元组；
/// - 物理部分 = max(本地墙钟, 已见最大物理值)；同一毫秒内 counter 自增；
/// - recv：收到比本地新的时间戳 → 跳变跟上；收到比本地旧的 → 沿用本地物理并 counter++；
/// - 时钟回拨：物理部分取 max，回拨不影响全序；回拨过大（>60s）上报告警；
/// - 定宽编码：13 位毫秒 + 6 位计数器 + 12 位节点标识，全部补零定宽，
///   保证「字符串字典序 = 时间全序」，SQLite/Postgres 按 TEXT 比较即得 LWW 顺序。
///
/// 修复的隐藏 bug：裸十进制下 "999" > "1000"（字典序），定宽补零后
/// "000999" < "001000"，与数值序一致（§6.3 编码表）。
library;

import 'dart:math' as math;

/// 单个 HLC 值：不可变、可比较、可定宽编码/解析（§6.3）。
///
/// 编码形如 `1700000000000:000042:3F8A12C0B7D4`（总长 33 字符）。
/// 注：§6.3 示例串 `0001700000000000:…` 的物理段有 16 位，与同节编码表
/// 「13 位十进制补零」矛盾，判定为示例笔误——本实现以编码表为准，
/// 13 位宽度下 1700000000000 本身已定宽、无需前导零。
/// 补零在物理值小于 10^12（2001-09 前）时才在毫秒段显现，
/// 计数器段则始终补零（「000999 < 001000」是定宽修复的核心）。
class Hlc implements Comparable<Hlc> {
  /// 物理毫秒段：定宽 13 位十进制补零（10^13 ms ≈ 公元 33658 年，§6.3）。
  final int physicalMs;

  /// 逻辑计数器段：定宽 6 位十进制补零；单毫秒上限 [maxCounter]，
  /// 超限时由时钟做「物理 +1、counter 归零」进位（§6.3 计数器行）。
  final int counter;

  /// 节点标识段：定长 12 位 hex（UUIDv7 前 12 个 hex 字符，§6.3）。
  /// 本类内部统一规范化为大写，保证同一节点的编码唯一且字典序稳定。
  final String deviceId;

  static const int physicalWidth = 13;
  static const int counterWidth = 6;
  static const int deviceIdWidth = 12;

  /// 单毫秒计数器上限：999,999 次（§6.3 counter 行）。
  static const int maxCounter = 999999;

  /// 13 位定宽能容纳的最大物理毫秒值（10^13 - 1）。
  static const int maxPhysicalMs = 10000000000000 - 1;

  /// 编码段分隔符。三个定宽段夹在分隔符之间，字典序逐字符比较时
  /// 分隔符位置恒定，等价于按「物理段 → 计数器段 → 节点段」的数值序。
  static const String separator = ':';

  /// 严格定宽解析模式：13 位数字 : 6 位数字 : 12 位 hex（大小写均可）。
  /// 任何缺位/超宽/缺分隔符的输入一律拒绝——定宽性是本编码的存在意义。
  static final RegExp _pattern =
      RegExp(r'^(\d{13}):(\d{6}):([0-9A-Fa-f]{12})$');

  /// 节点标识字符集校验（12 位 hex）。
  static final RegExp _devicePattern = RegExp(r'^[0-9A-Fa-f]{12}$');

  /// 校验并构造 HLC 值（非 const：需要运行时校验边界）。
  ///
  /// 边界（§6.3 编码表，逐条对应）：
  /// - [physicalMs] 必须落在 [0, maxPhysicalMs]，否则无法定宽 13 位；
  /// - [counter] 必须落在 [0, maxCounter]，否则无法定宽 6 位；
  /// - [deviceId] 必须恰为 12 位 hex，会规范化为大写。
  factory Hlc({
    required int physicalMs,
    required int counter,
    required String deviceId,
  }) {
    if (physicalMs < 0 || physicalMs > maxPhysicalMs) {
      throw ArgumentError.value(
        physicalMs,
        'physicalMs',
        '必须落在 [0, $maxPhysicalMs] 才能满足 13 位定宽编码（§6.3）',
      );
    }
    if (counter < 0 || counter > maxCounter) {
      throw ArgumentError.value(
        counter,
        'counter',
        '必须落在 [0, $maxCounter] 才能满足 6 位定宽编码（§6.3）',
      );
    }
    // 节点标识校验与规范化（12 位定长 hex，§6.3）。
    final normalizedDeviceId = normalizeNodeId(deviceId);
    return Hlc._(physicalMs, counter, normalizedDeviceId);
  }

  const Hlc._(this.physicalMs, this.counter, this.deviceId);

  /// 节点标识校验与规范化：恰为 12 位 hex（大小写均可），统一转大写。
  static String normalizeNodeId(String raw) {
    if (!_devicePattern.hasMatch(raw)) {
      throw ArgumentError.value(
        raw,
        'deviceId',
        '必须为 $deviceIdWidth 位定长 hex（UUIDv7 前 12 个 hex 字符，§6.3）',
      );
    }
    return raw.toUpperCase();
  }

  /// 从 UUIDv7 文本提取节点标识：取前 12 个 hex 字符（§6.3 device_id 行）。
  /// 允许带连字符的标准 UUID 形式；不足 12 位 hex 或含非 hex 字符即拒绝。
  static String nodeIdFromUuidV7(String uuidV7) {
    final hexOnly = uuidV7.replaceAll('-', '');
    if (hexOnly.length < deviceIdWidth) {
      throw ArgumentError.value(
        uuidV7,
        'uuidV7',
        '不足 $deviceIdWidth 个 hex 字符（§6.3：UUIDv7 前 12 个 hex 字符）',
      );
    }
    try {
      return normalizeNodeId(hexOnly.substring(0, deviceIdWidth));
    } on ArgumentError {
      throw ArgumentError.value(
        uuidV7,
        'uuidV7',
        '前 $deviceIdWidth 个字符必须为 hex（§6.3：UUIDv7 前 12 个 hex 字符）',
      );
    }
  }

  /// 定宽编码（§6.3）：`physical(13):counter(6):device(12)`，全部补零。
  String format() {
    final p = physicalMs.toString().padLeft(physicalWidth, '0');
    final c = counter.toString().padLeft(counterWidth, '0');
    return '$p$separator$c$separator$deviceId';
  }

  /// [format] 的逆运算：严格按定宽正则解析，失败抛 [FormatException]。
  static Hlc parse(String encoded) {
    final m = _pattern.firstMatch(encoded);
    if (m == null) {
      throw FormatException(
        'HLC 编码必须为定宽 "13位数字:6位数字:12位hex"，实际: "$encoded"（§6.3）',
        encoded,
      );
    }
    return Hlc(
      physicalMs: int.parse(m.group(1)!),
      counter: int.parse(m.group(2)!),
      deviceId: m.group(3)!,
    );
  }

  /// 全序比较：物理毫秒 → 计数器 → 节点标识。
  ///
  /// 节点段是同定长的大写 hex 字符串，字典序与数值序一致，
  /// 因此本三元组序与 [format] 后的字符串字典序严格等价（§6.3 字典序即全序）。
  @override
  int compareTo(Hlc other) {
    final p = physicalMs.compareTo(other.physicalMs);
    if (p != 0) return p;
    final c = counter.compareTo(other.counter);
    if (c != 0) return c;
    return deviceId.compareTo(other.deviceId);
  }

  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;
  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Hlc &&
          physicalMs == other.physicalMs &&
          counter == other.counter &&
          deviceId == other.deviceId;

  @override
  int get hashCode => Object.hash(physicalMs, counter, deviceId);

  @override
  String toString() => format();
}

/// 发号状态的混合逻辑时钟：维护「已签发的最新 HLC」，提供 [now]/[recv]。
///
/// 设计要点（§6.3）：
/// - 墙钟通过 [wallClock] 注入，生产环境传毫秒墙钟，测试可注入虚拟时钟；
/// - 物理段永远不低于已见最大值（墙钟回拨不影响全序）；
/// - 计数器单毫秒耗尽时「物理 +1、counter 归零」进位；
/// - 回拨检测以「墙钟高水位」为基准：墙钟向下偏离高水位超过
///   [rollbackAlertThresholdMs] 时触发 [onClockRollback] 告警
///   （收到远端未来时间戳导致的「墙钟落后于已见物理」不算回拨）。
class HlcClock {
  /// 本节点标识（12 位定长 hex，§6.3）。
  final String deviceId;

  /// 墙钟源（UTC 毫秒）；默认 [DateTime.now]。
  final int Function() wallClock;

  /// 回拨告警阈值：回拨超过 60s 必须上报（§6.3「回拨过大（>60s）上报告警」）。
  static const int rollbackAlertThresholdMs = 60000;

  /// 回拨越过阈值时触发一次（同一回拨事件内不重复触发，墙钟追平后复位）。
  /// 参数为当前回拨幅度（毫秒，正值）。
  final void Function(int lagMs)? onClockRollback;

  Hlc? _last;
  int _wallHighWater = -1;
  int? _activeRollbackLagMs;
  bool _rollbackAlerted = false;

  HlcClock({
    required String deviceId,
    int Function()? wallClock,
    this.onClockRollback,
  })  : deviceId = Hlc.normalizeNodeId(deviceId),
        wallClock = wallClock ?? _defaultWallClock;

  static int _defaultWallClock() => DateTime.now().millisecondsSinceEpoch;

  /// 最近一次签发的 HLC；发号前为 null。
  /// 写路径需要在同一事务内取「刚签发」的值时使用（§6.2）。
  Hlc? get lastIssued => _last;

  /// 当前未解除的回拨幅度；无回拨（或未超阈值）时为 null。
  int? get activeRollbackLagMs => _activeRollbackLagMs;

  /// 签发新事件的时间戳（§6.3 now 语义）：
  /// 物理段 = max(墙钟, 已见最大物理值)；同毫秒内 counter 自增。
  Hlc now() {
    final wall = wallClock();
    _observeWall(wall);
    final last = _last;
    int physical;
    int counter;
    if (last == null || wall > last.physicalMs) {
      // 全新物理毫秒：counter 归零。
      physical = wall;
      counter = 0;
    } else {
      // 墙钟未超过已见最大值（同毫秒连发或回拨）：沿用已见物理并自增。
      // 这一行同时承载两条 §6.3 规则：同 ms 并发自增、回拨不影响全序。
      physical = last.physicalMs;
      counter = last.counter + 1;
      if (counter > Hlc.maxCounter) {
        // 计数器 6 位定宽耗尽：物理 +1 进位、counter 归零（§6.3 counter 行）。
        physical += 1;
        counter = 0;
      }
    }
    return _issue(physical, counter);
  }

  /// 合并远端时间戳（§6.3 recv 语义），返回本节点应使用的下一时间戳。
  ///
  /// 分支按 Kulkarni HLC 标准语义实现，并叠加 6 位计数器进位：
  /// - 远端物理值是新的最大值 → 跳变跟上，counter = 远端 counter + 1；
  /// - 远端与本地已见同毫秒 → counter = max(本地, 远端) + 1（同 ms 并发）；
  /// - 远端更旧 → 沿用本地物理并 counter++（本地事件照常单调）。
  ///
  /// 收到自己事件的回显同样安全：只会让 counter 单调前进，不会破坏全序。
  Hlc recv(Hlc remote) {
    final wall = wallClock();
    _observeWall(wall);
    final last = _last;
    final localPhysical = last?.physicalMs ?? -1;
    final localCounter = last?.counter ?? -1;

    // 三方取最大：墙钟、本地已见物理、远端物理（§6.3「物理部分取 max」）。
    final nextPhysical =
        math.max(math.max(wall, localPhysical), remote.physicalMs);

    int nextCounter;
    if (localPhysical == nextPhysical && remote.physicalMs == nextPhysical) {
      // 本地已见与远端同毫秒：双端同 ms 并发，取大者 +1。
      nextCounter = math.max(localCounter, remote.counter) + 1;
    } else if (wall == nextPhysical && localPhysical == nextPhysical) {
      // 墙钟与本地已见同毫秒且为最大（远端更旧）：本地事件照常 counter++。
      nextCounter = localCounter + 1;
    } else if (wall == nextPhysical && remote.physicalMs == nextPhysical) {
      // 墙钟恰好追平远端物理毫秒：以远端为基准自增。
      nextCounter = remote.counter + 1;
    } else if (wall == nextPhysical) {
      // 墙钟独大：全新物理毫秒，counter 归零。
      nextCounter = 0;
    } else if (localPhysical == nextPhysical) {
      // 远端更旧、本地已见物理为最大：沿用本地物理并 counter++（§6.3）。
      nextCounter = localCounter + 1;
    } else {
      // 远端物理值是新的最大值：跳变跟上（§6.3「收到比本地新的时间戳」）。
      nextCounter = remote.counter + 1;
    }

    if (nextCounter > Hlc.maxCounter) {
      // 6 位计数器进位（§6.3 counter 行）：物理 +1、counter 归零。
      // 进位后的物理值可能高于远端值，仍严格保持全序单调。
      nextCounter = 0;
      return _issue(nextPhysical + 1, nextCounter);
    }
    return _issue(nextPhysical, nextCounter);
  }

  /// 解析并合并一段远端编码（[Hlc.parse] + [recv]）。
  Hlc recvEncoded(String encoded) => recv(Hlc.parse(encoded));

  /// 签发：校验定宽边界、更新「已见最大」状态并返回。
  Hlc _issue(int physicalMs, int counter) {
    if (physicalMs > Hlc.maxPhysicalMs) {
      throw StateError(
        'HLC 物理段溢出 13 位定宽上限 $physicalMs（§6.3 编码表）',
      );
    }
    final next = Hlc(physicalMs: physicalMs, counter: counter, deviceId: deviceId);
    _last = next;
    return next;
  }

  /// 回拨观测：以墙钟高水位为基准。
  ///
  /// - 墙钟前进（>= 高水位）：刷新高水位、复位回拨状态；
  /// - 墙钟后退：记录幅度；幅度超过 [rollbackAlertThresholdMs] 且本事件
  ///   尚未告警时触发 [onClockRollback]（边沿触发，§6.3 回拨告警）。
  ///
  /// 刻意不把「墙钟落后于远端跳变后的物理值」当回拨——那是 recv 跳变的正常
  /// 结果，不应告警；只有墙钟自身向后走才触发。
  void _observeWall(int wall) {
    if (wall >= _wallHighWater) {
      _wallHighWater = wall;
      _rollbackAlerted = false;
      _activeRollbackLagMs = null;
      return;
    }
    final lag = _wallHighWater - wall;
    if (lag > rollbackAlertThresholdMs) {
      _activeRollbackLagMs = lag;
      if (!_rollbackAlerted) {
        _rollbackAlerted = true;
        onClockRollback?.call(lag);
      }
    } else {
      // 小幅抖动（<=60s）：不告警，物理取 max 已保证全序（§6.3）。
      _activeRollbackLagMs = null;
    }
  }
}
