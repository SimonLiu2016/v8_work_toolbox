/// 公开素材控制器：索引加载、源站增量同步、按场景/全量公开素材生成、来源与待生成统计。
///
/// 严格限定作用域（spec「合成作用域明确」）：
/// - `publicClips` 只包含非 `rehearsal`、非 `real-meeting` 的公开素材片段；
/// - `bakePending({scene})` 只合成公开素材的待生成片段，绝不触碰真实会议或排练；
/// - 场景列表只返回有公开素材的真实会议场景，不包含 `rehearsal` / `realMeeting`。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../services/app_paths.dart';
import '../../reader/services/tts_engine.dart';
import '../models/listening_models.dart';
import 'clip_baker.dart';
import 'clip_library.dart';
import 'coderslingo_source.dart';
import 'listening_host.dart';
import 'listening_source.dart';
import 'source_sync_service.dart';
import 'source_sync_state.dart';
import 'task_tracker.dart';

/// 公开素材控制器。
class PublicLibraryController extends ChangeNotifier {
  final ClipLibrary library;
  final TaskTracker tracker;
  final TtsEngine Function() _ttsEngineFactory;

  ClipIndex _index = const ClipIndex();
  DateTime? _lastSyncedAt;

  PublicLibraryController({
    ClipLibrary? library,
    required this.tracker,
    TtsEngine Function()? ttsEngineFactory,
  })  : library = library ?? ListeningHost.instance.library,
        _ttsEngineFactory = ttsEngineFactory ?? (() => OpenAiTtsEngine());

  ClipIndex get index => _index;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// 是否属于公开素材片段（排除排练与真实会议）。
  static bool isPublicClip(Clip c) =>
      c.source.sourceId != 'rehearsal' && c.source.sourceId != 'real-meeting';

  /// 全部公开素材片段。
  List<Clip> get publicClips => _index.clips.where(isPublicClip).toList();

  /// 当前公开素材包含的全部来源（`sourceId -> siteName`）。
  Map<String, String> get availableSources {
    final out = <String, String>{};
    for (final c in _index.clips) {
      if (!isPublicClip(c)) continue;
      out[c.source.sourceId] =
          c.source.site.isEmpty ? c.source.sourceId : c.source.site;
    }
    return out;
  }

  /// 是否存在多个公开素材来源（决定是否展示来源下拉）。
  bool get hasMultipleSources => availableSources.length > 1;

  /// 按来源过滤后的非空公开素材场景列表（绝不含 `rehearsal` / `realMeeting`）。
  List<MeetingScene> nonEmptyScenes({String? sourceId}) {
    final pool = _filteredPool(sourceId: sourceId);
    final out = <MeetingScene>[];
    for (final scene in MeetingScene.values) {
      if (scene == MeetingScene.rehearsal ||
          scene == MeetingScene.realMeeting) {
        continue;
      }
      if (pool.any((c) => c.scene == scene)) {
        out.add(scene);
      }
    }
    return out;
  }

  /// 某场景下的公开素材片段（按可选来源过滤）。
  List<Clip> clipsForScene(MeetingScene scene, {String? sourceId}) {
    if (scene == MeetingScene.rehearsal || scene == MeetingScene.realMeeting) {
      return const [];
    }
    return _filteredPool(sourceId: sourceId)
        .where((c) => c.scene == scene)
        .toList();
  }

  /// 某场景下尚未生成音频的公开素材片段。
  List<Clip> pendingForScene(MeetingScene scene, {String? sourceId}) =>
      clipsForScene(scene, sourceId: sourceId)
          .where((c) => c.isPlaceholder)
          .toList();

  /// 全部尚未生成音频的公开素材片段。
  List<Clip> get allPendingClips =>
      publicClips.where((c) => c.isPlaceholder).toList();

  List<Clip> _filteredPool({String? sourceId}) {
    return _index.clips
        .where(isPublicClip)
        .where((c) => sourceId == null || c.source.sourceId == sourceId)
        .toList();
  }

