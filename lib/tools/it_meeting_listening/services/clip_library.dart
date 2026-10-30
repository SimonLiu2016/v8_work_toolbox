/// 素材库（落盘与查询）。
///
/// 目录布局：
///
/// ```
/// <materials>/
///   index.json            素材索引（场景 → 片段）
///   <clipId>.mp3          片段音频
///   <clipId>.json         片段文稿清单（轮次 / 音色 / 时间戳 / 出处）
/// ```
///
/// 音频与文稿**分离且同目录配对**：文稿清单是精听模式逐句高亮、术语收藏记录
/// 时间点、以及将来导入其它来源（用户自己的会议录音）时共用的数据结构。
///
/// 索引是**全量覆盖**写入的：烘焙一批素材后，索引描述当前素材库的全部片段。
/// 索引缺失或损坏时降级为空列表，而不是崩溃——素材文件仍在磁盘上，用户可
/// 通过"重新生成索引"恢复。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/listening_models.dart';

/// 素材库。
class ClipLibrary {
  /// 索引文件名。
  static const String indexFileName = 'index.json';

  /// 索引结构版本。
  static const int indexVersion = 1;

  final Directory _root;

  ClipLibrary(this._root);

  /// 素材根目录。
  Directory get root => _root;

  /// 索引文件。
  File get indexFile => File(p.join(_root.path, indexFileName));

  /// 片段音频路径。
  File audioFileFor(Clip clip) => File(p.join(_root.path, clip.audioPath));

  /// 片段文稿路径。
  File manifestFileFor(Clip clip) =>
      File(p.join(_root.path, '${clip.id}.json'));

  /// 读取索引。
  ///
  /// 索引缺失/损坏时返回空索引（不抛异常）——素材库为空是一个合法状态。
  Future<ClipIndex> loadIndex() async {
    final file = indexFile;
    if (!await file.exists()) return const ClipIndex();
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const ClipIndex();
      return ClipIndex.fromJson(
          jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      return const ClipIndex();
    }
  }

  /// 写入索引（全量覆盖）。
  Future<void> saveIndex(ClipIndex index) async {
    await _root.create(recursive: true);
    final tmp = File('${indexFile.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(index.toJson()),
      flush: true,
    );
    await tmp.rename(indexFile.path);
  }

  /// 用给定片段列表重建索引。
  Future<void> rebuildIndex(List<Clip> clips) async {
    await saveIndex(ClipIndex(
      version: indexVersion,
      clips: clips,
      generatedAt: DateTime.now(),
    ));
  }

  /// 读取单个片段的文稿清单。
  ///
  /// 清单缺失时回落到索引里的片段数据——索引本身已含轮次信息，清单只是
  /// 同一份数据的独立副本。
  Future<Clip?> loadClipManifest(String clipId) async {
    final file = File(p.join(_root.path, '$clipId.json'));
    if (await file.exists()) {
      try {
        return Clip.fromJson(
            jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        // 落到索引兜底
      }
    }
    final index = await loadIndex();
    return index.byId(clipId);
  }

  /// 列出全部素材目录下的 mp3（用于索引丢失时的重建）。
  Future<List<String>> listAudioFiles() async {
    if (!await _root.exists()) return const [];
    final files = <String>[];
    await for (final entity in _root.list()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.mp3')) {
        files.add(p.basename(entity.path));
      }
    }
    return files;
  }

  /// 清理缓存目录中的临时轮次音频。
  Future<void> clearTurnCache(Directory cacheDir) async {
    if (!await cacheDir.exists()) return;
    await for (final entity in cacheDir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }
}
