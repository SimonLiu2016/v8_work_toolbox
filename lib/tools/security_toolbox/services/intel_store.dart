/// 情报库的本地存取与同步调度。
///
/// 同步（网络）在这里，写库也在这里——解析与同步拆分到 `threat_intel_services.dart`
/// 是为了单测能只喂 JSON 文本，而这一层承担"把条目 upsert 进 drift"的职责。
library;

import '../../../services/settings_store.dart';
import 'package:drift/drift.dart' show Value;

import '../database/security_database.dart' as db;
import '../database/security_database.dart' show SecurityDatabase;
import '../models/security_models.dart';
import 'threat_intel_services.dart';

/// 情报配置（Shodan/GitHub token 等小配置都落在 settings_store 的工具配置里）。
class IntelSettingsStore {
  IntelSettingsStore._();
  static final IntelSettingsStore instance = IntelSettingsStore._();

  static const String toolId = 'security-toolbox';

  Future<IntelConfig> load() async {
    final config = await SettingsStore.instance.readToolConfig(toolId);
    return IntelConfig(
      githubToken: config['github_token'] as String?,
      syncIntervalHours:
          (config['intel_sync_hours'] as num?)?.toInt() ??
          IntelConfig.defaultHours,
    );
  }

  Future<void> save(IntelConfig config) async {
    final existing = await SettingsStore.instance.readToolConfig(toolId);
    await SettingsStore.instance.writeToolConfig(toolId, {
      ...existing,
      'github_token': config.githubToken,
      'intel_sync_hours': config.syncIntervalHours,
    });
  }
}

/// 情报库仓储。
class ThreatIntelRepository {
  final SecurityDatabase database;
  const ThreatIntelRepository(this.database);

  Future<List<ThreatIntelEntry>> all() async {
    final rows = await database.select(database.threatIntelEntries).get();
    return rows.map(_toModel).toList();
  }

  Stream<List<ThreatIntelEntry>> watchAll() {
    return database.select(database.threatIntelEntries).watch().map(
      (rows) => rows.map(_toModel).toList(),
    );
  }

  /// 写入或更新一条（按 CVE 主键 upsert）。
  Future<void> upsert(ThreatIntelEntry entry) async {
    await database.into(database.threatIntelEntries).insertOnConflictUpdate(
      db.ThreatIntelEntriesCompanion.insert(
        cveId: entry.cveId,
        title: Value(entry.title),
        cvssScore: Value(entry.cvssScore),
        severity: Value(entry.severity),
        description: Value(entry.description),
        published: Value(entry.published),
        isKev: Value(entry.isKev ? 1 : 0),
        pocUrl: Value(entry.pocUrl),
        syncedAt: entry.syncedAt,
      ),
    );
  }

  Future<void> upsertAll(List<ThreatIntelEntry> entries) async {
    if (entries.isEmpty) return;
    await database.batch((b) {
      b.insertAllOnConflictUpdate(database.threatIntelEntries, [
        for (final e in entries)
          db.ThreatIntelEntriesCompanion.insert(
            cveId: e.cveId,
            title: Value(e.title),
            cvssScore: Value(e.cvssScore),
            severity: Value(e.severity),
            description: Value(e.description),
            published: Value(e.published),
            isKev: Value(e.isKev ? 1 : 0),
            pocUrl: Value(e.pocUrl),
            syncedAt: e.syncedAt,
          ),
      ]);
    });
  }

  Future<void> delete(String cveId) async {
    await (database.delete(database.threatIntelEntries)
          ..where((t) => t.cveId.equals(cveId)))
        .go();
  }

  Future<void> clear() async {
    await database.delete(database.threatIntelEntries).go();
  }

  Future<bool> isEmpty() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM threat_intel_entries')
        .getSingle();
    return (row.data['c'] as int? ?? 0) == 0;
  }

  ThreatIntelEntry _toModel(db.ThreatIntelEntry row) => ThreatIntelEntry(
    cveId: row.cveId,
    title: row.title,
    cvssScore: row.cvssScore,
    severity: row.severity,
    description: row.description,
    published: row.published,
    isKev: row.isKev == 1,
    pocUrl: row.pocUrl,
    syncedAt: row.syncedAt,
  );
}

/// 一次完整同步：拉三源 → upsert 入库。
class ThreatIntelSyncService {
  final ThreatIntelRepository repo;

  ThreatIntelSyncService(this.repo);

  /// 执行同步，返回本次写入的条目数与 KEV 命中数。
  Future<({int written, int kev, int poc})> sync({
    int days = 7,
    IntelConfig config = const IntelConfig(),
    void Function(String line)? onLog,
  }) async {
    final cves = await ThreatIntelFeedService.fetchNvd(
      days: days,
      config: config,
    );
    final kev = await ThreatIntelFeedService.fetchKev();
    final criticals = cves
        .where((c) => c.severity == 'critical' || c.severity == 'high')
        .take(20)
        .map((c) => c.id)
        .toList();
    final pocs = await ThreatIntelFeedService.searchPocs(
      criticals,
      config: config,
    );
    final now = DateTime.now();
    final entries = [
      for (final cve in cves)
        cve.toEntry(
          isKev: kev.contains(cve.id),
          pocUrl: pocs[cve.id],
          syncedAt: now,
        ),
    ];
    await repo.upsertAll(entries);
    onLog?.call('同步完成：写入 ${entries.length} 条，KEV ${kev.length} 个，PoC ${pocs.length} 个');
    return (written: entries.length, kev: kev.length, poc: pocs.length);
  }
}
