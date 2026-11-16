/// ai_parses 的 Drift 缓存实现（§5.6⑭：本地件、永不同步）。
///
/// 直读直写 core_db 的 `ai_parses` 表（W1 schema 冻结的 21 张之一）：
/// - find：按 input_hash 取最新一条——UUIDv7 id 时间有序（§5.1），TEXT
///   主键按字典序排序即时间序，`ORDER BY id DESC LIMIT 1` 即最新；
/// - save：`InsertMode.replace` 幂等 upsert（主键 id 冲突时整行替换）。
///
/// 表结构（core_db `AiParses`，§5.6⑭）：无 created_at 列——7 天时效由
/// UUIDv7 id 内嵌时间戳判定（见 ai_parse_cache.dart `uuidV7TimestampMs`）。
library;

import 'package:core_db/core_db.dart' as cdb;
import 'package:drift/drift.dart';

import 'ai_parse_cache.dart';

/// 生产缓存实现（宿主装配：`DriftAiParseCache(appDatabase)`）。
class DriftAiParseCache implements AiParseCache {
  const DriftAiParseCache(this._db);

  final cdb.AppDatabase _db;

  @override
  Future<AiParseRecord?> find(String inputHash) async {
    final query = _db.select(_db.aiParses)
      ..where((t) => t.inputHash.equals(inputHash))
      // UUIDv7 字典序 = 时间序（§5.1）：取最新一条（同 hash 可能存在
      // 多次解析的历史留痕）。
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : AiParseRecord.fromDbRow(row);
  }

  @override
  Future<void> save(AiParseRecord record) {
    return _db.into(_db.aiParses).insert(
          record.toDbRow(),
          mode: InsertMode.replace,
        );
  }
}
