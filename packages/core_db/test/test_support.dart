/// core_db 测试支撑：内存库工厂、sqlite3 缺库跳过、领域实体夹具。
///
/// Windows 宿主可能缺 sqlite3 运行库（sqlite3.dll）——[tryOpenTestDatabase]
/// 探测后返回 null，调用方温和跳过（与 W1 schema 冒烟测试同一策略）。
library;

import 'dart:math';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart' as domain;
import 'package:drift/native.dart';

/// 判断是否为「宿主缺 sqlite3 运行库」类错误。
bool isSqliteLibraryMissing(Object error) {
  final msg = error.toString().toLowerCase();
  return msg.contains('failed to load dynamic library') ||
      msg.contains('sqlite3.dll') ||
      (msg.contains('sqlite') && msg.contains('library'));
}

/// 打开内存库（首个查询触发 migration + 默认数据 seed）；宿主缺 sqlite3
/// 运行库时返回 null，由调用方决定跳过。
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
    if (isSqliteLibraryMissing(error)) {
      return null;
    }
    rethrow;
  }
}

/// 清空 sync_outbox（测试辅助）。
///
/// W7-8「全写路径 outbox 补课」后，beforeOpen 的默认数据 seed（§5.4）会把
/// 24 条 seed 行（categories 22 + ledgers 2，§5.1 同步真值表）同事务入队
/// sync_outbox——需要精确断言「本次业务写出网行数」的测试先清空 seed 出网
/// 项，从「干净 outbox」起步。seed 入队语义（全量入队/幂等/完整性）由
/// seed_idempotency_test 与本文件 seed 用例专属覆盖，不走本辅助。
Future<void> drainSeedOutbox(db.AppDatabase database) async {
  await database.delete(database.syncOutbox).go();
}

/// 测试用行戳源：物理毫秒逐次自增，保证 hlc 全序单调（§6.3）。
class TestClock {
  TestClock(this.deviceId, {int? baseMs})
      : _next = baseMs ?? 1763251200000;

  /// 12 位 hex 设备标识（§6.3 device_id 段）。
  final String deviceId;
  int _next;

  int _take() => _next++;

  /// 下一枚 §5.1 公共列集合（created_at/updated_at 同刻、hlc 定宽编码）。
  domain.SyncMeta meta({int revision = 1}) {
    final t = _take();
    return domain.SyncMeta(
      createdAt: t,
      updatedAt: t,
      hlc: domain.Hlc(physicalMs: t, counter: 0, deviceId: deviceId).format(),
      revision: revision,
      deviceId: deviceId,
    );
  }

  /// 下一枚删除操作时间戳（softDelete 的 hlc 参数）。
  String hlc() {
    final t = _take();
    return domain.Hlc(physicalMs: t, counter: 0, deviceId: deviceId).format();
  }
}

/// 造一条领域事件（§5.2① entries；校验在领域构造器内完成）。
domain.Entry makeEntry(
  TestClock clock, {
  required String id,
  required String date,
  domain.EntryKind kind = domain.EntryKind.expense,
  domain.EntrySource source = domain.EntrySource.manual,
  domain.EntryStatus status = domain.EntryStatus.confirmed,
  String title = '测试事件',
  String? note,
  int tzOffsetMin = 480,
  domain.SyncMeta? meta,
}) =>
    domain.Entry(
      id: id,
      date: date,
      tzOffsetMin: tzOffsetMin,
      kind: kind,
      source: source,
      title: title,
      note: note,
      status: status,
      meta: meta ?? clock.meta(),
    );

/// 造一条领域产出行（§5.2② entry_lines；kcal/金额单位口径见 §5.1）。
domain.EntryLine makeLine(
  TestClock clock, {
  required String id,
  required String entryId,
  required domain.LineType type,
  required int amount,
  required domain.LineDirection direction,
  String? ledgerId,
  String? categoryId,
  String? currency,
  double? confidence,
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
      confidence: confidence,
      status: status,
      correctionOf: correctionOf,
      meta: meta ?? clock.meta(),
    );

/// 确定性 UUIDv7（注入 [Random] 种子，§5.1 主键约定）。
String seededUuid(Random rng, {int timestampMs = 1763251200000}) =>
    db.generateUuidV7(timestampMs: timestampMs, random: rng);
