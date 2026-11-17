/// W13 本地通知权限清单与依赖接入断言（§11.2 W13 任务 3「Android 13+
/// POST_NOTIFICATIONS 权限 manifest 声明 + 运行时请求接线」）。
///
/// 纯文件内容断言（零平台通道/零网络；photo_permission_manifest_test 同
/// 口径——manifest/依赖的存在性是可本地验证的部分，运行时弹窗与真实通知
/// 展示属真机验收 remaining）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // flutter test 以包根（apps/mobile）为工作目录。
  final packageRoot = Directory.current.path;

  group('AndroidManifest.xml（§11.2 W13 任务 3「POST_NOTIFICATIONS 声明」）', () {
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
          reason: 'AndroidManifest.xml 必须存在（通知权限清单落点）');
      manifest = manifestFile.readAsStringSync();
    });

    test('声明 POST_NOTIFICATIONS（Android 13+ 通知运行时权限）', () {
      expect(
        manifest.contains('android.permission.POST_NOTIFICATIONS'),
        isTrue,
        reason: 'API 33+ 运行时请求的前置声明（§11.2 W13 任务 3）',
      );
    });
  });

  group('pubspec.yaml（§11.2 W13 任务 3「flutter_local_notifications 依赖」）', () {
    test('声明 flutter_local_notifications / timezone 依赖', () {
      final pubspec =
          File('$packageRoot${Platform.pathSeparator}pubspec.yaml');
      expect(pubspec.existsSync(), isTrue);
      final content = pubspec.readAsStringSync();
      expect(
        content.contains(RegExp(r'flutter_local_notifications:\s*\^')),
        isTrue,
        reason: 'flutter_local_notifications（待办提醒真实通道适配器）',
      );
      expect(
        content.contains(RegExp(r'timezone:\s*\^')),
        isTrue,
        reason: 'timezone（zonedSchedule 的 TZDateTime 构造，§5.5⑩）',
      );
    });
  });

  group('iOS Info.plist（W13 剩余项核对）', () {
    test('通知无 Info.plist 用途描述要求（iOS 权限走运行时请求）', () {
      // iOS 本地通知权限无 plist 静态键（与相机/相册不同）——运行时请求在
      // DarwinInitializationSettings/requestPermissions 内；此用例固定
      // 该口径，防误加无关键。
      final plist = File(
        '$packageRoot${Platform.pathSeparator}'
        'ios${Platform.pathSeparator}Runner${Platform.pathSeparator}'
        'Info.plist',
      );
      if (!plist.existsSync()) {
        return; // iOS 工程缺失环境（不影响 Android 验证口径）。
      }
      expect(plist.readAsStringSync().contains('NSNotificationUsageDescription'),
          isFalse,
          reason: 'iOS 通知权限无静态 plist 键（运行时请求语义）');
    });
  });
}
