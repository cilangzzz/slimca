/// 拍照/相册图片来源抽象（§11.2 W11-12 任务 1「ImageSource 抽象」）。
///
/// 分层边界（§10.4）：image_picker 是壳层依赖——本包只定义薄封装接缝
/// [CaptureImageSource]，真实插件实现由壳 override 注入（任务口径「真实
/// 插件依赖由壳注入」）；测试与预览注入 [FakeImageSource]
/// （capture_photo_fakes.dart，fixture 字节，硬规则：测试禁止真实相机）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_photo_models.dart';

/// 图片来源抽象：拍照 / 相册二入口（§3.3 录入抽屉「写/说/拍」三通道之拍）。
///
/// 实现约定：
/// - 用户取消/宿主侧失败返回 null（取消不是错误，不抛异常）；
/// - [CapturePhotoFile.localPath] 由实现落地临时文件后给出（即焚对象，
///   §3.7/§11.2 确认落库后删除）；
/// - 相机/存储权限拒绝等系统层交互由实现自行处理，本抽象不建模。
abstract interface class CaptureImageSource {
  /// 相机拍摄（image_picker `ImageSource.camera` 的薄封装位）。
  Future<CapturePhotoFile?> capturePhoto();

  /// 相册选择（image_picker `ImageSource.gallery` 的薄封装位）。
  Future<CapturePhotoFile?> pickGallery();
}

/// 注入点（§10.4 壳负责装配）：宿主必须 override 注入 image_picker 薄封装。
/// 未 override 直接读即抛错——装配遗漏在开发期立刻暴露，而非静默无图
/// （与 captureParserProvider / captureGatewayProvider 同纪律）。
final Provider<CaptureImageSource> captureImageSourceProvider =
    Provider<CaptureImageSource>(
  (ref) => throw UnimplementedError(
    '宿主必须 override captureImageSourceProvider（§10.4 壳负责装配）：'
    '注入 image_picker 薄封装（拍照/相册）；测试注入 FakeImageSource',
  ),
);
