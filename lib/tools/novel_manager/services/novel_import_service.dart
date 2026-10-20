import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/novel_models.dart';
import 'novel_repository.dart';
import 'epub_parser.dart';
import 'txt_parser.dart';
import 'novel_ai_organizer.dart';

/// 导入结果概要
class NovelImportResult {
  final NovelMetadata novel;
  final int importedChapters;
  final bool usedAiFallback;

  const NovelImportResult({
    required this.novel,
    required this.importedChapters,
    required this.usedAiFallback,
  });
}

/// 编排导入总服务：支持规则优先解析与 AI 智能兜底补齐结合
class NovelImportService {
  NovelImportService._();
  static final NovelImportService instance = NovelImportService._();

  final NovelRepository _repo = NovelRepository.instance;
  final NovelAiOrganizer _aiOrganizer = NovelAiOrganizer.instance;

  /// 导入文件（自动分流 .epub 与 .txt）
  Future<NovelImportResult> importFile(
    File file, {
    bool enableAiFallback = true,
    void Function(String stepMessage)? onProgress,
  }) async {
    final ext = p.extension(file.path).toLowerCase();
    if (ext != '.txt' && ext != '.epub') {
      throw UnsupportedError('当前仅支持导入 .txt 与 .epub 格式的小说');
    }

    onProgress?.call('正在解析文件结构...');

    String title = p.basenameWithoutExtension(file.path);
    String author = '佚名';
    String description = '';
    String genre = '通用';
    List<String> tags = [];
    List<ParsedChapterItem> chapters = [];
    bool usedAiFallback = false;

    if (ext == '.epub') {
      // 1. EPUB 电子书解析
      final epubBook = await EpubParser.parseFile(file);
      title = epubBook.title;
      author = epubBook.author;
      description = epubBook.description;
      tags = epubBook.tags;
      chapters = epubBook.chapters;
    } else {
      // 2. TXT 纯文本规则解析
      final txtBook = await TxtParser.parseFile(file);
      title = txtBook.title;
      author = txtBook.author;
      description = txtBook.description;
      chapters = txtBook.chapters;

      // 如果结构不规则（切分章节数 <= 1 且允许 AI 介入）
      if (!txtBook.isWellStructured && enableAiFallback) {
        onProgress?.call('文本无明显章节标记，正在调用 AI 智能断章与提炼...');
        usedAiFallback = true;

        final rawContent = chapters.firstOrNull?.content ?? '';
        final aiMeta = await _aiOrganizer.extractMetadata(
          rawSample: rawContent,
          fallbackTitle: title,
        );

        title = aiMeta['title'] as String? ?? title;
        author = aiMeta['author'] as String? ?? author;
        genre = aiMeta['genre'] as String? ?? genre;
        tags = (aiMeta['tags'] as List?)?.cast<String>() ?? tags;
        description = aiMeta['description'] as String? ?? description;

        // 使用 AI 切分章节
        chapters = await _aiOrganizer.splitUnstructuredTextIntoChapters(
          fullText: rawContent,
        );
      }
    }

    // 3. 若元数据信息（如故事背景/简介、分类）依然缺失，且开启了 AI 兜底，则调用一次 AI 提取补充
    if (enableAiFallback && (description.trim().isEmpty || tags.isEmpty)) {
      onProgress?.call('正在提炼小说背景描述与标签...');
      final sample = chapters.isNotEmpty ? chapters.first.content : '';
      if (sample.isNotEmpty) {
        final aiMeta = await _aiOrganizer.extractMetadata(rawSample: sample, fallbackTitle: title);
        if (description.trim().isEmpty) description = aiMeta['description'] as String? ?? '';
        if (tags.isEmpty) tags = (aiMeta['tags'] as List?)?.cast<String>() ?? ['推荐'];
        if (genre == '通用') genre = aiMeta['genre'] as String? ?? '都市';
      }
    }

    onProgress?.call('正在创建小说与章节资产...');

    // 4. 创建小说元数据记录
    final novel = await _repo.createNovel(
      title: title,
      author: author,
      description: description,
      genre: genre,
      tags: tags,
      status: NovelStatus.completed,
    );

    // 5. 逐章入库落盘
    int savedCount = 0;
    for (final c in chapters) {
      await _repo.saveChapter(
        novelId: novel.id,
        chapterIndex: c.index,
        title: c.title,
        content: c.content,
        status: ChapterStatus.synced,
      );
      savedCount++;
    }

    onProgress?.call('导入完成！共导入 $savedCount 章');

    return NovelImportResult(
      novel: (await _repo.getNovel(novel.id)) ?? novel,
      importedChapters: savedCount,
      usedAiFallback: usedAiFallback,
    );
  }
}
