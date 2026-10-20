import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/novel_models.dart';
import 'novel_database.dart';
import 'novel_chapter_storage.dart';

/// 统一小说仓储与业务管理服务
class NovelRepository extends ChangeNotifier {
  NovelRepository._();
  static final NovelRepository instance = NovelRepository._();

  final NovelDatabase _db = NovelDatabase.instance;
  final NovelChapterStorage _storage = NovelChapterStorage.instance;
  final Uuid _uuid = const Uuid();

  /// 检索小说列表
  Future<List<NovelMetadata>> getNovels({
    String? query,
    String? genre,
    String? tag,
    String orderBy = 'updated_at DESC',
  }) async {
    return await _db.queryNovels(
      query: query,
      genre: genre,
      tag: tag,
      orderBy: orderBy,
    );
  }

  /// 获取单本小说元数据
  Future<NovelMetadata?> getNovel(String id) async {
    return await _db.getNovelById(id);
  }

  /// 保存或更新小说元数据
  Future<void> saveNovel(NovelMetadata novel) async {
    await _db.insertOrUpdateNovel(novel);
    notifyListeners();
  }

  /// 删除整部小说（数据库元数据 + 本地章节文件与目录）
  Future<void> deleteNovel(String id) async {
    await _storage.deleteNovelDirectory(id);
    await _db.deleteNovel(id);
    notifyListeners();
  }

  /// 获取某小说全部章节索引列表（若数据库索引缺失但本地磁盘有已抓取章节，自动自愈恢复）
  Future<List<NovelChapterIndex>> getChapterIndices(String novelId) async {
    var chapters = await _db.getChapterIndices(novelId);
    if (chapters.isEmpty) {
      final diskIndices = await _storage.getStoredChapterIndices(novelId);
      if (diskIndices.isNotEmpty) {
        // 自愈补齐数据库中的章节索引
        final List<NovelChapterIndex> recovered = [];
        for (final idx in diskIndices) {
          final content = await _storage.readChapter(novelId, idx) ?? '';
          var title = '第 $idx 章';
          if (content.isNotEmpty) {
            final firstLine = content.split('\n').firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
            if (firstLine.trim().isNotEmpty && firstLine.trim().length < 50) {
              title = firstLine.trim();
            }
          }
          recovered.add(NovelChapterIndex(
            id: '$novelId-$idx',
            novelId: novelId,
            chapterIndex: idx,
            title: title,
            wordCount: content.length,
            status: ChapterStatus.synced,
            updatedAt: DateTime.now(),
          ));
        }
        await _db.batchInsertChapterIndices(recovered);
        final novel = await _db.getNovelById(novelId);
        if (novel != null) {
          final totalWords = recovered.fold<int>(0, (sum, c) => sum + c.wordCount);
          await _db.insertOrUpdateNovel(novel.copyWith(
            totalChapters: recovered.length,
            totalWordCount: totalWords,
            updatedAt: DateTime.now(),
          ));
        }
        chapters = recovered;
      }
    }
    return chapters;
  }

  /// 获取单章完整内容（索引 + 正文）
  Future<NovelChapter?> getChapter(String novelId, int chapterIndex) async {
    final idx = await _db.getChapterIndexByNumber(novelId, chapterIndex);
    if (idx == null) return null;
    final content = await _storage.readChapter(novelId, chapterIndex) ?? '';
    return NovelChapter(index: idx, content: content);
  }

  /// 保存或更新单个章节（同时提交数据库索引与原子落盘文件，并自动刷新小说的总字数和章节数）
  Future<void> saveChapter({
    required String novelId,
    required int chapterIndex,
    required String title,
    required String content,
    String? summary,
    String? originChapterUrl,
    ChapterStatus status = ChapterStatus.synced,
  }) async {
    // 1. 原子写入正文文件
    await _storage.writeChapterAtomic(novelId, chapterIndex, content);

    // 2. 写入/更新章节数据库索引
    final chapterId = '$novelId-$chapterIndex';
    final indexItem = NovelChapterIndex(
      id: chapterId,
      novelId: novelId,
      chapterIndex: chapterIndex,
      title: title,
      wordCount: content.length,
      summary: summary,
      originChapterUrl: originChapterUrl,
      status: status,
      updatedAt: DateTime.now(),
    );
    await _db.insertOrUpdateChapterIndex(indexItem);

    // 3. 更新小说元数据的章节总数与字数
    final allChapters = await _db.getChapterIndices(novelId);
    final totalWords = allChapters.fold<int>(0, (sum, c) => sum + c.wordCount);
    final novel = await _db.getNovelById(novelId);
    if (novel != null) {
      final updatedNovel = novel.copyWith(
        totalChapters: allChapters.length,
        totalWordCount: totalWords,
        updatedAt: DateTime.now(),
      );
      await _db.insertOrUpdateNovel(updatedNovel);
    }

    notifyListeners();
  }

