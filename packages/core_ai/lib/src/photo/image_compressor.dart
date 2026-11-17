/// 端侧压缩抽象与纯 Dart 实现（§3.3「端侧压缩（长边 1280、JPEG q80）」、
/// §11.2 W11-12 主线第一步）。
///
/// 口径（§3.3 拍照通道）：
/// - 最长边缩放至 [kPhotoMaxEdgePx]（1280）以内，**只缩不放大**；
/// - 统一重编码 JPEG 质量 [kPhotoJpegQuality]（80）——产物 mime 恒
///   `image/jpeg`；
/// - EXIF 方向烘焙（手机竖拍照片 orientation≠1，先转正再缩放，避免识别
///   模型看到横躺图）。
///
/// 实现选型（W11-12 任务口径）：`package:image` 纯 Dart 编解码（无平台
/// 通道，单元测试离线可跑真实 codec）——真实供应商凭据未提供、真机相机
/// 依赖不在本库，测试一律用 fixture 小图字节（任务硬规则：禁止真实相机）。
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'photo_models.dart';

/// §3.3 压缩口径：长边上限（像素）。
const int kPhotoMaxEdgePx = 1280;

/// §3.3 压缩口径：JPEG 重编码质量（0-100）。
const int kPhotoJpegQuality = 80;

/// 压缩产物 MIME（规范形统一 JPEG，§3.3）。
const String kPhotoCompressedMime = 'image/jpeg';

/// 端侧压缩抽象（拍照管线第 1 步，§7.1「照片端侧压缩」）。
///
/// 宿主可注入平台通道实现（如 flutter_image_compress 适配器）替换缺省的
/// 纯 Dart 实现——接口输入输出与本抽象一字不差；测试注入 Fake 或直接用
/// [PureDartImageCompressor]（离线真实 codec）。
abstract interface class ImageCompressor {
  /// 压缩一张原图为端侧规范形。
  ///
  /// 坏字节/不支持格式抛 [PhotoCompressionException]（拍照管线据此一级降级，
  /// §7.4）。
  Future<CompressedImage> compress(PhotoImageInput input);
}

/// package:image 纯 Dart 实现（W11-12 缺省；无平台依赖，全部平台可用）。
///
/// 步骤：decodeImage（自动识别格式）→ bakeOrientation（EXIF 方向烘焙）→
/// 最长边超限则等比缩放 → encodeJpg 质量重编码。纯 CPU 同步执行，经
/// async 接口封装（宿主换平台通道实现时签名不变）。
class PureDartImageCompressor implements ImageCompressor {
  const PureDartImageCompressor({
    this.maxEdge = kPhotoMaxEdgePx,
    this.jpegQuality = kPhotoJpegQuality,
  });

  /// 最长边上限（只缩不放大）。
  final int maxEdge;

  /// JPEG 重编码质量（§3.3：80）。
  final int jpegQuality;

  @override
  Future<CompressedImage> compress(PhotoImageInput input) async {
    if (input.bytes.isEmpty) {
      throw const PhotoCompressionException('原图字节为空，无法压缩');
    }
    img.Image? decoded;
    try {
      decoded = img.decodeImage(input.bytes);
    } catch (error) {
      throw PhotoCompressionException(
        '图片解码失败（mime=${input.mime}）：$error',
        cause: error,
      );
    }
    if (decoded == null) {
      throw PhotoCompressionException(
        '图片解码失败：非支持格式或坏字节（mime=${input.mime}）',
      );
    }

    // EXIF 方向烘焙：竖拍照片 orientation≠1 → 物理转正（§3.3 压缩规范形）。
    final oriented = img.bakeOrientation(decoded);
    final width = oriented.width;
    final height = oriented.height;
    if (width <= 0 || height <= 0) {
      throw const PhotoCompressionException('图片解码后尺寸非法');
    }

    // 最长边缩放（等比；只缩不放大——小于上限的图保持原尺寸）。
    final longest = width > height ? width : height;
    var targetW = width;
    var targetH = height;
    if (longest > maxEdge) {
      final scale = maxEdge / longest;
      targetW = (width * scale).round().clamp(1, maxEdge);
      targetH = (height * scale).round().clamp(1, maxEdge);
    }
    final resized = (targetW == width && targetH == height)
        ? oriented
        : img.copyResize(
            oriented,
            width: targetW,
            height: targetH,
            // 等比已由上方显式计算（目标宽高成对传入），插值取平均——
            // 缩图场景质量/速度均衡。
            interpolation: img.Interpolation.average,
          );

    // 统一重编码 JPEG（§3.3 q80）。
    final Uint8List encoded =
        Uint8List.fromList(img.encodeJpg(resized, quality: jpegQuality));
    return CompressedImage(
      bytes: encoded,
      mime: kPhotoCompressedMime,
      widthPx: targetW,
      heightPx: targetH,
    );
  }
}
