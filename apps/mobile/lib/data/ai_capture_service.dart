/// AI 录入网关（§11.1 W3-4 任务项 2「capture gateway 组合 parser」：
/// 解析 → 确认卡 → entries/entry_lines/ai_parses/corrections 同事务落库）。
///
/// 编排口径（逐条对文档）：
/// - 解析段（§7.1 管线）：规范化 → input_hash → ai_parses <7 天缓存命中
///   直用 raw_output（§7.1）；未命中走 [AiParser]（默认 FakeParser，任务项
///   1）→ §7.1 校验器过闸 → ai_parses 留痕（§5.6⑭）；
/// - 确认段（§7.3 字段映射表、§5.2 facet 拆行）：entries(source 按
///   input_kind、status=confirmed、ai_parse_id 溯源) + calorie/money 行
///   （AI 产出行必带 confidence，§5.2②）；
/// - 修正闭环（§5.6⑮ corrections、§3.3 修正闭环 P0）：确认卡上用户每次
///   修正（kcal/amount/title）落字段级 corrections 审计行（append-only，
///   source=user）；首记不改旧行，审计行即「修正=新增行」底座的落库路径；
/// - 降级（§2.4#3/§7.4）：[AiParserException] 原样上抛，UI 保留原输入转
///   手填表单——本服务不吞错，失败 100% 可见（§11.1 W3-4 验收线）。
///
/// 与手动路径（lib/data/manual_entry_service.dart）的关系：同一仓库抽象
/// （core_domain）+ 同一 HLC 时钟（§6.3 单调发号）；AI 路径的差异只在
/// 「解析 + 留痕 + 置信度 + 审计」，落库语义（outbox 同事务、软删）全由
/// core_db 仓库实现承担（§10.4 分层纪律）。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:core_domain/core_domain.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../ai/ai_parser.dart';
import '../app/providers.dart';
import 'ai_parse_cache.dart';

/// AI 录入网关 provider（§10.4 壳装配：依赖经 provider 注入，测试可整体
/// override 为注入 FakeParser 的实例——禁止真实网络调用）。
final aiCaptureServiceProvider = Provider<AiCaptureService>((ref) {
  return AiCaptureService(
    db: ref.watch(appDatabaseProvider),
    entries: ref.watch(entryRepositoryProvider),
    lines: ref.watch(entryLineRepositoryProvider),
    clock: ref.watch(hlcClockProvider),
    parser: ref.watch(aiParserProvider),
    cache: ref.watch(aiParseCacheProvider),
  );
});

/// 解析段产物：确认卡数据源（UI 只读渲染，确认时回传 [AiConfirmInput]）。
class AiCaptureDraft {
  const AiCaptureDraft({
    required this.result,
    required this.parseId,
    required this.inputHash,
    required this.fromCache,
    required this.inputKind,
  });

  /// 解析结果（缓存命中时=raw_output 回放，§7.1）。
  final AiParseResult result;

  /// ai_parses.id（缓存命中=原留痕行，溯源链不断；§5.6⑭）。
  final String parseId;

  /// 本次输入 hash（规范化后 sha256，§5.6⑭ 缓存键）。
  final String inputHash;

  /// 是否缓存命中（§7.1「<7 天直接复用 raw_output」）。
  final bool fromCache;

  /// 输入通道（W3-4 文本；决定 entries.source，§5.2①）。
  final AiInputKind inputKind;
}

/// 确认入参（确认卡上用户可改 title/kcal/amount，修正 ≤2 次点击 §3.3）。
class AiConfirmInput {
  const AiConfirmInput({
    required this.draft,
    required this.date,
    required this.tzOffsetMin,
    required this.confirmedTitle,
    this.confirmedKcal,
    this.confirmedAmountMinor,
  });

  /// 解析段产物（含 parseId 与解析原值——corrections old_value 口径）。
  final AiCaptureDraft draft;

  /// 归属日 `yyyy-MM-dd`（抽屉从哪天唤起就记到哪天，§3.2）。
  final String date;
  final int tzOffsetMin;