  /// 插入新章节（将 targetIndex 及之后的章节自动后移）
  Future<void> insertChapter({
    required String novelId,
    required int targetIndex,
    required String title,
    required String content,
  }) async {
    final existingChapters = await _db.getChapterIndices(novelId);
    // 从后往前搬迁正文文件和更新数据库索引
    for (int i = existingChapters.length - 1; i >= 0; i--) {
      final ch = existingChapters[i];
      if (ch.chapterIndex >= targetIndex) {
        final oldIdx = ch.chapterIndex;
        final newIdx = oldIdx + 1;
        final oldContent = await _storage.readChapter(novelId, oldIdx) ?? '';
        await _storage.writeChapterAtomic(novelId, newIdx, oldContent);
        await _storage.deleteChapter(novelId, oldIdx);

        final updatedIdxItem = NovelChapterIndex(
          id: '$novelId-$newIdx',
          novelId: novelId,
          chapterIndex: newIdx,
          title: ch.title,
          wordCount: ch.wordCount,
          summary: ch.summary,
          originChapterUrl: ch.originChapterUrl,
          status: ch.status,
          updatedAt: DateTime.now(),
        );
        await _db.deleteChapterIndex(novelId, oldIdx);
        await _db.insertOrUpdateChapterIndex(updatedIdxItem);
      }
    }

    // 写入新插入的章节
    await saveChapter(
      novelId: novelId,
      chapterIndex: targetIndex,
      title: title,
      content: content,
      status: ChapterStatus.draft,
    );
  }

  /// 删除单章（并将后续章节前移）
  Future<void> deleteChapter({
    required String novelId,
    required int chapterIndex,
  }) async {
    await _storage.deleteChapter(novelId, chapterIndex);
    await _db.deleteChapterIndex(novelId, chapterIndex);

    final existingChapters = await _db.getChapterIndices(novelId);
    for (final ch in existingChapters) {
      if (ch.chapterIndex > chapterIndex) {
        final oldIdx = ch.chapterIndex;
        final newIdx = oldIdx - 1;
        final content = await _storage.readChapter(novelId, oldIdx) ?? '';
        await _storage.writeChapterAtomic(novelId, newIdx, content);
        await _storage.deleteChapter(novelId, oldIdx);

        final updatedIdxItem = NovelChapterIndex(
          id: '$novelId-$newIdx',
          novelId: novelId,
          chapterIndex: newIdx,
          title: ch.title,
          wordCount: ch.wordCount,
          summary: ch.summary,
          originChapterUrl: ch.originChapterUrl,
          status: ch.status,
          updatedAt: DateTime.now(),
        );
        await _db.deleteChapterIndex(novelId, oldIdx);
        await _db.insertOrUpdateChapterIndex(updatedIdxItem);
      }
    }

    // 更新小说统计
    final reloadedChapters = await _db.getChapterIndices(novelId);
    final totalWords = reloadedChapters.fold<int>(0, (sum, c) => sum + c.wordCount);
    final novel = await _db.getNovelById(novelId);
    if (novel != null) {
      await _db.insertOrUpdateNovel(novel.copyWith(
        totalChapters: reloadedChapters.length,
        totalWordCount: totalWords,
        updatedAt: DateTime.now(),
      ));
    }
    notifyListeners();
  }

  /// 批量创建/初始化新小说（用于采集建书或导入建书）
  Future<NovelMetadata> createNovel({
    String? id,
    required String title,
    required String author,
    String description = '',
    List<String> tags = const [],
    String genre = '',
    String coverUrl = '',
    String sourceUrl = '',
    String sourceSiteId = '',
    NovelStatus status = NovelStatus.ongoing,
  }) async {
    final novelId = id ?? _uuid.v4();
    final novel = NovelMetadata(
      id: novelId,
      title: title,
      author: author,
      description: description,
      tags: tags,
      genre: genre,
      coverUrl: coverUrl,
      sourceUrl: sourceUrl,
      sourceSiteId: sourceSiteId,
      status: status,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.insertOrUpdateNovel(novel);
    notifyListeners();
    return novel;
  }
}
