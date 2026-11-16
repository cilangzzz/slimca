/// 输入规范化、缓存键与提示词/JSON Schema 组装（§7.1-§7.2）。
///
/// 组成：
/// - [normalizeParseInput]：§7.1 管线第一步「规范化」；
/// - [computeInputHash]：sha256 缓存键（§7.1/§5.6⑭）；
/// - [buildParseJsonSchema]：§7.2 受约束输出 schema（response_format
///   json_schema 档载荷；json_object 档与降级档经提示词承载同一 schema）；
/// - [buildSystemPrompt]：系统提示词（字段口径 + 单边约束 + 分类枚举 + 示例）；
/// - [buildRetryInstruction]：校验失败后的纠错回喂指令（重试 1 次，§7.1）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'parse_categories.dart';
import 'parse_models.dart';

/// 提示词版本（ai_parses.prompt_version，§5.6⑭；回放兼容性闸门——版本
/// 变更后旧缓存视为未命中）。
const String kPromptVersion = 'w3-4-v1';

/// 缓存键信封版本（算法演进时递增，避免跨算法串键）。
const String _kHashEnvelopeVersion = 'v1';

/// 字段分隔符（unit separator）：规范化文本含任意用户内容，取不可见控制
/// 字符防碰撞。
const String _kHashFieldSep = '\x1f';

/// §7.1「规范化」：去首尾空白 + 连续空白（含全角空格）折叠为单空格。
///
/// 规范化后再做哈希：同一句输入因多打一个空格/换行也能命中缓存。
String normalizeParseInput(String rawText) =>
    rawText.replaceAll(RegExp(r'[\s　]+'), ' ').trim();

/// 计算缓存键（§7.1「input_hash（sha256）」、§5.6⑭ input_hash 行）。
///
/// 信封 = `slimca-ai-parse|v1|<mode>|<规范化输入>`：
/// - 单边模式参与哈希——同文本在不同模式下产出行集合不同，不串缓存
///   （§3.3「schema 中对应 lines 只产出一类」）；
/// - **日期不参与**——解析输出不含日期字段，常吃常花的跨日重复输入必须
///   命中（§7.5 缓存再省 15-25% 的前提）；
/// - 输入通道（text/voice）不参与——同文本同解析（转写即文本）。
String computeInputHash(String normalizedText, ParseMode mode) {
  final envelope =
      'slimca-ai-parse$_kHashFieldSep$_kHashEnvelopeVersion'
      '$_kHashFieldSep${mode.wire}$_kHashFieldSep$normalizedText';
  return sha256.convert(utf8.encode(envelope)).toString();
}

/// §7.2 受约束输出 JSON Schema（response_format json_schema 档载荷）。
///
/// lines 元素 schema 随单边模式收窄（§3.3「schema 中对应 lines 只产出一
/// 类」）：both 档用 oneOf 双分支；单边档直接只给对应分支。schema 是引导
/// 性约束（strict 不强制），硬闸门在 parse_validator.dart。
Map<String, Object?> buildParseJsonSchema(ParseMode mode) {
  final moneySchema = _moneyLineSchema();
  final calorieSchema = _calorieLineSchema();
  final lineProperties = <String, Object?>{
    'type': <String, Object?>{'type': 'string'},
    'confidence': <String, Object?>{'type': 'number'},
  };
  final lineSchema = <String, Object?>{
    'type': 'object',
    'additionalProperties': true,
    'required': <String>['type', 'confidence'],
    'properties': lineProperties,
  };
  switch (mode) {
    case ParseMode.both:
      lineProperties['type'] = <String, Object?>{
        'type': 'string',
        'enum': <String>['money', 'calorie'],
      };
      lineSchema['oneOf'] = <Object?>[moneySchema, calorieSchema];
    case ParseMode.moneyOnly:
      lineSchema.addAll(moneySchema);
    case ParseMode.kcalOnly:
      lineSchema.addAll(calorieSchema);
  }
  return <String, Object?>{
    'type': 'object',
    'additionalProperties': true,
    'required': <String>['title', 'kind', 'lines'],
    'properties': <String, Object?>{
      'title': <String, Object?>{'type': 'string'},
      'kind': <String, Object?>{
        'type': 'string',
        'enum': <String>['food', 'fitness', 'expense', 'mixed', 'note'],
      },
      'parse_notes': <String, Object?>{'type': 'string'},
      'lines': <String, Object?>{
        'type': 'array',
        'minItems': 1,
        'items': lineSchema,
      },
    },
  };
}

Map<String, Object?> _moneyLineSchema() => <String, Object?>{
      'type': 'object',
      'additionalProperties': true,
      'required': <String>['type', 'amount_minor', 'confidence'],
      'properties': <String, Object?>{
        'type': <String, Object?>{'type': 'string', 'enum': <String>['money']},
        // 金额一律最小货币单位「分」（§5.1）：18 元 → 1800；必须 >0（§7.1）。
        'amount_minor': <String, Object?>{
          'type': 'integer',
          'minimum': 1,
        },
        // 收入方向标记（缺省支出；§5.2② direction: money 按 expense=out/income=in）。
        'income': <String, Object?>{'type': 'boolean'},
        'currency': <String, Object?>{'type': 'string'},
        'ledger_hint': <String, Object?>{'type': 'string'},
        'category_hint': <String, Object?>{'type': 'string'},
        'merchant': <String, Object?>{'type': ['string', 'null']},
        'confidence': <String, Object?>{'type': 'number', 'minimum': 0, 'maximum': 1},
      },
    };

