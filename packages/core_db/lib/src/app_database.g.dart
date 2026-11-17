// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $EntriesTable extends Entries with TableInfo<$EntriesTable, Entry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tzOffsetMinMeta = const VerificationMeta(
    'tzOffsetMin',
  );
  @override
  late final GeneratedColumn<int> tzOffsetMin = GeneratedColumn<int>(
    'tz_offset_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<int> occurredAt = GeneratedColumn<int>(
    'occurred_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aiParseIdMeta = const VerificationMeta(
    'aiParseId',
  );
  @override
  late final GeneratedColumn<String> aiParseId = GeneratedColumn<String>(
    'ai_parse_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    date,
    tzOffsetMin,
    occurredAt,
    kind,
    source,
    title,
    note,
    status,
    aiParseId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Entry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('tz_offset_min')) {
      context.handle(
        _tzOffsetMinMeta,
        tzOffsetMin.isAcceptableOrUnknown(
          data['tz_offset_min']!,
          _tzOffsetMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tzOffsetMinMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('ai_parse_id')) {
      context.handle(
        _aiParseIdMeta,
        aiParseId.isAcceptableOrUnknown(data['ai_parse_id']!, _aiParseIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Entry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Entry(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      tzOffsetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tz_offset_min'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}occurred_at'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      aiParseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_parse_id'],
      ),
    );
  }

  @override
  $EntriesTable createAlias(String alias) {
    return $EntriesTable(attachedDatabase, alias);
  }
}

class Entry extends DataClass implements Insertable<Entry> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键，TEXT 存储（§5.1）；由应用层生成（时间有序、同步友好），
  /// 数据库层不设默认值。
  final String id;

  /// 本地日历日 `yyyy-MM-dd`：事件归属日（可非今天）；一切聚合按 date 分组，
  /// 杜绝 UTC 错日（§5.1 日期约定）。
  final String date;

  /// 录入时本地时区偏移（分钟），与 [date] 配对。
  final int tzOffsetMin;

  /// 事件发生时刻 UTC ms（可早于录入时刻）。
  final int? occurredAt;

  /// food / fitness / expense / mixed（钱+热量）/ note。
  final String kind;

  /// text / voice / photo / receipt / chip（复记）/ manual。
  final String source;

  /// 一句话描述（AI 生成或用户输入）。
  final String title;

  /// 备注。
  final String? note;

  /// draft（AI 字段可被新解析覆盖）/ confirmed / edited（含修正）。
  final String status;

  /// → ai_parses.id 溯源。注意：ai_parses 是本地件、永不同步（§5.6），
  /// 因此这里只做逻辑引用、不建数据库外键——否则其他设备 pull 回的
  /// entries 行会因本地无对应 ai_parses 而无法插入（§6.2 per-table 拉取）。
  final String? aiParseId;
  const Entry({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
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
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['tz_offset_min'] = Variable<int>(tzOffsetMin);
    if (!nullToAbsent || occurredAt != null) {
      map['occurred_at'] = Variable<int>(occurredAt);
    }
    map['kind'] = Variable<String>(kind);
    map['source'] = Variable<String>(source);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || aiParseId != null) {
      map['ai_parse_id'] = Variable<String>(aiParseId);
    }
    return map;
  }

  EntriesCompanion toCompanion(bool nullToAbsent) {
    return EntriesCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      date: Value(date),
      tzOffsetMin: Value(tzOffsetMin),
      occurredAt: occurredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(occurredAt),
      kind: Value(kind),
      source: Value(source),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      status: Value(status),
      aiParseId: aiParseId == null && nullToAbsent
          ? const Value.absent()
          : Value(aiParseId),
    );
  }

  factory Entry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Entry(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      tzOffsetMin: serializer.fromJson<int>(json['tzOffsetMin']),
      occurredAt: serializer.fromJson<int?>(json['occurredAt']),
      kind: serializer.fromJson<String>(json['kind']),
      source: serializer.fromJson<String>(json['source']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      status: serializer.fromJson<String>(json['status']),
      aiParseId: serializer.fromJson<String?>(json['aiParseId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'tzOffsetMin': serializer.toJson<int>(tzOffsetMin),
      'occurredAt': serializer.toJson<int?>(occurredAt),
      'kind': serializer.toJson<String>(kind),
      'source': serializer.toJson<String>(source),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'status': serializer.toJson<String>(status),
      'aiParseId': serializer.toJson<String?>(aiParseId),
    };
  }

  Entry copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? date,
    int? tzOffsetMin,
    Value<int?> occurredAt = const Value.absent(),
    String? kind,
    String? source,
    String? title,
    Value<String?> note = const Value.absent(),
    String? status,
    Value<String?> aiParseId = const Value.absent(),
  }) => Entry(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    date: date ?? this.date,
    tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
    occurredAt: occurredAt.present ? occurredAt.value : this.occurredAt,
    kind: kind ?? this.kind,
    source: source ?? this.source,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    status: status ?? this.status,
    aiParseId: aiParseId.present ? aiParseId.value : this.aiParseId,
  );
  Entry copyWithCompanion(EntriesCompanion data) {
    return Entry(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      tzOffsetMin: data.tzOffsetMin.present
          ? data.tzOffsetMin.value
          : this.tzOffsetMin,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      source: data.source.present ? data.source.value : this.source,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      status: data.status.present ? data.status.value : this.status,
      aiParseId: data.aiParseId.present ? data.aiParseId.value : this.aiParseId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Entry(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('kind: $kind, ')
          ..write('source: $source, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('aiParseId: $aiParseId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    date,
    tzOffsetMin,
    occurredAt,
    kind,
    source,
    title,
    note,
    status,
    aiParseId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Entry &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.date == this.date &&
          other.tzOffsetMin == this.tzOffsetMin &&
          other.occurredAt == this.occurredAt &&
          other.kind == this.kind &&
          other.source == this.source &&
          other.title == this.title &&
          other.note == this.note &&
          other.status == this.status &&
          other.aiParseId == this.aiParseId);
}

class EntriesCompanion extends UpdateCompanion<Entry> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> date;
  final Value<int> tzOffsetMin;
  final Value<int?> occurredAt;
  final Value<String> kind;
  final Value<String> source;
  final Value<String> title;
  final Value<String?> note;
  final Value<String> status;
  final Value<String?> aiParseId;
  final Value<int> rowid;
  const EntriesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.tzOffsetMin = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.source = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.status = const Value.absent(),
    this.aiParseId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntriesCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String date,
    required int tzOffsetMin,
    this.occurredAt = const Value.absent(),
    required String kind,
    required String source,
    required String title,
    this.note = const Value.absent(),
    required String status,
    this.aiParseId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       date = Value(date),
       tzOffsetMin = Value(tzOffsetMin),
       kind = Value(kind),
       source = Value(source),
       title = Value(title),
       status = Value(status);
  static Insertable<Entry> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? date,
    Expression<int>? tzOffsetMin,
    Expression<int>? occurredAt,
    Expression<String>? kind,
    Expression<String>? source,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? status,
    Expression<String>? aiParseId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (tzOffsetMin != null) 'tz_offset_min': tzOffsetMin,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (kind != null) 'kind': kind,
      if (source != null) 'source': source,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (status != null) 'status': status,
      if (aiParseId != null) 'ai_parse_id': aiParseId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntriesCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? date,
    Value<int>? tzOffsetMin,
    Value<int?>? occurredAt,
    Value<String>? kind,
    Value<String>? source,
    Value<String>? title,
    Value<String?>? note,
    Value<String>? status,
    Value<String?>? aiParseId,
    Value<int>? rowid,
  }) {
    return EntriesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      date: date ?? this.date,
      tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
      occurredAt: occurredAt ?? this.occurredAt,
      kind: kind ?? this.kind,
      source: source ?? this.source,
      title: title ?? this.title,
      note: note ?? this.note,
      status: status ?? this.status,
      aiParseId: aiParseId ?? this.aiParseId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (tzOffsetMin.present) {
      map['tz_offset_min'] = Variable<int>(tzOffsetMin.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<int>(occurredAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (aiParseId.present) {
      map['ai_parse_id'] = Variable<String>(aiParseId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntriesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('kind: $kind, ')
          ..write('source: $source, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('aiParseId: $aiParseId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EntryLinesTable extends EntryLines
    with TableInfo<$EntryLinesTable, EntryLine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EntryLinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES entries (id)',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correctionOfMeta = const VerificationMeta(
    'correctionOf',
  );
  @override
  late final GeneratedColumn<String> correctionOf = GeneratedColumn<String>(
    'correction_of',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    type,
    amount,
    direction,
    ledgerId,
    categoryId,
    currency,
    confidence,
    payload,
    correctionOf,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'entry_lines';
  @override
  VerificationContext validateIntegrity(
    Insertable<EntryLine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('correction_of')) {
      context.handle(
        _correctionOfMeta,
        correctionOf.isAcceptableOrUnknown(
          data['correction_of']!,
          _correctionOfMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EntryLine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EntryLine(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      correctionOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correction_of'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $EntryLinesTable createAlias(String alias) {
    return $EntryLinesTable(attachedDatabase, alias);
  }
}

class EntryLine extends DataClass implements Insertable<EntryLine> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// → entries.id。文档明确标注 FK、软删不级联物理删：默认 NO ACTION
  /// （不级联），物理 GC 时先删子行再删墓碑（§5.1）。
  /// 同步 pull 需保证父表行先于子表行落库（per-table 游标按依赖序处理，§6.2）。
  final String entryId;

  /// calorie（摄入）/ burn（运动消耗）/ money（金额）。
  final String type;

  /// calorie/burn=kcal；money=分（正数）。金额一律最小货币单位、kcal 一律
  /// INTEGER（§5.1）。
  final int amount;

  /// in / out（calorie=in；burn=out；money 按 expense=out / income=in）。
  final String direction;

  /// money 行必填（默认账本）；kcal 行归集到内置 kcal 账本（§5.4 ledgers.kind）。
  /// 仅逻辑引用，不建外键：账本可能尚在 pull 队列中。
  final String? ledgerId;

  /// money 行=消费分类；calorie 行可挂餐饮子类（面食等）。
  final String? categoryId;

  /// money 行，默认 CNY。
  final String? currency;

  /// AI 置信度 0-1（AI 产出行必填；人工行 NULL）。
  final double? confidence;

  /// 行级明细引用 JSON：商户/支付方式/MET 参数/菜品数组摘要。
  /// burn 行 payload 记 session_id（§5.5 fitness_sessions.entry_id 说明）。
  final String? payload;

  /// 指向被修正旧行 id；修正=新增行，旧行 status→superseded（§5.2/§6.5）。
  final String? correctionOf;

  /// active / superseded（被修正）/ void（作废）。
  final String status;
  const EntryLine({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.entryId,
    required this.type,
    required this.amount,
    required this.direction,
    this.ledgerId,
    this.categoryId,
    this.currency,
    this.confidence,
    this.payload,
    this.correctionOf,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<int>(amount);
    map['direction'] = Variable<String>(direction);
    if (!nullToAbsent || ledgerId != null) {
      map['ledger_id'] = Variable<String>(ledgerId);
    }
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    if (!nullToAbsent || currency != null) {
      map['currency'] = Variable<String>(currency);
    }
    if (!nullToAbsent || confidence != null) {
      map['confidence'] = Variable<double>(confidence);
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    if (!nullToAbsent || correctionOf != null) {
      map['correction_of'] = Variable<String>(correctionOf);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  EntryLinesCompanion toCompanion(bool nullToAbsent) {
    return EntryLinesCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      entryId: Value(entryId),
      type: Value(type),
      amount: Value(amount),
      direction: Value(direction),
      ledgerId: ledgerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ledgerId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      currency: currency == null && nullToAbsent
          ? const Value.absent()
          : Value(currency),
      confidence: confidence == null && nullToAbsent
          ? const Value.absent()
          : Value(confidence),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
      correctionOf: correctionOf == null && nullToAbsent
          ? const Value.absent()
          : Value(correctionOf),
      status: Value(status),
    );
  }

  factory EntryLine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EntryLine(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<int>(json['amount']),
      direction: serializer.fromJson<String>(json['direction']),
      ledgerId: serializer.fromJson<String?>(json['ledgerId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      currency: serializer.fromJson<String?>(json['currency']),
      confidence: serializer.fromJson<double?>(json['confidence']),
      payload: serializer.fromJson<String?>(json['payload']),
      correctionOf: serializer.fromJson<String?>(json['correctionOf']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<int>(amount),
      'direction': serializer.toJson<String>(direction),
      'ledgerId': serializer.toJson<String?>(ledgerId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'currency': serializer.toJson<String?>(currency),
      'confidence': serializer.toJson<double?>(confidence),
      'payload': serializer.toJson<String?>(payload),
      'correctionOf': serializer.toJson<String?>(correctionOf),
      'status': serializer.toJson<String>(status),
    };
  }

  EntryLine copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? entryId,
    String? type,
    int? amount,
    String? direction,
    Value<String?> ledgerId = const Value.absent(),
    Value<String?> categoryId = const Value.absent(),
    Value<String?> currency = const Value.absent(),
    Value<double?> confidence = const Value.absent(),
    Value<String?> payload = const Value.absent(),
    Value<String?> correctionOf = const Value.absent(),
    String? status,
  }) => EntryLine(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    type: type ?? this.type,
    amount: amount ?? this.amount,
    direction: direction ?? this.direction,
    ledgerId: ledgerId.present ? ledgerId.value : this.ledgerId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    currency: currency.present ? currency.value : this.currency,
    confidence: confidence.present ? confidence.value : this.confidence,
    payload: payload.present ? payload.value : this.payload,
    correctionOf: correctionOf.present ? correctionOf.value : this.correctionOf,
    status: status ?? this.status,
  );
  EntryLine copyWithCompanion(EntryLinesCompanion data) {
    return EntryLine(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      direction: data.direction.present ? data.direction.value : this.direction,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      currency: data.currency.present ? data.currency.value : this.currency,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      payload: data.payload.present ? data.payload.value : this.payload,
      correctionOf: data.correctionOf.present
          ? data.correctionOf.value
          : this.correctionOf,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EntryLine(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('direction: $direction, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('currency: $currency, ')
          ..write('confidence: $confidence, ')
          ..write('payload: $payload, ')
          ..write('correctionOf: $correctionOf, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    type,
    amount,
    direction,
    ledgerId,
    categoryId,
    currency,
    confidence,
    payload,
    correctionOf,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EntryLine &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.direction == this.direction &&
          other.ledgerId == this.ledgerId &&
          other.categoryId == this.categoryId &&
          other.currency == this.currency &&
          other.confidence == this.confidence &&
          other.payload == this.payload &&
          other.correctionOf == this.correctionOf &&
          other.status == this.status);
}

class EntryLinesCompanion extends UpdateCompanion<EntryLine> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> type;
  final Value<int> amount;
  final Value<String> direction;
  final Value<String?> ledgerId;
  final Value<String?> categoryId;
  final Value<String?> currency;
  final Value<double?> confidence;
  final Value<String?> payload;
  final Value<String?> correctionOf;
  final Value<String> status;
  final Value<int> rowid;
  const EntryLinesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.direction = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.currency = const Value.absent(),
    this.confidence = const Value.absent(),
    this.payload = const Value.absent(),
    this.correctionOf = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EntryLinesCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String entryId,
    required String type,
    required int amount,
    required String direction,
    this.ledgerId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.currency = const Value.absent(),
    this.confidence = const Value.absent(),
    this.payload = const Value.absent(),
    this.correctionOf = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       entryId = Value(entryId),
       type = Value(type),
       amount = Value(amount),
       direction = Value(direction),
       status = Value(status);
  static Insertable<EntryLine> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? type,
    Expression<int>? amount,
    Expression<String>? direction,
    Expression<String>? ledgerId,
    Expression<String>? categoryId,
    Expression<String>? currency,
    Expression<double>? confidence,
    Expression<String>? payload,
    Expression<String>? correctionOf,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (direction != null) 'direction': direction,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (categoryId != null) 'category_id': categoryId,
      if (currency != null) 'currency': currency,
      if (confidence != null) 'confidence': confidence,
      if (payload != null) 'payload': payload,
      if (correctionOf != null) 'correction_of': correctionOf,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EntryLinesCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? type,
    Value<int>? amount,
    Value<String>? direction,
    Value<String?>? ledgerId,
    Value<String?>? categoryId,
    Value<String?>? currency,
    Value<double?>? confidence,
    Value<String?>? payload,
    Value<String?>? correctionOf,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return EntryLinesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      direction: direction ?? this.direction,
      ledgerId: ledgerId ?? this.ledgerId,
      categoryId: categoryId ?? this.categoryId,
      currency: currency ?? this.currency,
      confidence: confidence ?? this.confidence,
      payload: payload ?? this.payload,
      correctionOf: correctionOf ?? this.correctionOf,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (correctionOf.present) {
      map['correction_of'] = Variable<String>(correctionOf.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EntryLinesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('direction: $direction, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('currency: $currency, ')
          ..write('confidence: $confidence, ')
          ..write('payload: $payload, ')
          ..write('correctionOf: $correctionOf, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FoodItemsTable extends FoodItems
    with TableInfo<$FoodItemsTable, FoodItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoodItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portionGMeta = const VerificationMeta(
    'portionG',
  );
  @override
  late final GeneratedColumn<double> portionG = GeneratedColumn<double>(
    'portion_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalMeta = const VerificationMeta('kcal');
  @override
  late final GeneratedColumn<int> kcal = GeneratedColumn<int>(
    'kcal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _proteinGMeta = const VerificationMeta(
    'proteinG',
  );
  @override
  late final GeneratedColumn<double> proteinG = GeneratedColumn<double>(
    'protein_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carbGMeta = const VerificationMeta('carbG');
  @override
  late final GeneratedColumn<double> carbG = GeneratedColumn<double>(
    'carb_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fatGMeta = const VerificationMeta('fatG');
  @override
  late final GeneratedColumn<double> fatG = GeneratedColumn<double>(
    'fat_g',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refSourceMeta = const VerificationMeta(
    'refSource',
  );
  @override
  late final GeneratedColumn<String> refSource = GeneratedColumn<String>(
    'ref_source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userAdjustedMeta = const VerificationMeta(
    'userAdjusted',
  );
  @override
  late final GeneratedColumn<bool> userAdjusted = GeneratedColumn<bool>(
    'user_adjusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("user_adjusted" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    lineId,
    name,
    portionG,
    kcal,
    proteinG,
    carbG,
    fatG,
    refSource,
    refId,
    confidence,
    userAdjusted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'food_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<FoodItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lineIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('portion_g')) {
      context.handle(
        _portionGMeta,
        portionG.isAcceptableOrUnknown(data['portion_g']!, _portionGMeta),
      );
    } else if (isInserting) {
      context.missing(_portionGMeta);
    }
    if (data.containsKey('kcal')) {
      context.handle(
        _kcalMeta,
        kcal.isAcceptableOrUnknown(data['kcal']!, _kcalMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalMeta);
    }
    if (data.containsKey('protein_g')) {
      context.handle(
        _proteinGMeta,
        proteinG.isAcceptableOrUnknown(data['protein_g']!, _proteinGMeta),
      );
    } else if (isInserting) {
      context.missing(_proteinGMeta);
    }
    if (data.containsKey('carb_g')) {
      context.handle(
        _carbGMeta,
        carbG.isAcceptableOrUnknown(data['carb_g']!, _carbGMeta),
      );
    } else if (isInserting) {
      context.missing(_carbGMeta);
    }
    if (data.containsKey('fat_g')) {
      context.handle(
        _fatGMeta,
        fatG.isAcceptableOrUnknown(data['fat_g']!, _fatGMeta),
      );
    } else if (isInserting) {
      context.missing(_fatGMeta);
    }
    if (data.containsKey('ref_source')) {
      context.handle(
        _refSourceMeta,
        refSource.isAcceptableOrUnknown(data['ref_source']!, _refSourceMeta),
      );
    } else if (isInserting) {
      context.missing(_refSourceMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('user_adjusted')) {
      context.handle(
        _userAdjustedMeta,
        userAdjusted.isAcceptableOrUnknown(
          data['user_adjusted']!,
          _userAdjustedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_userAdjustedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoodItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoodItem(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      portionG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}portion_g'],
      )!,
      kcal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kcal'],
      )!,
      proteinG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}protein_g'],
      )!,
      carbG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}carb_g'],
      )!,
      fatG: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}fat_g'],
      )!,
      refSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_source'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      userAdjusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}user_adjusted'],
      )!,
    );
  }

  @override
  $FoodItemsTable createAlias(String alias) {
    return $FoodItemsTable(attachedDatabase, alias);
  }
}

class FoodItem extends DataClass implements Insertable<FoodItem> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// → entries.id（逻辑引用；pull 依赖序由同步层保证，见 §6.2）。
  final String entryId;

  /// → entry_lines.id（逻辑引用，同上）。
  final String lineId;

  /// 菜品名（中文优先）。
  final String name;

  /// 份量（克），滑杆联动重算的基准。
  final double portionG;

  /// 热量（kcal，一律 INTEGER，§5.1）。
  final int kcal;

  /// 蛋白质（克）。
  final double proteinG;

  /// 碳水（克）。
  final double carbG;

  /// 脂肪（克）。
  final double fatG;

  /// 联查来源：usda / off / baidu / local / llm。
  final String refSource;

  /// 来源库条目 id。
  final String? refId;

  /// 该菜品级置信度。
  final double confidence;

  /// 用户是否改过（校准信号，bool 存 INTEGER）。
  final bool userAdjusted;
  const FoodItem({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.entryId,
    required this.lineId,
    required this.name,
    required this.portionG,
    required this.kcal,
    required this.proteinG,
    required this.carbG,
    required this.fatG,
    required this.refSource,
    this.refId,
    required this.confidence,
    required this.userAdjusted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    map['line_id'] = Variable<String>(lineId);
    map['name'] = Variable<String>(name);
    map['portion_g'] = Variable<double>(portionG);
    map['kcal'] = Variable<int>(kcal);
    map['protein_g'] = Variable<double>(proteinG);
    map['carb_g'] = Variable<double>(carbG);
    map['fat_g'] = Variable<double>(fatG);
    map['ref_source'] = Variable<String>(refSource);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['confidence'] = Variable<double>(confidence);
    map['user_adjusted'] = Variable<bool>(userAdjusted);
    return map;
  }

  FoodItemsCompanion toCompanion(bool nullToAbsent) {
    return FoodItemsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      entryId: Value(entryId),
      lineId: Value(lineId),
      name: Value(name),
      portionG: Value(portionG),
      kcal: Value(kcal),
      proteinG: Value(proteinG),
      carbG: Value(carbG),
      fatG: Value(fatG),
      refSource: Value(refSource),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      confidence: Value(confidence),
      userAdjusted: Value(userAdjusted),
    );
  }

  factory FoodItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoodItem(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      lineId: serializer.fromJson<String>(json['lineId']),
      name: serializer.fromJson<String>(json['name']),
      portionG: serializer.fromJson<double>(json['portionG']),
      kcal: serializer.fromJson<int>(json['kcal']),
      proteinG: serializer.fromJson<double>(json['proteinG']),
      carbG: serializer.fromJson<double>(json['carbG']),
      fatG: serializer.fromJson<double>(json['fatG']),
      refSource: serializer.fromJson<String>(json['refSource']),
      refId: serializer.fromJson<String?>(json['refId']),
      confidence: serializer.fromJson<double>(json['confidence']),
      userAdjusted: serializer.fromJson<bool>(json['userAdjusted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'lineId': serializer.toJson<String>(lineId),
      'name': serializer.toJson<String>(name),
      'portionG': serializer.toJson<double>(portionG),
      'kcal': serializer.toJson<int>(kcal),
      'proteinG': serializer.toJson<double>(proteinG),
      'carbG': serializer.toJson<double>(carbG),
      'fatG': serializer.toJson<double>(fatG),
      'refSource': serializer.toJson<String>(refSource),
      'refId': serializer.toJson<String?>(refId),
      'confidence': serializer.toJson<double>(confidence),
      'userAdjusted': serializer.toJson<bool>(userAdjusted),
    };
  }

  FoodItem copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? entryId,
    String? lineId,
    String? name,
    double? portionG,
    int? kcal,
    double? proteinG,
    double? carbG,
    double? fatG,
    String? refSource,
    Value<String?> refId = const Value.absent(),
    double? confidence,
    bool? userAdjusted,
  }) => FoodItem(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    lineId: lineId ?? this.lineId,
    name: name ?? this.name,
    portionG: portionG ?? this.portionG,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbG: carbG ?? this.carbG,
    fatG: fatG ?? this.fatG,
    refSource: refSource ?? this.refSource,
    refId: refId.present ? refId.value : this.refId,
    confidence: confidence ?? this.confidence,
    userAdjusted: userAdjusted ?? this.userAdjusted,
  );
  FoodItem copyWithCompanion(FoodItemsCompanion data) {
    return FoodItem(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      name: data.name.present ? data.name.value : this.name,
      portionG: data.portionG.present ? data.portionG.value : this.portionG,
      kcal: data.kcal.present ? data.kcal.value : this.kcal,
      proteinG: data.proteinG.present ? data.proteinG.value : this.proteinG,
      carbG: data.carbG.present ? data.carbG.value : this.carbG,
      fatG: data.fatG.present ? data.fatG.value : this.fatG,
      refSource: data.refSource.present ? data.refSource.value : this.refSource,
      refId: data.refId.present ? data.refId.value : this.refId,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      userAdjusted: data.userAdjusted.present
          ? data.userAdjusted.value
          : this.userAdjusted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoodItem(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('lineId: $lineId, ')
          ..write('name: $name, ')
          ..write('portionG: $portionG, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('refSource: $refSource, ')
          ..write('refId: $refId, ')
          ..write('confidence: $confidence, ')
          ..write('userAdjusted: $userAdjusted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    lineId,
    name,
    portionG,
    kcal,
    proteinG,
    carbG,
    fatG,
    refSource,
    refId,
    confidence,
    userAdjusted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoodItem &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.lineId == this.lineId &&
          other.name == this.name &&
          other.portionG == this.portionG &&
          other.kcal == this.kcal &&
          other.proteinG == this.proteinG &&
          other.carbG == this.carbG &&
          other.fatG == this.fatG &&
          other.refSource == this.refSource &&
          other.refId == this.refId &&
          other.confidence == this.confidence &&
          other.userAdjusted == this.userAdjusted);
}

class FoodItemsCompanion extends UpdateCompanion<FoodItem> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> entryId;
  final Value<String> lineId;
  final Value<String> name;
  final Value<double> portionG;
  final Value<int> kcal;
  final Value<double> proteinG;
  final Value<double> carbG;
  final Value<double> fatG;
  final Value<String> refSource;
  final Value<String?> refId;
  final Value<double> confidence;
  final Value<bool> userAdjusted;
  final Value<int> rowid;
  const FoodItemsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.name = const Value.absent(),
    this.portionG = const Value.absent(),
    this.kcal = const Value.absent(),
    this.proteinG = const Value.absent(),
    this.carbG = const Value.absent(),
    this.fatG = const Value.absent(),
    this.refSource = const Value.absent(),
    this.refId = const Value.absent(),
    this.confidence = const Value.absent(),
    this.userAdjusted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoodItemsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String entryId,
    required String lineId,
    required String name,
    required double portionG,
    required int kcal,
    required double proteinG,
    required double carbG,
    required double fatG,
    required String refSource,
    this.refId = const Value.absent(),
    required double confidence,
    required bool userAdjusted,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       entryId = Value(entryId),
       lineId = Value(lineId),
       name = Value(name),
       portionG = Value(portionG),
       kcal = Value(kcal),
       proteinG = Value(proteinG),
       carbG = Value(carbG),
       fatG = Value(fatG),
       refSource = Value(refSource),
       confidence = Value(confidence),
       userAdjusted = Value(userAdjusted);
  static Insertable<FoodItem> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? lineId,
    Expression<String>? name,
    Expression<double>? portionG,
    Expression<int>? kcal,
    Expression<double>? proteinG,
    Expression<double>? carbG,
    Expression<double>? fatG,
    Expression<String>? refSource,
    Expression<String>? refId,
    Expression<double>? confidence,
    Expression<bool>? userAdjusted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (lineId != null) 'line_id': lineId,
      if (name != null) 'name': name,
      if (portionG != null) 'portion_g': portionG,
      if (kcal != null) 'kcal': kcal,
      if (proteinG != null) 'protein_g': proteinG,
      if (carbG != null) 'carb_g': carbG,
      if (fatG != null) 'fat_g': fatG,
      if (refSource != null) 'ref_source': refSource,
      if (refId != null) 'ref_id': refId,
      if (confidence != null) 'confidence': confidence,
      if (userAdjusted != null) 'user_adjusted': userAdjusted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoodItemsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? entryId,
    Value<String>? lineId,
    Value<String>? name,
    Value<double>? portionG,
    Value<int>? kcal,
    Value<double>? proteinG,
    Value<double>? carbG,
    Value<double>? fatG,
    Value<String>? refSource,
    Value<String?>? refId,
    Value<double>? confidence,
    Value<bool>? userAdjusted,
    Value<int>? rowid,
  }) {
    return FoodItemsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      lineId: lineId ?? this.lineId,
      name: name ?? this.name,
      portionG: portionG ?? this.portionG,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbG: carbG ?? this.carbG,
      fatG: fatG ?? this.fatG,
      refSource: refSource ?? this.refSource,
      refId: refId ?? this.refId,
      confidence: confidence ?? this.confidence,
      userAdjusted: userAdjusted ?? this.userAdjusted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (portionG.present) {
      map['portion_g'] = Variable<double>(portionG.value);
    }
    if (kcal.present) {
      map['kcal'] = Variable<int>(kcal.value);
    }
    if (proteinG.present) {
      map['protein_g'] = Variable<double>(proteinG.value);
    }
    if (carbG.present) {
      map['carb_g'] = Variable<double>(carbG.value);
    }
    if (fatG.present) {
      map['fat_g'] = Variable<double>(fatG.value);
    }
    if (refSource.present) {
      map['ref_source'] = Variable<String>(refSource.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (userAdjusted.present) {
      map['user_adjusted'] = Variable<bool>(userAdjusted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoodItemsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('lineId: $lineId, ')
          ..write('name: $name, ')
          ..write('portionG: $portionG, ')
          ..write('kcal: $kcal, ')
          ..write('proteinG: $proteinG, ')
          ..write('carbG: $carbG, ')
          ..write('fatG: $fatG, ')
          ..write('refSource: $refSource, ')
          ..write('refId: $refId, ')
          ..write('confidence: $confidence, ')
          ..write('userAdjusted: $userAdjusted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LedgersTable extends Ledgers with TableInfo<$LedgersTable, Ledger> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LedgersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openingBalanceMinorMeta =
      const VerificationMeta('openingBalanceMinor');
  @override
  late final GeneratedColumn<int> openingBalanceMinor = GeneratedColumn<int>(
    'opening_balance_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    icon,
    currency,
    kind,
    sort,
    openingBalanceMinor,
    isArchived,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ledgers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Ledger> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    if (data.containsKey('opening_balance_minor')) {
      context.handle(
        _openingBalanceMinorMeta,
        openingBalanceMinor.isAcceptableOrUnknown(
          data['opening_balance_minor']!,
          _openingBalanceMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_openingBalanceMinorMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    } else if (isInserting) {
      context.missing(_isArchivedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ledger map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ledger(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
      openingBalanceMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opening_balance_minor'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
    );
  }

  @override
  $LedgersTable createAlias(String alias) {
    return $LedgersTable(attachedDatabase, alias);
  }
}

class Ledger extends DataClass implements Insertable<Ledger> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 账本名。
  final String name;

  /// 图标标识。
  final String icon;

  /// 币种（money 账本如 CNY；kcal 账本=kcal）。
  final String currency;

  /// money / kcal。
  final String kind;

  /// 排序。
  final int sort;

  /// 期初余额（分或 kcal，INTEGER，§5.1）。
  final int openingBalanceMinor;

  /// 归档（bool 存 INTEGER）。
  final bool isArchived;
  const Ledger({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.name,
    required this.icon,
    required this.currency,
    required this.kind,
    required this.sort,
    required this.openingBalanceMinor,
    required this.isArchived,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['currency'] = Variable<String>(currency);
    map['kind'] = Variable<String>(kind);
    map['sort'] = Variable<int>(sort);
    map['opening_balance_minor'] = Variable<int>(openingBalanceMinor);
    map['is_archived'] = Variable<bool>(isArchived);
    return map;
  }

  LedgersCompanion toCompanion(bool nullToAbsent) {
    return LedgersCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      currency: Value(currency),
      kind: Value(kind),
      sort: Value(sort),
      openingBalanceMinor: Value(openingBalanceMinor),
      isArchived: Value(isArchived),
    );
  }

  factory Ledger.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ledger(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      currency: serializer.fromJson<String>(json['currency']),
      kind: serializer.fromJson<String>(json['kind']),
      sort: serializer.fromJson<int>(json['sort']),
      openingBalanceMinor: serializer.fromJson<int>(
        json['openingBalanceMinor'],
      ),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'currency': serializer.toJson<String>(currency),
      'kind': serializer.toJson<String>(kind),
      'sort': serializer.toJson<int>(sort),
      'openingBalanceMinor': serializer.toJson<int>(openingBalanceMinor),
      'isArchived': serializer.toJson<bool>(isArchived),
    };
  }

  Ledger copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? name,
    String? icon,
    String? currency,
    String? kind,
    int? sort,
    int? openingBalanceMinor,
    bool? isArchived,
  }) => Ledger(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    currency: currency ?? this.currency,
    kind: kind ?? this.kind,
    sort: sort ?? this.sort,
    openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
    isArchived: isArchived ?? this.isArchived,
  );
  Ledger copyWithCompanion(LedgersCompanion data) {
    return Ledger(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      currency: data.currency.present ? data.currency.value : this.currency,
      kind: data.kind.present ? data.kind.value : this.kind,
      sort: data.sort.present ? data.sort.value : this.sort,
      openingBalanceMinor: data.openingBalanceMinor.present
          ? data.openingBalanceMinor.value
          : this.openingBalanceMinor,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ledger(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('currency: $currency, ')
          ..write('kind: $kind, ')
          ..write('sort: $sort, ')
          ..write('openingBalanceMinor: $openingBalanceMinor, ')
          ..write('isArchived: $isArchived')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    icon,
    currency,
    kind,
    sort,
    openingBalanceMinor,
    isArchived,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ledger &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.currency == this.currency &&
          other.kind == this.kind &&
          other.sort == this.sort &&
          other.openingBalanceMinor == this.openingBalanceMinor &&
          other.isArchived == this.isArchived);
}

class LedgersCompanion extends UpdateCompanion<Ledger> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<String> currency;
  final Value<String> kind;
  final Value<int> sort;
  final Value<int> openingBalanceMinor;
  final Value<bool> isArchived;
  final Value<int> rowid;
  const LedgersCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.currency = const Value.absent(),
    this.kind = const Value.absent(),
    this.sort = const Value.absent(),
    this.openingBalanceMinor = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LedgersCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String name,
    required String icon,
    required String currency,
    required String kind,
    required int sort,
    required int openingBalanceMinor,
    required bool isArchived,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       name = Value(name),
       icon = Value(icon),
       currency = Value(currency),
       kind = Value(kind),
       sort = Value(sort),
       openingBalanceMinor = Value(openingBalanceMinor),
       isArchived = Value(isArchived);
  static Insertable<Ledger> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<String>? currency,
    Expression<String>? kind,
    Expression<int>? sort,
    Expression<int>? openingBalanceMinor,
    Expression<bool>? isArchived,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (currency != null) 'currency': currency,
      if (kind != null) 'kind': kind,
      if (sort != null) 'sort': sort,
      if (openingBalanceMinor != null)
        'opening_balance_minor': openingBalanceMinor,
      if (isArchived != null) 'is_archived': isArchived,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LedgersCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<String>? currency,
    Value<String>? kind,
    Value<int>? sort,
    Value<int>? openingBalanceMinor,
    Value<bool>? isArchived,
    Value<int>? rowid,
  }) {
    return LedgersCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      currency: currency ?? this.currency,
      kind: kind ?? this.kind,
      sort: sort ?? this.sort,
      openingBalanceMinor: openingBalanceMinor ?? this.openingBalanceMinor,
      isArchived: isArchived ?? this.isArchived,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (openingBalanceMinor.present) {
      map['opening_balance_minor'] = Variable<int>(openingBalanceMinor.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LedgersCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('currency: $currency, ')
          ..write('kind: $kind, ')
          ..write('sort: $sort, ')
          ..write('openingBalanceMinor: $openingBalanceMinor, ')
          ..write('isArchived: $isArchived, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorTokenMeta = const VerificationMeta(
    'colorToken',
  );
  @override
  late final GeneratedColumn<String> colorToken = GeneratedColumn<String>(
    'color_token',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPresetMeta = const VerificationMeta(
    'isPreset',
  );
  @override
  late final GeneratedColumn<bool> isPreset = GeneratedColumn<bool>(
    'is_preset',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_preset" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    icon,
    sort,
    ledgerId,
    kind,
    colorToken,
    isPreset,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    } else if (isInserting) {
      context.missing(_iconMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('color_token')) {
      context.handle(
        _colorTokenMeta,
        colorToken.isAcceptableOrUnknown(data['color_token']!, _colorTokenMeta),
      );
    } else if (isInserting) {
      context.missing(_colorTokenMeta);
    }
    if (data.containsKey('is_preset')) {
      context.handle(
        _isPresetMeta,
        isPreset.isAcceptableOrUnknown(data['is_preset']!, _isPresetMeta),
      );
    } else if (isInserting) {
      context.missing(_isPresetMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      colorToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_token'],
      )!,
      isPreset: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_preset'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 分类名。
  final String name;

  /// 图标标识。
  final String icon;

  /// 排序。
  final int sort;

  /// NULL=全局分类；逻辑引用不建外键（pull 依赖序，§6.2）。
  final String? ledgerId;

  /// expense / income。
  final String kind;

  /// 引用语义 token 名（如 success/warn），禁止裸色值（§8.2）。
  final String colorToken;

  /// 内置 20+ 中文分类不可删。
  final bool isPreset;
  const Category({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.name,
    required this.icon,
    required this.sort,
    this.ledgerId,
    required this.kind,
    required this.colorToken,
    required this.isPreset,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['icon'] = Variable<String>(icon);
    map['sort'] = Variable<int>(sort);
    if (!nullToAbsent || ledgerId != null) {
      map['ledger_id'] = Variable<String>(ledgerId);
    }
    map['kind'] = Variable<String>(kind);
    map['color_token'] = Variable<String>(colorToken);
    map['is_preset'] = Variable<bool>(isPreset);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      sort: Value(sort),
      ledgerId: ledgerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ledgerId),
      kind: Value(kind),
      colorToken: Value(colorToken),
      isPreset: Value(isPreset),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      icon: serializer.fromJson<String>(json['icon']),
      sort: serializer.fromJson<int>(json['sort']),
      ledgerId: serializer.fromJson<String?>(json['ledgerId']),
      kind: serializer.fromJson<String>(json['kind']),
      colorToken: serializer.fromJson<String>(json['colorToken']),
      isPreset: serializer.fromJson<bool>(json['isPreset']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'icon': serializer.toJson<String>(icon),
      'sort': serializer.toJson<int>(sort),
      'ledgerId': serializer.toJson<String?>(ledgerId),
      'kind': serializer.toJson<String>(kind),
      'colorToken': serializer.toJson<String>(colorToken),
      'isPreset': serializer.toJson<bool>(isPreset),
    };
  }

  Category copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? name,
    String? icon,
    int? sort,
    Value<String?> ledgerId = const Value.absent(),
    String? kind,
    String? colorToken,
    bool? isPreset,
  }) => Category(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    sort: sort ?? this.sort,
    ledgerId: ledgerId.present ? ledgerId.value : this.ledgerId,
    kind: kind ?? this.kind,
    colorToken: colorToken ?? this.colorToken,
    isPreset: isPreset ?? this.isPreset,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      icon: data.icon.present ? data.icon.value : this.icon,
      sort: data.sort.present ? data.sort.value : this.sort,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      kind: data.kind.present ? data.kind.value : this.kind,
      colorToken: data.colorToken.present
          ? data.colorToken.value
          : this.colorToken,
      isPreset: data.isPreset.present ? data.isPreset.value : this.isPreset,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('sort: $sort, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('kind: $kind, ')
          ..write('colorToken: $colorToken, ')
          ..write('isPreset: $isPreset')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    icon,
    sort,
    ledgerId,
    kind,
    colorToken,
    isPreset,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.name == this.name &&
          other.icon == this.icon &&
          other.sort == this.sort &&
          other.ledgerId == this.ledgerId &&
          other.kind == this.kind &&
          other.colorToken == this.colorToken &&
          other.isPreset == this.isPreset);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> name;
  final Value<String> icon;
  final Value<int> sort;
  final Value<String?> ledgerId;
  final Value<String> kind;
  final Value<String> colorToken;
  final Value<bool> isPreset;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.icon = const Value.absent(),
    this.sort = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.kind = const Value.absent(),
    this.colorToken = const Value.absent(),
    this.isPreset = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String name,
    required String icon,
    required int sort,
    this.ledgerId = const Value.absent(),
    required String kind,
    required String colorToken,
    required bool isPreset,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       name = Value(name),
       icon = Value(icon),
       sort = Value(sort),
       kind = Value(kind),
       colorToken = Value(colorToken),
       isPreset = Value(isPreset);
  static Insertable<Category> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? icon,
    Expression<int>? sort,
    Expression<String>? ledgerId,
    Expression<String>? kind,
    Expression<String>? colorToken,
    Expression<bool>? isPreset,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (icon != null) 'icon': icon,
      if (sort != null) 'sort': sort,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (kind != null) 'kind': kind,
      if (colorToken != null) 'color_token': colorToken,
      if (isPreset != null) 'is_preset': isPreset,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? name,
    Value<String>? icon,
    Value<int>? sort,
    Value<String?>? ledgerId,
    Value<String>? kind,
    Value<String>? colorToken,
    Value<bool>? isPreset,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sort: sort ?? this.sort,
      ledgerId: ledgerId ?? this.ledgerId,
      kind: kind ?? this.kind,
      colorToken: colorToken ?? this.colorToken,
      isPreset: isPreset ?? this.isPreset,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (colorToken.present) {
      map['color_token'] = Variable<String>(colorToken.value);
    }
    if (isPreset.present) {
      map['is_preset'] = Variable<bool>(isPreset.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('icon: $icon, ')
          ..write('sort: $sort, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('kind: $kind, ')
          ..write('colorToken: $colorToken, ')
          ..write('isPreset: $isPreset, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BudgetsTable extends Budgets with TableInfo<$BudgetsTable, Budget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BudgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ledgerIdMeta = const VerificationMeta(
    'ledgerId',
  );
  @override
  late final GeneratedColumn<String> ledgerId = GeneratedColumn<String>(
    'ledger_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _periodTypeMeta = const VerificationMeta(
    'periodType',
  );
  @override
  late final GeneratedColumn<String> periodType = GeneratedColumn<String>(
    'period_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dayOfMonthStartMeta = const VerificationMeta(
    'dayOfMonthStart',
  );
  @override
  late final GeneratedColumn<int> dayOfMonthStart = GeneratedColumn<int>(
    'day_of_month_start',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _carryOverMeta = const VerificationMeta(
    'carryOver',
  );
  @override
  late final GeneratedColumn<bool> carryOver = GeneratedColumn<bool>(
    'carry_over',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("carry_over" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    ledgerId,
    categoryId,
    periodType,
    amount,
    dayOfMonthStart,
    carryOver,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'budgets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Budget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('ledger_id')) {
      context.handle(
        _ledgerIdMeta,
        ledgerId.isAcceptableOrUnknown(data['ledger_id']!, _ledgerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ledgerIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    }
    if (data.containsKey('period_type')) {
      context.handle(
        _periodTypeMeta,
        periodType.isAcceptableOrUnknown(data['period_type']!, _periodTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_periodTypeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('day_of_month_start')) {
      context.handle(
        _dayOfMonthStartMeta,
        dayOfMonthStart.isAcceptableOrUnknown(
          data['day_of_month_start']!,
          _dayOfMonthStartMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_dayOfMonthStartMeta);
    }
    if (data.containsKey('carry_over')) {
      context.handle(
        _carryOverMeta,
        carryOver.isAcceptableOrUnknown(data['carry_over']!, _carryOverMeta),
      );
    } else if (isInserting) {
      context.missing(_carryOverMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Budget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Budget(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      ledgerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ledger_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      ),
      periodType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}period_type'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      dayOfMonthStart: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_of_month_start'],
      )!,
      carryOver: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}carry_over'],
      )!,
    );
  }

  @override
  $BudgetsTable createAlias(String alias) {
    return $BudgetsTable(attachedDatabase, alias);
  }
}

class Budget extends DataClass implements Insertable<Budget> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 预算归属账本（含 kcal 账本）；逻辑引用不建外键（pull 依赖序，§6.2）。
  final String ledgerId;

  /// NULL=总预算。
  final String? categoryId;

  /// daily（P0：热量+支出每日预算）/ monthly（P1）。
  final String periodType;

  /// money=分；kcal 账本=kcal（一律 INTEGER，§5.1）。
  final int amount;

  /// 月度周期起点（P1）。
  final int dayOfMonthStart;

  /// 结转开关（P1，bool 存 INTEGER）。
  final bool carryOver;
  const Budget({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.ledgerId,
    this.categoryId,
    required this.periodType,
    required this.amount,
    required this.dayOfMonthStart,
    required this.carryOver,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['ledger_id'] = Variable<String>(ledgerId);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['period_type'] = Variable<String>(periodType);
    map['amount'] = Variable<int>(amount);
    map['day_of_month_start'] = Variable<int>(dayOfMonthStart);
    map['carry_over'] = Variable<bool>(carryOver);
    return map;
  }

  BudgetsCompanion toCompanion(bool nullToAbsent) {
    return BudgetsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      ledgerId: Value(ledgerId),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      periodType: Value(periodType),
      amount: Value(amount),
      dayOfMonthStart: Value(dayOfMonthStart),
      carryOver: Value(carryOver),
    );
  }

  factory Budget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Budget(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      ledgerId: serializer.fromJson<String>(json['ledgerId']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      periodType: serializer.fromJson<String>(json['periodType']),
      amount: serializer.fromJson<int>(json['amount']),
      dayOfMonthStart: serializer.fromJson<int>(json['dayOfMonthStart']),
      carryOver: serializer.fromJson<bool>(json['carryOver']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'ledgerId': serializer.toJson<String>(ledgerId),
      'categoryId': serializer.toJson<String?>(categoryId),
      'periodType': serializer.toJson<String>(periodType),
      'amount': serializer.toJson<int>(amount),
      'dayOfMonthStart': serializer.toJson<int>(dayOfMonthStart),
      'carryOver': serializer.toJson<bool>(carryOver),
    };
  }

  Budget copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? ledgerId,
    Value<String?> categoryId = const Value.absent(),
    String? periodType,
    int? amount,
    int? dayOfMonthStart,
    bool? carryOver,
  }) => Budget(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    ledgerId: ledgerId ?? this.ledgerId,
    categoryId: categoryId.present ? categoryId.value : this.categoryId,
    periodType: periodType ?? this.periodType,
    amount: amount ?? this.amount,
    dayOfMonthStart: dayOfMonthStart ?? this.dayOfMonthStart,
    carryOver: carryOver ?? this.carryOver,
  );
  Budget copyWithCompanion(BudgetsCompanion data) {
    return Budget(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      ledgerId: data.ledgerId.present ? data.ledgerId.value : this.ledgerId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      periodType: data.periodType.present
          ? data.periodType.value
          : this.periodType,
      amount: data.amount.present ? data.amount.value : this.amount,
      dayOfMonthStart: data.dayOfMonthStart.present
          ? data.dayOfMonthStart.value
          : this.dayOfMonthStart,
      carryOver: data.carryOver.present ? data.carryOver.value : this.carryOver,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Budget(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('periodType: $periodType, ')
          ..write('amount: $amount, ')
          ..write('dayOfMonthStart: $dayOfMonthStart, ')
          ..write('carryOver: $carryOver')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    ledgerId,
    categoryId,
    periodType,
    amount,
    dayOfMonthStart,
    carryOver,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Budget &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.ledgerId == this.ledgerId &&
          other.categoryId == this.categoryId &&
          other.periodType == this.periodType &&
          other.amount == this.amount &&
          other.dayOfMonthStart == this.dayOfMonthStart &&
          other.carryOver == this.carryOver);
}

class BudgetsCompanion extends UpdateCompanion<Budget> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> ledgerId;
  final Value<String?> categoryId;
  final Value<String> periodType;
  final Value<int> amount;
  final Value<int> dayOfMonthStart;
  final Value<bool> carryOver;
  final Value<int> rowid;
  const BudgetsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.ledgerId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.periodType = const Value.absent(),
    this.amount = const Value.absent(),
    this.dayOfMonthStart = const Value.absent(),
    this.carryOver = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BudgetsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String ledgerId,
    this.categoryId = const Value.absent(),
    required String periodType,
    required int amount,
    required int dayOfMonthStart,
    required bool carryOver,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       ledgerId = Value(ledgerId),
       periodType = Value(periodType),
       amount = Value(amount),
       dayOfMonthStart = Value(dayOfMonthStart),
       carryOver = Value(carryOver);
  static Insertable<Budget> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? ledgerId,
    Expression<String>? categoryId,
    Expression<String>? periodType,
    Expression<int>? amount,
    Expression<int>? dayOfMonthStart,
    Expression<bool>? carryOver,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (ledgerId != null) 'ledger_id': ledgerId,
      if (categoryId != null) 'category_id': categoryId,
      if (periodType != null) 'period_type': periodType,
      if (amount != null) 'amount': amount,
      if (dayOfMonthStart != null) 'day_of_month_start': dayOfMonthStart,
      if (carryOver != null) 'carry_over': carryOver,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BudgetsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? ledgerId,
    Value<String?>? categoryId,
    Value<String>? periodType,
    Value<int>? amount,
    Value<int>? dayOfMonthStart,
    Value<bool>? carryOver,
    Value<int>? rowid,
  }) {
    return BudgetsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      ledgerId: ledgerId ?? this.ledgerId,
      categoryId: categoryId ?? this.categoryId,
      periodType: periodType ?? this.periodType,
      amount: amount ?? this.amount,
      dayOfMonthStart: dayOfMonthStart ?? this.dayOfMonthStart,
      carryOver: carryOver ?? this.carryOver,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (ledgerId.present) {
      map['ledger_id'] = Variable<String>(ledgerId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (periodType.present) {
      map['period_type'] = Variable<String>(periodType.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (dayOfMonthStart.present) {
      map['day_of_month_start'] = Variable<int>(dayOfMonthStart.value);
    }
    if (carryOver.present) {
      map['carry_over'] = Variable<bool>(carryOver.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BudgetsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('ledgerId: $ledgerId, ')
          ..write('categoryId: $categoryId, ')
          ..write('periodType: $periodType, ')
          ..write('amount: $amount, ')
          ..write('dayOfMonthStart: $dayOfMonthStart, ')
          ..write('carryOver: $carryOver, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodosTable extends Todos with TableInfo<$TodosTable, Todo> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<int> doneAt = GeneratedColumn<int>(
    'done_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<int> dueAt = GeneratedColumn<int>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _repeatRuleMeta = const VerificationMeta(
    'repeatRule',
  );
  @override
  late final GeneratedColumn<String> repeatRule = GeneratedColumn<String>(
    'repeat_rule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remindAtMeta = const VerificationMeta(
    'remindAt',
  );
  @override
  late final GeneratedColumn<int> remindAt = GeneratedColumn<int>(
    'remind_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _goalLinkMeta = const VerificationMeta(
    'goalLink',
  );
  @override
  late final GeneratedColumn<String> goalLink = GeneratedColumn<String>(
    'goal_link',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    title,
    note,
    date,
    doneAt,
    dueAt,
    repeatRule,
    remindAt,
    goalLink,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todos';
  @override
  VerificationContext validateIntegrity(
    Insertable<Todo> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('repeat_rule')) {
      context.handle(
        _repeatRuleMeta,
        repeatRule.isAcceptableOrUnknown(data['repeat_rule']!, _repeatRuleMeta),
      );
    }
    if (data.containsKey('remind_at')) {
      context.handle(
        _remindAtMeta,
        remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta),
      );
    }
    if (data.containsKey('goal_link')) {
      context.handle(
        _goalLinkMeta,
        goalLink.isAcceptableOrUnknown(data['goal_link']!, _goalLinkMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Todo map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Todo(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      ),
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done_at'],
      ),
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due_at'],
      ),
      repeatRule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}repeat_rule'],
      ),
      remindAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remind_at'],
      ),
      goalLink: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal_link'],
      ),
    );
  }

  @override
  $TodosTable createAlias(String alias) {
    return $TodosTable(attachedDatabase, alias);
  }
}

class Todo extends DataClass implements Insertable<Todo> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 标题。
  final String title;

  /// 备注。
  final String? note;

  /// 计划日；NULL=无日期收集箱（§5.5）。
  final String? date;

  /// 完成时刻；合并只前进不回退（§6.5）。
  final int? doneAt;

  /// 截止时刻 UTC ms。
  final int? dueAt;

  /// RRULE（RFC5545，P1）。
  final String? repeatRule;

  /// 提醒时刻（P1）。
  final int? remindAt;

  /// → savings_goals / fitness_plans（联动）。多态引用（目标可指向两类
  /// 表），无法建数据库外键，仅逻辑引用（§5.5）。
  final String? goalLink;
  const Todo({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.title,
    this.note,
    this.date,
    this.doneAt,
    this.dueAt,
    this.repeatRule,
    this.remindAt,
    this.goalLink,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || date != null) {
      map['date'] = Variable<String>(date);
    }
    if (!nullToAbsent || doneAt != null) {
      map['done_at'] = Variable<int>(doneAt);
    }
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<int>(dueAt);
    }
    if (!nullToAbsent || repeatRule != null) {
      map['repeat_rule'] = Variable<String>(repeatRule);
    }
    if (!nullToAbsent || remindAt != null) {
      map['remind_at'] = Variable<int>(remindAt);
    }
    if (!nullToAbsent || goalLink != null) {
      map['goal_link'] = Variable<String>(goalLink);
    }
    return map;
  }

  TodosCompanion toCompanion(bool nullToAbsent) {
    return TodosCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      title: Value(title),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      date: date == null && nullToAbsent ? const Value.absent() : Value(date),
      doneAt: doneAt == null && nullToAbsent
          ? const Value.absent()
          : Value(doneAt),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      repeatRule: repeatRule == null && nullToAbsent
          ? const Value.absent()
          : Value(repeatRule),
      remindAt: remindAt == null && nullToAbsent
          ? const Value.absent()
          : Value(remindAt),
      goalLink: goalLink == null && nullToAbsent
          ? const Value.absent()
          : Value(goalLink),
    );
  }

  factory Todo.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Todo(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      note: serializer.fromJson<String?>(json['note']),
      date: serializer.fromJson<String?>(json['date']),
      doneAt: serializer.fromJson<int?>(json['doneAt']),
      dueAt: serializer.fromJson<int?>(json['dueAt']),
      repeatRule: serializer.fromJson<String?>(json['repeatRule']),
      remindAt: serializer.fromJson<int?>(json['remindAt']),
      goalLink: serializer.fromJson<String?>(json['goalLink']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'note': serializer.toJson<String?>(note),
      'date': serializer.toJson<String?>(date),
      'doneAt': serializer.toJson<int?>(doneAt),
      'dueAt': serializer.toJson<int?>(dueAt),
      'repeatRule': serializer.toJson<String?>(repeatRule),
      'remindAt': serializer.toJson<int?>(remindAt),
      'goalLink': serializer.toJson<String?>(goalLink),
    };
  }

  Todo copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? title,
    Value<String?> note = const Value.absent(),
    Value<String?> date = const Value.absent(),
    Value<int?> doneAt = const Value.absent(),
    Value<int?> dueAt = const Value.absent(),
    Value<String?> repeatRule = const Value.absent(),
    Value<int?> remindAt = const Value.absent(),
    Value<String?> goalLink = const Value.absent(),
  }) => Todo(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    title: title ?? this.title,
    note: note.present ? note.value : this.note,
    date: date.present ? date.value : this.date,
    doneAt: doneAt.present ? doneAt.value : this.doneAt,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    repeatRule: repeatRule.present ? repeatRule.value : this.repeatRule,
    remindAt: remindAt.present ? remindAt.value : this.remindAt,
    goalLink: goalLink.present ? goalLink.value : this.goalLink,
  );
  Todo copyWithCompanion(TodosCompanion data) {
    return Todo(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      note: data.note.present ? data.note.value : this.note,
      date: data.date.present ? data.date.value : this.date,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      repeatRule: data.repeatRule.present
          ? data.repeatRule.value
          : this.repeatRule,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      goalLink: data.goalLink.present ? data.goalLink.value : this.goalLink,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Todo(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('doneAt: $doneAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('remindAt: $remindAt, ')
          ..write('goalLink: $goalLink')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    title,
    note,
    date,
    doneAt,
    dueAt,
    repeatRule,
    remindAt,
    goalLink,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Todo &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.title == this.title &&
          other.note == this.note &&
          other.date == this.date &&
          other.doneAt == this.doneAt &&
          other.dueAt == this.dueAt &&
          other.repeatRule == this.repeatRule &&
          other.remindAt == this.remindAt &&
          other.goalLink == this.goalLink);
}

class TodosCompanion extends UpdateCompanion<Todo> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> title;
  final Value<String?> note;
  final Value<String?> date;
  final Value<int?> doneAt;
  final Value<int?> dueAt;
  final Value<String?> repeatRule;
  final Value<int?> remindAt;
  final Value<String?> goalLink;
  final Value<int> rowid;
  const TodosCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.note = const Value.absent(),
    this.date = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.goalLink = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodosCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String title,
    this.note = const Value.absent(),
    this.date = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.repeatRule = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.goalLink = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       title = Value(title);
  static Insertable<Todo> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? note,
    Expression<String>? date,
    Expression<int>? doneAt,
    Expression<int>? dueAt,
    Expression<String>? repeatRule,
    Expression<int>? remindAt,
    Expression<String>? goalLink,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (note != null) 'note': note,
      if (date != null) 'date': date,
      if (doneAt != null) 'done_at': doneAt,
      if (dueAt != null) 'due_at': dueAt,
      if (repeatRule != null) 'repeat_rule': repeatRule,
      if (remindAt != null) 'remind_at': remindAt,
      if (goalLink != null) 'goal_link': goalLink,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodosCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? title,
    Value<String?>? note,
    Value<String?>? date,
    Value<int?>? doneAt,
    Value<int?>? dueAt,
    Value<String?>? repeatRule,
    Value<int?>? remindAt,
    Value<String?>? goalLink,
    Value<int>? rowid,
  }) {
    return TodosCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      date: date ?? this.date,
      doneAt: doneAt ?? this.doneAt,
      dueAt: dueAt ?? this.dueAt,
      repeatRule: repeatRule ?? this.repeatRule,
      remindAt: remindAt ?? this.remindAt,
      goalLink: goalLink ?? this.goalLink,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<int>(doneAt.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<int>(dueAt.value);
    }
    if (repeatRule.present) {
      map['repeat_rule'] = Variable<String>(repeatRule.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<int>(remindAt.value);
    }
    if (goalLink.present) {
      map['goal_link'] = Variable<String>(goalLink.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodosCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('note: $note, ')
          ..write('date: $date, ')
          ..write('doneAt: $doneAt, ')
          ..write('dueAt: $dueAt, ')
          ..write('repeatRule: $repeatRule, ')
          ..write('remindAt: $remindAt, ')
          ..write('goalLink: $goalLink, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FitnessSessionsTable extends FitnessSessions
    with TableInfo<$FitnessSessionsTable, FitnessSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FitnessSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tzOffsetMinMeta = const VerificationMeta(
    'tzOffsetMin',
  );
  @override
  late final GeneratedColumn<int> tzOffsetMin = GeneratedColumn<int>(
    'tz_offset_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startAtMeta = const VerificationMeta(
    'startAt',
  );
  @override
  late final GeneratedColumn<int> startAt = GeneratedColumn<int>(
    'start_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSMeta = const VerificationMeta(
    'durationS',
  );
  @override
  late final GeneratedColumn<int> durationS = GeneratedColumn<int>(
    'duration_s',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalBurnMeta = const VerificationMeta(
    'kcalBurn',
  );
  @override
  late final GeneratedColumn<int> kcalBurn = GeneratedColumn<int>(
    'kcal_burn',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planDayIdMeta = const VerificationMeta(
    'planDayId',
  );
  @override
  late final GeneratedColumn<String> planDayId = GeneratedColumn<String>(
    'plan_day_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    date,
    tzOffsetMin,
    startAt,
    durationS,
    type,
    kcalBurn,
    entryId,
    source,
    planDayId,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fitness_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<FitnessSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('tz_offset_min')) {
      context.handle(
        _tzOffsetMinMeta,
        tzOffsetMin.isAcceptableOrUnknown(
          data['tz_offset_min']!,
          _tzOffsetMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tzOffsetMinMeta);
    }
    if (data.containsKey('start_at')) {
      context.handle(
        _startAtMeta,
        startAt.isAcceptableOrUnknown(data['start_at']!, _startAtMeta),
      );
    }
    if (data.containsKey('duration_s')) {
      context.handle(
        _durationSMeta,
        durationS.isAcceptableOrUnknown(data['duration_s']!, _durationSMeta),
      );
    } else if (isInserting) {
      context.missing(_durationSMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('kcal_burn')) {
      context.handle(
        _kcalBurnMeta,
        kcalBurn.isAcceptableOrUnknown(data['kcal_burn']!, _kcalBurnMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalBurnMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('plan_day_id')) {
      context.handle(
        _planDayIdMeta,
        planDayId.isAcceptableOrUnknown(data['plan_day_id']!, _planDayIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FitnessSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FitnessSession(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      tzOffsetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tz_offset_min'],
      )!,
      startAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_at'],
      ),
      durationS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_s'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      kcalBurn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kcal_burn'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      planDayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_day_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $FitnessSessionsTable createAlias(String alias) {
    return $FitnessSessionsTable(attachedDatabase, alias);
  }
}

class FitnessSession extends DataClass implements Insertable<FitnessSession> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 归属日 `yyyy-MM-dd`（§5.1 日期约定）。
  final String date;

  /// 录入时本地时区偏移（分钟）。
  final int tzOffsetMin;

  /// 开始时刻 UTC ms。
  final int? startAt;

  /// 时长（秒）。
  final int durationS;

  /// strength / cardio / hiit / other / template_instance。
  final String type;

  /// MET 表估算（MET × 体重 × 时长），UI 按 ±20% 口径标注（§5.5）。
  final int kcalBurn;

  /// → entries.id：经此对应 entries(kind=fitness) 1:1 产出
  /// entry_lines(type=burn)（§5.7）。逻辑引用不建外键：会话与其 entry
  /// 同事务生成（§2.2），但跨设备 pull 顺序不定（§6.2）。
  final String? entryId;

  /// manual / timer / plan。
  final String source;

  /// → 健身计划排期日（P1）。v1 无独立排期日表（21 表清单未含），
  /// 故为逻辑前向引用、不建外键（§5.5）。
  final String? planDayId;

  /// 备注。
  final String? note;
  const FitnessSession({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.date,
    required this.tzOffsetMin,
    this.startAt,
    required this.durationS,
    required this.type,
    required this.kcalBurn,
    this.entryId,
    required this.source,
    this.planDayId,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['date'] = Variable<String>(date);
    map['tz_offset_min'] = Variable<int>(tzOffsetMin);
    if (!nullToAbsent || startAt != null) {
      map['start_at'] = Variable<int>(startAt);
    }
    map['duration_s'] = Variable<int>(durationS);
    map['type'] = Variable<String>(type);
    map['kcal_burn'] = Variable<int>(kcalBurn);
    if (!nullToAbsent || entryId != null) {
      map['entry_id'] = Variable<String>(entryId);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || planDayId != null) {
      map['plan_day_id'] = Variable<String>(planDayId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  FitnessSessionsCompanion toCompanion(bool nullToAbsent) {
    return FitnessSessionsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      date: Value(date),
      tzOffsetMin: Value(tzOffsetMin),
      startAt: startAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startAt),
      durationS: Value(durationS),
      type: Value(type),
      kcalBurn: Value(kcalBurn),
      entryId: entryId == null && nullToAbsent
          ? const Value.absent()
          : Value(entryId),
      source: Value(source),
      planDayId: planDayId == null && nullToAbsent
          ? const Value.absent()
          : Value(planDayId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory FitnessSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FitnessSession(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      date: serializer.fromJson<String>(json['date']),
      tzOffsetMin: serializer.fromJson<int>(json['tzOffsetMin']),
      startAt: serializer.fromJson<int?>(json['startAt']),
      durationS: serializer.fromJson<int>(json['durationS']),
      type: serializer.fromJson<String>(json['type']),
      kcalBurn: serializer.fromJson<int>(json['kcalBurn']),
      entryId: serializer.fromJson<String?>(json['entryId']),
      source: serializer.fromJson<String>(json['source']),
      planDayId: serializer.fromJson<String?>(json['planDayId']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'date': serializer.toJson<String>(date),
      'tzOffsetMin': serializer.toJson<int>(tzOffsetMin),
      'startAt': serializer.toJson<int?>(startAt),
      'durationS': serializer.toJson<int>(durationS),
      'type': serializer.toJson<String>(type),
      'kcalBurn': serializer.toJson<int>(kcalBurn),
      'entryId': serializer.toJson<String?>(entryId),
      'source': serializer.toJson<String>(source),
      'planDayId': serializer.toJson<String?>(planDayId),
      'note': serializer.toJson<String?>(note),
    };
  }

  FitnessSession copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? date,
    int? tzOffsetMin,
    Value<int?> startAt = const Value.absent(),
    int? durationS,
    String? type,
    int? kcalBurn,
    Value<String?> entryId = const Value.absent(),
    String? source,
    Value<String?> planDayId = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => FitnessSession(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    date: date ?? this.date,
    tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
    startAt: startAt.present ? startAt.value : this.startAt,
    durationS: durationS ?? this.durationS,
    type: type ?? this.type,
    kcalBurn: kcalBurn ?? this.kcalBurn,
    entryId: entryId.present ? entryId.value : this.entryId,
    source: source ?? this.source,
    planDayId: planDayId.present ? planDayId.value : this.planDayId,
    note: note.present ? note.value : this.note,
  );
  FitnessSession copyWithCompanion(FitnessSessionsCompanion data) {
    return FitnessSession(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      tzOffsetMin: data.tzOffsetMin.present
          ? data.tzOffsetMin.value
          : this.tzOffsetMin,
      startAt: data.startAt.present ? data.startAt.value : this.startAt,
      durationS: data.durationS.present ? data.durationS.value : this.durationS,
      type: data.type.present ? data.type.value : this.type,
      kcalBurn: data.kcalBurn.present ? data.kcalBurn.value : this.kcalBurn,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      source: data.source.present ? data.source.value : this.source,
      planDayId: data.planDayId.present ? data.planDayId.value : this.planDayId,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FitnessSession(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('startAt: $startAt, ')
          ..write('durationS: $durationS, ')
          ..write('type: $type, ')
          ..write('kcalBurn: $kcalBurn, ')
          ..write('entryId: $entryId, ')
          ..write('source: $source, ')
          ..write('planDayId: $planDayId, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    date,
    tzOffsetMin,
    startAt,
    durationS,
    type,
    kcalBurn,
    entryId,
    source,
    planDayId,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FitnessSession &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.date == this.date &&
          other.tzOffsetMin == this.tzOffsetMin &&
          other.startAt == this.startAt &&
          other.durationS == this.durationS &&
          other.type == this.type &&
          other.kcalBurn == this.kcalBurn &&
          other.entryId == this.entryId &&
          other.source == this.source &&
          other.planDayId == this.planDayId &&
          other.note == this.note);
}

class FitnessSessionsCompanion extends UpdateCompanion<FitnessSession> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> date;
  final Value<int> tzOffsetMin;
  final Value<int?> startAt;
  final Value<int> durationS;
  final Value<String> type;
  final Value<int> kcalBurn;
  final Value<String?> entryId;
  final Value<String> source;
  final Value<String?> planDayId;
  final Value<String?> note;
  final Value<int> rowid;
  const FitnessSessionsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.tzOffsetMin = const Value.absent(),
    this.startAt = const Value.absent(),
    this.durationS = const Value.absent(),
    this.type = const Value.absent(),
    this.kcalBurn = const Value.absent(),
    this.entryId = const Value.absent(),
    this.source = const Value.absent(),
    this.planDayId = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FitnessSessionsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String date,
    required int tzOffsetMin,
    this.startAt = const Value.absent(),
    required int durationS,
    required String type,
    required int kcalBurn,
    this.entryId = const Value.absent(),
    required String source,
    this.planDayId = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       date = Value(date),
       tzOffsetMin = Value(tzOffsetMin),
       durationS = Value(durationS),
       type = Value(type),
       kcalBurn = Value(kcalBurn),
       source = Value(source);
  static Insertable<FitnessSession> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? date,
    Expression<int>? tzOffsetMin,
    Expression<int>? startAt,
    Expression<int>? durationS,
    Expression<String>? type,
    Expression<int>? kcalBurn,
    Expression<String>? entryId,
    Expression<String>? source,
    Expression<String>? planDayId,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (tzOffsetMin != null) 'tz_offset_min': tzOffsetMin,
      if (startAt != null) 'start_at': startAt,
      if (durationS != null) 'duration_s': durationS,
      if (type != null) 'type': type,
      if (kcalBurn != null) 'kcal_burn': kcalBurn,
      if (entryId != null) 'entry_id': entryId,
      if (source != null) 'source': source,
      if (planDayId != null) 'plan_day_id': planDayId,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FitnessSessionsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? date,
    Value<int>? tzOffsetMin,
    Value<int?>? startAt,
    Value<int>? durationS,
    Value<String>? type,
    Value<int>? kcalBurn,
    Value<String?>? entryId,
    Value<String>? source,
    Value<String?>? planDayId,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return FitnessSessionsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      date: date ?? this.date,
      tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
      startAt: startAt ?? this.startAt,
      durationS: durationS ?? this.durationS,
      type: type ?? this.type,
      kcalBurn: kcalBurn ?? this.kcalBurn,
      entryId: entryId ?? this.entryId,
      source: source ?? this.source,
      planDayId: planDayId ?? this.planDayId,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (tzOffsetMin.present) {
      map['tz_offset_min'] = Variable<int>(tzOffsetMin.value);
    }
    if (startAt.present) {
      map['start_at'] = Variable<int>(startAt.value);
    }
    if (durationS.present) {
      map['duration_s'] = Variable<int>(durationS.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (kcalBurn.present) {
      map['kcal_burn'] = Variable<int>(kcalBurn.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (planDayId.present) {
      map['plan_day_id'] = Variable<String>(planDayId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FitnessSessionsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('startAt: $startAt, ')
          ..write('durationS: $durationS, ')
          ..write('type: $type, ')
          ..write('kcalBurn: $kcalBurn, ')
          ..write('entryId: $entryId, ')
          ..write('source: $source, ')
          ..write('planDayId: $planDayId, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FitnessPlansTable extends FitnessPlans
    with TableInfo<$FitnessPlansTable, FitnessPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FitnessPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weekdayMaskMeta = const VerificationMeta(
    'weekdayMask',
  );
  @override
  late final GeneratedColumn<int> weekdayMask = GeneratedColumn<int>(
    'weekday_mask',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exercisesMeta = const VerificationMeta(
    'exercises',
  );
  @override
  late final GeneratedColumn<String> exercises = GeneratedColumn<String>(
    'exercises',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<String> startDate = GeneratedColumn<String>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    weekdayMask,
    exercises,
    startDate,
    active,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fitness_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<FitnessPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('weekday_mask')) {
      context.handle(
        _weekdayMaskMeta,
        weekdayMask.isAcceptableOrUnknown(
          data['weekday_mask']!,
          _weekdayMaskMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weekdayMaskMeta);
    }
    if (data.containsKey('exercises')) {
      context.handle(
        _exercisesMeta,
        exercises.isAcceptableOrUnknown(data['exercises']!, _exercisesMeta),
      );
    } else if (isInserting) {
      context.missing(_exercisesMeta);
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    } else if (isInserting) {
      context.missing(_activeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FitnessPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FitnessPlan(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      weekdayMask: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weekday_mask'],
      )!,
      exercises: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercises'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}start_date'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
    );
  }

  @override
  $FitnessPlansTable createAlias(String alias) {
    return $FitnessPlansTable(attachedDatabase, alias);
  }
}

class FitnessPlan extends DataClass implements Insertable<FitnessPlan> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 计划名。
  final String name;

  /// bit0=周一…bit6=周日 排期掩码。
  final int weekdayMask;

  /// 排期模板 JSON：动作/组数/重量配比/休息秒。
  final String exercises;

  /// 起始日 `yyyy-MM-dd`。
  final String startDate;

  /// 启用（bool 存 INTEGER）。
  final bool active;
  const FitnessPlan({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.name,
    required this.weekdayMask,
    required this.exercises,
    required this.startDate,
    required this.active,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['weekday_mask'] = Variable<int>(weekdayMask);
    map['exercises'] = Variable<String>(exercises);
    map['start_date'] = Variable<String>(startDate);
    map['active'] = Variable<bool>(active);
    return map;
  }

  FitnessPlansCompanion toCompanion(bool nullToAbsent) {
    return FitnessPlansCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      name: Value(name),
      weekdayMask: Value(weekdayMask),
      exercises: Value(exercises),
      startDate: Value(startDate),
      active: Value(active),
    );
  }

  factory FitnessPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FitnessPlan(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      weekdayMask: serializer.fromJson<int>(json['weekdayMask']),
      exercises: serializer.fromJson<String>(json['exercises']),
      startDate: serializer.fromJson<String>(json['startDate']),
      active: serializer.fromJson<bool>(json['active']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'weekdayMask': serializer.toJson<int>(weekdayMask),
      'exercises': serializer.toJson<String>(exercises),
      'startDate': serializer.toJson<String>(startDate),
      'active': serializer.toJson<bool>(active),
    };
  }

  FitnessPlan copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? name,
    int? weekdayMask,
    String? exercises,
    String? startDate,
    bool? active,
  }) => FitnessPlan(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    name: name ?? this.name,
    weekdayMask: weekdayMask ?? this.weekdayMask,
    exercises: exercises ?? this.exercises,
    startDate: startDate ?? this.startDate,
    active: active ?? this.active,
  );
  FitnessPlan copyWithCompanion(FitnessPlansCompanion data) {
    return FitnessPlan(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      weekdayMask: data.weekdayMask.present
          ? data.weekdayMask.value
          : this.weekdayMask,
      exercises: data.exercises.present ? data.exercises.value : this.exercises,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      active: data.active.present ? data.active.value : this.active,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FitnessPlan(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weekdayMask: $weekdayMask, ')
          ..write('exercises: $exercises, ')
          ..write('startDate: $startDate, ')
          ..write('active: $active')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    weekdayMask,
    exercises,
    startDate,
    active,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FitnessPlan &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.name == this.name &&
          other.weekdayMask == this.weekdayMask &&
          other.exercises == this.exercises &&
          other.startDate == this.startDate &&
          other.active == this.active);
}

class FitnessPlansCompanion extends UpdateCompanion<FitnessPlan> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> weekdayMask;
  final Value<String> exercises;
  final Value<String> startDate;
  final Value<bool> active;
  final Value<int> rowid;
  const FitnessPlansCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.weekdayMask = const Value.absent(),
    this.exercises = const Value.absent(),
    this.startDate = const Value.absent(),
    this.active = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FitnessPlansCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String name,
    required int weekdayMask,
    required String exercises,
    required String startDate,
    required bool active,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       name = Value(name),
       weekdayMask = Value(weekdayMask),
       exercises = Value(exercises),
       startDate = Value(startDate),
       active = Value(active);
  static Insertable<FitnessPlan> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? weekdayMask,
    Expression<String>? exercises,
    Expression<String>? startDate,
    Expression<bool>? active,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (weekdayMask != null) 'weekday_mask': weekdayMask,
      if (exercises != null) 'exercises': exercises,
      if (startDate != null) 'start_date': startDate,
      if (active != null) 'active': active,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FitnessPlansCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? weekdayMask,
    Value<String>? exercises,
    Value<String>? startDate,
    Value<bool>? active,
    Value<int>? rowid,
  }) {
    return FitnessPlansCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      weekdayMask: weekdayMask ?? this.weekdayMask,
      exercises: exercises ?? this.exercises,
      startDate: startDate ?? this.startDate,
      active: active ?? this.active,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (weekdayMask.present) {
      map['weekday_mask'] = Variable<int>(weekdayMask.value);
    }
    if (exercises.present) {
      map['exercises'] = Variable<String>(exercises.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<String>(startDate.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FitnessPlansCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('weekdayMask: $weekdayMask, ')
          ..write('exercises: $exercises, ')
          ..write('startDate: $startDate, ')
          ..write('active: $active, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExerciseSetsTable extends ExerciseSets
    with TableInfo<$ExerciseSetsTable, ExerciseSet> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExerciseSetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exerciseRefMeta = const VerificationMeta(
    'exerciseRef',
  );
  @override
  late final GeneratedColumn<String> exerciseRef = GeneratedColumn<String>(
    'exercise_ref',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _weightKgX10Meta = const VerificationMeta(
    'weightKgX10',
  );
  @override
  late final GeneratedColumn<int> weightKgX10 = GeneratedColumn<int>(
    'weight_kg_x10',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
    'reps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rpeMeta = const VerificationMeta('rpe');
  @override
  late final GeneratedColumn<double> rpe = GeneratedColumn<double>(
    'rpe',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _restSMeta = const VerificationMeta('restS');
  @override
  late final GeneratedColumn<int> restS = GeneratedColumn<int>(
    'rest_s',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<int> doneAt = GeneratedColumn<int>(
    'done_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    sessionId,
    exerciseRef,
    weightKgX10,
    reps,
    rpe,
    restS,
    doneAt,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exercise_sets';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExerciseSet> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('exercise_ref')) {
      context.handle(
        _exerciseRefMeta,
        exerciseRef.isAcceptableOrUnknown(
          data['exercise_ref']!,
          _exerciseRefMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exerciseRefMeta);
    }
    if (data.containsKey('weight_kg_x10')) {
      context.handle(
        _weightKgX10Meta,
        weightKgX10.isAcceptableOrUnknown(
          data['weight_kg_x10']!,
          _weightKgX10Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_weightKgX10Meta);
    }
    if (data.containsKey('reps')) {
      context.handle(
        _repsMeta,
        reps.isAcceptableOrUnknown(data['reps']!, _repsMeta),
      );
    } else if (isInserting) {
      context.missing(_repsMeta);
    }
    if (data.containsKey('rpe')) {
      context.handle(
        _rpeMeta,
        rpe.isAcceptableOrUnknown(data['rpe']!, _rpeMeta),
      );
    }
    if (data.containsKey('rest_s')) {
      context.handle(
        _restSMeta,
        restS.isAcceptableOrUnknown(data['rest_s']!, _restSMeta),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    } else if (isInserting) {
      context.missing(_doneAtMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExerciseSet map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExerciseSet(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      exerciseRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_ref'],
      )!,
      weightKgX10: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}weight_kg_x10'],
      )!,
      reps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reps'],
      )!,
      rpe: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}rpe'],
      ),
      restS: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rest_s'],
      ),
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}done_at'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $ExerciseSetsTable createAlias(String alias) {
    return $ExerciseSetsTable(attachedDatabase, alias);
  }
}

class ExerciseSet extends DataClass implements Insertable<ExerciseSet> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// → fitness_sessions.id。逻辑引用不建外键（pull 依赖序，§6.2）。
  final String sessionId;

  /// 动作库 id 或名称。
  final String exerciseRef;

  /// 重量 ×10 定点（避免浮点同步问题，§5.5）。
  final int weightKgX10;

  /// 次数。
  final int reps;

  /// 强度 RPE。
  final double? rpe;

  /// 休息秒。
  final int? restS;

  /// 完成时刻 UTC ms。
  final int doneAt;

  /// 组序。
  final int sort;
  const ExerciseSet({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.sessionId,
    required this.exerciseRef,
    required this.weightKgX10,
    required this.reps,
    this.rpe,
    this.restS,
    required this.doneAt,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['exercise_ref'] = Variable<String>(exerciseRef);
    map['weight_kg_x10'] = Variable<int>(weightKgX10);
    map['reps'] = Variable<int>(reps);
    if (!nullToAbsent || rpe != null) {
      map['rpe'] = Variable<double>(rpe);
    }
    if (!nullToAbsent || restS != null) {
      map['rest_s'] = Variable<int>(restS);
    }
    map['done_at'] = Variable<int>(doneAt);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  ExerciseSetsCompanion toCompanion(bool nullToAbsent) {
    return ExerciseSetsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      sessionId: Value(sessionId),
      exerciseRef: Value(exerciseRef),
      weightKgX10: Value(weightKgX10),
      reps: Value(reps),
      rpe: rpe == null && nullToAbsent ? const Value.absent() : Value(rpe),
      restS: restS == null && nullToAbsent
          ? const Value.absent()
          : Value(restS),
      doneAt: Value(doneAt),
      sort: Value(sort),
    );
  }

  factory ExerciseSet.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExerciseSet(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      exerciseRef: serializer.fromJson<String>(json['exerciseRef']),
      weightKgX10: serializer.fromJson<int>(json['weightKgX10']),
      reps: serializer.fromJson<int>(json['reps']),
      rpe: serializer.fromJson<double?>(json['rpe']),
      restS: serializer.fromJson<int?>(json['restS']),
      doneAt: serializer.fromJson<int>(json['doneAt']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'exerciseRef': serializer.toJson<String>(exerciseRef),
      'weightKgX10': serializer.toJson<int>(weightKgX10),
      'reps': serializer.toJson<int>(reps),
      'rpe': serializer.toJson<double?>(rpe),
      'restS': serializer.toJson<int?>(restS),
      'doneAt': serializer.toJson<int>(doneAt),
      'sort': serializer.toJson<int>(sort),
    };
  }

  ExerciseSet copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? sessionId,
    String? exerciseRef,
    int? weightKgX10,
    int? reps,
    Value<double?> rpe = const Value.absent(),
    Value<int?> restS = const Value.absent(),
    int? doneAt,
    int? sort,
  }) => ExerciseSet(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    exerciseRef: exerciseRef ?? this.exerciseRef,
    weightKgX10: weightKgX10 ?? this.weightKgX10,
    reps: reps ?? this.reps,
    rpe: rpe.present ? rpe.value : this.rpe,
    restS: restS.present ? restS.value : this.restS,
    doneAt: doneAt ?? this.doneAt,
    sort: sort ?? this.sort,
  );
  ExerciseSet copyWithCompanion(ExerciseSetsCompanion data) {
    return ExerciseSet(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      exerciseRef: data.exerciseRef.present
          ? data.exerciseRef.value
          : this.exerciseRef,
      weightKgX10: data.weightKgX10.present
          ? data.weightKgX10.value
          : this.weightKgX10,
      reps: data.reps.present ? data.reps.value : this.reps,
      rpe: data.rpe.present ? data.rpe.value : this.rpe,
      restS: data.restS.present ? data.restS.value : this.restS,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExerciseSet(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('exerciseRef: $exerciseRef, ')
          ..write('weightKgX10: $weightKgX10, ')
          ..write('reps: $reps, ')
          ..write('rpe: $rpe, ')
          ..write('restS: $restS, ')
          ..write('doneAt: $doneAt, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    sessionId,
    exerciseRef,
    weightKgX10,
    reps,
    rpe,
    restS,
    doneAt,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExerciseSet &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.exerciseRef == this.exerciseRef &&
          other.weightKgX10 == this.weightKgX10 &&
          other.reps == this.reps &&
          other.rpe == this.rpe &&
          other.restS == this.restS &&
          other.doneAt == this.doneAt &&
          other.sort == this.sort);
}

class ExerciseSetsCompanion extends UpdateCompanion<ExerciseSet> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> exerciseRef;
  final Value<int> weightKgX10;
  final Value<int> reps;
  final Value<double?> rpe;
  final Value<int?> restS;
  final Value<int> doneAt;
  final Value<int> sort;
  final Value<int> rowid;
  const ExerciseSetsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.exerciseRef = const Value.absent(),
    this.weightKgX10 = const Value.absent(),
    this.reps = const Value.absent(),
    this.rpe = const Value.absent(),
    this.restS = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExerciseSetsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String sessionId,
    required String exerciseRef,
    required int weightKgX10,
    required int reps,
    this.rpe = const Value.absent(),
    this.restS = const Value.absent(),
    required int doneAt,
    required int sort,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       sessionId = Value(sessionId),
       exerciseRef = Value(exerciseRef),
       weightKgX10 = Value(weightKgX10),
       reps = Value(reps),
       doneAt = Value(doneAt),
       sort = Value(sort);
  static Insertable<ExerciseSet> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? exerciseRef,
    Expression<int>? weightKgX10,
    Expression<int>? reps,
    Expression<double>? rpe,
    Expression<int>? restS,
    Expression<int>? doneAt,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (exerciseRef != null) 'exercise_ref': exerciseRef,
      if (weightKgX10 != null) 'weight_kg_x10': weightKgX10,
      if (reps != null) 'reps': reps,
      if (rpe != null) 'rpe': rpe,
      if (restS != null) 'rest_s': restS,
      if (doneAt != null) 'done_at': doneAt,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExerciseSetsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? exerciseRef,
    Value<int>? weightKgX10,
    Value<int>? reps,
    Value<double?>? rpe,
    Value<int?>? restS,
    Value<int>? doneAt,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return ExerciseSetsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      exerciseRef: exerciseRef ?? this.exerciseRef,
      weightKgX10: weightKgX10 ?? this.weightKgX10,
      reps: reps ?? this.reps,
      rpe: rpe ?? this.rpe,
      restS: restS ?? this.restS,
      doneAt: doneAt ?? this.doneAt,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (exerciseRef.present) {
      map['exercise_ref'] = Variable<String>(exerciseRef.value);
    }
    if (weightKgX10.present) {
      map['weight_kg_x10'] = Variable<int>(weightKgX10.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (rpe.present) {
      map['rpe'] = Variable<double>(rpe.value);
    }
    if (restS.present) {
      map['rest_s'] = Variable<int>(restS.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<int>(doneAt.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExerciseSetsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('exerciseRef: $exerciseRef, ')
          ..write('weightKgX10: $weightKgX10, ')
          ..write('reps: $reps, ')
          ..write('rpe: $rpe, ')
          ..write('restS: $restS, ')
          ..write('doneAt: $doneAt, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavingsGoalsTable extends SavingsGoals
    with TableInfo<$SavingsGoalsTable, SavingsGoal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavingsGoalsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetMinorMeta = const VerificationMeta(
    'targetMinor',
  );
  @override
  late final GeneratedColumn<int> targetMinor = GeneratedColumn<int>(
    'target_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deadlineMeta = const VerificationMeta(
    'deadline',
  );
  @override
  late final GeneratedColumn<String> deadline = GeneratedColumn<String>(
    'deadline',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rhythmMeta = const VerificationMeta('rhythm');
  @override
  late final GeneratedColumn<String> rhythm = GeneratedColumn<String>(
    'rhythm',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedOnMeta = const VerificationMeta(
    'startedOn',
  );
  @override
  late final GeneratedColumn<String> startedOn = GeneratedColumn<String>(
    'started_on',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    targetMinor,
    deadline,
    method,
    rhythm,
    status,
    startedOn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'savings_goals';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavingsGoal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('target_minor')) {
      context.handle(
        _targetMinorMeta,
        targetMinor.isAcceptableOrUnknown(
          data['target_minor']!,
          _targetMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetMinorMeta);
    }
    if (data.containsKey('deadline')) {
      context.handle(
        _deadlineMeta,
        deadline.isAcceptableOrUnknown(data['deadline']!, _deadlineMeta),
      );
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    } else if (isInserting) {
      context.missing(_methodMeta);
    }
    if (data.containsKey('rhythm')) {
      context.handle(
        _rhythmMeta,
        rhythm.isAcceptableOrUnknown(data['rhythm']!, _rhythmMeta),
      );
    } else if (isInserting) {
      context.missing(_rhythmMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('started_on')) {
      context.handle(
        _startedOnMeta,
        startedOn.isAcceptableOrUnknown(data['started_on']!, _startedOnMeta),
      );
    } else if (isInserting) {
      context.missing(_startedOnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavingsGoal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavingsGoal(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      targetMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}target_minor'],
      )!,
      deadline: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deadline'],
      ),
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      )!,
      rhythm: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rhythm'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}started_on'],
      )!,
    );
  }

  @override
  $SavingsGoalsTable createAlias(String alias) {
    return $SavingsGoalsTable(attachedDatabase, alias);
  }
}

class SavingsGoal extends DataClass implements Insertable<SavingsGoal> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 目标名。
  final String name;

  /// 目标金额（分，INTEGER，§5.1）。
  final int targetMinor;

  /// 截止日 `yyyy-MM-dd`。
  final String? deadline;

  /// daily365 / week52 / custom。
  final String method;

  /// 阶梯表或每日额（JSON）。
  final String rhythm;

  /// active / completed / abandoned。
  final String status;

  /// 起始日 `yyyy-MM-dd`。
  final String startedOn;
  const SavingsGoal({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.name,
    required this.targetMinor,
    this.deadline,
    required this.method,
    required this.rhythm,
    required this.status,
    required this.startedOn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['target_minor'] = Variable<int>(targetMinor);
    if (!nullToAbsent || deadline != null) {
      map['deadline'] = Variable<String>(deadline);
    }
    map['method'] = Variable<String>(method);
    map['rhythm'] = Variable<String>(rhythm);
    map['status'] = Variable<String>(status);
    map['started_on'] = Variable<String>(startedOn);
    return map;
  }

  SavingsGoalsCompanion toCompanion(bool nullToAbsent) {
    return SavingsGoalsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      name: Value(name),
      targetMinor: Value(targetMinor),
      deadline: deadline == null && nullToAbsent
          ? const Value.absent()
          : Value(deadline),
      method: Value(method),
      rhythm: Value(rhythm),
      status: Value(status),
      startedOn: Value(startedOn),
    );
  }

  factory SavingsGoal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavingsGoal(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      targetMinor: serializer.fromJson<int>(json['targetMinor']),
      deadline: serializer.fromJson<String?>(json['deadline']),
      method: serializer.fromJson<String>(json['method']),
      rhythm: serializer.fromJson<String>(json['rhythm']),
      status: serializer.fromJson<String>(json['status']),
      startedOn: serializer.fromJson<String>(json['startedOn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'targetMinor': serializer.toJson<int>(targetMinor),
      'deadline': serializer.toJson<String?>(deadline),
      'method': serializer.toJson<String>(method),
      'rhythm': serializer.toJson<String>(rhythm),
      'status': serializer.toJson<String>(status),
      'startedOn': serializer.toJson<String>(startedOn),
    };
  }

  SavingsGoal copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? name,
    int? targetMinor,
    Value<String?> deadline = const Value.absent(),
    String? method,
    String? rhythm,
    String? status,
    String? startedOn,
  }) => SavingsGoal(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    name: name ?? this.name,
    targetMinor: targetMinor ?? this.targetMinor,
    deadline: deadline.present ? deadline.value : this.deadline,
    method: method ?? this.method,
    rhythm: rhythm ?? this.rhythm,
    status: status ?? this.status,
    startedOn: startedOn ?? this.startedOn,
  );
  SavingsGoal copyWithCompanion(SavingsGoalsCompanion data) {
    return SavingsGoal(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      targetMinor: data.targetMinor.present
          ? data.targetMinor.value
          : this.targetMinor,
      deadline: data.deadline.present ? data.deadline.value : this.deadline,
      method: data.method.present ? data.method.value : this.method,
      rhythm: data.rhythm.present ? data.rhythm.value : this.rhythm,
      status: data.status.present ? data.status.value : this.status,
      startedOn: data.startedOn.present ? data.startedOn.value : this.startedOn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavingsGoal(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetMinor: $targetMinor, ')
          ..write('deadline: $deadline, ')
          ..write('method: $method, ')
          ..write('rhythm: $rhythm, ')
          ..write('status: $status, ')
          ..write('startedOn: $startedOn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    targetMinor,
    deadline,
    method,
    rhythm,
    status,
    startedOn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavingsGoal &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.name == this.name &&
          other.targetMinor == this.targetMinor &&
          other.deadline == this.deadline &&
          other.method == this.method &&
          other.rhythm == this.rhythm &&
          other.status == this.status &&
          other.startedOn == this.startedOn);
}

class SavingsGoalsCompanion extends UpdateCompanion<SavingsGoal> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> name;
  final Value<int> targetMinor;
  final Value<String?> deadline;
  final Value<String> method;
  final Value<String> rhythm;
  final Value<String> status;
  final Value<String> startedOn;
  final Value<int> rowid;
  const SavingsGoalsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.targetMinor = const Value.absent(),
    this.deadline = const Value.absent(),
    this.method = const Value.absent(),
    this.rhythm = const Value.absent(),
    this.status = const Value.absent(),
    this.startedOn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavingsGoalsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String name,
    required int targetMinor,
    this.deadline = const Value.absent(),
    required String method,
    required String rhythm,
    required String status,
    required String startedOn,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       name = Value(name),
       targetMinor = Value(targetMinor),
       method = Value(method),
       rhythm = Value(rhythm),
       status = Value(status),
       startedOn = Value(startedOn);
  static Insertable<SavingsGoal> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? targetMinor,
    Expression<String>? deadline,
    Expression<String>? method,
    Expression<String>? rhythm,
    Expression<String>? status,
    Expression<String>? startedOn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (targetMinor != null) 'target_minor': targetMinor,
      if (deadline != null) 'deadline': deadline,
      if (method != null) 'method': method,
      if (rhythm != null) 'rhythm': rhythm,
      if (status != null) 'status': status,
      if (startedOn != null) 'started_on': startedOn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavingsGoalsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? name,
    Value<int>? targetMinor,
    Value<String?>? deadline,
    Value<String>? method,
    Value<String>? rhythm,
    Value<String>? status,
    Value<String>? startedOn,
    Value<int>? rowid,
  }) {
    return SavingsGoalsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      targetMinor: targetMinor ?? this.targetMinor,
      deadline: deadline ?? this.deadline,
      method: method ?? this.method,
      rhythm: rhythm ?? this.rhythm,
      status: status ?? this.status,
      startedOn: startedOn ?? this.startedOn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (targetMinor.present) {
      map['target_minor'] = Variable<int>(targetMinor.value);
    }
    if (deadline.present) {
      map['deadline'] = Variable<String>(deadline.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (rhythm.present) {
      map['rhythm'] = Variable<String>(rhythm.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedOn.present) {
      map['started_on'] = Variable<String>(startedOn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavingsGoalsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('targetMinor: $targetMinor, ')
          ..write('deadline: $deadline, ')
          ..write('method: $method, ')
          ..write('rhythm: $rhythm, ')
          ..write('status: $status, ')
          ..write('startedOn: $startedOn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavingsContributionsTable extends SavingsContributions
    with TableInfo<$SavingsContributionsTable, SavingsContribution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavingsContributionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _goalIdMeta = const VerificationMeta('goalId');
  @override
  late final GeneratedColumn<String> goalId = GeneratedColumn<String>(
    'goal_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    goalId,
    date,
    amountMinor,
    slot,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'savings_contributions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavingsContribution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('goal_id')) {
      context.handle(
        _goalIdMeta,
        goalId.isAcceptableOrUnknown(data['goal_id']!, _goalIdMeta),
      );
    } else if (isInserting) {
      context.missing(_goalIdMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavingsContribution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavingsContribution(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      goalId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}goal_id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      slot: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}slot'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
    );
  }

  @override
  $SavingsContributionsTable createAlias(String alias) {
    return $SavingsContributionsTable(attachedDatabase, alias);
  }
}

class SavingsContribution extends DataClass
    implements Insertable<SavingsContribution> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// → savings_goals.id。逻辑引用不建外键（pull 依赖序，§6.2）。
  final String goalId;

  /// 打卡日 `yyyy-MM-dd`。
  final String date;

  /// 金额（分，INTEGER，§5.1）。
  final int amountMinor;

  /// 365/52 周存钱法格子号。
  final int? slot;

  /// 备注。
  final String? note;
  const SavingsContribution({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.goalId,
    required this.date,
    required this.amountMinor,
    this.slot,
    this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['goal_id'] = Variable<String>(goalId);
    map['date'] = Variable<String>(date);
    map['amount_minor'] = Variable<int>(amountMinor);
    if (!nullToAbsent || slot != null) {
      map['slot'] = Variable<int>(slot);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    return map;
  }

  SavingsContributionsCompanion toCompanion(bool nullToAbsent) {
    return SavingsContributionsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      goalId: Value(goalId),
      date: Value(date),
      amountMinor: Value(amountMinor),
      slot: slot == null && nullToAbsent ? const Value.absent() : Value(slot),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
    );
  }

  factory SavingsContribution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavingsContribution(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      goalId: serializer.fromJson<String>(json['goalId']),
      date: serializer.fromJson<String>(json['date']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      slot: serializer.fromJson<int?>(json['slot']),
      note: serializer.fromJson<String?>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'goalId': serializer.toJson<String>(goalId),
      'date': serializer.toJson<String>(date),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'slot': serializer.toJson<int?>(slot),
      'note': serializer.toJson<String?>(note),
    };
  }

  SavingsContribution copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? goalId,
    String? date,
    int? amountMinor,
    Value<int?> slot = const Value.absent(),
    Value<String?> note = const Value.absent(),
  }) => SavingsContribution(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    goalId: goalId ?? this.goalId,
    date: date ?? this.date,
    amountMinor: amountMinor ?? this.amountMinor,
    slot: slot.present ? slot.value : this.slot,
    note: note.present ? note.value : this.note,
  );
  SavingsContribution copyWithCompanion(SavingsContributionsCompanion data) {
    return SavingsContribution(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      goalId: data.goalId.present ? data.goalId.value : this.goalId,
      date: data.date.present ? data.date.value : this.date,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      slot: data.slot.present ? data.slot.value : this.slot,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavingsContribution(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('date: $date, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('slot: $slot, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    goalId,
    date,
    amountMinor,
    slot,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavingsContribution &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.goalId == this.goalId &&
          other.date == this.date &&
          other.amountMinor == this.amountMinor &&
          other.slot == this.slot &&
          other.note == this.note);
}

class SavingsContributionsCompanion
    extends UpdateCompanion<SavingsContribution> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> goalId;
  final Value<String> date;
  final Value<int> amountMinor;
  final Value<int?> slot;
  final Value<String?> note;
  final Value<int> rowid;
  const SavingsContributionsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.goalId = const Value.absent(),
    this.date = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.slot = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavingsContributionsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String goalId,
    required String date,
    required int amountMinor,
    this.slot = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       goalId = Value(goalId),
       date = Value(date),
       amountMinor = Value(amountMinor);
  static Insertable<SavingsContribution> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? goalId,
    Expression<String>? date,
    Expression<int>? amountMinor,
    Expression<int>? slot,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (goalId != null) 'goal_id': goalId,
      if (date != null) 'date': date,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (slot != null) 'slot': slot,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavingsContributionsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? goalId,
    Value<String>? date,
    Value<int>? amountMinor,
    Value<int?>? slot,
    Value<String?>? note,
    Value<int>? rowid,
  }) {
    return SavingsContributionsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      goalId: goalId ?? this.goalId,
      date: date ?? this.date,
      amountMinor: amountMinor ?? this.amountMinor,
      slot: slot ?? this.slot,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (goalId.present) {
      map['goal_id'] = Variable<String>(goalId.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavingsContributionsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('goalId: $goalId, ')
          ..write('date: $date, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('slot: $slot, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CorrectionsTable extends Corrections
    with TableInfo<$CorrectionsTable, Correction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CorrectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineIdMeta = const VerificationMeta('lineId');
  @override
  late final GeneratedColumn<String> lineId = GeneratedColumn<String>(
    'line_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fieldMeta = const VerificationMeta('field');
  @override
  late final GeneratedColumn<String> field = GeneratedColumn<String>(
    'field',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _oldValueMeta = const VerificationMeta(
    'oldValue',
  );
  @override
  late final GeneratedColumn<String> oldValue = GeneratedColumn<String>(
    'old_value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _newValueMeta = const VerificationMeta(
    'newValue',
  );
  @override
  late final GeneratedColumn<String> newValue = GeneratedColumn<String>(
    'new_value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    lineId,
    field,
    oldValue,
    newValue,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'corrections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Correction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entryIdMeta);
    }
    if (data.containsKey('line_id')) {
      context.handle(
        _lineIdMeta,
        lineId.isAcceptableOrUnknown(data['line_id']!, _lineIdMeta),
      );
    }
    if (data.containsKey('field')) {
      context.handle(
        _fieldMeta,
        field.isAcceptableOrUnknown(data['field']!, _fieldMeta),
      );
    } else if (isInserting) {
      context.missing(_fieldMeta);
    }
    if (data.containsKey('old_value')) {
      context.handle(
        _oldValueMeta,
        oldValue.isAcceptableOrUnknown(data['old_value']!, _oldValueMeta),
      );
    } else if (isInserting) {
      context.missing(_oldValueMeta);
    }
    if (data.containsKey('new_value')) {
      context.handle(
        _newValueMeta,
        newValue.isAcceptableOrUnknown(data['new_value']!, _newValueMeta),
      );
    } else if (isInserting) {
      context.missing(_newValueMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Correction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Correction(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      )!,
      lineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}line_id'],
      ),
      field: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field'],
      )!,
      oldValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}old_value'],
      )!,
      newValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}new_value'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $CorrectionsTable createAlias(String alias) {
    return $CorrectionsTable(attachedDatabase, alias);
  }
}

class Correction extends DataClass implements Insertable<Correction> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 修正对象所在事件。
  final String entryId;

  /// 修正对象所在产出行（可空）。
  final String? lineId;

  /// kcal / amount / category / portion / …
  final String field;

  /// 字段级前值（TEXT 序列化）。
  final String oldValue;

  /// 字段级后值（TEXT 序列化）。
  final String newValue;

  /// user / ai_recalib。
  final String source;
  const Correction({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.entryId,
    this.lineId,
    required this.field,
    required this.oldValue,
    required this.newValue,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['entry_id'] = Variable<String>(entryId);
    if (!nullToAbsent || lineId != null) {
      map['line_id'] = Variable<String>(lineId);
    }
    map['field'] = Variable<String>(field);
    map['old_value'] = Variable<String>(oldValue);
    map['new_value'] = Variable<String>(newValue);
    map['source'] = Variable<String>(source);
    return map;
  }

  CorrectionsCompanion toCompanion(bool nullToAbsent) {
    return CorrectionsCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      entryId: Value(entryId),
      lineId: lineId == null && nullToAbsent
          ? const Value.absent()
          : Value(lineId),
      field: Value(field),
      oldValue: Value(oldValue),
      newValue: Value(newValue),
      source: Value(source),
    );
  }

  factory Correction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Correction(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String>(json['entryId']),
      lineId: serializer.fromJson<String?>(json['lineId']),
      field: serializer.fromJson<String>(json['field']),
      oldValue: serializer.fromJson<String>(json['oldValue']),
      newValue: serializer.fromJson<String>(json['newValue']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String>(entryId),
      'lineId': serializer.toJson<String?>(lineId),
      'field': serializer.toJson<String>(field),
      'oldValue': serializer.toJson<String>(oldValue),
      'newValue': serializer.toJson<String>(newValue),
      'source': serializer.toJson<String>(source),
    };
  }

  Correction copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? entryId,
    Value<String?> lineId = const Value.absent(),
    String? field,
    String? oldValue,
    String? newValue,
    String? source,
  }) => Correction(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    entryId: entryId ?? this.entryId,
    lineId: lineId.present ? lineId.value : this.lineId,
    field: field ?? this.field,
    oldValue: oldValue ?? this.oldValue,
    newValue: newValue ?? this.newValue,
    source: source ?? this.source,
  );
  Correction copyWithCompanion(CorrectionsCompanion data) {
    return Correction(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      lineId: data.lineId.present ? data.lineId.value : this.lineId,
      field: data.field.present ? data.field.value : this.field,
      oldValue: data.oldValue.present ? data.oldValue.value : this.oldValue,
      newValue: data.newValue.present ? data.newValue.value : this.newValue,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Correction(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('lineId: $lineId, ')
          ..write('field: $field, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    entryId,
    lineId,
    field,
    oldValue,
    newValue,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Correction &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.lineId == this.lineId &&
          other.field == this.field &&
          other.oldValue == this.oldValue &&
          other.newValue == this.newValue &&
          other.source == this.source);
}

class CorrectionsCompanion extends UpdateCompanion<Correction> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> entryId;
  final Value<String?> lineId;
  final Value<String> field;
  final Value<String> oldValue;
  final Value<String> newValue;
  final Value<String> source;
  final Value<int> rowid;
  const CorrectionsCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.lineId = const Value.absent(),
    this.field = const Value.absent(),
    this.oldValue = const Value.absent(),
    this.newValue = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CorrectionsCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String entryId,
    this.lineId = const Value.absent(),
    required String field,
    required String oldValue,
    required String newValue,
    required String source,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       entryId = Value(entryId),
       field = Value(field),
       oldValue = Value(oldValue),
       newValue = Value(newValue),
       source = Value(source);
  static Insertable<Correction> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? lineId,
    Expression<String>? field,
    Expression<String>? oldValue,
    Expression<String>? newValue,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (lineId != null) 'line_id': lineId,
      if (field != null) 'field': field,
      if (oldValue != null) 'old_value': oldValue,
      if (newValue != null) 'new_value': newValue,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CorrectionsCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? entryId,
    Value<String?>? lineId,
    Value<String>? field,
    Value<String>? oldValue,
    Value<String>? newValue,
    Value<String>? source,
    Value<int>? rowid,
  }) {
    return CorrectionsCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      lineId: lineId ?? this.lineId,
      field: field ?? this.field,
      oldValue: oldValue ?? this.oldValue,
      newValue: newValue ?? this.newValue,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (lineId.present) {
      map['line_id'] = Variable<String>(lineId.value);
    }
    if (field.present) {
      map['field'] = Variable<String>(field.value);
    }
    if (oldValue.present) {
      map['old_value'] = Variable<String>(oldValue.value);
    }
    if (newValue.present) {
      map['new_value'] = Variable<String>(newValue.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CorrectionsCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('lineId: $lineId, ')
          ..write('field: $field, ')
          ..write('oldValue: $oldValue, ')
          ..write('newValue: $newValue, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThemeProfilesTable extends ThemeProfiles
    with TableInfo<$ThemeProfilesTable, ThemeProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThemeProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVerMeta = const VerificationMeta(
    'schemaVer',
  );
  @override
  late final GeneratedColumn<int> schemaVer = GeneratedColumn<int>(
    'schema_ver',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokensMeta = const VerificationMeta('tokens');
  @override
  late final GeneratedColumn<String> tokens = GeneratedColumn<String>(
    'tokens',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _motionLevelMeta = const VerificationMeta(
    'motionLevel',
  );
  @override
  late final GeneratedColumn<String> motionLevel = GeneratedColumn<String>(
    'motion_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fontIdMeta = const VerificationMeta('fontId');
  @override
  late final GeneratedColumn<String> fontId = GeneratedColumn<String>(
    'font_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isPresetMeta = const VerificationMeta(
    'isPreset',
  );
  @override
  late final GeneratedColumn<bool> isPreset = GeneratedColumn<bool>(
    'is_preset',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_preset" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortMeta = const VerificationMeta('sort');
  @override
  late final GeneratedColumn<int> sort = GeneratedColumn<int>(
    'sort',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    tokens,
    motionLevel,
    fontId,
    isPreset,
    sort,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'theme_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThemeProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionMeta);
    }
    if (data.containsKey('schema_ver')) {
      context.handle(
        _schemaVerMeta,
        schemaVer.isAcceptableOrUnknown(data['schema_ver']!, _schemaVerMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('tokens')) {
      context.handle(
        _tokensMeta,
        tokens.isAcceptableOrUnknown(data['tokens']!, _tokensMeta),
      );
    } else if (isInserting) {
      context.missing(_tokensMeta);
    }
    if (data.containsKey('motion_level')) {
      context.handle(
        _motionLevelMeta,
        motionLevel.isAcceptableOrUnknown(
          data['motion_level']!,
          _motionLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_motionLevelMeta);
    }
    if (data.containsKey('font_id')) {
      context.handle(
        _fontIdMeta,
        fontId.isAcceptableOrUnknown(data['font_id']!, _fontIdMeta),
      );
    }
    if (data.containsKey('is_preset')) {
      context.handle(
        _isPresetMeta,
        isPreset.isAcceptableOrUnknown(data['is_preset']!, _isPresetMeta),
      );
    } else if (isInserting) {
      context.missing(_isPresetMeta);
    }
    if (data.containsKey('sort')) {
      context.handle(
        _sortMeta,
        sort.isAcceptableOrUnknown(data['sort']!, _sortMeta),
      );
    } else if (isInserting) {
      context.missing(_sortMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ThemeProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThemeProfile(
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}deleted_at'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      revision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision'],
      )!,
      schemaVer: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_ver'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      tokens: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tokens'],
      )!,
      motionLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}motion_level'],
      )!,
      fontId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}font_id'],
      ),
      isPreset: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_preset'],
      )!,
      sort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort'],
      )!,
    );
  }

  @override
  $ThemeProfilesTable createAlias(String alias) {
    return $ThemeProfilesTable(attachedDatabase, alias);
  }
}

class ThemeProfile extends DataClass implements Insertable<ThemeProfile> {
  /// created_at：UTC 毫秒 INTEGER（文档 §5.1 明确不用 DateTime，规避时区歧义）。
  final int createdAt;

  /// updated_at：UTC 毫秒 INTEGER，LWW（行级后写者胜）的排序依据之一。
  final int updatedAt;

  /// deleted_at：软删墓碑，NULL=未删；双端对齐后保留 90 天再物理 GC（§5.1）。
  /// 墓碑拒绝复活（§6.5 删除策略）。
  final int? deletedAt;

  /// hlc：定宽 HLC 编码（physical_ms 13 位:counter 6 位:device_id 12 位，
  /// 字典序=时间序，见 §6.3），SQLite/Postgres 均按 TEXT 比较即得全序。
  final String hlc;

  /// revision：本地自增起步，同步签发后升级为服务端版本（§5.1/§6.2 写路径）。
  final int revision;

  /// schema_ver：行级 schema 版本，默认 1；同步层按 schema_ver 协商容忍 N-1
  /// （§5.1/§6.4 行级只加列前向兼容）。
  final int schemaVer;

  /// device_id：最后写入设备（创建设备见各表语义，如 entries.device_id）。
  final String deviceId;

  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// 主题包名（内置 6 套：墨/纸/霓虹/奶油/森野/曜黑，§8.3）。
  final String name;

  /// 语义 token 集 JSON（§8.2 三层架构第 2 层）。
  final String tokens;

  /// 动效等级：off/reduced/full（§9.2 MotionLevel）。
  final String motionLevel;

  /// 字体 id（可空）。
  final String? fontId;

  /// 内置包不可删。
  final bool isPreset;

  /// 排序。
  final int sort;
  const ThemeProfile({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    required this.hlc,
    required this.revision,
    required this.schemaVer,
    required this.deviceId,
    required this.id,
    required this.name,
    required this.tokens,
    required this.motionLevel,
    this.fontId,
    required this.isPreset,
    required this.sort,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['hlc'] = Variable<String>(hlc);
    map['revision'] = Variable<int>(revision);
    map['schema_ver'] = Variable<int>(schemaVer);
    map['device_id'] = Variable<String>(deviceId);
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['tokens'] = Variable<String>(tokens);
    map['motion_level'] = Variable<String>(motionLevel);
    if (!nullToAbsent || fontId != null) {
      map['font_id'] = Variable<String>(fontId);
    }
    map['is_preset'] = Variable<bool>(isPreset);
    map['sort'] = Variable<int>(sort);
    return map;
  }

  ThemeProfilesCompanion toCompanion(bool nullToAbsent) {
    return ThemeProfilesCompanion(
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      hlc: Value(hlc),
      revision: Value(revision),
      schemaVer: Value(schemaVer),
      deviceId: Value(deviceId),
      id: Value(id),
      name: Value(name),
      tokens: Value(tokens),
      motionLevel: Value(motionLevel),
      fontId: fontId == null && nullToAbsent
          ? const Value.absent()
          : Value(fontId),
      isPreset: Value(isPreset),
      sort: Value(sort),
    );
  }

  factory ThemeProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThemeProfile(
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      hlc: serializer.fromJson<String>(json['hlc']),
      revision: serializer.fromJson<int>(json['revision']),
      schemaVer: serializer.fromJson<int>(json['schemaVer']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      tokens: serializer.fromJson<String>(json['tokens']),
      motionLevel: serializer.fromJson<String>(json['motionLevel']),
      fontId: serializer.fromJson<String?>(json['fontId']),
      isPreset: serializer.fromJson<bool>(json['isPreset']),
      sort: serializer.fromJson<int>(json['sort']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'hlc': serializer.toJson<String>(hlc),
      'revision': serializer.toJson<int>(revision),
      'schemaVer': serializer.toJson<int>(schemaVer),
      'deviceId': serializer.toJson<String>(deviceId),
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'tokens': serializer.toJson<String>(tokens),
      'motionLevel': serializer.toJson<String>(motionLevel),
      'fontId': serializer.toJson<String?>(fontId),
      'isPreset': serializer.toJson<bool>(isPreset),
      'sort': serializer.toJson<int>(sort),
    };
  }

  ThemeProfile copyWith({
    int? createdAt,
    int? updatedAt,
    Value<int?> deletedAt = const Value.absent(),
    String? hlc,
    int? revision,
    int? schemaVer,
    String? deviceId,
    String? id,
    String? name,
    String? tokens,
    String? motionLevel,
    Value<String?> fontId = const Value.absent(),
    bool? isPreset,
    int? sort,
  }) => ThemeProfile(
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    hlc: hlc ?? this.hlc,
    revision: revision ?? this.revision,
    schemaVer: schemaVer ?? this.schemaVer,
    deviceId: deviceId ?? this.deviceId,
    id: id ?? this.id,
    name: name ?? this.name,
    tokens: tokens ?? this.tokens,
    motionLevel: motionLevel ?? this.motionLevel,
    fontId: fontId.present ? fontId.value : this.fontId,
    isPreset: isPreset ?? this.isPreset,
    sort: sort ?? this.sort,
  );
  ThemeProfile copyWithCompanion(ThemeProfilesCompanion data) {
    return ThemeProfile(
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      revision: data.revision.present ? data.revision.value : this.revision,
      schemaVer: data.schemaVer.present ? data.schemaVer.value : this.schemaVer,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      tokens: data.tokens.present ? data.tokens.value : this.tokens,
      motionLevel: data.motionLevel.present
          ? data.motionLevel.value
          : this.motionLevel,
      fontId: data.fontId.present ? data.fontId.value : this.fontId,
      isPreset: data.isPreset.present ? data.isPreset.value : this.isPreset,
      sort: data.sort.present ? data.sort.value : this.sort,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThemeProfile(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('tokens: $tokens, ')
          ..write('motionLevel: $motionLevel, ')
          ..write('fontId: $fontId, ')
          ..write('isPreset: $isPreset, ')
          ..write('sort: $sort')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    createdAt,
    updatedAt,
    deletedAt,
    hlc,
    revision,
    schemaVer,
    deviceId,
    id,
    name,
    tokens,
    motionLevel,
    fontId,
    isPreset,
    sort,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThemeProfile &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.hlc == this.hlc &&
          other.revision == this.revision &&
          other.schemaVer == this.schemaVer &&
          other.deviceId == this.deviceId &&
          other.id == this.id &&
          other.name == this.name &&
          other.tokens == this.tokens &&
          other.motionLevel == this.motionLevel &&
          other.fontId == this.fontId &&
          other.isPreset == this.isPreset &&
          other.sort == this.sort);
}

class ThemeProfilesCompanion extends UpdateCompanion<ThemeProfile> {
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<String> hlc;
  final Value<int> revision;
  final Value<int> schemaVer;
  final Value<String> deviceId;
  final Value<String> id;
  final Value<String> name;
  final Value<String> tokens;
  final Value<String> motionLevel;
  final Value<String?> fontId;
  final Value<bool> isPreset;
  final Value<int> sort;
  final Value<int> rowid;
  const ThemeProfilesCompanion({
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.revision = const Value.absent(),
    this.schemaVer = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.tokens = const Value.absent(),
    this.motionLevel = const Value.absent(),
    this.fontId = const Value.absent(),
    this.isPreset = const Value.absent(),
    this.sort = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThemeProfilesCompanion.insert({
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required String hlc,
    required int revision,
    this.schemaVer = const Value.absent(),
    required String deviceId,
    required String id,
    required String name,
    required String tokens,
    required String motionLevel,
    this.fontId = const Value.absent(),
    required bool isPreset,
    required int sort,
    this.rowid = const Value.absent(),
  }) : createdAt = Value(createdAt),
       updatedAt = Value(updatedAt),
       hlc = Value(hlc),
       revision = Value(revision),
       deviceId = Value(deviceId),
       id = Value(id),
       name = Value(name),
       tokens = Value(tokens),
       motionLevel = Value(motionLevel),
       isPreset = Value(isPreset),
       sort = Value(sort);
  static Insertable<ThemeProfile> custom({
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<String>? hlc,
    Expression<int>? revision,
    Expression<int>? schemaVer,
    Expression<String>? deviceId,
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? tokens,
    Expression<String>? motionLevel,
    Expression<String>? fontId,
    Expression<bool>? isPreset,
    Expression<int>? sort,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (hlc != null) 'hlc': hlc,
      if (revision != null) 'revision': revision,
      if (schemaVer != null) 'schema_ver': schemaVer,
      if (deviceId != null) 'device_id': deviceId,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (tokens != null) 'tokens': tokens,
      if (motionLevel != null) 'motion_level': motionLevel,
      if (fontId != null) 'font_id': fontId,
      if (isPreset != null) 'is_preset': isPreset,
      if (sort != null) 'sort': sort,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThemeProfilesCompanion copyWith({
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int?>? deletedAt,
    Value<String>? hlc,
    Value<int>? revision,
    Value<int>? schemaVer,
    Value<String>? deviceId,
    Value<String>? id,
    Value<String>? name,
    Value<String>? tokens,
    Value<String>? motionLevel,
    Value<String?>? fontId,
    Value<bool>? isPreset,
    Value<int>? sort,
    Value<int>? rowid,
  }) {
    return ThemeProfilesCompanion(
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      hlc: hlc ?? this.hlc,
      revision: revision ?? this.revision,
      schemaVer: schemaVer ?? this.schemaVer,
      deviceId: deviceId ?? this.deviceId,
      id: id ?? this.id,
      name: name ?? this.name,
      tokens: tokens ?? this.tokens,
      motionLevel: motionLevel ?? this.motionLevel,
      fontId: fontId ?? this.fontId,
      isPreset: isPreset ?? this.isPreset,
      sort: sort ?? this.sort,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (schemaVer.present) {
      map['schema_ver'] = Variable<int>(schemaVer.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (tokens.present) {
      map['tokens'] = Variable<String>(tokens.value);
    }
    if (motionLevel.present) {
      map['motion_level'] = Variable<String>(motionLevel.value);
    }
    if (fontId.present) {
      map['font_id'] = Variable<String>(fontId.value);
    }
    if (isPreset.present) {
      map['is_preset'] = Variable<bool>(isPreset.value);
    }
    if (sort.present) {
      map['sort'] = Variable<int>(sort.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThemeProfilesCompanion(')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('hlc: $hlc, ')
          ..write('revision: $revision, ')
          ..write('schemaVer: $schemaVer, ')
          ..write('deviceId: $deviceId, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('tokens: $tokens, ')
          ..write('motionLevel: $motionLevel, ')
          ..write('fontId: $fontId, ')
          ..write('isPreset: $isPreset, ')
          ..write('sort: $sort, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DaySummariesTable extends DaySummaries
    with TableInfo<$DaySummariesTable, DaySummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DaySummariesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tzOffsetMinMeta = const VerificationMeta(
    'tzOffsetMin',
  );
  @override
  late final GeneratedColumn<int> tzOffsetMin = GeneratedColumn<int>(
    'tz_offset_min',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalInMeta = const VerificationMeta('kcalIn');
  @override
  late final GeneratedColumn<int> kcalIn = GeneratedColumn<int>(
    'kcal_in',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kcalOutMeta = const VerificationMeta(
    'kcalOut',
  );
  @override
  late final GeneratedColumn<int> kcalOut = GeneratedColumn<int>(
    'kcal_out',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _netKcalMeta = const VerificationMeta(
    'netKcal',
  );
  @override
  late final GeneratedColumn<int> netKcal = GeneratedColumn<int>(
    'net_kcal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spendMinorMeta = const VerificationMeta(
    'spendMinor',
  );
  @override
  late final GeneratedColumn<int> spendMinor = GeneratedColumn<int>(
    'spend_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _incomeMinorMeta = const VerificationMeta(
    'incomeMinor',
  );
  @override
  late final GeneratedColumn<int> incomeMinor = GeneratedColumn<int>(
    'income_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _todoDoneMeta = const VerificationMeta(
    'todoDone',
  );
  @override
  late final GeneratedColumn<int> todoDone = GeneratedColumn<int>(
    'todo_done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _todoTotalMeta = const VerificationMeta(
    'todoTotal',
  );
  @override
  late final GeneratedColumn<int> todoTotal = GeneratedColumn<int>(
    'todo_total',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _budgetSnapshotMeta = const VerificationMeta(
    'budgetSnapshot',
  );
  @override
  late final GeneratedColumn<String> budgetSnapshot = GeneratedColumn<String>(
    'budget_snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savingsProgressMeta = const VerificationMeta(
    'savingsProgress',
  );
  @override
  late final GeneratedColumn<String> savingsProgress = GeneratedColumn<String>(
    'savings_progress',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _builtAtMeta = const VerificationMeta(
    'builtAt',
  );
  @override
  late final GeneratedColumn<int> builtAt = GeneratedColumn<int>(
    'built_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    date,
    tzOffsetMin,
    kcalIn,
    kcalOut,
    netKcal,
    spendMinor,
    incomeMinor,
    todoDone,
    todoTotal,
    budgetSnapshot,
    savingsProgress,
    builtAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'day_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<DaySummary> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('tz_offset_min')) {
      context.handle(
        _tzOffsetMinMeta,
        tzOffsetMin.isAcceptableOrUnknown(
          data['tz_offset_min']!,
          _tzOffsetMinMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_tzOffsetMinMeta);
    }
    if (data.containsKey('kcal_in')) {
      context.handle(
        _kcalInMeta,
        kcalIn.isAcceptableOrUnknown(data['kcal_in']!, _kcalInMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalInMeta);
    }
    if (data.containsKey('kcal_out')) {
      context.handle(
        _kcalOutMeta,
        kcalOut.isAcceptableOrUnknown(data['kcal_out']!, _kcalOutMeta),
      );
    } else if (isInserting) {
      context.missing(_kcalOutMeta);
    }
    if (data.containsKey('net_kcal')) {
      context.handle(
        _netKcalMeta,
        netKcal.isAcceptableOrUnknown(data['net_kcal']!, _netKcalMeta),
      );
    } else if (isInserting) {
      context.missing(_netKcalMeta);
    }
    if (data.containsKey('spend_minor')) {
      context.handle(
        _spendMinorMeta,
        spendMinor.isAcceptableOrUnknown(data['spend_minor']!, _spendMinorMeta),
      );
    } else if (isInserting) {
      context.missing(_spendMinorMeta);
    }
    if (data.containsKey('income_minor')) {
      context.handle(
        _incomeMinorMeta,
        incomeMinor.isAcceptableOrUnknown(
          data['income_minor']!,
          _incomeMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_incomeMinorMeta);
    }
    if (data.containsKey('todo_done')) {
      context.handle(
        _todoDoneMeta,
        todoDone.isAcceptableOrUnknown(data['todo_done']!, _todoDoneMeta),
      );
    } else if (isInserting) {
      context.missing(_todoDoneMeta);
    }
    if (data.containsKey('todo_total')) {
      context.handle(
        _todoTotalMeta,
        todoTotal.isAcceptableOrUnknown(data['todo_total']!, _todoTotalMeta),
      );
    } else if (isInserting) {
      context.missing(_todoTotalMeta);
    }
    if (data.containsKey('budget_snapshot')) {
      context.handle(
        _budgetSnapshotMeta,
        budgetSnapshot.isAcceptableOrUnknown(
          data['budget_snapshot']!,
          _budgetSnapshotMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_budgetSnapshotMeta);
    }
    if (data.containsKey('savings_progress')) {
      context.handle(
        _savingsProgressMeta,
        savingsProgress.isAcceptableOrUnknown(
          data['savings_progress']!,
          _savingsProgressMeta,
        ),
      );
    }
    if (data.containsKey('built_at')) {
      context.handle(
        _builtAtMeta,
        builtAt.isAcceptableOrUnknown(data['built_at']!, _builtAtMeta),
      );
    } else if (isInserting) {
      context.missing(_builtAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {date};
  @override
  DaySummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DaySummary(
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}date'],
      )!,
      tzOffsetMin: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tz_offset_min'],
      )!,
      kcalIn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kcal_in'],
      )!,
      kcalOut: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kcal_out'],
      )!,
      netKcal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}net_kcal'],
      )!,
      spendMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}spend_minor'],
      )!,
      incomeMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}income_minor'],
      )!,
      todoDone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}todo_done'],
      )!,
      todoTotal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}todo_total'],
      )!,
      budgetSnapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}budget_snapshot'],
      )!,
      savingsProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}savings_progress'],
      ),
      builtAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}built_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $DaySummariesTable createAlias(String alias) {
    return $DaySummariesTable(attachedDatabase, alias);
  }
}

class DaySummary extends DataClass implements Insertable<DaySummary> {
  /// 本地日历日 `yyyy-MM-dd` 作主键（一天一投影行）。
  final String date;

  /// 时区偏移（分钟）。
  final int tzOffsetMin;

  /// 摄入 kcal。
  final int kcalIn;

  /// 消耗 kcal。
  final int kcalOut;

  /// 净 kcal。
  final int netKcal;

  /// 支出（分）。
  final int spendMinor;

  /// 收入（分）。
  final int incomeMinor;

  /// 待办完成数。
  final int todoDone;

  /// 待办总数。
  final int todoTotal;

  /// 预算余量快照 JSON。
  final String budgetSnapshot;

  /// 存钱目标进度快照 JSON（goal_id→{contributed_minor,target_minor}），
  /// P1 存钱上线后启用（§5.6）。
  final String? savingsProgress;

  /// 构建时刻 UTC ms。
  final int builtAt;

  /// 重建标记（bool 存 INTEGER）。
  final bool dirty;
  const DaySummary({
    required this.date,
    required this.tzOffsetMin,
    required this.kcalIn,
    required this.kcalOut,
    required this.netKcal,
    required this.spendMinor,
    required this.incomeMinor,
    required this.todoDone,
    required this.todoTotal,
    required this.budgetSnapshot,
    this.savingsProgress,
    required this.builtAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['date'] = Variable<String>(date);
    map['tz_offset_min'] = Variable<int>(tzOffsetMin);
    map['kcal_in'] = Variable<int>(kcalIn);
    map['kcal_out'] = Variable<int>(kcalOut);
    map['net_kcal'] = Variable<int>(netKcal);
    map['spend_minor'] = Variable<int>(spendMinor);
    map['income_minor'] = Variable<int>(incomeMinor);
    map['todo_done'] = Variable<int>(todoDone);
    map['todo_total'] = Variable<int>(todoTotal);
    map['budget_snapshot'] = Variable<String>(budgetSnapshot);
    if (!nullToAbsent || savingsProgress != null) {
      map['savings_progress'] = Variable<String>(savingsProgress);
    }
    map['built_at'] = Variable<int>(builtAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  DaySummariesCompanion toCompanion(bool nullToAbsent) {
    return DaySummariesCompanion(
      date: Value(date),
      tzOffsetMin: Value(tzOffsetMin),
      kcalIn: Value(kcalIn),
      kcalOut: Value(kcalOut),
      netKcal: Value(netKcal),
      spendMinor: Value(spendMinor),
      incomeMinor: Value(incomeMinor),
      todoDone: Value(todoDone),
      todoTotal: Value(todoTotal),
      budgetSnapshot: Value(budgetSnapshot),
      savingsProgress: savingsProgress == null && nullToAbsent
          ? const Value.absent()
          : Value(savingsProgress),
      builtAt: Value(builtAt),
      dirty: Value(dirty),
    );
  }

  factory DaySummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DaySummary(
      date: serializer.fromJson<String>(json['date']),
      tzOffsetMin: serializer.fromJson<int>(json['tzOffsetMin']),
      kcalIn: serializer.fromJson<int>(json['kcalIn']),
      kcalOut: serializer.fromJson<int>(json['kcalOut']),
      netKcal: serializer.fromJson<int>(json['netKcal']),
      spendMinor: serializer.fromJson<int>(json['spendMinor']),
      incomeMinor: serializer.fromJson<int>(json['incomeMinor']),
      todoDone: serializer.fromJson<int>(json['todoDone']),
      todoTotal: serializer.fromJson<int>(json['todoTotal']),
      budgetSnapshot: serializer.fromJson<String>(json['budgetSnapshot']),
      savingsProgress: serializer.fromJson<String?>(json['savingsProgress']),
      builtAt: serializer.fromJson<int>(json['builtAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'date': serializer.toJson<String>(date),
      'tzOffsetMin': serializer.toJson<int>(tzOffsetMin),
      'kcalIn': serializer.toJson<int>(kcalIn),
      'kcalOut': serializer.toJson<int>(kcalOut),
      'netKcal': serializer.toJson<int>(netKcal),
      'spendMinor': serializer.toJson<int>(spendMinor),
      'incomeMinor': serializer.toJson<int>(incomeMinor),
      'todoDone': serializer.toJson<int>(todoDone),
      'todoTotal': serializer.toJson<int>(todoTotal),
      'budgetSnapshot': serializer.toJson<String>(budgetSnapshot),
      'savingsProgress': serializer.toJson<String?>(savingsProgress),
      'builtAt': serializer.toJson<int>(builtAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  DaySummary copyWith({
    String? date,
    int? tzOffsetMin,
    int? kcalIn,
    int? kcalOut,
    int? netKcal,
    int? spendMinor,
    int? incomeMinor,
    int? todoDone,
    int? todoTotal,
    String? budgetSnapshot,
    Value<String?> savingsProgress = const Value.absent(),
    int? builtAt,
    bool? dirty,
  }) => DaySummary(
    date: date ?? this.date,
    tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
    kcalIn: kcalIn ?? this.kcalIn,
    kcalOut: kcalOut ?? this.kcalOut,
    netKcal: netKcal ?? this.netKcal,
    spendMinor: spendMinor ?? this.spendMinor,
    incomeMinor: incomeMinor ?? this.incomeMinor,
    todoDone: todoDone ?? this.todoDone,
    todoTotal: todoTotal ?? this.todoTotal,
    budgetSnapshot: budgetSnapshot ?? this.budgetSnapshot,
    savingsProgress: savingsProgress.present
        ? savingsProgress.value
        : this.savingsProgress,
    builtAt: builtAt ?? this.builtAt,
    dirty: dirty ?? this.dirty,
  );
  DaySummary copyWithCompanion(DaySummariesCompanion data) {
    return DaySummary(
      date: data.date.present ? data.date.value : this.date,
      tzOffsetMin: data.tzOffsetMin.present
          ? data.tzOffsetMin.value
          : this.tzOffsetMin,
      kcalIn: data.kcalIn.present ? data.kcalIn.value : this.kcalIn,
      kcalOut: data.kcalOut.present ? data.kcalOut.value : this.kcalOut,
      netKcal: data.netKcal.present ? data.netKcal.value : this.netKcal,
      spendMinor: data.spendMinor.present
          ? data.spendMinor.value
          : this.spendMinor,
      incomeMinor: data.incomeMinor.present
          ? data.incomeMinor.value
          : this.incomeMinor,
      todoDone: data.todoDone.present ? data.todoDone.value : this.todoDone,
      todoTotal: data.todoTotal.present ? data.todoTotal.value : this.todoTotal,
      budgetSnapshot: data.budgetSnapshot.present
          ? data.budgetSnapshot.value
          : this.budgetSnapshot,
      savingsProgress: data.savingsProgress.present
          ? data.savingsProgress.value
          : this.savingsProgress,
      builtAt: data.builtAt.present ? data.builtAt.value : this.builtAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DaySummary(')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('kcalIn: $kcalIn, ')
          ..write('kcalOut: $kcalOut, ')
          ..write('netKcal: $netKcal, ')
          ..write('spendMinor: $spendMinor, ')
          ..write('incomeMinor: $incomeMinor, ')
          ..write('todoDone: $todoDone, ')
          ..write('todoTotal: $todoTotal, ')
          ..write('budgetSnapshot: $budgetSnapshot, ')
          ..write('savingsProgress: $savingsProgress, ')
          ..write('builtAt: $builtAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    date,
    tzOffsetMin,
    kcalIn,
    kcalOut,
    netKcal,
    spendMinor,
    incomeMinor,
    todoDone,
    todoTotal,
    budgetSnapshot,
    savingsProgress,
    builtAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DaySummary &&
          other.date == this.date &&
          other.tzOffsetMin == this.tzOffsetMin &&
          other.kcalIn == this.kcalIn &&
          other.kcalOut == this.kcalOut &&
          other.netKcal == this.netKcal &&
          other.spendMinor == this.spendMinor &&
          other.incomeMinor == this.incomeMinor &&
          other.todoDone == this.todoDone &&
          other.todoTotal == this.todoTotal &&
          other.budgetSnapshot == this.budgetSnapshot &&
          other.savingsProgress == this.savingsProgress &&
          other.builtAt == this.builtAt &&
          other.dirty == this.dirty);
}

class DaySummariesCompanion extends UpdateCompanion<DaySummary> {
  final Value<String> date;
  final Value<int> tzOffsetMin;
  final Value<int> kcalIn;
  final Value<int> kcalOut;
  final Value<int> netKcal;
  final Value<int> spendMinor;
  final Value<int> incomeMinor;
  final Value<int> todoDone;
  final Value<int> todoTotal;
  final Value<String> budgetSnapshot;
  final Value<String?> savingsProgress;
  final Value<int> builtAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const DaySummariesCompanion({
    this.date = const Value.absent(),
    this.tzOffsetMin = const Value.absent(),
    this.kcalIn = const Value.absent(),
    this.kcalOut = const Value.absent(),
    this.netKcal = const Value.absent(),
    this.spendMinor = const Value.absent(),
    this.incomeMinor = const Value.absent(),
    this.todoDone = const Value.absent(),
    this.todoTotal = const Value.absent(),
    this.budgetSnapshot = const Value.absent(),
    this.savingsProgress = const Value.absent(),
    this.builtAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DaySummariesCompanion.insert({
    required String date,
    required int tzOffsetMin,
    required int kcalIn,
    required int kcalOut,
    required int netKcal,
    required int spendMinor,
    required int incomeMinor,
    required int todoDone,
    required int todoTotal,
    required String budgetSnapshot,
    this.savingsProgress = const Value.absent(),
    required int builtAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : date = Value(date),
       tzOffsetMin = Value(tzOffsetMin),
       kcalIn = Value(kcalIn),
       kcalOut = Value(kcalOut),
       netKcal = Value(netKcal),
       spendMinor = Value(spendMinor),
       incomeMinor = Value(incomeMinor),
       todoDone = Value(todoDone),
       todoTotal = Value(todoTotal),
       budgetSnapshot = Value(budgetSnapshot),
       builtAt = Value(builtAt);
  static Insertable<DaySummary> custom({
    Expression<String>? date,
    Expression<int>? tzOffsetMin,
    Expression<int>? kcalIn,
    Expression<int>? kcalOut,
    Expression<int>? netKcal,
    Expression<int>? spendMinor,
    Expression<int>? incomeMinor,
    Expression<int>? todoDone,
    Expression<int>? todoTotal,
    Expression<String>? budgetSnapshot,
    Expression<String>? savingsProgress,
    Expression<int>? builtAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (date != null) 'date': date,
      if (tzOffsetMin != null) 'tz_offset_min': tzOffsetMin,
      if (kcalIn != null) 'kcal_in': kcalIn,
      if (kcalOut != null) 'kcal_out': kcalOut,
      if (netKcal != null) 'net_kcal': netKcal,
      if (spendMinor != null) 'spend_minor': spendMinor,
      if (incomeMinor != null) 'income_minor': incomeMinor,
      if (todoDone != null) 'todo_done': todoDone,
      if (todoTotal != null) 'todo_total': todoTotal,
      if (budgetSnapshot != null) 'budget_snapshot': budgetSnapshot,
      if (savingsProgress != null) 'savings_progress': savingsProgress,
      if (builtAt != null) 'built_at': builtAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DaySummariesCompanion copyWith({
    Value<String>? date,
    Value<int>? tzOffsetMin,
    Value<int>? kcalIn,
    Value<int>? kcalOut,
    Value<int>? netKcal,
    Value<int>? spendMinor,
    Value<int>? incomeMinor,
    Value<int>? todoDone,
    Value<int>? todoTotal,
    Value<String>? budgetSnapshot,
    Value<String?>? savingsProgress,
    Value<int>? builtAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return DaySummariesCompanion(
      date: date ?? this.date,
      tzOffsetMin: tzOffsetMin ?? this.tzOffsetMin,
      kcalIn: kcalIn ?? this.kcalIn,
      kcalOut: kcalOut ?? this.kcalOut,
      netKcal: netKcal ?? this.netKcal,
      spendMinor: spendMinor ?? this.spendMinor,
      incomeMinor: incomeMinor ?? this.incomeMinor,
      todoDone: todoDone ?? this.todoDone,
      todoTotal: todoTotal ?? this.todoTotal,
      budgetSnapshot: budgetSnapshot ?? this.budgetSnapshot,
      savingsProgress: savingsProgress ?? this.savingsProgress,
      builtAt: builtAt ?? this.builtAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (tzOffsetMin.present) {
      map['tz_offset_min'] = Variable<int>(tzOffsetMin.value);
    }
    if (kcalIn.present) {
      map['kcal_in'] = Variable<int>(kcalIn.value);
    }
    if (kcalOut.present) {
      map['kcal_out'] = Variable<int>(kcalOut.value);
    }
    if (netKcal.present) {
      map['net_kcal'] = Variable<int>(netKcal.value);
    }
    if (spendMinor.present) {
      map['spend_minor'] = Variable<int>(spendMinor.value);
    }
    if (incomeMinor.present) {
      map['income_minor'] = Variable<int>(incomeMinor.value);
    }
    if (todoDone.present) {
      map['todo_done'] = Variable<int>(todoDone.value);
    }
    if (todoTotal.present) {
      map['todo_total'] = Variable<int>(todoTotal.value);
    }
    if (budgetSnapshot.present) {
      map['budget_snapshot'] = Variable<String>(budgetSnapshot.value);
    }
    if (savingsProgress.present) {
      map['savings_progress'] = Variable<String>(savingsProgress.value);
    }
    if (builtAt.present) {
      map['built_at'] = Variable<int>(builtAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DaySummariesCompanion(')
          ..write('date: $date, ')
          ..write('tzOffsetMin: $tzOffsetMin, ')
          ..write('kcalIn: $kcalIn, ')
          ..write('kcalOut: $kcalOut, ')
          ..write('netKcal: $netKcal, ')
          ..write('spendMinor: $spendMinor, ')
          ..write('incomeMinor: $incomeMinor, ')
          ..write('todoDone: $todoDone, ')
          ..write('todoTotal: $todoTotal, ')
          ..write('budgetSnapshot: $budgetSnapshot, ')
          ..write('savingsProgress: $savingsProgress, ')
          ..write('builtAt: $builtAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AiParsesTable extends AiParses with TableInfo<$AiParsesTable, AiParse> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiParsesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputKindMeta = const VerificationMeta(
    'inputKind',
  );
  @override
  late final GeneratedColumn<String> inputKind = GeneratedColumn<String>(
    'input_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputHashMeta = const VerificationMeta(
    'inputHash',
  );
  @override
  late final GeneratedColumn<String> inputHash = GeneratedColumn<String>(
    'input_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawOutputMeta = const VerificationMeta(
    'rawOutput',
  );
  @override
  late final GeneratedColumn<String> rawOutput = GeneratedColumn<String>(
    'raw_output',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latencyMsMeta = const VerificationMeta(
    'latencyMs',
  );
  @override
  late final GeneratedColumn<int> latencyMs = GeneratedColumn<int>(
    'latency_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costMeta = const VerificationMeta('cost');
  @override
  late final GeneratedColumn<int> cost = GeneratedColumn<int>(
    'cost',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _confidenceMeta = const VerificationMeta(
    'confidence',
  );
  @override
  late final GeneratedColumn<double> confidence = GeneratedColumn<double>(
    'confidence',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    inputKind,
    inputHash,
    provider,
    model,
    rawOutput,
    latencyMs,
    cost,
    confidence,
    promptVersion,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_parses';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiParse> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('input_kind')) {
      context.handle(
        _inputKindMeta,
        inputKind.isAcceptableOrUnknown(data['input_kind']!, _inputKindMeta),
      );
    } else if (isInserting) {
      context.missing(_inputKindMeta);
    }
    if (data.containsKey('input_hash')) {
      context.handle(
        _inputHashMeta,
        inputHash.isAcceptableOrUnknown(data['input_hash']!, _inputHashMeta),
      );
    } else if (isInserting) {
      context.missing(_inputHashMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    } else if (isInserting) {
      context.missing(_providerMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('raw_output')) {
      context.handle(
        _rawOutputMeta,
        rawOutput.isAcceptableOrUnknown(data['raw_output']!, _rawOutputMeta),
      );
    } else if (isInserting) {
      context.missing(_rawOutputMeta);
    }
    if (data.containsKey('latency_ms')) {
      context.handle(
        _latencyMsMeta,
        latencyMs.isAcceptableOrUnknown(data['latency_ms']!, _latencyMsMeta),
      );
    } else if (isInserting) {
      context.missing(_latencyMsMeta);
    }
    if (data.containsKey('cost')) {
      context.handle(
        _costMeta,
        cost.isAcceptableOrUnknown(data['cost']!, _costMeta),
      );
    } else if (isInserting) {
      context.missing(_costMeta);
    }
    if (data.containsKey('confidence')) {
      context.handle(
        _confidenceMeta,
        confidence.isAcceptableOrUnknown(data['confidence']!, _confidenceMeta),
      );
    } else if (isInserting) {
      context.missing(_confidenceMeta);
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_promptVersionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AiParse map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiParse(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      inputKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_kind'],
      )!,
      inputHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_hash'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      rawOutput: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_output'],
      )!,
      latencyMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}latency_ms'],
      )!,
      cost: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost'],
      )!,
      confidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}confidence'],
      )!,
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      )!,
    );
  }

  @override
  $AiParsesTable createAlias(String alias) {
    return $AiParsesTable(attachedDatabase, alias);
  }
}

class AiParse extends DataClass implements Insertable<AiParse> {
  /// UUIDv7 主键（应用层生成，§5.1）。
  final String id;

  /// text / voice / photo。
  final String inputKind;

  /// sha256(规范化输入)=缓存键。
  final String inputHash;

  /// 供应商（可 A/B 对比）。
  final String provider;

  /// 模型名。
  final String model;

  /// 原始结构化输出 JSON（可回放排查）。
  final String rawOutput;

  /// 延迟（毫秒）。
  final int latencyMs;

  /// 成本（微元计，可审计）。
  final int cost;

  /// 解析置信度。
  final double confidence;

  /// 提示词版本。
  final String promptVersion;
  const AiParse({
    required this.id,
    required this.inputKind,
    required this.inputHash,
    required this.provider,
    required this.model,
    required this.rawOutput,
    required this.latencyMs,
    required this.cost,
    required this.confidence,
    required this.promptVersion,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['input_kind'] = Variable<String>(inputKind);
    map['input_hash'] = Variable<String>(inputHash);
    map['provider'] = Variable<String>(provider);
    map['model'] = Variable<String>(model);
    map['raw_output'] = Variable<String>(rawOutput);
    map['latency_ms'] = Variable<int>(latencyMs);
    map['cost'] = Variable<int>(cost);
    map['confidence'] = Variable<double>(confidence);
    map['prompt_version'] = Variable<String>(promptVersion);
    return map;
  }

  AiParsesCompanion toCompanion(bool nullToAbsent) {
    return AiParsesCompanion(
      id: Value(id),
      inputKind: Value(inputKind),
      inputHash: Value(inputHash),
      provider: Value(provider),
      model: Value(model),
      rawOutput: Value(rawOutput),
      latencyMs: Value(latencyMs),
      cost: Value(cost),
      confidence: Value(confidence),
      promptVersion: Value(promptVersion),
    );
  }

  factory AiParse.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiParse(
      id: serializer.fromJson<String>(json['id']),
      inputKind: serializer.fromJson<String>(json['inputKind']),
      inputHash: serializer.fromJson<String>(json['inputHash']),
      provider: serializer.fromJson<String>(json['provider']),
      model: serializer.fromJson<String>(json['model']),
      rawOutput: serializer.fromJson<String>(json['rawOutput']),
      latencyMs: serializer.fromJson<int>(json['latencyMs']),
      cost: serializer.fromJson<int>(json['cost']),
      confidence: serializer.fromJson<double>(json['confidence']),
      promptVersion: serializer.fromJson<String>(json['promptVersion']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'inputKind': serializer.toJson<String>(inputKind),
      'inputHash': serializer.toJson<String>(inputHash),
      'provider': serializer.toJson<String>(provider),
      'model': serializer.toJson<String>(model),
      'rawOutput': serializer.toJson<String>(rawOutput),
      'latencyMs': serializer.toJson<int>(latencyMs),
      'cost': serializer.toJson<int>(cost),
      'confidence': serializer.toJson<double>(confidence),
      'promptVersion': serializer.toJson<String>(promptVersion),
    };
  }

  AiParse copyWith({
    String? id,
    String? inputKind,
    String? inputHash,
    String? provider,
    String? model,
    String? rawOutput,
    int? latencyMs,
    int? cost,
    double? confidence,
    String? promptVersion,
  }) => AiParse(
    id: id ?? this.id,
    inputKind: inputKind ?? this.inputKind,
    inputHash: inputHash ?? this.inputHash,
    provider: provider ?? this.provider,
    model: model ?? this.model,
    rawOutput: rawOutput ?? this.rawOutput,
    latencyMs: latencyMs ?? this.latencyMs,
    cost: cost ?? this.cost,
    confidence: confidence ?? this.confidence,
    promptVersion: promptVersion ?? this.promptVersion,
  );
  AiParse copyWithCompanion(AiParsesCompanion data) {
    return AiParse(
      id: data.id.present ? data.id.value : this.id,
      inputKind: data.inputKind.present ? data.inputKind.value : this.inputKind,
      inputHash: data.inputHash.present ? data.inputHash.value : this.inputHash,
      provider: data.provider.present ? data.provider.value : this.provider,
      model: data.model.present ? data.model.value : this.model,
      rawOutput: data.rawOutput.present ? data.rawOutput.value : this.rawOutput,
      latencyMs: data.latencyMs.present ? data.latencyMs.value : this.latencyMs,
      cost: data.cost.present ? data.cost.value : this.cost,
      confidence: data.confidence.present
          ? data.confidence.value
          : this.confidence,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiParse(')
          ..write('id: $id, ')
          ..write('inputKind: $inputKind, ')
          ..write('inputHash: $inputHash, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('rawOutput: $rawOutput, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('cost: $cost, ')
          ..write('confidence: $confidence, ')
          ..write('promptVersion: $promptVersion')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    inputKind,
    inputHash,
    provider,
    model,
    rawOutput,
    latencyMs,
    cost,
    confidence,
    promptVersion,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiParse &&
          other.id == this.id &&
          other.inputKind == this.inputKind &&
          other.inputHash == this.inputHash &&
          other.provider == this.provider &&
          other.model == this.model &&
          other.rawOutput == this.rawOutput &&
          other.latencyMs == this.latencyMs &&
          other.cost == this.cost &&
          other.confidence == this.confidence &&
          other.promptVersion == this.promptVersion);
}

class AiParsesCompanion extends UpdateCompanion<AiParse> {
  final Value<String> id;
  final Value<String> inputKind;
  final Value<String> inputHash;
  final Value<String> provider;
  final Value<String> model;
  final Value<String> rawOutput;
  final Value<int> latencyMs;
  final Value<int> cost;
  final Value<double> confidence;
  final Value<String> promptVersion;
  final Value<int> rowid;
  const AiParsesCompanion({
    this.id = const Value.absent(),
    this.inputKind = const Value.absent(),
    this.inputHash = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.rawOutput = const Value.absent(),
    this.latencyMs = const Value.absent(),
    this.cost = const Value.absent(),
    this.confidence = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiParsesCompanion.insert({
    required String id,
    required String inputKind,
    required String inputHash,
    required String provider,
    required String model,
    required String rawOutput,
    required int latencyMs,
    required int cost,
    required double confidence,
    required String promptVersion,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       inputKind = Value(inputKind),
       inputHash = Value(inputHash),
       provider = Value(provider),
       model = Value(model),
       rawOutput = Value(rawOutput),
       latencyMs = Value(latencyMs),
       cost = Value(cost),
       confidence = Value(confidence),
       promptVersion = Value(promptVersion);
  static Insertable<AiParse> custom({
    Expression<String>? id,
    Expression<String>? inputKind,
    Expression<String>? inputHash,
    Expression<String>? provider,
    Expression<String>? model,
    Expression<String>? rawOutput,
    Expression<int>? latencyMs,
    Expression<int>? cost,
    Expression<double>? confidence,
    Expression<String>? promptVersion,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (inputKind != null) 'input_kind': inputKind,
      if (inputHash != null) 'input_hash': inputHash,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (rawOutput != null) 'raw_output': rawOutput,
      if (latencyMs != null) 'latency_ms': latencyMs,
      if (cost != null) 'cost': cost,
      if (confidence != null) 'confidence': confidence,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiParsesCompanion copyWith({
    Value<String>? id,
    Value<String>? inputKind,
    Value<String>? inputHash,
    Value<String>? provider,
    Value<String>? model,
    Value<String>? rawOutput,
    Value<int>? latencyMs,
    Value<int>? cost,
    Value<double>? confidence,
    Value<String>? promptVersion,
    Value<int>? rowid,
  }) {
    return AiParsesCompanion(
      id: id ?? this.id,
      inputKind: inputKind ?? this.inputKind,
      inputHash: inputHash ?? this.inputHash,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      rawOutput: rawOutput ?? this.rawOutput,
      latencyMs: latencyMs ?? this.latencyMs,
      cost: cost ?? this.cost,
      confidence: confidence ?? this.confidence,
      promptVersion: promptVersion ?? this.promptVersion,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (inputKind.present) {
      map['input_kind'] = Variable<String>(inputKind.value);
    }
    if (inputHash.present) {
      map['input_hash'] = Variable<String>(inputHash.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (rawOutput.present) {
      map['raw_output'] = Variable<String>(rawOutput.value);
    }
    if (latencyMs.present) {
      map['latency_ms'] = Variable<int>(latencyMs.value);
    }
    if (cost.present) {
      map['cost'] = Variable<int>(cost.value);
    }
    if (confidence.present) {
      map['confidence'] = Variable<double>(confidence.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiParsesCompanion(')
          ..write('id: $id, ')
          ..write('inputKind: $inputKind, ')
          ..write('inputHash: $inputHash, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('rawOutput: $rawOutput, ')
          ..write('latencyMs: $latencyMs, ')
          ..write('cost: $cost, ')
          ..write('confidence: $confidence, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncOutboxTable extends SyncOutbox
    with TableInfo<$SyncOutboxTable, SyncOutboxItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTableMeta = const VerificationMeta(
    'targetTable',
  );
  @override
  late final GeneratedColumn<String> targetTable = GeneratedColumn<String>(
    'table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<String> rowId = GeneratedColumn<String>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ackedAtMeta = const VerificationMeta(
    'ackedAt',
  );
  @override
  late final GeneratedColumn<int> ackedAt = GeneratedColumn<int>(
    'acked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetTable,
    rowId,
    op,
    payload,
    baseRevision,
    hlc,
    createdAt,
    ackedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncOutboxItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('table_name')) {
      context.handle(
        _targetTableMeta,
        targetTable.isAcceptableOrUnknown(
          data['table_name']!,
          _targetTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetTableMeta);
    }
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    } else if (isInserting) {
      context.missing(_rowIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('acked_at')) {
      context.handle(
        _ackedAtMeta,
        ackedAt.isAcceptableOrUnknown(data['acked_at']!, _ackedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncOutboxItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncOutboxItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      targetTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name'],
      )!,
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}row_id'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      ),
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      ackedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}acked_at'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxItem extends DataClass implements Insertable<SyncOutboxItem> {
  /// 幂等键（服务端据此去重，§6.2）。
  final String id;

  /// 目标表名。
  ///
  /// Dart getter 名不能叫 `tableName`——drift 的 `Table.tableName` 是框架
  /// 自有成员（自定义 SQL 表名钩子），列 getter 与之冲突会破坏生成代码；
  /// 故 getter 取 `targetTable`，用 `.named('table_name')` 冻结 SQL 列名
  /// 与文档 §5.6 表结构一致。
  final String targetTable;

  /// 目标行 id。
  final String rowId;

  /// upsert / delete。
  final String op;

  /// 行快照 JSON。
  final String payload;

  /// 乐观校验用基线版本。
  final int? baseRevision;

  /// 入队时 HLC（定宽编码，§6.3）。
  final String hlc;

  /// 入队时刻 UTC ms。
  final int createdAt;

  /// 确认时刻（NULL=未 ack；§6.2 写路径回写）。
  final int? ackedAt;
  const SyncOutboxItem({
    required this.id,
    required this.targetTable,
    required this.rowId,
    required this.op,
    required this.payload,
    this.baseRevision,
    required this.hlc,
    required this.createdAt,
    this.ackedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['table_name'] = Variable<String>(targetTable);
    map['row_id'] = Variable<String>(rowId);
    map['op'] = Variable<String>(op);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || baseRevision != null) {
      map['base_revision'] = Variable<int>(baseRevision);
    }
    map['hlc'] = Variable<String>(hlc);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || ackedAt != null) {
      map['acked_at'] = Variable<int>(ackedAt);
    }
    return map;
  }

  SyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return SyncOutboxCompanion(
      id: Value(id),
      targetTable: Value(targetTable),
      rowId: Value(rowId),
      op: Value(op),
      payload: Value(payload),
      baseRevision: baseRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(baseRevision),
      hlc: Value(hlc),
      createdAt: Value(createdAt),
      ackedAt: ackedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(ackedAt),
    );
  }

  factory SyncOutboxItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncOutboxItem(
      id: serializer.fromJson<String>(json['id']),
      targetTable: serializer.fromJson<String>(json['targetTable']),
      rowId: serializer.fromJson<String>(json['rowId']),
      op: serializer.fromJson<String>(json['op']),
      payload: serializer.fromJson<String>(json['payload']),
      baseRevision: serializer.fromJson<int?>(json['baseRevision']),
      hlc: serializer.fromJson<String>(json['hlc']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      ackedAt: serializer.fromJson<int?>(json['ackedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'targetTable': serializer.toJson<String>(targetTable),
      'rowId': serializer.toJson<String>(rowId),
      'op': serializer.toJson<String>(op),
      'payload': serializer.toJson<String>(payload),
      'baseRevision': serializer.toJson<int?>(baseRevision),
      'hlc': serializer.toJson<String>(hlc),
      'createdAt': serializer.toJson<int>(createdAt),
      'ackedAt': serializer.toJson<int?>(ackedAt),
    };
  }

  SyncOutboxItem copyWith({
    String? id,
    String? targetTable,
    String? rowId,
    String? op,
    String? payload,
    Value<int?> baseRevision = const Value.absent(),
    String? hlc,
    int? createdAt,
    Value<int?> ackedAt = const Value.absent(),
  }) => SyncOutboxItem(
    id: id ?? this.id,
    targetTable: targetTable ?? this.targetTable,
    rowId: rowId ?? this.rowId,
    op: op ?? this.op,
    payload: payload ?? this.payload,
    baseRevision: baseRevision.present ? baseRevision.value : this.baseRevision,
    hlc: hlc ?? this.hlc,
    createdAt: createdAt ?? this.createdAt,
    ackedAt: ackedAt.present ? ackedAt.value : this.ackedAt,
  );
  SyncOutboxItem copyWithCompanion(SyncOutboxCompanion data) {
    return SyncOutboxItem(
      id: data.id.present ? data.id.value : this.id,
      targetTable: data.targetTable.present
          ? data.targetTable.value
          : this.targetTable,
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      op: data.op.present ? data.op.value : this.op,
      payload: data.payload.present ? data.payload.value : this.payload,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      ackedAt: data.ackedAt.present ? data.ackedAt.value : this.ackedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxItem(')
          ..write('id: $id, ')
          ..write('targetTable: $targetTable, ')
          ..write('rowId: $rowId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('hlc: $hlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('ackedAt: $ackedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetTable,
    rowId,
    op,
    payload,
    baseRevision,
    hlc,
    createdAt,
    ackedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncOutboxItem &&
          other.id == this.id &&
          other.targetTable == this.targetTable &&
          other.rowId == this.rowId &&
          other.op == this.op &&
          other.payload == this.payload &&
          other.baseRevision == this.baseRevision &&
          other.hlc == this.hlc &&
          other.createdAt == this.createdAt &&
          other.ackedAt == this.ackedAt);
}

class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxItem> {
  final Value<String> id;
  final Value<String> targetTable;
  final Value<String> rowId;
  final Value<String> op;
  final Value<String> payload;
  final Value<int?> baseRevision;
  final Value<String> hlc;
  final Value<int> createdAt;
  final Value<int?> ackedAt;
  final Value<int> rowid;
  const SyncOutboxCompanion({
    this.id = const Value.absent(),
    this.targetTable = const Value.absent(),
    this.rowId = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.hlc = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.ackedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String id,
    required String targetTable,
    required String rowId,
    required String op,
    required String payload,
    this.baseRevision = const Value.absent(),
    required String hlc,
    required int createdAt,
    this.ackedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       targetTable = Value(targetTable),
       rowId = Value(rowId),
       op = Value(op),
       payload = Value(payload),
       hlc = Value(hlc),
       createdAt = Value(createdAt);
  static Insertable<SyncOutboxItem> custom({
    Expression<String>? id,
    Expression<String>? targetTable,
    Expression<String>? rowId,
    Expression<String>? op,
    Expression<String>? payload,
    Expression<int>? baseRevision,
    Expression<String>? hlc,
    Expression<int>? createdAt,
    Expression<int>? ackedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetTable != null) 'table_name': targetTable,
      if (rowId != null) 'row_id': rowId,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (hlc != null) 'hlc': hlc,
      if (createdAt != null) 'created_at': createdAt,
      if (ackedAt != null) 'acked_at': ackedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncOutboxCompanion copyWith({
    Value<String>? id,
    Value<String>? targetTable,
    Value<String>? rowId,
    Value<String>? op,
    Value<String>? payload,
    Value<int?>? baseRevision,
    Value<String>? hlc,
    Value<int>? createdAt,
    Value<int?>? ackedAt,
    Value<int>? rowid,
  }) {
    return SyncOutboxCompanion(
      id: id ?? this.id,
      targetTable: targetTable ?? this.targetTable,
      rowId: rowId ?? this.rowId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      baseRevision: baseRevision ?? this.baseRevision,
      hlc: hlc ?? this.hlc,
      createdAt: createdAt ?? this.createdAt,
      ackedAt: ackedAt ?? this.ackedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (targetTable.present) {
      map['table_name'] = Variable<String>(targetTable.value);
    }
    if (rowId.present) {
      map['row_id'] = Variable<String>(rowId.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (ackedAt.present) {
      map['acked_at'] = Variable<int>(ackedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('id: $id, ')
          ..write('targetTable: $targetTable, ')
          ..write('rowId: $rowId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('hlc: $hlc, ')
          ..write('createdAt: $createdAt, ')
          ..write('ackedAt: $ackedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetTableMeta = const VerificationMeta(
    'targetTable',
  );
  @override
  late final GeneratedColumn<String> targetTable = GeneratedColumn<String>(
    'table_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pullHlcMeta = const VerificationMeta(
    'pullHlc',
  );
  @override
  late final GeneratedColumn<String> pullHlc = GeneratedColumn<String>(
    'pull_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [deviceId, targetTable, pullHlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('table_name')) {
      context.handle(
        _targetTableMeta,
        targetTable.isAcceptableOrUnknown(
          data['table_name']!,
          _targetTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetTableMeta);
    }
    if (data.containsKey('pull_hlc')) {
      context.handle(
        _pullHlcMeta,
        pullHlc.isAcceptableOrUnknown(data['pull_hlc']!, _pullHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_pullHlcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, targetTable};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      targetTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}table_name'],
      )!,
      pullHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pull_hlc'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  /// 设备 id。
  final String deviceId;

  /// 表名。
  ///
  /// 同 [SyncOutbox.targetTable]：getter 避让 drift `Table.tableName` 钩子，
  /// SQL 列名经 `.named('table_name')` 保持 §5.6 文档口径。
  final String targetTable;

  /// 已拉取到的 HLC 水位（§6.2 since_hlc）。
  final String pullHlc;
  const SyncCursor({
    required this.deviceId,
    required this.targetTable,
    required this.pullHlc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['table_name'] = Variable<String>(targetTable);
    map['pull_hlc'] = Variable<String>(pullHlc);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      deviceId: Value(deviceId),
      targetTable: Value(targetTable),
      pullHlc: Value(pullHlc),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      targetTable: serializer.fromJson<String>(json['targetTable']),
      pullHlc: serializer.fromJson<String>(json['pullHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'targetTable': serializer.toJson<String>(targetTable),
      'pullHlc': serializer.toJson<String>(pullHlc),
    };
  }

  SyncCursor copyWith({
    String? deviceId,
    String? targetTable,
    String? pullHlc,
  }) => SyncCursor(
    deviceId: deviceId ?? this.deviceId,
    targetTable: targetTable ?? this.targetTable,
    pullHlc: pullHlc ?? this.pullHlc,
  );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      targetTable: data.targetTable.present
          ? data.targetTable.value
          : this.targetTable,
      pullHlc: data.pullHlc.present ? data.pullHlc.value : this.pullHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('deviceId: $deviceId, ')
          ..write('targetTable: $targetTable, ')
          ..write('pullHlc: $pullHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, targetTable, pullHlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.deviceId == this.deviceId &&
          other.targetTable == this.targetTable &&
          other.pullHlc == this.pullHlc);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> deviceId;
  final Value<String> targetTable;
  final Value<String> pullHlc;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.deviceId = const Value.absent(),
    this.targetTable = const Value.absent(),
    this.pullHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String deviceId,
    required String targetTable,
    required String pullHlc,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       targetTable = Value(targetTable),
       pullHlc = Value(pullHlc);
  static Insertable<SyncCursor> custom({
    Expression<String>? deviceId,
    Expression<String>? targetTable,
    Expression<String>? pullHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (targetTable != null) 'table_name': targetTable,
      if (pullHlc != null) 'pull_hlc': pullHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? targetTable,
    Value<String>? pullHlc,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      deviceId: deviceId ?? this.deviceId,
      targetTable: targetTable ?? this.targetTable,
      pullHlc: pullHlc ?? this.pullHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (targetTable.present) {
      map['table_name'] = Variable<String>(targetTable.value);
    }
    if (pullHlc.present) {
      map['pull_hlc'] = Variable<String>(pullHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('targetTable: $targetTable, ')
          ..write('pullHlc: $pullHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  /// 配置键。
  final String key;

  /// 配置值（JSON）。
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _platformMeta = const VerificationMeta(
    'platform',
  );
  @override
  late final GeneratedColumn<String> platform = GeneratedColumn<String>(
    'platform',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revokedAtMeta = const VerificationMeta(
    'revokedAt',
  );
  @override
  late final GeneratedColumn<int> revokedAt = GeneratedColumn<int>(
    'revoked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    platform,
    createdAt,
    lastSeenAt,
    revokedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('platform')) {
      context.handle(
        _platformMeta,
        platform.isAcceptableOrUnknown(data['platform']!, _platformMeta),
      );
    } else if (isInserting) {
      context.missing(_platformMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastSeenAtMeta);
    }
    if (data.containsKey('revoked_at')) {
      context.handle(
        _revokedAtMeta,
        revokedAt.isAcceptableOrUnknown(data['revoked_at']!, _revokedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      platform: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}platform'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      )!,
      revokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revoked_at'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  /// = device_id（与 §5.1 公共列 device_id 同域）。
  final String id;

  /// 设备名。
  final String name;

  /// 平台（ios/android/…）。
  final String platform;

  /// 注册时刻 UTC ms。
  final int createdAt;

  /// 最后在线时刻 UTC ms。
  final int lastSeenAt;

  /// 下线/吊销时刻（NULL=未吊销）。
  final int? revokedAt;
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.revokedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['platform'] = Variable<String>(platform);
    map['created_at'] = Variable<int>(createdAt);
    map['last_seen_at'] = Variable<int>(lastSeenAt);
    if (!nullToAbsent || revokedAt != null) {
      map['revoked_at'] = Variable<int>(revokedAt);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      name: Value(name),
      platform: Value(platform),
      createdAt: Value(createdAt),
      lastSeenAt: Value(lastSeenAt),
      revokedAt: revokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(revokedAt),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      platform: serializer.fromJson<String>(json['platform']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastSeenAt: serializer.fromJson<int>(json['lastSeenAt']),
      revokedAt: serializer.fromJson<int?>(json['revokedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'platform': serializer.toJson<String>(platform),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastSeenAt': serializer.toJson<int>(lastSeenAt),
      'revokedAt': serializer.toJson<int?>(revokedAt),
    };
  }

  Device copyWith({
    String? id,
    String? name,
    String? platform,
    int? createdAt,
    int? lastSeenAt,
    Value<int?> revokedAt = const Value.absent(),
  }) => Device(
    id: id ?? this.id,
    name: name ?? this.name,
    platform: platform ?? this.platform,
    createdAt: createdAt ?? this.createdAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    revokedAt: revokedAt.present ? revokedAt.value : this.revokedAt,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      platform: data.platform.present ? data.platform.value : this.platform,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      revokedAt: data.revokedAt.present ? data.revokedAt.value : this.revokedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revokedAt: $revokedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, platform, createdAt, lastSeenAt, revokedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.id == this.id &&
          other.name == this.name &&
          other.platform == this.platform &&
          other.createdAt == this.createdAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.revokedAt == this.revokedAt);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> platform;
  final Value<int> createdAt;
  final Value<int> lastSeenAt;
  final Value<int?> revokedAt;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.platform = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.revokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String id,
    required String name,
    required String platform,
    required int createdAt,
    required int lastSeenAt,
    this.revokedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       platform = Value(platform),
       createdAt = Value(createdAt),
       lastSeenAt = Value(lastSeenAt);
  static Insertable<Device> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? platform,
    Expression<int>? createdAt,
    Expression<int>? lastSeenAt,
    Expression<int>? revokedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (platform != null) 'platform': platform,
      if (createdAt != null) 'created_at': createdAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (revokedAt != null) 'revoked_at': revokedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? platform,
    Value<int>? createdAt,
    Value<int>? lastSeenAt,
    Value<int?>? revokedAt,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      createdAt: createdAt ?? this.createdAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      revokedAt: revokedAt ?? this.revokedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (platform.present) {
      map['platform'] = Variable<String>(platform.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (revokedAt.present) {
      map['revoked_at'] = Variable<int>(revokedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('platform: $platform, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('revokedAt: $revokedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AttachmentsTable extends Attachments
    with TableInfo<$AttachmentsTable, Attachment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AttachmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryIdMeta = const VerificationMeta(
    'entryId',
  );
  @override
  late final GeneratedColumn<String> entryId = GeneratedColumn<String>(
    'entry_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeMeta = const VerificationMeta('mime');
  @override
  late final GeneratedColumn<String> mime = GeneratedColumn<String>(
    'mime',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _blobRefMeta = const VerificationMeta(
    'blobRef',
  );
  @override
  late final GeneratedColumn<String> blobRef = GeneratedColumn<String>(
    'blob_ref',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _burnedAtMeta = const VerificationMeta(
    'burnedAt',
  );
  @override
  late final GeneratedColumn<int> burnedAt = GeneratedColumn<int>(
    'burned_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    entryId,
    contentHash,
    kind,
    mime,
    sizeBytes,
    localPath,
    blobRef,
    status,
    burnedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'attachments';
  @override
  VerificationContext validateIntegrity(
    Insertable<Attachment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('entry_id')) {
      context.handle(
        _entryIdMeta,
        entryId.isAcceptableOrUnknown(data['entry_id']!, _entryIdMeta),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_contentHashMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('mime')) {
      context.handle(
        _mimeMeta,
        mime.isAcceptableOrUnknown(data['mime']!, _mimeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('blob_ref')) {
      context.handle(
        _blobRefMeta,
        blobRef.isAcceptableOrUnknown(data['blob_ref']!, _blobRefMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('burned_at')) {
      context.handle(
        _burnedAtMeta,
        burnedAt.isAcceptableOrUnknown(data['burned_at']!, _burnedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Attachment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Attachment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      entryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_id'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      mime: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      blobRef: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blob_ref'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      burnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}burned_at'],
      ),
    );
  }

  @override
  $AttachmentsTable createAlias(String alias) {
    return $AttachmentsTable(attachedDatabase, alias);
  }
}

class Attachment extends DataClass implements Insertable<Attachment> {
  /// UUIDv7 主键（应用层生成，§5.1）。
  ///
  /// id 内嵌 48 位 unix 毫秒——即焚清理（>7 天残留强制焚毁）的「残留
  /// 时长」判据由此得出，不另设 created_at 列（§5.6⑭ ai_parses「7 天时效
  /// 判断可由 UUIDv7 id 内嵌时间戳得出，故不另设时间列」同一口径）。
  final String id;

  /// 所属事件（可空：拍照先于事件落库）；逻辑引用不建外键
  /// （服务端为主、pull 顺序不定）。
  final String? entryId;

  /// 去重键（sha256 内容哈希；去重由应用层查重保证，§5.6）。
  final String contentHash;

  /// photo / receipt。
  final String kind;

  /// MIME 类型。
  final String mime;

  /// 字节数。
  final int sizeBytes;

  /// 本地文件路径。
  ///
  /// 即焚后保留（审计元数据：内容曾在此、已焚毁），不代表内容仍存在。
  final String localPath;

  /// 服务端 blob 引用（可空；默认即焚为 NULL——原图不落服务端，§5.6）。
  final String? blobRef;

  /// 即焚状态机（§3.3）：active（本地内容存在）/ burned（内容已焚毁）。
  /// 列默认值 'active'：v1 内补列的迁移风险规避（§6.4 只加列）。
  final String status;

  /// 即焚时刻 UTC ms（NULL=未焚毁）——审计元数据（保留时刻、不保留内容）。
  final int? burnedAt;
  const Attachment({
    required this.id,
    this.entryId,
    required this.contentHash,
    required this.kind,
    required this.mime,
    required this.sizeBytes,
    required this.localPath,
    this.blobRef,
    required this.status,
    this.burnedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || entryId != null) {
      map['entry_id'] = Variable<String>(entryId);
    }
    map['content_hash'] = Variable<String>(contentHash);
    map['kind'] = Variable<String>(kind);
    map['mime'] = Variable<String>(mime);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['local_path'] = Variable<String>(localPath);
    if (!nullToAbsent || blobRef != null) {
      map['blob_ref'] = Variable<String>(blobRef);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || burnedAt != null) {
      map['burned_at'] = Variable<int>(burnedAt);
    }
    return map;
  }

  AttachmentsCompanion toCompanion(bool nullToAbsent) {
    return AttachmentsCompanion(
      id: Value(id),
      entryId: entryId == null && nullToAbsent
          ? const Value.absent()
          : Value(entryId),
      contentHash: Value(contentHash),
      kind: Value(kind),
      mime: Value(mime),
      sizeBytes: Value(sizeBytes),
      localPath: Value(localPath),
      blobRef: blobRef == null && nullToAbsent
          ? const Value.absent()
          : Value(blobRef),
      status: Value(status),
      burnedAt: burnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(burnedAt),
    );
  }

  factory Attachment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Attachment(
      id: serializer.fromJson<String>(json['id']),
      entryId: serializer.fromJson<String?>(json['entryId']),
      contentHash: serializer.fromJson<String>(json['contentHash']),
      kind: serializer.fromJson<String>(json['kind']),
      mime: serializer.fromJson<String>(json['mime']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      localPath: serializer.fromJson<String>(json['localPath']),
      blobRef: serializer.fromJson<String?>(json['blobRef']),
      status: serializer.fromJson<String>(json['status']),
      burnedAt: serializer.fromJson<int?>(json['burnedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'entryId': serializer.toJson<String?>(entryId),
      'contentHash': serializer.toJson<String>(contentHash),
      'kind': serializer.toJson<String>(kind),
      'mime': serializer.toJson<String>(mime),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'localPath': serializer.toJson<String>(localPath),
      'blobRef': serializer.toJson<String?>(blobRef),
      'status': serializer.toJson<String>(status),
      'burnedAt': serializer.toJson<int?>(burnedAt),
    };
  }

  Attachment copyWith({
    String? id,
    Value<String?> entryId = const Value.absent(),
    String? contentHash,
    String? kind,
    String? mime,
    int? sizeBytes,
    String? localPath,
    Value<String?> blobRef = const Value.absent(),
    String? status,
    Value<int?> burnedAt = const Value.absent(),
  }) => Attachment(
    id: id ?? this.id,
    entryId: entryId.present ? entryId.value : this.entryId,
    contentHash: contentHash ?? this.contentHash,
    kind: kind ?? this.kind,
    mime: mime ?? this.mime,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    localPath: localPath ?? this.localPath,
    blobRef: blobRef.present ? blobRef.value : this.blobRef,
    status: status ?? this.status,
    burnedAt: burnedAt.present ? burnedAt.value : this.burnedAt,
  );
  Attachment copyWithCompanion(AttachmentsCompanion data) {
    return Attachment(
      id: data.id.present ? data.id.value : this.id,
      entryId: data.entryId.present ? data.entryId.value : this.entryId,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      kind: data.kind.present ? data.kind.value : this.kind,
      mime: data.mime.present ? data.mime.value : this.mime,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      blobRef: data.blobRef.present ? data.blobRef.value : this.blobRef,
      status: data.status.present ? data.status.value : this.status,
      burnedAt: data.burnedAt.present ? data.burnedAt.value : this.burnedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Attachment(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('contentHash: $contentHash, ')
          ..write('kind: $kind, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('localPath: $localPath, ')
          ..write('blobRef: $blobRef, ')
          ..write('status: $status, ')
          ..write('burnedAt: $burnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    entryId,
    contentHash,
    kind,
    mime,
    sizeBytes,
    localPath,
    blobRef,
    status,
    burnedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Attachment &&
          other.id == this.id &&
          other.entryId == this.entryId &&
          other.contentHash == this.contentHash &&
          other.kind == this.kind &&
          other.mime == this.mime &&
          other.sizeBytes == this.sizeBytes &&
          other.localPath == this.localPath &&
          other.blobRef == this.blobRef &&
          other.status == this.status &&
          other.burnedAt == this.burnedAt);
}

class AttachmentsCompanion extends UpdateCompanion<Attachment> {
  final Value<String> id;
  final Value<String?> entryId;
  final Value<String> contentHash;
  final Value<String> kind;
  final Value<String> mime;
  final Value<int> sizeBytes;
  final Value<String> localPath;
  final Value<String?> blobRef;
  final Value<String> status;
  final Value<int?> burnedAt;
  final Value<int> rowid;
  const AttachmentsCompanion({
    this.id = const Value.absent(),
    this.entryId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.kind = const Value.absent(),
    this.mime = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.localPath = const Value.absent(),
    this.blobRef = const Value.absent(),
    this.status = const Value.absent(),
    this.burnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AttachmentsCompanion.insert({
    required String id,
    this.entryId = const Value.absent(),
    required String contentHash,
    required String kind,
    required String mime,
    required int sizeBytes,
    required String localPath,
    this.blobRef = const Value.absent(),
    this.status = const Value.absent(),
    this.burnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       contentHash = Value(contentHash),
       kind = Value(kind),
       mime = Value(mime),
       sizeBytes = Value(sizeBytes),
       localPath = Value(localPath);
  static Insertable<Attachment> custom({
    Expression<String>? id,
    Expression<String>? entryId,
    Expression<String>? contentHash,
    Expression<String>? kind,
    Expression<String>? mime,
    Expression<int>? sizeBytes,
    Expression<String>? localPath,
    Expression<String>? blobRef,
    Expression<String>? status,
    Expression<int>? burnedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entryId != null) 'entry_id': entryId,
      if (contentHash != null) 'content_hash': contentHash,
      if (kind != null) 'kind': kind,
      if (mime != null) 'mime': mime,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (localPath != null) 'local_path': localPath,
      if (blobRef != null) 'blob_ref': blobRef,
      if (status != null) 'status': status,
      if (burnedAt != null) 'burned_at': burnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AttachmentsCompanion copyWith({
    Value<String>? id,
    Value<String?>? entryId,
    Value<String>? contentHash,
    Value<String>? kind,
    Value<String>? mime,
    Value<int>? sizeBytes,
    Value<String>? localPath,
    Value<String?>? blobRef,
    Value<String>? status,
    Value<int?>? burnedAt,
    Value<int>? rowid,
  }) {
    return AttachmentsCompanion(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      contentHash: contentHash ?? this.contentHash,
      kind: kind ?? this.kind,
      mime: mime ?? this.mime,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      localPath: localPath ?? this.localPath,
      blobRef: blobRef ?? this.blobRef,
      status: status ?? this.status,
      burnedAt: burnedAt ?? this.burnedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (entryId.present) {
      map['entry_id'] = Variable<String>(entryId.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (mime.present) {
      map['mime'] = Variable<String>(mime.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (blobRef.present) {
      map['blob_ref'] = Variable<String>(blobRef.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (burnedAt.present) {
      map['burned_at'] = Variable<int>(burnedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AttachmentsCompanion(')
          ..write('id: $id, ')
          ..write('entryId: $entryId, ')
          ..write('contentHash: $contentHash, ')
          ..write('kind: $kind, ')
          ..write('mime: $mime, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('localPath: $localPath, ')
          ..write('blobRef: $blobRef, ')
          ..write('status: $status, ')
          ..write('burnedAt: $burnedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $EntriesTable entries = $EntriesTable(this);
  late final $EntryLinesTable entryLines = $EntryLinesTable(this);
  late final $FoodItemsTable foodItems = $FoodItemsTable(this);
  late final $LedgersTable ledgers = $LedgersTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $BudgetsTable budgets = $BudgetsTable(this);
  late final $TodosTable todos = $TodosTable(this);
  late final $FitnessSessionsTable fitnessSessions = $FitnessSessionsTable(
    this,
  );
  late final $FitnessPlansTable fitnessPlans = $FitnessPlansTable(this);
  late final $ExerciseSetsTable exerciseSets = $ExerciseSetsTable(this);
  late final $SavingsGoalsTable savingsGoals = $SavingsGoalsTable(this);
  late final $SavingsContributionsTable savingsContributions =
      $SavingsContributionsTable(this);
  late final $CorrectionsTable corrections = $CorrectionsTable(this);
  late final $ThemeProfilesTable themeProfiles = $ThemeProfilesTable(this);
  late final $DaySummariesTable daySummaries = $DaySummariesTable(this);
  late final $AiParsesTable aiParses = $AiParsesTable(this);
  late final $SyncOutboxTable syncOutbox = $SyncOutboxTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $AttachmentsTable attachments = $AttachmentsTable(this);
  late final Index idxEntriesDate = Index(
    'idx_entries_date',
    'CREATE INDEX idx_entries_date ON entries (date)',
  );
  late final Index idxEntriesKindDate = Index(
    'idx_entries_kind_date',
    'CREATE INDEX idx_entries_kind_date ON entries (kind, date)',
  );
  late final Index idxEntriesUpdatedAt = Index(
    'idx_entries_updated_at',
    'CREATE INDEX idx_entries_updated_at ON entries (updated_at)',
  );
  late final Index idxEntriesHlc = Index(
    'idx_entries_hlc',
    'CREATE INDEX idx_entries_hlc ON entries (hlc)',
  );
  late final Index idxEntryLinesEntryId = Index(
    'idx_entry_lines_entry_id',
    'CREATE INDEX idx_entry_lines_entry_id ON entry_lines (entry_id)',
  );
  late final Index idxEntryLinesType = Index(
    'idx_entry_lines_type',
    'CREATE INDEX idx_entry_lines_type ON entry_lines (type)',
  );
  late final Index idxEntryLinesLedgerUpdatedAt = Index(
    'idx_entry_lines_ledger_updated_at',
    'CREATE INDEX idx_entry_lines_ledger_updated_at ON entry_lines (ledger_id, updated_at)',
  );
  late final Index idxEntryLinesCorrectionOf = Index(
    'idx_entry_lines_correction_of',
    'CREATE INDEX idx_entry_lines_correction_of ON entry_lines (correction_of)',
  );
  late final Index idxEntryLinesHlc = Index(
    'idx_entry_lines_hlc',
    'CREATE INDEX idx_entry_lines_hlc ON entry_lines (hlc)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    entries,
    entryLines,
    foodItems,
    ledgers,
    categories,
    budgets,
    todos,
    fitnessSessions,
    fitnessPlans,
    exerciseSets,
    savingsGoals,
    savingsContributions,
    corrections,
    themeProfiles,
    daySummaries,
    aiParses,
    syncOutbox,
    syncCursors,
    settings,
    devices,
    attachments,
    idxEntriesDate,
    idxEntriesKindDate,
    idxEntriesUpdatedAt,
    idxEntriesHlc,
    idxEntryLinesEntryId,
    idxEntryLinesType,
    idxEntryLinesLedgerUpdatedAt,
    idxEntryLinesCorrectionOf,
    idxEntryLinesHlc,
  ];
}

typedef $$EntriesTableCreateCompanionBuilder =
    EntriesCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String date,
      required int tzOffsetMin,
      Value<int?> occurredAt,
      required String kind,
      required String source,
      required String title,
      Value<String?> note,
      required String status,
      Value<String?> aiParseId,
      Value<int> rowid,
    });
typedef $$EntriesTableUpdateCompanionBuilder =
    EntriesCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> date,
      Value<int> tzOffsetMin,
      Value<int?> occurredAt,
      Value<String> kind,
      Value<String> source,
      Value<String> title,
      Value<String?> note,
      Value<String> status,
      Value<String?> aiParseId,
      Value<int> rowid,
    });

final class $$EntriesTableReferences
    extends BaseReferences<_$AppDatabase, $EntriesTable, Entry> {
  $$EntriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$EntryLinesTable, List<EntryLine>>
  _entryLinesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.entryLines,
    aliasName: $_aliasNameGenerator(db.entries.id, db.entryLines.entryId),
  );

  $$EntryLinesTableProcessedTableManager get entryLinesRefs {
    final manager = $$EntryLinesTableTableManager(
      $_db,
      $_db.entryLines,
    ).filter((f) => f.entryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_entryLinesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$EntriesTableFilterComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
  $$EntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiParseId => $composableBuilder(
    column: $table.aiParseId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> entryLinesRefs(
    Expression<bool> Function($$EntryLinesTableFilterComposer f) f,
  ) {
    final $$EntryLinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryLines,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryLinesTableFilterComposer(
            $db: $db,
            $table: $db.entryLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
  $$EntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiParseId => $composableBuilder(
    column: $table.aiParseId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntriesTable> {
  $$EntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get aiParseId =>
      $composableBuilder(column: $table.aiParseId, builder: (column) => column);

  Expression<T> entryLinesRefs<T extends Object>(
    Expression<T> Function($$EntryLinesTableAnnotationComposer a) f,
  ) {
    final $$EntryLinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.entryLines,
      getReferencedColumn: (t) => t.entryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntryLinesTableAnnotationComposer(
            $db: $db,
            $table: $db.entryLines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$EntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntriesTable,
          Entry,
          $$EntriesTableFilterComposer,
          $$EntriesTableOrderingComposer,
          $$EntriesTableAnnotationComposer,
          $$EntriesTableCreateCompanionBuilder,
          $$EntriesTableUpdateCompanionBuilder,
          (Entry, $$EntriesTableReferences),
          Entry,
          PrefetchHooks Function({bool entryLinesRefs})
        > {
  $$EntriesTableTableManager(_$AppDatabase db, $EntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> tzOffsetMin = const Value.absent(),
                Value<int?> occurredAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> aiParseId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                date: date,
                tzOffsetMin: tzOffsetMin,
                occurredAt: occurredAt,
                kind: kind,
                source: source,
                title: title,
                note: note,
                status: status,
                aiParseId: aiParseId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String date,
                required int tzOffsetMin,
                Value<int?> occurredAt = const Value.absent(),
                required String kind,
                required String source,
                required String title,
                Value<String?> note = const Value.absent(),
                required String status,
                Value<String?> aiParseId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntriesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                date: date,
                tzOffsetMin: tzOffsetMin,
                occurredAt: occurredAt,
                kind: kind,
                source: source,
                title: title,
                note: note,
                status: status,
                aiParseId: aiParseId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryLinesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (entryLinesRefs) db.entryLines],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (entryLinesRefs)
                    await $_getPrefetchedData<Entry, $EntriesTable, EntryLine>(
                      currentTable: table,
                      referencedTable: $$EntriesTableReferences
                          ._entryLinesRefsTable(db),
                      managerFromTypedResult: (p0) => $$EntriesTableReferences(
                        db,
                        table,
                        p0,
                      ).entryLinesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.entryId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$EntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntriesTable,
      Entry,
      $$EntriesTableFilterComposer,
      $$EntriesTableOrderingComposer,
      $$EntriesTableAnnotationComposer,
      $$EntriesTableCreateCompanionBuilder,
      $$EntriesTableUpdateCompanionBuilder,
      (Entry, $$EntriesTableReferences),
      Entry,
      PrefetchHooks Function({bool entryLinesRefs})
    >;
typedef $$EntryLinesTableCreateCompanionBuilder =
    EntryLinesCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String entryId,
      required String type,
      required int amount,
      required String direction,
      Value<String?> ledgerId,
      Value<String?> categoryId,
      Value<String?> currency,
      Value<double?> confidence,
      Value<String?> payload,
      Value<String?> correctionOf,
      required String status,
      Value<int> rowid,
    });
typedef $$EntryLinesTableUpdateCompanionBuilder =
    EntryLinesCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> entryId,
      Value<String> type,
      Value<int> amount,
      Value<String> direction,
      Value<String?> ledgerId,
      Value<String?> categoryId,
      Value<String?> currency,
      Value<double?> confidence,
      Value<String?> payload,
      Value<String?> correctionOf,
      Value<String> status,
      Value<int> rowid,
    });

final class $$EntryLinesTableReferences
    extends BaseReferences<_$AppDatabase, $EntryLinesTable, EntryLine> {
  $$EntryLinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $EntriesTable _entryIdTable(_$AppDatabase db) => db.entries
      .createAlias($_aliasNameGenerator(db.entryLines.entryId, db.entries.id));

  $$EntriesTableProcessedTableManager get entryId {
    final $_column = $_itemColumn<String>('entry_id')!;

    final manager = $$EntriesTableTableManager(
      $_db,
      $_db.entries,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_entryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EntryLinesTableFilterComposer
    extends Composer<_$AppDatabase, $EntryLinesTable> {
  $$EntryLinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctionOf => $composableBuilder(
    column: $table.correctionOf,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  $$EntriesTableFilterComposer get entryId {
    final $$EntriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableFilterComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryLinesTableOrderingComposer
    extends Composer<_$AppDatabase, $EntryLinesTable> {
  $$EntryLinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctionOf => $composableBuilder(
    column: $table.correctionOf,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  $$EntriesTableOrderingComposer get entryId {
    final $$EntriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableOrderingComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryLinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EntryLinesTable> {
  $$EntryLinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get correctionOf => $composableBuilder(
    column: $table.correctionOf,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  $$EntriesTableAnnotationComposer get entryId {
    final $$EntriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.entryId,
      referencedTable: $db.entries,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EntriesTableAnnotationComposer(
            $db: $db,
            $table: $db.entries,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EntryLinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EntryLinesTable,
          EntryLine,
          $$EntryLinesTableFilterComposer,
          $$EntryLinesTableOrderingComposer,
          $$EntryLinesTableAnnotationComposer,
          $$EntryLinesTableCreateCompanionBuilder,
          $$EntryLinesTableUpdateCompanionBuilder,
          (EntryLine, $$EntryLinesTableReferences),
          EntryLine,
          PrefetchHooks Function({bool entryId})
        > {
  $$EntryLinesTableTableManager(_$AppDatabase db, $EntryLinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EntryLinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EntryLinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EntryLinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String?> ledgerId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> currency = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> correctionOf = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EntryLinesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                type: type,
                amount: amount,
                direction: direction,
                ledgerId: ledgerId,
                categoryId: categoryId,
                currency: currency,
                confidence: confidence,
                payload: payload,
                correctionOf: correctionOf,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String entryId,
                required String type,
                required int amount,
                required String direction,
                Value<String?> ledgerId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String?> currency = const Value.absent(),
                Value<double?> confidence = const Value.absent(),
                Value<String?> payload = const Value.absent(),
                Value<String?> correctionOf = const Value.absent(),
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => EntryLinesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                type: type,
                amount: amount,
                direction: direction,
                ledgerId: ledgerId,
                categoryId: categoryId,
                currency: currency,
                confidence: confidence,
                payload: payload,
                correctionOf: correctionOf,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EntryLinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({entryId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (entryId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.entryId,
                                referencedTable: $$EntryLinesTableReferences
                                    ._entryIdTable(db),
                                referencedColumn: $$EntryLinesTableReferences
                                    ._entryIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EntryLinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EntryLinesTable,
      EntryLine,
      $$EntryLinesTableFilterComposer,
      $$EntryLinesTableOrderingComposer,
      $$EntryLinesTableAnnotationComposer,
      $$EntryLinesTableCreateCompanionBuilder,
      $$EntryLinesTableUpdateCompanionBuilder,
      (EntryLine, $$EntryLinesTableReferences),
      EntryLine,
      PrefetchHooks Function({bool entryId})
    >;
typedef $$FoodItemsTableCreateCompanionBuilder =
    FoodItemsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String entryId,
      required String lineId,
      required String name,
      required double portionG,
      required int kcal,
      required double proteinG,
      required double carbG,
      required double fatG,
      required String refSource,
      Value<String?> refId,
      required double confidence,
      required bool userAdjusted,
      Value<int> rowid,
    });
typedef $$FoodItemsTableUpdateCompanionBuilder =
    FoodItemsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> entryId,
      Value<String> lineId,
      Value<String> name,
      Value<double> portionG,
      Value<int> kcal,
      Value<double> proteinG,
      Value<double> carbG,
      Value<double> fatG,
      Value<String> refSource,
      Value<String?> refId,
      Value<double> confidence,
      Value<bool> userAdjusted,
      Value<int> rowid,
    });

class $$FoodItemsTableFilterComposer
    extends Composer<_$AppDatabase, $FoodItemsTable> {
  $$FoodItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get portionG => $composableBuilder(
    column: $table.portionG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refSource => $composableBuilder(
    column: $table.refSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get userAdjusted => $composableBuilder(
    column: $table.userAdjusted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FoodItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $FoodItemsTable> {
  $$FoodItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get portionG => $composableBuilder(
    column: $table.portionG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kcal => $composableBuilder(
    column: $table.kcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get proteinG => $composableBuilder(
    column: $table.proteinG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get carbG => $composableBuilder(
    column: $table.carbG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get fatG => $composableBuilder(
    column: $table.fatG,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refSource => $composableBuilder(
    column: $table.refSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get userAdjusted => $composableBuilder(
    column: $table.userAdjusted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FoodItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoodItemsTable> {
  $$FoodItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get portionG =>
      $composableBuilder(column: $table.portionG, builder: (column) => column);

  GeneratedColumn<int> get kcal =>
      $composableBuilder(column: $table.kcal, builder: (column) => column);

  GeneratedColumn<double> get proteinG =>
      $composableBuilder(column: $table.proteinG, builder: (column) => column);

  GeneratedColumn<double> get carbG =>
      $composableBuilder(column: $table.carbG, builder: (column) => column);

  GeneratedColumn<double> get fatG =>
      $composableBuilder(column: $table.fatG, builder: (column) => column);

  GeneratedColumn<String> get refSource =>
      $composableBuilder(column: $table.refSource, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get userAdjusted => $composableBuilder(
    column: $table.userAdjusted,
    builder: (column) => column,
  );
}

class $$FoodItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FoodItemsTable,
          FoodItem,
          $$FoodItemsTableFilterComposer,
          $$FoodItemsTableOrderingComposer,
          $$FoodItemsTableAnnotationComposer,
          $$FoodItemsTableCreateCompanionBuilder,
          $$FoodItemsTableUpdateCompanionBuilder,
          (FoodItem, BaseReferences<_$AppDatabase, $FoodItemsTable, FoodItem>),
          FoodItem,
          PrefetchHooks Function()
        > {
  $$FoodItemsTableTableManager(_$AppDatabase db, $FoodItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoodItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoodItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoodItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String> lineId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> portionG = const Value.absent(),
                Value<int> kcal = const Value.absent(),
                Value<double> proteinG = const Value.absent(),
                Value<double> carbG = const Value.absent(),
                Value<double> fatG = const Value.absent(),
                Value<String> refSource = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<bool> userAdjusted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FoodItemsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                lineId: lineId,
                name: name,
                portionG: portionG,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                refSource: refSource,
                refId: refId,
                confidence: confidence,
                userAdjusted: userAdjusted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String entryId,
                required String lineId,
                required String name,
                required double portionG,
                required int kcal,
                required double proteinG,
                required double carbG,
                required double fatG,
                required String refSource,
                Value<String?> refId = const Value.absent(),
                required double confidence,
                required bool userAdjusted,
                Value<int> rowid = const Value.absent(),
              }) => FoodItemsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                lineId: lineId,
                name: name,
                portionG: portionG,
                kcal: kcal,
                proteinG: proteinG,
                carbG: carbG,
                fatG: fatG,
                refSource: refSource,
                refId: refId,
                confidence: confidence,
                userAdjusted: userAdjusted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FoodItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FoodItemsTable,
      FoodItem,
      $$FoodItemsTableFilterComposer,
      $$FoodItemsTableOrderingComposer,
      $$FoodItemsTableAnnotationComposer,
      $$FoodItemsTableCreateCompanionBuilder,
      $$FoodItemsTableUpdateCompanionBuilder,
      (FoodItem, BaseReferences<_$AppDatabase, $FoodItemsTable, FoodItem>),
      FoodItem,
      PrefetchHooks Function()
    >;
typedef $$LedgersTableCreateCompanionBuilder =
    LedgersCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String name,
      required String icon,
      required String currency,
      required String kind,
      required int sort,
      required int openingBalanceMinor,
      required bool isArchived,
      Value<int> rowid,
    });
typedef $$LedgersTableUpdateCompanionBuilder =
    LedgersCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<String> currency,
      Value<String> kind,
      Value<int> sort,
      Value<int> openingBalanceMinor,
      Value<bool> isArchived,
      Value<int> rowid,
    });

class $$LedgersTableFilterComposer
    extends Composer<_$AppDatabase, $LedgersTable> {
  $$LedgersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LedgersTableOrderingComposer
    extends Composer<_$AppDatabase, $LedgersTable> {
  $$LedgersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LedgersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LedgersTable> {
  $$LedgersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<int> get openingBalanceMinor => $composableBuilder(
    column: $table.openingBalanceMinor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );
}

class $$LedgersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LedgersTable,
          Ledger,
          $$LedgersTableFilterComposer,
          $$LedgersTableOrderingComposer,
          $$LedgersTableAnnotationComposer,
          $$LedgersTableCreateCompanionBuilder,
          $$LedgersTableUpdateCompanionBuilder,
          (Ledger, BaseReferences<_$AppDatabase, $LedgersTable, Ledger>),
          Ledger,
          PrefetchHooks Function()
        > {
  $$LedgersTableTableManager(_$AppDatabase db, $LedgersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LedgersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LedgersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LedgersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> openingBalanceMinor = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LedgersCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                icon: icon,
                currency: currency,
                kind: kind,
                sort: sort,
                openingBalanceMinor: openingBalanceMinor,
                isArchived: isArchived,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String name,
                required String icon,
                required String currency,
                required String kind,
                required int sort,
                required int openingBalanceMinor,
                required bool isArchived,
                Value<int> rowid = const Value.absent(),
              }) => LedgersCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                icon: icon,
                currency: currency,
                kind: kind,
                sort: sort,
                openingBalanceMinor: openingBalanceMinor,
                isArchived: isArchived,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LedgersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LedgersTable,
      Ledger,
      $$LedgersTableFilterComposer,
      $$LedgersTableOrderingComposer,
      $$LedgersTableAnnotationComposer,
      $$LedgersTableCreateCompanionBuilder,
      $$LedgersTableUpdateCompanionBuilder,
      (Ledger, BaseReferences<_$AppDatabase, $LedgersTable, Ledger>),
      Ledger,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String name,
      required String icon,
      required int sort,
      Value<String?> ledgerId,
      required String kind,
      required String colorToken,
      required bool isPreset,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> name,
      Value<String> icon,
      Value<int> sort,
      Value<String?> ledgerId,
      Value<String> kind,
      Value<String> colorToken,
      Value<bool> isPreset,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPreset => $composableBuilder(
    column: $table.isPreset,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPreset => $composableBuilder(
    column: $table.isPreset,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);

  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get colorToken => $composableBuilder(
    column: $table.colorToken,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPreset =>
      $composableBuilder(column: $table.isPreset, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<String?> ledgerId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> colorToken = const Value.absent(),
                Value<bool> isPreset = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                icon: icon,
                sort: sort,
                ledgerId: ledgerId,
                kind: kind,
                colorToken: colorToken,
                isPreset: isPreset,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String name,
                required String icon,
                required int sort,
                Value<String?> ledgerId = const Value.absent(),
                required String kind,
                required String colorToken,
                required bool isPreset,
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                icon: icon,
                sort: sort,
                ledgerId: ledgerId,
                kind: kind,
                colorToken: colorToken,
                isPreset: isPreset,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$BudgetsTableCreateCompanionBuilder =
    BudgetsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String ledgerId,
      Value<String?> categoryId,
      required String periodType,
      required int amount,
      required int dayOfMonthStart,
      required bool carryOver,
      Value<int> rowid,
    });
typedef $$BudgetsTableUpdateCompanionBuilder =
    BudgetsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> ledgerId,
      Value<String?> categoryId,
      Value<String> periodType,
      Value<int> amount,
      Value<int> dayOfMonthStart,
      Value<bool> carryOver,
      Value<int> rowid,
    });

class $$BudgetsTableFilterComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dayOfMonthStart => $composableBuilder(
    column: $table.dayOfMonthStart,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get carryOver => $composableBuilder(
    column: $table.carryOver,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BudgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ledgerId => $composableBuilder(
    column: $table.ledgerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dayOfMonthStart => $composableBuilder(
    column: $table.dayOfMonthStart,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get carryOver => $composableBuilder(
    column: $table.carryOver,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BudgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BudgetsTable> {
  $$BudgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get ledgerId =>
      $composableBuilder(column: $table.ledgerId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get periodType => $composableBuilder(
    column: $table.periodType,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<int> get dayOfMonthStart => $composableBuilder(
    column: $table.dayOfMonthStart,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get carryOver =>
      $composableBuilder(column: $table.carryOver, builder: (column) => column);
}

class $$BudgetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BudgetsTable,
          Budget,
          $$BudgetsTableFilterComposer,
          $$BudgetsTableOrderingComposer,
          $$BudgetsTableAnnotationComposer,
          $$BudgetsTableCreateCompanionBuilder,
          $$BudgetsTableUpdateCompanionBuilder,
          (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
          Budget,
          PrefetchHooks Function()
        > {
  $$BudgetsTableTableManager(_$AppDatabase db, $BudgetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BudgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BudgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BudgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> ledgerId = const Value.absent(),
                Value<String?> categoryId = const Value.absent(),
                Value<String> periodType = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<int> dayOfMonthStart = const Value.absent(),
                Value<bool> carryOver = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BudgetsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                ledgerId: ledgerId,
                categoryId: categoryId,
                periodType: periodType,
                amount: amount,
                dayOfMonthStart: dayOfMonthStart,
                carryOver: carryOver,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String ledgerId,
                Value<String?> categoryId = const Value.absent(),
                required String periodType,
                required int amount,
                required int dayOfMonthStart,
                required bool carryOver,
                Value<int> rowid = const Value.absent(),
              }) => BudgetsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                ledgerId: ledgerId,
                categoryId: categoryId,
                periodType: periodType,
                amount: amount,
                dayOfMonthStart: dayOfMonthStart,
                carryOver: carryOver,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BudgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BudgetsTable,
      Budget,
      $$BudgetsTableFilterComposer,
      $$BudgetsTableOrderingComposer,
      $$BudgetsTableAnnotationComposer,
      $$BudgetsTableCreateCompanionBuilder,
      $$BudgetsTableUpdateCompanionBuilder,
      (Budget, BaseReferences<_$AppDatabase, $BudgetsTable, Budget>),
      Budget,
      PrefetchHooks Function()
    >;
typedef $$TodosTableCreateCompanionBuilder =
    TodosCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String title,
      Value<String?> note,
      Value<String?> date,
      Value<int?> doneAt,
      Value<int?> dueAt,
      Value<String?> repeatRule,
      Value<int?> remindAt,
      Value<String?> goalLink,
      Value<int> rowid,
    });
typedef $$TodosTableUpdateCompanionBuilder =
    TodosCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> title,
      Value<String?> note,
      Value<String?> date,
      Value<int?> doneAt,
      Value<int?> dueAt,
      Value<String?> repeatRule,
      Value<int?> remindAt,
      Value<String?> goalLink,
      Value<int> rowid,
    });

class $$TodosTableFilterComposer extends Composer<_$AppDatabase, $TodosTable> {
  $$TodosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalLink => $composableBuilder(
    column: $table.goalLink,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TodosTableOrderingComposer
    extends Composer<_$AppDatabase, $TodosTable> {
  $$TodosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remindAt => $composableBuilder(
    column: $table.remindAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalLink => $composableBuilder(
    column: $table.goalLink,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TodosTableAnnotationComposer
    extends Composer<_$AppDatabase, $TodosTable> {
  $$TodosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<int> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<String> get repeatRule => $composableBuilder(
    column: $table.repeatRule,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<String> get goalLink =>
      $composableBuilder(column: $table.goalLink, builder: (column) => column);
}

class $$TodosTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TodosTable,
          Todo,
          $$TodosTableFilterComposer,
          $$TodosTableOrderingComposer,
          $$TodosTableAnnotationComposer,
          $$TodosTableCreateCompanionBuilder,
          $$TodosTableUpdateCompanionBuilder,
          (Todo, BaseReferences<_$AppDatabase, $TodosTable, Todo>),
          Todo,
          PrefetchHooks Function()
        > {
  $$TodosTableTableManager(_$AppDatabase db, $TodosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TodosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TodosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TodosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> date = const Value.absent(),
                Value<int?> doneAt = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<int?> remindAt = const Value.absent(),
                Value<String?> goalLink = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodosCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                title: title,
                note: note,
                date: date,
                doneAt: doneAt,
                dueAt: dueAt,
                repeatRule: repeatRule,
                remindAt: remindAt,
                goalLink: goalLink,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String title,
                Value<String?> note = const Value.absent(),
                Value<String?> date = const Value.absent(),
                Value<int?> doneAt = const Value.absent(),
                Value<int?> dueAt = const Value.absent(),
                Value<String?> repeatRule = const Value.absent(),
                Value<int?> remindAt = const Value.absent(),
                Value<String?> goalLink = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TodosCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                title: title,
                note: note,
                date: date,
                doneAt: doneAt,
                dueAt: dueAt,
                repeatRule: repeatRule,
                remindAt: remindAt,
                goalLink: goalLink,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TodosTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TodosTable,
      Todo,
      $$TodosTableFilterComposer,
      $$TodosTableOrderingComposer,
      $$TodosTableAnnotationComposer,
      $$TodosTableCreateCompanionBuilder,
      $$TodosTableUpdateCompanionBuilder,
      (Todo, BaseReferences<_$AppDatabase, $TodosTable, Todo>),
      Todo,
      PrefetchHooks Function()
    >;
typedef $$FitnessSessionsTableCreateCompanionBuilder =
    FitnessSessionsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String date,
      required int tzOffsetMin,
      Value<int?> startAt,
      required int durationS,
      required String type,
      required int kcalBurn,
      Value<String?> entryId,
      required String source,
      Value<String?> planDayId,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$FitnessSessionsTableUpdateCompanionBuilder =
    FitnessSessionsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> date,
      Value<int> tzOffsetMin,
      Value<int?> startAt,
      Value<int> durationS,
      Value<String> type,
      Value<int> kcalBurn,
      Value<String?> entryId,
      Value<String> source,
      Value<String?> planDayId,
      Value<String?> note,
      Value<int> rowid,
    });

class $$FitnessSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $FitnessSessionsTable> {
  $$FitnessSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationS => $composableBuilder(
    column: $table.durationS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kcalBurn => $composableBuilder(
    column: $table.kcalBurn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planDayId => $composableBuilder(
    column: $table.planDayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FitnessSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $FitnessSessionsTable> {
  $$FitnessSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startAt => $composableBuilder(
    column: $table.startAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationS => $composableBuilder(
    column: $table.durationS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kcalBurn => $composableBuilder(
    column: $table.kcalBurn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planDayId => $composableBuilder(
    column: $table.planDayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FitnessSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FitnessSessionsTable> {
  $$FitnessSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get startAt =>
      $composableBuilder(column: $table.startAt, builder: (column) => column);

  GeneratedColumn<int> get durationS =>
      $composableBuilder(column: $table.durationS, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get kcalBurn =>
      $composableBuilder(column: $table.kcalBurn, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get planDayId =>
      $composableBuilder(column: $table.planDayId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$FitnessSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FitnessSessionsTable,
          FitnessSession,
          $$FitnessSessionsTableFilterComposer,
          $$FitnessSessionsTableOrderingComposer,
          $$FitnessSessionsTableAnnotationComposer,
          $$FitnessSessionsTableCreateCompanionBuilder,
          $$FitnessSessionsTableUpdateCompanionBuilder,
          (
            FitnessSession,
            BaseReferences<
              _$AppDatabase,
              $FitnessSessionsTable,
              FitnessSession
            >,
          ),
          FitnessSession,
          PrefetchHooks Function()
        > {
  $$FitnessSessionsTableTableManager(
    _$AppDatabase db,
    $FitnessSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FitnessSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FitnessSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FitnessSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> tzOffsetMin = const Value.absent(),
                Value<int?> startAt = const Value.absent(),
                Value<int> durationS = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> kcalBurn = const Value.absent(),
                Value<String?> entryId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> planDayId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FitnessSessionsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                date: date,
                tzOffsetMin: tzOffsetMin,
                startAt: startAt,
                durationS: durationS,
                type: type,
                kcalBurn: kcalBurn,
                entryId: entryId,
                source: source,
                planDayId: planDayId,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String date,
                required int tzOffsetMin,
                Value<int?> startAt = const Value.absent(),
                required int durationS,
                required String type,
                required int kcalBurn,
                Value<String?> entryId = const Value.absent(),
                required String source,
                Value<String?> planDayId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FitnessSessionsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                date: date,
                tzOffsetMin: tzOffsetMin,
                startAt: startAt,
                durationS: durationS,
                type: type,
                kcalBurn: kcalBurn,
                entryId: entryId,
                source: source,
                planDayId: planDayId,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FitnessSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FitnessSessionsTable,
      FitnessSession,
      $$FitnessSessionsTableFilterComposer,
      $$FitnessSessionsTableOrderingComposer,
      $$FitnessSessionsTableAnnotationComposer,
      $$FitnessSessionsTableCreateCompanionBuilder,
      $$FitnessSessionsTableUpdateCompanionBuilder,
      (
        FitnessSession,
        BaseReferences<_$AppDatabase, $FitnessSessionsTable, FitnessSession>,
      ),
      FitnessSession,
      PrefetchHooks Function()
    >;
typedef $$FitnessPlansTableCreateCompanionBuilder =
    FitnessPlansCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String name,
      required int weekdayMask,
      required String exercises,
      required String startDate,
      required bool active,
      Value<int> rowid,
    });
typedef $$FitnessPlansTableUpdateCompanionBuilder =
    FitnessPlansCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> name,
      Value<int> weekdayMask,
      Value<String> exercises,
      Value<String> startDate,
      Value<bool> active,
      Value<int> rowid,
    });

class $$FitnessPlansTableFilterComposer
    extends Composer<_$AppDatabase, $FitnessPlansTable> {
  $$FitnessPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weekdayMask => $composableBuilder(
    column: $table.weekdayMask,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exercises => $composableBuilder(
    column: $table.exercises,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FitnessPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $FitnessPlansTable> {
  $$FitnessPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weekdayMask => $composableBuilder(
    column: $table.weekdayMask,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exercises => $composableBuilder(
    column: $table.exercises,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FitnessPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $FitnessPlansTable> {
  $$FitnessPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get weekdayMask => $composableBuilder(
    column: $table.weekdayMask,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exercises =>
      $composableBuilder(column: $table.exercises, builder: (column) => column);

  GeneratedColumn<String> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);
}

class $$FitnessPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FitnessPlansTable,
          FitnessPlan,
          $$FitnessPlansTableFilterComposer,
          $$FitnessPlansTableOrderingComposer,
          $$FitnessPlansTableAnnotationComposer,
          $$FitnessPlansTableCreateCompanionBuilder,
          $$FitnessPlansTableUpdateCompanionBuilder,
          (
            FitnessPlan,
            BaseReferences<_$AppDatabase, $FitnessPlansTable, FitnessPlan>,
          ),
          FitnessPlan,
          PrefetchHooks Function()
        > {
  $$FitnessPlansTableTableManager(_$AppDatabase db, $FitnessPlansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FitnessPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FitnessPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FitnessPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> weekdayMask = const Value.absent(),
                Value<String> exercises = const Value.absent(),
                Value<String> startDate = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FitnessPlansCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                weekdayMask: weekdayMask,
                exercises: exercises,
                startDate: startDate,
                active: active,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String name,
                required int weekdayMask,
                required String exercises,
                required String startDate,
                required bool active,
                Value<int> rowid = const Value.absent(),
              }) => FitnessPlansCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                weekdayMask: weekdayMask,
                exercises: exercises,
                startDate: startDate,
                active: active,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FitnessPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FitnessPlansTable,
      FitnessPlan,
      $$FitnessPlansTableFilterComposer,
      $$FitnessPlansTableOrderingComposer,
      $$FitnessPlansTableAnnotationComposer,
      $$FitnessPlansTableCreateCompanionBuilder,
      $$FitnessPlansTableUpdateCompanionBuilder,
      (
        FitnessPlan,
        BaseReferences<_$AppDatabase, $FitnessPlansTable, FitnessPlan>,
      ),
      FitnessPlan,
      PrefetchHooks Function()
    >;
typedef $$ExerciseSetsTableCreateCompanionBuilder =
    ExerciseSetsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String sessionId,
      required String exerciseRef,
      required int weightKgX10,
      required int reps,
      Value<double?> rpe,
      Value<int?> restS,
      required int doneAt,
      required int sort,
      Value<int> rowid,
    });
typedef $$ExerciseSetsTableUpdateCompanionBuilder =
    ExerciseSetsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> sessionId,
      Value<String> exerciseRef,
      Value<int> weightKgX10,
      Value<int> reps,
      Value<double?> rpe,
      Value<int?> restS,
      Value<int> doneAt,
      Value<int> sort,
      Value<int> rowid,
    });

class $$ExerciseSetsTableFilterComposer
    extends Composer<_$AppDatabase, $ExerciseSetsTable> {
  $$ExerciseSetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseRef => $composableBuilder(
    column: $table.exerciseRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get weightKgX10 => $composableBuilder(
    column: $table.weightKgX10,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get rpe => $composableBuilder(
    column: $table.rpe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get restS => $composableBuilder(
    column: $table.restS,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExerciseSetsTableOrderingComposer
    extends Composer<_$AppDatabase, $ExerciseSetsTable> {
  $$ExerciseSetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseRef => $composableBuilder(
    column: $table.exerciseRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get weightKgX10 => $composableBuilder(
    column: $table.weightKgX10,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get rpe => $composableBuilder(
    column: $table.rpe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get restS => $composableBuilder(
    column: $table.restS,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExerciseSetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExerciseSetsTable> {
  $$ExerciseSetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get exerciseRef => $composableBuilder(
    column: $table.exerciseRef,
    builder: (column) => column,
  );

  GeneratedColumn<int> get weightKgX10 => $composableBuilder(
    column: $table.weightKgX10,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<double> get rpe =>
      $composableBuilder(column: $table.rpe, builder: (column) => column);

  GeneratedColumn<int> get restS =>
      $composableBuilder(column: $table.restS, builder: (column) => column);

  GeneratedColumn<int> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$ExerciseSetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExerciseSetsTable,
          ExerciseSet,
          $$ExerciseSetsTableFilterComposer,
          $$ExerciseSetsTableOrderingComposer,
          $$ExerciseSetsTableAnnotationComposer,
          $$ExerciseSetsTableCreateCompanionBuilder,
          $$ExerciseSetsTableUpdateCompanionBuilder,
          (
            ExerciseSet,
            BaseReferences<_$AppDatabase, $ExerciseSetsTable, ExerciseSet>,
          ),
          ExerciseSet,
          PrefetchHooks Function()
        > {
  $$ExerciseSetsTableTableManager(_$AppDatabase db, $ExerciseSetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExerciseSetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExerciseSetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExerciseSetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> exerciseRef = const Value.absent(),
                Value<int> weightKgX10 = const Value.absent(),
                Value<int> reps = const Value.absent(),
                Value<double?> rpe = const Value.absent(),
                Value<int?> restS = const Value.absent(),
                Value<int> doneAt = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExerciseSetsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                sessionId: sessionId,
                exerciseRef: exerciseRef,
                weightKgX10: weightKgX10,
                reps: reps,
                rpe: rpe,
                restS: restS,
                doneAt: doneAt,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String sessionId,
                required String exerciseRef,
                required int weightKgX10,
                required int reps,
                Value<double?> rpe = const Value.absent(),
                Value<int?> restS = const Value.absent(),
                required int doneAt,
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => ExerciseSetsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                sessionId: sessionId,
                exerciseRef: exerciseRef,
                weightKgX10: weightKgX10,
                reps: reps,
                rpe: rpe,
                restS: restS,
                doneAt: doneAt,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExerciseSetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExerciseSetsTable,
      ExerciseSet,
      $$ExerciseSetsTableFilterComposer,
      $$ExerciseSetsTableOrderingComposer,
      $$ExerciseSetsTableAnnotationComposer,
      $$ExerciseSetsTableCreateCompanionBuilder,
      $$ExerciseSetsTableUpdateCompanionBuilder,
      (
        ExerciseSet,
        BaseReferences<_$AppDatabase, $ExerciseSetsTable, ExerciseSet>,
      ),
      ExerciseSet,
      PrefetchHooks Function()
    >;
typedef $$SavingsGoalsTableCreateCompanionBuilder =
    SavingsGoalsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String name,
      required int targetMinor,
      Value<String?> deadline,
      required String method,
      required String rhythm,
      required String status,
      required String startedOn,
      Value<int> rowid,
    });
typedef $$SavingsGoalsTableUpdateCompanionBuilder =
    SavingsGoalsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> name,
      Value<int> targetMinor,
      Value<String?> deadline,
      Value<String> method,
      Value<String> rhythm,
      Value<String> status,
      Value<String> startedOn,
      Value<int> rowid,
    });

class $$SavingsGoalsTableFilterComposer
    extends Composer<_$AppDatabase, $SavingsGoalsTable> {
  $$SavingsGoalsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get targetMinor => $composableBuilder(
    column: $table.targetMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rhythm => $composableBuilder(
    column: $table.rhythm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get startedOn => $composableBuilder(
    column: $table.startedOn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavingsGoalsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavingsGoalsTable> {
  $$SavingsGoalsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get targetMinor => $composableBuilder(
    column: $table.targetMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deadline => $composableBuilder(
    column: $table.deadline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rhythm => $composableBuilder(
    column: $table.rhythm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get startedOn => $composableBuilder(
    column: $table.startedOn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavingsGoalsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavingsGoalsTable> {
  $$SavingsGoalsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get targetMinor => $composableBuilder(
    column: $table.targetMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deadline =>
      $composableBuilder(column: $table.deadline, builder: (column) => column);

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get rhythm =>
      $composableBuilder(column: $table.rhythm, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get startedOn =>
      $composableBuilder(column: $table.startedOn, builder: (column) => column);
}

class $$SavingsGoalsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavingsGoalsTable,
          SavingsGoal,
          $$SavingsGoalsTableFilterComposer,
          $$SavingsGoalsTableOrderingComposer,
          $$SavingsGoalsTableAnnotationComposer,
          $$SavingsGoalsTableCreateCompanionBuilder,
          $$SavingsGoalsTableUpdateCompanionBuilder,
          (
            SavingsGoal,
            BaseReferences<_$AppDatabase, $SavingsGoalsTable, SavingsGoal>,
          ),
          SavingsGoal,
          PrefetchHooks Function()
        > {
  $$SavingsGoalsTableTableManager(_$AppDatabase db, $SavingsGoalsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavingsGoalsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavingsGoalsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavingsGoalsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> targetMinor = const Value.absent(),
                Value<String?> deadline = const Value.absent(),
                Value<String> method = const Value.absent(),
                Value<String> rhythm = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> startedOn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavingsGoalsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                targetMinor: targetMinor,
                deadline: deadline,
                method: method,
                rhythm: rhythm,
                status: status,
                startedOn: startedOn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String name,
                required int targetMinor,
                Value<String?> deadline = const Value.absent(),
                required String method,
                required String rhythm,
                required String status,
                required String startedOn,
                Value<int> rowid = const Value.absent(),
              }) => SavingsGoalsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                targetMinor: targetMinor,
                deadline: deadline,
                method: method,
                rhythm: rhythm,
                status: status,
                startedOn: startedOn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavingsGoalsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavingsGoalsTable,
      SavingsGoal,
      $$SavingsGoalsTableFilterComposer,
      $$SavingsGoalsTableOrderingComposer,
      $$SavingsGoalsTableAnnotationComposer,
      $$SavingsGoalsTableCreateCompanionBuilder,
      $$SavingsGoalsTableUpdateCompanionBuilder,
      (
        SavingsGoal,
        BaseReferences<_$AppDatabase, $SavingsGoalsTable, SavingsGoal>,
      ),
      SavingsGoal,
      PrefetchHooks Function()
    >;
typedef $$SavingsContributionsTableCreateCompanionBuilder =
    SavingsContributionsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String goalId,
      required String date,
      required int amountMinor,
      Value<int?> slot,
      Value<String?> note,
      Value<int> rowid,
    });
typedef $$SavingsContributionsTableUpdateCompanionBuilder =
    SavingsContributionsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> goalId,
      Value<String> date,
      Value<int> amountMinor,
      Value<int?> slot,
      Value<String?> note,
      Value<int> rowid,
    });

class $$SavingsContributionsTableFilterComposer
    extends Composer<_$AppDatabase, $SavingsContributionsTable> {
  $$SavingsContributionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get goalId => $composableBuilder(
    column: $table.goalId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavingsContributionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavingsContributionsTable> {
  $$SavingsContributionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get goalId => $composableBuilder(
    column: $table.goalId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavingsContributionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavingsContributionsTable> {
  $$SavingsContributionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get goalId =>
      $composableBuilder(column: $table.goalId, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$SavingsContributionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavingsContributionsTable,
          SavingsContribution,
          $$SavingsContributionsTableFilterComposer,
          $$SavingsContributionsTableOrderingComposer,
          $$SavingsContributionsTableAnnotationComposer,
          $$SavingsContributionsTableCreateCompanionBuilder,
          $$SavingsContributionsTableUpdateCompanionBuilder,
          (
            SavingsContribution,
            BaseReferences<
              _$AppDatabase,
              $SavingsContributionsTable,
              SavingsContribution
            >,
          ),
          SavingsContribution,
          PrefetchHooks Function()
        > {
  $$SavingsContributionsTableTableManager(
    _$AppDatabase db,
    $SavingsContributionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavingsContributionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavingsContributionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SavingsContributionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> goalId = const Value.absent(),
                Value<String> date = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<int?> slot = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavingsContributionsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                goalId: goalId,
                date: date,
                amountMinor: amountMinor,
                slot: slot,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String goalId,
                required String date,
                required int amountMinor,
                Value<int?> slot = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavingsContributionsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                goalId: goalId,
                date: date,
                amountMinor: amountMinor,
                slot: slot,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavingsContributionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavingsContributionsTable,
      SavingsContribution,
      $$SavingsContributionsTableFilterComposer,
      $$SavingsContributionsTableOrderingComposer,
      $$SavingsContributionsTableAnnotationComposer,
      $$SavingsContributionsTableCreateCompanionBuilder,
      $$SavingsContributionsTableUpdateCompanionBuilder,
      (
        SavingsContribution,
        BaseReferences<
          _$AppDatabase,
          $SavingsContributionsTable,
          SavingsContribution
        >,
      ),
      SavingsContribution,
      PrefetchHooks Function()
    >;
typedef $$CorrectionsTableCreateCompanionBuilder =
    CorrectionsCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String entryId,
      Value<String?> lineId,
      required String field,
      required String oldValue,
      required String newValue,
      required String source,
      Value<int> rowid,
    });
typedef $$CorrectionsTableUpdateCompanionBuilder =
    CorrectionsCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> entryId,
      Value<String?> lineId,
      Value<String> field,
      Value<String> oldValue,
      Value<String> newValue,
      Value<String> source,
      Value<int> rowid,
    });

class $$CorrectionsTableFilterComposer
    extends Composer<_$AppDatabase, $CorrectionsTable> {
  $$CorrectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get oldValue => $composableBuilder(
    column: $table.oldValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get newValue => $composableBuilder(
    column: $table.newValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CorrectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CorrectionsTable> {
  $$CorrectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lineId => $composableBuilder(
    column: $table.lineId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get field => $composableBuilder(
    column: $table.field,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get oldValue => $composableBuilder(
    column: $table.oldValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get newValue => $composableBuilder(
    column: $table.newValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CorrectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CorrectionsTable> {
  $$CorrectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get lineId =>
      $composableBuilder(column: $table.lineId, builder: (column) => column);

  GeneratedColumn<String> get field =>
      $composableBuilder(column: $table.field, builder: (column) => column);

  GeneratedColumn<String> get oldValue =>
      $composableBuilder(column: $table.oldValue, builder: (column) => column);

  GeneratedColumn<String> get newValue =>
      $composableBuilder(column: $table.newValue, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$CorrectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CorrectionsTable,
          Correction,
          $$CorrectionsTableFilterComposer,
          $$CorrectionsTableOrderingComposer,
          $$CorrectionsTableAnnotationComposer,
          $$CorrectionsTableCreateCompanionBuilder,
          $$CorrectionsTableUpdateCompanionBuilder,
          (
            Correction,
            BaseReferences<_$AppDatabase, $CorrectionsTable, Correction>,
          ),
          Correction,
          PrefetchHooks Function()
        > {
  $$CorrectionsTableTableManager(_$AppDatabase db, $CorrectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CorrectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CorrectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CorrectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> entryId = const Value.absent(),
                Value<String?> lineId = const Value.absent(),
                Value<String> field = const Value.absent(),
                Value<String> oldValue = const Value.absent(),
                Value<String> newValue = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CorrectionsCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                lineId: lineId,
                field: field,
                oldValue: oldValue,
                newValue: newValue,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String entryId,
                Value<String?> lineId = const Value.absent(),
                required String field,
                required String oldValue,
                required String newValue,
                required String source,
                Value<int> rowid = const Value.absent(),
              }) => CorrectionsCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                entryId: entryId,
                lineId: lineId,
                field: field,
                oldValue: oldValue,
                newValue: newValue,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CorrectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CorrectionsTable,
      Correction,
      $$CorrectionsTableFilterComposer,
      $$CorrectionsTableOrderingComposer,
      $$CorrectionsTableAnnotationComposer,
      $$CorrectionsTableCreateCompanionBuilder,
      $$CorrectionsTableUpdateCompanionBuilder,
      (
        Correction,
        BaseReferences<_$AppDatabase, $CorrectionsTable, Correction>,
      ),
      Correction,
      PrefetchHooks Function()
    >;
typedef $$ThemeProfilesTableCreateCompanionBuilder =
    ThemeProfilesCompanion Function({
      required int createdAt,
      required int updatedAt,
      Value<int?> deletedAt,
      required String hlc,
      required int revision,
      Value<int> schemaVer,
      required String deviceId,
      required String id,
      required String name,
      required String tokens,
      required String motionLevel,
      Value<String?> fontId,
      required bool isPreset,
      required int sort,
      Value<int> rowid,
    });
typedef $$ThemeProfilesTableUpdateCompanionBuilder =
    ThemeProfilesCompanion Function({
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int?> deletedAt,
      Value<String> hlc,
      Value<int> revision,
      Value<int> schemaVer,
      Value<String> deviceId,
      Value<String> id,
      Value<String> name,
      Value<String> tokens,
      Value<String> motionLevel,
      Value<String?> fontId,
      Value<bool> isPreset,
      Value<int> sort,
      Value<int> rowid,
    });

class $$ThemeProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ThemeProfilesTable> {
  $$ThemeProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokens => $composableBuilder(
    column: $table.tokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get motionLevel => $composableBuilder(
    column: $table.motionLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fontId => $composableBuilder(
    column: $table.fontId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPreset => $composableBuilder(
    column: $table.isPreset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ThemeProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ThemeProfilesTable> {
  $$ThemeProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVer => $composableBuilder(
    column: $table.schemaVer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokens => $composableBuilder(
    column: $table.tokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get motionLevel => $composableBuilder(
    column: $table.motionLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fontId => $composableBuilder(
    column: $table.fontId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPreset => $composableBuilder(
    column: $table.isPreset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sort => $composableBuilder(
    column: $table.sort,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThemeProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ThemeProfilesTable> {
  $$ThemeProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<int> get schemaVer =>
      $composableBuilder(column: $table.schemaVer, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get tokens =>
      $composableBuilder(column: $table.tokens, builder: (column) => column);

  GeneratedColumn<String> get motionLevel => $composableBuilder(
    column: $table.motionLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fontId =>
      $composableBuilder(column: $table.fontId, builder: (column) => column);

  GeneratedColumn<bool> get isPreset =>
      $composableBuilder(column: $table.isPreset, builder: (column) => column);

  GeneratedColumn<int> get sort =>
      $composableBuilder(column: $table.sort, builder: (column) => column);
}

class $$ThemeProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ThemeProfilesTable,
          ThemeProfile,
          $$ThemeProfilesTableFilterComposer,
          $$ThemeProfilesTableOrderingComposer,
          $$ThemeProfilesTableAnnotationComposer,
          $$ThemeProfilesTableCreateCompanionBuilder,
          $$ThemeProfilesTableUpdateCompanionBuilder,
          (
            ThemeProfile,
            BaseReferences<_$AppDatabase, $ThemeProfilesTable, ThemeProfile>,
          ),
          ThemeProfile,
          PrefetchHooks Function()
        > {
  $$ThemeProfilesTableTableManager(_$AppDatabase db, $ThemeProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThemeProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThemeProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThemeProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int?> deletedAt = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> schemaVer = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> tokens = const Value.absent(),
                Value<String> motionLevel = const Value.absent(),
                Value<String?> fontId = const Value.absent(),
                Value<bool> isPreset = const Value.absent(),
                Value<int> sort = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThemeProfilesCompanion(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                tokens: tokens,
                motionLevel: motionLevel,
                fontId: fontId,
                isPreset: isPreset,
                sort: sort,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int createdAt,
                required int updatedAt,
                Value<int?> deletedAt = const Value.absent(),
                required String hlc,
                required int revision,
                Value<int> schemaVer = const Value.absent(),
                required String deviceId,
                required String id,
                required String name,
                required String tokens,
                required String motionLevel,
                Value<String?> fontId = const Value.absent(),
                required bool isPreset,
                required int sort,
                Value<int> rowid = const Value.absent(),
              }) => ThemeProfilesCompanion.insert(
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                hlc: hlc,
                revision: revision,
                schemaVer: schemaVer,
                deviceId: deviceId,
                id: id,
                name: name,
                tokens: tokens,
                motionLevel: motionLevel,
                fontId: fontId,
                isPreset: isPreset,
                sort: sort,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ThemeProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ThemeProfilesTable,
      ThemeProfile,
      $$ThemeProfilesTableFilterComposer,
      $$ThemeProfilesTableOrderingComposer,
      $$ThemeProfilesTableAnnotationComposer,
      $$ThemeProfilesTableCreateCompanionBuilder,
      $$ThemeProfilesTableUpdateCompanionBuilder,
      (
        ThemeProfile,
        BaseReferences<_$AppDatabase, $ThemeProfilesTable, ThemeProfile>,
      ),
      ThemeProfile,
      PrefetchHooks Function()
    >;
typedef $$DaySummariesTableCreateCompanionBuilder =
    DaySummariesCompanion Function({
      required String date,
      required int tzOffsetMin,
      required int kcalIn,
      required int kcalOut,
      required int netKcal,
      required int spendMinor,
      required int incomeMinor,
      required int todoDone,
      required int todoTotal,
      required String budgetSnapshot,
      Value<String?> savingsProgress,
      required int builtAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$DaySummariesTableUpdateCompanionBuilder =
    DaySummariesCompanion Function({
      Value<String> date,
      Value<int> tzOffsetMin,
      Value<int> kcalIn,
      Value<int> kcalOut,
      Value<int> netKcal,
      Value<int> spendMinor,
      Value<int> incomeMinor,
      Value<int> todoDone,
      Value<int> todoTotal,
      Value<String> budgetSnapshot,
      Value<String?> savingsProgress,
      Value<int> builtAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$DaySummariesTableFilterComposer
    extends Composer<_$AppDatabase, $DaySummariesTable> {
  $$DaySummariesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kcalIn => $composableBuilder(
    column: $table.kcalIn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kcalOut => $composableBuilder(
    column: $table.kcalOut,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get netKcal => $composableBuilder(
    column: $table.netKcal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get spendMinor => $composableBuilder(
    column: $table.spendMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get incomeMinor => $composableBuilder(
    column: $table.incomeMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get todoDone => $composableBuilder(
    column: $table.todoDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get todoTotal => $composableBuilder(
    column: $table.todoTotal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get budgetSnapshot => $composableBuilder(
    column: $table.budgetSnapshot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savingsProgress => $composableBuilder(
    column: $table.savingsProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get builtAt => $composableBuilder(
    column: $table.builtAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DaySummariesTableOrderingComposer
    extends Composer<_$AppDatabase, $DaySummariesTable> {
  $$DaySummariesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kcalIn => $composableBuilder(
    column: $table.kcalIn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kcalOut => $composableBuilder(
    column: $table.kcalOut,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get netKcal => $composableBuilder(
    column: $table.netKcal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get spendMinor => $composableBuilder(
    column: $table.spendMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get incomeMinor => $composableBuilder(
    column: $table.incomeMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get todoDone => $composableBuilder(
    column: $table.todoDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get todoTotal => $composableBuilder(
    column: $table.todoTotal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get budgetSnapshot => $composableBuilder(
    column: $table.budgetSnapshot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savingsProgress => $composableBuilder(
    column: $table.savingsProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get builtAt => $composableBuilder(
    column: $table.builtAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DaySummariesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DaySummariesTable> {
  $$DaySummariesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get tzOffsetMin => $composableBuilder(
    column: $table.tzOffsetMin,
    builder: (column) => column,
  );

  GeneratedColumn<int> get kcalIn =>
      $composableBuilder(column: $table.kcalIn, builder: (column) => column);

  GeneratedColumn<int> get kcalOut =>
      $composableBuilder(column: $table.kcalOut, builder: (column) => column);

  GeneratedColumn<int> get netKcal =>
      $composableBuilder(column: $table.netKcal, builder: (column) => column);

  GeneratedColumn<int> get spendMinor => $composableBuilder(
    column: $table.spendMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get incomeMinor => $composableBuilder(
    column: $table.incomeMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get todoDone =>
      $composableBuilder(column: $table.todoDone, builder: (column) => column);

  GeneratedColumn<int> get todoTotal =>
      $composableBuilder(column: $table.todoTotal, builder: (column) => column);

  GeneratedColumn<String> get budgetSnapshot => $composableBuilder(
    column: $table.budgetSnapshot,
    builder: (column) => column,
  );

  GeneratedColumn<String> get savingsProgress => $composableBuilder(
    column: $table.savingsProgress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get builtAt =>
      $composableBuilder(column: $table.builtAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$DaySummariesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DaySummariesTable,
          DaySummary,
          $$DaySummariesTableFilterComposer,
          $$DaySummariesTableOrderingComposer,
          $$DaySummariesTableAnnotationComposer,
          $$DaySummariesTableCreateCompanionBuilder,
          $$DaySummariesTableUpdateCompanionBuilder,
          (
            DaySummary,
            BaseReferences<_$AppDatabase, $DaySummariesTable, DaySummary>,
          ),
          DaySummary,
          PrefetchHooks Function()
        > {
  $$DaySummariesTableTableManager(_$AppDatabase db, $DaySummariesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DaySummariesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DaySummariesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DaySummariesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> date = const Value.absent(),
                Value<int> tzOffsetMin = const Value.absent(),
                Value<int> kcalIn = const Value.absent(),
                Value<int> kcalOut = const Value.absent(),
                Value<int> netKcal = const Value.absent(),
                Value<int> spendMinor = const Value.absent(),
                Value<int> incomeMinor = const Value.absent(),
                Value<int> todoDone = const Value.absent(),
                Value<int> todoTotal = const Value.absent(),
                Value<String> budgetSnapshot = const Value.absent(),
                Value<String?> savingsProgress = const Value.absent(),
                Value<int> builtAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DaySummariesCompanion(
                date: date,
                tzOffsetMin: tzOffsetMin,
                kcalIn: kcalIn,
                kcalOut: kcalOut,
                netKcal: netKcal,
                spendMinor: spendMinor,
                incomeMinor: incomeMinor,
                todoDone: todoDone,
                todoTotal: todoTotal,
                budgetSnapshot: budgetSnapshot,
                savingsProgress: savingsProgress,
                builtAt: builtAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String date,
                required int tzOffsetMin,
                required int kcalIn,
                required int kcalOut,
                required int netKcal,
                required int spendMinor,
                required int incomeMinor,
                required int todoDone,
                required int todoTotal,
                required String budgetSnapshot,
                Value<String?> savingsProgress = const Value.absent(),
                required int builtAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DaySummariesCompanion.insert(
                date: date,
                tzOffsetMin: tzOffsetMin,
                kcalIn: kcalIn,
                kcalOut: kcalOut,
                netKcal: netKcal,
                spendMinor: spendMinor,
                incomeMinor: incomeMinor,
                todoDone: todoDone,
                todoTotal: todoTotal,
                budgetSnapshot: budgetSnapshot,
                savingsProgress: savingsProgress,
                builtAt: builtAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DaySummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DaySummariesTable,
      DaySummary,
      $$DaySummariesTableFilterComposer,
      $$DaySummariesTableOrderingComposer,
      $$DaySummariesTableAnnotationComposer,
      $$DaySummariesTableCreateCompanionBuilder,
      $$DaySummariesTableUpdateCompanionBuilder,
      (
        DaySummary,
        BaseReferences<_$AppDatabase, $DaySummariesTable, DaySummary>,
      ),
      DaySummary,
      PrefetchHooks Function()
    >;
typedef $$AiParsesTableCreateCompanionBuilder =
    AiParsesCompanion Function({
      required String id,
      required String inputKind,
      required String inputHash,
      required String provider,
      required String model,
      required String rawOutput,
      required int latencyMs,
      required int cost,
      required double confidence,
      required String promptVersion,
      Value<int> rowid,
    });
typedef $$AiParsesTableUpdateCompanionBuilder =
    AiParsesCompanion Function({
      Value<String> id,
      Value<String> inputKind,
      Value<String> inputHash,
      Value<String> provider,
      Value<String> model,
      Value<String> rawOutput,
      Value<int> latencyMs,
      Value<int> cost,
      Value<double> confidence,
      Value<String> promptVersion,
      Value<int> rowid,
    });

class $$AiParsesTableFilterComposer
    extends Composer<_$AppDatabase, $AiParsesTable> {
  $$AiParsesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputKind => $composableBuilder(
    column: $table.inputKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputHash => $composableBuilder(
    column: $table.inputHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawOutput => $composableBuilder(
    column: $table.rawOutput,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiParsesTableOrderingComposer
    extends Composer<_$AppDatabase, $AiParsesTable> {
  $$AiParsesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputKind => $composableBuilder(
    column: $table.inputKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputHash => $composableBuilder(
    column: $table.inputHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawOutput => $composableBuilder(
    column: $table.rawOutput,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get latencyMs => $composableBuilder(
    column: $table.latencyMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cost => $composableBuilder(
    column: $table.cost,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiParsesTableAnnotationComposer
    extends Composer<_$AppDatabase, $AiParsesTable> {
  $$AiParsesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get inputKind =>
      $composableBuilder(column: $table.inputKind, builder: (column) => column);

  GeneratedColumn<String> get inputHash =>
      $composableBuilder(column: $table.inputHash, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get rawOutput =>
      $composableBuilder(column: $table.rawOutput, builder: (column) => column);

  GeneratedColumn<int> get latencyMs =>
      $composableBuilder(column: $table.latencyMs, builder: (column) => column);

  GeneratedColumn<int> get cost =>
      $composableBuilder(column: $table.cost, builder: (column) => column);

  GeneratedColumn<double> get confidence => $composableBuilder(
    column: $table.confidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );
}

class $$AiParsesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AiParsesTable,
          AiParse,
          $$AiParsesTableFilterComposer,
          $$AiParsesTableOrderingComposer,
          $$AiParsesTableAnnotationComposer,
          $$AiParsesTableCreateCompanionBuilder,
          $$AiParsesTableUpdateCompanionBuilder,
          (AiParse, BaseReferences<_$AppDatabase, $AiParsesTable, AiParse>),
          AiParse,
          PrefetchHooks Function()
        > {
  $$AiParsesTableTableManager(_$AppDatabase db, $AiParsesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiParsesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiParsesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiParsesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> inputKind = const Value.absent(),
                Value<String> inputHash = const Value.absent(),
                Value<String> provider = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> rawOutput = const Value.absent(),
                Value<int> latencyMs = const Value.absent(),
                Value<int> cost = const Value.absent(),
                Value<double> confidence = const Value.absent(),
                Value<String> promptVersion = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiParsesCompanion(
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
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String inputKind,
                required String inputHash,
                required String provider,
                required String model,
                required String rawOutput,
                required int latencyMs,
                required int cost,
                required double confidence,
                required String promptVersion,
                Value<int> rowid = const Value.absent(),
              }) => AiParsesCompanion.insert(
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
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiParsesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AiParsesTable,
      AiParse,
      $$AiParsesTableFilterComposer,
      $$AiParsesTableOrderingComposer,
      $$AiParsesTableAnnotationComposer,
      $$AiParsesTableCreateCompanionBuilder,
      $$AiParsesTableUpdateCompanionBuilder,
      (AiParse, BaseReferences<_$AppDatabase, $AiParsesTable, AiParse>),
      AiParse,
      PrefetchHooks Function()
    >;
typedef $$SyncOutboxTableCreateCompanionBuilder =
    SyncOutboxCompanion Function({
      required String id,
      required String targetTable,
      required String rowId,
      required String op,
      required String payload,
      Value<int?> baseRevision,
      required String hlc,
      required int createdAt,
      Value<int?> ackedAt,
      Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    SyncOutboxCompanion Function({
      Value<String> id,
      Value<String> targetTable,
      Value<String> rowId,
      Value<String> op,
      Value<String> payload,
      Value<int?> baseRevision,
      Value<String> hlc,
      Value<int> createdAt,
      Value<int?> ackedAt,
      Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ackedAt => $composableBuilder(
    column: $table.ackedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ackedAt => $composableBuilder(
    column: $table.ackedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get ackedAt =>
      $composableBuilder(column: $table.ackedAt, builder: (column) => column);
}

class $$SyncOutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncOutboxTable,
          SyncOutboxItem,
          $$SyncOutboxTableFilterComposer,
          $$SyncOutboxTableOrderingComposer,
          $$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            SyncOutboxItem,
            BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxItem>,
          ),
          SyncOutboxItem,
          PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(_$AppDatabase db, $SyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> targetTable = const Value.absent(),
                Value<String> rowId = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int?> baseRevision = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> ackedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion(
                id: id,
                targetTable: targetTable,
                rowId: rowId,
                op: op,
                payload: payload,
                baseRevision: baseRevision,
                hlc: hlc,
                createdAt: createdAt,
                ackedAt: ackedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String targetTable,
                required String rowId,
                required String op,
                required String payload,
                Value<int?> baseRevision = const Value.absent(),
                required String hlc,
                required int createdAt,
                Value<int?> ackedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncOutboxCompanion.insert(
                id: id,
                targetTable: targetTable,
                rowId: rowId,
                op: op,
                payload: payload,
                baseRevision: baseRevision,
                hlc: hlc,
                createdAt: createdAt,
                ackedAt: ackedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncOutboxTable,
      SyncOutboxItem,
      $$SyncOutboxTableFilterComposer,
      $$SyncOutboxTableOrderingComposer,
      $$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        SyncOutboxItem,
        BaseReferences<_$AppDatabase, $SyncOutboxTable, SyncOutboxItem>,
      ),
      SyncOutboxItem,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String deviceId,
      required String targetTable,
      required String pullHlc,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> deviceId,
      Value<String> targetTable,
      Value<String> pullHlc,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pullHlc => $composableBuilder(
    column: $table.pullHlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pullHlc => $composableBuilder(
    column: $table.pullHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get targetTable => $composableBuilder(
    column: $table.targetTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pullHlc =>
      $composableBuilder(column: $table.pullHlc, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> targetTable = const Value.absent(),
                Value<String> pullHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                deviceId: deviceId,
                targetTable: targetTable,
                pullHlc: pullHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String targetTable,
                required String pullHlc,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                deviceId: deviceId,
                targetTable: targetTable,
                pullHlc: pullHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required String id,
      required String name,
      required String platform,
      required int createdAt,
      required int lastSeenAt,
      Value<int?> revokedAt,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> platform,
      Value<int> createdAt,
      Value<int> lastSeenAt,
      Value<int?> revokedAt,
      Value<int> rowid,
    });

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get platform => $composableBuilder(
    column: $table.platform,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revokedAt => $composableBuilder(
    column: $table.revokedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get platform =>
      $composableBuilder(column: $table.platform, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revokedAt =>
      $composableBuilder(column: $table.revokedAt, builder: (column) => column);
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
          Device,
          PrefetchHooks Function()
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> platform = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> lastSeenAt = const Value.absent(),
                Value<int?> revokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                name: name,
                platform: platform,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                revokedAt: revokedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String platform,
                required int createdAt,
                required int lastSeenAt,
                Value<int?> revokedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                name: name,
                platform: platform,
                createdAt: createdAt,
                lastSeenAt: lastSeenAt,
                revokedAt: revokedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, BaseReferences<_$AppDatabase, $DevicesTable, Device>),
      Device,
      PrefetchHooks Function()
    >;
typedef $$AttachmentsTableCreateCompanionBuilder =
    AttachmentsCompanion Function({
      required String id,
      Value<String?> entryId,
      required String contentHash,
      required String kind,
      required String mime,
      required int sizeBytes,
      required String localPath,
      Value<String?> blobRef,
      Value<String> status,
      Value<int?> burnedAt,
      Value<int> rowid,
    });
typedef $$AttachmentsTableUpdateCompanionBuilder =
    AttachmentsCompanion Function({
      Value<String> id,
      Value<String?> entryId,
      Value<String> contentHash,
      Value<String> kind,
      Value<String> mime,
      Value<int> sizeBytes,
      Value<String> localPath,
      Value<String?> blobRef,
      Value<String> status,
      Value<int?> burnedAt,
      Value<int> rowid,
    });

class $$AttachmentsTableFilterComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get blobRef => $composableBuilder(
    column: $table.blobRef,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get burnedAt => $composableBuilder(
    column: $table.burnedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AttachmentsTableOrderingComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryId => $composableBuilder(
    column: $table.entryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mime => $composableBuilder(
    column: $table.mime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get blobRef => $composableBuilder(
    column: $table.blobRef,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get burnedAt => $composableBuilder(
    column: $table.burnedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AttachmentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AttachmentsTable> {
  $$AttachmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entryId =>
      $composableBuilder(column: $table.entryId, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get mime =>
      $composableBuilder(column: $table.mime, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get blobRef =>
      $composableBuilder(column: $table.blobRef, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get burnedAt =>
      $composableBuilder(column: $table.burnedAt, builder: (column) => column);
}

class $$AttachmentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AttachmentsTable,
          Attachment,
          $$AttachmentsTableFilterComposer,
          $$AttachmentsTableOrderingComposer,
          $$AttachmentsTableAnnotationComposer,
          $$AttachmentsTableCreateCompanionBuilder,
          $$AttachmentsTableUpdateCompanionBuilder,
          (
            Attachment,
            BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
          ),
          Attachment,
          PrefetchHooks Function()
        > {
  $$AttachmentsTableTableManager(_$AppDatabase db, $AttachmentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AttachmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AttachmentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AttachmentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String?> entryId = const Value.absent(),
                Value<String> contentHash = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> mime = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<String?> blobRef = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> burnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion(
                id: id,
                entryId: entryId,
                contentHash: contentHash,
                kind: kind,
                mime: mime,
                sizeBytes: sizeBytes,
                localPath: localPath,
                blobRef: blobRef,
                status: status,
                burnedAt: burnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String?> entryId = const Value.absent(),
                required String contentHash,
                required String kind,
                required String mime,
                required int sizeBytes,
                required String localPath,
                Value<String?> blobRef = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> burnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AttachmentsCompanion.insert(
                id: id,
                entryId: entryId,
                contentHash: contentHash,
                kind: kind,
                mime: mime,
                sizeBytes: sizeBytes,
                localPath: localPath,
                blobRef: blobRef,
                status: status,
                burnedAt: burnedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AttachmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AttachmentsTable,
      Attachment,
      $$AttachmentsTableFilterComposer,
      $$AttachmentsTableOrderingComposer,
      $$AttachmentsTableAnnotationComposer,
      $$AttachmentsTableCreateCompanionBuilder,
      $$AttachmentsTableUpdateCompanionBuilder,
      (
        Attachment,
        BaseReferences<_$AppDatabase, $AttachmentsTable, Attachment>,
      ),
      Attachment,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$EntriesTableTableManager get entries =>
      $$EntriesTableTableManager(_db, _db.entries);
  $$EntryLinesTableTableManager get entryLines =>
      $$EntryLinesTableTableManager(_db, _db.entryLines);
  $$FoodItemsTableTableManager get foodItems =>
      $$FoodItemsTableTableManager(_db, _db.foodItems);
  $$LedgersTableTableManager get ledgers =>
      $$LedgersTableTableManager(_db, _db.ledgers);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$BudgetsTableTableManager get budgets =>
      $$BudgetsTableTableManager(_db, _db.budgets);
  $$TodosTableTableManager get todos =>
      $$TodosTableTableManager(_db, _db.todos);
  $$FitnessSessionsTableTableManager get fitnessSessions =>
      $$FitnessSessionsTableTableManager(_db, _db.fitnessSessions);
  $$FitnessPlansTableTableManager get fitnessPlans =>
      $$FitnessPlansTableTableManager(_db, _db.fitnessPlans);
  $$ExerciseSetsTableTableManager get exerciseSets =>
      $$ExerciseSetsTableTableManager(_db, _db.exerciseSets);
  $$SavingsGoalsTableTableManager get savingsGoals =>
      $$SavingsGoalsTableTableManager(_db, _db.savingsGoals);
  $$SavingsContributionsTableTableManager get savingsContributions =>
      $$SavingsContributionsTableTableManager(_db, _db.savingsContributions);
  $$CorrectionsTableTableManager get corrections =>
      $$CorrectionsTableTableManager(_db, _db.corrections);
  $$ThemeProfilesTableTableManager get themeProfiles =>
      $$ThemeProfilesTableTableManager(_db, _db.themeProfiles);
  $$DaySummariesTableTableManager get daySummaries =>
      $$DaySummariesTableTableManager(_db, _db.daySummaries);
  $$AiParsesTableTableManager get aiParses =>
      $$AiParsesTableTableManager(_db, _db.aiParses);
  $$SyncOutboxTableTableManager get syncOutbox =>
      $$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$AttachmentsTableTableManager get attachments =>
      $$AttachmentsTableTableManager(_db, _db.attachments);
}
