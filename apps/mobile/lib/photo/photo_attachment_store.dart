/// 拍照通道附件存储的壳层桥接（§5.6㉑ attachments、§3.7/§11.2「解析后即焚」、
/// §11.2 W11-12 任务 3「即焚默认开的设置项」）。
///
/// 实现 feature_capture 的 [CaptureAttachmentStore] 窄接口（唯一动作
/// registerBurned=登记即焚），经 captureAttachmentStoreProvider override
/// 注入（bootstrap 装配）。底层走 core_db AttachmentsDao（§5.6㉑ 即焚状态机
/// `active → burned` 单向、blob_ref 恒 NULL=原图不落服务端、attachments 不入
/// sync_outbox 出网集）：
///
/// 1. content_hash 去重（§5.6㉑「去重由应用层查重保证」）：同压缩字节
///    （sha256 同 hash）重复登记时复用既有行（幂等），仅把 entry_id 补指到
///    最新事件——同图多次确认不产生重复附件行；
/// 2. 登记即焚：insert（active 行）→ markBurned（DAO 先删本地文件再推状态，
///    单向不可逆；burned 行保留审计元数据：hash/size/mime/路径/即焚时刻）；
/// 3. 即焚开关（§3.7、lib/settings/photo_burn_setting.dart，默认开=即焚）：
///    **开**——原图不留任何副本（合规缺省）；**关（用户显式选本机留档）**——
///    markBurned 删文件**之前**先把原图复制一份到应用 support 目录
///    photo_archive/（以 content_hash 命名、同 hash 幂等），设备本地副本，
///    不落 attachments 行、不入任何同步面（§5.6⑯ 真值表集之外）。开关在
///    登记时刻经 [PhotoBurnPolicy] 同步读取（设置页 toggle 即刻生效，与
///    RawInputGateCaptureParser 同款持有器纪律）。
///
/// 与 feature_capture 自带的 DbCaptureAttachmentStore（W11-12 包内桥）差异：
/// 本类额外承担去重复用与「即焚开关关闭时的本机留档副本」——设置项语义归壳
/// （§10.4：settings 读取与文件系统装配都是壳层职责）。控制器在 store 之外
/// 仍会兜底删除临时文件（防御纵深；行状态为即焚真值）。
library;

import 'dart:io';

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/drift.dart' show Value;
import 'package:feature_capture/feature_capture.dart';

import '../settings/photo_burn_setting.dart';

/// 即焚开关感知的附件存储（core_db AttachmentsDao 桥接 + 去重 + 本机留档）。
class DriftPhotoAttachmentStore implements CaptureAttachmentStore {
  DriftPhotoAttachmentStore({
    required cdb.AppDatabase database,
    this.burnPolicy,
    this.archiveDirectory,
  })  : _database = database,
        _dao = cdb.AttachmentsDao(database);

  final cdb.AppDatabase _database;

  /// core_db 附件 DAO（§5.6㉑：insert active → markBurned 先焚内容再推状态）。
  final cdb.AttachmentsDao _dao;

  /// 即焚开关持有器（null=按默认开=即焚处理；bootstrap 注入 settings 装载
  /// 的同一持有器，设置页写回，§3.7）。
  final PhotoBurnPolicy? burnPolicy;

  /// 本机留档目录（§3.7 开关=关时登记焚毁前复制原图；null=无条件即焚——
  /// 目录装配失败时取最严档，§6.1 缺省最严纪律）。
  final Directory? archiveDirectory;

  @override
  Future<String> registerBurned(CaptureAttachmentDraft draft) async {
    // ① content_hash 去重（§5.6㉑）：同压缩字节复用既有行（幂等登记），
    //    entry_id 补指到最新事件（拍照→确认→换图重确认等路径不重复建行）。
    final existing = await _dao.findLatestByContentHash(draft.contentHash);
    if (existing != null) {
      if (existing.entryId != draft.entryId) {
        await (_database.update(_database.attachments)
              ..where((t) => t.id.equals(existing.id)))
            .write(cdb.AttachmentsCompanion(entryId: Value(draft.entryId)));
      }
      // 既有行已 burned（登记即焚语义下 insert 与 burn 同事务完成）；补留档
      // 不在此路径（原图临时文件在首次登记时已焚，副本以首次为准）。
      return existing.id;
    }
    // ② 登记 active 行（blob_ref 走列缺省 NULL=原图不落服务端，§5.6㉑）；
    //    local_path 为 null（Fake/无盘上文件）以空串落列（DAO 契约）。
    final row = await _dao.insert(
      contentHash: draft.contentHash,
      kind: draft.kind,
      mime: draft.mime,
      sizeBytes: draft.sizeBytes,
      localPath: draft.localPath ?? '',
      entryId: draft.entryId,
    );
    // ③ 即焚开关关闭（用户选本机留档，§3.7）：焚毁**前**复制副本——
    //    markBurned 先删文件再推状态，副本窗口只能在此前完成。
    final burnAfterParse = burnPolicy?.enabled ?? true;
    if (!burnAfterParse) {
      await _archiveOriginal(
        localPath: draft.localPath,
        contentHash: draft.contentHash,
        mime: draft.mime,
      );
    }
    // ④ 登记即焚（§3.3/§5.6㉑）：DAO 先焚本地内容（删文件，失败上抛可重试）
    //    再推 `active → burned`（单向不可逆，保留审计元数据与首次即焚时刻）。
    final burned = await _dao.markBurned(row.id);
    return burned.id;
  }

  /// 本机留档副本（§3.7 开关=关时的「本机留档」语义；仅设备本地文件，
  /// 永不上传/不同步）。副本名 = content_hash.`<png|jpg>`（同 hash 幂等覆盖
  /// 判定：已存在即跳过）。失败降级：留档失败不阻断即焚主流程（§6.1 原则 1
  /// 「只降级不打断」——合规缺省是即焚，留档是用户附加选择，允许失败）。
  Future<void> _archiveOriginal({
    required String? localPath,
    required String contentHash,
    required String mime,
  }) async {
    final directory = archiveDirectory;
    if (directory == null || localPath == null || localPath.isEmpty) {
      return;
    }
    try {
      final source = File(localPath);
      if (!await source.exists()) {
        return; // 无盘上文件（Fake/路径未落地）：无可留档内容。
      }
      await directory.create(recursive: true);
      final extension = mime == 'image/png' ? 'png' : 'jpg';
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$contentHash.$extension',
      );
      if (await destination.exists()) {
        return; // 同 hash 已留档（重复登记幂等，§5.6㉑ 去重同向）。
      }
      await source.copy(destination.path);
    } on Object {
      // 留档失败不影响即焚（§6.1）。
    }
  }
}
