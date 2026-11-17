/// AttachmentsDao — 附件引用登记与「解析后即焚」状态机
/// （§5.6㉑ attachments、§3.3 拍照通道、§11.2 W11-12 主线）。
///
/// 合规红线（§3.3「原图解析后即焚不落存储」、§3.9「照片『解析后即焚+不落
/// 存储』落实」、§5.6「默认『解析后即焚』：原图不落服务端」）在数据层的
/// 落点：
/// - [insert]：拍照/压缩后登记审计元数据（本地路径/内容哈希/字节大小/mime），
///   状态起步 `active`（本地内容存在），blob_ref 恒 NULL（原图不落服务端）；
/// - [markBurned]：解析完成后即焚——**先焚毁本地内容（删文件）再落状态**，
///   状态机 `active → burned` 单向不可逆；burned 行保留全部审计元数据
///   （hash/size/mime/local_path/burned_at），只焚毁内容不抹除痕迹
///   （合规审计：照片曾在、何时焚毁）；
/// - [purgeExpired]：兜底清扫——超过保留期（默认 7 天）仍持有内容的残留
///   （进程中断/解析未回的 active 行）强制焚毁；已 burned 行的意外残留文件
///   （如系统恢复文件）防御性清除。残留时长取 id（UUIDv7）内嵌时间戳，
///   「时间可由 id 得出就不另设时间列」（§5.6⑭ 同口径）。
///
/// 同步边界：attachments 不在 §5.1「同步真值表 14 张」内——即焚生命周期
/// 不入 sync_outbox、不出网（服务端侧为结构化引用登记，见表注释）。
///
/// 内容焚毁经 [AttachmentContentCleaner] 注入：缺省实现为本地文件删除；
/// 测试注入 Fake（记录焚毁路径，不触真实文件系统）。文件删除失败时
/// [markBurned] 上抛（行保持 active、可重试），[purgeExpired] 逐行降级
/// 继续（清扫器尽力而为，下轮重试）。
library;

import 'dart:io';

import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid_v7.dart';

/// §5.6㉑ attachment.kind 枚举。
const String kAttachmentKindPhoto = 'photo';
const String kAttachmentKindReceipt = 'receipt';

/// §3.3 即焚状态机：active（本地内容存在）→ burned（内容已焚毁），单向。
const String kAttachmentStatusActive = 'active';
const String kAttachmentStatusBurned = 'burned';

/// 残留强制焚毁保留期（§11.2 W11-12「>7 天残留强制清理」）。
const Duration kAttachmentBurnRetention = Duration(days: 7);

/// 本地内容焚毁器（即焚的物理半边）。
///
/// 返回 true=本次调用删掉了文件；false=文件本已不存在（视为已焚毁）。
/// 抛异常=删除失败（调用方按各自语义处理：markBurned 上抛、purge 降级）。
typedef AttachmentContentCleaner = Future<bool> Function(String localPath);

/// 缺省焚毁器：删除 [localPath] 文件；文件不存在即已焚毁（幂等）。
Future<bool> deleteAttachmentFile(String localPath) async {
  final file = File(localPath);
  if (!await file.exists()) {
    return false;
  }
  await file.delete();
  return true;
}

/// 附件 DAO（§5.6㉑）。
class AttachmentsDao {
  AttachmentsDao(this._db, {AttachmentContentCleaner? contentCleaner})
      : _cleaner = contentCleaner ?? deleteAttachmentFile;

  final AppDatabase _db;

  /// 内容焚毁器（即焚物理半边，见库注释）。
  final AttachmentContentCleaner _cleaner;

