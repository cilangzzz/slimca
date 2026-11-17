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
///    （§3.7 默认关）、同步栈（后端工厂 → 引擎 → 设备注册 → 协调器，§6.2）；
/// 7. W11-12 装配（§11.2）：拍照通道注入点（image_picker ImageSource /
///    端侧压缩 / 双供应商拍照解析 / attachments 即焚存储 / raw_input 闸门
///    同源开关 / 拍照漏斗遥测）+ 拍照即焚开关装载（§3.7 默认开）+ 附件残留
///    兜底清扫（>7 天强制焚毁，§5.6㉑）。
///
/// 完成后以 [AppRuntime] 返回 override 清单与运行期句柄（遥测/开关/协调器）：
/// `appDatabaseProvider` / `hlcClockProvider` / `captureGatewayProvider` /
/// `captureParserProvider` / `syncEngineProvider` 等同步可读，页面零等待
/// （§2.3 步 0 无 spinner 冷启动）。
library;

import 'dart:async';
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
import '../ai/photo_parser_factory.dart';
import '../ai/raw_input_gate_capture_parser.dart';
import '../ai/telemetry_capture_parser.dart';
import '../notifications/flutter_local_reminder_scheduler.dart';
import '../notifications/reminder_sync.dart';
import '../photo/photo_attachment_store.dart';
import '../photo/photo_compressor.dart';
import '../photo/photo_image_source.dart';
import '../settings/photo_burn_setting.dart';
import '../settings/raw_input_setting.dart';
import '../sync/sync_backend_factory.dart';
import '../sync/sync_coordinator.dart';
import '../sync/telemetry_sync_backend.dart';
import '../telemetry/telemetry.dart';
import 'providers.dart';

/// settings 表中的设备标识键（§5.6⑲：key-value 配置，value 一律 JSON）。
const String _kDeviceIdKey = 'device_id';

/// settings 表中的首次启动日键（W9-10 北极星·次日留存的 D0 锚点；
/// §5.6⑲ settings 本地件，永不同步、自愈口径同 device_id）。
const String _kFirstOpenDayKey = 'first_open_day';

/// 同步真值表名（§5.6⑯ outbox target_table；与 Drift 表 SQL 名一致）。
const String _kLedgersTable = 'ledgers';

/// 启动装配产出：provider overrides + 运行期句柄（main() 持有）。
class AppRuntime {
  const AppRuntime({
    required this.overrides,
    required this.telemetry,
    required this.rawInputPolicy,
    required this.syncCoordinator,
    required this.reminderCoordinator,
  });

  /// ProviderScope overrides（含遥测/开关/同步引擎/协调器的注入）。
  final List<Override> overrides;

  /// 遥测服务（main() 挂崩溃钩子与冷启动漏斗，§3.9）。
  final TelemetryService telemetry;

  /// raw_input 上云开关持有（已按 settings 表初值装载，§3.7 默认关）。
  final RawInputPolicy rawInputPolicy;

  /// 同步协调器（main() start() + 生命周期观察者，§6.2）。
  final SyncCoordinator syncCoordinator;

  /// 提醒对账协调器（main() start()，§11.2 W13 任务 3：todos 流 → 按展开
  /// 实例调度本地通知）。
  final ReminderSyncCoordinator reminderCoordinator;
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

  // ── W9-10 · 北极星留存锚点（§12「次日留存」、§11.1 W9-10「北极星实测」）：
  // 首次启动记 first_open（D0 锚），此后每次启动记 app_open（day_offset=
  // 距首次启动的日历日偏移；D1 存在 app_open 即次日留存，本地 JSONL 周报
  // 可算——数字待真机实测）。
  final retention = await ensureFirstOpenDay(database);
  unawaited(
    telemetry.funnel(
      retention.isFirstOpen ? TelemetryFunnel.firstOpen : TelemetryFunnel.appOpen,
      props: <String, Object?>{'day_offset': retention.dayOffset},
    ),
  );

  // ── W7-8 · raw_input 上云开关（§3.7 数据主权、§3.3 默认关）：读 settings
  // 装入上次用户选择；坏值回落 false（本地件自愈，§5.6⑲）。
  final policy = RawInputPolicy();
  policy.enabled = await loadRawInputCloudEnabled(database);

