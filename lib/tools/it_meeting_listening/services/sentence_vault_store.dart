import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../services/app_paths.dart';
import '../models/sentence_vault_models.dart';

/// 长难句复盘本持久化存储（Sentence Vault）。
///
/// 负责保存用户从排练会议、真实会议中收藏的长难句，记录意群结构标签、跟读复盘
/// 次数与掌握状态。文件使用原子写入防止崩溃时损坏。
class SentenceVaultStore extends ChangeNotifier {
  final File _file;
  final Map<String, VaultSentence> _items = {};
  bool _initialized = false;

  SentenceVaultStore([File? file])
      : _file = file ?? AppPaths.itMeetingSentenceVaultFile;

  static SentenceVaultStore? _instance;
  static SentenceVaultStore get instance =>
      _instance ??= SentenceVaultStore();

  @visibleForTesting
  static void setInstanceForTesting(SentenceVaultStore? store) {
    _instance = store;
  }

  bool get isInitialized => _initialized;
  List<VaultSentence> get allSentences =>
      _items.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  int get totalCount => _items.length;
  int get masteredCount => _items.values.where((s) => s.mastered).length;
  int get unmasteredCount => _items.values.where((s) => !s.mastered).length;

  /// 初始化并从磁盘载入
  Future<void> init() async {
    if (_initialized) return;
    try {
      if (await _file.exists()) {
        final content = await _file.readAsString();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is List) {
            _items.clear();
            for (final entry in decoded) {
              if (entry is Map<String, dynamic>) {
                final sentence = VaultSentence.fromJson(entry);
                if (sentence.id.isNotEmpty) {
                  _items[sentence.id] = sentence;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[SentenceVaultStore] 载入异常，自愈为空: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// 检查某轮发言是否已被收藏
  bool isSaved(String clipId, int turnIndex) {
    return _items.values.any(
      (s) => s.clipId == clipId && s.turnIndex == turnIndex,
    );
  }

  /// 查找指定轮次的难句记录
  VaultSentence? find(String clipId, int turnIndex) {
    try {
      return _items.values.firstWhere(
        (s) => s.clipId == clipId && s.turnIndex == turnIndex,
      );
    } catch (_) {
      return null;
    }
  }

  /// 查找或添加
  Future<void> addOrUpdate(VaultSentence sentence) async {
    _items[sentence.id] = sentence;
    await _persist();
    notifyListeners();
  }

  /// 移除条目
  Future<void> remove(String id) async {
    if (_items.remove(id) != null) {
      await _persist();
      notifyListeners();
    }
  }

  /// 切换掌握状态
  Future<void> toggleMastered(String id) async {
    final existing = _items[id];
    if (existing == null) return;
    _items[id] = existing.copyWith(
      mastered: !existing.mastered,
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  /// 增加复述练习计数
  Future<void> incrementReviewCount(String id) async {
    final existing = _items[id];
    if (existing == null) return;
    _items[id] = existing.copyWith(
      reviewCount: existing.reviewCount + 1,
      updatedAt: DateTime.now(),
    );
    await _persist();
    notifyListeners();
  }

  /// 条件筛选
  List<VaultSentence> filter({
    String? query,
    String? tag,
    bool? mastered,
  }) {
    return _items.values.where((item) {
      if (mastered != null && item.mastered != mastered) {
        return false;
      }
      if (tag != null && tag.isNotEmpty && !item.tags.contains(tag)) {
        return false;
      }
      if (query != null && query.trim().isNotEmpty) {
        final q = query.trim().toLowerCase();
        final matchText = item.text.toLowerCase().contains(q);
        final matchSpeaker = item.speaker.toLowerCase().contains(q);
        final matchTitle = item.meetingTitle.toLowerCase().contains(q);
        if (!matchText && !matchSpeaker && !matchTitle) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _persist() async {
    try {
      final parentDir = _file.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
      final list = _items.values.map((s) => s.toJson()).toList();
      final content = const JsonEncoder.withIndent('  ').convert(list);
      final tmpFile = File('${_file.path}.tmp');
      await tmpFile.writeAsString(content);
      if (await _file.exists()) {
        await _file.delete();
      }
      await tmpFile.rename(_file.path);
    } catch (e) {
      debugPrint('[SentenceVaultStore] 持久化失败: $e');
    }
  }
}
