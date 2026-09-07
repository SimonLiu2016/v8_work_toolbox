import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 隐私空间私密媒体与数据存储管理器
class PrivateStorageManager {
  PrivateStorageManager._();
  static final PrivateStorageManager instance = PrivateStorageManager._();

  Directory? _rootDir;
  Directory get rootDir => _rootDir!;

  Directory get downloadsDir => Directory(p.join(rootDir.path, 'downloads'));
  Directory get subtitlesDir => Directory(p.join(rootDir.path, 'subtitles'));
  Directory get tempAudioDir => Directory(p.join(rootDir.path, 'temp_audio'));

  File get _historyFile => File(p.join(rootDir.path, 'history.json'));
  File get _favoritesFile => File(p.join(rootDir.path, 'favorites.json'));

  /// 初始化并创建私密存储目录树
  Future<void> init({Directory? customRoot}) async {
    if (customRoot != null) {
      _rootDir = customRoot;
    } else {
      final home = Platform.environment['HOME'];
      if (Platform.isMacOS && home != null && home.isNotEmpty) {
        _rootDir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox', 'PrivateMedia'));
      } else {
        final appSupport = await getApplicationSupportDirectory();
        _rootDir = Directory(p.join(appSupport.path, 'V8WorkToolbox', 'PrivateMedia'));
      }
    }

    if (!_rootDir!.existsSync()) {
      _rootDir!.createSync(recursive: true);
    }
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    if (!subtitlesDir.existsSync()) {
      subtitlesDir.createSync(recursive: true);
    }
    if (!tempAudioDir.existsSync()) {
      tempAudioDir.createSync(recursive: true);
    }
  }

  /// 在 macOS Finder 中快速打开私密目录或选中特定文件
  Future<void> revealInFinder([FileSystemEntity? target]) async {
    final entity = target ?? rootDir;
    if (!entity.existsSync()) return;

    try {
      if (Platform.isMacOS) {
        if (entity is File) {
          await Process.run('open', ['-R', entity.path]);
        } else {
          await Process.run('open', [entity.path]);
        }
      }
    } catch (e) {
      debugPrint('打开 Finder 失败: $e');
    }
  }

  /// 读取播放历史记录
  Future<List<Map<String, dynamic>>> loadHistory() async {
    try {
      if (!_historyFile.existsSync()) return [];
      final content = await _historyFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('读取播放历史失败: $e');
    }
    return [];
  }

  /// 保存播放历史记录
  Future<void> saveHistory(List<Map<String, dynamic>> items) async {
    try {
      await _historyFile.writeAsString(jsonEncode(items), flush: true);
    } catch (e) {
      debugPrint('保存播放历史失败: $e');
    }
  }

  /// 读取收藏夹列表
  Future<List<Map<String, dynamic>>> loadFavorites() async {
    try {
      if (!_favoritesFile.existsSync()) return [];
      final content = await _favoritesFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('读取收藏夹失败: $e');
    }
    return [];
  }

  /// 保存收藏夹列表
  Future<void> saveFavorites(List<Map<String, dynamic>> items) async {
    try {
      await _favoritesFile.writeAsString(jsonEncode(items), flush: true);
    } catch (e) {
      debugPrint('保存收藏夹失败: $e');
    }
  }

  /// 清理旧的临时音频切片
  Future<void> cleanTempAudio() async {
    try {
      if (tempAudioDir.existsSync()) {
        for (final file in tempAudioDir.listSync()) {
          if (file is File) {
            try {
              file.deleteSync();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
  }
}