  // ── W11-12 · 拍照即焚开关（§3.7/§5.6㉑，默认开=解析后即焚，§11.2 任务 3）：
  // 读 settings 装入上次用户选择；坏值回落默认开（即焚是合规缺省，损坏时取
  // 更严档，§6.1——与 raw_input 开关「坏值回落更严」同向）。
  final photoBurnPolicy = PhotoBurnPolicy();
  photoBurnPolicy.enabled = await loadPhotoBurnAfterParse(database);

  // ── W11-12 · 附件本机留档目录（§3.7 即焚开关=关时登记焚毁前复制原图）：
  // support 目录/photo_archive；装配失败 → null=无条件即焚（缺省最严，
  // §6.1——留档是用户附加选择，允许缺失降级）。
  Directory? photoArchiveDirectory;
  try {
    final support = await getApplicationSupportDirectory();
    photoArchiveDirectory =
        Directory('${support.path}${Platform.pathSeparator}photo_archive');
  } on Object {
    photoArchiveDirectory = null;
  }

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

  // ── W11-12 · 附件残留兜底清扫（§5.6㉑、§11.2「>7 天残留强制清理」）：
  // 启动期一次性，失败不阻塞启动（下轮重试，§6.1）。
  unawaited(_sweepAttachmentResidue(database));

  // ── W13 · 本地通知调度（§11.2 W13 任务 3）：flutter_local_notifications
  // 适配器（Android 13+ POST_NOTIFICATIONS 运行时请求在适配器内接线）+
  // 提醒对账协调器（todos 流 → 按展开实例调度；main() start()）。
  final reminderScheduler = FlutterLocalReminderScheduler();
  final reminderCoordinator = ReminderSyncCoordinator(
    db: database,
    scheduler: reminderScheduler,
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
      // ── W11-12 拍照通道注入点（§11.2 W11-12 任务 1/3/5，§10.4 壳负责
      //    装配；测试注入 Fake 集，禁真实相机/网络）：
      // - ImageSource：image_picker 薄封装（拍照/相册双入口；端侧压缩在
      //   拾取参数内完成，长边 1280、JPEG q80，§3.3）；
      captureImageSourceProvider.overrideWithValue(
        const ImagePickerCaptureImageSource(),
      ),
      // - 端侧压缩：拾取参数已压缩，压缩器做规范化收口（mime 归一 image/jpeg
      //   + sha256 content_hash 一址两用键，§5.6㉑/§5.6⑭）；
      captureImageCompressorProvider.overrideWithValue(
        const PickerCompressedCaptureCompressor(),
      ),
      // - 拍照解析：百度菜品识别先行 → Vision LLM 兜底（dart-define 凭据
      //   注入，缺省离线确定性桩；remaining：待凭据联调，§3.3/§7.4）；
      capturePhotoParserProvider.overrideWithValue(createCapturePhotoParser()),
      // - 附件存储：core_db AttachmentsDao 桥接（登记即 burned、blob_ref 恒
      //   NULL，§5.6㉑）+ content_hash 去重复用 + 即焚开关关闭时登记前本机
      //   留档（§3.7；开关运行期经持有器同步读取，设置页 toggle 即刻生效）；
      captureAttachmentStoreProvider.overrideWithValue(
        DriftPhotoAttachmentStore(
          database: database,
          burnPolicy: photoBurnPolicy,
          archiveDirectory: photoArchiveDirectory,
        ),
      ),
      // - raw_input 上云闸门（§3.7，默认关=图片字节不出端 → 端侧粗估/人工
      //   确认）：settings 持有器同步读取（与文本解析闸门同源开关）；
      captureRawInputCloudEnabledProvider
          .overrideWithValue(() => policy.enabled),
      // - 拍照漏斗（§11.2 任务 5）：FileTelemetryService（缺省 null=不发
      //   事件；装配失败回落 Noop 同源）。
      capturePhotoTelemetryProvider.overrideWithValue(telemetry),
      photoBurnPolicyProvider.overrideWithValue(photoBurnPolicy),
      // W7-8 运行期句柄注入（§10.4）。
      telemetryServiceProvider.overrideWithValue(telemetry),
      rawInputPolicyProvider.overrideWithValue(policy),
      syncEngineProvider.overrideWithValue(engine),
      syncCoordinatorProvider.overrideWithValue(coordinator),
      // W13 提醒调度注入点（§11.2 任务 3）：真实通道适配器（测试注入 Fake）。
      reminderSchedulerProvider.overrideWithValue(reminderScheduler),
    ],
    telemetry: telemetry,
    rawInputPolicy: policy,
    syncCoordinator: coordinator,
    reminderCoordinator: reminderCoordinator,
  );
}

