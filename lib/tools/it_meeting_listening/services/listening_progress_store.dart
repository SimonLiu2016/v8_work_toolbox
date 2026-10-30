/// 播放断点记忆（v2）。
///
/// 按内容（`clipId`）记录播放偏移、时长与完成时间，同时保留每个场景最后播放的
/// 片段以及全局 `lastPlayed` 指针。用户关闭应用、切换内容或重新打开工具时，
/// 从记录的位置继续，而不是从头开始。
///
/// 单独存一个文件而不是塞进素材索引：索引是**烘焙产物**（会被整体重写），
/// 断点是**用户行为**（不该被烘焙覆盖）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 单项内容（公开素材片段 / 排练会议 / 真实会议）的播放进度。
class ItemProgress {
  final String clipId;
  final int offsetMs;
  final int durationMs;
  final DateTime updatedAt;
  final DateTime? completedAt;

  const ItemProgress({
    required this.clipId,
    required this.offsetMs,
    this.durationMs = 0,
    required this.updatedAt,
    this.completedAt,
  });

  bool get isCompleted => completedAt != null;

  /// 已听比例（0.0 ~ 1.0）。若已标记完成则返回 1.0。
  double get ratio {
    if (completedAt != null) return 1.0;
    if (durationMs <= 0 || offsetMs <= 0) return 0.0;
    final r = offsetMs / durationMs;
    return r.clamp(0.0, 1.0);
  }

