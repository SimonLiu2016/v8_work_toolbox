import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'private_storage_manager.dart';

/// 播放记录与收藏条目模型
class MediaPlayRecord {
  final String id;
  final String title;
  final String urlOrPath;
  final bool isOnline;
  final String? thumbnailUrl;
  final int durationMs;
  final int lastPositionMs;
  final DateTime lastPlayedAt;
  final bool isFavorite;
  final String? subtitlePath;

  const MediaPlayRecord({
    required this.id,
    required this.title,
    required this.urlOrPath,
    required this.isOnline,
    this.thumbnailUrl,
    required this.durationMs,
    required this.lastPositionMs,
    required this.lastPlayedAt,
    this.isFavorite = false,
    this.subtitlePath,
  });

  Duration get duration => Duration(milliseconds: durationMs);
  Duration get lastPosition => Duration(milliseconds: lastPositionMs);

  double get progress => durationMs > 0 ? (lastPositionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  MediaPlayRecord copyWith({
    String? title,
    String? urlOrPath,
    bool? isOnline,
    String? thumbnailUrl,
    int? durationMs,
    int? lastPositionMs,
    DateTime? lastPlayedAt,
    bool? isFavorite,
    String? subtitlePath,
  }) {
    return MediaPlayRecord(
      id: id,
      title: title ?? this.title,
      urlOrPath: urlOrPath ?? this.urlOrPath,
      isOnline: isOnline ?? this.isOnline,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationMs: durationMs ?? this.durationMs,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      subtitlePath: subtitlePath ?? this.subtitlePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'urlOrPath': urlOrPath,
    'isOnline': isOnline,
    'thumbnailUrl': thumbnailUrl,
    'durationMs': durationMs,
    'lastPositionMs': lastPositionMs,
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'isFavorite': isFavorite,
    'subtitlePath': subtitlePath,
  };

  factory MediaPlayRecord.fromJson(Map<String, dynamic> json) {
    return MediaPlayRecord(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名影音',
      urlOrPath: json['urlOrPath'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      durationMs: json['durationMs'] as int? ?? 0,
      lastPositionMs: json['lastPositionMs'] as int? ?? 0,
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt'] as String? ?? '') ?? DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
      subtitlePath: json['subtitlePath'] as String?,
    );
  }
}

/// 播放历史与收藏夹统一管理
class MediaHistoryStore extends ChangeNotifier {
  MediaHistoryStore._();
  static final MediaHistoryStore instance = MediaHistoryStore._();

  final List<MediaPlayRecord> _history = [];
  final List<MediaPlayRecord> _favorites = [];

  List<MediaPlayRecord> get history => List.unmodifiable(_history);
  List<MediaPlayRecord> get favorites => List.unmodifiable(_favorites);

  bool _isLoaded = false;

  /// 初始化并加载持久化记录
  Future<void> init() async {
    if (_isLoaded) return;
    await PrivateStorageManager.instance.init();

    final hData = await PrivateStorageManager.instance.loadHistory();
    _history.clear();
    for (final m in hData) {
      _history.add(MediaPlayRecord.fromJson(m));
    }

    final fData = await PrivateStorageManager.instance.loadFavorites();
    _favorites.clear();
    for (final m in fData) {
      _favorites.add(MediaPlayRecord.fromJson(m));
    }

    _isLoaded = true;
    notifyListeners();
  }

  /// 记录或更新播放进度
  Future<void> recordPlayback({
    required String urlOrPath,
    required String title,
    required Duration position,
    required Duration duration,
    String? thumbnail,
    String? subtitlePath,
    bool? isOnline,
  }) async {
    final id = _normalizeId(urlOrPath);
    final fav = isFavorite(urlOrPath);

    final record = MediaPlayRecord(
      id: id,
      title: title,
      urlOrPath: urlOrPath,
      isOnline: isOnline ?? (urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://')),
      thumbnailUrl: thumbnail,
      durationMs: duration.inMilliseconds,
      lastPositionMs: position.inMilliseconds,
      lastPlayedAt: DateTime.now(),
      isFavorite: fav,
      subtitlePath: subtitlePath,
    );

    _history.removeWhere((r) => r.id == id);
    _history.insert(0, record);

    if (_history.length > 100) {
      _history.removeRange(100, _history.length);
    }

    notifyListeners();
    await _saveHistory();
  }

  /// 收藏或取消收藏
  Future<void> toggleFavorite({
    required String urlOrPath,
    required String title,
    Duration? duration,
    String? thumbnail,
    String? subtitlePath,
  }) async {
    final id = _normalizeId(urlOrPath);
    final existingIdx = _favorites.indexWhere((f) => f.id == id);

    if (existingIdx >= 0) {
      _favorites.removeAt(existingIdx);
      // 同时更新历史记录中的收藏标识
      final histIdx = _history.indexWhere((h) => h.id == id);
      if (histIdx >= 0) {
        _history[histIdx] = _history[histIdx].copyWith(isFavorite: false);
      }
    } else {
      final record = MediaPlayRecord(
        id: id,
        title: title,
        urlOrPath: urlOrPath,
        isOnline: urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://'),
        thumbnailUrl: thumbnail,
        durationMs: duration?.inMilliseconds ?? 0,
        lastPositionMs: 0,
        lastPlayedAt: DateTime.now(),
        isFavorite: true,
        subtitlePath: subtitlePath,
      );
      _favorites.insert(0, record);
      final histIdx = _history.indexWhere((h) => h.id == id);
      if (histIdx >= 0) {
        _history[histIdx] = _history[histIdx].copyWith(isFavorite: true);
      }
    }

    notifyListeners();
    await _saveFavorites();
    await _saveHistory();
  }

  /// 检查是否已收藏
  bool isFavorite(String urlOrPath) {
    final id = _normalizeId(urlOrPath);
    return _favorites.any((f) => f.id == id);
  }

  /// 获取特定路径/URL 的历史记录
  MediaPlayRecord? findRecord(String urlOrPath) {
    final id = _normalizeId(urlOrPath);
    return _history.where((r) => r.id == id).firstOrNull;
  }

  /// 获取特定路径/URL 的上次播放位置
  Duration? getLastPosition(String urlOrPath) {
    final record = findRecord(urlOrPath);
    if (record != null && record.lastPositionMs > 2000) {
      return record.lastPosition;
    }
    return null;
  }

  /// 更新指定记录关联的字幕路径
  Future<void> updateSubtitlePath({
    required String urlOrPath,
    required String subtitlePath,
  }) async {
    final id = _normalizeId(urlOrPath);
    final idx = _history.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      _history[idx] = _history[idx].copyWith(subtitlePath: subtitlePath);
      notifyListeners();
      await _saveHistory();
    }
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _saveHistory();
  }

  /// 删除单个历史记录
  Future<void> removeHistory(String id) async {
    _history.removeWhere((r) => r.id == id);
    notifyListeners();
    await _saveHistory();
  }

  /// 删除单个收藏
  Future<void> removeFavorite(String id) async {
    _favorites.removeWhere((r) => r.id == id);
    final histIdx = _history.indexWhere((h) => h.id == id);
    if (histIdx >= 0) {
      _history[histIdx] = _history[histIdx].copyWith(isFavorite: false);
    }
    notifyListeners();
    await _saveFavorites();
    await _saveHistory();
  }

  String _normalizeId(String str) {
    return base64Url.encode(utf8.encode(str.trim()));
  }

  Future<void> _saveHistory() async {
    await PrivateStorageManager.instance.saveHistory(_history.map((e) => e.toJson()).toList());
  }

  Future<void> _saveFavorites() async {
    await PrivateStorageManager.instance.saveFavorites(_favorites.map((e) => e.toJson()).toList());
  }
}
