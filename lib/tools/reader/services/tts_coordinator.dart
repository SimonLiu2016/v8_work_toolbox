import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/reader_models.dart';
import 'audio_cache_manager.dart';
import 'tts_engine.dart';

/// TTS 合成调度协调器
/// 负责滑动窗口后台预拉取、并发限流与缓存命中检测
class TtsSynthesisCoordinator extends ChangeNotifier {
  final AudioCacheManager cacheManager;
  TtsSynthesisConfig _config;

  TtsSynthesisCoordinator({
    required this.cacheManager,
    TtsSynthesisConfig? config,
  }) : _config = config ?? const TtsSynthesisConfig();

  TtsSynthesisConfig get config => _config;

  void updateConfig(TtsSynthesisConfig newConfig) {
    _config = newConfig;
    notifyListeners();
  }

  /// 正在合成的切片任务集合 (避免重复并发合成相同切片)
  final Map<int, Future<String?>> _inFlightTasks = {};
  bool _isDisposed = false;

  /// 针对指定切片执行合成或读取缓存
  Future<String?> ensureChunkSynthesized(
    ReadingDocument document,
    int chunkIndex,
  ) async {
    if (_isDisposed) return null;
    if (chunkIndex < 0 || chunkIndex >= document.chunks.length) return null;

    final chunk = document.chunks[chunkIndex];

    // 1. 本地缓存已存在且物理文件有效
    if (cacheManager.isChunkCached(document.id, chunkIndex)) {
      final path = cacheManager.getChunkFilePath(document.id, chunkIndex);
      chunk.audioCachePath = path;
      chunk.status = ChunkSynthesisStatus.cached;
      return path;
    }

    // 2. 若当前切片已在飞行的异步队列中，复用该 Future
    if (_inFlightTasks.containsKey(chunkIndex)) {
      return _inFlightTasks[chunkIndex];
    }

    // 3. 启动合成任务
    final future = _doSynthesizeChunk(document, chunk);
    _inFlightTasks[chunkIndex] = future;

    try {
      final path = await future;
      return path;
    } finally {
      _inFlightTasks.remove(chunkIndex);
    }
  }

  void _safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  Future<String?> _doSynthesizeChunk(
    ReadingDocument document,
    ReadingChunk chunk,
  ) async {
    if (_isDisposed) return null;
    chunk.status = ChunkSynthesisStatus.synthesizing;
    _safeNotifyListeners();

    try {
      final engine = TtsEngineFactory.createEngine(_config.mode);
      final audioBytes = await engine.synthesize(chunk.text, _config);
      if (_isDisposed) return null;

      final file = await cacheManager.saveChunkAudio(
        document.id,
        chunk.index,
        audioBytes,
      );

      chunk.audioCachePath = file.path;
      chunk.status = ChunkSynthesisStatus.cached;
      chunk.errorMessage = null;
      _safeNotifyListeners();
      return file.path;
    } catch (e) {
      if (_isDisposed) return null;
      chunk.status = ChunkSynthesisStatus.error;
      chunk.errorMessage = e.toString();
      _safeNotifyListeners();
      return null;
    }
  }

  int? _pendingCommercialIndex;
  Future<void>? _sequentialPrefetchWorker;

  /// 滑动窗口超前预合成：确保当前播放段落之后的 N 段提前在后台合成
  void ensureAhead(ReadingDocument document, int currentIndex, {int lookahead = 2}) {
    if (currentIndex >= document.chunks.length) return;

    if (_config.mode == TtsMode.customAi) {
      // 商用 AI 模式（如小米 MiMo）：严格单任务互斥串行预加载，杜绝并发打爆 429
      _pendingCommercialIndex = currentIndex;
      if (_sequentialPrefetchWorker != null) {
        return;
      }
      _sequentialPrefetchWorker = () async {
        try {
          while (!_isDisposed && _pendingCommercialIndex != null) {
            final target = _pendingCommercialIndex!;
            _pendingCommercialIndex = null;
            if (_isDisposed) break;
            if (target < document.chunks.length) {
              if (!cacheManager.isChunkCached(document.id, target) && !_inFlightTasks.containsKey(target)) {
                await ensureChunkSynthesized(document, target);
              }
            }
          }
        } finally {
          _sequentialPrefetchWorker = null;
        }
      }();
      return;
    }

    // Edge-TTS 与 macOS 原生模式：支持并发滑动窗口预合成
    for (int i = currentIndex; i <= currentIndex + lookahead; i++) {
      if (i < document.chunks.length) {
        if (!cacheManager.isChunkCached(document.id, i) && !_inFlightTasks.containsKey(i)) {
          ensureChunkSynthesized(document, i);
        }
      }
    }
  }

  /// 后台批量全篇预合成
  Future<void> prefetchAll(
    ReadingDocument document, {
    void Function(int completed, int total)? onProgress,
  }) async {
    int total = document.chunks.length;
    int completed = 0;

    for (int i = 0; i < total; i++) {
      if (_isDisposed) break;
      await ensureChunkSynthesized(document, i);
      completed++;
      onProgress?.call(completed, total);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _inFlightTasks.clear();
    super.dispose();
  }
}
