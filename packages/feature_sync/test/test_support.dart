/// feature_sync 测试支撑：双设备同步夹具（§6.7 验收自动化、§11.1 W5-6
/// 冲突测试集的公共底座）。
///
/// 组装要点（§6.2 装配契约、§10.4 壳层装配的测试等价物）：
/// - 每台设备独立内存库（migration + 默认数据 seed，§5.4）+ 确定性 12 位
///   hex 设备标识（覆写 settings，§6.3 节点段）；
/// - **共享 HLC 时钟**：发戳（写路径）与引擎 recv（同步层）用同一
///   [domain.HlcClock] 实例——生产装配点必须如此，测试夹具同构（§6.3）；
/// - 共享 [InMemorySyncBackend] 模拟远端（Fake，禁真实网络，§6.7）；
/// - 本地写辅助 = §6.2 写路径第一步：业务行与 outbox 出网项**同事务**入队；
/// - Windows 宿主缺 sqlite3 运行库时 [SyncHarness.open] 返回 null，
///   调用方温和跳过（与 core_db 仓库测试同一策略）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';

import 'package:feature_sync/feature_sync.dart';

/// 夹具基准墙钟：2026-11-16T00:00:00Z（§6.3 物理段=UTC 毫秒）。
const int kHarnessBaseWallMs = 1763251200000;

/// 夹具基准日（§2.3 日期口径：本地日 YYYY-MM-DD）。
const String kHarnessDate = '2026-11-16';

/// 虚拟墙钟：测试显式推进，不发真实时间（确定性全序）。
class VirtualWall {
  VirtualWall(this._nowMs);

  int _nowMs;

  int take() => _nowMs;

  /// 推进 n 毫秒（模拟时间流逝/设备时钟偏差）。
  void advance(int ms) => _nowMs += ms;
}

/// 单台设备夹具：内存库 + 共享时钟 + outbox + 引擎（§6.2 装配契约）。
class SyncDeviceFixture {
  SyncDeviceFixture._({
    required this.deviceId,
    required this.database,
    required this.wall,
    required this.clock,
    required this.entryRepo,
    required this.lineRepo,
    required this.outbox,
    required this.store,
    required this.backend,
  }) : rng = Random(deviceId.hashCode ^ kHarnessBaseWallMs);

