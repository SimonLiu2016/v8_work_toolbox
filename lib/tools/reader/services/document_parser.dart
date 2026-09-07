import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../models/reader_models.dart';

/// 智能段落与标点切片器
class ParagraphChunker {
  /// 单片最小建议字数与最大建议字数
  static const int minChunkChars = 60;
  static const int maxChunkChars = 260;

  /// 将纯文本切分为适合 TTS 朗读与高亮对齐的切片列表
  static List<ReadingChunk> chunkText(String fullText) {
    if (fullText.trim().isEmpty) return [];

    final rawParagraphs = fullText.split(RegExp(r'\r?\n\s*\r?\n|\r?\n'));
    final chunks = <ReadingChunk>[];
    int currentOffset = 0;
    int chunkIndex = 0;

    for (var para in rawParagraphs) {
      final trimmed = para.trim();
      if (trimmed.isEmpty) {
        currentOffset += para.length + 1;
        continue;
      }

      // 如果段落较短，直接作为一个独立切片
      if (trimmed.length <= maxChunkChars) {
        chunks.add(ReadingChunk(
          index: chunkIndex++,
          text: trimmed,
          startChar: currentOffset,
          endChar: currentOffset + trimmed.length,
        ));
        currentOffset += para.length + 1;
      } else {
        // 段落较长，按标点符号细切
        final subChunks = _splitByPunctuation(trimmed, maxChunkChars);
        int subOffset = currentOffset;
        for (final sub in subChunks) {
          if (sub.trim().isNotEmpty) {
            chunks.add(ReadingChunk(
              index: chunkIndex++,
              text: sub.trim(),
              startChar: subOffset,
              endChar: subOffset + sub.length,
            ));
          }
          subOffset += sub.length;
        }
        currentOffset += para.length + 1;
      }
    }

    return chunks;
  }

  /// 依据中英文句子标点断句
  static List<String> _splitByPunctuation(String text, int maxChars) {
    final result = <String>[];
    final sentenceReg = RegExp(r'[^。！？；\n\.!\?;]+[。！？；\n\.!\?;]?');
    final matches = sentenceReg.allMatches(text);

    final buffer = StringBuffer();
    for (final match in matches) {
      final sentence = match.group(0) ?? '';
      if (buffer.length + sentence.length > maxChars && buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
      buffer.write(sentence);
    }
    if (buffer.isNotEmpty) {
      result.add(buffer.toString());
    }

    if (result.isEmpty && text.isNotEmpty) {
      result.add(text);
    }
    return result;
  }
}

/// 多格式文档与网络文章解析引擎
class DocumentParser {
  /// 从本地文件解析
  static Future<ReadingDocument> parseFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('文件不存在: $filePath');
    }

    final ext = p.extension(filePath).toLowerCase();
    final fileName = p.basenameWithoutExtension(filePath);

