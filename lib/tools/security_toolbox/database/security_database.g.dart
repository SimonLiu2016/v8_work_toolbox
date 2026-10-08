// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'security_database.dart';

// ignore_for_file: type=lint
class $PentestSessionsTable extends PentestSessions
    with TableInfo<$PentestSessionsTable, PentestSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PentestSessionsTable(this.attachedDatabase, [this._alias]);
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 200,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('lan'),
  );
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
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
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    type,
    scope,
    status,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pentest_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<PentestSession> instance, {
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
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PentestSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PentestSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PentestSessionsTable createAlias(String alias) {
    return $PentestSessionsTable(attachedDatabase, alias);
  }
}

class PentestSession extends DataClass implements Insertable<PentestSession> {
  final String id;
  final String name;
  final String type;
  final String scope;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PentestSession({
    required this.id,
    required this.name,
    required this.type,
    required this.scope,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['scope'] = Variable<String>(scope);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PentestSessionsCompanion toCompanion(bool nullToAbsent) {
    return PentestSessionsCompanion(
      id: Value(id),
      name: Value(name),
      type: Value(type),
      scope: Value(scope),
      status: Value(status),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PentestSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PentestSession(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      scope: serializer.fromJson<String>(json['scope']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'scope': serializer.toJson<String>(scope),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PentestSession copyWith({
    String? id,
    String? name,
    String? type,
    String? scope,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PentestSession(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    scope: scope ?? this.scope,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PentestSession copyWithCompanion(PentestSessionsCompanion data) {
    return PentestSession(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      scope: data.scope.present ? data.scope.value : this.scope,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PentestSession(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('scope: $scope, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, type, scope, status, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PentestSession &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.scope == this.scope &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PentestSessionsCompanion extends UpdateCompanion<PentestSession> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> type;
  final Value<String> scope;
  final Value<String> status;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PentestSessionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.scope = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PentestSessionsCompanion.insert({
    required String id,
    required String name,
    this.type = const Value.absent(),
    this.scope = const Value.absent(),
    this.status = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<PentestSession> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? scope,
    Expression<String>? status,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (scope != null) 'scope': scope,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PentestSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? type,
    Value<String>? scope,
    Value<String>? status,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return PentestSessionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      scope: scope ?? this.scope,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PentestSessionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('scope: $scope, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionAssetsTable extends SessionAssets
    with TableInfo<$SessionAssetsTable, SessionAsset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionAssetsTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pentest_sessions (id)',
    ),
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('host'),
  );
  static const VerificationMeta _addressMeta = const VerificationMeta(
    'address',
  );
  @override
  late final GeneratedColumn<String> address = GeneratedColumn<String>(
    'address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _riskLevelMeta = const VerificationMeta(
    'riskLevel',
  );
  @override
  late final GeneratedColumn<String> riskLevel = GeneratedColumn<String>(
    'risk_level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _userNoteMeta = const VerificationMeta(
    'userNote',
  );
  @override
  late final GeneratedColumn<String> userNote = GeneratedColumn<String>(
    'user_note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    type,
    address,
    metadata,
    riskLevel,
    userNote,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_assets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionAsset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('address')) {
      context.handle(
        _addressMeta,
        address.isAcceptableOrUnknown(data['address']!, _addressMeta),
      );
    } else if (isInserting) {
      context.missing(_addressMeta);
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('risk_level')) {
      context.handle(
        _riskLevelMeta,
        riskLevel.isAcceptableOrUnknown(data['risk_level']!, _riskLevelMeta),
      );
    }
    if (data.containsKey('user_note')) {
      context.handle(
        _userNoteMeta,
        userNote.isAcceptableOrUnknown(data['user_note']!, _userNoteMeta),
      );
    }
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionAsset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionAsset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      address: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}address'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      )!,
      riskLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}risk_level'],
      )!,
      userNote: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_note'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SessionAssetsTable createAlias(String alias) {
    return $SessionAssetsTable(attachedDatabase, alias);
  }
}

class SessionAsset extends DataClass implements Insertable<SessionAsset> {
  final String id;
  final String sessionId;
  final String type;
  final String address;

  /// JSON：os / mac / vendor / ports / techStack / statusCode / title 等。
  final String metadata;

  /// critical / high / medium / low / info / unknown。
  final String riskLevel;

  /// 用户手工备注；扫描结果合并时不得覆盖（见 spec「资产手动标注」）。
  final String? userNote;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SessionAsset({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.address,
    required this.metadata,
    required this.riskLevel,
    this.userNote,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['type'] = Variable<String>(type);
    map['address'] = Variable<String>(address);
    map['metadata'] = Variable<String>(metadata);
    map['risk_level'] = Variable<String>(riskLevel);
    if (!nullToAbsent || userNote != null) {
      map['user_note'] = Variable<String>(userNote);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SessionAssetsCompanion toCompanion(bool nullToAbsent) {
    return SessionAssetsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      type: Value(type),
      address: Value(address),
      metadata: Value(metadata),
      riskLevel: Value(riskLevel),
      userNote: userNote == null && nullToAbsent
          ? const Value.absent()
          : Value(userNote),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionAsset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionAsset(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      type: serializer.fromJson<String>(json['type']),
      address: serializer.fromJson<String>(json['address']),
      metadata: serializer.fromJson<String>(json['metadata']),
      riskLevel: serializer.fromJson<String>(json['riskLevel']),
      userNote: serializer.fromJson<String?>(json['userNote']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'type': serializer.toJson<String>(type),
      'address': serializer.toJson<String>(address),
      'metadata': serializer.toJson<String>(metadata),
      'riskLevel': serializer.toJson<String>(riskLevel),
      'userNote': serializer.toJson<String?>(userNote),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionAsset copyWith({
    String? id,
    String? sessionId,
    String? type,
    String? address,
    String? metadata,
    String? riskLevel,
    Value<String?> userNote = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionAsset(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    type: type ?? this.type,
    address: address ?? this.address,
    metadata: metadata ?? this.metadata,
    riskLevel: riskLevel ?? this.riskLevel,
    userNote: userNote.present ? userNote.value : this.userNote,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionAsset copyWithCompanion(SessionAssetsCompanion data) {
    return SessionAsset(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      type: data.type.present ? data.type.value : this.type,
      address: data.address.present ? data.address.value : this.address,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      riskLevel: data.riskLevel.present ? data.riskLevel.value : this.riskLevel,
      userNote: data.userNote.present ? data.userNote.value : this.userNote,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionAsset(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('address: $address, ')
          ..write('metadata: $metadata, ')
          ..write('riskLevel: $riskLevel, ')
          ..write('userNote: $userNote, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    type,
    address,
    metadata,
    riskLevel,
    userNote,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionAsset &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.type == this.type &&
          other.address == this.address &&
          other.metadata == this.metadata &&
          other.riskLevel == this.riskLevel &&
          other.userNote == this.userNote &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionAssetsCompanion extends UpdateCompanion<SessionAsset> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> type;
  final Value<String> address;
  final Value<String> metadata;
  final Value<String> riskLevel;
  final Value<String?> userNote;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionAssetsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.type = const Value.absent(),
    this.address = const Value.absent(),
    this.metadata = const Value.absent(),
    this.riskLevel = const Value.absent(),
    this.userNote = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionAssetsCompanion.insert({
    required String id,
    required String sessionId,
    this.type = const Value.absent(),
    required String address,
    this.metadata = const Value.absent(),
    this.riskLevel = const Value.absent(),
    this.userNote = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       address = Value(address),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SessionAsset> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? type,
    Expression<String>? address,
    Expression<String>? metadata,
    Expression<String>? riskLevel,
    Expression<String>? userNote,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (type != null) 'type': type,
      if (address != null) 'address': address,
      if (metadata != null) 'metadata': metadata,
      if (riskLevel != null) 'risk_level': riskLevel,
      if (userNote != null) 'user_note': userNote,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionAssetsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? type,
    Value<String>? address,
    Value<String>? metadata,
    Value<String>? riskLevel,
    Value<String?>? userNote,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionAssetsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      type: type ?? this.type,
      address: address ?? this.address,
      metadata: metadata ?? this.metadata,
      riskLevel: riskLevel ?? this.riskLevel,
      userNote: userNote ?? this.userNote,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (address.present) {
      map['address'] = Variable<String>(address.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (riskLevel.present) {
      map['risk_level'] = Variable<String>(riskLevel.value);
    }
    if (userNote.present) {
      map['user_note'] = Variable<String>(userNote.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionAssetsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('type: $type, ')
          ..write('address: $address, ')
          ..write('metadata: $metadata, ')
          ..write('riskLevel: $riskLevel, ')
          ..write('userNote: $userNote, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionFindingsTable extends SessionFindings
    with TableInfo<$SessionFindingsTable, SessionFinding> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionFindingsTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pentest_sessions (id)',
    ),
  );
  static const VerificationMeta _assetIdMeta = const VerificationMeta(
    'assetId',
  );
  @override
  late final GeneratedColumn<String> assetId = GeneratedColumn<String>(
    'asset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES session_assets (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _cveIdMeta = const VerificationMeta('cveId');
  @override
  late final GeneratedColumn<String> cveId = GeneratedColumn<String>(
    'cve_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('info'),
  );
  static const VerificationMeta _cvssScoreMeta = const VerificationMeta(
    'cvssScore',
  );
  @override
  late final GeneratedColumn<double> cvssScore = GeneratedColumn<double>(
    'cvss_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
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
    defaultValue: const Constant('open'),
  );
  static const VerificationMeta _evidenceMeta = const VerificationMeta(
    'evidence',
  );
  @override
  late final GeneratedColumn<String> evidence = GeneratedColumn<String>(
    'evidence',
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
    requiredDuringInsert: false,
    defaultValue: const Constant('manual'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    assetId,
    cveId,
    title,
    severity,
    cvssScore,
    status,
    evidence,
    source,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_findings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionFinding> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('asset_id')) {
      context.handle(
        _assetIdMeta,
        assetId.isAcceptableOrUnknown(data['asset_id']!, _assetIdMeta),
      );
    }
    if (data.containsKey('cve_id')) {
      context.handle(
        _cveIdMeta,
        cveId.isAcceptableOrUnknown(data['cve_id']!, _cveIdMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('cvss_score')) {
      context.handle(
        _cvssScoreMeta,
        cvssScore.isAcceptableOrUnknown(data['cvss_score']!, _cvssScoreMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('evidence')) {
      context.handle(
        _evidenceMeta,
        evidence.isAcceptableOrUnknown(data['evidence']!, _evidenceMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionFinding map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionFinding(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      assetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}asset_id'],
      ),
      cveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cve_id'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      cvssScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cvss_score'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      evidence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SessionFindingsTable createAlias(String alias) {
    return $SessionFindingsTable(attachedDatabase, alias);
  }
}

class SessionFinding extends DataClass implements Insertable<SessionFinding> {
  final String id;
  final String sessionId;
  final String? assetId;
  final String? cveId;
  final String title;
  final String severity;
  final double? cvssScore;
  final String status;
  final String? evidence;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SessionFinding({
    required this.id,
    required this.sessionId,
    this.assetId,
    this.cveId,
    required this.title,
    required this.severity,
    this.cvssScore,
    required this.status,
    this.evidence,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    if (!nullToAbsent || assetId != null) {
      map['asset_id'] = Variable<String>(assetId);
    }
    if (!nullToAbsent || cveId != null) {
      map['cve_id'] = Variable<String>(cveId);
    }
    map['title'] = Variable<String>(title);
    map['severity'] = Variable<String>(severity);
    if (!nullToAbsent || cvssScore != null) {
      map['cvss_score'] = Variable<double>(cvssScore);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || evidence != null) {
      map['evidence'] = Variable<String>(evidence);
    }
    map['source'] = Variable<String>(source);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SessionFindingsCompanion toCompanion(bool nullToAbsent) {
    return SessionFindingsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      assetId: assetId == null && nullToAbsent
          ? const Value.absent()
          : Value(assetId),
      cveId: cveId == null && nullToAbsent
          ? const Value.absent()
          : Value(cveId),
      title: Value(title),
      severity: Value(severity),
      cvssScore: cvssScore == null && nullToAbsent
          ? const Value.absent()
          : Value(cvssScore),
      status: Value(status),
      evidence: evidence == null && nullToAbsent
          ? const Value.absent()
          : Value(evidence),
      source: Value(source),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionFinding.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionFinding(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      assetId: serializer.fromJson<String?>(json['assetId']),
      cveId: serializer.fromJson<String?>(json['cveId']),
      title: serializer.fromJson<String>(json['title']),
      severity: serializer.fromJson<String>(json['severity']),
      cvssScore: serializer.fromJson<double?>(json['cvssScore']),
      status: serializer.fromJson<String>(json['status']),
      evidence: serializer.fromJson<String?>(json['evidence']),
      source: serializer.fromJson<String>(json['source']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'assetId': serializer.toJson<String?>(assetId),
      'cveId': serializer.toJson<String?>(cveId),
      'title': serializer.toJson<String>(title),
      'severity': serializer.toJson<String>(severity),
      'cvssScore': serializer.toJson<double?>(cvssScore),
      'status': serializer.toJson<String>(status),
      'evidence': serializer.toJson<String?>(evidence),
      'source': serializer.toJson<String>(source),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionFinding copyWith({
    String? id,
    String? sessionId,
    Value<String?> assetId = const Value.absent(),
    Value<String?> cveId = const Value.absent(),
    String? title,
    String? severity,
    Value<double?> cvssScore = const Value.absent(),
    String? status,
    Value<String?> evidence = const Value.absent(),
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionFinding(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    assetId: assetId.present ? assetId.value : this.assetId,
    cveId: cveId.present ? cveId.value : this.cveId,
    title: title ?? this.title,
    severity: severity ?? this.severity,
    cvssScore: cvssScore.present ? cvssScore.value : this.cvssScore,
    status: status ?? this.status,
    evidence: evidence.present ? evidence.value : this.evidence,
    source: source ?? this.source,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionFinding copyWithCompanion(SessionFindingsCompanion data) {
    return SessionFinding(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      assetId: data.assetId.present ? data.assetId.value : this.assetId,
      cveId: data.cveId.present ? data.cveId.value : this.cveId,
      title: data.title.present ? data.title.value : this.title,
      severity: data.severity.present ? data.severity.value : this.severity,
      cvssScore: data.cvssScore.present ? data.cvssScore.value : this.cvssScore,
      status: data.status.present ? data.status.value : this.status,
      evidence: data.evidence.present ? data.evidence.value : this.evidence,
      source: data.source.present ? data.source.value : this.source,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionFinding(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('assetId: $assetId, ')
          ..write('cveId: $cveId, ')
          ..write('title: $title, ')
          ..write('severity: $severity, ')
          ..write('cvssScore: $cvssScore, ')
          ..write('status: $status, ')
          ..write('evidence: $evidence, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    assetId,
    cveId,
    title,
    severity,
    cvssScore,
    status,
    evidence,
    source,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionFinding &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.assetId == this.assetId &&
          other.cveId == this.cveId &&
          other.title == this.title &&
          other.severity == this.severity &&
          other.cvssScore == this.cvssScore &&
          other.status == this.status &&
          other.evidence == this.evidence &&
          other.source == this.source &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionFindingsCompanion extends UpdateCompanion<SessionFinding> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String?> assetId;
  final Value<String?> cveId;
  final Value<String> title;
  final Value<String> severity;
  final Value<double?> cvssScore;
  final Value<String> status;
  final Value<String?> evidence;
  final Value<String> source;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionFindingsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.assetId = const Value.absent(),
    this.cveId = const Value.absent(),
    this.title = const Value.absent(),
    this.severity = const Value.absent(),
    this.cvssScore = const Value.absent(),
    this.status = const Value.absent(),
    this.evidence = const Value.absent(),
    this.source = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionFindingsCompanion.insert({
    required String id,
    required String sessionId,
    this.assetId = const Value.absent(),
    this.cveId = const Value.absent(),
    required String title,
    this.severity = const Value.absent(),
    this.cvssScore = const Value.absent(),
    this.status = const Value.absent(),
    this.evidence = const Value.absent(),
    this.source = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       title = Value(title),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SessionFinding> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? assetId,
    Expression<String>? cveId,
    Expression<String>? title,
    Expression<String>? severity,
    Expression<double>? cvssScore,
    Expression<String>? status,
    Expression<String>? evidence,
    Expression<String>? source,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (assetId != null) 'asset_id': assetId,
      if (cveId != null) 'cve_id': cveId,
      if (title != null) 'title': title,
      if (severity != null) 'severity': severity,
      if (cvssScore != null) 'cvss_score': cvssScore,
      if (status != null) 'status': status,
      if (evidence != null) 'evidence': evidence,
      if (source != null) 'source': source,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionFindingsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String?>? assetId,
    Value<String?>? cveId,
    Value<String>? title,
    Value<String>? severity,
    Value<double?>? cvssScore,
    Value<String>? status,
    Value<String?>? evidence,
    Value<String>? source,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionFindingsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      assetId: assetId ?? this.assetId,
      cveId: cveId ?? this.cveId,
      title: title ?? this.title,
      severity: severity ?? this.severity,
      cvssScore: cvssScore ?? this.cvssScore,
      status: status ?? this.status,
      evidence: evidence ?? this.evidence,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (assetId.present) {
      map['asset_id'] = Variable<String>(assetId.value);
    }
    if (cveId.present) {
      map['cve_id'] = Variable<String>(cveId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (cvssScore.present) {
      map['cvss_score'] = Variable<double>(cvssScore.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (evidence.present) {
      map['evidence'] = Variable<String>(evidence.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionFindingsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('assetId: $assetId, ')
          ..write('cveId: $cveId, ')
          ..write('title: $title, ')
          ..write('severity: $severity, ')
          ..write('cvssScore: $cvssScore, ')
          ..write('status: $status, ')
          ..write('evidence: $evidence, ')
          ..write('source: $source, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionTimelineEventsTable extends SessionTimelineEvents
    with TableInfo<$SessionTimelineEventsTable, SessionTimelineEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionTimelineEventsTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pentest_sessions (id)',
    ),
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
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
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    eventType,
    title,
    detail,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_timeline_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionTimelineEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionTimelineEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionTimelineEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionTimelineEventsTable createAlias(String alias) {
    return $SessionTimelineEventsTable(attachedDatabase, alias);
  }
}

class SessionTimelineEvent extends DataClass
    implements Insertable<SessionTimelineEvent> {
  final String id;
  final String sessionId;
  final String eventType;
  final String title;

  /// JSON：command / args / durationMs / aiText 等。
  final String detail;
  final DateTime createdAt;
  const SessionTimelineEvent({
    required this.id,
    required this.sessionId,
    required this.eventType,
    required this.title,
    required this.detail,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['event_type'] = Variable<String>(eventType);
    map['title'] = Variable<String>(title);
    map['detail'] = Variable<String>(detail);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SessionTimelineEventsCompanion toCompanion(bool nullToAbsent) {
    return SessionTimelineEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      eventType: Value(eventType),
      title: Value(title),
      detail: Value(detail),
      createdAt: Value(createdAt),
    );
  }

  factory SessionTimelineEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionTimelineEvent(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      title: serializer.fromJson<String>(json['title']),
      detail: serializer.fromJson<String>(json['detail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'eventType': serializer.toJson<String>(eventType),
      'title': serializer.toJson<String>(title),
      'detail': serializer.toJson<String>(detail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SessionTimelineEvent copyWith({
    String? id,
    String? sessionId,
    String? eventType,
    String? title,
    String? detail,
    DateTime? createdAt,
  }) => SessionTimelineEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    eventType: eventType ?? this.eventType,
    title: title ?? this.title,
    detail: detail ?? this.detail,
    createdAt: createdAt ?? this.createdAt,
  );
  SessionTimelineEvent copyWithCompanion(SessionTimelineEventsCompanion data) {
    return SessionTimelineEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      title: data.title.present ? data.title.value : this.title,
      detail: data.detail.present ? data.detail.value : this.detail,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionTimelineEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('eventType: $eventType, ')
          ..write('title: $title, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, eventType, title, detail, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionTimelineEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.eventType == this.eventType &&
          other.title == this.title &&
          other.detail == this.detail &&
          other.createdAt == this.createdAt);
}

class SessionTimelineEventsCompanion
    extends UpdateCompanion<SessionTimelineEvent> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> eventType;
  final Value<String> title;
  final Value<String> detail;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SessionTimelineEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.title = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionTimelineEventsCompanion.insert({
    required String id,
    required String sessionId,
    required String eventType,
    required String title,
    this.detail = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       eventType = Value(eventType),
       title = Value(title),
       createdAt = Value(createdAt);
  static Insertable<SessionTimelineEvent> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? eventType,
    Expression<String>? title,
    Expression<String>? detail,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (eventType != null) 'event_type': eventType,
      if (title != null) 'title': title,
      if (detail != null) 'detail': detail,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionTimelineEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? eventType,
    Value<String>? title,
    Value<String>? detail,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SessionTimelineEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      eventType: eventType ?? this.eventType,
      title: title ?? this.title,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionTimelineEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('eventType: $eventType, ')
          ..write('title: $title, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ThreatIntelEntriesTable extends ThreatIntelEntries
    with TableInfo<$ThreatIntelEntriesTable, ThreatIntelEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ThreatIntelEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cveIdMeta = const VerificationMeta('cveId');
  @override
  late final GeneratedColumn<String> cveId = GeneratedColumn<String>(
    'cve_id',
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
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _cvssScoreMeta = const VerificationMeta(
    'cvssScore',
  );
  @override
  late final GeneratedColumn<double> cvssScore = GeneratedColumn<double>(
    'cvss_score',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('info'),
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _publishedMeta = const VerificationMeta(
    'published',
  );
  @override
  late final GeneratedColumn<DateTime> published = GeneratedColumn<DateTime>(
    'published',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isKevMeta = const VerificationMeta('isKev');
  @override
  late final GeneratedColumn<int> isKev = GeneratedColumn<int>(
    'is_kev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pocUrlMeta = const VerificationMeta('pocUrl');
  @override
  late final GeneratedColumn<String> pocUrl = GeneratedColumn<String>(
    'poc_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedAtMeta = const VerificationMeta(
    'syncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cveId,
    title,
    cvssScore,
    severity,
    description,
    published,
    isKev,
    pocUrl,
    syncedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'threat_intel_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ThreatIntelEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cve_id')) {
      context.handle(
        _cveIdMeta,
        cveId.isAcceptableOrUnknown(data['cve_id']!, _cveIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cveIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('cvss_score')) {
      context.handle(
        _cvssScoreMeta,
        cvssScore.isAcceptableOrUnknown(data['cvss_score']!, _cvssScoreMeta),
      );
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('published')) {
      context.handle(
        _publishedMeta,
        published.isAcceptableOrUnknown(data['published']!, _publishedMeta),
      );
    }
    if (data.containsKey('is_kev')) {
      context.handle(
        _isKevMeta,
        isKev.isAcceptableOrUnknown(data['is_kev']!, _isKevMeta),
      );
    }
    if (data.containsKey('poc_url')) {
      context.handle(
        _pocUrlMeta,
        pocUrl.isAcceptableOrUnknown(data['poc_url']!, _pocUrlMeta),
      );
    }
    if (data.containsKey('synced_at')) {
      context.handle(
        _syncedAtMeta,
        syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cveId};
  @override
  ThreatIntelEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ThreatIntelEntry(
      cveId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cve_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      cvssScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cvss_score'],
      ),
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      published: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}published'],
      ),
      isKev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_kev'],
      )!,
      pocUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poc_url'],
      ),
      syncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}synced_at'],
      )!,
    );
  }

  @override
  $ThreatIntelEntriesTable createAlias(String alias) {
    return $ThreatIntelEntriesTable(attachedDatabase, alias);
  }
}

class ThreatIntelEntry extends DataClass
    implements Insertable<ThreatIntelEntry> {
  final String cveId;
  final String title;
  final double? cvssScore;
  final String severity;
  final String description;
  final DateTime? published;

  /// 是否在 CISA KEV 目录中（0/1）。
  final int isKev;
  final String? pocUrl;
  final DateTime syncedAt;
  const ThreatIntelEntry({
    required this.cveId,
    required this.title,
    this.cvssScore,
    required this.severity,
    required this.description,
    this.published,
    required this.isKev,
    this.pocUrl,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cve_id'] = Variable<String>(cveId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || cvssScore != null) {
      map['cvss_score'] = Variable<double>(cvssScore);
    }
    map['severity'] = Variable<String>(severity);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || published != null) {
      map['published'] = Variable<DateTime>(published);
    }
    map['is_kev'] = Variable<int>(isKev);
    if (!nullToAbsent || pocUrl != null) {
      map['poc_url'] = Variable<String>(pocUrl);
    }
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  ThreatIntelEntriesCompanion toCompanion(bool nullToAbsent) {
    return ThreatIntelEntriesCompanion(
      cveId: Value(cveId),
      title: Value(title),
      cvssScore: cvssScore == null && nullToAbsent
          ? const Value.absent()
          : Value(cvssScore),
      severity: Value(severity),
      description: Value(description),
      published: published == null && nullToAbsent
          ? const Value.absent()
          : Value(published),
      isKev: Value(isKev),
      pocUrl: pocUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(pocUrl),
      syncedAt: Value(syncedAt),
    );
  }

  factory ThreatIntelEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ThreatIntelEntry(
      cveId: serializer.fromJson<String>(json['cveId']),
      title: serializer.fromJson<String>(json['title']),
      cvssScore: serializer.fromJson<double?>(json['cvssScore']),
      severity: serializer.fromJson<String>(json['severity']),
      description: serializer.fromJson<String>(json['description']),
      published: serializer.fromJson<DateTime?>(json['published']),
      isKev: serializer.fromJson<int>(json['isKev']),
      pocUrl: serializer.fromJson<String?>(json['pocUrl']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cveId': serializer.toJson<String>(cveId),
      'title': serializer.toJson<String>(title),
      'cvssScore': serializer.toJson<double?>(cvssScore),
      'severity': serializer.toJson<String>(severity),
      'description': serializer.toJson<String>(description),
      'published': serializer.toJson<DateTime?>(published),
      'isKev': serializer.toJson<int>(isKev),
      'pocUrl': serializer.toJson<String?>(pocUrl),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  ThreatIntelEntry copyWith({
    String? cveId,
    String? title,
    Value<double?> cvssScore = const Value.absent(),
    String? severity,
    String? description,
    Value<DateTime?> published = const Value.absent(),
    int? isKev,
    Value<String?> pocUrl = const Value.absent(),
    DateTime? syncedAt,
  }) => ThreatIntelEntry(
    cveId: cveId ?? this.cveId,
    title: title ?? this.title,
    cvssScore: cvssScore.present ? cvssScore.value : this.cvssScore,
    severity: severity ?? this.severity,
    description: description ?? this.description,
    published: published.present ? published.value : this.published,
    isKev: isKev ?? this.isKev,
    pocUrl: pocUrl.present ? pocUrl.value : this.pocUrl,
    syncedAt: syncedAt ?? this.syncedAt,
  );
  ThreatIntelEntry copyWithCompanion(ThreatIntelEntriesCompanion data) {
    return ThreatIntelEntry(
      cveId: data.cveId.present ? data.cveId.value : this.cveId,
      title: data.title.present ? data.title.value : this.title,
      cvssScore: data.cvssScore.present ? data.cvssScore.value : this.cvssScore,
      severity: data.severity.present ? data.severity.value : this.severity,
      description: data.description.present
          ? data.description.value
          : this.description,
      published: data.published.present ? data.published.value : this.published,
      isKev: data.isKev.present ? data.isKev.value : this.isKev,
      pocUrl: data.pocUrl.present ? data.pocUrl.value : this.pocUrl,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ThreatIntelEntry(')
          ..write('cveId: $cveId, ')
          ..write('title: $title, ')
          ..write('cvssScore: $cvssScore, ')
          ..write('severity: $severity, ')
          ..write('description: $description, ')
          ..write('published: $published, ')
          ..write('isKev: $isKev, ')
          ..write('pocUrl: $pocUrl, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    cveId,
    title,
    cvssScore,
    severity,
    description,
    published,
    isKev,
    pocUrl,
    syncedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ThreatIntelEntry &&
          other.cveId == this.cveId &&
          other.title == this.title &&
          other.cvssScore == this.cvssScore &&
          other.severity == this.severity &&
          other.description == this.description &&
          other.published == this.published &&
          other.isKev == this.isKev &&
          other.pocUrl == this.pocUrl &&
          other.syncedAt == this.syncedAt);
}

class ThreatIntelEntriesCompanion extends UpdateCompanion<ThreatIntelEntry> {
  final Value<String> cveId;
  final Value<String> title;
  final Value<double?> cvssScore;
  final Value<String> severity;
  final Value<String> description;
  final Value<DateTime?> published;
  final Value<int> isKev;
  final Value<String?> pocUrl;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const ThreatIntelEntriesCompanion({
    this.cveId = const Value.absent(),
    this.title = const Value.absent(),
    this.cvssScore = const Value.absent(),
    this.severity = const Value.absent(),
    this.description = const Value.absent(),
    this.published = const Value.absent(),
    this.isKev = const Value.absent(),
    this.pocUrl = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ThreatIntelEntriesCompanion.insert({
    required String cveId,
    this.title = const Value.absent(),
    this.cvssScore = const Value.absent(),
    this.severity = const Value.absent(),
    this.description = const Value.absent(),
    this.published = const Value.absent(),
    this.isKev = const Value.absent(),
    this.pocUrl = const Value.absent(),
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  }) : cveId = Value(cveId),
       syncedAt = Value(syncedAt);
  static Insertable<ThreatIntelEntry> custom({
    Expression<String>? cveId,
    Expression<String>? title,
    Expression<double>? cvssScore,
    Expression<String>? severity,
    Expression<String>? description,
    Expression<DateTime>? published,
    Expression<int>? isKev,
    Expression<String>? pocUrl,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cveId != null) 'cve_id': cveId,
      if (title != null) 'title': title,
      if (cvssScore != null) 'cvss_score': cvssScore,
      if (severity != null) 'severity': severity,
      if (description != null) 'description': description,
      if (published != null) 'published': published,
      if (isKev != null) 'is_kev': isKev,
      if (pocUrl != null) 'poc_url': pocUrl,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ThreatIntelEntriesCompanion copyWith({
    Value<String>? cveId,
    Value<String>? title,
    Value<double?>? cvssScore,
    Value<String>? severity,
    Value<String>? description,
    Value<DateTime?>? published,
    Value<int>? isKev,
    Value<String?>? pocUrl,
    Value<DateTime>? syncedAt,
    Value<int>? rowid,
  }) {
    return ThreatIntelEntriesCompanion(
      cveId: cveId ?? this.cveId,
      title: title ?? this.title,
      cvssScore: cvssScore ?? this.cvssScore,
      severity: severity ?? this.severity,
      description: description ?? this.description,
      published: published ?? this.published,
      isKev: isKev ?? this.isKev,
      pocUrl: pocUrl ?? this.pocUrl,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cveId.present) {
      map['cve_id'] = Variable<String>(cveId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (cvssScore.present) {
      map['cvss_score'] = Variable<double>(cvssScore.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (published.present) {
      map['published'] = Variable<DateTime>(published.value);
    }
    if (isKev.present) {
      map['is_kev'] = Variable<int>(isKev.value);
    }
    if (pocUrl.present) {
      map['poc_url'] = Variable<String>(pocUrl.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ThreatIntelEntriesCompanion(')
          ..write('cveId: $cveId, ')
          ..write('title: $title, ')
          ..write('cvssScore: $cvssScore, ')
          ..write('severity: $severity, ')
          ..write('description: $description, ')
          ..write('published: $published, ')
          ..write('isKev: $isKev, ')
          ..write('pocUrl: $pocUrl, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReportVersionsTableTable extends ReportVersionsTable
    with TableInfo<$ReportVersionsTableTable, ReportVersionsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReportVersionsTableTable(this.attachedDatabase, [this._alias]);
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
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES pentest_sessions (id)',
    ),
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('technical'),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    version,
    format,
    content,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'report_versions_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReportVersionsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReportVersionsTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReportVersionsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ReportVersionsTableTable createAlias(String alias) {
    return $ReportVersionsTableTable(attachedDatabase, alias);
  }
}

class ReportVersionsTableData extends DataClass
    implements Insertable<ReportVersionsTableData> {
  final String id;
  final String sessionId;
  final int version;
  final String format;
  final String content;
  final DateTime createdAt;
  const ReportVersionsTableData({
    required this.id,
    required this.sessionId,
    required this.version,
    required this.format,
    required this.content,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['version'] = Variable<int>(version);
    map['format'] = Variable<String>(format);
    map['content'] = Variable<String>(content);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ReportVersionsTableCompanion toCompanion(bool nullToAbsent) {
    return ReportVersionsTableCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      version: Value(version),
      format: Value(format),
      content: Value(content),
      createdAt: Value(createdAt),
    );
  }

  factory ReportVersionsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReportVersionsTableData(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      version: serializer.fromJson<int>(json['version']),
      format: serializer.fromJson<String>(json['format']),
      content: serializer.fromJson<String>(json['content']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'version': serializer.toJson<int>(version),
      'format': serializer.toJson<String>(format),
      'content': serializer.toJson<String>(content),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ReportVersionsTableData copyWith({
    String? id,
    String? sessionId,
    int? version,
    String? format,
    String? content,
    DateTime? createdAt,
  }) => ReportVersionsTableData(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    version: version ?? this.version,
    format: format ?? this.format,
    content: content ?? this.content,
    createdAt: createdAt ?? this.createdAt,
  );
  ReportVersionsTableData copyWithCompanion(ReportVersionsTableCompanion data) {
    return ReportVersionsTableData(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      version: data.version.present ? data.version.value : this.version,
      format: data.format.present ? data.format.value : this.format,
      content: data.content.present ? data.content.value : this.content,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReportVersionsTableData(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('version: $version, ')
          ..write('format: $format, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sessionId, version, format, content, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReportVersionsTableData &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.version == this.version &&
          other.format == this.format &&
          other.content == this.content &&
          other.createdAt == this.createdAt);
}

class ReportVersionsTableCompanion
    extends UpdateCompanion<ReportVersionsTableData> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<int> version;
  final Value<String> format;
  final Value<String> content;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ReportVersionsTableCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.version = const Value.absent(),
    this.format = const Value.absent(),
    this.content = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReportVersionsTableCompanion.insert({
    required String id,
    required String sessionId,
    this.version = const Value.absent(),
    this.format = const Value.absent(),
    required String content,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<ReportVersionsTableData> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<int>? version,
    Expression<String>? format,
    Expression<String>? content,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (version != null) 'version': version,
      if (format != null) 'format': format,
      if (content != null) 'content': content,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReportVersionsTableCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<int>? version,
    Value<String>? format,
    Value<String>? content,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ReportVersionsTableCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      version: version ?? this.version,
      format: format ?? this.format,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReportVersionsTableCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('version: $version, ')
          ..write('format: $format, ')
          ..write('content: $content, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SecurityDatabase extends GeneratedDatabase {
  _$SecurityDatabase(QueryExecutor e) : super(e);
  $SecurityDatabaseManager get managers => $SecurityDatabaseManager(this);
  late final $PentestSessionsTable pentestSessions = $PentestSessionsTable(
    this,
  );
  late final $SessionAssetsTable sessionAssets = $SessionAssetsTable(this);
  late final $SessionFindingsTable sessionFindings = $SessionFindingsTable(
    this,
  );
  late final $SessionTimelineEventsTable sessionTimelineEvents =
      $SessionTimelineEventsTable(this);
  late final $ThreatIntelEntriesTable threatIntelEntries =
      $ThreatIntelEntriesTable(this);
  late final $ReportVersionsTableTable reportVersionsTable =
      $ReportVersionsTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    pentestSessions,
    sessionAssets,
    sessionFindings,
    sessionTimelineEvents,
    threatIntelEntries,
    reportVersionsTable,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'session_assets',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('session_findings', kind: UpdateKind.update)],
    ),
  ]);
}

typedef $$PentestSessionsTableCreateCompanionBuilder =
    PentestSessionsCompanion Function({
      required String id,
      required String name,
      Value<String> type,
      Value<String> scope,
      Value<String> status,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$PentestSessionsTableUpdateCompanionBuilder =
    PentestSessionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> type,
      Value<String> scope,
      Value<String> status,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$PentestSessionsTableReferences
    extends
        BaseReferences<
          _$SecurityDatabase,
          $PentestSessionsTable,
          PentestSession
        > {
  $$PentestSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$SessionAssetsTable, List<SessionAsset>>
  _sessionAssetsRefsTable(_$SecurityDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionAssets,
        aliasName: $_aliasNameGenerator(
          db.pentestSessions.id,
          db.sessionAssets.sessionId,
        ),
      );

  $$SessionAssetsTableProcessedTableManager get sessionAssetsRefs {
    final manager = $$SessionAssetsTableTableManager(
      $_db,
      $_db.sessionAssets,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionAssetsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionFindingsTable, List<SessionFinding>>
  _sessionFindingsRefsTable(_$SecurityDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionFindings,
        aliasName: $_aliasNameGenerator(
          db.pentestSessions.id,
          db.sessionFindings.sessionId,
        ),
      );

  $$SessionFindingsTableProcessedTableManager get sessionFindingsRefs {
    final manager = $$SessionFindingsTableTableManager(
      $_db,
      $_db.sessionFindings,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionFindingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $SessionTimelineEventsTable,
    List<SessionTimelineEvent>
  >
  _sessionTimelineEventsRefsTable(_$SecurityDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionTimelineEvents,
        aliasName: $_aliasNameGenerator(
          db.pentestSessions.id,
          db.sessionTimelineEvents.sessionId,
        ),
      );

  $$SessionTimelineEventsTableProcessedTableManager
  get sessionTimelineEventsRefs {
    final manager = $$SessionTimelineEventsTableTableManager(
      $_db,
      $_db.sessionTimelineEvents,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionTimelineEventsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ReportVersionsTableTable,
    List<ReportVersionsTableData>
  >
  _reportVersionsTableRefsTable(_$SecurityDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.reportVersionsTable,
        aliasName: $_aliasNameGenerator(
          db.pentestSessions.id,
          db.reportVersionsTable.sessionId,
        ),
      );

  $$ReportVersionsTableTableProcessedTableManager get reportVersionsTableRefs {
    final manager = $$ReportVersionsTableTableTableManager(
      $_db,
      $_db.reportVersionsTable,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _reportVersionsTableRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PentestSessionsTableFilterComposer
    extends Composer<_$SecurityDatabase, $PentestSessionsTable> {
  $$PentestSessionsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionAssetsRefs(
    Expression<bool> Function($$SessionAssetsTableFilterComposer f) f,
  ) {
    final $$SessionAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionAssets,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionAssetsTableFilterComposer(
            $db: $db,
            $table: $db.sessionAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionFindingsRefs(
    Expression<bool> Function($$SessionFindingsTableFilterComposer f) f,
  ) {
    final $$SessionFindingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFindings,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFindingsTableFilterComposer(
            $db: $db,
            $table: $db.sessionFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionTimelineEventsRefs(
    Expression<bool> Function($$SessionTimelineEventsTableFilterComposer f) f,
  ) {
    final $$SessionTimelineEventsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.sessionTimelineEvents,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SessionTimelineEventsTableFilterComposer(
                $db: $db,
                $table: $db.sessionTimelineEvents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> reportVersionsTableRefs(
    Expression<bool> Function($$ReportVersionsTableTableFilterComposer f) f,
  ) {
    final $$ReportVersionsTableTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.reportVersionsTable,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReportVersionsTableTableFilterComposer(
            $db: $db,
            $table: $db.reportVersionsTable,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PentestSessionsTableOrderingComposer
    extends Composer<_$SecurityDatabase, $PentestSessionsTable> {
  $$PentestSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PentestSessionsTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $PentestSessionsTable> {
  $$PentestSessionsTableAnnotationComposer({
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

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> sessionAssetsRefs<T extends Object>(
    Expression<T> Function($$SessionAssetsTableAnnotationComposer a) f,
  ) {
    final $$SessionAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionAssets,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionFindingsRefs<T extends Object>(
    Expression<T> Function($$SessionFindingsTableAnnotationComposer a) f,
  ) {
    final $$SessionFindingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFindings,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFindingsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sessionTimelineEventsRefs<T extends Object>(
    Expression<T> Function($$SessionTimelineEventsTableAnnotationComposer a) f,
  ) {
    final $$SessionTimelineEventsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.sessionTimelineEvents,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$SessionTimelineEventsTableAnnotationComposer(
                $db: $db,
                $table: $db.sessionTimelineEvents,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> reportVersionsTableRefs<T extends Object>(
    Expression<T> Function($$ReportVersionsTableTableAnnotationComposer a) f,
  ) {
    final $$ReportVersionsTableTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.reportVersionsTable,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ReportVersionsTableTableAnnotationComposer(
                $db: $db,
                $table: $db.reportVersionsTable,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$PentestSessionsTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $PentestSessionsTable,
          PentestSession,
          $$PentestSessionsTableFilterComposer,
          $$PentestSessionsTableOrderingComposer,
          $$PentestSessionsTableAnnotationComposer,
          $$PentestSessionsTableCreateCompanionBuilder,
          $$PentestSessionsTableUpdateCompanionBuilder,
          (PentestSession, $$PentestSessionsTableReferences),
          PentestSession,
          PrefetchHooks Function({
            bool sessionAssetsRefs,
            bool sessionFindingsRefs,
            bool sessionTimelineEventsRefs,
            bool reportVersionsTableRefs,
          })
        > {
  $$PentestSessionsTableTableManager(
    _$SecurityDatabase db,
    $PentestSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PentestSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PentestSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PentestSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PentestSessionsCompanion(
                id: id,
                name: name,
                type: type,
                scope: scope,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> type = const Value.absent(),
                Value<String> scope = const Value.absent(),
                Value<String> status = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => PentestSessionsCompanion.insert(
                id: id,
                name: name,
                type: type,
                scope: scope,
                status: status,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PentestSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sessionAssetsRefs = false,
                sessionFindingsRefs = false,
                sessionTimelineEventsRefs = false,
                reportVersionsTableRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionAssetsRefs) db.sessionAssets,
                    if (sessionFindingsRefs) db.sessionFindings,
                    if (sessionTimelineEventsRefs) db.sessionTimelineEvents,
                    if (reportVersionsTableRefs) db.reportVersionsTable,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionAssetsRefs)
                        await $_getPrefetchedData<
                          PentestSession,
                          $PentestSessionsTable,
                          SessionAsset
                        >(
                          currentTable: table,
                          referencedTable: $$PentestSessionsTableReferences
                              ._sessionAssetsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PentestSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionAssetsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionFindingsRefs)
                        await $_getPrefetchedData<
                          PentestSession,
                          $PentestSessionsTable,
                          SessionFinding
                        >(
                          currentTable: table,
                          referencedTable: $$PentestSessionsTableReferences
                              ._sessionFindingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PentestSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionFindingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sessionTimelineEventsRefs)
                        await $_getPrefetchedData<
                          PentestSession,
                          $PentestSessionsTable,
                          SessionTimelineEvent
                        >(
                          currentTable: table,
                          referencedTable: $$PentestSessionsTableReferences
                              ._sessionTimelineEventsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PentestSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionTimelineEventsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (reportVersionsTableRefs)
                        await $_getPrefetchedData<
                          PentestSession,
                          $PentestSessionsTable,
                          ReportVersionsTableData
                        >(
                          currentTable: table,
                          referencedTable: $$PentestSessionsTableReferences
                              ._reportVersionsTableRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PentestSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).reportVersionsTableRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PentestSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $PentestSessionsTable,
      PentestSession,
      $$PentestSessionsTableFilterComposer,
      $$PentestSessionsTableOrderingComposer,
      $$PentestSessionsTableAnnotationComposer,
      $$PentestSessionsTableCreateCompanionBuilder,
      $$PentestSessionsTableUpdateCompanionBuilder,
      (PentestSession, $$PentestSessionsTableReferences),
      PentestSession,
      PrefetchHooks Function({
        bool sessionAssetsRefs,
        bool sessionFindingsRefs,
        bool sessionTimelineEventsRefs,
        bool reportVersionsTableRefs,
      })
    >;
typedef $$SessionAssetsTableCreateCompanionBuilder =
    SessionAssetsCompanion Function({
      required String id,
      required String sessionId,
      Value<String> type,
      required String address,
      Value<String> metadata,
      Value<String> riskLevel,
      Value<String?> userNote,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SessionAssetsTableUpdateCompanionBuilder =
    SessionAssetsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> type,
      Value<String> address,
      Value<String> metadata,
      Value<String> riskLevel,
      Value<String?> userNote,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SessionAssetsTableReferences
    extends
        BaseReferences<_$SecurityDatabase, $SessionAssetsTable, SessionAsset> {
  $$SessionAssetsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PentestSessionsTable _sessionIdTable(_$SecurityDatabase db) =>
      db.pentestSessions.createAlias(
        $_aliasNameGenerator(db.sessionAssets.sessionId, db.pentestSessions.id),
      );

  $$PentestSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$PentestSessionsTableTableManager(
      $_db,
      $_db.pentestSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SessionFindingsTable, List<SessionFinding>>
  _sessionFindingsRefsTable(_$SecurityDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionFindings,
        aliasName: $_aliasNameGenerator(
          db.sessionAssets.id,
          db.sessionFindings.assetId,
        ),
      );

  $$SessionFindingsTableProcessedTableManager get sessionFindingsRefs {
    final manager = $$SessionFindingsTableTableManager(
      $_db,
      $_db.sessionFindings,
    ).filter((f) => f.assetId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionFindingsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionAssetsTableFilterComposer
    extends Composer<_$SecurityDatabase, $SessionAssetsTable> {
  $$SessionAssetsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get riskLevel => $composableBuilder(
    column: $table.riskLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PentestSessionsTableFilterComposer get sessionId {
    final $$PentestSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableFilterComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> sessionFindingsRefs(
    Expression<bool> Function($$SessionFindingsTableFilterComposer f) f,
  ) {
    final $$SessionFindingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFindings,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFindingsTableFilterComposer(
            $db: $db,
            $table: $db.sessionFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionAssetsTableOrderingComposer
    extends Composer<_$SecurityDatabase, $SessionAssetsTable> {
  $$SessionAssetsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get address => $composableBuilder(
    column: $table.address,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get riskLevel => $composableBuilder(
    column: $table.riskLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userNote => $composableBuilder(
    column: $table.userNote,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PentestSessionsTableOrderingComposer get sessionId {
    final $$PentestSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionAssetsTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $SessionAssetsTable> {
  $$SessionAssetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get address =>
      $composableBuilder(column: $table.address, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<String> get riskLevel =>
      $composableBuilder(column: $table.riskLevel, builder: (column) => column);

  GeneratedColumn<String> get userNote =>
      $composableBuilder(column: $table.userNote, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PentestSessionsTableAnnotationComposer get sessionId {
    final $$PentestSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> sessionFindingsRefs<T extends Object>(
    Expression<T> Function($$SessionFindingsTableAnnotationComposer a) f,
  ) {
    final $$SessionFindingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionFindings,
      getReferencedColumn: (t) => t.assetId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionFindingsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionFindings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionAssetsTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $SessionAssetsTable,
          SessionAsset,
          $$SessionAssetsTableFilterComposer,
          $$SessionAssetsTableOrderingComposer,
          $$SessionAssetsTableAnnotationComposer,
          $$SessionAssetsTableCreateCompanionBuilder,
          $$SessionAssetsTableUpdateCompanionBuilder,
          (SessionAsset, $$SessionAssetsTableReferences),
          SessionAsset,
          PrefetchHooks Function({bool sessionId, bool sessionFindingsRefs})
        > {
  $$SessionAssetsTableTableManager(
    _$SecurityDatabase db,
    $SessionAssetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionAssetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionAssetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionAssetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> address = const Value.absent(),
                Value<String> metadata = const Value.absent(),
                Value<String> riskLevel = const Value.absent(),
                Value<String?> userNote = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionAssetsCompanion(
                id: id,
                sessionId: sessionId,
                type: type,
                address: address,
                metadata: metadata,
                riskLevel: riskLevel,
                userNote: userNote,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<String> type = const Value.absent(),
                required String address,
                Value<String> metadata = const Value.absent(),
                Value<String> riskLevel = const Value.absent(),
                Value<String?> userNote = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionAssetsCompanion.insert(
                id: id,
                sessionId: sessionId,
                type: type,
                address: address,
                metadata: metadata,
                riskLevel: riskLevel,
                userNote: userNote,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionAssetsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({sessionId = false, sessionFindingsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionFindingsRefs) db.sessionFindings,
                  ],
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
                        if (sessionId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.sessionId,
                                    referencedTable:
                                        $$SessionAssetsTableReferences
                                            ._sessionIdTable(db),
                                    referencedColumn:
                                        $$SessionAssetsTableReferences
                                            ._sessionIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionFindingsRefs)
                        await $_getPrefetchedData<
                          SessionAsset,
                          $SessionAssetsTable,
                          SessionFinding
                        >(
                          currentTable: table,
                          referencedTable: $$SessionAssetsTableReferences
                              ._sessionFindingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionAssetsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionFindingsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.assetId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionAssetsTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $SessionAssetsTable,
      SessionAsset,
      $$SessionAssetsTableFilterComposer,
      $$SessionAssetsTableOrderingComposer,
      $$SessionAssetsTableAnnotationComposer,
      $$SessionAssetsTableCreateCompanionBuilder,
      $$SessionAssetsTableUpdateCompanionBuilder,
      (SessionAsset, $$SessionAssetsTableReferences),
      SessionAsset,
      PrefetchHooks Function({bool sessionId, bool sessionFindingsRefs})
    >;
typedef $$SessionFindingsTableCreateCompanionBuilder =
    SessionFindingsCompanion Function({
      required String id,
      required String sessionId,
      Value<String?> assetId,
      Value<String?> cveId,
      required String title,
      Value<String> severity,
      Value<double?> cvssScore,
      Value<String> status,
      Value<String?> evidence,
      Value<String> source,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SessionFindingsTableUpdateCompanionBuilder =
    SessionFindingsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String?> assetId,
      Value<String?> cveId,
      Value<String> title,
      Value<String> severity,
      Value<double?> cvssScore,
      Value<String> status,
      Value<String?> evidence,
      Value<String> source,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

final class $$SessionFindingsTableReferences
    extends
        BaseReferences<
          _$SecurityDatabase,
          $SessionFindingsTable,
          SessionFinding
        > {
  $$SessionFindingsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PentestSessionsTable _sessionIdTable(_$SecurityDatabase db) =>
      db.pentestSessions.createAlias(
        $_aliasNameGenerator(
          db.sessionFindings.sessionId,
          db.pentestSessions.id,
        ),
      );

  $$PentestSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$PentestSessionsTableTableManager(
      $_db,
      $_db.pentestSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SessionAssetsTable _assetIdTable(_$SecurityDatabase db) =>
      db.sessionAssets.createAlias(
        $_aliasNameGenerator(db.sessionFindings.assetId, db.sessionAssets.id),
      );

  $$SessionAssetsTableProcessedTableManager? get assetId {
    final $_column = $_itemColumn<String>('asset_id');
    if ($_column == null) return null;
    final manager = $$SessionAssetsTableTableManager(
      $_db,
      $_db.sessionAssets,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_assetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionFindingsTableFilterComposer
    extends Composer<_$SecurityDatabase, $SessionFindingsTable> {
  $$SessionFindingsTableFilterComposer({
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

  ColumnFilters<String> get cveId => $composableBuilder(
    column: $table.cveId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cvssScore => $composableBuilder(
    column: $table.cvssScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PentestSessionsTableFilterComposer get sessionId {
    final $$PentestSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableFilterComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionAssetsTableFilterComposer get assetId {
    final $$SessionAssetsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.sessionAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionAssetsTableFilterComposer(
            $db: $db,
            $table: $db.sessionAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFindingsTableOrderingComposer
    extends Composer<_$SecurityDatabase, $SessionFindingsTable> {
  $$SessionFindingsTableOrderingComposer({
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

  ColumnOrderings<String> get cveId => $composableBuilder(
    column: $table.cveId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cvssScore => $composableBuilder(
    column: $table.cvssScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidence => $composableBuilder(
    column: $table.evidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PentestSessionsTableOrderingComposer get sessionId {
    final $$PentestSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionAssetsTableOrderingComposer get assetId {
    final $$SessionAssetsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.sessionAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionAssetsTableOrderingComposer(
            $db: $db,
            $table: $db.sessionAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFindingsTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $SessionFindingsTable> {
  $$SessionFindingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cveId =>
      $composableBuilder(column: $table.cveId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<double> get cvssScore =>
      $composableBuilder(column: $table.cvssScore, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get evidence =>
      $composableBuilder(column: $table.evidence, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$PentestSessionsTableAnnotationComposer get sessionId {
    final $$PentestSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionAssetsTableAnnotationComposer get assetId {
    final $$SessionAssetsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.assetId,
      referencedTable: $db.sessionAssets,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionAssetsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionAssets,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionFindingsTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $SessionFindingsTable,
          SessionFinding,
          $$SessionFindingsTableFilterComposer,
          $$SessionFindingsTableOrderingComposer,
          $$SessionFindingsTableAnnotationComposer,
          $$SessionFindingsTableCreateCompanionBuilder,
          $$SessionFindingsTableUpdateCompanionBuilder,
          (SessionFinding, $$SessionFindingsTableReferences),
          SessionFinding,
          PrefetchHooks Function({bool sessionId, bool assetId})
        > {
  $$SessionFindingsTableTableManager(
    _$SecurityDatabase db,
    $SessionFindingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionFindingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionFindingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionFindingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String?> assetId = const Value.absent(),
                Value<String?> cveId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<double?> cvssScore = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> evidence = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionFindingsCompanion(
                id: id,
                sessionId: sessionId,
                assetId: assetId,
                cveId: cveId,
                title: title,
                severity: severity,
                cvssScore: cvssScore,
                status: status,
                evidence: evidence,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<String?> assetId = const Value.absent(),
                Value<String?> cveId = const Value.absent(),
                required String title,
                Value<String> severity = const Value.absent(),
                Value<double?> cvssScore = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> evidence = const Value.absent(),
                Value<String> source = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionFindingsCompanion.insert(
                id: id,
                sessionId: sessionId,
                assetId: assetId,
                cveId: cveId,
                title: title,
                severity: severity,
                cvssScore: cvssScore,
                status: status,
                evidence: evidence,
                source: source,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionFindingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, assetId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$SessionFindingsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$SessionFindingsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (assetId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.assetId,
                                referencedTable:
                                    $$SessionFindingsTableReferences
                                        ._assetIdTable(db),
                                referencedColumn:
                                    $$SessionFindingsTableReferences
                                        ._assetIdTable(db)
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

typedef $$SessionFindingsTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $SessionFindingsTable,
      SessionFinding,
      $$SessionFindingsTableFilterComposer,
      $$SessionFindingsTableOrderingComposer,
      $$SessionFindingsTableAnnotationComposer,
      $$SessionFindingsTableCreateCompanionBuilder,
      $$SessionFindingsTableUpdateCompanionBuilder,
      (SessionFinding, $$SessionFindingsTableReferences),
      SessionFinding,
      PrefetchHooks Function({bool sessionId, bool assetId})
    >;
typedef $$SessionTimelineEventsTableCreateCompanionBuilder =
    SessionTimelineEventsCompanion Function({
      required String id,
      required String sessionId,
      required String eventType,
      required String title,
      Value<String> detail,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$SessionTimelineEventsTableUpdateCompanionBuilder =
    SessionTimelineEventsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> eventType,
      Value<String> title,
      Value<String> detail,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$SessionTimelineEventsTableReferences
    extends
        BaseReferences<
          _$SecurityDatabase,
          $SessionTimelineEventsTable,
          SessionTimelineEvent
        > {
  $$SessionTimelineEventsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PentestSessionsTable _sessionIdTable(_$SecurityDatabase db) =>
      db.pentestSessions.createAlias(
        $_aliasNameGenerator(
          db.sessionTimelineEvents.sessionId,
          db.pentestSessions.id,
        ),
      );

  $$PentestSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$PentestSessionsTableTableManager(
      $_db,
      $_db.pentestSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionTimelineEventsTableFilterComposer
    extends Composer<_$SecurityDatabase, $SessionTimelineEventsTable> {
  $$SessionTimelineEventsTableFilterComposer({
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

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PentestSessionsTableFilterComposer get sessionId {
    final $$PentestSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableFilterComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTimelineEventsTableOrderingComposer
    extends Composer<_$SecurityDatabase, $SessionTimelineEventsTable> {
  $$SessionTimelineEventsTableOrderingComposer({
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

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PentestSessionsTableOrderingComposer get sessionId {
    final $$PentestSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTimelineEventsTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $SessionTimelineEventsTable> {
  $$SessionTimelineEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PentestSessionsTableAnnotationComposer get sessionId {
    final $$PentestSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionTimelineEventsTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $SessionTimelineEventsTable,
          SessionTimelineEvent,
          $$SessionTimelineEventsTableFilterComposer,
          $$SessionTimelineEventsTableOrderingComposer,
          $$SessionTimelineEventsTableAnnotationComposer,
          $$SessionTimelineEventsTableCreateCompanionBuilder,
          $$SessionTimelineEventsTableUpdateCompanionBuilder,
          (SessionTimelineEvent, $$SessionTimelineEventsTableReferences),
          SessionTimelineEvent,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SessionTimelineEventsTableTableManager(
    _$SecurityDatabase db,
    $SessionTimelineEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionTimelineEventsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SessionTimelineEventsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SessionTimelineEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> detail = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionTimelineEventsCompanion(
                id: id,
                sessionId: sessionId,
                eventType: eventType,
                title: title,
                detail: detail,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String eventType,
                required String title,
                Value<String> detail = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionTimelineEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                eventType: eventType,
                title: title,
                detail: detail,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionTimelineEventsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$SessionTimelineEventsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$SessionTimelineEventsTableReferences
                                        ._sessionIdTable(db)
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

typedef $$SessionTimelineEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $SessionTimelineEventsTable,
      SessionTimelineEvent,
      $$SessionTimelineEventsTableFilterComposer,
      $$SessionTimelineEventsTableOrderingComposer,
      $$SessionTimelineEventsTableAnnotationComposer,
      $$SessionTimelineEventsTableCreateCompanionBuilder,
      $$SessionTimelineEventsTableUpdateCompanionBuilder,
      (SessionTimelineEvent, $$SessionTimelineEventsTableReferences),
      SessionTimelineEvent,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ThreatIntelEntriesTableCreateCompanionBuilder =
    ThreatIntelEntriesCompanion Function({
      required String cveId,
      Value<String> title,
      Value<double?> cvssScore,
      Value<String> severity,
      Value<String> description,
      Value<DateTime?> published,
      Value<int> isKev,
      Value<String?> pocUrl,
      required DateTime syncedAt,
      Value<int> rowid,
    });
typedef $$ThreatIntelEntriesTableUpdateCompanionBuilder =
    ThreatIntelEntriesCompanion Function({
      Value<String> cveId,
      Value<String> title,
      Value<double?> cvssScore,
      Value<String> severity,
      Value<String> description,
      Value<DateTime?> published,
      Value<int> isKev,
      Value<String?> pocUrl,
      Value<DateTime> syncedAt,
      Value<int> rowid,
    });

class $$ThreatIntelEntriesTableFilterComposer
    extends Composer<_$SecurityDatabase, $ThreatIntelEntriesTable> {
  $$ThreatIntelEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cveId => $composableBuilder(
    column: $table.cveId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cvssScore => $composableBuilder(
    column: $table.cvssScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get published => $composableBuilder(
    column: $table.published,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isKev => $composableBuilder(
    column: $table.isKev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pocUrl => $composableBuilder(
    column: $table.pocUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ThreatIntelEntriesTableOrderingComposer
    extends Composer<_$SecurityDatabase, $ThreatIntelEntriesTable> {
  $$ThreatIntelEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cveId => $composableBuilder(
    column: $table.cveId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cvssScore => $composableBuilder(
    column: $table.cvssScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get published => $composableBuilder(
    column: $table.published,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isKev => $composableBuilder(
    column: $table.isKev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pocUrl => $composableBuilder(
    column: $table.pocUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
    column: $table.syncedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ThreatIntelEntriesTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $ThreatIntelEntriesTable> {
  $$ThreatIntelEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cveId =>
      $composableBuilder(column: $table.cveId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<double> get cvssScore =>
      $composableBuilder(column: $table.cvssScore, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get published =>
      $composableBuilder(column: $table.published, builder: (column) => column);

  GeneratedColumn<int> get isKev =>
      $composableBuilder(column: $table.isKev, builder: (column) => column);

  GeneratedColumn<String> get pocUrl =>
      $composableBuilder(column: $table.pocUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$ThreatIntelEntriesTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $ThreatIntelEntriesTable,
          ThreatIntelEntry,
          $$ThreatIntelEntriesTableFilterComposer,
          $$ThreatIntelEntriesTableOrderingComposer,
          $$ThreatIntelEntriesTableAnnotationComposer,
          $$ThreatIntelEntriesTableCreateCompanionBuilder,
          $$ThreatIntelEntriesTableUpdateCompanionBuilder,
          (
            ThreatIntelEntry,
            BaseReferences<
              _$SecurityDatabase,
              $ThreatIntelEntriesTable,
              ThreatIntelEntry
            >,
          ),
          ThreatIntelEntry,
          PrefetchHooks Function()
        > {
  $$ThreatIntelEntriesTableTableManager(
    _$SecurityDatabase db,
    $ThreatIntelEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ThreatIntelEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ThreatIntelEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ThreatIntelEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> cveId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<double?> cvssScore = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime?> published = const Value.absent(),
                Value<int> isKev = const Value.absent(),
                Value<String?> pocUrl = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ThreatIntelEntriesCompanion(
                cveId: cveId,
                title: title,
                cvssScore: cvssScore,
                severity: severity,
                description: description,
                published: published,
                isKev: isKev,
                pocUrl: pocUrl,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cveId,
                Value<String> title = const Value.absent(),
                Value<double?> cvssScore = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<DateTime?> published = const Value.absent(),
                Value<int> isKev = const Value.absent(),
                Value<String?> pocUrl = const Value.absent(),
                required DateTime syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => ThreatIntelEntriesCompanion.insert(
                cveId: cveId,
                title: title,
                cvssScore: cvssScore,
                severity: severity,
                description: description,
                published: published,
                isKev: isKev,
                pocUrl: pocUrl,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ThreatIntelEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $ThreatIntelEntriesTable,
      ThreatIntelEntry,
      $$ThreatIntelEntriesTableFilterComposer,
      $$ThreatIntelEntriesTableOrderingComposer,
      $$ThreatIntelEntriesTableAnnotationComposer,
      $$ThreatIntelEntriesTableCreateCompanionBuilder,
      $$ThreatIntelEntriesTableUpdateCompanionBuilder,
      (
        ThreatIntelEntry,
        BaseReferences<
          _$SecurityDatabase,
          $ThreatIntelEntriesTable,
          ThreatIntelEntry
        >,
      ),
      ThreatIntelEntry,
      PrefetchHooks Function()
    >;
typedef $$ReportVersionsTableTableCreateCompanionBuilder =
    ReportVersionsTableCompanion Function({
      required String id,
      required String sessionId,
      Value<int> version,
      Value<String> format,
      required String content,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$ReportVersionsTableTableUpdateCompanionBuilder =
    ReportVersionsTableCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<int> version,
      Value<String> format,
      Value<String> content,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ReportVersionsTableTableReferences
    extends
        BaseReferences<
          _$SecurityDatabase,
          $ReportVersionsTableTable,
          ReportVersionsTableData
        > {
  $$ReportVersionsTableTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PentestSessionsTable _sessionIdTable(_$SecurityDatabase db) =>
      db.pentestSessions.createAlias(
        $_aliasNameGenerator(
          db.reportVersionsTable.sessionId,
          db.pentestSessions.id,
        ),
      );

  $$PentestSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$PentestSessionsTableTableManager(
      $_db,
      $_db.pentestSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReportVersionsTableTableFilterComposer
    extends Composer<_$SecurityDatabase, $ReportVersionsTableTable> {
  $$ReportVersionsTableTableFilterComposer({
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

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PentestSessionsTableFilterComposer get sessionId {
    final $$PentestSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableFilterComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReportVersionsTableTableOrderingComposer
    extends Composer<_$SecurityDatabase, $ReportVersionsTableTable> {
  $$ReportVersionsTableTableOrderingComposer({
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

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PentestSessionsTableOrderingComposer get sessionId {
    final $$PentestSessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableOrderingComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReportVersionsTableTableAnnotationComposer
    extends Composer<_$SecurityDatabase, $ReportVersionsTableTable> {
  $$ReportVersionsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PentestSessionsTableAnnotationComposer get sessionId {
    final $$PentestSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.pentestSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PentestSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.pentestSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReportVersionsTableTableTableManager
    extends
        RootTableManager<
          _$SecurityDatabase,
          $ReportVersionsTableTable,
          ReportVersionsTableData,
          $$ReportVersionsTableTableFilterComposer,
          $$ReportVersionsTableTableOrderingComposer,
          $$ReportVersionsTableTableAnnotationComposer,
          $$ReportVersionsTableTableCreateCompanionBuilder,
          $$ReportVersionsTableTableUpdateCompanionBuilder,
          (ReportVersionsTableData, $$ReportVersionsTableTableReferences),
          ReportVersionsTableData,
          PrefetchHooks Function({bool sessionId})
        > {
  $$ReportVersionsTableTableTableManager(
    _$SecurityDatabase db,
    $ReportVersionsTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReportVersionsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReportVersionsTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ReportVersionsTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReportVersionsTableCompanion(
                id: id,
                sessionId: sessionId,
                version: version,
                format: format,
                content: content,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                Value<int> version = const Value.absent(),
                Value<String> format = const Value.absent(),
                required String content,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => ReportVersionsTableCompanion.insert(
                id: id,
                sessionId: sessionId,
                version: version,
                format: format,
                content: content,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReportVersionsTableTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
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
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$ReportVersionsTableTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$ReportVersionsTableTableReferences
                                        ._sessionIdTable(db)
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

typedef $$ReportVersionsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$SecurityDatabase,
      $ReportVersionsTableTable,
      ReportVersionsTableData,
      $$ReportVersionsTableTableFilterComposer,
      $$ReportVersionsTableTableOrderingComposer,
      $$ReportVersionsTableTableAnnotationComposer,
      $$ReportVersionsTableTableCreateCompanionBuilder,
      $$ReportVersionsTableTableUpdateCompanionBuilder,
      (ReportVersionsTableData, $$ReportVersionsTableTableReferences),
      ReportVersionsTableData,
      PrefetchHooks Function({bool sessionId})
    >;

class $SecurityDatabaseManager {
  final _$SecurityDatabase _db;
  $SecurityDatabaseManager(this._db);
  $$PentestSessionsTableTableManager get pentestSessions =>
      $$PentestSessionsTableTableManager(_db, _db.pentestSessions);
  $$SessionAssetsTableTableManager get sessionAssets =>
      $$SessionAssetsTableTableManager(_db, _db.sessionAssets);
  $$SessionFindingsTableTableManager get sessionFindings =>
      $$SessionFindingsTableTableManager(_db, _db.sessionFindings);
  $$SessionTimelineEventsTableTableManager get sessionTimelineEvents =>
      $$SessionTimelineEventsTableTableManager(_db, _db.sessionTimelineEvents);
  $$ThreatIntelEntriesTableTableManager get threatIntelEntries =>
      $$ThreatIntelEntriesTableTableManager(_db, _db.threatIntelEntries);
  $$ReportVersionsTableTableTableManager get reportVersionsTable =>
      $$ReportVersionsTableTableTableManager(_db, _db.reportVersionsTable);
}
