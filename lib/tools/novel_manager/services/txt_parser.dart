import 'dart:convert';
import 'dart:io';
import 'package:charset_converter/charset_converter.dart';
import 'package:path/path.dart' as p;
import 'epub_parser.dart';

/// TXT 文本切分与提取结果
class ParsedTxtBook {
  final String title;
  final String author;
  final String description;
  final List<ParsedChapterItem> chapters;
  final bool isWellStructured; // 是否成功按规范正则切分出多章节

  const ParsedTxtBook({
    required this.title,
    required this.author,
    required this.description,
    required this.chapters,
    required this.isWellStructured,
  });
}

/// TXT 纯文本编码探测与规则切分器
class TxtParser {
  /// 经典中文小说章节正则匹配模式
  static final List<RegExp> chapterPatterns = [
    // 模式 1: "第123章 章节名" 或 "第 一百二十三 章 章节名"
    RegExp(r'(?:^|\n)\s*(第\s*[0-9一二三四五六七八九十百千万]+\s*[章回节集部卷])\s*([^\n\r]{0,40})'),
    // 模式 2: "Chapter 1 Chapter Title"
    RegExp(r'(?:^|\n)\s*(Chapter\s*[0-9]+)\s*([^\n\r]{0,40})', caseSensitive: false),
    // 模式 3: "【第1章】" 或 "［第1章］"
    RegExp(r'(?:^|\n)\s*[【\[［(](第\s*[0-9一二三四五六七八九十百千万]+\s*[章回节集部卷])[】\]］)]\s*([^\n\r]{0,40})'),
    // 模式 4: "1、章节名" 或 "001 章节名"
    RegExp(r'(?:^|\n)\s*([0-9]{1,4}[、.\s])\s*([^\n\r]{1,40})'),
  ];

  /// 读取文件并探测编码
  static Future<String> readTextWithEncoding(File file) async {
    final bytes = await file.readAsBytes();
    // 1. 尝试 UTF-8
    try {
      return utf8.decode(bytes);
    } catch (_) {}

    // 2. 尝试 GBK / GB2312
    try {
      return await CharsetConverter.decode('gbk', bytes);
    } catch (_) {}

    // 3. 尝试 UTF-16
    try {
      return await CharsetConverter.decode('utf-16', bytes);
    } catch (_) {}

    // 4. 兜底 Latin1
    return latin1.decode(bytes);
  }

  /// 解析 TXT 小说
  static Future<ParsedTxtBook> parseFile(File file) async {
    final rawText = await readTextWithEncoding(file);
    final fallbackTitle = p.basenameWithoutExtension(file.path);

    // 尝试从前文 1000 字中提取作者与书名（常见格式：《书名》 作者：某某）
    String title = fallbackTitle;
    String author = '佚名';
    String description = '';

    final headerSample = rawText.length > 2000 ? rawText.substring(0, 2000) : rawText;
    final bookTitleMatch = RegExp(r'《([^》]+)》').firstMatch(headerSample);
    if (bookTitleMatch != null) {
      title = bookTitleMatch.group(1)!.trim();
    }

    final authorMatch = RegExp(r'(?:作者|著|文|编者)\s*[:：]\s*([^\s\n\r]+)').firstMatch(headerSample);
    if (authorMatch != null) {
      author = authorMatch.group(1)!.trim();
    }

    final descMatch = RegExp(r'(?:简介|内容简介|文案|背景)\s*[:：]\s*([\s\S]{10,400}?)(?=\n\s*(?:第|[0-9]+[、.]|正文|$))')
        .firstMatch(headerSample);
    if (descMatch != null) {
      description = descMatch.group(1)!.trim();
    }

    // 遍历正则模式匹配章节
    List<ParsedChapterItem> chapters = [];

    for (final pattern in chapterPatterns) {
      final matches = pattern.allMatches(rawText).toList();
      // 如果匹配到的章节数 >= 2，认为这是一个有效的章节切分模板
      if (matches.length >= 2) {
        chapters = _splitByMatches(rawText, matches);
        break;
      }
    }

    final bool isWellStructured = chapters.length >= 2;

    // 如果未能按规则切分，则将整个正文作为单章，标记待 AI 整理
    if (!isWellStructured) {
      chapters = [
        ParsedChapterItem(
          index: 1,
          title: '正文',
          content: rawText.trim(),
        ),
      ];
    }

    return ParsedTxtBook(
      title: title,
      author: author,
      description: description,
      chapters: chapters,
      isWellStructured: isWellStructured,
    );
  }

  static List<ParsedChapterItem> _splitByMatches(String text, List<RegExpMatch> matches) {
    final List<ParsedChapterItem> items = [];
    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final chapterLabel = match.group(1)?.trim() ?? '';
      final chapterSubTitle = match.group(2)?.trim() ?? '';
      final fullTitle = chapterSubTitle.isNotEmpty ? '$chapterLabel $chapterSubTitle' : chapterLabel;

      final startPos = match.end;
      final endPos = (i + 1 < matches.length) ? matches[i + 1].start : text.length;
      final body = text.substring(startPos, endPos).trim();

      // 规范化段落排版
      final formattedBody = body.split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => '    $l')
          .join('\n\n');

      items.add(ParsedChapterItem(
        index: i + 1,
        title: fullTitle,
        content: formattedBody,
      ));
    }
    return items;
  }
}
