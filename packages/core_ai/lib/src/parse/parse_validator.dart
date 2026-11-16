/// 受约束 JSON 解码 + 字段校验 + §7.3 字段映射（§7.1 校验器为硬闸门）。
///
/// 校验规则（§7.1「校验器（金额>0、kcal∈[0,5000]、分类枚举内、必需字段齐）」
/// + §7.3 字段映射表 + §5.1/§5.2 单位口径）：
/// - 顶层必须 JSON 对象；title/kind/lines 必需；
/// - 金额行 amount_minor：整数、单位=分、必须 >0（§5.1 金额行、§7.1）；
/// - 热量行 amount_kcal：整数、∈[0,5000]（§7.1）；
/// - 每行 confidence 必填 ∈[0,1]（§5.2② AI 产出行必填；菜品级缺失时继承行级）；
/// - category_hint 经 [CategoryResolver] 映射（命中内置 / 未命中挂其他+建议新建）；
/// - 单边模式越界行（§3.3）直接丢弃记 note——是上下文修正而非模型违例；
///   字段级违例（缺字段/类型错/超界）则整次失败、触发重试（§7.1）。
library;

import 'dart:convert';

import 'package:core_domain/core_domain.dart' as dom;

import 'parse_categories.dart';
import 'parse_models.dart';

/// 校验失败异常（携带错误清单回喂重试；reason 区分校验违例与空结果）。
class AiValidationException implements Exception {
  const AiValidationException(this.errors, this.rawOutput, this.reason);

  /// 人读中文错误清单（回喂重试 + [StructuredFailure.errors]）。
  final List<String> errors;

  /// 触发校验的原始输出。
  final String rawOutput;

  /// 失败归因（validationFailed / emptyResult）。
  final AiFailureReason reason;

  @override
  String toString() =>
      'AiValidationException(${reason.wire}): ${errors.join('；')}';
}

/// 从模型原始输出中提取 JSON 载荷（§7.1「拒绝自由文本」的宽容入口）。
///
/// 容忍：markdown 代码围栏（```json … ```）、前后缀说明文字——取首个 `{`
/// 到最后一个 `}` 之间内容。提取不到对象即抛（仍算受约束失败）。
String extractJsonPayload(String rawOutput) {
  var text = rawOutput.trim();
  final fenced = RegExp(r'^```[a-zA-Z0-9]*\s*([\s\S]*?)\s*```$').firstMatch(text);
  if (fenced != null) {
    text = (fenced.group(1) ?? '').trim();
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const AiValidationException(
      ['输出中未找到 JSON 对象（受约束解码失败，§7.1）'],
      '',
      AiFailureReason.invalidJson,
    );
  }
  return text.substring(start, end + 1);
}

