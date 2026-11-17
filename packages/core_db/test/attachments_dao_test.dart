/// AttachmentsDao 测试（§5.6㉑ attachments、§3.3 拍照通道、§11.2 W11-12）。
///
/// 覆盖：
/// 1. insert：审计元数据登记（本地路径/哈希/字节大小/mime/kind/entry 关联），
///    状态起步 active、burned_at/blob_ref 空（原图不落服务端，§5.6）；
///    content_hash 查重（去重由应用层查重保证，§5.6）；
/// 2. 即焚状态机（§3.3）：active→burned 单向——先焚内容（Fake 清理器收到
///    local_path）再落状态；元数据保留（保留审计元数据不保留内容）；重复
///    即焚幂等（保留首次即焚时刻）；无此行 StateError；焚毁失败行保持
///    active 可重试（不产生「burned 而内容在」的残留，§3.9）；
/// 3. purgeExpired 边界（§11.2「>7 天残留强制清理」）：恰好 7 天不焚、
///    超 1ms 即焚；active 超龄强制 burned；burned 超龄只清防御性残留文件、
///    行不动；未超龄不碰；id 非 UUIDv7 保守跳过；单文件失败降级继续；
/// 4. backfillAttachmentBurnColumns：v1 旧形态库幂等补列（存量行落列默认
///    值、drift 生成查询可用）、新库 no-op（§6.4 只加列、schemaVersion=1）。
///
/// 测试纪律：内容焚毁一律 Fake 清理器（内存集合模拟文件存在性，不触真实
/// 文件系统）；无网络、无相机。运行前提同既有策略（宿主缺 sqlite3 运行库
/// 时温和跳过）。
library;

import 'dart:math';

import 'package:core_db/core_db.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

/// 内容焚毁 Fake：以内存集合模拟「文件当前存在」——
/// - [present] 含该路径 → 视为文件存在：移除并返回 true（本次焚毁成功）；
/// - 不含 → 文件本已不存在，返回 false（同真实文件系统幂等语义）；
/// - [failPaths] 内的路径模拟删除失败（抛异常，行不得先行落状态）。
///
/// callable class（`call` 与 `AttachmentContentCleaner` 函数签名一致，
/// 注入时以 `cleaner.call` 显式 tear-off——该「接口」为 typedef 而非类）。
class FakeContentCleaner {
  FakeContentCleaner({Set<String>? failPaths}) : failPaths = failPaths ?? {};

  final Set<String> failPaths;
  final Set<String> present = {};
  final List<String> calls = [];

  Future<bool> call(String localPath) async {
    calls.add(localPath);
    if (failPaths.contains(localPath)) {
      throw StateError('模拟删除失败：$localPath');
    }
    if (!present.contains(localPath)) {
      return false;
    }
    present.remove(localPath);
    return true;
  }
}