Map<String, Object?> _calorieLineSchema() => <String, Object?>{
      'type': 'object',
      'additionalProperties': true,
      'required': <String>['type', 'amount_kcal', 'confidence'],
      'properties': <String, Object?>{
        'type': <String, Object?>{
          'type': 'string',
          'enum': <String>['calorie'],
        },
        // 热量一律整数 kcal ∈ [0,5000]（§7.1 校验器、§5.1）。
        'amount_kcal': <String, Object?>{
          'type': 'integer',
          'minimum': 0,
          'maximum': 5000,
        },
        'category_hint': <String, Object?>{'type': 'string'},
        'confidence': <String, Object?>{
          'type': 'number',
          'minimum': 0,
          'maximum': 1,
        },
        'items': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{
            'type': 'object',
            'additionalProperties': true,
            'required': <String>['name', 'portion_g', 'kcal'],
            'properties': <String, Object?>{
              'name': <String, Object?>{'type': 'string'},
              'portion_g': <String, Object?>{'type': 'number', 'exclusiveMinimum': 0},
              'kcal': <String, Object?>{'type': 'integer', 'minimum': 0, 'maximum': 5000},
              'protein_g': <String, Object?>{'type': 'number'},
              'carb_g': <String, Object?>{'type': 'number'},
              'fat_g': <String, Object?>{'type': 'number'},
              'ref_source': <String, Object?>{
                'type': 'string',
                'enum': <String>['usda', 'off', 'baidu', 'local', 'llm'],
              },
              'ref_id': <String, Object?>{'type': ['string', 'null']},
              'confidence': <String, Object?>{'type': 'number'},
            },
          },
        },
      },
    };

/// 系统提示词（§7.2 受约束输出的文本载体；单边约束/分类枚举/日期锚点注入）。
String buildSystemPrompt({
  required ParseMode mode,
  required String date,
  Iterable<String> presetCategories = kDefaultPresetCategoryNames,
}) {
  final modeRule = switch (mode) {
    ParseMode.both => 'money 与 calorie 两类行都可以产出；钱和热量同时存在时必须两类都产出。',
    ParseMode.moneyOnly => '本次为「仅记钱」模式：只允许产出 type=money 行；忽略输入中的热量语义。',
    ParseMode.kcalOnly => '本次为「仅记热量」模式：只允许产出 type=calorie 行；忽略输入中的金额语义。',
  };
  final categories = presetCategories.join('、');
  return '''
你是 Slimca 的记账解析引擎。把用户的一条自然语言输入解析为「一件事」的结构化 JSON。只输出 JSON 本体，禁止输出任何解释文字、前后缀或 markdown 代码块。

输出字段：
- title：一句话描述（不超过 20 字）。
- kind：food | fitness | expense | mixed | note（钱+热量同时产出时取 mixed）。
- lines：产出行数组，元素二选一：
  - 金额行：{"type":"money","amount_minor":整数分,"income":false,"currency":"CNY","confidence":0到1,"ledger_hint":"default","category_hint":"内置分类名","merchant":null}
  - 热量行：{"type":"calorie","amount_kcal":整数,"confidence":0到1,"category_hint":"内置分类名","items":[{"name":"菜品名","portion_g":克数,"kcal":整数,"protein_g":0,"carb_g":0,"fat_g":0,"ref_source":"llm"}]}
- parse_notes：一句话估算依据说明（可省略）。

硬规则：
1. 金额一律最小货币单位「分」：18 元必须输出 amount_minor=1800；金额必须大于 0。
2. 热量一律整数 kcal，范围 [0,5000]。
3. confidence 是你对这一行估计的确信程度，取值 [0,1]：数字金额接近 1，份量/热量估算通常 0.5-0.7。每个 items 元素也给出 confidence。
4. category_hint 优先从内置分类枚举选择：$categories；没有合适枚举时才给自定义词。
5. 单边约束：$modeRule
6. 今天是 $date（本地日历日）；「昨天/上午」等相对表达据此理解，但输出中不包含日期。
7. portion_g 按常见份量估计；ref_source 无把握时填 "llm"；菜品明细尽量拆分单菜品。
8. 每行必填 confidence，缺失会导致输出被整体拒绝。

示例（用户输入「中午吃了兰州拉面花了 18」）：
{"title":"兰州拉面","kind":"mixed","lines":[{"type":"calorie","amount_kcal":550,"confidence":0.62,"items":[{"name":"牛肉拉面","portion_g":450,"kcal":500,"protein_g":25,"carb_g":65,"fat_g":12,"ref_source":"local"}],"category_hint":"餐饮-面食"},{"type":"money","amount_minor":1800,"currency":"CNY","confidence":0.93,"ledger_hint":"default","category_hint":"餐饮-面食","merchant":null}],"parse_notes":"份量按中碗估计；金额来自文本「18」"}
''';
}

/// 校验失败后的纠错回喂指令（§7.1「校验失败重试 1 次」的重试消息）。
///
/// 把上一轮原始输出与错误清单回喂给模型，要求修正后重新输出完整 JSON。
String buildRetryInstruction(List<String> errors) {
  final listed = errors.map((e) => '- $e').join('\n');
  return '''
上一次输出未通过校验，错误如下：
$listed

请严格按系统提示中的 JSON Schema 修正后重新输出完整 JSON（不要复述错误、不要输出 JSON 以外的任何文字）。''';
}
