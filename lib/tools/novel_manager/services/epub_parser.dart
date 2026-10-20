import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// EPUB 解析出的单章结构
class ParsedChapterItem {
  final int index;
  final String title;
  final String content;

  const ParsedChapterItem({
    required this.index,
    required this.title,
    required this.content,
  });
}

/// EPUB 整体解析成果
class ParsedEpubBook {
  final String title;
  final String author;
  final String description;
  final List<String> tags;
  final List<ParsedChapterItem> chapters;

  const ParsedEpubBook({
    required this.title,
    required this.author,
    required this.description,
    required this.tags,
    required this.chapters,
  });
}

/// EPUB 电子书解析器
class EpubParser {
  /// 解析本地 EPUB 文件
  static Future<ParsedEpubBook> parseFile(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. 定位 META-INF/container.xml 找到 rootfile (content.opf)
    String opfPath = 'OEBPS/content.opf';
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile != null) {
      try {
        final xmlDoc = XmlDocument.parse(utf8.decode(containerFile.content as List<int>));
        final rootfile = xmlDoc.findAllElements('rootfile').firstOrNull;
        if (rootfile != null) {
          opfPath = rootfile.getAttribute('full-path') ?? opfPath;
        }
      } catch (_) {}
    }

    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw const FormatException('未找到 EPUB content.opf 描述文件');
    }

    final opfDoc = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));
    final opfBaseDir = p.dirname(opfPath);

    // 2. 提取元数据 (Title, Creator/Author, Description, Subject)
    final metadataEl = opfDoc.findAllElements('metadata').firstOrNull;
    String title = p.basenameWithoutExtension(file.path);
    String author = '佚名';
    String description = '';
    final List<String> tags = [];

    if (metadataEl != null) {
      final t = metadataEl.findElements('dc:title').firstOrNull ?? metadataEl.findElements('title').firstOrNull;
      if (t != null && t.innerText.trim().isNotEmpty) title = t.innerText.trim();

      final a = metadataEl.findElements('dc:creator').firstOrNull ?? metadataEl.findElements('creator').firstOrNull;
      if (a != null && a.innerText.trim().isNotEmpty) author = a.innerText.trim();

      final d = metadataEl.findElements('dc:description').firstOrNull ?? metadataEl.findElements('description').firstOrNull;
      if (d != null) description = d.innerText.trim();

      final subjects = metadataEl.findElements('dc:subject').isNotEmpty
          ? metadataEl.findElements('dc:subject')
          : metadataEl.findElements('subject');
      for (final s in subjects) {
        final text = s.innerText.trim();
        if (text.isNotEmpty && !tags.contains(text)) tags.add(text);
      }
    }

    // 3. 构建 Manifest 字典 (id -> href)
    final manifestMap = <String, String>{};
    final manifestEl = opfDoc.findAllElements('manifest').firstOrNull;
    if (manifestEl != null) {
      for (final item in manifestEl.findElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id != null && href != null) {
          manifestMap[id] = href;
        }
      }
    }

    // 4. 解析 Spine 确定章节顺序
    final spineItems = <String>[];
    final spineEl = opfDoc.findAllElements('spine').firstOrNull;
    if (spineEl != null) {
      for (final itemref in spineEl.findElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref != null && manifestMap.containsKey(idref)) {
          spineItems.add(manifestMap[idref]!);
        }
      }
    }

    // 5. 遍历各章节 XHTML/HTML 提取标题与正文
    final List<ParsedChapterItem> chapters = [];
    int chapterIndex = 1;

    for (final relHref in spineItems) {
      // 拼接绝对 zip 路径
      final fullPath = opfBaseDir.isEmpty || opfBaseDir == '.'
          ? relHref
          : p.normalize(p.join(opfBaseDir, relHref));

      final chapterFile = archive.findFile(fullPath);
      if (chapterFile == null) continue;

      try {
        final htmlContent = utf8.decode(chapterFile.content as List<int>);
        final doc = html_parser.parse(htmlContent);

        // 提取章节标题（优先 h1-h3，没有则取 title，最后使用自然序号）
        String chapterTitle = '';
        final hTag = doc.querySelector('h1, h2, h3');
        if (hTag != null && hTag.text.trim().isNotEmpty) {
          chapterTitle = hTag.text.trim();
        } else {
          final tTag = doc.querySelector('title');
          if (tTag != null && tTag.text.trim().isNotEmpty) {
            chapterTitle = tTag.text.trim();
          }
        }
        if (chapterTitle.isEmpty) {
          chapterTitle = '第 $chapterIndex 章';
        }

        // 清洗段落为标准格式
        doc.querySelectorAll('script, style').forEach((e) => e.remove());
        doc.querySelectorAll('br').forEach((e) => e.replaceWith(dom.Text('\n')));
        doc.querySelectorAll('p').forEach((e) => e.append(dom.Text('\n\n')));

        final body = doc.body;
        final rawText = body?.text ?? '';
        final lines = rawText.split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && l != chapterTitle)
            .map((l) => '    $l')
            .join('\n\n');

        if (lines.trim().isNotEmpty) {
          chapters.add(ParsedChapterItem(
            index: chapterIndex++,
            title: chapterTitle,
            content: lines,
          ));
        }
      } catch (_) {}
    }

    return ParsedEpubBook(
      title: title,
      author: author,
      description: description,
      tags: tags,
      chapters: chapters,
    );
  }
}
