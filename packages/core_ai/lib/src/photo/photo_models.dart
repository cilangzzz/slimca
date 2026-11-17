/// 拍照通道数据模型（§3.3 拍照通道 P1、§7.1 管线、§11.2 W11-12 主线
/// 「拍照通道」）。
///
/// 数据流口径（§3.3）：
/// ```
/// 原图 [PhotoImageInput]（即用即焚，不落存储）
///   → [ImageCompressor.compress] → 端侧压缩规范形 [CompressedImage]
///   （长边 1280、JPEG q80）
///   → [ImageDishAdapter.recognize] → [DishCandidate] 候选清单
///   → food_items 草稿组装（photo_parser.dart，§5.2③）
/// ```
/// 分层边界（§10.4）：本库只产出草稿与候选，attachments 附件行（§5.6㉑
/// 「解析后即焚：原图不落服务端」）的落库由宿主 feature 层经 core_db 编排。
library;

import 'dart:typed_data';

import '../parse/parse_models.dart' show FoodRefSource;

/// 原始拍摄图（[ImageCompressor] 的输入；原图即用即焚——解析后不落任何
/// 存储表，§3.3「原图解析后即焚不落存储」）。
class PhotoImageInput {
  const PhotoImageInput({required this.bytes, required this.mime});

  /// 原图字节（相机/相册原始编码）。
  final Uint8List bytes;

  /// MIME 类型（如 `image/jpeg`、`image/png`；与 §5.6㉑ attachments.mime
  /// 同一口径，仅作解码提示，压缩产物统一重编码为 JPEG）。
  final String mime;
}

/// 端侧压缩后的规范形（§3.3「端侧压缩（长边 1280、JPEG q80）」的产物）。
///
/// 同时是 [ImageDishAdapter.recognize] 的输入口径——「输入压缩后图片字节
/// +mime」：识别供应商只见压缩规范形，原图不出压缩机即被丢弃。
class CompressedImage {
  const CompressedImage({
    required this.bytes,
    required this.mime,
    required this.widthPx,
    required this.heightPx,
  });

  /// 压缩后图片字节（JPEG 编码）。
  final Uint8List bytes;

  /// MIME 类型（恒 `image/jpeg`——规范形统一重编码口径）。
  final String mime;

  /// 压缩后宽度（像素）。
  final int widthPx;

  /// 压缩后高度（像素）。
  final int heightPx;
}

/// 菜品候选（[ImageDishAdapter] 的输出口径：name/grams/confidence/
/// categoryHint，W11-12 任务口径）。
class DishCandidate {
  const DishCandidate({
    required this.name,
    required this.grams,
    required this.confidence,
    this.categoryHint,
    this.kcalPer100gHint,
  });

  /// 菜品名（中文优先，§5.2③）。
  final String name;

  /// 基准份量（克）：确认卡份量滑杆联动重算的初值（§3.3「先拍后改确认卡」）。
  /// 百度菜品识别无份量输出 → 适配器填 [kDefaultDishPortionG] 基准；
  /// Vision LLM 按照片估计；联查命中且参考库给默认份量时由草稿组装覆写。
  final double grams;

  /// 菜品级置信度 ∈ [0,1]（§5.2③ food_items.confidence 初值；未联查校准
  /// 时由草稿组装降档，红线 §7.1）。
  final double confidence;

  /// 分类提示（确认卡九宫格快选初值，§3.3；百度无分类输出 → null）。
  final String? categoryHint;

  /// Vision LLM 直报的每百克热量参考（可选携载位；核心四字段之外的任务
  /// 扩展——§7.2 口径 Vision 会按份量直报 kcal，换算成每百克随候选带回）。
  ///
  /// 红线（§7.1）：LLM 直报热量不可信——本字段仅在联查未命中时作 est_kcal
  /// 初值（置信度同步降档），联查命中时不采用。
  final double? kcalPer100gHint;

  @override
  String toString() =>
      'DishCandidate($name, ${grams}g, conf=$confidence'
      '${categoryHint == null ? '' : ', $categoryHint'})';
}

/// 缺省基准份量（克）：营养学基准 100g/份——百度菜品识别无份量输出的
/// 兜底初值；确认卡滑杆可调（§3.3），联查库可给更准的默认份量覆写。
const double kDefaultDishPortionG = 100.0;

/// 联查未命中且无模型直报时的每百克热量本地估计基准（中餐混合菜品经验
/// 中值，仅供确认卡修正的初值；不虚报精度——est_kcal 伴随置信度降档，
/// §7.1 红线「热量必须走联查+置信度标注」）。
const double kFallbackKcalPer100g = 150.0;

/// 未联查校准的置信度降档系数（§7.1 红线：未走食物库联查的热量估算须以
/// 低置信标注——确认卡 <0.5 强制高亮「份量可能不准」，§3.3/§7.3 三色点）。
const double kUncalibratedConfidencePenalty = 0.8;

/// 菜品识别异常（压缩失败等适配器前置失败；识别供应商自身的 HTTP/协议
/// 失败复用 llm_adapter.dart 的 [LlmException] 分类体系——同一分类映射
/// 同一 §7.4 降级语义）。
class PhotoCompressionException implements Exception {
  const PhotoCompressionException(this.message, {this.cause});

  /// 人读错误摘要（StructuredFailure.errors 用）。
  final String message;

  /// 原始异常（诊断用）。
  final Object? cause;

  @override
  String toString() => 'PhotoCompressionException: $message';
}

/// 菜品识别适配器抽象（§3.3 拍照通道「百度菜品识别先行 → Vision LLM 兜底」
/// 的统一供应商接缝；§7.4 第 4 级双供应商 fallback 的编排单元）。
///
/// 实现约定：
/// - [recognize] 输入恒为端侧压缩规范形 [CompressedImage]（原图不出压缩机，
///   §3.3 即用即焚）；失败抛 llm_adapter.dart 的 [LlmException] 分类异常
///   （超时/限流/额度/鉴权等已分类），照片中无可识别菜品返回**空列表**
///   （不抛异常——空结果是正常业务分支，编排层据此切换兜底供应商）；
/// - 内部自带「超时 + 瞬时错误重试」（口径同 LlmAdapter 契约）。
abstract interface class ImageDishAdapter {
  /// 供应商标识（ai_parses.provider，§5.6⑭ 可 A/B 对比）。
  String get providerId;

  /// 模型/接口名（ai_parses.model）。
  String get modelId;

  /// 联查未命中时的 ref_source 标记（§5.2③ 联查来源口径：百度菜品库识别
  /// → [FoodRefSource.baidu]；Vision LLM 识别 → [FoodRefSource.llm]）。
  FoodRefSource get dishRefSource;

  /// 识别一张压缩后图片中的菜品候选（按置信度降序）。
  Future<List<DishCandidate>> recognize(CompressedImage image);
}
