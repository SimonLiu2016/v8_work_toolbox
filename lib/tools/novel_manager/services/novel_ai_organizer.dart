import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../services/ai_service.dart';
import 'epub_parser.dart';

/// AI 提炼的小说元数据与整理成果
class AiOrganizedNovelResult {
  final String title;
  final String author;
  final String genre;
  final List<String> tags;
  final String description; // 故事背景与简介
  final List<ParsedChapterItem> chapters;

  const AiOrganizedNovelResult({
    required this.title,
    required this.author,
    required this.genre,
    required this.tags,
    required this.description,
    required this.chapters,
  });
}

/// AI 智能分析管道：负责针对长文或无规则文本进行结构断章、拟题及核心元数据补全提炼
class NovelAiOrganizer {
  NovelAiOrganizer._();
  static final NovelAiOrganizer instance = NovelAiOrganizer._();

  /// 提炼小说核心元数据（书名、作者、类型、标签、故事背景）
  Future<Map<String, dynamic>> extractMetadata({
    required String rawSample,
    String? fallbackTitle,
  }) async {
    final prompt = '''
你是一名资深小说编辑与文本分析专家。请根据以下小说文本片段，分析并提取该小说的元数据信息。
请严格输出一个合法的 JSON 对象，不要包含 markdown 标记或任何闲聊废话。

输出 JSON 格式要求：
{
  "title": "书名（若文本中无法识别则返回推断书名或留空）",
  "author": "作者（若无法识别则返回'佚名'）",
  "genre": "主要题材（如：科幻、仙侠、都市、悬疑、历史、奇幻）",
  "tags": ["标签1", "标签2", "标签3"],
  "description": "50~200字的故事背景设定与剧情主线简介"
}

小说样本片段如下：
${rawSample.length > 3500 ? rawSample.substring(0, 3500) : rawSample}
''';

    try {
      final res = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );

      final text = res.text.trim();
      final cleaned = _extractJsonBlock(text);
      final jsonMap = jsonDecode(cleaned) as Map<String, dynamic>;

      return {
        'title': (jsonMap['title'] as String?)?.isNotEmpty == true ? jsonMap['title'] : (fallbackTitle ?? '未命名小说'),
        'author': (jsonMap['author'] as String?)?.isNotEmpty == true ? jsonMap['author'] : '佚名',
        'genre': jsonMap['genre'] as String? ?? '都市',
        'tags': (jsonMap['tags'] as List?)?.map((e) => e.toString()).toList() ?? <String>[],
        'description': jsonMap['description'] as String? ?? '',
      };
    } catch (e) {
      debugPrint('[NovelAiOrganizer] extractMetadata failed: $e');
      return {
        'title': fallbackTitle ?? '未命名小说',
        'author': '佚名',
        'genre': '通用',
        'tags': <String>['未分类'],
        'description': '',
      };
    }
  }

  /// 当长文本完全没有章节标记时，使用 AI 智能滑窗识别或按字数建议断章拟定标题
  Future<List<ParsedChapterItem>> splitUnstructuredTextIntoChapters({
    required String fullText,
    int targetWordsPerChapter = 3000,
  }) async {
    final List<ParsedChapterItem> results = [];
    final totalLen = fullText.length;

    if (totalLen <= targetWordsPerChapter * 1.5) {
      // 较短文本直接作为第 1 章
      final title = await generateChapterTitle(fullText.substring(0, totalLen > 1000 ? 1000 : totalLen), 1);
      return [
        ParsedChapterItem(index: 1, title: title, content: fullText.trim()),
      ];
    }

    // 按段落分块切分，尽量在段落边界断开
    final paragraphs = fullText.split('\n');
    final StringBuffer currentChapterBuffer = StringBuffer();
    int currentChapterIndex = 1;

    for (final p in paragraphs) {
      final trimmed = p.trim();
      if (trimmed.isEmpty) continue;

      currentChapterBuffer.writeln('    $trimmed\n');

      if (currentChapterBuffer.length >= targetWordsPerChapter) {
        final content = currentChapterBuffer.toString().trim();
        final sample = content.length > 800 ? content.substring(0, 800) : content;
        final title = await generateChapterTitle(sample, currentChapterIndex);

        results.add(ParsedChapterItem(
          index: currentChapterIndex++,
          title: title,
          content: content,
        ));
        currentChapterBuffer.clear();
      }
    }

    if (currentChapterBuffer.isNotEmpty) {
      final content = currentChapterBuffer.toString().trim();
      final sample = content.length > 800 ? content.substring(0, 800) : content;
      final title = await generateChapterTitle(sample, currentChapterIndex);

      results.add(ParsedChapterItem(
        index: currentChapterIndex,
        title: title,
        content: content,
      ));
    }

    return results;
  }

  /// 为一段章节正文拟定简明有戏剧吸引力的章节标题
  Future<String> generateChapterTitle(String sampleText, int chapterIndex) async {
    final prompt = '''
请阅读以下小说片段，为这一个章节拟定一个精炼、吸引人且符合网文习惯的章节名。
格式要求：严格仅输出标题本身（例如：“第$chapterIndex章 风起云涌”），不要包含任何标点符号说明或废话。

片段内容：
$sampleText
''';

    try {
      final res = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      final title = res.text.replaceAll(RegExp(r'["`\n\r]'), '').trim();
      return title.isNotEmpty ? title : '第$chapterIndex章';
    } catch (_) {
      return '第$chapterIndex章';
    }
  }

  String _extractJsonBlock(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      return text.substring(start, end + 1);
    }
    return text;
  }
}
