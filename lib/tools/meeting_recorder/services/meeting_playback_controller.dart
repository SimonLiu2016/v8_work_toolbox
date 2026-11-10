import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 播放器抽象接口，隔离 audioplayers 的原生平台依赖
abstract class MeetingAudioPlayer {
  Stream<Duration> get onPositionChanged;
  Stream<Duration> get onDurationChanged;
  Stream<void> get onPlayerComplete;
  Stream<PlayerState> get onPlayerStateChanged;

  Future<void> playFile(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setPlaybackRate(double rate);
  Future<void> release();
}

/// 生产环境适配器：包装 audioplayers
class AudioPlayerMeetingAdapter implements MeetingAudioPlayer {
  final AudioPlayer _player;

  AudioPlayerMeetingAdapter([AudioPlayer? player])
      : _player = player ?? AudioPlayer();

  @override
  Stream<Duration> get onPositionChanged => _player.onPositionChanged;

  @override
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;

  @override
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  @override
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  @override
  Future<void> playFile(String path) => _player.play(DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setPlaybackRate(double rate) => _player.setPlaybackRate(rate);

  @override
  Future<void> release() => _player.release();
}

/// 会议录音播放业务控制器
class MeetingPlaybackController extends ChangeNotifier {
  final MeetingAudioPlayer _player;

  String? _currentPlayingPath;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackRate = 1.0;

  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;

  MeetingPlaybackController({
    MeetingAudioPlayer? player,
    double initialPlaybackRate = 1.0,
  })  : _player = player ?? AudioPlayerMeetingAdapter(),
        _playbackRate = initialPlaybackRate {
    _posSub = _player.onPositionChanged.listen((p) {
      _position = p;
      notifyListeners();
    });

    _durSub = _player.onDurationChanged.listen((d) {
      if (d > Duration.zero) {
        _duration = d;
        notifyListeners();
      }
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _position = Duration.zero;
      notifyListeners();
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      final playing = state == PlayerState.playing;
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
    });
  }

  String? get currentPlayingPath => _currentPlayingPath;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get playbackRate => _playbackRate;

  bool isPathPlaying(String path) =>
      _currentPlayingPath == path && _isPlaying;

  bool isPathSelected(String path) =>
      _currentPlayingPath == path;

  /// 点击某录音项：若当前正在播放该文件则切换暂停/播放，若切到新文件则停止旧的并开始新的
  Future<void> togglePlay(String path, {int? fallbackDurationMs}) async {
    if (_currentPlayingPath == path) {
      if (_isPlaying) {
        await pause();
      } else {
        await resume();
      }
      return;
    }

    await play(path, fallbackDurationMs: fallbackDurationMs);
  }

  Future<void> play(String path, {int? fallbackDurationMs}) async {
    _currentPlayingPath = path;
    _position = Duration.zero;
    if (fallbackDurationMs != null && fallbackDurationMs > 0) {
      _duration = Duration(milliseconds: fallbackDurationMs);
    } else {
      _duration = Duration.zero;
    }
    _isPlaying = true;
    notifyListeners();

    try {
      await _player.playFile(path);
      if (_playbackRate != 1.0) {
        await _player.setPlaybackRate(_playbackRate);
      }
    } catch (e) {
      debugPrint('[MeetingPlaybackController] 播放音频失败: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> pause() async {
    _isPlaying = false;
    notifyListeners();
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> resume() async {
    if (_currentPlayingPath == null) return;
    _isPlaying = true;
    notifyListeners();
    try {
      await _player.resume();
    } catch (_) {}
  }

  Future<void> stop() async {
    _isPlaying = false;
    _position = Duration.zero;
    _currentPlayingPath = null;
    notifyListeners();
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> seek(Duration target) async {
    _position = target;
    notifyListeners();
    try {
      await _player.seek(target);
    } catch (_) {}
  }

  Future<void> setPlaybackRate(double rate) async {
    if (_playbackRate == rate) return;
    _playbackRate = rate;
    notifyListeners();
    try {
      await _player.setPlaybackRate(rate);
    } catch (_) {}
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.stop();
    _player.release();
    super.dispose();
  }
}