void main() {
  /// 固定时间戳的 UUIDv7（即焚「残留时长」判据 = id 内嵌时间戳，§5.6⑭）。
  ///
  /// [seed] 区分同刻多行（随机段不同 → 主键不同；内嵌时间戳相同 → 年龄
  /// 判据一致）。
  String idAt(int ms, {int seed = 7}) =>
      generateUuidV7(timestampMs: ms, random: Random(seed));

  const int bornAtMs = 1763251200000; // 与 TestClock 基准同一时钟域

  test('insert：审计元数据登记、active 起步、blob_ref 空；content_hash 查重',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AttachmentsDao 测试未执行');
      return;
    }
    try {
      final cleaner = FakeContentCleaner();
      final dao = AttachmentsDao(db, contentCleaner: cleaner.call);
      final hash = 'aa' * 32; // fixture：sha256 十六进制摘要形态

      final photo = await dao.insert(
        contentHash: hash,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 123456,
        localPath: '/data/tmp/photo_1.jpg',
        entryId: null, // 拍照先于事件落库：entry_id 允许为空（§5.6㉑）
        id: idAt(bornAtMs),
      );
      cleaner.present.add(photo.localPath); // 模拟压缩产物已写入本地路径
      expect(photo.status, kAttachmentStatusActive,
          reason: '§3.3 状态机起点：active（本地内容存在）');
      expect(photo.burnedAt, isNull, reason: '未焚毁：burned_at NULL');
      expect(photo.blobRef, isNull,
          reason: '§5.6㉑ 默认即焚为 NULL——原图不落服务端');
      expect(photo.contentHash, hash);
      expect(photo.kind, 'photo');
      expect(photo.mime, 'image/jpeg');
      expect(photo.sizeBytes, 123456);
      expect(photo.localPath, '/data/tmp/photo_1.jpg');
      expect(photo.entryId, isNull);
      expect(uuidV7TimestampMs(photo.id), bornAtMs,
          reason: 'id 内嵌时间戳即残留时长判据（不另设 created_at，§5.6⑭）');

      // entry 关联（解析成功回填所属事件）：登记时直接带 entry_id。
      final linked = await dao.insert(
        contentHash: 'bb' * 32,
        kind: kAttachmentKindReceipt,
        mime: 'image/jpeg',
        sizeBytes: 2048,
        localPath: '/data/tmp/receipt_1.jpg',
        entryId: 'entry-photo-1',
      );
      expect(linked.entryId, 'entry-photo-1');
      expect(linked.status, kAttachmentStatusActive);

      // content_hash 查重（§5.6「去重由应用层查重保证」）：同 hash 命中最新行。
      final again = await dao.insert(
        contentHash: hash, // 同图重拍/重复登记
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 123456,
        localPath: '/data/tmp/photo_2.jpg',
        id: idAt(bornAtMs + 5),
      );
      final dedupeHit = await dao.findLatestByContentHash(hash);
      expect(dedupeHit!.id, again.id, reason: '同 hash 取最新登记（id 时间有序）');
      expect(await dao.findLatestByContentHash('ff' * 32), isNull);

      // 登记不触发焚毁（焚毁只属于 markBurned/purgeExpired 两条路径）。
      expect(cleaner.calls, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('即焚状态机：active→burned 单向、先焚内容再落状态、元数据保留、'
      '重复即焚幂等、焚毁失败可重试', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AttachmentsDao 测试未执行');
      return;
    }
    try {
      final cleaner = FakeContentCleaner();
      final dao = AttachmentsDao(db, contentCleaner: cleaner.call);
      final row = await dao.insert(
        contentHash: 'cc' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 4096,
        localPath: '/data/tmp/burn_me.jpg',
        entryId: 'entry-burn-1',
        id: idAt(bornAtMs),
      );
      cleaner.present.add(row.localPath);

      // 即焚：Fake 清理器收到 local_path（先焚内容），随后状态落 burned。
      const burnAt = bornAtMs + 60_000;
      final burned = await dao.markBurned(row.id, atMs: burnAt);
      expect(burned.status, kAttachmentStatusBurned);
      expect(burned.burnedAt, burnAt);
      expect(cleaner.calls, ['/data/tmp/burn_me.jpg']);
      expect(cleaner.present.contains('/data/tmp/burn_me.jpg'), isFalse,
          reason: '内容本体已焚毁（§3.3「解析后即焚不落存储」）');

      // 保留审计元数据不保留内容（任务口径）：元数据逐字段原样。
      expect(burned.contentHash, row.contentHash);
      expect(burned.mime, row.mime);
      expect(burned.sizeBytes, row.sizeBytes);
      expect(burned.localPath, row.localPath, reason: '路径为审计元数据保留');
      expect(burned.entryId, row.entryId);
      expect(burned.blobRef, isNull, reason: '原图不落服务端（§5.6）');

      // 单向状态机：重复即焚 no-op——保留首次即焚时刻、不再触发焚毁
      // （与 §6.5「完成事件只前进」同一时间语义）。
      final again = await dao.markBurned(row.id, atMs: burnAt + 99);
      expect(again.status, kAttachmentStatusBurned);
      expect(again.burnedAt, burnAt, reason: '不覆盖首次即焚时刻');
      expect(cleaner.calls.length, 1, reason: 'burned 终态不再触发清理器');

      // 文件本已不存在（如已被调用方手工删除）：焚毁语义幂等成立，状态照常
      // 推进（清理器返回 false≠失败）。
      final gone = await dao.insert(
        contentHash: 'ee' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 1024,
        localPath: '/data/tmp/never_written.jpg',
        id: idAt(bornAtMs + 1),
      );
      // 刻意不把 localPath 放进 cleaner.present——模拟文件不存在。
      final goneBurned = await dao.markBurned(gone.id, atMs: burnAt + 1);
      expect(goneBurned.status, kAttachmentStatusBurned);
      expect(goneBurned.burnedAt, burnAt + 1);

      // 焚毁失败：异常上抛、行保持 active（不产生「burned 而内容在」残留），
      // 修复后重试成功（§3.9 合规红线）。
      final flaky = FakeContentCleaner(
        failPaths: {'/data/tmp/flaky.jpg'},
      )..present.add('/data/tmp/flaky.jpg');
      final retryDao = AttachmentsDao(db, contentCleaner: flaky.call);
      final flakyRow = await retryDao.insert(
        contentHash: 'dd' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 8192,
        localPath: '/data/tmp/flaky.jpg',
        id: idAt(bornAtMs + 10),
      );
      await expectLater(
        retryDao.markBurned(flakyRow.id, atMs: burnAt),
        throwsStateError,
      );
      final stillActive = (await dao.findById(flakyRow.id))!;
      expect(stillActive.status, kAttachmentStatusActive,
          reason: '内容未焚毁：状态不得先行');
      expect(stillActive.burnedAt, isNull);
      // 修复（模拟重试时删除不再失败）后重试成功。
      flaky.failPaths.clear();
      final retried = await retryDao.markBurned(flakyRow.id, atMs: burnAt + 1);
      expect(retried.status, kAttachmentStatusBurned);
      expect(retried.burnedAt, burnAt + 1, reason: '重试即焚以成功时刻落状态');

      // 无此行：StateError（§5.6㉑）。
      await expectLater(dao.markBurned('ghost-photo'), throwsStateError);
    } finally {
      await db.close();
    }
  });

  test('purgeExpired 边界：恰好 7 天不焚、超 1ms 即焚；active 强制焚毁、'
      'burned 只清残留文件、非 UUIDv7 保守跳过、单文件失败降级', () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AttachmentsDao 测试未执行');
      return;
    }
    try {
      final cleaner = FakeContentCleaner();
      final dao = AttachmentsDao(db, contentCleaner: cleaner.call);
      final retentionMs = kAttachmentBurnRetention.inMilliseconds;

      // ① 边界：残留恰为 7 天（now-born == retention）→「>7 天」不含等号，
      //    不焚；超 1ms → 强制焚毁。
      final boundary = await dao.insert(
        contentHash: '11' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 1,
        localPath: '/data/tmp/boundary.jpg',
        id: idAt(bornAtMs),
      );
      cleaner.present.add(boundary.localPath);

      var report = await dao.purgeExpired(nowMs: bornAtMs + retentionMs);
      var row = (await dao.findById(boundary.id))!;
      expect(row.status, kAttachmentStatusActive,
          reason: '恰好 7 天不算残留（严格大于）');
      expect(report.forceBurned, 0);
      expect(report.filesDeleted, 0);

      report = await dao.purgeExpired(nowMs: bornAtMs + retentionMs + 1);
      row = (await dao.findById(boundary.id))!;
      expect(row.status, kAttachmentStatusBurned, reason: '>7 天强制焚毁');
      expect(row.burnedAt, bornAtMs + retentionMs + 1,
          reason: '强制即焚时刻=本次清扫时刻');
      expect(report.forceBurned, 1);
      expect(report.filesDeleted, 1);
      expect(cleaner.present.contains('/data/tmp/boundary.jpg'), isFalse);

      // ② 未超龄 active：不碰（出生时刻贴着清扫时刻，残留≈0）。
      final freshBornAtMs = bornAtMs + retentionMs + 2;
      final fresh = await dao.insert(
        contentHash: '22' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 2,
        localPath: '/data/tmp/fresh.jpg',
        id: idAt(freshBornAtMs),
      );
      cleaner.present.add(fresh.localPath);
      report = await dao.purgeExpired(nowMs: freshBornAtMs);
      row = (await dao.findById(fresh.id))!;
      expect(row.status, kAttachmentStatusActive);
      expect(report.forceBurned, 0, reason: '未超龄行不焚');
      expect(report.filesDeleted, 0);

      // ③ burned 超龄残留文件（防御性）：只删文件，行状态/即焚时刻不动。
      final burnedEarly = await dao.insert(
        contentHash: '33' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 3,
        localPath: '/data/tmp/already_burned.jpg',
        id: idAt(bornAtMs, seed: 8),
      );
      cleaner.present.add(burnedEarly.localPath);
      await dao.markBurned(burnedEarly.id, atMs: bornAtMs + 1000);
      cleaner.present.add(burnedEarly.localPath); // 模拟文件复活残留
      report = await dao.purgeExpired(
        nowMs: bornAtMs + retentionMs + 3,
      );
      row = (await dao.findById(burnedEarly.id))!;
      expect(row.status, kAttachmentStatusBurned);
      expect(row.burnedAt, bornAtMs + 1000, reason: '保留首次即焚时刻');
      expect(report.forceBurned, 0, reason: '已焚行不计入强制即焚');
      expect(report.filesDeleted, 1, reason: '防御性清除复活残留文件');

      // ④ id 非 UUIDv7 形态（时长来源不明）：保守跳过，绝不误焚。
      await db.into(db.attachments).insert(
            AttachmentsCompanion.insert(
              id: 'legacy-plain-id',
              contentHash: '44' * 32,
              kind: kAttachmentKindPhoto,
              mime: 'image/jpeg',
              sizeBytes: 4,
              localPath: '/data/tmp/legacy.jpg',
            ),
          );
      report = await dao.purgeExpired(
        nowMs: bornAtMs + retentionMs * 10,
      );
      row = (await dao.findById('legacy-plain-id'))!;
      expect(row.status, kAttachmentStatusActive, reason: '时长不明不焚');
      // 此刻 ② 的 fresh 行也已超龄（active）→ 被正常强制焚毁 1 行。
      expect(report.forceBurned, 1, reason: 'fresh 已超龄照常焚毁（不影响本断言点）');
      expect(report.filesDeleted, 1);
      expect((await dao.findById(fresh.id))!.status, kAttachmentStatusBurned);

      // ⑤ 单文件删除失败：降级继续（行保持 active，下轮重试），不阻断清扫。
      final stuckFail = {'/data/tmp/stuck.jpg'};
      final sweepCleaner = FakeContentCleaner(failPaths: stuckFail)
        ..present.add('/data/tmp/stuck.jpg');
      final sweepDao = AttachmentsDao(db, contentCleaner: sweepCleaner.call);
      final stuck = await sweepDao.insert(
        contentHash: '55' * 32,
        kind: kAttachmentKindPhoto,
        mime: 'image/jpeg',
        sizeBytes: 5,
        localPath: '/data/tmp/stuck.jpg',
        id: idAt(bornAtMs, seed: 9),
      );
      final stuckReport = await sweepDao.purgeExpired(
        nowMs: bornAtMs + retentionMs + 4,
      );
      expect(stuckReport.forceBurned, 0, reason: '焚毁失败不推进状态');
      expect(stuckReport.filesDeleted, 0);
      expect((await dao.findById(stuck.id))!.status, kAttachmentStatusActive);
      // 修复后重跑：正常强制焚毁。
      stuckFail.clear();
      final healed = await sweepDao.purgeExpired(
        nowMs: bornAtMs + retentionMs + 5,
      );
      expect(healed.forceBurned, 1);
      expect((await dao.findById(stuck.id))!.status, kAttachmentStatusBurned);
    } finally {
      await db.close();
    }
  });

  test('backfillAttachmentBurnColumns：v1 旧形态库幂等补列、新库 no-op',
      () async {
    final db = await tryOpenTestDatabase();
    if (db == null) {
      // ignore: avoid_print
      print('SKIP：宿主缺 sqlite3 运行库，AttachmentsDao 测试未执行');
      return;
    }
    try {
      // 新库（createAll 已含两列）：no-op 幂等。
      await backfillAttachmentBurnColumns(db);
      final probe = await _insertProbe(db);
      expect(probe.status, kAttachmentStatusActive);

      // 模拟 v1 旧形态库：丢弃现表，按 §5.6㉑ 文档字段（无 status/burned_at）
      // 重建并放入存量行。
      await db.customStatement('DROP TABLE attachments');
      await db.customStatement(
        'CREATE TABLE attachments ('
        'id TEXT NOT NULL PRIMARY KEY, '
        'entry_id TEXT NULL, '
        'content_hash TEXT NOT NULL, '
        'kind TEXT NOT NULL, '
        'mime TEXT NOT NULL, '
        'size_bytes INTEGER NOT NULL, '
        'local_path TEXT NOT NULL, '
        'blob_ref TEXT NULL)',
      );
      await db.customStatement(
        "INSERT INTO attachments (id, entry_id, content_hash, kind, mime, "
        "size_bytes, local_path, blob_ref) VALUES ('legacy-row', NULL, "
        "'6633', 'photo', 'image/jpeg', 512, '/data/tmp/legacy.jpg', NULL)",
      );

      await backfillAttachmentBurnColumns(db);

      // 补列后 drift 生成查询可用：存量行落列默认值（status='active'、
      // burned_at NULL——SQLite ADD COLUMN DEFAULT 语义，§6.4 只加列）。
      final legacy = await (db.select(db.attachments)
            ..where((t) => t.id.equals('legacy-row')))
          .getSingle();
      expect(legacy.status, kAttachmentStatusActive,
          reason: '补列默认值落位：旧行视为「本地内容存在」');
      expect(legacy.burnedAt, isNull);
      expect(legacy.localPath, '/data/tmp/legacy.jpg');
      expect(legacy.contentHash, '6633');

      // 幂等重跑：不报错、数据不动。
      await backfillAttachmentBurnColumns(db);
      final legacyAgain = await (db.select(db.attachments)
            ..where((t) => t.id.equals('legacy-row')))
          .getSingle();
      expect(legacyAgain.status, kAttachmentStatusActive);
      expect(legacyAgain.burnedAt, isNull);
    } finally {
      await db.close();
    }
  });
}

/// 新库探针：确认 createAll 出的 attachments 已含即焚两列且可直接落行。
Future<Attachment> _insertProbe(AppDatabase db) {
  final dao = AttachmentsDao(db, contentCleaner: (_) async => false);
  return dao.insert(
    contentHash: '77' * 32,
    kind: kAttachmentKindPhoto,
    mime: 'image/jpeg',
    sizeBytes: 16,
    localPath: '/data/tmp/probe.jpg',
    id: generateUuidV7(timestampMs: 1763251200000, random: Random(7)),
  );
}
