/// 端侧粗估抽象与 raw_input 上云闸门（§3.7 数据主权、§10.1 端侧 OCR
/// 「不传原图」、§11.2 W11-12 任务 3）。
///
/// **§3.7 口径（任务明示「写清注释」）**：
/// - raw_input 上云开关**默认关**=即用即焚仅落结构化结果（§3.3「raw_input
///   上云开关 P0」）；图片字节是拍照通道的 raw_input；
/// - 开关关闭时**字节不出端**——任何需要上传图片的网络识别路径（百度菜品
///   识别 / Vision LLM，二者都必须把图片送出设备）都不可走；
/// - 因此拍照路径降级为「**端侧粗估 + 人工确认**」：端侧估计（不联网）给出
///   结构化初值（或 null=无法估计），其余字段由用户在确认卡/手填表单完成；
/// - 开关开启时才允许本次识别请求携带图片字节上云（§3.7「开=原文留档便于
///   排查」的网络语义）；**原图即焚不受开关影响**——§3.3 拍照通道行
///   「原图解析后即焚不落存储」、§5.6㉑「默认解析后即焚：原图不落服务端」
///   均无条件，开关只治理识别请求的字节出端；
/// - input_hash 缓存命中复用（§5.6⑭）在开关关闭时仍可用：查询只发生本地
///   ai_parses（字节不出端，复用的结构化结果是既有本地留痕）。
///
/// 端侧实现（ML Kit/Vision OCR、端侧小模型粗筛，§10.1 端侧行）由壳层注入；
/// 缺省 [NoOnDeviceEstimator] 恒返回 null=无端侧模型 → 直接人工确认表单——
/// 「缺省最严」安全兜底：不因装配缺失而把字节送出端。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capture_parser.dart' show CaptureParseResult;
import 'capture_photo_models.dart';

/// raw_input 上云开关读取点（§3.7/§3.3；§11.2 W11-12 任务 3）。
///
/// 缺省恒 false=默认关（§3.3「默认关=即用即焚」；装配缺失时取最严口径，
/// 字节永不出端）。宿主 override 传 settings 持有器同步读取
/// （apps/mobile `RawInputPolicy.enabled`——bootstrap 装载初值、设置页写回，
/// settings 表本地件、永不同步 §5.6⑲；同 TelemetryCaptureParser 的
/// `bool Function()? rawInputCloud` 注入形态）。
final Provider<bool Function()> captureRawInputCloudEnabledProvider =
    Provider<bool Function()>((ref) => _rawInputClosedByDefault);

bool _rawInputClosedByDefault() => false;

/// 端侧粗估抽象（不联网；估计与解析同构便于确认卡复用，§3.7 关闭口径）。
///
/// 实现约定：
/// - 返回 [CaptureParseResult]（provider/model 标 'on_device'/端侧模型名）；
///   该路径**无云端解析**，ai_parses 不落行（entries.ai_parse_id 为 null，
///   §5.6⑭ 留痕为云端口径）、不参与 input_hash 云缓存写；
/// - 返回 null=无法端侧估计（→ 人工确认表单，§3.7 降级口径）；
/// - 估计置信度按粗估口径从保守标注（低置信度强制高亮「份量可能不准」，
///   §3.3 同一信任语言）。
abstract interface class CaptureOnDeviceEstimator {
  Future<CaptureParseResult?> estimate(CapturePhotoParseRequest request);
}

/// 缺省兜底：恒 null（无端侧模型 → 人工确认，§3.7 关=端侧粗估+人工确认）。
class NoOnDeviceEstimator implements CaptureOnDeviceEstimator {
  const NoOnDeviceEstimator();

  @override
  Future<CaptureParseResult?> estimate(CapturePhotoParseRequest request) async =>
      null;
}

/// 注入点：缺省 [NoOnDeviceEstimator]（安全兜底，不抛错——关闭路径是默认
/// 生产路径，人工确认即正确行为）；壳接入端侧 OCR/模型后 override 注入。
final Provider<CaptureOnDeviceEstimator> captureOnDeviceEstimatorProvider =
    Provider<CaptureOnDeviceEstimator>((ref) => const NoOnDeviceEstimator());
