import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import '../../../../services/app_paths.dart';

/// 章节正文原子文件系统存储（保证断电/崩溃不损坏文件）
class NovelChapterStorage {
  NovelChapterStorage._();
  static final NovelChapterStorage instance = NovelChapterStorage._();

  /// 获取指定小说章节正文文件
  File chapterFile(String novelId, int chapterIndex) {
    final chaptersDir = AppPaths.novelChaptersDir(novelId);
    return File(p.join(chaptersDir.path, '$chapterIndex.txt'));
  }

  /// 确保小说章节存储目录存在
  Future<Directory> ensureChaptersDir(String novelId) async {
    final dir = AppPaths.novelChaptersDir(novelId);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 原子写入章节正文（先写 .tmp 再 rename）
  Future<void> writeChapterAtomic(String novelId, int chapterIndex, String content) async {
    await ensureChaptersDir(novelId);
    final target = chapterFile(novelId, chapterIndex);
    final tmpFile = File('${target.path}.tmp');

    try {
      await tmpFile.writeAsString(content, flush: true);
      if (await target.exists()) {
        await target.delete();
      }
      await tmpFile.rename(target.path);
    } catch (e) {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      debugPrint('[NovelChapterStorage] writeChapterAtomic error: $e');
      rethrow;
    }
  }

  /// 读取章节正文
  Future<String?> readChapter(String novelId, int chapterIndex) async {
    final file = chapterFile(novelId, chapterIndex);
    if (!await file.exists()) return null;
    return await file.readAsString();
  }

  /// 获取本地磁盘上已有的所有章节编号列表
  Future<List<int>> getStoredChapterIndices(String novelId) async {
    final dir = AppPaths.novelChaptersDir(novelId);
    if (!await dir.exists()) return [];

    final List<int> indices = [];
    final entities = await dir.list().toList();
    for (final entity in entities) {
      if (entity is File && entity.path.endsWith('.txt')) {
        final name = p.basenameWithoutExtension(entity.path);
        final idx = int.tryParse(name);
        if (idx != null) {
          indices.add(idx);
        }
      }
    }
    indices.sort();
    return indices;
  }

  /// 删除单章正文文件
  Future<void> deleteChapter(String novelId, int chapterIndex) async {
    final file = chapterFile(novelId, chapterIndex);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 删除整本小说的文件目录（包含封面和所有章节）
  Future<void> deleteNovelDirectory(String novelId) async {
    final novelDir = AppPaths.novelDir(novelId);
    if (await novelDir.exists()) {
      await novelDir.delete(recursive: true);
    }
  }
}
