import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import '../models/novel_models.dart';
import 'novel_repository.dart';

/// 导出格式枚举
enum NovelExportFormat {
  txt,
  markdown,
  json,
  epub,
}

/// 小说统一格式导出服务
class NovelExportService {
  NovelExportService._();
  static final NovelExportService instance = NovelExportService._();

  final NovelRepository _repo = NovelRepository.instance;

  /// 导出整本或勾选的部分章节
  Future<File> exportNovel({
    required String novelId,
    required List<int> chapterIndices,
    required NovelExportFormat format,
    required Directory targetDir,
    String? customFileName,
  }) async {
    final novel = await _repo.getNovel(novelId);
    if (novel == null) throw StateError('Novel $novelId not found');

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    // 依序抓取选定章节
    final List<NovelChapter> chapters = [];
    final sortedIndices = List<int>.from(chapterIndices)..sort();
    for (final idx in sortedIndices) {
      final ch = await _repo.getChapter(novelId, idx);
      if (ch != null) chapters.add(ch);
    }

    final safeTitle = novel.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final baseName = customFileName ?? safeTitle;

    switch (format) {
      case NovelExportFormat.txt:
        return _exportAsTxt(novel, chapters, targetDir, baseName);
      case NovelExportFormat.markdown:
        return _exportAsMarkdown(novel, chapters, targetDir, baseName);
      case NovelExportFormat.json:
        return _exportAsJson(novel, chapters, targetDir, baseName);
      case NovelExportFormat.epub:
        return _exportAsEpub(novel, chapters, targetDir, baseName);
    }
  }

  Future<File> _exportAsTxt(
    NovelMetadata novel,
    List<NovelChapter> chapters,
    Directory targetDir,
    String baseName,
  ) async {
    final file = File(p.join(targetDir.path, '$baseName.txt'));
    final sb = StringBuffer();
    sb.writeln('《${novel.title}》');
    sb.writeln('作者：${novel.author}');
    if (novel.description.isNotEmpty) {
      sb.writeln('简介：\n${novel.description}');
    }
    sb.writeln('\n====================\n');

    for (final ch in chapters) {
      sb.writeln('${ch.title}\n');
      sb.writeln(ch.content);
      sb.writeln('\n\n');
    }

    await file.writeAsString(sb.toString(), flush: true);
    return file;
  }

  Future<File> _exportAsMarkdown(
    NovelMetadata novel,
    List<NovelChapter> chapters,
    Directory targetDir,
    String baseName,
  ) async {
    final file = File(p.join(targetDir.path, '$baseName.md'));
    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('title: "${novel.title}"');
    sb.writeln('author: "${novel.author}"');
    sb.writeln('genre: "${novel.genre}"');
    sb.writeln('tags: ${jsonEncode(novel.tags)}');
    sb.writeln('---');
    sb.writeln('\n# ${novel.title}\n');
    sb.writeln('> 作者：${novel.author}\n');
    if (novel.description.isNotEmpty) {
      sb.writeln('> **故事背景与简介**：\n> ${novel.description.replaceAll('\n', '\n> ')}\n');
    }

    for (final ch in chapters) {
      sb.writeln('## ${ch.title}\n');
      sb.writeln('${ch.content}\n\n');
    }

    await file.writeAsString(sb.toString(), flush: true);
    return file;
  }

  Future<File> _exportAsJson(
    NovelMetadata novel,
    List<NovelChapter> chapters,
    Directory targetDir,
    String baseName,
  ) async {
    final file = File(p.join(targetDir.path, '$baseName.json'));
    final data = {
      'metadata': novel.toMap(),
      'chapters': chapters.map((c) => {
        'index': c.chapterIndex,
        'title': c.title,
        'word_count': c.wordCount,
        'content': c.content,
      }).toList(),
    };

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
    return file;
  }

  Future<File> _exportAsEpub(
    NovelMetadata novel,
    List<NovelChapter> chapters,
    Directory targetDir,
    String baseName,
  ) async {
    final file = File(p.join(targetDir.path, '$baseName.epub'));
    final archive = Archive();

    // 1. mimetype (必须是第一个)
    final mimetypeData = utf8.encode('application/epub+zip');
    archive.addFile(ArchiveFile('mimetype', mimetypeData.length, mimetypeData));

    // 2. container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    final containerBytes = utf8.encode(containerXml);
    archive.addFile(ArchiveFile('META-INF/container.xml', containerBytes.length, containerBytes));

    // 3. 章节 XHTML 文件
    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();

    manifestItems.writeln('    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');

    for (int i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final filename = 'chapter_${ch.chapterIndex}.xhtml';
      manifestItems.writeln('    <item id="ch${ch.chapterIndex}" href="$filename" media-type="application/xhtml+xml"/>');
      spineItems.writeln('    <itemref idref="ch${ch.chapterIndex}"/>');

      final xhtml = '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>${ch.title}</title>
</head>
<body>
  <h1>${ch.title}</h1>
  ${ch.content.split('\n').where((l) => l.trim().isNotEmpty).map((l) => '<p>${l.trim()}</p>').join('\n  ')}
</body>
</html>''';
      final xhtmlBytes = utf8.encode(xhtml);
      archive.addFile(ArchiveFile('OEBPS/$filename', xhtmlBytes.length, xhtmlBytes));
    }

    // 4. content.opf
    final opf = '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>${novel.title}</dc:title>
    <dc:creator>${novel.author}</dc:creator>
    <dc:language>zh-CN</dc:language>
  </metadata>
  <manifest>
$manifestItems
  </manifest>
  <spine toc="ncx">
$spineItems
  </spine>
</package>''';
    final opfBytes = utf8.encode(opf);
    archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

    // 5. toc.ncx
    final ncx = '''<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="${novel.id}"/></head>
  <docTitle><text>${novel.title}</text></docTitle>
  <navMap>
${chapters.map((c) => '    <navPoint id="nav${c.chapterIndex}" playOrder="${c.chapterIndex}"><navLabel><text>${c.title}</text></navLabel><content src="chapter_${c.chapterIndex}.xhtml"/></navPoint>').join('\n')}
  </navMap>
</ncx>''';
    final ncxBytes = utf8.encode(ncx);
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', ncxBytes.length, ncxBytes));

    final zipData = ZipEncoder().encode(archive);
    await file.writeAsBytes(zipData, flush: true);
    return file;
  }
}
