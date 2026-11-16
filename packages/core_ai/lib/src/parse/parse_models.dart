/// 解析管线的数据模型（§7.1-§7.4 管线载荷、§3.3 单边开关、§5.2 行草稿）。
///
/// 设计边界：本库产出的是「草稿」——[ParsedLineDraft] 携带落库所需的
/// 字段口径（分/kcal/置信度/方向/分类），但不构造 core_domain 实体：
/// entries/entry_lines 的实体化、HLC 发戳与事务落库由宿主 feature 层
/// 按既有网关编排（§10.4 分层，复用 CaptureGateway 同款写路径）。
library;

import 'package:core_domain/core_domain.dart' as dom;

import '../cache/ai_parse_cache.dart';

/// 输入通道（§5.6⑭ ai_parses.input_kind）。
enum AiInputKind {
  text('text'),
  voice('voice'),
  photo('photo');

  const AiInputKind(this.wire);

  /// 存储用文本（与 §5.6⑭ 枚举一字不差）。
  final String wire;
}

/// 单边模式（§3.3「仅记钱 / 仅记热量，schema 中对应 lines 只产出一类」；
/// §2.4#2 便宜答案：降低录入心智负担）。
enum ParseMode {
  both('both'),
  moneyOnly('money_only'),
  kcalOnly('kcal_only');

  const ParseMode(this.wire);

  /// 存储用文本；参与 input_hash 信封（同文本不同模式不串缓存）。
  final String wire;
}

/// 解析上下文（随 [ParseInput] 传入，进提示词但不进缓存键——常吃常花
/// 跨日重复输入必须命中，§7.5「input_hash 7 天缓存预计再省 15-25%」）。
class ParseContext {
  const ParseContext({required this.date, this.mode = ParseMode.both});

  /// 本地日历日 `yyyy-MM-dd`（§5.1）：提示词日期锚点；输出不含日期字段，
  /// 事件归属日由调用方在落库时决定。格式校验在管线入口执行
  /// （复用 core_domain `validateCalendarDay`）。
  final String date;

  /// 单边模式（§3.3）。
  final ParseMode mode;
}

/// 解析输入（自由文本：打字原文或语音转写）。
class ParseInput {
  const ParseInput({
    required this.rawText,
    required this.context,
    this.kind = AiInputKind.text,
  });

  /// 用户原文（管线内先做规范化，见 `normalizeParseInput`）。
  final String rawText;

  /// 解析上下文（日期锚点 + 单边模式）。
  final ParseContext context;

  /// 输入通道（ai_parses.input_kind，§5.6⑭）。
  final AiInputKind kind;
}

/// 置信度三色点（§7.3/§2.3：≥0.8 绿 / 0.5-0.8 黄 / <0.5 红；阈值与
/// ui_kit 的 SlimcaConfidenceDot 同一口径——「信任设计一等交互」）。
enum ConfidenceBand {
  green('green'),
  yellow('yellow'),
  red('red');

  const ConfidenceBand(this.wire);

  final String wire;

  /// 按三档阈值归档（§7.3 confidence 行）。
  static ConfidenceBand fromConfidence(double confidence) =>
      confidence >= 0.8
          ? green
          : confidence >= 0.5
          ? yellow
          : red;
}

/// 菜品明细联查来源（§5.2③ ref_source）。
enum FoodRefSource {
  usda('usda'),
  off('off'),
  baidu('baidu'),
  local('local'),
  llm('llm');

  const FoodRefSource(this.wire);

  final String wire;

  /// 解析 wire 文本；未知名抛 ArgumentError（校验器拦截在先）。
  static FoodRefSource fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 FoodRefSource: $value（§5.2③）'),
      );
}

/// 菜品明细草稿（§7.2 lines[].items[] → §5.2③ food_items 逐菜品；
/// ref_source 由联查校准改写，§7.1「食物库联查校准」）。
class ParsedFoodItemDraft {
  const ParsedFoodItemDraft({
    required this.name,
    required this.portionG,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.refSource,
    required this.confidence,
    this.refId,
  });