  /// 从宿主/磁盘加载素材索引。
  Future<ClipIndex> reloadIndex() async {
    _index = await ListeningHost.instance.loadIndex();
    notifyListeners();
    return _index;
  }

  /// 直接更新内存索引（测试或外部合并后同步）。
  void setIndex(ClipIndex index) {
    _index = index;
    notifyListeners();
  }

  /// 同步公开素材源站。
  Future<void> syncSources({
    ListeningSource? sourceOverride,
    File? syncStateFileOverride,
    Directory? materialDirOverride,
    Directory? cacheDirOverride,
  }) async {
    const taskId = 'all';
    if (tracker.isRunning(WorkspaceTaskKind.publicSync, taskId)) return;

    tracker.start(
      WorkspaceTaskKind.publicSync,
      taskId,
      label: '正在检查源站变更…',
    );

    final source = sourceOverride ?? CoderSlingoSource();
    final matDir = materialDirOverride ?? AppPaths.itMeetingListeningDir;
    final cacheDir = cacheDirOverride ?? AppPaths.itMeetingListeningCacheDir;
    final syncFile = syncStateFileOverride ?? AppPaths.itMeetingSyncStateFile;

    final baker = ClipBaker(
      engine: _ttsEngineFactory(),
      materialDir: matDir,
      cacheDir: cacheDir,
    );
    final syncService = SourceSyncService(
      store: SourceSyncStore(syncFile),
      baker: baker,
    );

    final SourceUpdateResult result;
    try {
      result = await syncService.updateSource(
        source,
        existingClips: _index.clips,
      );
    } catch (e) {
      tracker.fail(WorkspaceTaskKind.publicSync, taskId, '同步失败：$e');
      return;
    }

    final produced = <Clip>[];
    for (final r in result.columns) {
      if (r.status == ColumnUpdateStatus.unchanged) continue;
      try {
        final dialogues = await source.fetchDialogues(r.columnSlug);
        for (final d in dialogues) {
          produced.add(Clip(
            id: d.clipId,
            scene: d.column.scene,
            title: d.scenarioNote.isEmpty
                ? '${d.column.displayName} #${d.blockIndex}'
                : d.scenarioNote,
            audioPath: '',
            durationMs: 0,
            turns: d.turns,
            source: ClipSource(
              sourceId: d.column.sourceId,
              site: CoderSlingoSource.siteName,
              pageUrl: d.pageUrl,
              column: d.column.displayName,
              license: CoderSlingoSource.licenseId,
            ),
          ));
        }
      } catch (_) {}
    }

    await library.rebuildIndex(_mergeClips(produced));
    await reloadIndex();
    _lastSyncedAt = DateTime.now();

    final updatedCount = result.columns
        .where((c) =>
            c.status == ColumnUpdateStatus.updated ||
            c.status == ColumnUpdateStatus.initial)
        .length;
    if (result.failedCount > 0) {
      final firstReason = result.columns
          .where((c) => c.status == ColumnUpdateStatus.failed)
          .map((c) => '${c.displayName}：${c.reason ?? "失败"}')
          .take(2)
          .join('；');
      tracker.fail(
        WorkspaceTaskKind.publicSync,
        taskId,
        '同步完成，${result.failedCount} 个栏目失败（$firstReason）',
      );
    } else {
      tracker.complete(
        WorkspaceTaskKind.publicSync,
        taskId,
        message: updatedCount == 0
            ? '源站无新增变更'
            : '已同步 $updatedCount 个栏目',
      );
    }
    notifyListeners();
  }

