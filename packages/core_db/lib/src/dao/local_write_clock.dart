/// 本地写入戳与设备标识（§5.1 公共列 + §6.3 HLC）。
///
/// 本地写路径（UI → Drift 事务，§6.2）所有需要「自己生成公共列」的组件
/// （DAO seed、TodoDao）统一经 [LocalWriteClock] 发戳：
/// - device_id（§5.1 公共列）：首次调用生成 12 位 hex 并持久化进 settings
///   （key=[kSettingDeviceId]），此后全库复用——同一设备的行共享该标识；
/// - hlc（§6.3）：`core_domain.HlcClock` 签发，同毫秒 counter 自增、全序单调；
/// - updated_at（§5.1）：取 hlc 物理段，与 hlc 同源单调，同步游标
///   (updated_at)/(hlc) 索引依赖该一致性（§5.2）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as domain;

import '../app_database.dart';
import '../uuid_v7.dart';

/// settings 键：本设备标识（12 位 hex，§5.1 device_id / §6.3 节点段）。
const String kSettingDeviceId = 'device_id';

/// settings 键：默认账本 id（§5.6⑲ settings 内容清单「默认账本」）。
const String kSettingDefaultLedgerId = 'default_ledger_id';

/// 一次本地写入的行级戳（§5.1 公共列语义）。
class WriteStamp {
  /// 定宽 HLC 编码（§6.3），字典序=时间序。
  final String hlc;

  /// 与 [hlc] 物理段同源的 UTC 毫秒（updated_at / created_at 取值）。
  final int updatedAtMs;

  const WriteStamp({required this.hlc, required this.updatedAtMs});
}

/// 本地写路径的统一发戳点。
///
/// 设备标识与 HLC 时钟均为懒加载单例：首个 stamp 前解析一次并缓存。
class LocalWriteClock {
  LocalWriteClock(this._db);

  final AppDatabase _db;
  domain.HlcClock? _clock;
  String? _deviceId;

  /// 本设备标识（§5.1 device_id）：settings 缺失时生成 12 位 hex 并落库。
  Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null) {
      return cached;
    }
    final row = await (_db.select(_db.settings)
          ..where((t) => t.key.equals(kSettingDeviceId)))
        .getSingleOrNull();
    if (row != null) {
      // value 为 JSON 文本（§5.6⑲ settings.value TEXT(JSON)）。
      final id = jsonDecode(row.value) as String;
      return _deviceId = id;
    }
    final generated = generateDeviceIdHex12();
    await _db.into(_db.settings).insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: kSettingDeviceId,
            value: jsonEncode(generated),
          ),
        );
    return _deviceId = generated;
  }

  /// 签发下一枚写入戳（§6.3 now 语义：物理=max(墙钟,已见)，同毫秒 counter++）。
  Future<WriteStamp> next() async {
    final id = await deviceId();
    final clock = _clock ??= domain.HlcClock(deviceId: id);
    final hlc = clock.now();
    return WriteStamp(hlc: hlc.format(), updatedAtMs: hlc.physicalMs);
  }
}