/// 解码 + 校验 + §7.3 映射。任何字段级违例抛 [AiValidationException]。
///
/// [rawOutput] 为模型原始文本（缓存回放时即 ai_parses.raw_output）。
ValidatedParse validateAndMap({
  required String rawOutput,
  required ParseMode mode,
  required CategoryResolver categoryResolver,
}) {
  final errors = <String>[];
  final notes = <String>[];

  // ── 受约束解码（拒绝自由文本，§7.1）──
  final Object? decoded;
  try {
    decoded = jsonDecode(extractJsonPayload(rawOutput));
  } on AiValidationException catch (error) {
    throw AiValidationException(
      error.errors,
      rawOutput,
      AiFailureReason.invalidJson,
    );
  } on FormatException catch (error) {
    throw AiValidationException(
      ['输出不是合法 JSON：${error.message}'],
      rawOutput,
      AiFailureReason.invalidJson,
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw AiValidationException(
      ['顶层必须是 JSON 对象，实际 ${decoded.runtimeType}'],
      rawOutput,
      AiFailureReason.invalidJson,
    );
  }

  // ── title（§7.3 → entries.title）──
  final titleRaw = decoded['title'];
  final title = titleRaw is String ? titleRaw.trim() : null;
  if (title == null || title.isEmpty) {
    errors.add('title 缺失或非字符串（§7.2 必需字段）');
  }

  // ── lines 逐行校验与映射（§7.2 lines[] → §5.2② 行草稿）──
  final linesRaw = decoded['lines'];
  if (linesRaw is! List) {
    errors.add('lines 缺失或非数组（§7.2 必需字段）');
    throw AiValidationException(
      errors,
      rawOutput,
      AiFailureReason.validationFailed,
    );
  }
  if (linesRaw.isEmpty) {
    throw AiValidationException(
      ['lines 为空：未产出任何可用行（§7.1 必需字段齐）'],
      rawOutput,
      AiFailureReason.emptyResult,
    );
  }
  final drafts = <ParsedLineDraft>[];
  for (var i = 0; i < linesRaw.length; i++) {
    final lineRaw = linesRaw[i];
    if (lineRaw is! Map<String, Object?>) {
      errors.add('lines[$i] 必须是对象');
      continue;
    }
    final typeRaw = lineRaw['type'];
    if (typeRaw is! String || (typeRaw != 'money' && typeRaw != 'calorie')) {
      errors.add("lines[$i].type 必须为 money|calorie，实际：$typeRaw");
      continue;
    }
    // 单边开关（§3.3）：越界行丢弃记 note——上下文修正，不算模型违例。
    final isMoney = typeRaw == 'money';
    if (mode == ParseMode.moneyOnly && !isMoney) {
      notes.add('已按「仅记钱」丢弃 lines[$i]（calorie 行，§3.3 单边开关）');
      continue;
    }
    if (mode == ParseMode.kcalOnly && isMoney) {
      notes.add('已按「仅记热量」丢弃 lines[$i]（money 行，§3.3 单边开关）');
      continue;
    }
    final draft = isMoney
        ? _mapMoneyLine(lineRaw, i, errors, notes, categoryResolver)
        : _mapCalorieLine(lineRaw, i, errors, notes, categoryResolver);
    if (draft != null) {
      drafts.add(draft);
    }
  }
  if (drafts.isEmpty && errors.isEmpty) {
    throw AiValidationException(
      ['单边模式（${mode.wire}）下无可用产出行'],
      rawOutput,
      AiFailureReason.emptyResult,
    );
  }

  // ── kind（§7.3 → entries.kind；单边模式下按保留行推导）──
  var kind = dom.EntryKind.mixed;
  final kindRaw = decoded['kind'];
  if (kindRaw == null) {
    errors.add('kind 缺失（§7.2 必需字段）');
  } else if (kindRaw is! String) {
    errors.add('kind 必须为字符串，实际 ${kindRaw.runtimeType}');
  } else {
    try {
      final parsedKind = dom.EntryKind.fromWire(kindRaw);
      final derived = _deriveKind(drafts);
      if (mode != ParseMode.both && parsedKind != derived) {
        // 单边过滤后 kind 随保留行修正（上下文修正，不触发重试）。
        notes.add('kind 由单边模式推导为 ${derived.wire}');
        kind = derived;
      } else {
        kind = parsedKind;
      }
    } on ArgumentError {
      errors.add("kind '$kindRaw' 不在枚举 food|fitness|expense|mixed|note 内（§5.2①）");
    }
  }

  // ── parse_notes（§7.3 → entries.note 追加，可关）──
  final parseNotesRaw = decoded['parse_notes'];
  String? parseNotes;
  if (parseNotesRaw != null) {
    if (parseNotesRaw is String) {
      parseNotes = parseNotesRaw.trim().isEmpty ? null : parseNotesRaw.trim();
    } else {
      errors.add('parse_notes 必须为字符串');
    }
  }

  if (errors.isNotEmpty) {
    throw AiValidationException(
      errors,
      rawOutput,
      AiFailureReason.validationFailed,
    );
  }
  return ValidatedParse(
    title: title!,
    kind: kind,
    lines: drafts,
    parseNotes: parseNotes,
    notes: List<String>.unmodifiable(notes),
  );
}

/// 按保留行推导 kind（§5.2①：钱+热量=mixed；仅钱=expense；仅热量=food）。
dom.EntryKind _deriveKind(List<ParsedLineDraft> drafts) {
  final hasMoney = drafts.any((d) => d.type == dom.LineType.money);
  final hasCalorie = drafts.any((d) => d.type == dom.LineType.calorie);
  if (hasMoney && hasCalorie) {
    return dom.EntryKind.mixed;
  }
  return hasMoney ? dom.EntryKind.expense : dom.EntryKind.food;
}

/// 金额行映射（§7.3：lines[].type=money → entry_lines(type=money, amount=分,
/// ledger_id, category_id, currency, confidence)）。字段违例写 [errors]。
ParsedLineDraft? _mapMoneyLine(
  Map<String, Object?> line,
  int index,
  List<String> errors,
  List<String> notes,
  CategoryResolver categoryResolver,
) {
  final path = 'lines[$index]';
  final before = errors.length;
  final amount = _requireAmountMinor(line['amount_minor'], path, errors);
  final confidence = _requireConfidence(line['confidence'], path, errors);
  _requireMoneyFacets(line, index, errors);
  if (amount == null || confidence == null || errors.length != before) {
    return null;
  }

  // income 缺省 false → direction=out（支出）；true → in（§5.2② direction 行）。
  final income = line['income'];
  final direction = income is bool && income
      ? dom.LineDirection.income
      : dom.LineDirection.outcome;

  final currency = _trimmedString(line['currency']);
  final ledgerHint = _trimmedString(line['ledger_hint']);
  final merchant = _trimmedString(line['merchant']);
  final categoryHint = _trimmedString(line['category_hint']);

  // §7.3：category_hint → category_id（命中内置；未命中挂「其他」+建议新建）。
  final category = categoryResolver.resolve(categoryHint);
  if (categoryHint != null && !category.matched) {
    notes.add('category_hint「$categoryHint」未命中内置分类'
        '${category.suggestNew ? '，已挂「其他」并建议新建' : ''}（§7.3）');
  }

  // payload（§5.2② 行级明细引用：商户等）。
  final payload = <String, Object?>{
    if (merchant != null) 'merchant': merchant,
    if (ledgerHint != null) 'ledger_hint': ledgerHint,
  };

  return ParsedLineDraft(
    type: dom.LineType.money,
    direction: direction,
    amount: amount,
    confidence: confidence,
    ledgerHint: ledgerHint,
    categoryId: category.categoryId,
    categoryHint: categoryHint == null
        ? null
        : category.categoryName ?? categoryHint,
    categorySuggestNew: category.suggestNew,
    currency: (currency == null || currency.isEmpty) ? 'CNY' : currency,
    payload: payload.isEmpty ? null : payload,
  );
}

/// 安全取 trim 后字符串（类型已由 *_require* 校验，此处仅做提取）。
String? _trimmedString(Object? raw) =>
    raw is String ? (raw.trim().isEmpty ? null : raw.trim()) : null;

/// 热量行映射（§7.3：lines[].type=calorie → entry_lines(type=calorie,
/// amount=kcal, confidence, payload) + food_items 逐菜品）。
ParsedLineDraft? _mapCalorieLine(
  Map<String, Object?> line,
  int index,
  List<String> errors,
  List<String> notes,
  CategoryResolver categoryResolver,
) {
  final path = 'lines[$index]';
  final before = errors.length;
  final kcal = _requireLineKcal(line['amount_kcal'], path, errors);
  final confidence = _requireConfidence(line['confidence'], path, errors);
  final categoryHint = _trimmedString(line['category_hint']);
  if (line['category_hint'] != null && categoryHint == null) {
    errors.add('$path.category_hint 必须为字符串或 null');
  }
  if (kcal == null || confidence == null || errors.length != before) {
    return null;
  }

  // §7.3：category_hint → category_id（与金额行同口径；未命中挂「其他」
  // + 建议新建）。
  final category = categoryResolver.resolve(categoryHint);
  if (categoryHint != null && !category.matched) {
    notes.add('category_hint「$categoryHint」未命中内置分类'
        '${category.suggestNew ? '，已挂「其他」并建议新建' : ''}（§7.3）');
  }

  final itemsRaw = line['items'];
  final items = <ParsedFoodItemDraft>[];
  if (itemsRaw != null) {
    if (itemsRaw is! List) {
      errors.add('$path.items 必须为数组');
      return null;
    }
    for (var i = 0; i < itemsRaw.length; i++) {
      final item = itemsRaw[i];
      if (item is! Map<String, Object?>) {
        errors.add('$path.items[$i] 必须是对象');
        continue;
      }
      final draft = _mapFoodItem(item, '$path.items[$i]', errors, confidence);
      if (draft != null) {
        items.add(draft);
      }
    }
    // 行内菜品级错误只计入行失败（由 errors 汇总触发整次重试）。
    if (items.length != itemsRaw.length) {
      return null;
    }
  }

  return ParsedLineDraft(
    type: dom.LineType.calorie,
    // §5.2②：calorie 行 direction 恒为 in。
    direction: dom.LineDirection.income,
    amount: kcal,
    confidence: confidence,
    categoryId: category.categoryId,
    categoryHint: categoryHint == null
        ? null
        : category.categoryName ?? categoryHint,
    categorySuggestNew: category.suggestNew,
    items: items,
    payload: null,
  );
}

/// 菜品明细映射（§5.2③ food_items；confidence 缺失继承行级——§7.2 示例
/// 即如此，文档口径允许行级置信度覆盖菜品级）。
ParsedFoodItemDraft? _mapFoodItem(
  Map<String, Object?> item,
  String path,
  List<String> errors,
  double lineConfidence,
) {
  final nameRaw = item['name'];
  final name = nameRaw is String ? nameRaw.trim() : null;
  if (name == null || name.isEmpty) {
    errors.add('$path.name 缺失或非字符串');
  }
  final portionRaw = item['portion_g'];
  double? portionG;
  if (portionRaw == null) {
    errors.add('$path.portion_g 缺失（份量滑杆重算基准，§3.3）');
  } else if (portionRaw is! num) {
    errors.add('$path.portion_g 必须为数字，实际 ${portionRaw.runtimeType}');
  } else if (portionRaw <= 0) {
    errors.add('$path.portion_g 必须为正数');
  } else {
    portionG = portionRaw.toDouble();
  }
  final kcal = _requireItemKcal(item['kcal'], path, errors);

  final macros = _requireMacros(item, path, errors);
  final refSource = _requireRefSource(item['ref_source'], path, errors);
  final refId = _trimmedString(item['ref_id']);
  if (item['ref_id'] != null && refId == null) {
    errors.add('$path.ref_id 必须为字符串或 null');
  }
  final confidenceRaw = item['confidence'];
  final confidence = confidenceRaw == null
      // 菜品级缺失 → 继承行级（§7.2 示例口径；§5.2③ 列 NOT NULL 必须有值）。
      ? lineConfidence
      : _requireConfidence(confidenceRaw, path, errors);
  if (name == null || portionG == null || kcal == null || confidence == null) {
    return null;
  }
  return ParsedFoodItemDraft(
    name: name,
    portionG: portionG,
    kcal: kcal,
    proteinG: macros[0],
    carbG: macros[1],
    fatG: macros[2],
    refSource: refSource,
    refId: refId,
    confidence: confidence,
  );
}

List<double> _requireMacros(
  Map<String, Object?> item,
  String path,
  List<String> errors,
) {
  final out = <double>[0, 0, 0];
  final keys = <String>['protein_g', 'carb_g', 'fat_g'];
  for (var i = 0; i < keys.length; i++) {
    final raw = item[keys[i]];
    if (raw == null) {
      continue;
    }
    if (raw is! num || raw < 0) {
      errors.add('$path.${keys[i]} 必须为非负数字');
      continue;
    }
    out[i] = raw.toDouble();
  }
  return out;
}

FoodRefSource _requireRefSource(Object? raw, String path, List<String> errors) {
  if (raw == null) {
    // 缺省 llm（提示词硬规则 7：无把握填 llm；联查命中后由校准改写，§7.1）。
    return FoodRefSource.llm;
  }
  if (raw is! String) {
    errors.add('$path.ref_source 必须为字符串');
    return FoodRefSource.llm;
  }
  try {
    return FoodRefSource.fromWire(raw);
  } on ArgumentError {
    errors.add(
      "$path.ref_source 必须为 usda|off|baidu|local|llm，实际：'$raw'（§5.2③）",
    );
    return FoodRefSource.llm;
  }
}

int? _requireAmountMinor(Object? raw, String path, List<String> errors) {
  if (raw == null) {
    errors.add('$path.amount_minor 缺失（金额行必需，§7.3）');
    return null;
  }
  // 严格整数分（§5.1）：字符串 "1800"、小数 1800.5 都算类型错（任务口径
  // 「金额单位分」——本库不猜测元/分换算，口径错就交重试纠偏）。
  if (raw is! int) {
    errors.add(
      '$path.amount_minor 必须为整数分（实际 ${raw.runtimeType}；'
      '"18 元"应输出 1800，§5.1/§7.3）',
    );
    return null;
  }
  if (raw <= 0) {
    errors.add('$path.amount_minor 必须为正数（金额>0，§7.1 校验器）');
    return null;
  }
  return raw;
}

int? _requireLineKcal(Object? raw, String path, List<String> errors) {
  if (raw == null) {
    errors.add('$path.amount_kcal 缺失（热量行必需，§7.3）');
    return null;
  }
  if (raw is! int) {
    errors.add('$path.amount_kcal 必须为整数 kcal，实际 ${raw.runtimeType}');
    return null;
  }
  if (raw < 0 || raw > 5000) {
    errors.add('$path.amount_kcal 必须落在 [0,5000]（§7.1 校验器）');
    return null;
  }
  return raw;
}

int? _requireItemKcal(Object? raw, String path, List<String> errors) =>
    _requireLineKcal(raw, path, errors);

double? _requireConfidence(Object? raw, String path, List<String> errors) {
  if (raw == null) {
    errors.add('$path.confidence 缺失（§5.2② AI 产出行必填）');
    return null;
  }
  if (raw is! num) {
    errors.add('$path.confidence 必须为数字，实际 ${raw.runtimeType}');
    return null;
  }
  final value = raw.toDouble();
  if (value.isNaN || value < 0 || value > 1) {
    errors.add('$path.confidence 必须落在 [0,1]（§5.2②）');
    return null;
  }
  return value;
}

/// money 行外围字段类型校验（income/currency/ledger_hint/category_hint/
/// merchant；值合法但类型错 → 计错，阻断成功）。
void _requireMoneyFacets(
  Map<String, Object?> line,
  int index,
  List<String> errors,
) {
  final path = 'lines[$index]';
  final income = line['income'];
  if (income != null && income is! bool) {
    errors.add('$path.income 必须为布尔');
  }
  for (final key in const ['currency', 'ledger_hint', 'category_hint', 'merchant']) {
    final raw = line[key];
    if (raw != null && raw is! String) {
      errors.add('$path.$key 必须为字符串或 null');
    }
  }
}
