/// 拍照通道确定性 Fake 集合（§11.2 W11-12 硬规则：测试禁止真实网络/相机，
/// 用 Fake/mock transport 与 fixture 图片字节；壳层开发/预览亦可复用）。
///
/// - [FakeImageSource]：fixture 字节 + 可选真实临时文件（即焚「文件已删除」
///   断言可验证删除）；
/// - [FakeImageCompressor]：透传字节 + sha256 content_hash（生产同源键口径，
///   §5.6㉑/§5.6⑭；不重编码）；
/// - [FakeCapturePhotoParser]：脚本化返回/抛出（双供应商组合语义由测试组装）；
/// - [FakeCaptureOnDeviceEstimator]：脚本化端侧估计（默认 null=无法估计）；
/// - [FakeCaptureAttachmentStore]：内存登记表（登记即 burned，断言即焚）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'capture_attachment_store.dart';
import 'capture_parser.dart'
    show CaptureParseResult, CaptureStructuredFailure;
import 'capture_photo_compressor.dart';
import 'capture_photo_estimator.dart';
import 'capture_photo_models.dart';
import 'capture_photo_parser.dart';
import 'capture_photo_source.dart';

/// fixture 图片字节（1×1 PNG 占位——Fake 路径不参与图片解码，§3.3 测试口径；
/// 仅要求字节稳定以派生稳定 sha256 缓存键）。
final Uint8List kFakePhotoBytes = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x13, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// 假图片来源（§11.2 W11-12 任务 1）：返回 fixture 字节；[writeTempFile]=true
/// 时落**真实临时文件**并回填 localPath（即焚文件删除断言用）。
class FakeImageSource implements CaptureImageSource {
  FakeImageSource({
    Uint8List? bytes,
    this.mime = 'image/jpeg',
    this.writeTempFile = false,
  }) : bytes = bytes ?? kFakePhotoBytes;

  /// fixture 字节（缺省 [kFakePhotoBytes]；参数可空因默认值非编译期常量）。
  final Uint8List bytes;

  /// 产物 MIME（拍照产物口径 image/jpeg）。
  final String mime;

  /// 是否落真实临时文件（默认 false；即焚断言用例开 true）。
  final bool writeTempFile;

  /// capturePhoto 被调用次数（入口分流断言）。
  int captureCalls = 0;

  /// pickGallery 被调用次数。
  int galleryCalls = 0;

  /// 全部已创建的临时文件路径（按序；即焚删除断言用）。
  final List<String> createdPaths = [];

  @override
  Future<CapturePhotoFile?> capturePhoto() async {
    captureCalls++;
    return _produce();
  }

  @override
  Future<CapturePhotoFile?> pickGallery() async {
    galleryCalls++;
    return _produce();
  }

  Future<CapturePhotoFile> _produce() async {
    String? path;
    if (writeTempFile) {
      final dir =
          await Directory.systemTemp.createTemp('slimca_capture_fake');
      final file =
          File('${dir.path}${Platform.pathSeparator}fake_photo.jpg');
      await file.writeAsBytes(bytes, flush: true);
      path = file.path;
      createdPaths.add(path);
    }
    return CapturePhotoFile(bytes: bytes, mime: mime, localPath: path);
  }
}

/// 假压缩器：透传字节（fixture 不重编码）、sha256 content_hash（生产同源键
/// 口径，§5.6㉑/§5.6⑭）。
class FakeImageCompressor implements CaptureImageCompressor {
  /// 非 const：[calls] 为可变计数器（压缩阶段执行断言需要）。
  FakeImageCompressor({this.mime = 'image/jpeg'});

  final String mime;

  /// compress 被调用次数（压缩阶段执行断言）。
  int calls = 0;

  @override
  Future<CaptureCompressedImage> compress(CapturePhotoFile photo) async {
    calls++;
    return CaptureCompressedImage(
      bytes: photo.bytes,
      mime: mime,
      contentHash: sha256.convert(photo.bytes).toString(),
    );
  }
}

/// 假拍照解析器：脚本化（[result] 返回 / [failure] 抛出，与文本 FakeParser
/// 同口径，§7.4 失败驱动降级路径测试）。
class FakeCapturePhotoParser implements CapturePhotoParser {
  FakeCapturePhotoParser(CaptureParseResult initialResult)
      : _result = initialResult;

  CaptureParseResult _result;

  /// 注入失败（非空 = parse 抛该异常）。
  CaptureStructuredFailure? failure;

  /// 解析器被真实调用的次数（缓存命中/端侧路径不再调用，§5.6⑭/§3.7）。
  int calls = 0;

  /// 收到的请求（断言 input_hash=sha256(压缩字节) 口径，§7.1）。
  final List<CapturePhotoParseRequest> requests = [];

  set result(CaptureParseResult value) => _result = value;

  @override
  Future<CaptureParseResult> parse(CapturePhotoParseRequest request) async {
    calls++;
    requests.add(request);
    final failure = this.failure;
    if (failure != null) throw failure;
    return _result;
  }
}

/// 假端侧粗估：脚本化（[script] 按次序返回；耗尽或未脚本化 → null=无法
/// 估计，§3.7 关闭口径降级人工确认）。
class FakeCaptureOnDeviceEstimator implements CaptureOnDeviceEstimator {
  FakeCaptureOnDeviceEstimator([List<CaptureParseResult?>? script])
      : _script = List<CaptureParseResult?>.unmodifiable(script ?? const []);

  final List<CaptureParseResult?> _script;

  /// estimate 被调用次数（字节不出端路径断言）。
  int calls = 0;

  /// 收到的请求（断言压缩字节在端侧流转，不出端）。
  final List<CapturePhotoParseRequest> requests = [];

  @override
  Future<CaptureParseResult?> estimate(
    CapturePhotoParseRequest request,
  ) async {
    calls++;
    requests.add(request);
    return calls <= _script.length ? _script[calls - 1] : null;
  }
}

/// 假附件存储：内存登记（[registerBurned]=登记即 burned，§3.7/§11.2）。
class FakeCaptureAttachmentStore implements CaptureAttachmentStore {
  /// 登记顺序的载荷表（断言 entry_id/content_hash/kind/mime/size 映射）。
  final List<CaptureAttachmentDraft> drafts = [];

  /// 已焚行 id 集（registerBurned 即加入）。
  final Set<String> burnedIds = {};

  int _seq = 0;

  @override
  Future<String> registerBurned(CaptureAttachmentDraft draft) async {
    final id = 'fake-attachment-${++_seq}';
    drafts.add(draft);
    burnedIds.add(id);
    return id;
  }
}
