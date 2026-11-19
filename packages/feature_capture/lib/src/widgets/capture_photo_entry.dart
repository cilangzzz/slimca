/// 拍照通道入口区（§3.3 拍照通道「拍 → 识别 → 确认」、§11.2 W11-12 任务 2
/// 「录入页『拍』段启用」）。
///
/// 组成：拍照 / 相册选择双入口按钮 + 隐私提示行（随 §3.7 raw_input 上云开关
/// 切换文案）：
/// - 开关关闭（默认）：「原图不出端，端侧粗估 + 人工确认，确认后即焚」；
/// - 开关开启：「原图仅用于本次识别，确认落库后即焚」。
///
/// 相机/相册的真实实现（image_picker 薄封装）由壳层注入
/// [CaptureImageSource]（§10.4），本组件只发意图回调，不持有插件依赖；
/// 未拍摄承诺：原图解析确认前不焚（§11.2 任务 4「绝不丢已拍数据」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui_kit/ui_kit.dart';

import '../capture_photo_estimator.dart';

/// 拍照按钮测试锚点。
const Key capturePhotoCameraKey = ValueKey('capture_photo_camera');

/// 相册选择按钮测试锚点。
const Key capturePhotoGalleryKey = ValueKey('capture_photo_gallery');

/// 隐私提示测试锚点（断言 §3.7 开关口径文案）。
const Key capturePhotoPrivacyHintKey = ValueKey('capture_photo_privacy_hint');

/// 拍照/相册入口区（AI 流 input 阶段渲染于文本输入区下方）。
class CapturePhotoEntry extends ConsumerWidget {
  const CapturePhotoEntry({
    super.key,
    required this.onCamera,
    required this.onGallery,
    this.showGalleryEntry = true,
  });

  /// 发起拍照（漏斗 photo_capture_open from_camera=true，§11.2 任务 5）。
  final VoidCallback onCamera;

  /// 发起相册选择（photo_capture_open from_camera=false）。
  final VoidCallback onGallery;

  /// 是否露出相册选择入口（缺省 true=拍照/相册双入口）。拍通道面板传
  /// false——拍照单一入口纪律：「拍」即拍照识别，通道内不再并列相册
  /// 按钮（相册路径语义由 [onGallery] 与包测试保留）。
  final bool showGalleryEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.slimca;
    // §3.7 raw_input 上云开关（默认关）：只读同步函数，控制提示文案口径。
    final rawInputCloud = ref.watch(captureRawInputCloudEnabledProvider)();
    final hint = rawInputCloud
        ? '原图仅用于本次识别，确认落库后即焚（§3.7/§11.2）'
        : '原图不出端（§3.7）：端侧粗估 + 人工确认，确认后即焚';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showGalleryEntry)
          Row(
            children: [
              Expanded(child: _cameraButton(tokens, context)),
              SizedBox(width: context.spacing.space250),
              Expanded(child: _galleryButton(tokens, context)),
            ],
          )
        else
          // 拍照单一入口：全宽主按钮（拍通道口径，§10.4）。
          _cameraButton(tokens, context),
        SizedBox(height: context.spacing.space100),
        Text(
          hint,
          key: capturePhotoPrivacyHintKey,
          style: TextStyle(fontSize: 12, color: tokens.onSurfaceMuted),
        ),
      ],
    );
  }

  /// 拍照识别主按钮（单一入口 / 双入口两态共用样式；胶囊 + 48 触控目标）。
  Widget _cameraButton(SlimcaTheme tokens, BuildContext context) {
    return OutlinedButton.icon(
      key: capturePhotoCameraKey,
      onPressed: onCamera,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.onSurface,
        side: BorderSide(color: tokens.primary),
        minimumSize: Size.fromHeight(context.sizes.minTouchTarget),
        shape: const StadiumBorder(), // §7.1 按钮胶囊（M3 full）
      ),
      icon: Icon(Icons.photo_camera_outlined,
          size: context.sizes.iconVisual, color: tokens.primary),
      label: const Text(
        '拍照识别',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// 相册选择按钮（双入口态）。
  Widget _galleryButton(SlimcaTheme tokens, BuildContext context) {
    return OutlinedButton.icon(
      key: capturePhotoGalleryKey,
      onPressed: onGallery,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.onSurface,
        side: BorderSide(color: tokens.onSurfaceMuted),
        minimumSize: Size.fromHeight(context.sizes.minTouchTarget),
        shape: const StadiumBorder(), // §7.1 按钮胶囊（M3 full）
      ),
      icon: Icon(Icons.photo_outlined,
          size: context.sizes.iconVisual, color: tokens.onSurfaceMuted),
      label: const Text(
        '相册选择',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}
