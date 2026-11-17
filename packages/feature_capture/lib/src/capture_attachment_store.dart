/// 附件登记/即焚接口（§5.6㉑ attachments、§3.7/§11.2「解析后即焚」、
/// §11.2 W11-12 任务 3）。
///
/// 分层边界（§10.4 + 任务口径「经 core_db AttachmentsDao 接口，本包只调用」）：
/// attachments 行的存储语义归 core_db [cdb.AttachmentsDao]（即焚状态机
/// `active → burned`、blob_ref 恒 NULL、attachments 不进 sync_outbox 出网集，
/// §5.6⑯ 14 张真值表之外）。本包提供两层：
/// - [CaptureAttachmentStore]：窄接口（唯一动作 [registerBurned]）——控制器
///   只依赖它，便于测试注入 Fake 与宿主替换；
/// - [DbCaptureAttachmentStore]：现成的 core_db 桥接实现（insert active 行 →
///   markBurned 即焚），宿主以
///   `captureAttachmentStoreProvider.overrideWithValue(
///     DbCaptureAttachmentStore(AttachmentsDao(db)))` 一行装配。
///
/// 语义契约：**登记即焚**——[registerBurned] 返回时行已为 burned 状态（含
/// 本地内容焚毁，DAO markBurned 先删文件再落状态，§3.3）；本通道不存在
/// 「留档附件行」。控制器在 store 之外仍会尽力删除临时文件（防御纵深：
/// Fake/降级实现不保证删文件）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_photo_models.dart';

/// 附件存储抽象（拍照通道只需要「登记即焚」一个动作）。
///
/// 实现约定：
/// - [registerBurned] 原子完成「attachments 行登记 + burned 标记」（§3.7/
///   §11.2「解析确认后本地临时文件删除+attachments 行标记 burned」的行侧
///   半边；文件侧半边由本包与 DAO 内容焚毁器共同兜底——行状态为即焚真值）；
/// - content_hash 去重（§5.6㉑）由实现承担（同 hash 幂等/复用登记）；
/// - attachments 不入 sync_outbox（§5.6⑯ 真值表集之外），实现无需入队。
abstract interface class CaptureAttachmentStore {
  /// 登记附件行并标记 burned（确认落库后调用）。返回行 id。
  Future<String> registerBurned(CaptureAttachmentDraft draft);
}

/// core_db [cdb.AttachmentsDao] 桥接实现（任务口径「本包只调用」的落点）：
/// `insert`（active 行，blob_ref 恒 NULL）→ `markBurned`（先焚毁本地内容
/// 再推状态机，单向不可逆；burned 行保留审计元数据，§5.6㉑）。
///
/// [CaptureAttachmentDraft.localPath] 为 null（Fake/无盘上文件场景）时以
/// 空串落 local_path（NOT NULL 列的「无盘上内容」哨兵；内容从未落盘即已焚）。
class DbCaptureAttachmentStore implements CaptureAttachmentStore {
  DbCaptureAttachmentStore(this._dao);

  final cdb.AttachmentsDao _dao;

  @override
  Future<String> registerBurned(CaptureAttachmentDraft draft) async {
    final row = await _dao.insert(
      entryId: draft.entryId,
      contentHash: draft.contentHash,
      kind: draft.kind,
      mime: draft.mime,
      sizeBytes: draft.sizeBytes,
      localPath: draft.localPath ?? '',
    );
    final burned = await _dao.markBurned(row.id);
    return burned.id;
  }
}

/// 注入点（§10.4 壳负责装配）：宿主注入 [DbCaptureAttachmentStore]（桥接
/// core_db AttachmentsDao，§5.6㉑）；测试可注入 FakeCaptureAttachmentStore
/// 或真实桥接。未 override 直接读即抛错——即焚是合规红线（§1.6/§3.9），
/// 不允许静默 no-op 兜底。
final Provider<CaptureAttachmentStore> captureAttachmentStoreProvider =
    Provider<CaptureAttachmentStore>(
  (ref) => throw UnimplementedError(
    '宿主必须 override captureAttachmentStoreProvider（§10.4 壳负责装配）：'
    '注入 DbCaptureAttachmentStore(AttachmentsDao(db))（§5.6㉑，登记即 '
    'burned）；测试注入 FakeCaptureAttachmentStore',
  ),
);