  /// 单设备建夹具：开库 → 覆写设备标识 → 组装同步层。
  static Future<SyncDeviceFixture> open(
    InMemorySyncBackend backend,
    String deviceId,
    int baseWallMs,
  ) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    // 首查询触发 migration + 默认数据 seed（§5.4）。
    await database.customSelect('SELECT 1').getSingle();
    // 覆写 settings.device_id 为确定性 12 位 hex（§6.3 节点段）：
    // 必须发生在 LocalWriteClock / DeviceRegistry 读取之前。
    await database.into(database.settings).insertOnConflictUpdate(
          db.SettingsCompanion.insert(
            key: db.kSettingDeviceId,
            value: jsonEncode(deviceId),
          ),
        );
    final wall = VirtualWall(baseWallMs);
    // 共享 HLC 时钟（§6.3）：写路径发戳与引擎 recv 同一实例。
    final clock = domain.HlcClock(deviceId: deviceId, wallClock: wall.take);
    final fixture = SyncDeviceFixture._(
      deviceId: deviceId,
      database: database,
      wall: wall,
      clock: clock,
      entryRepo: db.DriftEntryRepository(
        database,
        projection: db.DaySummaryProjection(database),
      ),
      lineRepo: db.DriftEntryLineRepository(
        database,
        projection: db.DaySummaryProjection(database),
      ),
      outbox: DriftSyncOutboxStore(database),
      store: DriftSyncLocalStore(database, deviceId: deviceId),
      backend: backend,
    );
    fixture.engine = LocalSyncEngine(
      backend: backend,
      outbox: fixture.outbox,
      store: fixture.store,
      deviceId: deviceId,
      clock: clock,
      listener: (status) => fixture.statuses.add(status),
    );
    return fixture;
  }

  /// 设备标识（12 位 hex，§6.3）。
  final String deviceId;

  /// 本设备内存库（命名避开 `db` 导入前缀，防止实例成员遮蔽前缀解析）。
  final db.AppDatabase database;

  /// 虚拟墙钟。
  final VirtualWall wall;

  /// 共享 HLC 时钟（写路径发戳 + 引擎 recv，§6.3）。
  final domain.HlcClock clock;

  /// 事件仓库（W2 校验路径：墓碑/投影联动，§5.2①）。
  final db.DriftEntryRepository entryRepo;

  /// 产出行仓库（W2 校验路径：金额不可变/supersede，§5.2②）。
  final db.DriftEntryLineRepository lineRepo;

  /// 出网队列（§5.6⑯）。
  final DriftSyncOutboxStore outbox;

  /// pull 落库/游标/回写（§5.6⑱）。
  final DriftSyncLocalStore store;

  /// 共享远端。
  final InMemorySyncBackend backend;

  /// 引擎（open 时装配）。
  late final LocalSyncEngine engine;

  /// 引擎状态回调记录（顶栏小圆点断言用，§6.1 原则 1）。
  final List<SyncStatus> statuses = [];

  /// 确定性行 id 源（UUIDv7，§5.1）。
  final Random rng;

  String nextUuid() => db.generateUuidV7(timestampMs: wall.take(), random: rng);

  // ── 发戳与造行（§5.1 公共列 + §6.3 HLC）──────────────────────────────

  /// 下一枚行戳：经共享时钟签发（与引擎 recv 同源，§6.3）。
  domain.SyncMeta stamp({int revision = 1, int? deletedAt}) {
    final hlc = clock.now();
    return domain.SyncMeta(
      createdAt: hlc.physicalMs,
      updatedAt: hlc.physicalMs,
      deletedAt: deletedAt,
      hlc: hlc.format(),
      revision: revision,
      deviceId: deviceId,
    );
  }

  /// 事件编辑戳：保留原 created_at、revision 自增（§5.1 公共列语义）。
  domain.SyncMeta stampEdit(domain.SyncMeta base) =>
      stamp(revision: base.revision + 1).copyWith(createdAt: base.createdAt);

  /// 造一条领域事件（§5.2①）。
  domain.Entry makeEntry({
    required String id,
    String date = kHarnessDate,
    String title = '测试事件',
    domain.EntryStatus status = domain.EntryStatus.confirmed,
    domain.SyncMeta? meta,
  }) =>
      domain.Entry(
        id: id,
        date: date,
        tzOffsetMin: 480,
        kind: domain.EntryKind.expense,
        source: domain.EntrySource.manual,
        title: title,
        status: status,
        meta: meta ?? stamp(),
      );

  /// 造一条领域产出行（§5.2②）。
  domain.EntryLine makeLine({
    required String id,
    required String entryId,
    required domain.LineType type,
    required int amount,
    required domain.LineDirection direction,
    String? ledgerId,
    String? categoryId,
    String? currency,
    domain.LineStatus status = domain.LineStatus.active,
    String? correctionOf,
    domain.SyncMeta? meta,
  }) =>
      domain.EntryLine(
        id: id,
        entryId: entryId,
        type: type,
        amount: amount,
        direction: direction,
        ledgerId: ledgerId,
        categoryId: categoryId,
        currency: currency,
        status: status,
        correctionOf: correctionOf,
        meta: meta ?? stamp(),
      );

  /// 本设备默认记账账本 id（金额行挂账本用，§5.2②/§5.4）。
  Future<String> defaultLedgerId() async =>
      (await db.LedgerDao(database).defaultMoneyLedger())!.id;

  // ── 本地写辅助（§6.2 写路径第一步：业务行 + outbox 同事务）────────────

  /// 写一笔事件（可带产出行）；返回各行戳（hlc 断言用）。
  Future<List<domain.SyncMeta>> writeEntryWithLines(
    domain.Entry entry, [
    List<domain.EntryLine> lines = const [],
  ]) async {
    final stamped = <domain.SyncMeta>[entry.meta];
    await database.transaction(() async {
      await entryRepo.upsert(entry);
      await _enqueue('entries', entry.meta, entry.toJson());
      for (final line in lines) {
        await lineRepo.upsert(line);
        stamped.add(line.meta);
        await _enqueue('entry_lines', line.meta, line.toJson());
      }
    });
    return stamped;
  }

  /// 编辑事件标题（存活行，走 W2 仓库校验 + 出网）。
  Future<domain.SyncMeta> editEntryTitle(String entryId, String newTitle) async {
    final existing = (await entryRepo.findById(entryId))!;
    final meta = stampEdit(existing.meta);
    final edited = existing.copyWith(title: newTitle, meta: meta);
    await database.transaction(() async {
      await entryRepo.upsert(edited);
      await _enqueue('entries', meta, edited.toJson(),
          baseRevision: existing.meta.revision);
    });
    return meta;
  }

  /// 编辑产出行 amount（仅 calorie/burn 行；金额行走修正链，§5.2②）。
  Future<domain.SyncMeta> editLineAmount(String lineId, int newAmount) async {
    final existing = (await lineRepo.findById(lineId))!;
    final meta = stampEdit(existing.meta);
    final edited = existing.copyWith(amount: newAmount, meta: meta);
    await database.transaction(() async {
      await lineRepo.upsert(edited);
      await _enqueue('entry_lines', meta, edited.toJson(),
          baseRevision: existing.meta.revision);
    });
    return meta;
  }

  /// 金额行修正（§5.2②：新增 correction 行、旧行 status→superseded，
  /// 两行各自出网——修正链的合法改写路径）。
  Future<List<domain.SyncMeta>> supersedeMoneyLine(
    String oldLineId,
    domain.EntryLine correction,
  ) async {
    final stamped = <domain.SyncMeta>[];
    await database.transaction(() async {
      await lineRepo.supersede(oldLineId, correction);
      stamped.add(correction.meta);
      final oldRow = (await lineRepo.findById(oldLineId))!;
      stamped.add(oldRow.meta);
      // 旧行状态位更新与新 correction 行各自入队（同一事务）。
      await _enqueue('entry_lines', oldRow.meta, oldRow.toJson());
      await _enqueue('entry_lines', correction.meta, correction.toJson());
    });
    return stamped;
  }

  /// 软删事件（墓碑出网，§5.1 删除行/§6.5）；返回墓碑 hlc。
  Future<String> deleteEntry(String entryId) async {
    final hlc = clock.now().format();
    await database.transaction(() async {
      await entryRepo.softDelete(entryId, hlc: hlc);
      final tomb = (await entryRepo.findById(entryId))!;
      await _enqueue(
        'entries',
        tomb.meta,
        tomb.toJson(),
        op: domain.OutboxOp.delete,
      );
    });
    return hlc;
  }

  /// 直接入队一条手工构造的出网项（模拟「陈旧副本上送」等合成场景；
  /// 不经本地仓库——绕过本地校验，由服务端仲裁，§6.2）。
  Future<void> enqueueRaw({
    required String tableName,
    required String rowId,
    required Map<String, Object?> payload,
    required String hlc,
    int? baseRevision,
    domain.OutboxOp op = domain.OutboxOp.upsert,
  }) =>
      outbox.enqueue(
        domain.OutboxEntry(
          id: nextUuid(),
          tableName: tableName,
          rowId: rowId,
          op: op,
          payload: jsonEncode(payload),
          baseRevision: baseRevision,
          hlc: hlc,
          createdAt: domain.Hlc.parse(hlc).physicalMs,
        ),
      );

  Future<void> _enqueue(
    String tableName,
    domain.SyncMeta meta,
    Map<String, Object?> payload, {
    int? baseRevision,
    domain.OutboxOp op = domain.OutboxOp.upsert,
  }) =>
      outbox.enqueue(
        domain.OutboxEntry(
          id: nextUuid(),
          tableName: tableName,
          rowId: payload['id'] as String,
          op: op,
          payload: jsonEncode(payload),
          baseRevision: baseRevision,
          hlc: meta.hlc,
          createdAt: meta.updatedAt,
        ),
      );

  // ── 断言辅助 ──────────────────────────────────────────────────────────

  /// 读本地行原始快照（snake_case 平铺）。
  Future<Map<String, Object?>?> rawRow(String table, String id) async {
    final rows = await database
        .customSelect('SELECT * FROM "$table" WHERE id = ?',
            variables: [Variable.withString(id)])
        .get();
    return rows.isEmpty ? null : rows.first.data;
  }

  /// 未确认出网项的 hlc 列表（按出队序：created_at, hlc，§6.2）。
  Future<List<String>> pendingHlcs() async {
    final rows = await database
        .customSelect(
            'SELECT hlc FROM "sync_outbox" WHERE acked_at IS NULL '
            'ORDER BY created_at, hlc')
        .get();
    return rows.map((r) => r.data['hlc'] as String).toList();
  }

  Future<int> pendingCount() => outbox.pendingCount();

  /// 读 day_summary 单日聚合（spend_minor/kcal_in/kcal_out/net_kcal）。
  Future<Map<String, int?>> daySummaryOf(String date) async {
    final rows = await database
        .customSelect(
            'SELECT spend_minor, income_minor, kcal_in, kcal_out, net_kcal '
            'FROM "day_summaries" WHERE date = ?',
            variables: [Variable.withString(date)])
        .get();
    if (rows.isEmpty) {
      return const <String, int?>{};
    }
    final d = rows.first.data;
    return <String, int?>{
      'spend_minor': d['spend_minor'] as int?,
      'income_minor': d['income_minor'] as int?,
      'kcal_in': d['kcal_in'] as int?,
      'kcal_out': d['kcal_out'] as int?,
      'net_kcal': d['net_kcal'] as int?,
    };
  }

  Future<void> close() => database.close();
}

