/// 播放控制器。
///
/// **播放状态由主进程持有**（design D7）：`desktop_multi_window` 的子窗口是
/// 独立 Dart isolate，若播放逻辑放在悬浮窗里，主窗口的管理界面就拿不到真实
/// 播放状态，"两处状态一致"无法实现；且悬浮窗关闭会终止播放，"关闭不终止
/// 播放"也会破。放在主进程，悬浮窗只做渲染，两个要求同时满足。
///
/// 变速走 `audioplayers` 的 `setPlaybackRate`——macOS 端 `AVPlayer` 显式设置
/// 了 `audioTimePitchAlgorithm = .timeDomain`，**变速时音高保持**，正是
/// "慢速磨耳朵"需要的（design D8）。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/listening_models.dart';
import 'listening_audio_player.dart';
import 'resume_recorder.dart';

/// 播放状态。
enum ListeningPlaybackState { stopped, playing, paused, buffering }

/// 播放控制器的对外快照。
class ListeningPlaybackSnapshot {
  final ListeningPlaybackState state;
  final Clip? clip;
  final Duration position;
  final Duration duration;
  final double speed;

  const ListeningPlaybackSnapshot({
    this.state = ListeningPlaybackState.stopped,
    this.clip,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
  });

  bool get isPlaying => state == ListeningPlaybackState.playing;

  ListeningPlaybackSnapshot copyWith({
    ListeningPlaybackState? state,
    Clip? clip,
    Duration? position,
    Duration? duration,
    double? speed,
  }) {
    return ListeningPlaybackSnapshot(
      state: state ?? this.state,
      clip: clip ?? this.clip,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      speed: speed ?? this.speed,
    );
  }
}

/// 播放速度档位。
///
/// 上限 1.25x：真实海外会议大多就在这个区间，更快会让人听不清而不是更快。
const List<double> kListeningSpeedSteps = [0.75, 0.9, 1.0, 1.25];

/// 播放控制器。
class ListeningPlayerController extends ChangeNotifier {
  /// 播放器实现。抽成接口是为了让 widget 测试能注入假实现——
  /// `audioplayers` 在 flutter test 里没有平台实现（EventChannel 的
  /// channel 名带运行期 UUID，根本没法 mock）。
  final ListeningAudioPlayer _player;

  /// 播放断点记录器。
  final ResumeRecorder recorder;

  /// 默认音频路径解析器（供自动连播下一首时使用）。
  String? Function(Clip clip)? defaultFilePathFor;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _stateSub;

  ListeningPlaybackState _state = ListeningPlaybackState.stopped;
  Clip? _clip;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  /// 启动恢复时预载入的音频路径（处于暂停态、尚未真正调用底层播放器发声）。
  String? _preparedFilePath;

  /// 连续播放：到末尾自动接下一条。
  bool _continuous = false;

  /// 连续播放的候选队列（按场景筛选后的片段列表）。
  List<Clip> _queue = const [];

  /// 队列中当前片段的下标。
  int _queueIndex = -1;

  /// 播放失败或完成的回调（供 UI 提示）。
  final void Function(String message)? onError;

  ListeningPlayerController({
    ListeningAudioPlayer? player,
    ResumeRecorder? recorder,
    this.defaultFilePathFor,
    this.onError,
  })  : _player = player ?? AudioPlayerListeningAdapter(),
        recorder = recorder ?? ResumeRecorder() {
    _initListeners();
  }

  ListeningPlaybackState get state => _state;
  Clip? get clip => _clip;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  bool get isPlaying => _state == ListeningPlaybackState.playing;
  bool get isContinuous => _continuous;
  List<Clip> get queue => _queue;

  /// 当前播放快照。
  ListeningPlaybackSnapshot get snapshot => ListeningPlaybackSnapshot(
        state: _state,
        clip: _clip,
        position: _position,
        duration: _duration,
        speed: _speed,
      );

