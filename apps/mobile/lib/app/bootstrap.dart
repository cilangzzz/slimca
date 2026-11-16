/// 启动期异步装配（§11 W2 接线；W1 注记「W2+ 接入后再改 async main」的落点）。
///
/// 装配顺序：
/// 1. 打开应用主库（§10.1 Drift，core_db driftDatabase('slimca')）；
/// 2. 确保本地 device_id（§5.6⑲ settings 本地件）；
/// 3. 构造 HLC 时钟（§6.3）；
/// 4. 种子内置账本（§5.4：MVP 恒默认 money 账本；kcal 账本系统内置一个）；
/// 5. 装配 feature_capture 录入域（§10.4「壳负责装配」）：CaptureGateway
///    （core_db 仓库 + HLC 单例时钟）与 CaptureParser 装饰链（W7-8）：
///    遥测埋点(raw_input 开关位) → raw_input 闸门(§3.7) → dart-define 工厂
///    （core_ai adapter，缺省 Fake——见 lib/ai/capture_parser_factory.dart）；
/// 6. W7-8 装配（§11.1）：本地 JSONL 遥测（§3.9）、raw_input 上云开关装载
///    （§3.7 默认关）、同步栈（后端工厂 → 引擎 → 设备注册 → 协调器，§6.2）。
///
/// 完成后以 [AppRuntime] 返回 override 清单与运行期句柄（遥测/开关/协调器）：
/// `appDatabaseProvider` / `hlcClockProvider` / `captureGatewayProvider` /
/// `captureParserProvider` / `syncEngineProvider` 等同步可读，页面零等待
/// （§2.3 步 0 无 spinner 冷启动）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart';
import 'package:feature_capture/feature_capture.dart';
import 'package:feature_sync/feature_sync.dart';
// Riverpod 3：Override 不在主库 show 清单内，由 misc.dart 导出。
import 'package:flutter_riverpod/misc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../ai/capture_parser_factory.dart';
import '../ai/raw_input_gate_capture_parser.dart';
import '../ai/telemetry_capture_parser.dart';
import '../settings/raw_input_setting.dart';
import '../sync/sync_backend_factory.dart';
import '../sync/sync_coordinator.dart';
import '../sync/telemetry_sync_backend.dart';
import '../telemetry/telemetry.dart';
import 'providers.dart';

/// settings 表中的设备标识键（§5.6⑲：key-value 配置，value 一律 JSON）。
const String _kDeviceIdKey = 'device_id';

/// 同步真值表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String _kLedgersTable = 'ledgers';

/// 启动装配产出：provider overrides + 运行期句柄（main() 持有）。
class AppRuntime {
  const AppRuntime({
    required this.overrides,
    required this.telemetry,
    required this.rawInputPolicy,
    required this.syncCoordinator,
  });

  /// ProviderScope overrides（含遥测/开关/同步引擎/协调器的注入）。
  final List<Override> overrides;

  /// 遥测服务（main() 挂崩溃钩子与冷启动漏斗，§3.9）。
  final TelemetryService telemetry;

  /// raw_input 上云开关持有（已按 settings 表初值装载，§3.7 默认关）。
  final RawInputPolicy rawInputPolicy;

  /// 同步协调器（main() start() + 生命周期观察者，§6.2）。
  final SyncCoordinator syncCoordinator;
}

/// 启动装配：返回 main() 注入 ProviderScope 的 [AppRuntime]。
Future<AppRuntime> bootstrap() async {
  final database = db.AppDatabase();
  final deviceId = await ensureDeviceId(database);
  final clock = HlcClock(deviceId: deviceId);
  await ensureDefaultLedgers(database, clock);

  // ── W7-8 · 遥测（§3.9）：本地 JSONL 落盘；装配失败回落 Noop（缺失只损
  // 失监控数据、不影响业务，§6.1 纪律）。路径 = 应用 support 目录/telemetry。
  final telemetry = await _createTelemetryService();

  // ── W7-8 · raw_input 上云开关（§3.7 数据主权、§3.3 默认关）：读 settings
  // 装入上次用户选择；坏值回落 false（本地件自愈，§5.6⑲）。
  final policy = RawInputPolicy();
  policy.enabled = await loadRawInputCloudEnabled(database);

  // ── W7-8 · 同步栈（§6.2、§11.1「托管 Supabase 接入」）：后端工厂按
  // dart-define 凭据装配（缺省本地回环，待用户凭据）→ 遥测装饰 → 引擎 →
  // 协调器（设备注册 §5.6⑰ + 周期/前台切回触发）。
  final backend = TelemetrySyncBackend(
    inner: createSyncBackend(),
    telemetry: telemetry,
  );
  final engine = LocalSyncEngine(
    backend: backend,
    outbox: DriftSyncOutboxStore(database),
    store: DriftSyncLocalStore(database, deviceId: deviceId),
    deviceId: deviceId,
    clock: clock,
  );
  final coordinator = SyncCoordinator(
    engine: engine,
    registry: DeviceRegistry(database, backend),
    telemetry: telemetry,
  );

  return AppRuntime(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      hlcClockProvider.overrideWithValue(clock),
      // feature_capture 录入域装配（§10.4「壳负责装配」）：网关绑定同一
      // AppDatabase 与应用级 HLC 单例时钟；解析器为 W7-8 装饰链——遥测
      // 漏斗（§12 解析请求/成功/失败降级）→ raw_input 闸门（§3.7）→
      // dart-define 工厂桥接 core_ai 管线（缺省离线桩）。
      captureGatewayProvider.overrideWithValue(
        createCaptureGateway(db: database, clock: clock),
      ),
      captureParserProvider.overrideWithValue(
        TelemetryCaptureParser(
          inner: RawInputGateCaptureParser(
            inner: createCaptureParser(),
            policy: policy,
          ),
          telemetry: telemetry,
          rawInputCloud: () => policy.enabled,
        ),
      ),
      // W7-8 运行期句柄注入（§10.4）。
      telemetryServiceProvider.overrideWithValue(telemetry),
      rawInputPolicyProvider.overrideWithValue(policy),
      syncEngineProvider.overrideWithValue(engine),
      syncCoordinatorProvider.overrideWithValue(coordinator),
    ],
    telemetry: telemetry,
    rawInputPolicy: policy,
    syncCoordinator: coordinator,
  );
}

/// 本地遥测装配（§3.9）：support 目录下 telemetry 子目录 JSONL 落盘。
/// path_provider 不可用/磁盘异常 → Noop 兜底（遥测永不阻塞业务）。
Future<TelemetryService> _createTelemetryService() async {
  try {
    final support = await getApplicationSupportDirectory();
    return await FileTelemetryService.open(
      Directory('${support.path}${Platform.pathSeparator}telemetry'),
    );
  } on Object {
    return const NoopTelemetryService();
  }
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
