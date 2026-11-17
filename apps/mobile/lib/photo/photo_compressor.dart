/// 拍照通道端侧压缩的壳层实现（§3.3「端侧压缩（长边 1280、JPEG q80）」、
/// §7.1 管线照片路径第 0 步、§11.2 W11-12 任务 1「端侧压缩插件」）。
///
/// 分层取舍（§10.4）：压缩动作已由 [ImagePickerCaptureImageSource] 在
/// image_picker 拾取参数内完成（maxWidth/maxHeight=1280 约束长边 +
/// imageQuality=80 强制 JPEG 重编码，原生层缩放编码，§3.3）——壳内不再引
/// 入 Dart 侧图像解码库做二次压缩。本压缩器承担**规范化收口**：
/// - mime 归一 image/jpeg（§3.3 q80 口径，CaptureCompressedImage 契约）；
/// - content_hash = sha256(输出字节)——一址两用：attachments.content_hash
///   去重键（§5.6㉑）与 ai_parses.input_hash photo 缓存键（§5.6⑭），
///   杜绝两套哈希口径；
/// - 空字节视为压缩失败抛异常（§11.2 [CaptureImageCompressor] 契约「压缩
///   失败抛异常」→ 控制器捕获后走失败降级，§7.4，绝不丢已拍数据——降级
///   路径保留待焚原件）。
///
/// 测试注入 FakeImageCompressor（feature_capture fakes，透传 + sha256 同
/// 键口径），禁真实编解码（§11.2 硬规则）。
library;

import 'package:crypto/crypto.dart';
import 'package:feature_capture/feature_capture.dart';

/// 拾取参数已压缩的透传压缩器（规范化收口：mime 归一 + sha256 同源键）。
class PickerCompressedCaptureCompressor implements CaptureImageCompressor {
  const PickerCompressedCaptureCompressor();

  @override
  Future<CaptureCompressedImage> compress(CapturePhotoFile photo) async {
    // 压缩失败语义（§11.2 契约）：无字节产物（拾取/原生编码异常）抛错 →
    // 控制器失败降级（§7.4）。空字节绝不能静默进识别管线（否则 sha256(空)
    // 缓存键会跨次误命中，§5.6⑭）。
    if (photo.bytes.isEmpty) {
      throw StateError('端侧压缩产物为空（§3.3 压缩失败语义，§7.4 降级）');
    }
    return CaptureCompressedImage(
      bytes: photo.bytes,
      // §3.3「JPEG q80」口径：拾取参数已强制 JPEG 重编码，mime 恒归一。
      mime: 'image/jpeg',
      contentHash: sha256.convert(photo.bytes).toString(),
    );
  }
}
