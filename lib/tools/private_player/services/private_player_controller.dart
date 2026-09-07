import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'ai_subtitle_service.dart';
import 'media_history_store.dart';

/// 字幕片段模型
class SubtitleSegment {
  final int id;
  final Duration start;
  final Duration end;
  final String text;

  const SubtitleSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
  });

  bool contains(Duration position) => position >= start && position <= end;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'text': text,
  };

  factory SubtitleSegment.fromJson(Map<String, dynamic> json) {
    return SubtitleSegment(
      id: json['id'] as int? ?? 0,
      start: Duration(milliseconds: json['startMs'] as int? ?? 0),
      end: Duration(milliseconds: json['endMs'] as int? ?? 0),
      text: json['text'] as String? ?? '',
    );
  }
}

/// 私密播放器核心控制器（封装 media_kit，驱动音视频渲染、进度同步、历史落盘与实时字幕）
class PrivatePlayerController extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  final List<StreamSubscription> _subscriptions = [];

  bool isPlaying = false;
  bool isBuffering = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  double volume = 100.0;
  double rate = 1.0;

  String? currentSource;
  String currentTitle = '未命名影音';
  String? currentThumbnail;
  bool isFullscreen = false;
  Future<void> Function(bool enter)? onFullscreenRequested;

  // 字幕状态
  final List<SubtitleSegment> _subtitles = [];
  List<SubtitleSegment> get subtitles => List.unmodifiable(_subtitles);
  bool showSubtitles = false; // 默认先关闭字幕，避免遮挡
  String? currentSubtitlePath;
  String currentSubtitleText = '';
  Duration subtitleOffset = Duration.zero;

  // 历史记录落盘节流
  DateTime _lastRecordTime = DateTime.now();

  bool _isInitialized = false;
  bool get isPlayerInitialized => _isInitialized;

  PrivatePlayerController() {
    try {
      player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
        ),
      );
      videoController = VideoController(player);
      _isInitialized = true;
      _listenEvents();
    } catch (e) {
      debugPrint('Player initialization skipped in test runner: $e');
    }
  }

  void _listenEvents() {
    _subscriptions.add(player.stream.playing.listen((val) {
      isPlaying = val;
      notifyListeners();
    }));

    _subscriptions.add(player.stream.buffering.listen((val) {
      isBuffering = val;
      notifyListeners();
    }));

    _subscriptions.add(player.stream.position.listen((pos) {
      position = pos;
      _updateActiveSubtitle();
      _throttledRecordHistory();
      notifyListeners();
    }));

    _subscriptions.add(player.stream.duration.listen((dur) {
      duration = dur;
      notifyListeners();
    }));

    _subscriptions.add(player.stream.volume.listen((vol) {
      volume = vol;
      notifyListeners();
    }));

    _subscriptions.add(player.stream.rate.listen((r) {
      rate = r;
      notifyListeners();
    }));

    _subscriptions.add(player.stream.completed.listen((completed) {
      if (completed) {
        isPlaying = false;
        notifyListeners();
      }
    }));
  }

  /// 打开音视频源（本地文件或在线流地址）
  Future<void> open(
    String urlOrPath, {
    String? title,
    String? thumbnail,
    Duration? startPosition,
    Map<String, String>? httpHeaders,
  }) async {
    currentSource = urlOrPath;
    currentTitle = title ?? (urlOrPath.split('/').lastOrNull ?? '未命名影音');
    currentThumbnail = thumbnail;
    currentSubtitleText = '';

    // 尝试获取上次播放记录以支持断点续播
    final lastPos = startPosition ?? MediaHistoryStore.instance.getLastPosition(urlOrPath);

    final media = Media(
      urlOrPath,
      httpHeaders: httpHeaders,
    );

    if (_isInitialized) {
      await player.open(media, play: true);

      if (lastPos != null && lastPos > const Duration(seconds: 2)) {
        await player.seek(lastPos);
      }
    }

    // 检查是否有历史记录中保存的关联字幕文件
    final record = MediaHistoryStore.instance.findRecord(urlOrPath);
    if (record?.subtitlePath != null && File(record!.subtitlePath!).existsSync()) {
      try {
        await mountSubtitleFile(record.subtitlePath!, autoEnable: false);
      } catch (e) {
        debugPrint('自动挂载历史字幕失败: $e');
      }
    }

    notifyListeners();
  }

  /// 挂载外部字幕文件 (.srt / .vtt)
  Future<int> mountSubtitleFile(String filePath, {bool autoEnable = true}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('字幕文件不存在: $filePath');
    }

    final raw = await file.readAsString();
    final parsed = AiSubtitleService.parseSrtOrVtt(raw);
    if (parsed.isEmpty) {
      throw Exception('未能解析出有效字幕时间轴');
    }

    setSubtitles(parsed);
    currentSubtitlePath = filePath;
    showSubtitles = autoEnable;
    _updateActiveSubtitle();

    if (currentSource != null) {
      await MediaHistoryStore.instance.updateSubtitlePath(
        urlOrPath: currentSource!,
        subtitlePath: filePath,
      );
    }

    notifyListeners();
    return parsed.length;
  }

  Future<void> play() async {
    if (_isInitialized) await player.play();
  }
  Future<void> pause() async {
    if (_isInitialized) await player.pause();
  }
  Future<void> playOrPause() async {
    if (_isInitialized) await player.playOrPause();
  }
  Future<void> seek(Duration pos) async {
    if (_isInitialized) await player.seek(pos);
  }
  Future<void> setRate(double newRate) async {
    if (_isInitialized) await player.setRate(newRate);
  }
  Future<void> setVolume(double newVolume) async {
    if (_isInitialized) await player.setVolume(newVolume);
  }
  Future<void> stop() async {
    if (_isInitialized) await player.stop();
  }

  /// 设置加载外部/生成的字幕列表
  void setSubtitles(List<SubtitleSegment> items) {
    _subtitles.clear();
    _subtitles.addAll(items);
    _updateActiveSubtitle();
    notifyListeners();
  }

  /// 清空字幕
  void clearSubtitles() {
    _subtitles.clear();
    currentSubtitleText = '';
    notifyListeners();
  }

  /// 切换字幕显示开关
  void toggleSubtitles([bool? force]) {
    showSubtitles = force ?? !showSubtitles;
    _updateActiveSubtitle();
    notifyListeners();
  }

  /// 设置全屏状态
  void setFullscreen(bool value) {
    if (isFullscreen == value) return;
    isFullscreen = value;
    notifyListeners();
  }

  /// 切换全屏状态
  Future<void> toggleFullscreen([bool? force]) async {
    final target = force ?? !isFullscreen;
    if (onFullscreenRequested != null) {
      await onFullscreenRequested!(target);
    } else {
      setFullscreen(target);
    }
  }

  /// 微调字幕时间偏移
  void adjustSubtitleOffset(Duration delta) {
    subtitleOffset += delta;
    _updateActiveSubtitle();
    notifyListeners();
  }

  void _updateActiveSubtitle() {
    if (!showSubtitles || _subtitles.isEmpty) {
      if (currentSubtitleText.isNotEmpty) {
        currentSubtitleText = '';
      }
      return;
    }

    final adjustedPos = position + subtitleOffset;
    String matched = '';
    for (final seg in _subtitles) {
      if (seg.contains(adjustedPos)) {
        matched = seg.text;
        break;
      }
    }

    if (matched != currentSubtitleText) {
      currentSubtitleText = matched;
    }
  }

  void _throttledRecordHistory() {
    if (currentSource == null || duration <= Duration.zero) return;
    final now = DateTime.now();
    if (now.difference(_lastRecordTime).inSeconds >= 5) {
      _lastRecordTime = now;
      MediaHistoryStore.instance.recordPlayback(
        urlOrPath: currentSource!,
        title: currentTitle,
        position: position,
        duration: duration,
        thumbnail: currentThumbnail,
      );
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    if (_isInitialized) {
      player.dispose();
    }
    super.dispose();
  }
}