  /// 登记附件审计元数据（拍照/端侧压缩完成后调用；§5.6㉑）。
  ///
  /// 调用契约：调用方已把压缩产物写入 [localPath] 并算出 sha256
  /// [contentHash]（内容哈希即去重键，查重口径见 [findLatestByContentHash]）。
  /// 状态起步 active（列默认值，§3.3 状态机起点）；blob_ref 恒 NULL——
  /// 原图不落服务端（§5.6）。
  ///
  /// [id] 可注入（缺省本地生成 UUIDv7，§5.1）：测试用固定时间戳的 UUIDv7
  /// 构造「超龄残留」，调用方也可传入与其它登记同源的 id。
  Future<Attachment> insert({
    required String contentHash,
    required String kind,
    required String mime,
    required int sizeBytes,
    required String localPath,
    String? entryId,
    String? id,
  }) async {
    assert(
      kind == kAttachmentKindPhoto || kind == kAttachmentKindReceipt,
      'kind 仅 photo/receipt（§5.6㉑ attachments.kind）',
    );
    assert(sizeBytes >= 0, 'size_bytes 为字节数、非负（§5.6㉑）');
    final rowId = id ?? generateUuidV7();
    await _db.into(_db.attachments).insert(
          AttachmentsCompanion.insert(
            id: rowId,
            entryId: Value(entryId),
            contentHash: contentHash,
            kind: kind,
            mime: mime,
            sizeBytes: sizeBytes,
            localPath: localPath,
            // status 走列默认 'active'；burned_at/blob_ref 缺省（NULL）——
            // 即焚起点与「原图不落服务端」口径（§5.6㉑）。
          ),
        );
    return (await findById(rowId))!;
  }