  /// 确认后标题（§5.2① title）。
  final String confirmedTitle;

  /// 确认后摄入 kcal；null=用户清空（不落热量行）。
  final int? confirmedKcal;

  /// 确认后金额（分）；null=用户清空（不落金额行）。
  final int? confirmedAmountMinor;
}

/// AI 录入网关：解析段 + 确认段编排（§11.1 W3-4）。
class AiCaptureService {
  AiCaptureService({
    required db.AppDatabase db,
    required EntryRepository entries,
    required EntryLineRepository lines,
    required HlcClock clock,
    required AiParser parser,
    required AiParseCache cache,
  })  : _db = db,
        _entries = entries,
        _lines = lines,
        _clock = clock,
        _parser = parser,
        _cache = cache;

  final db.AppDatabase _db;
  final EntryRepository _entries;
  final EntryLineRepository _lines;
  final HlcClock _clock;
  final AiParser _parser;
  final AiParseCache _cache;

  static const Uuid _uuid = Uuid();

  // ── 解析段（§7.1 管线 1-4 段：规范化 → hash → 缓存 → adapter+校验）──

  /// 解析为确认卡草稿。
  ///
  /// - 缓存命中：raw_output 回放 + 校验器复闸，不重复计费（§7.1）；
  /// - 未命中：解析 → 校验 → ai_parses 留痕（latency 管线实测）；
  /// - 输入为空/解析失败/校验不过：抛 [AiParserException]（§7.4 降级口）。
  Future<AiCaptureDraft> parseToDraft(
    String rawInput, {
    AiInputKind kind = AiInputKind.text,
  }) async {
    final normalized = normalizeAiInput(rawInput);
    if (normalized.isEmpty) {
      throw const AiParserException('输入为空（§7.1 规范化后无有效内容）');
    }
    final hash = aiInputHash(normalized);

    // ① 缓存命中（§7.1：ai_parses <7 天直接复用 raw_output）。
    final cached = await _cache.findFresh(hash);
    if (cached != null) {
      final replay = AiParseResult.tryDecode(cached.rawOutput);
      if (replay != null) {
        try {
          validateAiParseResult(replay);
          return AiCaptureDraft(
            result: replay,
            parseId: cached.id,
            inputHash: hash,
            fromCache: true,
            inputKind: kind,
          );
        } on AiParserException {
          // 缓存行不合规 → 视为未命中，重走解析（管线自愈，§5.6 自愈纪律）。
        }
      }
    }

    // ② adapter 解析（默认 FakeParser mock；真实 adapter 经 dart-define
    //    切换，见 lib/ai/ai_parser_factory.dart）。latency 由管线实测
    //    （§5.6⑭ latency_ms，与 adapter 自报解耦）。
    final stopwatch = Stopwatch()..start();
    final result = await _parser.parse(
      AiParseRequest(inputKind: kind, input: normalized),
    );
    final latencyMs = stopwatch.elapsedMilliseconds;

    // ③ 校验器（§7.1）：越界/缺字段一律拒收 → 调用方降级手填。
    validateAiParseResult(result);

    // ④ 留痕（§5.6⑭）：raw_output=canonical JSON，可回放排查。
    final parseId = await _cache.record(
      inputKind: kind.wire,
      inputHash: hash,
      provider: result.provider,
      model: result.model,
      rawOutput: jsonEncode(result.toJson()),
      latencyMs: latencyMs,
      cost: result.costMicro,
      confidence: result.confidence,
      promptVersion: result.promptVersion,
    );
    return AiCaptureDraft(
      result: result,
      parseId: parseId,
      inputHash: hash,
      fromCache: false,
      inputKind: kind,
    );
  }

  // ── 确认段（§7.3 字段映射表 + §5.6⑮ corrections 修正闭环）────────

