/// 拍照通道测试支撑：fixture 图片字节（package:image 真实 codec 现场编码，
/// 任务硬规则「测试禁止真实网络/相机，用 fixture 图片字节」）、联查钩子
/// 桩、异常压缩机桩。
///
/// 全部离线：识别供应商经 FakeDishAdapter（脚本化候选），HTTP 经
/// MockClient（契约测试），压缩经 PureDartImageCompressor（纯 Dart 真实
/// codec，fixture 小图）。
library;

import 'dart:typed_data';

import 'package:core_ai/core_ai.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'test_support.dart';

/// utf8 响应构造（契约测试用）：http ≥1.5 的 `Response` 不再收 `encoding`
/// 参数、按 content-type 头推断字符集（缺省 latin1——响应体含中文即抛
/// 「Contains invalid characters」）。识别响应必含中文（菜品中文名/中文
/// 错误信息），统一带 charset=utf-8 头构造。
http.Response utf8Response(String body, int status) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// 生成确定性 fixture JPEG 字节（固定像素函数，无随机——同参数恒同字节，
/// 端到端缓存命中断言依赖此确定性）。
Uint8List makeJpegFixture({int width = 64, int height = 48}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, (x * 4) % 256, (y * 5) % 256, 128, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// 生成 fixture PNG 字节（非 JPEG 输入 → 统一重编码 JPEG 的规范形断言用）。
Uint8List makePngFixture({int width = 32, int height = 32}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgba(x, y, 255 - x, y * 8, 64, 255);
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// 构造拍照解析请求（日期锚点取测试基准日，§5.1）。
PhotoParseRequest makePhotoRequest(
  Uint8List bytes, {
  String mime = 'image/jpeg',
  String date = kTestDate,
}) =>
    PhotoParseRequest(imageBytes: bytes, mime: mime, date: date);

/// 脚本化联查钩子（§7.1 第 6 步拍照侧：按菜品名精确查表）。
class MapDishRefLookup implements DishRefLookup {
  const MapDishRefLookup(this.entries);

  final Map<String, DishRefEntry> entries;

  @override
  DishRefEntry? lookup(String dishName) => entries[dishName];
}

/// 恒抛压缩异常的压缩机（压缩失败 → §7.4 一级降级路径测试用）。
class ThrowingCompressor implements ImageCompressor {
  const ThrowingCompressor();

  @override
  Future<CompressedImage> compress(PhotoImageInput input) async {
    throw PhotoCompressionException('注入的压缩失败（测试桩）');
  }
}

/// 确定性两道候选（管线主成功路径的 fixture 候选；未联查未直报 →
/// est_kcal 走本地估计基准 kFallbackKcalPer100g=150）。
const List<DishCandidate> kFixtureDishes = <DishCandidate>[
  DishCandidate(name: '宫保鸡丁', grams: 300, confidence: 0.7),
  DishCandidate(name: '米饭', grams: 200, confidence: 0.8),
];