  Future<Attachment?> findById(String id) => (_db.select(_db.attachments)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  /// 内容哈希查重（§5.6㉑ content_hash 去重键；「去重由应用层查重保证」）。
  ///
  /// 同图（同压缩字节）重拍/重复登记时返回最新登记行；无命中返回 null。
  Future<Attachment?> findLatestByContentHash(String contentHash) {
    return (_db.select(_db.attachments)
          ..where((t) => t.contentHash.equals(contentHash))
          // UUIDv7 字典序=时间序（§5.1）：同 hash 多次登记取最新一条。
          ..orderBy([(t) => OrderingTerm.desc(t.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// 即焚（§3.3「原图解析后即焚」）：先焚毁内容、再把状态推到 burned。
  ///
  /// 状态机单向（§3.3 active→burned 不可逆）：
  /// - 已 burned 行：幂等 no-op——保留**首次**即焚时刻（与 §6.5「完成事件
  ///   只前进」同一时间语义），不重复触发焚毁；
  /// - 内容焚毁（删文件）先行：删除失败异常上抛、行保持 active——绝不产生
  ///   「行已 burned 而内容仍在」的新增残留（§3.9 合规红线）；调用方可重试；
  /// - burned 行保留全部审计元数据（路径/哈希/字节大小/mime/即焚时刻），
  ///   不保留内容本体（§5.6㉑「保留审计元数据不保留内容」的任务口径）。
  ///
  /// [atMs] 即焚时刻（缺省墙钟）；测试注入固定时刻做确定性断言。
  Future<Attachment> markBurned(String id, {int? atMs}) async {
    final row = await findById(id);
    if (row == null) {
      throw StateError('markBurned: attachments 无此行 $id（§5.6㉑）');
    }
    if (row.status == kAttachmentStatusBurned) {
      return row; // 单向状态机：burned 终态幂等，保留首次即焚时刻
    }
    await _cleaner(row.localPath);
    final burnedAt = atMs ?? DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.attachments)..where((t) => t.id.equals(id))).write(
      AttachmentsCompanion(
        status: const Value(kAttachmentStatusBurned),
        burnedAt: Value(burnedAt),
      ),
    );
    return (await findById(id))!;
  }

  /// 残留强制清理（§11.2 W11-12「>7 天残留强制清理」）。
  ///
  /// 兜底口径：正常流在解析完成后即 [markBurned]；本方法处理**漏网残留**——
  /// - active 超龄行（进程中断/解析未回/焚毁失败）：删内容 + 状态强制推到
  ///   burned（即焚时刻取本次清扫时刻）；
  /// - burned 超龄行仍有文件（防御性：系统恢复文件/旧版本焚毁未删净）：
  ///   只删文件，行不动（状态机单向、即焚时刻保留首次值）；
  /// - 未超龄行、id 非 UUIDv7 形态（时长不明）的行：不碰——宁可保守。
  ///
  /// 返回 (forceBurned, filesDeleted)：强制即焚行数与本次实际删除文件数
  /// （供调用方打点/监控，§3.9 合规证据）。逐行降级：单文件删除失败不阻断
  /// 整轮清扫（行保持 active，下轮重试）。刻意不裹事务：焚毁是跨文件系统
  /// 与数据库的物理动作，逐行原子推进即可，清扫器随时可安全重跑。
  Future<({int forceBurned, int filesDeleted})> purgeExpired({
    int? nowMs,
    Duration retention = kAttachmentBurnRetention,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final retentionMs = retention.inMilliseconds;
    final rows = await _db.select(_db.attachments).get();
    var forceBurned = 0;
    var filesDeleted = 0;
    for (final row in rows) {
      final bornAt = uuidV7TimestampMs(row.id);
      if (bornAt == null) {
        continue; // 时长来源不明：保守跳过，绝不误焚（§5.6⑭ 同口径）
      }
      if (now - bornAt <= retentionMs) {
        continue; // 边界语义「>7 天」：恰好 7 天不算残留
      }
      final deleted = await _cleanOrNull(row.localPath);
      if (deleted == null) {
        continue; // 焚毁失败：行保持 active，下轮重试（§3.9——绝不产生
        // 「行已 burned 而内容仍在」残留，见 markBurned 同红线）
      }
      if (deleted) {
        filesDeleted++;
      }
      if (row.status == kAttachmentStatusBurned) {
        continue; // 已焚行只清防御性残留文件，行不动（状态机单向）
      }
      await (_db.update(_db.attachments)
            ..where((t) => t.id.equals(row.id)))
          .write(
        AttachmentsCompanion(
          status: const Value(kAttachmentStatusBurned),
          burnedAt: Value(now),
        ),
      );
      forceBurned++;
    }
    return (forceBurned: forceBurned, filesDeleted: filesDeleted);
  }

  /// 清扫用的降级焚毁：失败返回 null（行保持 active，下轮 purge 重试）；
  /// 成功返回删除结果（true=删掉文件、false=文件本已不存在）。
  Future<bool?> _cleanOrNull(String localPath) async {
    try {
      return await _cleaner(localPath);
    } catch (_) {
      return null;
    }
  }
}

/// v1 内补列幂等回填（§6.4「行级 schema_ver 只加列前向兼容」的落点）。
///
/// 即焚状态机两列（status/burned_at，§11.2 W11-12）为 schema v1 冻结后的
/// 只加列变更：**schemaVersion 保持 1**，旧 v1 库文件不触发 onUpgrade——
/// 在 beforeOpen 里按 `PRAGMA table_info` 探测缺列并 ALTER TABLE ADD
/// COLUMN 补齐：
/// - status `TEXT NOT NULL DEFAULT 'active'`：SQLite 加列语义下存量行一次
///   性落到默认值（与「补列用默认值规避迁移风险」口径一致）；
/// - burned_at `INTEGER NULL`：可空加列无默认值问题。
///
/// 新库（onCreate createAll）已含两列 → 本函数幂等 no-op。
///
/// 取舍说明：若本变更发生在已发布版本上，正规路径是 schemaVersion=2 +
/// onUpgrade 迁移步 + 迁移测试；当前 V1 未发布（§11.2 W16 才商店发布）、
/// 冻结期禁破坏性迁移（§6.4），故选择「v1 内补列+默认值+幂等回填」——
/// 无版本号变化、无破坏性、对存量开发库文件自愈。
Future<void> backfillAttachmentBurnColumns(AppDatabase db) async {
  final info = await db.customSelect('PRAGMA table_info(attachments)').get();
  if (info.isEmpty) {
    return; // 表不存在（onCreate 前的异常时序）：交给建表流程
  }
  final columns = info.map((row) => row.data['name'] as String).toSet();
  if (columns.contains('status') && columns.contains('burned_at')) {
    return; // 新库已含两列：幂等 no-op
  }
  if (!columns.contains('status')) {
    await db.customStatement(
      "ALTER TABLE attachments ADD COLUMN status TEXT NOT NULL DEFAULT 'active'",
    );
  }
  if (!columns.contains('burned_at')) {
    await db.customStatement(
      'ALTER TABLE attachments ADD COLUMN burned_at INTEGER NULL',
    );
  }
}
