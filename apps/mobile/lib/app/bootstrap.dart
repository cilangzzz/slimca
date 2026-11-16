/// 启动期异步装配（§11 W2 接线；W1 注记「W2+ 接入后再改 async main」的落点）。
///
/// 装配顺序：
/// 1. 打开应用主库（§10.1 Drift，core_db driftDatabase('slimca')）；
/// 2. 确保本地 device_id（§5.6⑲ settings 本地件；devices 表正式注册 W7-8
///    接入，§11 W7-8——届时同一标识映射到服务端设备行）；
/// 3. 构造 HLC 时钟（§6.3）；
/// 4. 种子内置账本（§5.4：MVP 恒默认 money 账本；kcal 账本系统内置一个）。
///
/// 完成后以 override 注入 provider 容器：运行期 `appDatabaseProvider` /
/// `hlcClockProvider` 同步可读，页面零等待（§2.3 步 0 无 spinner 冷启动）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
// Riverpod 3：Override 不在主库 show 清单内，由 misc.dart 导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:uuid/uuid.dart';

import 'providers.dart';

/// settings 表中的设备标识键（§5.6⑲：key-value 配置，value 一律 JSON）。
const String _kDeviceIdKey = 'device_id';

/// 同步真值表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String _kLedgersTable = 'ledgers';

/// 启动装配：返回 main() 注入 ProviderScope 的 overrides。
Future<List<Override>> bootstrap() async {
  final database = db.AppDatabase();
  final deviceId = await ensureDeviceId(database);
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);
  return [
    appDatabaseProvider.overrideWithValue(database),
    hlcClockProvider.overrideWithValue(clock),
  ];
}

/// 确保本地设备标识就绪并返回（§6.3：device_id = UUIDv7 前 12 个 hex 字符）。
///
/// 首次启动生成 UUIDv7 → 取前 12 位 hex 落 settings；此后复用。settings 是
/// 本地件、永不同步（§5.1 表分组）；值损坏（非法 JSON / 非 12 位 hex）时
/// 视同未存储、重新生成——本地件可自愈，不影响 HLC 全序（§6.3 物理取 max）。
Future<String> ensureDeviceId(db.AppDatabase database) async {
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(_kDeviceIdKey)))
      .getSingleOrNull();
  if (row != null) {
    try {
      return Hlc.normalizeNodeId(jsonDecode(row.value) as String);
    } catch (_) {
      // 损坏值：落入下方重新生成并覆盖（settings ⑲ 本地件自愈）。
    }
  }
  final deviceId = Hlc.nodeIdFromUuidV7(const Uuid().v7());
  await database.into(database.settings).insertOnConflictUpdate(
        db.Setting(key: _kDeviceIdKey, value: jsonEncode(deviceId)),
      );
  return deviceId;
}

/// 内置账本种子（§5.4：MVP 表建好但恒默认 money 账本；kcal 账本系统内置、
/// 不可删除不可多开，币种=kcal，预算=收入、吃=支出、运动=再入账 §2.1③）。
///
/// 幂等：按 kind 检查缺哪个补哪个；写入与 outbox 同事务（§6.2 写路径纪律，
/// W5-6 SyncEngine 接入后统一出队）。
Future<void> ensureDefaultLedgers(db.AppDatabase database, HlcClock clock) async {
  final existing = await database.select(database.ledgers).get();
  bool hasKind(String kind) =>
      existing.any((row) => row.kind == kind && row.deletedAt == null);
  if (hasKind('money') && hasKind('kcal')) return;

  await database.transaction(() async {
    if (!hasKind('money')) {
      await _insertLedger(
        database,
        clock,
        name: '默认账本',
        icon: 'account_balance_wallet',
        currency: 'CNY',
        kind: 'money',
        sort: 0,
      );
    }
    if (!hasKind('kcal')) {
      await _insertLedger(
        database,
        clock,
        name: '热量账本',
        icon: 'local_fire_department',
        currency: 'kcal',
        kind: 'kcal',
        sort: 1,
      );
    }
  });
}

Future<void> _insertLedger(
  db.AppDatabase database,
  HlcClock clock, {
  required String name,
  required String icon,
  required String currency,
  required String kind,
  required int sort,
}) async {
  final hlc = clock.now();
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final meta = SyncMeta(
    createdAt: nowMs,
    updatedAt: nowMs,
    hlc: hlc.format(),
    revision: 1,
    schemaVer: kCurrentSchemaVer,
    deviceId: clock.deviceId,
  );
  final id = const Uuid().v7();
  await database.into(database.ledgers).insertOnConflictUpdate(
        db.LedgersCompanion(
          id: Value(id),
          name: Value(name),
          icon: Value(icon),
          currency: Value(currency),
          kind: Value(kind),
          sort: Value(sort),
          openingBalanceMinor: const Value(0),
          isArchived: const Value(false),
          createdAt: Value(meta.createdAt),
          updatedAt: Value(meta.updatedAt),
          deletedAt: Value(meta.deletedAt),
          hlc: Value(meta.hlc),
          revision: Value(meta.revision),
          schemaVer: Value(meta.schemaVer),
          deviceId: Value(meta.deviceId),
        ),
      );
  // §6.2：业务行 + sync_outbox 同事务写入（此处已在 ensureDefaultLedgers
  // 的事务内）。W5-6 SyncEngine 出队后上送。
  await database.into(database.syncOutbox).insert(
        db.SyncOutboxCompanion.insert(
          id: const Uuid().v7(),
          targetTable: _kLedgersTable,
          rowId: id,
          op: OutboxOp.upsert.wire,
          payload: jsonEncode(<String, Object?>{
            'id': id,
            'name': name,
            'icon': icon,
            'currency': currency,
            'kind': kind,
            'sort': sort,
            'opening_balance_minor': 0,
            'is_archived': false,
            ...meta.toRowJson(),
          }),
          hlc: meta.hlc,
          createdAt: meta.createdAt,
        ),
      );
}
