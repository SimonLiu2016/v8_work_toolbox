import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/reader_models.dart';
import 'tts_coordinator.dart';

/// 播放器运行状态枚举
enum ReaderPlaybackState {
  stopped,
  playing,
  paused,
  buffering,
}

/// 朗读播放与双向同步控制器
class AudioReaderController extends ChangeNotifier {
  final TtsSynthesisCoordinator coordinator;
  final AudioPlayer _player;

  ReadingDocument? _document;
  int _currentChunkIndex = 0;
  ReaderPlaybackState _playbackState = ReaderPlaybackState.stopped;
  Duration _currentPosition = Duration.zero;
  Duration _chunkDuration = Duration.zero;
  double _speed = 1.0;
  double _volume = 1.0;
  String? _lastErrorMessage;

  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _completeSub;
  StreamSubscription? _stateSub;

  AudioReaderController({
    required this.coordinator,
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer() {
    _initPlayerListeners();
  }

  ReadingDocument? get document => _document;
  int get currentChunkIndex => _currentChunkIndex;
  ReaderPlaybackState get playbackState => _playbackState;
  bool get isPlaying => _playbackState == ReaderPlaybackState.playing;
  bool get isPaused => _playbackState == ReaderPlaybackState.paused;
  bool get isBuffering => _playbackState == ReaderPlaybackState.buffering;
  Duration get currentPosition => _currentPosition;
  Duration get chunkDuration => _chunkDuration;
  double get speed => _speed;
  double get volume => _volume;
  String? get lastErrorMessage => _lastErrorMessage;

  void clearErrorMessage() {
    _lastErrorMessage = null;
    notifyListeners();
  }

  ReadingChunk? get currentChunk {
    if (_document == null || _currentChunkIndex < 0 || _currentChunkIndex >= _document!.chunks.length) {
      return null;
    }
    return _document!.chunks[_currentChunkIndex];
  }

  void _initPlayerListeners() {
    _posSub = _player.onPositionChanged.listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    });

    _durSub = _player.onDurationChanged.listen((dur) {
      _chunkDuration = dur;
      notifyListeners();
    });

    _completeSub = _player.onPlayerComplete.listen((_) {
      // 当前切片播放完毕，自动无缝推进至下一段
      _onChunkFinished();
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        _playbackState = ReaderPlaybackState.playing;
      } else if (state == PlayerState.paused) {
        _playbackState = ReaderPlaybackState.paused;
      } else if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (_playbackState == ReaderPlaybackState.playing) {
          // 状态流转中
        }
      }
      notifyListeners();
    });
  }

  /// 载入新文档并预取前序切片
  Future<void> loadDocument(ReadingDocument doc) async {
    await stop();
    _document = doc;
    _currentChunkIndex = 0;
    _currentPosition = Duration.zero;
    _chunkDuration = Duration.zero;
    notifyListeners();

    // 预加载前两段
    coordinator.ensureAhead(doc, 0, lookahead: 2);
  }

  /// 开始或恢复播放当前段落
  Future<void> play() async {
    if (_document == null || _document!.chunks.isEmpty) return;

    if (_playbackState == ReaderPlaybackState.paused) {
      await _player.resume();
      _playbackState = ReaderPlaybackState.playing;
      notifyListeners();
      return;
    }

    await _playChunk(_currentChunkIndex);
  }

  /// 暂停播放
  Future<void> pause() async {
    if (_playbackState == ReaderPlaybackState.playing) {
      await _player.pause();
      _playbackState = ReaderPlaybackState.paused;
      notifyListeners();
    }
  }

  /// 停止播放
  Future<void> stop() async {
    await _player.stop();
    _playbackState = ReaderPlaybackState.stopped;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  /// 跳转并播放指定段落
  Future<void> jumpToChunk(int index) async {
    if (_document == null) return;
    if (index < 0 || index >= _document!.chunks.length) return;

    _currentChunkIndex = index;
    await _playChunk(index);
  }

  /// 下一段
  Future<void> nextChunk() async {
    if (_document == null) return;
    if (_currentChunkIndex + 1 < _document!.chunks.length) {
      await jumpToChunk(_currentChunkIndex + 1);
    }
  }

  /// 上一段
  Future<void> previousChunk() async {
    if (_document == null) return;
    if (_currentChunkIndex - 1 >= 0) {
      await jumpToChunk(_currentChunkIndex - 1);
    }
  }

  /// 调节语速 (0.5x ~ 2.5x)
  Future<void> setSpeed(double newSpeed) async {
    _speed = newSpeed.clamp(0.5, 2.5);
    await _player.setPlaybackRate(_speed);
    notifyListeners();
  }

  /// 调节音量 (0.0 ~ 1.0)
  Future<void> setVolume(double newVolume) async {
    _volume = newVolume.clamp(0.0, 1.0);
    await _player.setVolume(_volume);
    notifyListeners();
  }

  /// 内部播放逻辑：合成/读取音频并交给 AudioPlayer
  Future<void> _playChunk(int index) async {
    if (_document == null) return;
    _lastErrorMessage = null;
    _playbackState = ReaderPlaybackState.buffering;
    notifyListeners();

    // 触发超前合成当前段后方的切片
    coordinator.ensureAhead(_document!, index, lookahead: 2);

    final audioPath = await coordinator.ensureChunkSynthesized(_document!, index);

    if (audioPath == null || audioPath.isEmpty) {
      _playbackState = ReaderPlaybackState.stopped;
      if (index >= 0 && index < _document!.chunks.length) {
        final err = _document!.chunks[index].errorMessage;
        _lastErrorMessage = (err != null && err.isNotEmpty) ? err : '段落语音合成失败，请检查网络或 TTS 服务配置';
      } else {
        _lastErrorMessage = '段落语音合成失败，请检查网络或 TTS 服务配置';
      }
      notifyListeners();
      return;
    }

    try {
      await _player.stop();
      await _player.setPlaybackRate(_speed);
      await _player.setVolume(_volume);
      await _player.play(DeviceFileSource(audioPath));
      _playbackState = ReaderPlaybackState.playing;
      notifyListeners();
    } catch (e) {
      _playbackState = ReaderPlaybackState.stopped;
      _lastErrorMessage = '音频播放失败: $e';
      notifyListeners();
    }
  }

  void _onChunkFinished() {
    if (_document == null) return;
    if (_currentChunkIndex + 1 < _document!.chunks.length) {
      _currentChunkIndex++;
      _playChunk(_currentChunkIndex);
    } else {
      // 整篇文档朗读完毕
      _playbackState = ReaderPlaybackState.stopped;
      _currentPosition = Duration.zero;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
