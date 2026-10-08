/// 会话/资产/发现物/时间线的读写。
///
/// 只把 drift 的 DataClass 换成自己的领域模型后往上交——UI 与 Agent 都面向
/// `models/security_models.dart`，不接触数据库类型。
///
/// drift 生成的 DataClass 与本模块的领域模型同名（`PentestSession` 等），所以
/// 这里用前缀别名区分：`Db` 前缀是数据库行，无前缀是领域模型。
library;

import 'dart:convert';

import 'package:drift/drift.dart' hide OrderingTerm;
import 'package:drift/drift.dart' as drift show OrderingTerm;
import 'package:uuid/uuid.dart';

import '../database/security_database.dart' show SecurityDatabase;
import '../database/security_database.dart' as db;
import '../models/security_enums.dart';
import '../models/security_models.dart';

/// 仓库层共用的 id 生成。
String newId() => const Uuid().v4();

/// JSON 列表编解码的小工具（scope 字段）。
String encodeJsonList(List<String> values) => jsonEncode(values);

class SessionRepository {
  final SecurityDatabase database;
  const SessionRepository(this.database);

  Future<List<PentestSession>> all() async {
    final rows =
        await (database.select(database.pentestSessions)
              ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
            .get();
    return rows.map<PentestSession>(_toModel).toList();
  }

  Stream<List<PentestSession>> watchAll() {
    return (database.select(database.pentestSessions)
          ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Future<PentestSession?> byId(String id) async {
    final row =
        await (database.select(database.pentestSessions)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// 最近一次仍在进行中的会话（spec 的「会话恢复」）。
  Future<PentestSession?> lastActive() async {
    final row =
        await (database.select(database.pentestSessions)
              ..where((t) => t.status.equals(SessionStatus.active))
              ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<PentestSession> create({
    required String name,
    required String type,
    required List<String> scope,
    String? id,
  }) async {
    final now = DateTime.now();
    final session = PentestSession(
      id: id ?? newId(),
      name: name,
      type: type,
      scopeJson: encodeJsonList(scope),
      status: SessionStatus.active,
      createdAt: now,
      updatedAt: now,
    );
    await database.into(database.pentestSessions).insert(
      db.PentestSessionsCompanion.insert(
        id: session.id,
        name: session.name,
        type: Value(session.type),
        scope: Value(session.scopeJson),
        status: Value(session.status),
        createdAt: session.createdAt,
        updatedAt: session.updatedAt,
      ),
    );
    return session;
  }

  Future<void> touch(String id) async {
    await (database.update(database.pentestSessions)
          ..where((t) => t.id.equals(id)))
        .write(db.PentestSessionsCompanion(updatedAt: Value(DateTime.now())));
  }

  Future<void> rename(String id, String name) async {
    await (database.update(database.pentestSessions)
          ..where((t) => t.id.equals(id)))
        .write(
          db.PentestSessionsCompanion(
            name: Value(name),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setStatus(String id, String status) async {
    await (database.update(database.pentestSessions)
          ..where((t) => t.id.equals(id)))
        .write(
          db.PentestSessionsCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setScope(String id, List<String> scope) async {
    await (database.update(database.pentestSessions)
          ..where((t) => t.id.equals(id)))
        .write(
          db.PentestSessionsCompanion(
            scope: Value(encodeJsonList(scope)),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// 删除会话及其全部从属数据（资产/发现物/时间线/报告版本）。
  Future<void> delete(String id) async {
    await database.transaction(() async {
      // 1. 批量断开当前会话可能关联的 assetId 引用（单条批量 SQL）
      await (database.update(database.sessionFindings)
            ..where((t) => t.sessionId.equals(id)))
          .write(const db.SessionFindingsCompanion(assetId: Value(null)));
      // 2. 依次批量清理从表数据（findings、assets、timeline、reports）
      await (database.delete(database.sessionFindings)
            ..where((t) => t.sessionId.equals(id)))
          .go();
      await (database.delete(database.sessionAssets)
            ..where((t) => t.sessionId.equals(id)))
          .go();
      await (database.delete(database.sessionTimelineEvents)
            ..where((t) => t.sessionId.equals(id)))
          .go();
      await (database.delete(database.reportVersionsTable)
            ..where((t) => t.sessionId.equals(id)))
          .go();
      // 3. 清理主表会话记录
      await (database.delete(database.pentestSessions)
            ..where((t) => t.id.equals(id)))
          .go();
    });
  }

  PentestSession _toModel(db.PentestSession row) => PentestSession(
    id: row.id,
    name: row.name,
    type: row.type,
    scopeJson: row.scope,
    status: row.status,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

class AssetRepository {
  final SecurityDatabase database;
  const AssetRepository(this.database);

  Future<List<PentestAsset>> forSession(String sessionId) async {
    final rows =
        await (database.select(database.sessionAssets)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => drift.OrderingTerm.asc(t.address)]))
            .get();
    return rows.map<PentestAsset>(_toModel).toList();
  }

  Stream<List<PentestAsset>> watchForSession(String sessionId) {
    return (database.select(database.sessionAssets)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => drift.OrderingTerm.asc(t.address)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Future<PentestAsset?> byAddress(String sessionId, String address) async {
    final row =
        await (database.select(database.sessionAssets)
              ..where(
                (t) => t.sessionId.equals(sessionId) & t.address.equals(address),
              ))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<PentestAsset?> byId(String id) async {
    final row =
        await (database.select(database.sessionAssets)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// upsert 资产：按 (sessionId, address) 判重。
  ///
  /// - 已存在 → 合并 metadata（新键覆盖旧键），**不动 userNote**（spec：手动标注
  ///   不受后续扫描覆盖），刷新 updatedAt。
  /// - 不存在 → 插入新行。
  Future<PentestAsset> upsert({
    required String sessionId,
    required String type,
    required String address,
    Map<String, dynamic> metadata = const {},
    String? riskLevel,
  }) async {
    final existing = await byAddress(sessionId, address);
    final now = DateTime.now();
    if (existing == null) {
      final asset = PentestAsset(
        id: newId(),
        sessionId: sessionId,
        type: type,
        address: address,
        metadataJson: jsonEncode(metadata),
        riskLevel: riskLevel ?? 'unknown',
        createdAt: now,
        updatedAt: now,
      );
      await database.into(database.sessionAssets).insert(
        db.SessionAssetsCompanion.insert(
          id: asset.id,
          sessionId: asset.sessionId,
          type: Value(asset.type),
          address: asset.address,
          metadata: Value(asset.metadataJson),
          riskLevel: Value(asset.riskLevel),
          createdAt: asset.createdAt,
          updatedAt: asset.updatedAt,
        ),
      );
      return asset;
    }
    final merged = Map<String, dynamic>.from(existing.metadata);
    for (final entry in metadata.entries) {
      if (entry.value != null) {
        merged[entry.key] = entry.value;
      }
    }
    final asset = existing.copyWith(
      metadataJson: jsonEncode(merged),
      riskLevel: riskLevel ?? existing.riskLevel,
      updatedAt: now,
    );
    await (database.update(database.sessionAssets)
          ..where((t) => t.id.equals(existing.id)))
        .write(
          db.SessionAssetsCompanion(
            metadata: Value(asset.metadataJson),
            riskLevel: Value(asset.riskLevel),
            updatedAt: Value(now),
          ),
        );
    return asset;
  }

  Future<void> setUserNote(String id, String? note) async {
    await (database.update(database.sessionAssets)
          ..where((t) => t.id.equals(id)))
        .write(
          db.SessionAssetsCompanion(
            userNote: Value(note),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setRiskLevel(String id, String riskLevel) async {
    await (database.update(database.sessionAssets)
          ..where((t) => t.id.equals(id)))
        .write(
          db.SessionAssetsCompanion(
            riskLevel: Value(riskLevel),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> delete(String id) async {
    await (database.delete(database.sessionAssets)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  PentestAsset _toModel(db.SessionAsset row) => PentestAsset(
    id: row.id,
    sessionId: row.sessionId,
    type: row.type,
    address: row.address,
    metadataJson: row.metadata,
    riskLevel: row.riskLevel,
    userNote: row.userNote,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

class FindingRepository {
  final SecurityDatabase database;
  const FindingRepository(this.database);

  Future<List<PentestFinding>> forSession(String sessionId) async {
    final rows =
        await (database.select(database.sessionFindings)
              ..where((t) => t.sessionId.equals(sessionId)))
            .get();
    return _sorted(rows.map(_toModel).toList());
  }

  Stream<List<PentestFinding>> watchForSession(String sessionId) {
    return (database.select(database.sessionFindings)
          ..where((t) => t.sessionId.equals(sessionId)))
        .watch()
        .map((rows) => _sorted(rows.map(_toModel).toList()));
  }

  /// 该会话下「同一资产 + 同一 CVE」的 Finding 是否已存在。
  ///
  /// 情报匹配的一键落库靠它做幂等——用户重复点击不该产生第二条目。
  /// cveId 为空（手工录入）时不参与去重，因为空 CVE 之间不可比。
  Future<bool> existsForAssetCve(
    String sessionId,
    String? assetId,
    String? cveId,
  ) async {
    if (assetId == null || cveId == null || cveId.isEmpty) return false;
    final row =
        await (database.select(database.sessionFindings)
              ..where(
                (t) =>
                    t.sessionId.equals(sessionId) &
                    t.assetId.equals(assetId) &
                    t.cveId.equals(cveId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  Future<PentestFinding?> byId(String id) async {
    final row =
        await (database.select(database.sessionFindings)
              ..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// 写入一条 Finding。
  Future<PentestFinding> add({
    required String sessionId,
    String? assetId,
    String? cveId,
    required String title,
    required String severity,
    double? cvssScore,
    String evidence = '',
    required String source,
    String status = FindingStatus.open,
    String? id,
  }) async {
    final now = DateTime.now();
    final finding = PentestFinding(
      id: id ?? newId(),
      sessionId: sessionId,
      assetId: assetId,
      cveId: cveId,
      title: title,
      severity: severity,
      cvssScore: cvssScore,
      status: status,
      evidence: evidence.isEmpty ? null : evidence,
      source: source,
      createdAt: now,
      updatedAt: now,
    );
    await database.into(database.sessionFindings).insert(
      db.SessionFindingsCompanion.insert(
        id: finding.id,
        sessionId: finding.sessionId,
        assetId: Value(finding.assetId),
        cveId: Value(finding.cveId),
        title: finding.title,
        severity: Value(finding.severity),
        cvssScore: Value(finding.cvssScore),
        status: Value(finding.status),
        evidence: Value(finding.evidence),
        source: Value(finding.source),
        createdAt: finding.createdAt,
        updatedAt: finding.updatedAt,
      ),
    );
    return finding;
  }

  Future<void> setStatus(String id, String status) async {
    await (database.update(database.sessionFindings)
          ..where((t) => t.id.equals(id)))
        .write(
          db.SessionFindingsCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> batchSetStatus(List<String> ids, String status) async {
    if (ids.isEmpty) return;
    await (database.update(database.sessionFindings)
          ..where((t) => t.id.isIn(ids)))
        .write(
          db.SessionFindingsCompanion(
            status: Value(status),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> setCvss(String id, double score, String severity) async {
    await (database.update(database.sessionFindings)
          ..where((t) => t.id.equals(id)))
        .write(
          db.SessionFindingsCompanion(
            cvssScore: Value(score),
            severity: Value(severity),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  Future<void> delete(String id) async {
    await (database.delete(database.sessionFindings)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<Map<Severity, int>> severityCounts(String sessionId) async {
    final findings = await forSession(sessionId);
    final counts = <Severity, int>{for (final s in Severity.values) s: 0};
    for (final f in findings) {
      counts[f.severityLevel] = (counts[f.severityLevel] ?? 0) + 1;
    }
    return counts;
  }

  /// 严重等级降序 → 时间倒序。
  ///
  /// severity 是 TEXT 列，SQL 排不出 critical/high/medium/low/info 的语义顺序，
  /// 所以在内存里排（单会话 Finding 量级在千行内，排序开销可忽略）。
  List<PentestFinding> _sorted(List<PentestFinding> list) {
    list.sort((a, b) {
      final bySeverity = a.severityLevel.sortIndex.compareTo(
        b.severityLevel.sortIndex,
      );
      if (bySeverity != 0) return bySeverity;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  PentestFinding _toModel(db.SessionFinding row) => PentestFinding(
    id: row.id,
    sessionId: row.sessionId,
    assetId: row.assetId,
    cveId: row.cveId,
    title: row.title,
    severity: row.severity,
    cvssScore: row.cvssScore,
    status: row.status,
    evidence: row.evidence,
    source: row.source,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}

class TimelineRepository {
  final SecurityDatabase database;
  const TimelineRepository(this.database);

  Future<List<TimelineEvent>> forSession(String sessionId) async {
    final rows =
        await (database.select(database.sessionTimelineEvents)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows.map<TimelineEvent>(_toModel).toList();
  }

  Stream<List<TimelineEvent>> watchForSession(String sessionId) {
    return (database.select(database.sessionTimelineEvents)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
        .watch()
        .map((rows) => rows.map(_toModel).toList());
  }

  Future<TimelineEvent> append({
    required String sessionId,
    required String eventType,
    required String title,
    Map<String, dynamic> detail = const {},
  }) async {
    final event = TimelineEvent(
      id: newId(),
      sessionId: sessionId,
      eventType: eventType,
      title: title,
      detailJson: jsonEncode(detail),
      createdAt: DateTime.now(),
    );
    await database.into(database.sessionTimelineEvents).insert(
      db.SessionTimelineEventsCompanion.insert(
        id: event.id,
        sessionId: event.sessionId,
        eventType: event.eventType,
        title: event.title,
        detail: Value(event.detailJson),
        createdAt: event.createdAt,
      ),
    );
    return event;
  }

  Future<void> clearForSession(String sessionId) async {
    await (database.delete(database.sessionTimelineEvents)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  TimelineEvent _toModel(db.SessionTimelineEvent row) => TimelineEvent(
    id: row.id,
    sessionId: row.sessionId,
    eventType: row.eventType,
    title: row.title,
    detailJson: row.detail,
    createdAt: row.createdAt,
  );
}