  /// 生成公开素材中待生成的片段。
  ///
  /// - 若传入 [scene]，只合成该场景下的待生成公开素材；
  /// - 若 [scene] 为 null，合成全部待生成公开素材；
  /// - **绝不合成** `real-meeting` 或 `rehearsal` 条目。
  Future<void> bakePending({
    MeetingScene? scene,
    String? sourceId,
    Directory? materialDirOverride,
    Directory? cacheDirOverride,
  }) async {
    final taskKey = scene?.id ?? 'all';
    if (tracker.isRunning(WorkspaceTaskKind.publicBake, taskKey)) return;

    final pending = scene != null
        ? pendingForScene(scene, sourceId: sourceId)
        : allPendingClips;
    if (pending.isEmpty) {
      tracker.emitToast('当前没有待生成音频的公开素材');
      return;
    }

    tracker.start(
      WorkspaceTaskKind.publicBake,
      taskKey,
      label: '正在生成音频（0/${pending.length}）…',
      done: 0,
      total: pending.length,
    );

    final matDir = materialDirOverride ?? AppPaths.itMeetingListeningDir;
    final cacheDir = cacheDirOverride ?? AppPaths.itMeetingListeningCacheDir;
    final baker = ClipBaker(
      engine: _ttsEngineFactory(),
      materialDir: matDir,
      cacheDir: cacheDir,
    );

    final baked = <String, Clip>{};
    final failures = <String>[];
    var done = 0;

    for (final clip in pending) {
      final dialogue = FetchedDialogue(
        scene: clip.scene,
        columnSlug: _columnSlugOf(clip),
        column: clip.source.column,
        pageUrl: clip.source.pageUrl,
        blockIndex: _blockIndexOf(clip.id),
        scenarioNote: clip.title,
        turns: clip.turns,
      );
      try {
        final result = await baker.bakeDialogue(
          dialogue,
          onProgress: (id, d, t) {
            if (d < t) {
              tracker.updateProgress(
                WorkspaceTaskKind.publicBake,
                taskKey,
                done: done,
                total: pending.length,
                label: '正在生成音频（$done/${pending.length}）…',
              );
            }
          },
        );
        for (final c in result.clips) {
          baked[c.id] = c;
        }
        failures.addAll(result.failures.values);
      } catch (e) {
        failures.add('$e');
      }
      done++;
      tracker.updateProgress(
        WorkspaceTaskKind.publicBake,
        taskKey,
        done: done,
        total: pending.length,
        label: '正在生成音频（$done/${pending.length}）…',
      );
    }

    await library.clearTurnCache(cacheDir);
    await reloadIndex();
    final merged = _mergeClips(baked.values.toList());
    await library.rebuildIndex(merged);
    await reloadIndex();

    if (failures.isNotEmpty) {
      tracker.fail(
        WorkspaceTaskKind.publicBake,
        taskKey,
        '生成完成，${failures.length} 条失败：${failures.first}',
      );
    } else {
      tracker.complete(
        WorkspaceTaskKind.publicBake,
        taskKey,
        message: '公开素材音频生成完成（共 ${baked.length} 条）',
      );
    }
  }

  /// 将新片段合并入当前索引（保留已烘焙音频与所有排练/真实会议条目）。
  List<Clip> _mergeClips(List<Clip> incoming) {
    final byId = <String, Clip>{
      for (final c in _index.clips) c.id: c,
    };
    for (final p in incoming) {
      final existing = byId[p.id];
      if (existing == null || existing.isPlaceholder || !p.isPlaceholder) {
        byId[p.id] = p;
      }
    }
    return byId.values.toList();
  }

  static String _columnSlugOf(Clip clip) {
    final parts = clip.id.split('_');
    if (parts.length >= 4) return parts.sublist(2, parts.length - 1).join('_');
    return clip.source.column.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
  }

  static int _blockIndexOf(String clipId) {
    final m = RegExp(r'_(\d+)_s\d+$').firstMatch(clipId);
    if (m != null) return int.tryParse(m.group(1) ?? '0') ?? 0;
    final n = RegExp(r'_(\d+)$').firstMatch(clipId);
    return n != null ? (int.tryParse(n.group(1) ?? '0') ?? 0) : 0;
  }
}