/// 启动期附件残留兜底清扫（§5.6㉑、§11.2 W11-12「>7 天残留强制清理」）：
/// 进程中断/焚毁失败的漏网残留由 core_db AttachmentsDao.purgeExpired 强制
/// 焚毁（active 超龄行推 burned；burned 行意外残留文件防御性删除）。启动期
/// 一次性、尽力而为——失败不阻塞启动（行保持 active，下轮启动重试，
/// §6.1 降级纪律）。
Future<void> _sweepAttachmentResidue(db.AppDatabase database) async {
  try {
    await db.AttachmentsDao(database).purgeExpired();
  } on Object {
    // 清扫失败静默（下轮启动重试，§6.1）。
  }
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

/// 次日留存启动锚点产出（W9-10 北极星口径，§12「次日留存」）。
class RetentionAnchor {
  const RetentionAnchor({
    required this.firstOpenDay,
    required this.isFirstOpen,
    required this.dayOffset,
  });

  /// 首次启动日（本地日历日 yyyy-MM-dd；settings 本地件，之后恒定）。
  final String firstOpenDay;

  /// 本次启动是否为首次启动（首次=true → 漏斗记 first_open）。
  final bool isFirstOpen;

  /// 距首次启动的日历日偏移（0=当日、1=次日；次日留存分母=首次启动设备，
  /// 分子=存在 day_offset==1 的 app_open 的设备——本地 JSONL 可算）。
  final int dayOffset;
}

/// 确保首次启动日锚点就绪并返回（W9-10 北极星·次日留存，§11.1）。
///
/// 首次启动：写 settings（`first_open_day` = 本地日历日 JSON 字符串）→
/// [RetentionAnchor](isFirstOpen=true, dayOffset=0)；此后启动复用存储值并
/// 计算日偏移。损坏值（非法 JSON / 非法日历日）视同未存储重新锚定——本地件
/// 自愈（§5.6⑲ 同 device_id 口径）；代价只是留存曲线从当天重新起算。
///
/// 日偏移按 UTC 午末日历日差计算（双端无时区/夏令时漂移）。
Future<RetentionAnchor> ensureFirstOpenDay(
  db.AppDatabase database, {
  DateTime Function()? now,
}) async {
  final today = (now ?? DateTime.now)();
  final todayDay = formatCalendarDay(today);
  final row = await (database.select(database.settings)
        ..where((s) => s.key.equals(_kFirstOpenDayKey)))
      .getSingleOrNull();
  if (row != null) {
    try {
      final stored = jsonDecode(row.value) as String;
      if (_isRealCalendarDay(stored)) {
        return RetentionAnchor(
          firstOpenDay: stored,
          isFirstOpen: false,
          dayOffset: _calendarDayOffset(stored, todayDay),
        );
      }
    } on Object {
      // 损坏值：落入下方重新锚定（settings ⑲ 本地件自愈）。
    }
  }
  await database.into(database.settings).insertOnConflictUpdate(
        db.Setting(key: _kFirstOpenDayKey, value: jsonEncode(todayDay)),
      );
  return RetentionAnchor(
    firstOpenDay: todayDay,
    isFirstOpen: true,
    dayOffset: 0,
  );
}

/// 两个日历日（yyyy-MM-dd）的整数日偏移（to - from；UTC 午末日差，免时区
/// 与夏令时漂移）。
int _calendarDayOffset(String from, String to) {
  final fromDate = DateTime.utc(
    int.parse(from.substring(0, 4)),
    int.parse(from.substring(5, 7)),
    int.parse(from.substring(8, 10)),
  );
  final toDate = DateTime.utc(
    int.parse(to.substring(0, 4)),
    int.parse(to.substring(5, 7)),
    int.parse(to.substring(8, 10)),
  );
  return toDate.difference(fromDate).inDays;
}

/// 形状（§5.1 日历日正则）与语义（真实存在日期）双重校验——`9999-99-99`
/// 这类形状合格但语义坏值视同未存储（自愈重新锚定）。
bool _isRealCalendarDay(String value) {
  if (!isValidCalendarDay(value)) return false;
  final y = int.parse(value.substring(0, 4));
  final m = int.parse(value.substring(5, 7));
  final d = int.parse(value.substring(8, 10));
  final date = DateTime.utc(y, m, d);
  return date.year == y && date.month == m && date.day == d;
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
