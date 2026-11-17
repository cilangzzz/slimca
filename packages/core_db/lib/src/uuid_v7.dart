/// UUIDv7 生成器（§5.1 主键约定）。
///
/// 主键 `id` = UUIDv7（TEXT 存储，时间有序，天然同步友好，§5.1）。为避免
/// 引入第三方依赖，本地实现 RFC 9562 v7 布局：48 位 unix 毫秒（大端）+
/// version 7 + 12 位 rand_a + variant `10xx` + 62 位 rand_b。
/// HLC 的 device_id 段取「UUIDv7 前 12 个 hex 字符」（§6.3），故同源提供
/// [generateDeviceIdHex12] 供首次 seed 生成设备标识。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 生成一个 RFC 9562 UUIDv7 字符串（标准 8-4-4-4-12 连字符形式）。
///
/// [timestampMs] 缺省取当前墙钟；[random] 可注入固定种子（测试确定性）。
String generateUuidV7({int? timestampMs, math.Random? random}) {
  final ts = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final rnd = random ?? math.Random.secure();

  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  // 48 位 unix 毫秒（大端）填 byte0-5：与 HLC 物理段同一时钟域（§6.3）。
  for (var i = 0; i < 6; i++) {
    bytes[i] = (ts >> ((5 - i) * 8)) & 0xFF;
  }
  // version 7（高 4 位=0111）+ 随机 rand_a。
  bytes[6] = (bytes[6] & 0x0F) | 0x70;
  // variant `10xx` + 随机 rand_b。
  bytes[8] = (bytes[8] & 0x3F) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// 12 位定长 hex 设备标识（§6.3 device_id 段：UUIDv7 前 12 个 hex 字符）。
///
/// 供无既有 UUIDv7 可截取的场景（首次 seed 生成 device_id，见
/// `LocalWriteClock.deviceId`）；返回大写以保证 HLC 编码规范化（§6.3）。
String generateDeviceIdHex12({math.Random? random}) {
  final rnd = random ?? math.Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < 6; i++) {
    buf.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString().toUpperCase();
}

/// UUIDv7 id 内嵌时间戳（48 位 unix 毫秒，大端存放于前 12 个 hex 字符）。
///
/// 「时间可由 id 得出就不另设时间列」的统一判据（§5.6⑭ ai_parses 7 天缓存
/// 时效同一口径）：§11.2 W11-12 attachments 即焚清理（>7 天残留强制焚毁）
/// 的残留时长亦由 [generateUuidV7] 生成的 id 内嵌时间戳得出。
///
/// 非法/非 UUIDv7 形态返回 null——调用方不据此判过期（宁可保守跳过，
/// 也不误焚来源不明的行）。
int? uuidV7TimestampMs(String id) {
  final hex = id.replaceAll('-', '');
  if (hex.length < 12) return null;
  return int.tryParse(hex.substring(0, 12), radix: 16);
}