  ItemProgress copyWith({
    int? offsetMs,
    int? durationMs,
    DateTime? updatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return ItemProgress(
      clipId: clipId,
      offsetMs: offsetMs ?? this.offsetMs,
      durationMs: durationMs ?? this.durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt:
          clearCompletedAt ? null : (completedAt ?? this.completedAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'offsetMs': offsetMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory ItemProgress.fromJson(String clipId, Map<String, dynamic> json) =>
      ItemProgress(
        clipId: clipId,
        offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        completedAt: json['completedAt'] is String
            ? DateTime.tryParse(json['completedAt'] as String)
            : null,
      );
}

/// 某个场景下最后播放到的片段指针。
class SceneProgress {
  final String sceneId;
  final String clipId;
  final DateTime updatedAt;

  const SceneProgress({
    required this.sceneId,
    required this.clipId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'clipId': clipId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory SceneProgress.fromJson(String sceneId, Map<String, dynamic> json) =>
      SceneProgress(
        sceneId: sceneId,
        clipId: json['clipId'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 全局最后一次播放的内容指针。
class LastPlayedPointer {
  final String clipId;
  final DateTime updatedAt;

  const LastPlayedPointer({
    required this.clipId,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'clipId': clipId,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LastPlayedPointer.fromJson(Map<String, dynamic> json) =>
      LastPlayedPointer(
        clipId: json['clipId'] as String? ?? '',
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// v2 完整断点状态。
class ListeningProgressState {
  static const int currentVersion = 2;

  final Map<String, ItemProgress> items;
  final Map<String, SceneProgress> scenes;
  final LastPlayedPointer? lastPlayed;

  const ListeningProgressState({
    this.items = const {},
    this.scenes = const {},
    this.lastPlayed,
  });

  bool get isEmpty => items.isEmpty && scenes.isEmpty && lastPlayed == null;

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
        'scenes': scenes.map((k, v) => MapEntry(k, v.toJson())),
        if (lastPlayed != null) 'lastPlayed': lastPlayed!.toJson(),
      };

  factory ListeningProgressState.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt();
    if (version == null) {
      return ListeningProgressState._fromV1Json(json);
    }
    final items = <String, ItemProgress>{};
    final rawItems = json['items'];
    if (rawItems is Map) {
      rawItems.forEach((key, value) {
        if (key is String && key.isNotEmpty && value is Map) {
          items[key] =
              ItemProgress.fromJson(key, Map<String, dynamic>.from(value));
        }
      });
    }
    final scenes = <String, SceneProgress>{};
    final rawScenes = json['scenes'];
    if (rawScenes is Map) {
      rawScenes.forEach((key, value) {
        if (key is String && key.isNotEmpty && value is Map) {
          final sp =
              SceneProgress.fromJson(key, Map<String, dynamic>.from(value));
          if (sp.clipId.isNotEmpty) scenes[key] = sp;
        }
      });
    }
    LastPlayedPointer? lastPlayed;
    final rawLast = json['lastPlayed'];
    if (rawLast is Map) {
      final parsed =
          LastPlayedPointer.fromJson(Map<String, dynamic>.from(rawLast));
      if (parsed.clipId.isNotEmpty) {
        lastPlayed = parsed;
      }
    }
    return ListeningProgressState(
      items: items,
      scenes: scenes,
      lastPlayed: lastPlayed,
    );
  }

  /// 从 v1（以 `sceneId` 为顶层键的表）迁移到 v2。
  factory ListeningProgressState._fromV1Json(Map<String, dynamic> json) {
    final items = <String, ItemProgress>{};
    final scenes = <String, SceneProgress>{};
    LastPlayedPointer? latest;

    json.forEach((key, value) {
      if (value is! Map) return;
      final map = Map<String, dynamic>.from(value);
      final p = ListeningProgress.fromJson(map);
      final sceneId = p.sceneId.isNotEmpty ? p.sceneId : key;
      if (sceneId.isEmpty || p.clipId.isEmpty) return;
      scenes[sceneId] = SceneProgress(
        sceneId: sceneId,
        clipId: p.clipId,
        updatedAt: p.updatedAt,
      );
      final existing = items[p.clipId];
      if (existing == null || p.updatedAt.isAfter(existing.updatedAt)) {
        items[p.clipId] = ItemProgress(
          clipId: p.clipId,
          offsetMs: p.offsetMs,
          updatedAt: p.updatedAt,
        );
      }
      if (latest == null || p.updatedAt.isAfter(latest!.updatedAt)) {
        latest = LastPlayedPointer(
          clipId: p.clipId,
          updatedAt: p.updatedAt,
        );
      }
    });

    return ListeningProgressState(
      items: items,
      scenes: scenes,
      lastPlayed: latest,
    );
  }
}

/// 某个场景的播放位置（兼容旧调用方）。
class ListeningProgress {
  /// 场景 id。
  final String sceneId;

  /// 最后播放的片段 id。
  final String clipId;

  /// 该片段内的播放偏移（毫秒）。
  final int offsetMs;

  /// 记录时间。
  final DateTime updatedAt;

  const ListeningProgress({
    required this.sceneId,
    required this.clipId,
    this.offsetMs = 0,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'sceneId': sceneId,
        'clipId': clipId,
        'offsetMs': offsetMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ListeningProgress.fromJson(Map<String, dynamic> json) =>
      ListeningProgress(
        sceneId: json['sceneId'] as String? ?? '',
        clipId: json['clipId'] as String? ?? '',
        offsetMs: (json['offsetMs'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 断点记忆存储。
class ListeningProgressStore {
  final File _file;

  /// 串行化写入链，防止并发写入临时文件时互相踩踏。
  Future<void> _writeChain = Future<void>.value();

  ListeningProgressStore(this._file);

  /// 读取 v2 完整状态（自动完成 v1 → v2 内存转换；损坏文件返回空状态）。
  Future<ListeningProgressState> loadState() async {
    await _writeChain;
    return _readStateFromDisk();
  }

  Future<ListeningProgressState> _readStateFromDisk() async {
    if (!await _file.exists()) return const ListeningProgressState();
    try {
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return const ListeningProgressState();
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const ListeningProgressState();
      return ListeningProgressState.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return const ListeningProgressState();
    }
  }

  /// 原子写入 v2 完整状态（串行化）。
  Future<void> saveState(ListeningProgressState state) {
    final op = _writeChain.then((_) => _writeStateAtomically(state));
    _writeChain = op.catchError((_) {});
    return op;
  }

  /// 在串行队列内执行"读-改-写"事务，保证并发调用不丢更新。
  Future<ListeningProgressState> updateState(
    ListeningProgressState Function(ListeningProgressState current) updater,
  ) {
    final completer = Completer<ListeningProgressState>();
    _writeChain = _writeChain.then((_) async {
      try {
        final current = await _readStateFromDisk();
        final next = updater(current);
        await _writeStateAtomically(next);
        completer.complete(next);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _writeStateAtomically(ListeningProgressState state) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  /// 读取全部场景断点（兼容接口）。
  Future<Map<String, ListeningProgress>> loadAll() async {
    final state = await loadState();
    final out = <String, ListeningProgress>{};
    state.scenes.forEach((sceneId, sp) {
      final item = state.items[sp.clipId];
      out[sceneId] = ListeningProgress(
        sceneId: sceneId,
        clipId: sp.clipId,
        offsetMs: item?.offsetMs ?? 0,
        updatedAt: sp.updatedAt,
      );
    });
    return out;
  }

  /// 读取某场景的断点（兼容接口）。
  Future<ListeningProgress?> load(String sceneId) async =>
      (await loadAll())[sceneId];

  /// 写入某场景的断点（兼容接口，内部落盘为 v2）。
  Future<void> save(
    String sceneId,
    String clipId,
    int offsetMs, {
    int durationMs = 0,
  }) async {
    final now = DateTime.now();
    await updateState((current) {
      final items = Map<String, ItemProgress>.from(current.items);
      final prev = items[clipId];
      items[clipId] = ItemProgress(
        clipId: clipId,
        offsetMs: offsetMs,
        durationMs: durationMs > 0 ? durationMs : (prev?.durationMs ?? 0),
        updatedAt: now,
      );
      final scenes = Map<String, SceneProgress>.from(current.scenes);
      scenes[sceneId] = SceneProgress(
        sceneId: sceneId,
        clipId: clipId,
        updatedAt: now,
      );
      return ListeningProgressState(
        items: items,
        scenes: scenes,
        lastPlayed: LastPlayedPointer(clipId: clipId, updatedAt: now),
      );
    });
  }

  /// 清除某场景的断点（兼容接口）。
  Future<void> clear(String sceneId) async {
    await updateState((current) {
      final scenes = Map<String, SceneProgress>.from(current.scenes);
      scenes.remove(sceneId);
      return ListeningProgressState(
        items: current.items,
        scenes: scenes,
        lastPlayed: current.lastPlayed,
      );
    });
  }
}
