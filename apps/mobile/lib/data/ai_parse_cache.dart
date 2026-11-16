/// ai_parses 缓存 DAO（§5.6⑭ ai_parses、§7.1 缓存命中、§3.3 input_hash 缓存 P0）。
///
/// 注（任务项 3「input_hash 缓存注入」）：core_db 的 schema v1 已冻结
/// ai_parses 表但无专用 DAO，本 DAO 挂壳内 data 层（ai_parses 是本地件、
/// 永不同步 §5.1 表分组）；core_db 后续内聚 DAO 时上移（§10.4 分层）。
///
/// 缓存口径（§7.1 管线第 2 段）：
/// - input_hash = sha256(规范化输入) = 缓存键；
/// - 命中且 <7 天 → 直接复用 raw_output（§7.1「缓存命中直接复用」）；
/// - 7 天时效由 UUIDv7 id 内嵌时间戳判定（id 时间有序，§5.6⑭ 表注释
///   「不另设时间列」），无需额外列。
library;

import 'dart:convert';

import 'package:core_db/core_db.dart' as db;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show OrderingTerm;

/// 输入规范化（§7.1「规范化 + input_hash」）：连续空白（含全角空格/换行）
/// 折叠为单空格、去首尾——同一句话的多打空格/换行视为同一输入。
String normalizeAiInput(String raw) =>
    raw.replaceAll(RegExp(r'[\s　]+'), ' ').trim();

/// input_hash（§5.6⑭：sha256(规范化输入)）。
String aiInputHash(String normalizedInput) =>
    sha256.convert(utf8.encode(normalizedInput)).toString();

/// 从 UUIDv7 解出内嵌毫秒时间戳（前 48 bit，§5.6⑭ 7 天时效判定依据）；
/// 非 v7 形态（损坏 id）返回 null。
int? uuidV7TimestampMs(String id) {
  final hex = id.replaceAll('-', '');
  if (hex.length < 12) return null;
  final ms = int.tryParse(hex.substring(0, 12), radix: 16);
  if (ms == null || ms <= 0) return null;
  return ms;
}

/// ai_parses 缓存 DAO：解析留痕写入 + input_hash 7 天查找（§5.6⑭）。
class AiParseCache {
  AiParseCache(this._db);

  final db.AppDatabase _db;

  /// §7.1：缓存命中窗口 7 天。
  static const Duration defaultMaxAge = Duration(days: 7);

  /// 缓存查找（§7.1）：同 hash 取最新一行（UUIDv7 id 时间有序）；最新行
  /// 在 [maxAge] 内返回；过期/时钟异常/损坏 id 视为未命中（重解析自愈）。
  Future<db.AiParse?> findFresh(
    String inputHash, {
    Duration maxAge = defaultMaxAge,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final rows = await (_db.select(_db.aiParses)
          ..where((t) => t.inputHash.equals(inputHash))
          ..orderBy([(t) => OrderingTerm.desc(t.id)]))
        .get();
    for (final row in rows) {
      final stampedMs = uuidV7TimestampMs(row.id);
      if (stampedMs == null) continue; // 损坏 id：跳过看次新行
      final ageMs = now - stampedMs;
      final isFresh = ageMs >= 0 && ageMs <= maxAge.inMilliseconds;
      return isFresh ? row : null; // id 时间有序：最新行过期 ⇒ 全部过期
    }
    return null;
  }

  /// 解析留痕（§5.6⑭ 全字段）：raw_output 存 canonical JSON（可回放排查），
  /// 返回 ai_parses.id（entries.ai_parse_id 溯源引用）。
  Future<String> record({
    required String inputKind,
    required String inputHash,
    required String provider,
    required String model,
    required String rawOutput,
    required int latencyMs,
    required int cost,
    required double confidence,
    required String promptVersion,
  }) async {
    final id = db.generateUuidV7();
    await _db.into(_db.aiParses).insert(
          db.AiParse(
            id: id,
            inputKind: inputKind,
            inputHash: inputHash,
            provider: provider,
            model: model,
            rawOutput: rawOutput,
            latencyMs: latencyMs,
            cost: cost,
            confidence: confidence,
            promptVersion: promptVersion,
          ),
        );
    return id;
  }
}