  void _initListeners() {
    _posSub = _player.onPositionChanged.listen((pos) {
      _position = pos;
      final current = _clip;
      if (current != null && _state == ListeningPlaybackState.playing) {
        unawaited(
          recorder.onPositionTick(
            current,
            pos.inMilliseconds,
            durationMs: _duration.inMilliseconds,
          ),
        );
      }
      notifyListeners();
    });
    _durSub = _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    _completeSub = _player.onPlayerComplete.listen((_) {
      _onComplete();
    });
    _stateSub = _player.onPlayerStateChanged.listen((state) {
      switch (state) {
        case PlayerState.playing:
          _state = ListeningPlaybackState.playing;
        case PlayerState.paused:
          _state = ListeningPlaybackState.paused;
        case PlayerState.stopped:
          _state = ListeningPlaybackState.stopped;
        case PlayerState.completed:
          _state = ListeningPlaybackState.stopped;
        case PlayerState.disposed:
          _state = ListeningPlaybackState.stopped;
      }
      notifyListeners();
    });
  }

  /// 设定连续播放的队列，并定位到指定片段。
  ///
  /// 若未传 [clipId] 但传了 [sceneId]，优先定位到该场景上次播放的片段。
  void setQueue(List<Clip> queue, {String? clipId, String? sceneId}) {
    _queue = queue;
    final targetId =
        clipId ?? (sceneId != null ? recorder.sceneLastClip(sceneId) : null);
    if (targetId != null) {
      final idx = queue.indexWhere((c) => c.id == targetId);
      _queueIndex = idx >= 0 ? idx : (queue.isEmpty ? -1 : 0);
    } else {
      _queueIndex = -1;
    }
  }

  /// 解析某场景队列中应恢复播放的片段（若无记录则返回队列首项）。
  Clip? resolveSceneResumeClip(List<Clip> sceneQueue, String sceneId) {
    if (sceneQueue.isEmpty) return null;
    final lastId = recorder.sceneLastClip(sceneId);
    if (lastId != null) {
      for (final c in sceneQueue) {
        if (c.id == lastId) return c;
      }
    }
    return sceneQueue.first;
  }

  /// 预载入片段并停在指定偏移的暂停状态（启动恢复用，不触发底层发声）。
  void preparePaused(
    Clip clip, {
    required int offsetMs,
    String? filePath,
  }) {
    final safeOffset = (clip.durationMs > 0 && offsetMs >= clip.durationMs)
        ? 0
        : (offsetMs < 0 ? 0 : offsetMs);
    _clip = clip;
    _position = Duration(milliseconds: safeOffset);
    _duration = Duration(milliseconds: clip.durationMs);
    _state = ListeningPlaybackState.paused;
    _preparedFilePath = filePath;
    notifyListeners();
  }

  /// 播放某个片段。
  ///
  /// 若未显式传入 [startOffsetMs]，自动从 `recorder.offsetFor(clip.id)` 恢复。
  Future<void> play(
    Clip clip, {
    String? filePath,
    int? startOffsetMs,
  }) async {
    final resolvedPath = filePath ?? defaultFilePathFor?.call(clip);
    if (resolvedPath == null) {
      onError?.call('素材文件缺失，无法播放');
      return;
    }

    // 切换内容前先保存上一条内容的当前位置。
    final previousClip = _clip;
    if (previousClip != null &&
        previousClip.id != clip.id &&
        _position.inMilliseconds > 0) {
      await recorder.flushNow(
        clip: previousClip,
        offsetMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
      );
    }

    final resumeMs = startOffsetMs ??
        recorder.offsetFor(clip.id, currentDurationMs: clip.durationMs);

    _preparedFilePath = null;
    _clip = clip;
    _position = Duration(milliseconds: resumeMs);
    _duration = Duration(milliseconds: clip.durationMs);
    final qIdx = _queue.indexWhere((c) => c.id == clip.id);
    if (qIdx >= 0) _queueIndex = qIdx;

    try {
      await _player.setPlaybackRate(_speed);
      await _player.playFile(resolvedPath);
      if (resumeMs > 0) {
        await _player.seek(Duration(milliseconds: resumeMs));
        _position = Duration(milliseconds: resumeMs);
      }
      _state = ListeningPlaybackState.playing;
      await recorder.onClipStarted(
        clip,
        initialOffsetMs: resumeMs,
        durationMs: clip.durationMs,
      );
    } catch (e) {
      onError?.call('播放失败：$e');
      _state = ListeningPlaybackState.stopped;
    }
    notifyListeners();
  }

