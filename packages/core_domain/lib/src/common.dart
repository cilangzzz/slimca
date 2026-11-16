/// 同步真值表的通用约定（§5.1「通用约定（W1 随 schema v1 冻结）」）。
///
/// 所有同步表共享的公共列在此收敛为一个值对象 [SyncMeta]，
/// 领域实体以组合方式携带，行快照 JSON（sync_outbox.payload，§5.6⑯）
/// 与 Drift 行均按平铺的 snake_case 键名映射，保证三层同构、杜绝漂移（§6.2）。
library;

import 'hlc.dart';

/// 行级 schema 版本当前值（§5.1：schema_ver INTEGER，默认 1）。
/// 只加列前向兼容，v1-v3 冻结期禁破坏性迁移（§6.4）。
const int kCurrentSchemaVer = 1;

/// 本地日历日格式：TEXT `yyyy-MM-dd`（§5.1 日期约定）。
final RegExp kCalendarDayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 校验是否为合法的本地日历日文本。
bool isValidCalendarDay(String value) => kCalendarDayPattern.hasMatch(value);

/// 校验失败即抛 [ArgumentError]（[name] 用于标注字段名）。
void validateCalendarDay(String value, {String name = 'date'}) {
  if (!isValidCalendarDay(value)) {
    throw ArgumentError.value(
      value,
      name,
      '必须为本地日历日 yyyy-MM-dd（§5.1：一切聚合按 date 分组，杜绝 UTC 错日）',
    );
  }
}

/// 由本地 [DateTime] 生成 `yyyy-MM-dd`（零填充定宽，§5.1）。
String formatCalendarDay(DateTime localDateTime) {
  final y = localDateTime.year.toString().padLeft(4, '0');
  final m = localDateTime.month.toString().padLeft(2, '0');
  final d = localDateTime.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 所有同步表的公共列（§5.1 公共列行，W1 冻结）。
///
/// 字段语义逐条对应文档：
/// - [createdAt]/[updatedAt]：UTC 毫秒 INTEGER；
/// - [deletedAt]：软删墓碑，null=未删；双端对齐后保留 90 天物理清理（§5.1 删除行、§6.5 删除行）；
/// - [hlc]：定宽 HLC 编码 TEXT（编码规则见 `Hlc.format`，§6.3），LWW 与同步游标的基石；
/// - [revision]：本地自增起步、同步升级为服务端版本（§5.1）；
/// - [schemaVer]：行级 schema 版本，默认 [kCurrentSchemaVer]（§5.1、§6.4）；
/// - [deviceId]：最后写入设备（§5.1 公共列）；entries 表的 device_id 兼任
///   「创建设备」语义（§5.2①），MVP 单设备写入者即创建者，二者一致。
class SyncMeta {
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final String hlc;
  final int revision;
  final int schemaVer;
  final String deviceId;

  const SyncMeta({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    this.schemaVer = kCurrentSchemaVer,
    required this.deviceId,
  });

  /// 平铺为行快照/DB 行键名（snake_case，与 Drift 列同名，§5.6⑯ payload）。
  Map<String, Object?> toRowJson() => <String, Object?>{
        'created_at': createdAt,
        'updated_at': updatedAt,
        'deleted_at': deletedAt,
        'hlc': hlc,
        'revision': revision,
        'schema_ver': schemaVer,
        'device_id': deviceId,
      };

  /// [toRowJson] 的逆运算；缺失必需键或 [hlc] 不满足 §6.3 定宽编码即抛错
  /// （同步协议字段 W1 冻结，读侧即校验，坏数据不进领域层）。
  /// [hlc] 统一以规范化形式（节点段大写）入库/入域，
  /// 保证 SQLite/Postgres TEXT 比较的字典序=全序不被大小写破坏。
  factory SyncMeta.fromRowJson(Map<String, Object?> json) {
    final hlcText = _requireString(json, 'hlc');
    // 定宽编码校验+规范化（§6.3）：非 13:6:12 结构直接 FormatException。
    final canonicalHlc = Hlc.parse(hlcText).format();
    return SyncMeta(
      createdAt: _requireInt(json, 'created_at'),
      updatedAt: _requireInt(json, 'updated_at'),
      deletedAt: json['deleted_at'] as int?,
      hlc: canonicalHlc,
      revision: _requireInt(json, 'revision'),
      schemaVer: (json['schema_ver'] as int?) ?? kCurrentSchemaVer,
      deviceId: _requireString(json, 'device_id'),
    );
  }

  SyncMeta copyWith({
    int? createdAt,
    int? updatedAt,
    Object? deletedAt = _unchanged,
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
  }) =>
      SyncMeta(
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: identical(deletedAt, _unchanged)
            ? this.deletedAt
            : deletedAt as int?,
        hlc: hlc ?? this.hlc,
        revision: revision ?? this.revision,
        schemaVer: schemaVer ?? this.schemaVer,
        deviceId: deviceId ?? this.deviceId,
      );

  static const Object _unchanged = Object();

  static int _requireInt(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is! int) {
      throw ArgumentError('行快照缺少整数列 "$key"（§5.1 公共列）: $json');
    }
    return v;
  }

  static String _requireString(Map<String, Object?> json, String key) {
    final v = json[key];
    if (v is! String) {
      throw ArgumentError('行快照缺少文本列 "$key"（§5.1 公共列）: $json');
    }
    return v;
  }
}
