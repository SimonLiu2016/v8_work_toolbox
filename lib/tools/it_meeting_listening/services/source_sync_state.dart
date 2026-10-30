/// 每个来源的同步状态。
///
/// **与素材存储分开**（design D7）：素材是**产物**（会被重烘焙覆盖），同步状态
/// 是**与环境交互的历史**（上次同步到哪了）。两者生命周期不同——重烘焙不该
/// 让系统以为"这个栏目没同步过"而全量重抓。
library;

import 'dart:convert';
import 'dart:io';


/// 一个来源的一个栏目的同步状态。
class SourceSyncState {
  /// 来源标识。
  final String sourceId;

  /// 栏目 slug。
  final String columnSlug;

  /// 上次成功同步的时间。
  final DateTime? lastSyncedAt;

  /// 上次同步时的**站点级**变更标识。
  ///
  /// 站点没重建时用它整体跳过；重建了才逐栏目比内容哈希。
  final String? siteChangeToken;

  /// 上次同步时的**内容级**变更标识（解析后的对话文本哈希）。
  final String? contentHash;

  /// 最近一次失败的原因。
  final String? lastFailure;

  /// 累计失败次数。
  final int failureCount;

  const SourceSyncState({
    required this.sourceId,
    required this.columnSlug,
    this.lastSyncedAt,
    this.siteChangeToken,
    this.contentHash,
    this.lastFailure,
    this.failureCount = 0,
  });

  /// 这条状态是否记录过成功同步。
  bool get hasSynced => lastSyncedAt != null;

  /// 站点级标识是否变化（变化则需要重抓该栏目）。
  bool siteChanged(String? currentToken) =>
      currentToken != null && currentToken != siteChangeToken;

  /// 内容级标识是否变化。
  bool contentChanged(String? currentHash) => currentHash != contentHash;

  SourceSyncState copyWith({
    DateTime? lastSyncedAt,
    String? siteChangeToken,
    String? contentHash,
    String? lastFailure,
    int? failureCount,
    bool clearFailure = false,
  }) {
    return SourceSyncState(
      sourceId: sourceId,
      columnSlug: columnSlug,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      siteChangeToken: siteChangeToken ?? this.siteChangeToken,
      contentHash: contentHash ?? this.contentHash,
      lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      failureCount: clearFailure ? 0 : (failureCount ?? this.failureCount),
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'columnSlug': columnSlug,
        'lastSyncedAt': lastSyncedAt?.toIso8601String(),
        'siteChangeToken': siteChangeToken,
        'contentHash': contentHash,
        'lastFailure': lastFailure,
        'failureCount': failureCount,
      };

  factory SourceSyncState.fromJson(Map<String, dynamic> json) => SourceSyncState(
        sourceId: json['sourceId'] as String? ?? '',
        columnSlug: json['columnSlug'] as String? ?? '',
        lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
        siteChangeToken: json['siteChangeToken'] as String?,
        contentHash: json['contentHash'] as String?,
        lastFailure: json['lastFailure'] as String?,
        failureCount: (json['failureCount'] as num?)?.toInt() ?? 0,
      );
}

/// 同步状态存储。
class SourceSyncStore {
  final File _file;

  SourceSyncStore(this._file);

  /// 读取全部状态。
  ///
  /// 文件缺失或损坏时返回空表——同步状态丢失只是"下次全量同步"，不该让工具报错。
  Future<Map<String, SourceSyncState>> loadAll() async {
    if (!await _file.exists()) return {};
    try {
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return {};
      final decoded = jsonDecode(text);
      if (decoded is! Map) return {};
      final out = <String, SourceSyncState>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final s = SourceSyncState.fromJson(Map<String, dynamic>.from(value));
          if (s.sourceId.isNotEmpty && s.columnSlug.isNotEmpty) {
            out[_key(s.sourceId, s.columnSlug)] = s;
          }
        }
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// 读取某来源某栏目的状态。
  Future<SourceSyncState?> load(String sourceId, String columnSlug) async =>
      (await loadAll())[_key(sourceId, columnSlug)];

  /// 写入某来源某栏目的状态。
  Future<void> save(SourceSyncState state) async {
    final all = await loadAll();
    all[_key(state.sourceId, state.columnSlug)] = state;
    await _writeAll(all);
  }

  /// 记录一次失败。
  ///
  /// 首次失败时从**空状态**起步（而不是塞一个 `sourceId: ''` 的占位对象）——
  /// 那个占位对象 `loadAll` 读回时会因 `sourceId.isEmpty` 被丢掉，
  /// 失败计数永远停在 0。
  Future<void> recordFailure(
      String sourceId, String columnSlug, String reason) async {
    final all = await loadAll();
    final prev = all[_key(sourceId, columnSlug)];
    all[_key(sourceId, columnSlug)] = SourceSyncState(
      sourceId: sourceId,
      columnSlug: columnSlug,
      lastSyncedAt: prev?.lastSyncedAt,
      siteChangeToken: prev?.siteChangeToken,
      contentHash: prev?.contentHash,
      lastFailure: reason,
      failureCount: (prev?.failureCount ?? 0) + 1,
    );
    await _writeAll(all);
  }

  /// 清除某来源的全部状态（来源下线时用）。
  Future<void> clearSource(String sourceId) async {
    final all = await loadAll();
    all.removeWhere((_, s) => s.sourceId == sourceId);
    await _writeAll(all);
  }

  static String _key(String sourceId, String columnSlug) => '$sourceId::$columnSlug';

  Future<void> _writeAll(Map<String, SourceSyncState> all) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        all.map((k, v) => MapEntry(k, v.toJson())),
      ),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}

/// 对话内容的变更标识。
///
/// 规范化：只看**轮次文本 + 说话人 + 角色**——场景说明行、空白差异、
/// 引号差异都不算内容变化（否则站点改个标点就全量重烘）。
String computeContentHash(Iterable<dynamic> turns) {
  final buffer = StringBuffer();
  for (final t in turns) {
    final speaker = t.speaker as String? ?? '';
    final role = t.role as String? ?? '';
    final text = (t.rawText as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    buffer.write('|$speaker|$role|$text');
  }
  // FNV-1a：足够快，且不需要 crypto 依赖。
  var hash = 0x811c9dc5;
  for (final unit in buffer.toString().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
