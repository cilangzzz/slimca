/// 端侧图片压缩抽象（§3.3 拍照通道「端侧压缩（长边 1280、JPEG q80）」、
/// §7.1 管线照片路径第 0 步、§11.2 W11-12）。
///
/// 分层边界（§10.4）：压缩依赖平台图像编解码（插件/平台通道），本包只定义
/// 接缝，宿主 override 注入实现（如 flutter_image_compress）；测试注入
/// FakeImageCompressor（capture_photo_fakes.dart，透传 fixture 字节）。
///
/// 压缩产物字节即拍照通道的「规范化输入」：sha256 后同源充当
/// attachments.content_hash（§5.6㉑ 去重键）与 ai_parses.input_hash
/// （§5.6⑭ photo 缓存键），杜绝两套哈希口径。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_photo_models.dart';

/// 压缩长边上限（§3.3「长边 1280」）。
const int kCaptureCompressLongEdge = 1280;

/// JPEG 压缩质量（§3.3「JPEG q80」）。
const int kCaptureCompressJpegQuality = 80;

/// 端侧压缩抽象。实现约定：
/// - 输入 [CapturePhotoFile] 原图字节，输出 JPEG（mime=image/jpeg），
///   长边超限时缩到 [kCaptureCompressLongEdge]、质量 [kCaptureCompressJpegQuality]；
/// - [CaptureCompressedImage.contentHash] 必须= sha256(输出字节)（§5.6㉑/§5.6⑭
///   同源键，§7.1「规范化 + input_hash」照片口径）；
/// - 压缩失败抛异常（控制器捕获后走失败降级，§7.4）。
abstract interface class CaptureImageCompressor {
  Future<CaptureCompressedImage> compress(CapturePhotoFile photo);
}

/// 注入点（§10.4 壳负责装配）：与 captureImageSourceProvider 同纪律，
/// 未 override 直接读即抛错。
final Provider<CaptureImageCompressor> captureImageCompressorProvider =
    Provider<CaptureImageCompressor>(
  (ref) => throw UnimplementedError(
    '宿主必须 override captureImageCompressorProvider（§10.4 壳负责装配）：'
    '注入端侧压缩实现（长边 $kCaptureCompressLongEdge、JPEG q'
    '$kCaptureCompressJpegQuality，§3.3）；测试注入 FakeImageCompressor',
  ),
);