    switch (ext) {
      case '.txt':
        return _parseTxt(file, fileName, filePath);
      case '.md':
      case '.markdown':
        return _parseMarkdown(file, fileName, filePath);
      case '.docx':
        return _parseDocx(file, fileName, filePath);
      case '.pdf':
        return _parsePdf(file, fileName, filePath);
      case '.epub':
        return _parseEpub(file, fileName, filePath);
      default:
        throw Exception('暂不支持的文件格式: $ext (支持格式: .txt, .md, .docx, .pdf, .epub)');
    }
  }

  /// 从网络 URL 解析网页文章
  static Future<ReadingDocument> parseUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw Exception('请输入有效的 HTTP / HTTPS 网页地址');
    }

    final client = http.Client();
    try {
      final response = await client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('网页请求失败 (HTTP ${response.statusCode})');
      }

      final htmlBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      return _extractFromHtml(htmlBody, url);
    } finally {
      client.close();
    }
  }

  /// 1. 解析 TXT 文本
  static Future<ReadingDocument> _parseTxt(File file, String title, String path) async {
    final bytes = await file.readAsBytes();
    String content = '';
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    final chunks = ParagraphChunker.chunkText(content);
    return ReadingDocument(
      id: ReadingDocument.computeDocumentId(path, content),
      title: title,
      source: path,
      sourceType: DocumentSourceType.txt,
      chunks: chunks,
      totalWordCount: content.replaceAll(RegExp(r'\s+'), '').length,
    );
  }

  /// 2. 解析 Markdown 文本（清洗图片、超链接与修饰语法）
  static Future<ReadingDocument> _parseMarkdown(File file, String title, String path) async {
    final raw = await file.readAsString();
    final clean = cleanMarkdownFormatting(raw);
    final chunks = ParagraphChunker.chunkText(clean);

    return ReadingDocument(
      id: ReadingDocument.computeDocumentId(path, clean),
      title: title,
      source: path,
      sourceType: DocumentSourceType.markdown,
      chunks: chunks,
      totalWordCount: clean.replaceAll(RegExp(r'\s+'), '').length,
    );
  }

  /// 3. 解析 Word (.docx)
  static Future<ReadingDocument> _parseDocx(File file, String title, String path) async {
    String extractedText = '';

    // 优先尝试 macOS 原生 textutil 命令行工具 (保真度高，速度极快)
    if (Platform.isMacOS) {
      try {
        final proc = await Process.run('textutil', ['-convert', 'txt', '-stdout', path]);
        if (proc.exitCode == 0 && proc.stdout is String && (proc.stdout as String).trim().isNotEmpty) {
          extractedText = (proc.stdout as String).trim();
        }
      } catch (_) {}
    }

    // 回退方案：通过 archive 解压读取 word/document.xml
    if (extractedText.isEmpty) {
      try {
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final docEntry = archive.firstWhere(
          (e) => e.name == 'word/document.xml',
          orElse: () => throw Exception('docx 内部未找到 document.xml'),
        );

        final xmlStr = utf8.decode(docEntry.content as List<int>);
        final xmlDoc = XmlDocument.parse(xmlStr);
        final paragraphs = <String>[];

        for (final pNode in xmlDoc.findAllElements('w:p')) {
          final pText = pNode.findAllElements('w:t').map((e) => e.innerText).join('');
          if (pText.trim().isNotEmpty) {
            paragraphs.add(pText.trim());
          }
        }
        extractedText = paragraphs.join('\n\n');
      } catch (e) {
        throw Exception('Word 文档解析失败: $e');
      }
    }

    if (extractedText.isEmpty) {
      throw Exception('未能从 Word 文档中抽取到可朗读的正文');
    }

    final chunks = ParagraphChunker.chunkText(extractedText);
    return ReadingDocument(
      id: ReadingDocument.computeDocumentId(path, extractedText),
      title: title,
      source: path,
      sourceType: DocumentSourceType.docx,
      chunks: chunks,
      totalWordCount: extractedText.replaceAll(RegExp(r'\s+'), '').length,
    );
  }

  /// 4. 解析 PDF (.pdf)
  static Future<ReadingDocument> _parsePdf(File file, String title, String path) async {
    String extractedText = '';

    // 在 macOS 上使用 PDFKit 进行原生解析 (支持所有标准 PDF 文本层)
    if (Platform.isMacOS) {
      try {
        final script = '''
import PDFKit
import Foundation

let url = URL(fileURLWithPath: "${path.replaceAll('"', '\\"')}")
if let doc = PDFDocument(url: url) {
    var text = ""
    for i in 0..<doc.pageCount {
        if let page = doc.page(at: i), let pageText = page.string {
            text += pageText + "\\n\\n"
        }
    }
    print(text)
}
''';
        final proc = await Process.run('swift', ['-e', script]);
        if (proc.exitCode == 0 && proc.stdout is String) {
          extractedText = (proc.stdout as String).trim();
        }
      } catch (_) {}
    }

    if (extractedText.isEmpty) {
      throw Exception('未能提取 PDF 文字内容（若为纯扫描图片文档，暂不支持朗读）');
    }

    final chunks = ParagraphChunker.chunkText(extractedText);
    return ReadingDocument(
      id: ReadingDocument.computeDocumentId(path, extractedText),
      title: title,
      source: path,
      sourceType: DocumentSourceType.pdf,
      chunks: chunks,
      totalWordCount: extractedText.replaceAll(RegExp(r'\s+'), '').length,
    );
  }

  /// 5. 解析 EPUB (.epub) 电子书
  static Future<ReadingDocument> _parseEpub(File file, String title, String path) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 找到 container.xml
      final containerEntry = archive.firstWhere(
        (e) => e.name == 'META-INF/container.xml',
        orElse: () => throw Exception('EPUB container.xml 未找到'),
      );
      final containerXml = XmlDocument.parse(utf8.decode(containerEntry.content as List<int>));
      final rootfileNode = containerXml.findAllElements('rootfile').first;
      final opfPath = rootfileNode.getAttribute('full-path') ?? 'content.opf';
      final opfDir = p.dirname(opfPath);

      // 解析 content.opf
      final opfEntry = archive.firstWhere(
        (e) => e.name == opfPath,
        orElse: () => throw Exception('EPUB OPF 未找到: $opfPath'),
      );
      final opfXml = XmlDocument.parse(utf8.decode(opfEntry.content as List<int>));

      // 抽取书名
      var bookTitle = title;
      final titleNodes = opfXml.findAllElements('dc:title');
      if (titleNodes.isNotEmpty && titleNodes.first.innerText.trim().isNotEmpty) {
        bookTitle = titleNodes.first.innerText.trim();
      }

      // 抽取 manifest 项映射
      final manifestMap = <String, String>{};
      for (final item in opfXml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id != null && href != null) {
          manifestMap[id] = href;
        }
      }

      // 抽取 spine 顺序
      final spineItems = <String>[];
      for (final itemref in opfXml.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref != null && manifestMap.containsKey(idref)) {
          final href = manifestMap[idref]!;
          final fullHref = opfDir == '.' || opfDir.isEmpty ? href : p.normalize(p.join(opfDir, href));
          spineItems.add(fullHref);
        }
      }

      // 按 spine 顺序提取正文与章节
      final chapters = <ReadingChapter>[];
      final allChunks = <ReadingChunk>[];
      int currentOffset = 0;
      int chunkIdx = 0;
      int chapterIdx = 1;

      for (final itemPath in spineItems) {
        final entry = archive.firstWhere(
          (e) => p.normalize(e.name) == itemPath || e.name.endsWith(itemPath),
          orElse: () => ArchiveFile('', 0, []),
        );
        if (entry.size == 0) continue;

        final rawHtml = utf8.decode(entry.content as List<int>, allowMalformed: true);
        final cleanText = stripHtmlTags(rawHtml);
        if (cleanText.trim().isEmpty) continue;

        final startChunk = chunkIdx;
        final subChunks = ParagraphChunker.chunkText(cleanText);
        for (final sc in subChunks) {
          allChunks.add(ReadingChunk(
            index: chunkIdx++,
            text: sc.text,
            startChar: currentOffset + sc.startChar,
            endChar: currentOffset + sc.endChar,
          ));
        }
        currentOffset += cleanText.length + 1;

        if (subChunks.isNotEmpty) {
          chapters.add(ReadingChapter(
            id: 'chap_$chapterIdx',
            title: '第 $chapterIdx 节',
            startChunkIndex: startChunk,
            endChunkIndex: chunkIdx - 1,
          ));
          chapterIdx++;
        }
      }

      final fullDocText = allChunks.map((c) => c.text).join('\n\n');
      return ReadingDocument(
        id: ReadingDocument.computeDocumentId(path, fullDocText),
        title: bookTitle,
        source: path,
        sourceType: DocumentSourceType.epub,
        chunks: allChunks,
        chapters: chapters,
        totalWordCount: fullDocText.replaceAll(RegExp(r'\s+'), '').length,
      );
    } catch (e) {
      throw Exception('EPUB 电子书解析失败: $e');
    }
  }

  /// 6. 提取网页文章
  static ReadingDocument _extractFromHtml(String html, String url) {
    // 1. 抽取标题
    var title = '网络文章';
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true).firstMatch(html);
    if (titleMatch != null) {
      title = unescapeHtml(titleMatch.group(1) ?? '').trim();
      // 去除网站后缀 (如 - 掘金, | 36氪)
      title = title.split(RegExp(r'[-_|]')).first.trim();
    }

    // 2. 清理无关标签
    var cleaned = html;
    cleaned = cleaned.replaceAll(RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<style[^>]*>.*?</style>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<nav[^>]*>.*?</nav>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<header[^>]*>.*?</header>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<footer[^>]*>.*?</footer>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<aside[^>]*>.*?</aside>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<svg[^>]*>.*?</svg>', caseSensitive: false, dotAll: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

    // 3. 寻找正文容器 (<article> 或 <main>)
    final articleMatch = RegExp(r'<(article|main)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true).firstMatch(cleaned);
    String bodyHtml = articleMatch != null ? articleMatch.group(2) ?? cleaned : cleaned;

    final bodyText = stripHtmlTags(bodyHtml);
    if (bodyText.trim().isEmpty) {
      throw Exception('未能从该网页提取到有效正文，请尝试直接复制文本');
    }

    final chunks = ParagraphChunker.chunkText(bodyText);
    return ReadingDocument(
      id: ReadingDocument.computeDocumentId(url, bodyText),
      title: title.isEmpty ? url : title,
      source: url,
      sourceType: DocumentSourceType.webUrl,
      chunks: chunks,
      totalWordCount: bodyText.replaceAll(RegExp(r'\s+'), '').length,
    );
  }

  /// 移除 HTML 标签并转换段落换行
  static String stripHtmlTags(String html) {
    var text = html;
    // 段落与换行标签转为真实换行
    text = text.replaceAll(RegExp(r'<(p|br|div|h[1-6]|li)[^>]*>', caseSensitive: false), '\n');
    // 移除所有其它标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
    text = unescapeHtml(text);
    // 规整多余连续空行
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// Markdown 语法清洗
  static String cleanMarkdownFormatting(String md) {
    var text = md;
    // 移除图片引用: ![alt](url)
    text = text.replaceAll(RegExp(r'!\[([^\]]*)\]\([^\)]+\)'), '');
    // 提取链接文本: [text](url) -> text
    text = text.replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), (m) => m.group(1) ?? '');
    // 移除行内代码与代码块标记 ```
    text = text.replaceAll(RegExp(r'```[a-zA-Z]*'), '');
    text = text.replaceAll('`', '');
    // 转换标题 # Title -> Title
    text = text.replaceAllMapped(RegExp(r'^#{1,6}\s+(.+)$', multiLine: true), (m) => '${m.group(1)}\n');
    // 移除粗体/斜体语法
    text = text.replaceAll(RegExp(r'\*\*|__|\*|_'), '');
    // 移除 HTML 标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// 常用 HTML 实体反转义
  static String unescapeHtml(String str) {
    return str
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rsquo;', '’');
  }
}
