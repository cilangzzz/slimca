/// 拍照/相册图片来源的 image_picker 真实实现（§11.2 W11-12 任务 1「权限与
/// 插件：image_picker 依赖接入与 ImageSource 真实实现（经 provider 注入，
/// 测试用 Fake）」、§3.3 拍照通道「拍 → 识别 → 确认」首步）。
///
/// 分层边界（§10.4）：image_picker 是壳层插件依赖——本类实现 feature_capture
/// 的 [CaptureImageSource] 薄封装接缝，经 captureImageSourceProvider
/// override 注入（bootstrap 装配）；测试一律注入 FakeImageSource（fixture
/// 字节，硬规则：测试禁止真实相机/网络）。
///
/// 端侧压缩（§3.3「端侧压缩（长边 1280、JPEG q80）」）在**拾取参数内**由
/// image_picker 原生层完成：maxWidth/maxHeight 约束长边 ≤1280（两维同时
/// 上限即长边上限）、imageQuality=80 强制 JPEG 重编码——产物即为压缩后
/// 字节，壳内无需图像解码库（与 §10.1「端侧小、零冗余」口径一致）。
///
/// Android 权限分级（§11.2 任务 1、§3.3 数据主权最小权限）：
/// - 拍照：CAMERA（uses-feature required=false——无相机设备仍可走相册入口）；
/// - 相册：API 33+ READ_MEDIA_IMAGES / API 34+ READ_MEDIA_VISUAL_USER_
///   SELECTED / API ≤32 READ_EXTERNAL_STORAGE（见 AndroidManifest.xml）；
///   image_picker 在 Android 13+ 实际走系统 Photo Picker（无需运行时权限），
///   旧机型回落 READ_EXTERNAL_STORAGE 运行时授权。
/// iOS：NSCameraUsageDescription / NSPhotoLibraryUsageDescription（Info.plist）。
///
/// 失败语义（§11.2 [CaptureImageSource] 抽象约定）：用户取消/权限拒绝/平台
/// 异常一律返回 null——「取消不是错误，不抛异常」，控制器回输入区不动状态。
library;

import 'package:feature_capture/feature_capture.dart';
import 'package:image_picker/image_picker.dart';

/// image_picker 薄封装（拍照/相册双入口，拾取参数内完成 §3.3 端侧压缩）。
class ImagePickerCaptureImageSource implements CaptureImageSource {
  const ImagePickerCaptureImageSource();

  @override
  Future<CapturePhotoFile?> capturePhoto() => _pick(ImageSource.camera);

  @override
  Future<CapturePhotoFile?> pickGallery() => _pick(ImageSource.gallery);

  Future<CapturePhotoFile?> _pick(ImageSource source) async {
    try {
      final xfile = await ImagePicker().pickImage(
        source: source,
        // §3.3 端侧压缩参数：长边 ≤1280（两维同时约束）+ JPEG q80。
        maxWidth: kCaptureCompressLongEdge.toDouble(),
        maxHeight: kCaptureCompressLongEdge.toDouble(),
        imageQuality: kCaptureCompressJpegQuality,
        // 不取完整 EXIF 元数据（§3.9 隐私最小化：位置等敏感元数据本就不需要；
        // Android Photo Picker 路径也更快）。
        requestFullMetadata: false,
      );
      if (xfile == null) {
        // 用户取消（§11.2 抽象约定：取消不是错误，不抛异常）。
        return null;
      }
      return CapturePhotoFile(
        bytes: await xfile.readAsBytes(),
        mime: _mimeForName(xfile.name),
        // 临时文件路径（即焚对象，§3.7：确认落库成功后删除）。
        localPath: xfile.path,
      );
    } on Object {
      // 权限拒绝/平台通道异常（§11.2 抽象约定：宿主侧失败返回 null——
      // 系统层交互由实现自行处理，控制器回输入区，绝不抛异常打断表单）。
      return null;
    }
  }

  /// MIME 按扩展名兜底（§5.6㉑ attachments.mime）：q80 拾取参数下原生产物
  /// 恒为 JPEG（§3.3 口径），其余扩展名仅作相册旧图未重编码的兜底。
  String _mimeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