  /// 确认落库：entries + facet 行 + corrections 审计行同事务（§5.3 拆行、
  /// §6.2 写路径纪律——业务行 + outbox 同事务由仓库实现保证）。
  ///
  /// 修正审计口径（§5.6⑮ 字段级 old/new、append-only、source=user）：
  /// - 确认值与解析原值不同 → 落审计行（kcal/amount 挂行 id，title 挂主干）；
  /// - 解析有值而用户清空 → 审计 new_value 空串（修正=去掉该产出）；
  /// - 未改动 → 不落（确认 ≠ 修正）。
  Future<String> confirmAiCapture(AiConfirmInput input) async {
    final parsed = input.draft.result;

    // 确认值二次过闸（§7.1 校验器同样约束用户回改值）。
    final kcal = input.confirmedKcal;
    if (kcal != null && (kcal < 0 || kcal > 5000)) {
      throw ArgumentError.value(
        kcal, 'confirmedKcal', 'kcal 必须落在 [0,5000]（§7.1 校验器）',
      );
    }
    final amountMinor = input.confirmedAmountMinor;
    if (amountMinor != null && amountMinor <= 0) {
      throw ArgumentError.value(
        amountMinor, 'confirmedAmountMinor', '金额必须为正数（分，§7.1 校验器）',
      );
    }
    final title = input.confirmedTitle.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(title, 'confirmedTitle', 'title 必填（§5.2①）');
    }

    // 解析原值（corrections old_value 取自解析结果，§7.3 用户修正 ↔ 审计）。
    final parsedKcal = parsed.firstKcalLine?.amount;
    final parsedAmount = parsed.firstMoneyLine?.amount;
    final parsedTitle = parsed.title;

    final nowMs = _clock.wallClock();
    final occurredAt = nowMs;
    final entry = Entry(
      id: _uuid.v7(),
      date: input.date, // 构造器内做 §5.1 日历日校验
      tzOffsetMin: input.tzOffsetMin,
      occurredAt: occurredAt,
      kind: _deriveKind(kcal, amountMinor),
      source: _sourceOf(input.draft.inputKind),
      title: title,
      note: parsed.parseNotes, // §7.3：parse_notes → entries.note 追加
      status: EntryStatus.confirmed,
      aiParseId: input.draft.parseId, // §5.2① ai_parse_id 溯源（§5.6⑭）
      meta: _stampMeta(),
    );

    final kcalLedgerId = await _builtinLedgerId('kcal');
    final moneyLedgerId = await _builtinLedgerId('money');

    final kcalLine = (kcal != null && kcal > 0)
        ? EntryLine(
            id: _uuid.v7(),
            entryId: entry.id,
            type: LineType.calorie,
            amount: kcal,
            direction: LineDirection.income, // calorie=in（§5.2②）
            ledgerId: kcalLedgerId,
            // AI 产出行必带置信度（§5.2②）；行缺省回落整体置信度。
            confidence: parsed.firstKcalLine?.confidence ?? parsed.confidence,
            payload: _caloriePayload(parsed),
            status: LineStatus.active,
            meta: _stampMeta(),
          )
        : null;

    final moneyLine = (amountMinor != null && amountMinor > 0)
        ? EntryLine(
            id: _uuid.v7(),
            entryId: entry.id,
            type: LineType.money,
            amount: amountMinor,
            direction: LineDirection.outcome, // W3-4 文本路径只出账（§5.2②）
            ledgerId: moneyLedgerId,
            currency: parsed.firstMoneyLine?.currency ?? 'CNY',
            confidence:
                parsed.firstMoneyLine?.confidence ?? parsed.confidence,
            payload: _moneyPayload(parsed),
            status: LineStatus.active,
            meta: _stampMeta(),
          )
        : null;

