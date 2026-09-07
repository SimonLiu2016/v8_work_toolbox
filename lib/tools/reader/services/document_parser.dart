import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import '../models/reader_models.dart';

/// 智能段落与标点切片器
class ParagraphChunker {
  /// 单片最小建议字数与最大建议字数 (契合商用 TTS 最佳实践：300~600 字符)
  static const int minChunkChars = 250;
  static const int maxChunkChars = 600;
  static const int hardMaxChars = 1000;

  /// 判断字符是否属于 CJK 字符集（中日韩统一表意文字及符号标点）
  static bool isCjk(int codeUnit) {
    return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
        (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) ||
        (codeUnit >= 0x20000 && codeUnit <= 0x2A6DF) ||
        (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) ||
        (codeUnit >= 0x3000 && codeUnit <= 0x303F) ||
        (codeUnit >= 0xFF00 && codeUnit <= 0xFFEF);
  }

  /// 判断字符是否为拉丁字母或数字
  static bool isLatinOrDigit(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        (codeUnit >= 0x41 && codeUnit <= 0x5A) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7A);
  }

  /// 判断文本行是否以标题、章节编号或列表项符号开头
  static bool isHeadingOrListItem(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return false;
    final listPattern = RegExp(
      r'^(?:(?:\d+|[一二三四五六七八九十百]+)[\.、\)]|\((?:\d+|[一二三四五六七八九十百]+)\)|\[\d+\]|[-*•·]|\#{1,6}\s|【)',
    );
    return listPattern.hasMatch(trimmed);
  }

  /// 第一阶段：消解视觉硬回车软换行 (De-wrapping) 与段落规范化
  static String dewrapText(String fullText) {
    if (fullText.trim().isEmpty) return '';

    // 1. 统一回车换行符
    final normalized = fullText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 2. 双换行及以上视为显式独立段落
    final rawBlocks = normalized.split(RegExp(r'\n\s*\n+'));
    final cleanedBlocks = <String>[];

    for (final rawBlock in rawBlocks) {
      final lines = rawBlock.split('\n');
      final buffer = StringBuffer();

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        if (buffer.isEmpty) {
          buffer.write(line);
          continue;
        }

        // 如果下一行是明确的列表项或小标题，保留换行
        if (isHeadingOrListItem(line)) {
          buffer.write('\n');
          buffer.write(line);
          continue;
        }

        final prevStr = buffer.toString();
        final prevLastCode = prevStr.codeUnitAt(prevStr.length - 1);
        final nextFirstCode = line.codeUnitAt(0);

        // 如果上一行末尾是破折号或软连字符 '-'，直接拼合
        if (prevLastCode == 0x2D) {
          buffer.write(line);
        } else if (isLatinOrDigit(prevLastCode) && isLatinOrDigit(nextFirstCode)) {
          // 拉丁词汇之间保留单空格
          buffer.write(' ');
          buffer.write(line);
        } else if (isCjk(prevLastCode) || isCjk(nextFirstCode)) {
          // CJK 之间或 CJK 与英文之间直接无缝焊接，不插入空格
          buffer.write(line);
        } else {
          // 符号或其他情况保留单个空格
          buffer.write(' ');
          buffer.write(line);
        }
      }

      var blockText = buffer.toString().trim();
      // 清洗目录或排版中的长串填充虚线 (如 .............. 1) 与下划线，避免语音逐字读出数十个点号
      blockText = blockText
          .replaceAll(RegExp(r'[\.·•]{3,}'), ' ')
          .replaceAll(RegExp(r'…{2,}'), ' ')
          .replaceAll(RegExp(r'_{3,}'), ' ')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      if (blockText.isNotEmpty) {
        cleanedBlocks.add(blockText);
      }
    }

    return cleanedBlocks.join('\n\n');
  }

  /// 将规范化文本按照中英文标点断句，保留完整句子及末尾标点
  static List<String> extractSentences(String text) {
    if (text.trim().isEmpty) return [];

    final sentences = <String>[];
    final buffer = StringBuffer();
    final chars = text.runes.toList();

    bool isTerminator(int r, int? nextR) {
      if (r == 0x3002 /* 。 */ ||
          r == 0xFF01 /* ！ */ ||
          r == 0xFF1F /* ？ */ ||
          r == 0xFF1B /* ； */) {
        return true;
      }
      if (r == 0x0A /* \n */) {
        return true;
      }
      if (r == 0x2E /* . */ ||
          r == 0x21 /* ! */ ||
          r == 0x3F /* ? */ ||
          r == 0x3B /* ; */) {
        if (nextR == null ||
            nextR == 0x20 /* space */ ||
            nextR == 0x0A /* \n */ ||
            nextR == 0x22 /* " */ ||
            nextR == 0x27 /* ' */ ||
            nextR == 0x201D /* ” */ ||
            nextR == 0x2019 /* ’ */ ||
            nextR == 0xFF09 /* ） */ ||
            nextR == 0x29 /* ) */) {
          return true;
        }
      }
      return false;
    }

    bool isClosingQuoteOrBracket(int r) {
      return r == 0x201D /* ” */ ||
          r == 0x2019 /* ’ */ ||
          r == 0x0022 /* " */ ||
          r == 0x0027 /* ' */ ||
          r == 0xFF09 /* ） */ ||
          r == 0x0029 /* ) */ ||
          r == 0x300B /* 》 */ ||
          r == 0x3011 /* 】 */;
    }

    int i = 0;
    while (i < chars.length) {
      final r = chars[i];
      buffer.writeCharCode(r);

      final nextR = (i + 1 < chars.length) ? chars[i + 1] : null;
      if (isTerminator(r, nextR)) {
        i++;
        while (i < chars.length && isClosingQuoteOrBracket(chars[i])) {
          buffer.writeCharCode(chars[i]);
          i++;
        }
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) {
          sentences.add(sentence);
        }
        buffer.clear();
        continue;
      }
      i++;
    }

    if (buffer.isNotEmpty) {
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        sentences.add(remaining);
      }
    }

    return sentences;
  }

  /// 针对超长单句（> 600 字）按逗号等二级标点切分
  static List<String> _splitLongSentence(String text, int maxChars) {
    final result = <String>[];
    final subRegex = RegExp(r'[^，,、：:\n]+[，,、：:\n]?');
    final matches = subRegex.allMatches(text);

    final buffer = StringBuffer();
    for (final m in matches) {
      final part = m.group(0) ?? '';
      if (buffer.length + part.length > maxChars && buffer.isNotEmpty) {
        result.add(buffer.toString().trim());
        buffer.clear();
      }
      buffer.write(part);
    }
    if (buffer.isNotEmpty) {
      result.add(buffer.toString().trim());
    }
    if (result.isEmpty && text.isNotEmpty) {
      result.add(text);
    }
    return result;
  }

  /// 将纯文本智能消解软换行并聚合切分为 300~600 字符的意群切片列表
  static List<ReadingChunk> chunkText(
    String fullText, {
    int targetMinChars = minChunkChars,
    int targetMaxChars = maxChunkChars,
  }) {
    if (fullText.trim().isEmpty) return [];

    final dewrapped = dewrapText(fullText);
    if (dewrapped.isEmpty) return [];

    final sentences = extractSentences(dewrapped);
    if (sentences.isEmpty) return [];

    final chunks = <ReadingChunk>[];
    final buffer = StringBuffer();
    int chunkIndex = 0;
    int currentOffset = 0;

    void flushBuffer() {
      final chunkStr = buffer.toString().trim();
      if (chunkStr.isNotEmpty) {
        chunks.add(ReadingChunk(
          index: chunkIndex++,
          text: chunkStr,
          startChar: currentOffset,
          endChar: currentOffset + chunkStr.length,
        ));
        currentOffset += chunkStr.length + 1;
        buffer.clear();
      }
    }

    for (final s in sentences) {
      if (s.isEmpty) continue;

      if (s.length > targetMaxChars) {
        final subs = _splitLongSentence(s, targetMaxChars);
        for (final sub in subs) {
          if (buffer.length + sub.length > targetMaxChars && buffer.length >= targetMinChars) {
            flushBuffer();
          }
          if (buffer.isNotEmpty) {
            final prevCode = buffer.toString().codeUnitAt(buffer.length - 1);
            final nextCode = sub.codeUnitAt(0);
            if (isLatinOrDigit(prevCode) && isLatinOrDigit(nextCode)) {
              buffer.write(' ');
            }
          }
          buffer.write(sub);
        }
        continue;
      }

      if (buffer.length + s.length > targetMaxChars && buffer.length >= targetMinChars) {
        flushBuffer();
      }

      if (buffer.isNotEmpty) {
        final prevCode = buffer.toString().codeUnitAt(buffer.length - 1);
        final nextCode = s.codeUnitAt(0);
        if (isLatinOrDigit(prevCode) && isLatinOrDigit(nextCode)) {
          buffer.write(' ');
        }
      }
      buffer.write(s);
    }

    if (buffer.isNotEmpty) {
      flushBuffer();
    }

    return chunks;
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

    // 在 macOS 上使用 PDFKit 进行原生解析 (通过 JXA 脚本执行原生 Objective-C PDFDocument 运行时)
    if (Platform.isMacOS) {
      try {
        const jxaScript = '''
function run(argv) {
  ObjC.import("PDFKit");
  ObjC.import("Foundation");
  var url = \$.NSURL.fileURLWithPath(argv[0]);
  var doc = \$.PDFDocument.alloc.initWithURL(url);
  return (doc && doc.string) ? doc.string.js : "";
}
''';
        final proc = await Process.run('osascript', ['-l', 'JavaScript', '-e', jxaScript, path]);
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