  /// 播放/暂停切换。
  Future<void> togglePlay() async {
    if (_clip == null) return;
    if (_state == ListeningPlaybackState.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() async {
    if (_preparedFilePath == null) {
      await _player.pause();
    }
    _state = ListeningPlaybackState.paused;
    final current = _clip;
    if (current != null) {
      await recorder.flushNow(
        clip: current,
        offsetMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
      );
    }
    notifyListeners();
  }

  Future<void> resume() async {
    final current = _clip;
    if (current != null && _preparedFilePath != null) {
      final path = _preparedFilePath;
      _preparedFilePath = null;
      await play(
        current,
        filePath: path,
        startOffsetMs: _position.inMilliseconds,
      );
      return;
    }
    await _player.resume();
    _state = ListeningPlaybackState.playing;
    notifyListeners();
  }

  Future<void> stop() async {
    final current = _clip;
    if (current != null && _position.inMilliseconds > 0) {
      await recorder.flushNow(
        clip: current,
        offsetMs: _position.inMilliseconds,
        durationMs: _duration.inMilliseconds,
      );
    }
    _preparedFilePath = null;
    await _player.stop();
    _state = ListeningPlaybackState.stopped;
    _position = Duration.zero;
    notifyListeners();
  }

  /// 跳到指定位置（毫秒）。
  Future<void> seek(int positionMs) async {
    if (_preparedFilePath == null) {
      await _player.seek(Duration(milliseconds: positionMs));
    }
    _position = Duration(milliseconds: positionMs);
    final current = _clip;
    if (current != null) {
      await recorder.flushNow(
        clip: current,
        offsetMs: positionMs,
        durationMs: _duration.inMilliseconds,
      );
    }
    notifyListeners();
  }

  /// 立即将当前播放位置落盘（用于迷你窗关闭、页面/应用退出）。
  Future<void> flushProgress() async {
    final current = _clip;
    if (current == null) return;
    await recorder.flushNow(
      clip: current,
      offsetMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
    );
  }

  /// 设置变速。
  Future<void> setSpeed(double speed) async {
    if (!kListeningSpeedSteps.contains(speed)) return;
    _speed = speed;
    await _player.setPlaybackRate(speed);
    notifyListeners();
  }

  /// 减速一档。
  Future<void> slowDown() async {
    final idx = kListeningSpeedSteps.indexOf(_speed);
    if (idx <= 0) return;
    await setSpeed(kListeningSpeedSteps[idx - 1]);
  }

  /// 加速一档。
  Future<void> speedUp() async {
    final idx = kListeningSpeedSteps.indexOf(_speed);
    if (idx < 0 || idx >= kListeningSpeedSteps.length - 1) return;
    await setSpeed(kListeningSpeedSteps[idx + 1]);
  }

  /// 是否为整场会议类内容（排练或真实会议）：上一项/下一项按发言轮次跳转。
  static bool isMeetingClip(Clip clip) =>
      clip.source.sourceId == 'rehearsal' ||
      clip.source.sourceId == 'real-meeting';

  /// 当前播放偏移所在的轮次下标。
  int get currentTurnIndex {
    final c = _clip;
    if (c == null || c.turns.isEmpty) return -1;
    final ms = _position.inMilliseconds;
    for (var i = 0; i < c.turns.length; i++) {
      final t = c.turns[i];
      if (ms >= t.startMs && ms < t.endMs) return i;
    }
    for (var i = c.turns.length - 1; i >= 0; i--) {
      if (ms >= c.turns[i].startMs) return i;
    }
    return 0;
  }

  /// 下一片段（会议类内容则跳到下一轮发言）。
  ///
  /// [filePathFor] 由调用方提供"片段 → 音频绝对路径"的解析（素材库才知道
  /// 素材目录在哪）。为 null 时回退到 [defaultFilePathFor]。
  Future<void> next({String? Function(Clip clip)? filePathFor}) async {
    final current = _clip;
    if (current != null && isMeetingClip(current) && current.turns.isNotEmpty) {
      final idx = currentTurnIndex;
      if (idx >= 0 && idx + 1 < current.turns.length) {
        await seek(current.turns[idx + 1].startMs);
      }
      return;
    }

    if (_queue.isEmpty) return;
    final resolver = filePathFor ?? defaultFilePathFor;
    final targetIndex = _findPlayableIndex(from: _queueIndex, step: 1, filePathFor: resolver);
    if (targetIndex == null) {
      await stop();
      return;
    }
    _queueIndex = targetIndex;
    await _playAt(_queueIndex, resolver);
  }

  /// 上一片段（会议类内容：本轮开始 >2 秒回到本轮开头，否则跳到上一轮）。
  Future<void> previous({String? Function(Clip clip)? filePathFor}) async {
    final current = _clip;
    if (current != null && isMeetingClip(current) && current.turns.isNotEmpty) {
      final idx = currentTurnIndex;
      if (idx < 0) return;
      final turn = current.turns[idx];
      if (_position.inMilliseconds - turn.startMs > 2000) {
        await seek(turn.startMs);
      } else if (idx > 0) {
        await seek(current.turns[idx - 1].startMs);
      } else {
        await seek(current.turns.first.startMs);
      }
      return;
    }

    if (_queue.isEmpty) return;
    final resolver = filePathFor ?? defaultFilePathFor;
    final targetIndex = _findPlayableIndex(from: _queueIndex, step: -1, filePathFor: resolver);
    if (targetIndex == null) return;
    _queueIndex = targetIndex;
    await _playAt(_queueIndex, resolver);
  }

  int? _findPlayableIndex({
    required int from,
    required int step,
    required String? Function(Clip clip)? filePathFor,
  }) {
    if (_queue.isEmpty) return null;
    for (var i = 0; i < _queue.length; i++) {
      final raw = from + step * (i + 1);
      int idx;
      if (raw < 0 || raw >= _queue.length) {
        if (!_continuous) return null;
        idx = ((raw % _queue.length) + _queue.length) % _queue.length;
      } else {
        idx = raw;
      }
      final candidate = _queue[idx];
      if (candidate.isPlaceholder) continue;
      if (filePathFor != null && filePathFor(candidate) == null) continue;
      return idx;
    }
    return null;
  }

  /// 开启/关闭连续播放。
  void setContinuous(bool value) {
    _continuous = value;
    notifyListeners();
  }

  Future<void> _playAt(
    int index,
    String? Function(Clip clip)? filePathFor,
  ) async {
    if (index < 0 || index >= _queue.length) return;
    final target = _queue[index];
    final path = (filePathFor ?? defaultFilePathFor)?.call(target);
    await play(target, filePath: path);
  }

  Future<void> _onComplete() async {
    final finishedClip = _clip;
    if (finishedClip != null) {
      await recorder.markCompleted(
        finishedClip,
        durationMs: _duration.inMilliseconds,
      );
    }
    if (_continuous && _queue.isNotEmpty) {
      await next(filePathFor: defaultFilePathFor);
    } else {
      _state = ListeningPlaybackState.stopped;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(flushProgress());
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.release();
    super.dispose();
  }
}
