/// 真实供应商联调冒烟（§7.1 管线 + §7.5 通道验证）。
///
/// 硬规则「测试一律离线」的唯一豁免：本文件在 `SLIMCA_AI_KEY` 环境变量
/// 缺席时整组 skip——只有显式注入凭据才发起真实网络调用。凭据来源：
/// `SLIMCA_AI_KEY` / `SLIMCA_AI_BASE` / `SLIMCA_AI_MODEL` 三个环境变量，
/// 绝不写入任何仓库文件（.env 已被 .gitignore 覆盖）。
///
/// 运行示例（DeepSeek）：
/// ```
/// SLIMCA_AI_KEY=sk-xxx SLIMCA_AI_MODEL='deepseek-flash' \
///   flutter test test/live_llm_smoke_test.dart
/// ```
// 本文件的 print 是联调诊断输出（不进 CI 日常轨），豁免 lint。
// ignore_for_file: avoid_print
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:core_ai/core_ai.dart';

String? get _apiKey => Platform.environment['SLIMCA_AI_KEY'];
String get _baseUrl =>
    Platform.environment['SLIMCA_AI_BASE'] ?? 'https://api.deepseek.com/v1';
String get _model =>
    Platform.environment['SLIMCA_AI_MODEL'] ?? 'deepseek-flash';

/// 1×1 透明 PNG（格式兼容性探针：多模态请求被端点接受即为过，识别内容
/// 可为空——真实食物照片的识别质量属真机/真图验收范畴）。
const _kProbePngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

void main() {
  final hasKey = (_apiKey ?? '').trim().isNotEmpty;

  LlmAdapter adapter() => OpenAiCompatibleAdapter(
        OpenAiCompatibleConfig(
          baseUrl: _baseUrl,
          apiKey: _apiKey!.trim(),
          model: _model,
          jsonCapability: LlmJsonCapability.jsonObject,
          timeout: const Duration(seconds: 60),
          maxAttempts: 2,
        ),
      );

  test('真实联调·文本双解析：自由文本 → 结构化热量+金额草稿（§7.1-§7.3）',
      skip: !hasKey ? '未注入 SLIMCA_AI_KEY，离线纪律生效' : null, () async {
    final parser = LlmAiParser(
      adapter: adapter(),
      cache: InMemoryAiParseCache(),
    );
    final result = await parser.parse(const ParseInput(
      rawText: '早餐吃了两个肉包子和一杯豆浆，一共花了 6 块钱',
      context: ParseContext(date: '2026-11-17'),
    ));

    if (result is StructuredFailure) {
  
      print('━━━ 结构化解析失败 ━━━ reason=${result.reason} '
          'degrade=${result.degradeLevel} attempts=${result.attempts}');
      for (final e in result.errors) {
    
        print('    校验错: $e');
      }
  
      print('    lastRawOutput=${result.lastRawOutput}');
      if (result.cause != null) print('    cause=${result.cause}');
    }
    expect(result, isA<ParseSuccess>(), reason: '结构化解析必须成功（§7.4 一级降级仅在失败时触发；上方已打印诊断）');
    final success = result as ParseSuccess;
    expect(success.title, isNotEmpty);
    expect(success.lines, isNotEmpty, reason: '至少产出一条 facet 行（calorie/money）');

    print('━━━ 文本解析成功 ━━━ title="${success.title}" '
        'lines=${success.lines.length} '
        'kind=${success.kind} inputHash=${success.inputHash}');
    for (final line in success.lines) {
  
      print('    行: type=${line.type} direction=${line.direction} '
          'amount=${line.amount} confidence=${line.confidence}');
    }
  });

  test('真实联调·图像理解：多模态请求格式被端点接受（vision）',
      skip: !hasKey ? '未注入 SLIMCA_AI_KEY，离线纪律生效' : null, () async {
    final vision = VisionLlmDishAdapter(
      adapter: adapter(),
      timeout: const Duration(seconds: 60),
    );
    final probe = base64Decode(_kProbePngBase64);
    // 1×1 探针图不含食物——空列表=格式被接受且端点正常回话，即为过；
    // 非空候选则如实打印（不应发生，发生也不算失败）。
    final dishes =
        await vision.recognize(CompressedImage(
      bytes: probe,
      mime: 'image/png',
      widthPx: 1,
      heightPx: 1,
    ));

    print('━━━ 图像理解端点接受 ━━━ candidates=${dishes.length}');
    for (final dish in dishes) {
  
      print('    候选: ${dish.name} ${dish.grams}g conf=${dish.confidence}');
    }
    expect(dishes, isA<List<DishCandidate>>());
  });
}