  /// 菜品名（中文优先，§5.2③）。
  final String name;

  /// 份量（克）：确认卡份量滑杆联动重算的基准（§3.3）。
  final double portionG;

  /// 热量（kcal，INTEGER，§5.1）。
  final int kcal;

  /// 蛋白质（克）。
  final double proteinG;

  /// 碳水（克）。
  final double carbG;

  /// 脂肪（克）。
  final double fatG;

  /// 联查来源（§5.2③；LLM 无把握时为 llm，联查命中后改写）。
  final FoodRefSource refSource;

  /// 来源库条目 id（联查命中后回填；LLM 直报为 null）。
  final String? refId;

  /// 菜品级置信度（§5.2③ NOT NULL；缺省继承行级）。
  final double confidence;
}

/// 产出行草稿（§7.2 lines[] → §5.2② entry_lines 的落库口径）。
class ParsedLineDraft {
  const ParsedLineDraft({
    required this.type,
    required this.direction,
    required this.amount,
    required this.confidence,
    this.ledgerHint,
    this.categoryId,
    this.categoryHint,
    this.categorySuggestNew = false,
    this.currency,
    this.items = const [],
    this.payload,
  }) : assert(amount >= 0, 'amount 非负；方向语义由 direction 表达（§5.2②）'),
       assert(confidence >= 0 && confidence <= 1, '置信度 ∈ [0,1]（§5.2②）');

  /// 行类型（calorie 摄入 / money 金额；§5.2②）。
  final dom.LineType type;

  /// 方向：calorie=in；money 按 expense=out / income=in（§5.2②）。
  final dom.LineDirection direction;

  /// calorie=kcal；money=分（一律 INTEGER，§5.1）。
  final int amount;

  /// AI 置信度（AI 产出行必填，§5.2②；三色点口径见 [ConfidenceBand]）。
  final double confidence;

  /// 置信度三色档（§7.3）。
  ConfidenceBand get band => ConfidenceBand.fromConfidence(confidence);

  /// 账本提示（LLM 输出 ledger_hint，如 'default' → 宿主映射默认账本 id）。
  final String? ledgerHint;

  /// 解析后的分类 id（§7.3 category_hint → category_id；未命中挂「其他」，
  /// 由 [CategoryResolver] 决定，宿主注入实映射）。
  final String? categoryId;

  /// 分类提示原文（确认卡上展示/修改用）。
  final String? categoryHint;

  /// 未命中内置分类 → 建议新建（§7.3「未命中挂『其他』并建议新建」）。
  final bool categorySuggestNew;

  /// 币种（money 行，默认 CNY，§5.2②）。
  final String? currency;

  /// 菜品明细（仅 calorie 行；→ food_items 逐菜品，§5.2③）。
  final List<ParsedFoodItemDraft> items;

  /// 行级明细引用 JSON 载荷（§5.2②：商户/支付方式等；宿主 jsonEncode 落库）。
  final Map<String, Object?>? payload;
}

/// 解析结果密封类型：成功 [ParseSuccess] / 失败 [StructuredFailure]。
///
/// 失败不抛异常而作值返回：§7.4「健壮性即产品体验」——降级是正常业务
/// 分支（UI 切手填表单/入队/提示额度），不是程序错误。
sealed class ParseResult {
  const ParseResult();
}

/// 解析成功（含 entries/lines 草稿与置信度；§7.3 字段映射表全部落点）。
class ParseSuccess extends ParseResult {
  const ParseSuccess({
    required this.title,
    required this.kind,
    required this.lines,
    required this.inputHash,
    required this.record,
    required this.fromCache,
    this.parseNotes,
    this.notes = const [],
  });

  /// 事件标题（§7.3 title → entries.title）。
  final String title;

  /// 事件类型（§7.3 kind → entries.kind；单边模式下按产出推导）。
  final dom.EntryKind kind;

  /// 产出行草稿（§7.3 lines[] → entry_lines + food_items）。
  final List<ParsedLineDraft> lines;

  /// 缓存键（§7.1 input_hash=sha256(规范化输入信封)）。
  final String inputHash;

