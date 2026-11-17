/// W11-12 拍照通道权限清单存在性断言（§11.2 任务 1「AndroidManifest 声明
/// 相机/相册权限（READ_MEDIA_IMAGES 等 API 33+ 分级）」、§3.3 数据主权
/// 最小权限）。
///
/// 纯文件内容断言（零平台通道/零网络）：Android 分级媒体权限 + 相机可选
/// uses-feature + iOS 用途描述 + image_picker 依赖接入（§11.2 任务 1）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // flutter test 以包根（apps/mobile）为工作目录。
  final packageRoot = Directory.current.path;

  group('AndroidManifest.xml（§11.2 任务 1「API 33+ 分级」）', () {
    late File manifestFile;
    late String manifest;

    setUpAll(() {
      manifestFile = File(
        '$packageRoot${Platform.pathSeparator}'
        'android${Platform.pathSeparator}app${Platform.pathSeparator}'
        'src${Platform.pathSeparator}main${Platform.pathSeparator}'
        'AndroidManifest.xml',
      );
      expect(manifestFile.existsSync(), isTrue,
          reason: 'AndroidManifest.xml 必须存在（拍照通道权限清单落点）');
      manifest = manifestFile.readAsStringSync();
    });

    test('声明 CAMERA 权限（拍照入口，§3.3）', () {
      expect(manifest.contains('android.permission.CAMERA'), isTrue);
    });

    test('声明 API 33+ 照片细粒度权限 READ_MEDIA_IMAGES', () {
      expect(manifest.contains('android.permission.READ_MEDIA_IMAGES'),
          isTrue, reason: 'API 33+ 分级媒体权限（§11.2 任务 1）');
    });

    test('声明 API 34+ 部分授权 READ_MEDIA_VISUAL_USER_SELECTED', () {
      expect(
        manifest.contains('android.permission.READ_MEDIA_VISUAL_USER_SELECTED'),
        isTrue,
        reason: 'API 34+ 用户自选照片（部分授权）权限',
      );
    });

    test('声明旧机型退级 READ_EXTERNAL_STORAGE（maxSdkVersion=32）', () {
      expect(
        RegExp(
          r'READ_EXTERNAL_STORAGE[\s\S]{0,200}?android:maxSdkVersion="32"',
        ).hasMatch(manifest),
        isTrue,
        reason: 'API ≤32 退级声明（§3.3 数据主权最小权限）',
      );
    });

    test('相机 uses-feature required=false（无相机设备走相册入口）', () {
      expect(
        RegExp(r'<uses-feature[\s\S]{0,200}?android:required="false"')
            .hasMatch(manifest),
        isTrue,
        reason: '相机可选能力（§3.3 无相机设备仍可用拍照通道相册入口）',
      );
      expect(manifest.contains('android.hardware.camera'), isTrue);
    });
  });

  group('iOS Info.plist（§11.2 任务 1 相机/相册用途描述）', () {
    late File plistFile;
    late String plist;

    setUpAll(() {
      plistFile = File(
        '$packageRoot${Platform.pathSeparator}'
        'ios${Platform.pathSeparator}Runner${Platform.pathSeparator}Info.plist',
      );
      expect(plistFile.existsSync(), isTrue, reason: 'Info.plist 必须存在');
      plist = plistFile.readAsStringSync();
    });

    test('声明 NSCameraUsageDescription（相机用途描述）', () {
      expect(plist.contains('NSCameraUsageDescription'), isTrue,
          reason: 'App Store 审核必填（拍照入口）');
    });

    test('声明 NSPhotoLibraryUsageDescription（相册用途描述）', () {
      expect(plist.contains('NSPhotoLibraryUsageDescription'), isTrue,
          reason: 'App Store 审核必填（相册入口）');
    });
  });

  group('pubspec.yaml（§11.2 任务 1「image_picker 依赖接入」）', () {
    test('声明 image_picker / crypto / http 依赖', () {
      final pubspec = File('$packageRoot${Platform.pathSeparator}pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      final content = pubspec.readAsStringSync();
      expect(content.contains(RegExp(r'image_picker:\s*\^')),
          isTrue, reason: 'image_picker 依赖（拍照/相册真实实现）');
      expect(content.contains(RegExp(r'crypto:\s*\^')),
          isTrue, reason: 'crypto（sha256 content_hash 一址两用键，§5.6㉑）');
      expect(content.contains(RegExp(r'http:\s*\^')),
          isTrue, reason: 'http（双供应商传输层，§3.3；测试 mock transport）');
    });
  });
}
