/// 拍照通道值对象（§11.2 W11-12 主线「拍照通道」、§3.3 拍照通道行、§7.1
/// 管线照片路径、§5.6㉑ attachments）。
///
/// 数据流（§3.3 拍照通道）：
/// ```
/// 拍照/相册选择（[CapturePhotoFile]，W11-12 任务 1 ImageSource 抽象）
///   → 端侧压缩（长边 1280、JPEG q80 → [CaptureCompressedImage]，§3.3/§7.1）
///   → content_hash = sha256(压缩字节)（一址两用：§5.6㉑ attachments 去重键
///     + §5.6⑭ ai_parses.input_hash photo 缓存键——规范化输入即压缩产物）
///   → 识别（百度菜品识别先行 → Vision LLM 兜底，§3.3 双供应商防单点；
///     raw_input 上云开关关闭时走端侧粗估，§3.7）
///   → 确认卡复用（W3-4 已有）→ 确认落库（entries+entry_lines+food_items）
///   → 解析后即焚：登记 attachments 行（burned，[CaptureAttachmentDraft]）
///     + 本地临时文件删除（§3.7/§11.2，[CapturePendingPhoto] 在途态）
/// ```
library;

import 'dart:typed_data';

/// 拍照/相册选择产物（§11.2 W11-12 任务 1「ImageSource 抽象」的返回值）。
///
/// [bytes] 是解析所需的原图字节——它是拍照通道的 raw_input：raw_input 上云
/// 开关关闭（默认）时**不出端**（§3.7）；[localPath] 是壳层落地的临时文件
/// 路径（即焚对象，确认落库后删除；Fake/无盘上文件场景可空）。
class CapturePhotoFile {
  const CapturePhotoFile({
    required this.bytes,
    required this.mime,
    this.localPath,
  });

  /// 原始图片字节（识别输入；不落任何表，§3.3 raw_input 即用即焚口径）。
  final Uint8List bytes;

  /// MIME 类型（attachments.mime，§5.6㉑；拍照产物口径 image/jpeg）。
  final String mime;

  /// 临时文件路径（确认落库后即焚删除，§3.7/§11.2；null=无盘上文件）。
  final String? localPath;
}

/// 端侧压缩产物（§3.3「端侧压缩（长边 1280、JPEG q80）」、§7.1 管线第 0 步）。
class CaptureCompressedImage {
  const CaptureCompressedImage({
    required this.bytes,
    required this.mime,
    required this.contentHash,
  });

  /// 压缩后字节（识别输入；raw_input 开=本次识别可携带上云，关=不出端，
  /// §3.7）。
  final Uint8List bytes;

  /// 压缩产物 MIME（恒 image/jpeg，§3.3 q80 口径）。
  final String mime;

  /// sha256(压缩字节)——一址两用：§5.6㉑ attachments.content_hash 去重键 +
  /// §5.6⑭ ai_parses.input_hash（input_kind=photo）缓存键。
  final String contentHash;

  /// 字节数（attachments.size_bytes，§5.6㉑）。
  int get sizeBytes => bytes.length;
}

/// 拍照解析请求（§7.1 管线照片路径；百度菜品识别/Vision LLM 经壳层注入，
/// 真实凭据未提供——缺省 Fake，remaining：待凭据联调）。
class CapturePhotoParseRequest {
  const CapturePhotoParseRequest({
    required this.bytes,
    required this.mime,
    required this.inputHash,
  });

  /// 压缩后字节（§3.3 端侧压缩产物）。
  final Uint8List bytes;

  /// MIME（image/jpeg）。
  final String mime;

  /// sha256(压缩字节)=缓存键（§5.6⑭ input_hash，input_kind=photo）。
  final String inputHash;
}

/// 待焚附件的在途态（§3.7/§11.2「解析后即焚」）。
///
/// 拍下即持有；**确认落库后**经 [CaptureAttachmentStore.registerBurned]
/// 登记 attachments 行（登记即 burned，blob_ref 恒 NULL=原图不落服务端，
/// §5.6㉑）并删除 [localPath]；丢弃/换拍（未确认）时仅删临时文件——
/// 「绝不丢已拍数据」：原文图片在确认前绝不即焚（§11.2 任务 4）。
class CapturePendingPhoto {
  const CapturePendingPhoto({
    required this.contentHash,
    required this.mime,
    required this.sizeBytes,
    this.localPath,
  });

  /// sha256(压缩字节)（§5.6㉑ content_hash 去重键）。
  final String contentHash;

  /// MIME（image/jpeg）。
  final String mime;

  /// 字节数。
  final int sizeBytes;

  /// 临时文件路径（即焚对象；null=无盘上文件，仅登记标记）。
  final String? localPath;
}

/// 附件登记载荷（→ core_db attachments 行，§5.6㉑；本包只经
/// [CaptureAttachmentStore] 抽象调用、宿主桥接 core_db AttachmentsDao，
/// 任务口径「本包只调用」）。
class CaptureAttachmentDraft {
  const CaptureAttachmentDraft({
    required this.entryId,
    required this.contentHash,
    required this.kind,
    required this.mime,
    required this.sizeBytes,
    this.localPath,
  });

  /// 所属事件（确认落库后登记，此路径恒非空；§5.6㉑ entry_id 可空语义）。
  final String entryId;

  /// 去重键 sha256(压缩字节)（§5.6㉑）。
  final String contentHash;

  /// photo / receipt（§5.6㉑ kind；拍照通道恒 photo）。
  final String kind;

  /// MIME 类型（§5.6㉑）。
  final String mime;

  /// 字节数（§5.6㉑）。
  final int sizeBytes;

  /// 登记时刻的本地临时路径（即焚口径下行内是否留路径由 core_db schema
  /// 定版——attachments.local_path 为 NOT NULL 时实现以空串表达已焚）。
  final String? localPath;
}
