/// 播放断点记录器：内存态 + 节流/事件立即落盘。
///
/// 集中承载三条控制路径（主页面、迷你播放窗、全局热键）的断点写入与恢复计算：
/// - 播放中按固定周期（默认 5 秒）节流落盘；
/// - 暂停、停止、拖动定位、切换内容、播放完成、窗口/应用退出时立即落盘；
/// - 距结尾不足 5 秒或已播 ≥ 98% 时判定为"已听完"，偏移归零并标记 `completedAt`；
/// - 重新从头播放已听完的内容时清除 `completedAt`。
library;

import 'package:flutter/foundation.dart';

import '../models/listening_models.dart';
import 'listening_progress_store.dart';

/// 播放断点记录器。
class ResumeRecorder extends ChangeNotifier {
  final ListeningProgressStore? _store;
  final Duration throttleInterval;
  final DateTime Function() _clock;

  ListeningProgressState _state = const ListeningProgressState();
  bool _initialized = false;
  DateTime? _lastPersistAt;
  bool _dirty = false;

  ResumeRecorder({
    ListeningProgressStore? store,
    this.throttleInterval = const Duration(seconds: 5),
    DateTime Function()? clock,
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  /// 当前内存中的完整断点状态。
  ListeningProgressState get state => _state;

  /// 是否已完成初始化读取。
  bool get isInitialized => _initialized;

  /// 全局最后一次播放记录。
  LastPlayedPointer? get lastPlayed => _state.lastPlayed;

  /// 从磁盘载入初始状态（若已通过测试预置则直接返回）。
  Future<ListeningProgressState> init() async {
    if (_initialized) return _state;
    final store = _store;
    if (store != null) {
      _state = await store.loadState();
    }
    _initialized = true;
    notifyListeners();
    return _state;
  }

  /// 测试注入：直接预置内存状态，跳过磁盘读取。
  @visibleForTesting
  void setStateForTesting(ListeningProgressState state) {
    _state = state;
    _initialized = true;
    notifyListeners();
  }

  /// 查询某项内容的进度记录。
  ItemProgress? progressFor(String clipId) => _state.items[clipId];

  /// 查询某场景最后播放到的片段 id。
  String? sceneLastClip(String sceneId) => _state.scenes[sceneId]?.clipId;

  /// 计算某项内容本次播放应恢复到的偏移（毫秒）。
  ///
  /// - 无记录或已标记听完 → 0
  /// - 记录偏移超出当前已知时长（例如重新合成后变短）或已落入结尾区间 → 0
  int offsetFor(String clipId, {int? currentDurationMs}) {
    final item = _state.items[clipId];
    if (item == null || item.isCompleted || item.offsetMs <= 0) return 0;
    final effectiveDuration = (currentDurationMs != null && currentDurationMs > 0)
        ? currentDurationMs
        : item.durationMs;
    if (effectiveDuration > 0) {
      if (item.offsetMs >= effectiveDuration) return 0;
      if (isNearEnd(item.offsetMs, effectiveDuration)) return 0;
    }
    return item.offsetMs;
  }

  /// 是否已接近结尾（距结尾 < 5 秒或进度 ≥ 98%）。
  static bool isNearEnd(int offsetMs, int durationMs) {
    if (offsetMs <= 0 || durationMs <= 0) return false;
    final remaining = durationMs - offsetMs;
    if (remaining < 5000) return true;
    if (offsetMs / durationMs >= 0.98) return true;
    return false;
  }

  /// 开始播放某个片段时调用：更新场景指针与 `lastPlayed`，若从头开始则清除旧的完成标记。
  Future<void> onClipStarted(
    Clip clip, {
    required int initialOffsetMs,
    int? durationMs,
  }) async {
    final now = _clock();
    final dur = _resolveDuration(clip, durationMs);
    final prev = _state.items[clip.id];
    final items = Map<String, ItemProgress>.from(_state.items);
    items[clip.id] = ItemProgress(
      clipId: clip.id,
      offsetMs: initialOffsetMs,
      durationMs: dur > 0 ? dur : (prev?.durationMs ?? 0),
      updatedAt: now,
      completedAt: null,
    );
    final scenes = Map<String, SceneProgress>.from(_state.scenes);
    scenes[clip.scene.id] = SceneProgress(
      sceneId: clip.scene.id,
      clipId: clip.id,
      updatedAt: now,
    );
    _state = ListeningProgressState(
      items: items,
      scenes: scenes,
      lastPlayed: LastPlayedPointer(clipId: clip.id, updatedAt: now),
    );
    _lastPersistAt = now;
    _dirty = false;
    notifyListeners();
    await _persist();
  }

  /// 播放过程中的位置心跳：立即更新内存，按 `throttleInterval` 节流落盘。
  Future<void> onPositionTick(
    Clip clip,
    int offsetMs, {
    int? durationMs,
  }) async {
    if (offsetMs < 0) return;
    final now = _clock();
    _updateInMemory(clip, offsetMs, durationMs: durationMs, now: now);
    final last = _lastPersistAt;
    if (last == null || now.difference(last) >= throttleInterval) {
      _lastPersistAt = now;
      _dirty = false;
      await _persist();
    } else {
      _dirty = true;
    }
  }

  /// 事件触发（暂停 / 停止 / 拖动定位 / 切换内容 / 窗口关闭 / 退出）立即落盘。
  Future<void> flushNow({
    Clip? clip,
    int? offsetMs,
    int? durationMs,
  }) async {
    final now = _clock();
    if (clip != null && offsetMs != null && offsetMs >= 0) {
      _updateInMemory(clip, offsetMs, durationMs: durationMs, now: now);
    } else if (!_dirty) {
      return;
    }
    _lastPersistAt = now;
    _dirty = false;
    await _persist();
  }

  /// 播放自然结束或被判定为已听完时调用：偏移置 0 并记录 `completedAt`。
  Future<void> markCompleted(Clip clip, {int? durationMs}) async {
    final now = _clock();
    final dur = _resolveDuration(clip, durationMs);
    final prev = _state.items[clip.id];
    final items = Map<String, ItemProgress>.from(_state.items);
    items[clip.id] = ItemProgress(
      clipId: clip.id,
      offsetMs: 0,
      durationMs: dur > 0 ? dur : (prev?.durationMs ?? 0),
      updatedAt: now,
      completedAt: now,
    );
    final scenes = Map<String, SceneProgress>.from(_state.scenes);
    scenes[clip.scene.id] = SceneProgress(
      sceneId: clip.scene.id,
      clipId: clip.id,
      updatedAt: now,
    );
    _state = ListeningProgressState(
      items: items,
      scenes: scenes,
      lastPlayed: LastPlayedPointer(clipId: clip.id, updatedAt: now),
    );
    _lastPersistAt = now;
    _dirty = false;
    notifyListeners();
    await _persist();
  }

  void _updateInMemory(
    Clip clip,
    int offsetMs, {
    int? durationMs,
    required DateTime now,
  }) {
    final prev = _state.items[clip.id];
    final dur = _resolveDuration(clip, durationMs, fallback: prev?.durationMs);
    final completed = isNearEnd(offsetMs, dur);
    final items = Map<String, ItemProgress>.from(_state.items);
    items[clip.id] = ItemProgress(
      clipId: clip.id,
      offsetMs: completed ? 0 : offsetMs,
      durationMs: dur,
      updatedAt: now,
      completedAt: completed ? now : null,
    );
    final scenes = Map<String, SceneProgress>.from(_state.scenes);
    scenes[clip.scene.id] = SceneProgress(
      sceneId: clip.scene.id,
      clipId: clip.id,
      updatedAt: now,
    );
    _state = ListeningProgressState(
      items: items,
      scenes: scenes,
      lastPlayed: LastPlayedPointer(clipId: clip.id, updatedAt: now),
    );
    notifyListeners();
  }

  int _resolveDuration(Clip clip, int? durationMs, {int? fallback}) {
    if (durationMs != null && durationMs > 0) return durationMs;
    if (clip.durationMs > 0) return clip.durationMs;
    return fallback ?? 0;
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null) return;
    await store.saveState(_state);
  }
}
