/// ImageCompressor 契约测试（§3.3「端侧压缩（长边 1280、JPEG q80）」、
/// W11-12 任务第 3 项：压缩参数 + fixture 小图真实编解码）。
///
/// 全部离线：fixture 字节由 package:image 现场编码（确定性像素函数），
/// 无相机、无平台通道、无网络。
library;

import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'photo_test_support.dart';

void main() {
  group('压缩参数（§3.3 口径：长边 1280、JPEG q80）', () {
    test('长边超限 → 等比缩放至 1280，产物为可解码 JPEG', () async {
      // fixture 1600×900（长边超限）。
      final source = makeJpegFixture(width: 1600, height: 900);
      const compressor = PureDartImageCompressor();

      final out = await compressor
          .compress(PhotoImageInput(bytes: source, mime: 'image/jpeg'));

      expect(out.widthPx, 1280, reason: '§3.3 长边 1280');
      expect(out.heightPx, 720, reason: '等比缩放（1600×900 → 1280×720）');
      expect(out.mime, 'image/jpeg', reason: '规范形统一重编码 JPEG');
      // 真实编解码回环：产物可被 JPEG 解码且尺寸一致。
      final decoded = img.decodeImage(out.bytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, 1280);
      expect(decoded.height, 720);
    });

    test('竖图长边超限 → 高边缩放（900×1600 → 720×1280）', () async {
      final source = makeJpegFixture(width: 900, height: 1600);
      const compressor = PureDartImageCompressor();

      final out = await compressor
          .compress(PhotoImageInput(bytes: source, mime: 'image/jpeg'));

      expect(out.widthPx, 720);
      expect(out.heightPx, 1280);
    });

    test('短边小于上限 → 只缩不放大（800×600 保持原尺寸）', () async {
      final source = makeJpegFixture(width: 800, height: 600);
      const compressor = PureDartImageCompressor();

      final out = await compressor
          .compress(PhotoImageInput(bytes: source, mime: 'image/jpeg'));

      expect(out.widthPx, 800);
      expect(out.heightPx, 600, reason: '§7.1 压缩只降规格不放大');
    });

    test('PNG 输入 → 统一重编码 JPEG（mime 规范形）', () async {
      final source = makePngFixture();
      const compressor = PureDartImageCompressor();

      final out = await compressor
          .compress(PhotoImageInput(bytes: source, mime: 'image/png'));

      expect(out.mime, 'image/jpeg');
      expect(img.decodeImage(out.bytes), isNotNull);
    });

    test('可注入参数：maxEdge/jpegQuality 覆写（测试/宿主定制口径）', () async {
      final source = makeJpegFixture(width: 300, height: 150);
      const compressor = PureDartImageCompressor(maxEdge: 64, jpegQuality: 50);

      final out = await compressor
          .compress(PhotoImageInput(bytes: source, mime: 'image/jpeg'));

      expect(out.widthPx, 64);
      expect(out.heightPx, 32);
      expect(out.bytes.length, lessThan(source.length),
          reason: 'q50 重编码显著小于 q90 源');
    });

    test('缺省口径常量与 §3.3 文档一字不差（长边 1280 / 质量 80）', () {
      expect(kPhotoMaxEdgePx, 1280);
      expect(kPhotoJpegQuality, 80);
      expect(kPhotoCompressedMime, 'image/jpeg');
    });
  });

  group('失败路径（坏字节 → PhotoCompressionException → §7.4 一级降级）', () {
    test('空字节抛 PhotoCompressionException', () async {
      const compressor = PureDartImageCompressor();
      await expectLater(
        compressor.compress(
            PhotoImageInput(bytes: Uint8List(0), mime: 'image/jpeg')),
        throwsA(isA<PhotoCompressionException>()),
      );
    });

    test('坏字节（非图片）抛 PhotoCompressionException', () async {
      const compressor = PureDartImageCompressor();
      final garbage = Uint8List.fromList(
          List<int>.generate(128, (i) => (i * 37) % 256));
      await expectLater(
        compressor.compress(
            PhotoImageInput(bytes: garbage, mime: 'image/jpeg')),
        throwsA(isA<PhotoCompressionException>()
            .having((e) => e.message, 'message', isNotEmpty)),
      );
    });
  });
}
