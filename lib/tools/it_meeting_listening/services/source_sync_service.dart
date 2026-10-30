/// 增量更新编排。
///
/// 两级变更检测（design D6）：
///
/// ```
/// 第一级（零页面请求）站点级变更标识（sitemap 的 lastmod）
///     ↓ 站点没重建 → 该来源全部栏目跳过
/// 第二级（页面已抓）对话内容哈希
///     ↓ 内容没变 → 跳过烘焙，保留现有音频与文稿
/// ```
///
/// 两级各挡掉一半的浪费：只做第一级，站点每次重建就全量重烘（配额白花）；
/// 只做第二级，每次更新都要全量重抓（网络白花）。
library;

import 'package:flutter/foundation.dart';

import '../models/listening_models.dart';
import 'clip_baker.dart';
import 'listening_source.dart';
import 'source_sync_state.dart';

/// 一个栏目的更新结果。
class ColumnUpdateResult {
  /// 栏目 slug。
  final String columnSlug;

  /// 栏目展示名。
  final String displayName;

  /// 结果分类。
  final ColumnUpdateStatus status;

  /// 失败原因（仅失败时有）。
  final String? reason;

  /// 本次产出的素材数。
  final int produced;

  const ColumnUpdateResult({
    required this.columnSlug,
    required this.displayName,
    required this.status,
    this.reason,
    this.produced = 0,
  });
}

/// 栏目的更新结果分类。
enum ColumnUpdateStatus {
  /// 未变更，已跳过（零抓取零 TTS）。
  unchanged,

  /// 内容变了，已重新烘焙。
  updated,

  /// 首次同步（无基准可比），已完整烘焙。
  initial,

  /// 失败。
  failed,
}

/// 一次更新的整体结果。
class SourceUpdateResult {
  /// 来源标识。
  final String sourceId;

  /// 各栏目的结果。
  final List<ColumnUpdateResult> columns;

  /// 站点级变更标识（本次取到的）。
  final String? siteChangeToken;

  const SourceUpdateResult({
    required this.sourceId,
    required this.columns,
    this.siteChangeToken,
  });

  /// 成功数。
  int get okCount => columns.where((c) => c.status != ColumnUpdateStatus.failed).length;

  /// 失败数。
  int get failedCount => columns.where((c) => c.status == ColumnUpdateStatus.failed).length;

  /// 跳过的栏目数。
  int get skippedCount => columns.where((c) => c.status == ColumnUpdateStatus.unchanged).length;
}

/// 增量更新编排器。
class SourceSyncService {
  final SourceSyncStore _store;
  final ClipBaker _baker;

  SourceSyncService({required SourceSyncStore store, required ClipBaker baker})
      : _store = store,
        _baker = baker;

  /// 更新一个来源。
  ///
  /// [existingClips] 是当前素材库已有的片段——按栏目分组后，未变更的栏目
  /// 直接保留其产物，不重新烘焙。
  Future<SourceUpdateResult> updateSource(
    ListeningSource source, {
    required List<Clip> existingClips,
  }) async {
    final results = <ColumnUpdateResult>[];

    // 第一级：站点级变更标识
    String? siteToken;
    try {
      siteToken = await source.siteChangeToken();
    } catch (e) {
      debugPrint('[SourceSync] 取站点变更标识失败: $e');
    }

    final states = await _store.loadAll();
    final byColumn = <String, List<Clip>>{};
    for (final c in existingClips) {
      byColumn.putIfAbsent(_columnSlugOf(c), () => []).add(c);
    }

    for (final entry in source.columns.entries) {
      final slug = entry.key;
      final column = entry.value;
      final state = states[_key(source.sourceId, slug)];

      // 首次同步：无基准可比 → 完整处理
      if (state == null || !state.hasSynced) {
        final r = await _processColumn(source, column, siteToken, state);
        results.add(r);
        continue;
      }

      // 站点级未变 → 整个栏目跳过（零页面请求、零 TTS）
      if (siteToken != null && state.siteChangeToken == siteToken) {
        results.add(ColumnUpdateResult(
          columnSlug: slug,
          displayName: column.displayName,
          status: ColumnUpdateStatus.unchanged,
        ));
        continue;
      }

      // 站点级变了 → 抓取后比内容哈希
      final r = await _processColumn(source, column, siteToken, state);
      results.add(r);
    }

    return SourceUpdateResult(
      sourceId: source.sourceId,
      columns: results,
      siteChangeToken: siteToken,
    );
  }

  Future<ColumnUpdateResult> _processColumn(
    ListeningSource source,
    SourceColumn column,
    String? siteToken,
    SourceSyncState? state,
  ) async {
    try {
      final dialogues = await source.fetchDialogues(column.slug);
      final hash = computeContentHash(
        dialogues.expand((d) => d.turns).toList(),
      );

      // 第二级：内容未变 → 跳过烘焙，保留现有产物
      if (state != null && state.hasSynced && state.contentHash == hash) {
        await _store.save(state.copyWith(
          lastSyncedAt: DateTime.now(),
          siteChangeToken: siteToken,
          clearFailure: true,
        ));
        return ColumnUpdateResult(
          columnSlug: column.slug,
          displayName: column.displayName,
          status: ColumnUpdateStatus.unchanged,
        );
      }

      // 内容变了 → 重新烘焙
      final produced = <Clip>[];
      for (final dialogue in dialogues) {
        final r = await _baker.bakeSourceDialogue(dialogue);
        produced.addAll(r.clips);
        if (r.failures.isNotEmpty) {
          debugPrint('[SourceSync] ${column.slug} 部分失败: ${r.failures.values}');
        }
      }

      await _store.save(SourceSyncState(
        sourceId: source.sourceId,
        columnSlug: column.slug,
        lastSyncedAt: DateTime.now(),
        siteChangeToken: siteToken,
        contentHash: hash,
        failureCount: 0,
      ));

      return ColumnUpdateResult(
        columnSlug: column.slug,
        displayName: column.displayName,
        status: state == null || !state.hasSynced
            ? ColumnUpdateStatus.initial
            : ColumnUpdateStatus.updated,
        produced: produced.length,
      );
    } catch (e) {
      await _store.recordFailure(source.sourceId, column.slug, '$e');
      return ColumnUpdateResult(
        columnSlug: column.slug,
        displayName: column.displayName,
        status: ColumnUpdateStatus.failed,
        reason: '$e',
      );
    }
  }

  static String _key(String sourceId, String columnSlug) => '$sourceId::$columnSlug';

  /// 从素材 id 反推栏目 slug。
  ///
  /// 素材 id 规则：`{sourceId}_{sceneId}_{columnSlug}_{block}`。
  static String _columnSlugOf(Clip clip) {
    final parts = clip.id.split('_');
    if (parts.length >= 4) return parts.sublist(2, parts.length - 1).join('_');
    return '';
  }
}