/// 双设备同步夹具：共享远端 + N 台设备（§6.7 双设备一致脚本底座）。
class SyncHarness {
  SyncHarness._({
    required this.backend,
    required this.devices,
    required this.serverWall,
  });

  /// 开夹具：宿主缺 sqlite3 运行库时返回 null（调用方 SKIP）。
  static Future<SyncHarness?> open({
    required List<String> deviceIds,
    int baseWallMs = kHarnessBaseWallMs,
    int maxPullRows = 200,
  }) async {
    final probe = await tryOpenTestDatabase();
    if (probe == null) {
      return null;
    }
    await probe.close();
    final serverWall = VirtualWall(baseWallMs);
    final backend = InMemorySyncBackend(
      nowMs: serverWall.take,
      maxPullRows: maxPullRows,
    );
    final devices = <SyncDeviceFixture>[];
    for (final id in deviceIds) {
      devices.add(await SyncDeviceFixture.open(backend, id, baseWallMs));
    }
    return SyncHarness._(
      backend: backend,
      devices: devices,
      serverWall: serverWall,
    );
  }

  /// 共享内存远端（可分区/可断言服务端状态）。
  final InMemorySyncBackend backend;

  /// 设备夹具（[device] 取用）。
  final List<SyncDeviceFixture> devices;

  /// 服务端墙钟。
  final VirtualWall serverWall;

  SyncDeviceFixture device(int index) => devices[index];

  Future<void> close() async {
    for (final d in devices) {
      await d.close();
    }
  }
}

/// sqlite3 缺库探测（转发 core_db 测试策略）。
Future<db.AppDatabase?> tryOpenTestDatabase() async {
  final database = db.AppDatabase(NativeDatabase.memory());
  try {
    await database.customSelect('SELECT 1').getSingle();
    return database;
  } catch (error) {
    try {
      await database.close();
    } catch (_) {
      // 库加载失败的清理路径：忽略二次异常（原异常向上抛）。
    }
    final msg = error.toString().toLowerCase();
    if (msg.contains('failed to load dynamic library') ||
        msg.contains('sqlite3.dll') ||
        (msg.contains('sqlite') && msg.contains('library'))) {
      return null;
    }
    rethrow;
  }
}