    await _db.transaction(() async {
      await _entries.upsert(entry);
      if (kcalLine != null) {
        await _lines.upsert(kcalLine);
      }
      if (moneyLine != null) {
        await _lines.upsert(moneyLine);
      }

      // corrections 审计（§5.6⑮ append-only；确认卡上用户修正逐字段落行）。
      if (parsedKcal != null) {
        final newValue = (kcal != null && kcal > 0) ? '$kcal' : '';
        if (newValue != '$parsedKcal') {
          await _insertCorrectionAudit(
            entryId: entry.id,
            lineId: kcalLine?.id,
            field: 'kcal',
            oldValue: '$parsedKcal',
            newValue: newValue,
            createdAt: nowMs,
          );
        }
      }
      if (parsedAmount != null) {
        final newValue = (amountMinor != null && amountMinor > 0)
            ? '$amountMinor'
            : '';
        if (newValue != '$parsedAmount') {
          await _insertCorrectionAudit(
            entryId: entry.id,
            lineId: moneyLine?.id,
            field: 'amount',
            oldValue: '$parsedAmount',
            newValue: newValue,
            createdAt: nowMs,
          );
        }
      }
      if (parsedTitle.isNotEmpty && parsedTitle != title) {
        await _insertCorrectionAudit(
          entryId: entry.id,
          lineId: null, // 主干字段修正 line_id=NULL（§5.6⑮）
          field: 'title',
          oldValue: parsedTitle,
          newValue: title,
          createdAt: nowMs,
        );
      }
    });
    return entry.id;
  }

  // ── 内部装配（与 manual_entry_service 同口径，§5.1/§6.3）─────────

  /// kind 推导（§5.2①：确认值定 kind，解析 kind_hint 仅展示）。
  EntryKind _deriveKind(int? kcal, int? amountMinor) {
    final hasKcal = kcal != null && kcal > 0;
    final hasMoney = amountMinor != null && amountMinor > 0;
    if (hasKcal && hasMoney) return EntryKind.mixed;
    if (hasKcal) return EntryKind.food;
    if (hasMoney) return EntryKind.expense;
    return EntryKind.note;
  }

  /// 输入通道 → 事件来源（§5.2① source：写/说/拍）。
  EntrySource _sourceOf(AiInputKind kind) => switch (kind) {
        AiInputKind.text => EntrySource.text,
        AiInputKind.voice => EntrySource.voice,
        AiInputKind.photo => EntrySource.photo,
      };

  /// 新行公共列（§5.1）：HLC 由应用级单例时钟发号（§6.3 单调）、
  /// revision 本地自增起步=1。
  SyncMeta _stampMeta() {
    final nowMs = _clock.wallClock();
    return SyncMeta(
      createdAt: nowMs,
      updatedAt: nowMs,
      hlc: _clock.now().format(),
      revision: 1,
      deviceId: _clock.deviceId,
    );
  }

  /// corrections 审计行（§5.6⑮：id/entry_id/line_id/field/old/new/source
  /// + §5.1 公共列；entry_id/line_id 仅逻辑引用不建外键，审计永可插入）。
  Future<void> _insertCorrectionAudit({
    required String entryId,
    required String? lineId,
    required String field,
    required String oldValue,
    required String newValue,
    required int createdAt,
  }) async {
    await _db.into(_db.corrections).insert(
          db.Correction(
            id: _uuid.v7(),
            entryId: entryId,
            lineId: lineId,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            source: 'user',
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: null,
            hlc: _clock.now().format(),
            revision: 1,
            schemaVer: kCurrentSchemaVer,
            deviceId: _clock.deviceId,
          ),
        );
  }

  /// calorie 行 payload：菜品明细摘要 JSON（§5.2② payload=菜品数组摘要）。
  String? _caloriePayload(AiParseResult parsed) {
    final items = parsed.firstKcalLine?.items ?? const [];
    if (items.isEmpty) return null;
    return jsonEncode([for (final item in items) item.toJson()]);
  }

  /// money 行 payload：商户等引用（§5.2② payload=商户/支付方式）。
  String? _moneyPayload(AiParseResult parsed) {
    final merchant = parsed.firstMoneyLine?.merchant;
    if (merchant == null || merchant.isEmpty) return null;
    return jsonEncode(<String, Object?>{'merchant': merchant});
  }

  /// 内置账本 id（§5.4：money=默认账本、kcal=系统内置热量账本；W2 恒默认）。
  Future<String?> _builtinLedgerId(String kind) async {
    final rows = await (_db.select(_db.ledgers)
          ..where((t) => t.kind.equals(kind) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
    return rows.isEmpty ? null : rows.first.id;
  }
}
