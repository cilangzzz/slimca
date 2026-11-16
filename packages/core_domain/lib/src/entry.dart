/// 统一事件模型：事件主干实体与枚举（§2.1-§2.2 叙事、§5.2① entries 表）。
///
/// 「一件事（Entry）」是一切记录的原子：一次输入=一条事件，
/// 何时（date/occurred_at）、何事（title）、怎么来的（source）。
/// 产出的钱/热量维度拆在 [EntryLine]（facet 行，§5.2②/§5.3），
/// 本实体只承载主干——行级 LWW 与 facet 拆行的冲突隔离都发生在行上。
library;

import 'common.dart';

/// 事件类型（§5.2① kind 列）。
enum EntryKind {
  food('food'),
  fitness('fitness'),
  expense('expense'),
  mixed('mixed'),
  note('note');

  const EntryKind(this.wire);

  /// 存储与同步用文本（与 §5.2① 枚举值一字不差）。
  final String wire;

  static EntryKind fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 EntryKind: $value（§5.2①）'),
      );
}

/// 录入来源（§5.2① source 列：写/说/拍/复记/手填，§2.1①「怎么来的」）。
enum EntrySource {
  text('text'),
  voice('voice'),
  photo('photo'),
  receipt('receipt'),
  chip('chip'),
  manual('manual');

  const EntrySource(this.wire);

  final String wire;

  static EntrySource fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 EntrySource: $value（§5.2①）'),
      );
}

/// 事件状态（§5.2① status 列）。
///
/// - draft：AI 字段可被新解析覆盖（§6.5 entries 行）；
/// - confirmed：用户确认落库；
/// - edited：含修正（修正=新增行引用旧行，§2.1②）。
enum EntryStatus {
  draft('draft'),
  confirmed('confirmed'),
  edited('edited');

  const EntryStatus(this.wire);

  final String wire;

  static EntryStatus fromWire(String value) => values.firstWhere(
        (v) => v.wire == value,
        orElse: () => throw ArgumentError('未知 EntryStatus: $value（§5.2①）'),
      );
}

/// 事件主干实体（§5.2① entries）。
///
/// 边界：只覆盖「已发生之事」（§2.1 边界声明）；计划族（待办/健身计划/
/// 存钱目标）是独立实体族，不硬塞进事件模型。
class Entry {
  /// 主键 UUIDv7（§5.1：TEXT 存储，时间有序，同步友好）。
  final String id;

  /// 事件归属日，本地日历日 `yyyy-MM-dd`（可非今天，§5.2①）。
  final String date;

  /// 录入时本地时区偏移（分钟，§5.1 日期行）。
  final int tzOffsetMin;

  /// 事件发生时刻 UTC ms；可早于录入时刻（§5.2①）。
  final int? occurredAt;

  final EntryKind kind;
  final EntrySource source;
  final String title;
  final String? note;
  final EntryStatus status;

  /// → ai_parses.id 溯源（§5.2① ai_parse_id、§5.6⑭）。
  final String? aiParseId;

  /// 公共列（§5.1）。
  final SyncMeta meta;

  Entry({
    required this.id,
    required this.date,
    required this.tzOffsetMin,
    this.occurredAt,
    required this.kind,
    required this.source,
    required this.title,
    this.note,
    required this.status,
    this.aiParseId,
    required this.meta,
  }) {
    // §5.1：date 一律本地日历日文本，聚合按 date 分组，杜绝 UTC 错日。
    validateCalendarDay(date, name: 'date');
  }

  /// 行快照 JSON（sync_outbox.payload 行快照，§5.6⑯；导出复用，§3.4 数据主权）。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'date': date,
        'tz_offset_min': tzOffsetMin,
        'occurred_at': occurredAt,
        'kind': kind.wire,
        'source': source.wire,
        'title': title,
        'note': note,
        'status': status.wire,
        'ai_parse_id': aiParseId,
      }..addAll(meta.toRowJson());

  /// [toJson] 的逆运算。
  factory Entry.fromJson(Map<String, Object?> json) => Entry(
        id: json['id'] as String,
        date: json['date'] as String,
        tzOffsetMin: json['tz_offset_min'] as int,
        occurredAt: json['occurred_at'] as int?,
        kind: EntryKind.fromWire(json['kind'] as String),
        source: EntrySource.fromWire(json['source'] as String),
        title: json['title'] as String,
        note: json['note'] as String?,
        status: EntryStatus.fromWire(json['status'] as String),
        aiParseId: json['ai_parse_id'] as String?,
        meta: SyncMeta.fromRowJson(json),
      );

  /// 不可变更新；可空字段（occurredAt/note/aiParseId）以 Object? 哨兵参数
  /// 区分「不改动」与「置 null」，软删墓碑经 [SyncMeta.copyWith] 改。
  Entry copyWith({
    String? date,
    int? tzOffsetMin,
    Object? occurredAt = _unchanged,
    EntryKind? kind,
    EntrySource? source,
    String? title,
    Object? note = _unchanged,
    EntryStatus? status,
    Object? aiParseId = _unchanged,
    SyncMeta? meta,
  }) =>
      Entry(
        id: id,
        date: date ?? this.date,
        tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
        occurredAt: identical(occurredAt, _unchanged)
            ? this.occurredAt
            : occurredAt as int?,
        kind: kind ?? this.kind,
        source: source ?? this.source,
        title: title ?? this.title,
        note:
            identical(note, _unchanged) ? this.note : note as String?,
        status: status ?? this.status,
        aiParseId: identical(aiParseId, _unchanged)
            ? this.aiParseId
            : aiParseId as String?,
        meta: meta ?? this.meta,
      );

  /// 软删墓碑视图（§5.1 删除行、§6.5「墓碑拒绝复活」）。
  bool get isDeleted => meta.deletedAt != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Entry && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Entry($id, $date, ${kind.wire})';

  static const Object _unchanged = Object();
}
