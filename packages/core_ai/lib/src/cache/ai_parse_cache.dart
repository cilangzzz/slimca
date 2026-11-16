/// input_hash 缓存（§5.6⑭ ai_parses、§7.1「缓存命中（ai_parses <7 天）」）。
///
/// 关键口径：
/// - 缓存键 = sha256(规范化输入信封)（`computeInputHash`，parse_schema.dart）；
/// - 7 天时效判断**不另设时间列**——由 UUIDv7 id 内嵌时间戳得出
///   （id 时间有序，§5.1；core_db `AiParses` 表注同口径）；
/// - 命中且 <7 天 → 直接复用 raw_output 回放（§7.1），不再调 LLM；
/// - prompt_version 不同的历史记录视为未命中（提示词语义已变，回放不安全，
///   §5.6⑭ prompt_version 字段）。
///
/// [AiParseCache] 是抽象接口：core_ai 内置内存实现（测试/预览）与 Drift
/// 实现（drift_ai_parse_cache.dart，直写 core_db 的 ai_parses 表）。
library;

import 'package:core_db/core_db.dart' as cdb;

/// 缓存时效（§5.6⑭/§7.1：<7 天命中复用；§7.5 预计再省 15-25%）。
const Duration kAiParseCacheTtl = Duration(days: 7);

/// 从 UUIDv7 文本提取内嵌的 unix 毫秒时间戳（§5.6⑭ 表注：7 天时效由 id
/// 内嵌时间判定，不另设时间列）。
///
/// RFC 9562 v7 布局：前 48 位 = unix 毫秒（大端），第 13 个 hex 字符的高
/// 半字节 = version 7。与 core_db `generateUuidV7` 的本地实现同构。
/// 非 v7 布局抛 FormatException（坏 id 不静默降级——缓存判时效依赖它）。
int uuidV7TimestampMs(String uuidV7) {
  final hex = uuidV7.replaceAll('-', '');
  if (hex.length != 32 || hex[12] != '7') {
    throw FormatException('非 UUIDv7 布局，无法提取内嵌时间戳: $uuidV7');
  }
  return int.parse(hex.substring(0, 12), radix: 16);
}

/// 一条 ai_parses 留痕记录（§5.6⑭ 字段一一对应；本地件、永不同步）。
class AiParseRecord {
  const AiParseRecord({
    required this.id,
    required this.inputKind,
    required this.inputHash,
    required this.provider,
    required this.model,
    required this.rawOutput,
    required this.latencyMs,
    required this.costMicro,
    required this.confidence,
    required this.promptVersion,
  });

  /// UUIDv7 主键（应用层生成，§5.1）；7 天时效由其内嵌时间判定。
  final String id;

  /// text / voice / photo（[AiInputKind.wire]）。
  final String inputKind;

  /// sha256(规范化输入)=缓存键。
  final String inputHash;

  /// 供应商（可 A/B 对比）。
  final String provider;

  /// 模型名。
  final String model;

  /// 原始结构化输出 JSON（可回放排查，§5.6⑭）。
  final String rawOutput;

  /// 延迟（毫秒）。
  final int latencyMs;

  /// 成本（微元计，可审计；§7.5 口径估算）。
  final int costMicro;

  /// 解析置信度（全行最小值——最弱 facet 决定确认卡高亮档）。
  final double confidence;

  /// 提示词版本（回放兼容性闸门）。
  final String promptVersion;

  /// id 内嵌时间戳（UTC 毫秒）。
  int get createdAtMs => uuidV7TimestampMs(id);

  /// 映射到 core_db 生成的行对象（DriftAiParseCache 落库用）。
  cdb.AiParse toDbRow() => cdb.AiParse(
        id: id,
        inputKind: inputKind,
        inputHash: inputHash,
        provider: provider,
        model: model,
        rawOutput: rawOutput,
        latencyMs: latencyMs,
        cost: costMicro,
        confidence: confidence,
        promptVersion: promptVersion,
      );

  /// 从 core_db 行对象还原。
  factory AiParseRecord.fromDbRow(cdb.AiParse row) => AiParseRecord(
        id: row.id,
        inputKind: row.inputKind,
        inputHash: row.inputHash,
        provider: row.provider,
        model: row.model,
        rawOutput: row.rawOutput,
        latencyMs: row.latencyMs,
        costMicro: row.cost,
        confidence: row.confidence,
        promptVersion: row.promptVersion,
      );

  /// 判断在 [nowMs] 时刻是否仍处时效内（§7.1 命中条件之一）。
  ///
  /// 只做时间判定；提示词版本闸门由管线层负责（parser 知道当前
  /// kPromptVersion，版本不同的历史记录视为未命中、走实时解析）。
  bool isFreshAt(int nowMs, {Duration ttl = kAiParseCacheTtl}) {
    final ageMs = nowMs - createdAtMs;
    // 负年龄（时钟回拨/跨设备导入）一律视为过期——保守不回放。
    return ageMs >= 0 && ageMs < ttl.inMilliseconds;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AiParseRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AiParseRecord($id, hash=${inputHash.substring(0, 8)}…, $provider/$model)';
}

/// ai_parses 缓存抽象（§5.6⑭）。实现约定：
/// - [find] 返回该 input_hash 的**最新**一条记录（任意年龄；时效判断由
///   [AiParseRecord.isFreshAt] 在管线内做——需注入时钟，便于确定性测试）；
/// - [save] 幂等 upsert（主键 id；同 hash 新记录 id 字典序更大、时间更新）。
abstract interface class AiParseCache {
  /// 按缓存键取最新留痕；无记录返回 null。
  Future<AiParseRecord?> find(String inputHash);

  /// 写入/更新留痕。
  Future<void> save(AiParseRecord record);
}

/// 内存实现（测试与预览用；生产走 [DriftAiParseCache]）。
///
/// 每个 hash 只保留最新一条（与 [AiParseCache.find] 的「最新」语义一致）。
class InMemoryAiParseCache implements AiParseCache {
  final Map<String, AiParseRecord> _latestByHash = <String, AiParseRecord>{};

  @override
  Future<AiParseRecord?> find(String inputHash) async =>
      _latestByHash[inputHash];

  @override
  Future<void> save(AiParseRecord record) async {
    final existing = _latestByHash[record.inputHash];
    // 同 hash 已有更新记录（id 时间序更大）则保留旧值——不应发生，防御性。
    if (existing != null && existing.createdAtMs > record.createdAtMs) {
      return;
    }
    _latestByHash[record.inputHash] = record;
  }

  /// 当前缓存的 hash 键集合（测试断言用）。
  Set<String> get cachedHashes => _latestByHash.keys.toSet();

  /// 清空（测试隔离用）。
  void clear() => _latestByHash.clear();
}
