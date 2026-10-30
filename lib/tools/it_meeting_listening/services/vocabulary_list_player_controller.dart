/// 词汇列表播放编排（主进程侧）。
///
/// 迷你播放窗是独立 Dart isolate，**播放状态必须在主进程**（design D7）：
/// 词汇磨耳朵的编排因此也住进主进程，由 `ListeningHost` 持有，迷你窗只渲染
/// 状态 + 发指令。
///
/// 为什么独立成类而不是复用 [VocabularyBrowserDialog] 的连播逻辑：
/// 对话框那条连播与滚动静居中、逐词失败标记、`_visibleEntries()` 高度耦合，
/// 且对话框是模态、生命周期与迷你窗不同。这里**严格复刻**对话框已验证的编排
/// （停止 → 合成(磁盘缓存) → 播放 → 等待完成(4s 超时兜底) → 1.5s 停顿缓冲 →
/// 步进下一词，循环可选），保证行为一致。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'pronunciation_audio_backend.dart';
import 'vocabulary_study_store.dart';

/// 词汇列表播放控制器。
///
/// 生命周期由宿主（[ListeningHost]）持有，进程内不释放；词汇播放与片段播放
/// 互斥由宿主负责（一方激活先停另一方）。
class VocabularyListPlayerController extends ChangeNotifier {
  VocabularyListPlayerController({
    required VocabularyStudyStore studyStore,
    required PronunciationAudioBackend backend,
  })  : _studyStore = studyStore,
        _backend = backend;

  final VocabularyStudyStore _studyStore;
  final PronunciationAudioBackend _backend;

  /// 待播词列表（展示形态）。
  List<String> _words = const [];
  int _index = -1;
  bool _looping = false;
  bool _isPlaying = false;
  Timer? _stepTimer;

  /// 单词级发音失败的可见标记（键为 TTS 缓存键），成功播放后清除。
  final Set<String> _failedKeys = {};

  /// 待播词列表（只读）。
  List<String> get words => List.unmodifiable(_words);

  /// 当前下标（-1 表示未开始）。
  int get wordIndex => _index;

  /// 当前词（未开始或为空时为 null）。
  String? get currentWord =>
      (_index >= 0 && _index < _words.length) ? _words[_index] : null;

  /// 词数。
  int get wordCount => _words.length;

  /// 是否正在播放。
  bool get isPlaying => _isPlaying;

  /// 是否循环。
  bool get isLooping => _looping;

  /// 播放失败的词（展示形态，只读）。
  Set<String> get failedWords => Set.unmodifiable(
        _failedKeys.map((k) => _words.where((w) => _keyOf(w) == k).firstOrNull ??
            '').where((w) => w.isNotEmpty),
      );

  String _keyOf(String word) => VocabularyStudyStore.ttsCacheKey(
        VocabularyStudyStore.normalizeSentenceKey(word),
      );

  /// 设定词列表并停止当前播放。
  void setWords(List<String> words) {
    _stepTimer?.cancel();
    _words = List.of(words);
    _index = -1;
    _isPlaying = false;
    _failedKeys.clear();
    notifyListeners();
  }

  /// 开启连续播放。
  ///
  /// [autoplay] 为真时立即开始朗读第一个词；为假只载入待播（暂停态）。
  Future<void> start({bool autoplay = true}) async {
    _stepTimer?.cancel();
    if (_words.isEmpty) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    if (_index < 0 || _index >= _words.length) {
      _index = 0;
    }
    if (!autoplay) {
      _isPlaying = false;
      notifyListeners();
      return;
    }
    await _playAtCurrent();
  }

  /// 播放/暂停切换。
  Future<void> toggle() async {
    if (_words.isEmpty) return;
    if (_isPlaying) {
      await stop();
    } else {
      if (_index < 0) _index = 0;
      await _playAtCurrent();
    }
  }

  /// 上一词（回开头则停；不循环）。
  Future<void> previous() async {
    _stepTimer?.cancel();
    if (_words.isEmpty) return;
    _index = (_index - 1).clamp(0, _words.length - 1);
    await _playAtCurrent();
  }

  /// 下一词（到末尾不循环则停止，循环则回 0）。
  Future<void> next() async {
    _stepTimer?.cancel();
    if (_words.isEmpty) return;
    if (_index + 1 < _words.length) {
      _index++;
      await _playAtCurrent();
    } else if (_looping) {
      _index = 0;
      await _playAtCurrent();
    } else {
      await stop();
    }
  }

  /// 停止播放并清空待播计时。
  Future<void> stop() async {
    _stepTimer?.cancel();
    _isPlaying = false;
    try {
      await _backend.stop();
    } catch (_) {
      // 停止失败不致命：状态已复位。
    }
    notifyListeners();
  }

  /// 设置循环。
  void setLoop(bool value) {
    _looping = value;
    notifyListeners();
  }

  /// 播放当前下标词并编排步进。
  ///
  /// 编排与对话框 `_playWordTtsAndWait` 一致：
  /// 停止 → 合成(磁盘缓存) → 播放 → 等待完成(4s 超时兜底) → 1.5s 缓冲 → 步进。
  Future<void> _playAtCurrent() async {
    if (_index < 0 || _index >= _words.length) return;
    final word = _words[_index];
    final key = _keyOf(word);
    _isPlaying = true;
    notifyListeners();

    try {
      await _backend.stop();

      // 合成阶段：复用 VocabularyStudyStore（同一磁盘缓存，对话框播过的词零合成延迟）。
      final File file;
      try {
        file = await _studyStore.synthesizeOrGetTtsFile(word);
      } catch (e) {
        _failedKeys.add(key);
        _reportFailure('合成', e, word: word);
        if (!_isPlaying) return;
        await _scheduleNext();
        return;
      }

      // 播放阶段：失败仅标记，不中断步进。
      try {
        await _backend.playFile(file.path);
      } catch (e) {
        _failedKeys.add(key);
        _reportFailure('播放', e, word: word);
        if (!_isPlaying) return;
        await _scheduleNext();
        return;
      }

      // 等待播放完成（带 4s 超时兜底——超时视为该词已放完，继续步进而非卡死）。
      final completer = Completer<void>();
      final sub = _backend.onPlayerComplete.listen(
        (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
      );
      try {
        await completer.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () {},
        );
      } finally {
        sub.cancel();
      }

      _failedKeys.remove(key);
      if (!_isPlaying) return;
      await _scheduleNext();
    } finally {
      // 兜底复位：仅在仍在播放且未切换词时保留。
    }
  }

  /// 播放完成后 1.5s 停顿缓冲，再步进下一词。
  Future<void> _scheduleNext() async {
    if (!_isPlaying) return;
    _stepTimer?.cancel();
    _stepTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_isPlaying) return;
      if (_index + 1 < _words.length) {
        _index++;
        unawaited(_playAtCurrent());
      } else if (_looping) {
        _index = 0;
        unawaited(_playAtCurrent());
      } else {
        _isPlaying = false;
        notifyListeners();
      }
    });
  }

  void _reportFailure(String stage, Object error, {String? word}) {
    // 与对话框一致：同时落日志与调试输出，便于复现定位。
    debugPrint('[VocabMini][$stage] 词="$word" ${error.runtimeType}: $error');
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    unawaited(_backend.dispose());
    super.dispose();
  }
}