  /// ai_parses 留痕记录（§5.6⑭：宿主经 [AiParseCache] 已存/可存，
  /// entries.ai_parse_id 引用 [AiParseRecord.id] 溯源）。
  final AiParseRecord record;

  /// 是否命中缓存回放（§7.1：<7 天命中直接复用 raw_output）。
  final bool fromCache;

  /// 解析说明（§7.3 parse_notes → entries.note 追加，可关）。
  final String? parseNotes;

  /// 管线过程中的提示（越界行丢弃、kind 推导等；不阻断成功）。
  final List<String> notes;

  /// 全行最小置信度（=record.confidence，最弱 facet 决定高亮档）。
  double get confidence => record.confidence;
}

/// 解析失败（§7.4 一级降级「原输入保留 → 自动降级手填表单」的载体；
/// 其余三级见 `src/degrade/degrade_hooks.dart` 接口预留）。
class StructuredFailure extends ParseResult {
  const StructuredFailure({
    required this.reason,
    required this.degradeLevel,
    required this.rawInput,
    required this.context,
    required this.attempts,
    this.errors = const [],
    this.lastRawOutput,
    this.cause,
  });

  /// 失败原因分类（§7.1 错误分类 + 内容校验分类）。
  final AiFailureReason reason;

  /// 建议的降级级别（§7.4：本字段指路，UI/宿主执行）。
  final AiDegradeLevel degradeLevel;

  /// 原输入保留（§7.4 一级降级：手填表单预填；二级入队重放）。
  final String rawInput;

  /// 解析上下文（入延迟队列重放时必需，§3.3 离线延迟解析）。
  final ParseContext context;

  /// 管线级尝试次数（适配器内部瞬时重试不计入）。
  final int attempts;

  /// 校验错误清单（人读中文，回喂重试 + UI 提示）。
  final List<String> errors;

  /// 末次原始输出（排查用；§5.6⑭ raw_output 只存成功解析）。
  final String? lastRawOutput;

  /// 底层异常（诊断用）。
  final Object? cause;

  /// 人读摘要（UI toast 用）。
  String get message => errors.isEmpty
      ? 'AI 解析失败（${reason.wire}）'
      : 'AI 解析失败：${errors.first}';
}

/// 失败原因分类（§7.1 校验器/错误分类 + §7.4 降级映射）。
enum AiFailureReason {
  timeout('timeout'),
  network('network'),
  rateLimit('rate_limit'),
  quota('quota'),
  auth('auth'),
  invalidRequest('invalid_request'),
  badResponse('bad_response'),
  invalidJson('invalid_json'),
  validationFailed('validation_failed'),
  emptyResult('empty_result'),
  providerError('provider_error');

  const AiFailureReason(this.wire);

  /// 诊断/埋点用文本。
  final String wire;
}

/// 四级降级（§7.4 降级方案表；级别 1 内建于 [StructuredFailure]，
/// 级别 2-4 的执行接口见 `src/degrade/degrade_hooks.dart`）。
enum AiDegradeLevel {
  /// 一级：超时/解析失败 → 原输入保留 → 自动降级手填表单（内建）。
  manualForm(1),

  /// 二级：断网 → 记录落 draft + 延迟解析队列（接口预留）。
  deferredQueue(2),

  /// 三级：免费额度耗尽 → 额度提示（手填不受限；接口预留）。
  quotaNotice(3),

  /// 四级：供应商单点故障/涨价 → 双供应商 fallback（接口预留）。
  providerFallback(4);

  const AiDegradeLevel(this.level);

  /// 降级级别号（§7.4 表行序）。
  final int level;
}

/// 分类解析的内部载荷：校验器（parse_validator.dart）的产出。
class ValidatedParse {
  const ValidatedParse({
    required this.title,
    required this.kind,
    required this.lines,
    required this.notes,
    this.parseNotes,
  });

  final String title;
  final dom.EntryKind kind;
  final List<ParsedLineDraft> lines;
  final String? parseNotes;
  final List<String> notes;
}
