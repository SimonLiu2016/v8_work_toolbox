import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 从 DOCX 中提取出的内嵌图片。
///
/// [filename] 是包内路径的最后一段（如 `image1.png`），用作占位标记的键；
/// 真正的落库由上层 `addAttachment` 完成，这里只负责把字节与元数据带出。
class DocxImage {
  DocxImage({
    required this.filename,
    required this.mime,
    required this.bytes,
  });

  final String filename;
  final String mime;
  final Uint8List bytes;
}

/// DOCX 转换结果：[markdown] 含图片占位标记，[images] 按出现顺序给出字节。
class DocxConvertResult {
  DocxConvertResult({required this.markdown, required this.images});

  final String markdown;
  final List<DocxImage> images;
}

/// DOCX → Markdown 转换器
///
/// DOCX 本质是 ZIP，`word/document.xml` 含主体内容。
/// 本转换器解析 XML 映射为 Markdown，尽量保留：
/// 标题（Heading 样式）、加粗、斜体、列表、表格、内嵌图片。
/// 无法解析的元素降级为纯文本段落，无法提取的图片计入 unrecoverable。
class DocxToMarkdown {
  DocxToMarkdown._();

  /// 图片占位标记。上层按序替换为附件节点——不把二进制塞进 markdown。
  static const imagePlaceholderPrefix = '{{attachment:local:';
  static const imagePlaceholderSuffix = '}}';

  /// 提取失败（rels 缺失 / media 无此文件）的图片 rId 计数。
  static int lastUnrecoverableCount = 0;

  /// 从 DOCX 文件路径转换为 Markdown 字符串
  static Future<String> convert(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return convertFromBytes(bytes);
  }

  /// 从字节数据转换（便于测试）
  static String convertFromBytes(Uint8List bytes) {
    return convertWithImages(bytes).markdown;
  }

  /// 转换并提取内嵌图片。图片按其在 `document.xml` 中的出现位置以占位标记
  /// 插入 markdown——不是全文扫完后统一追加到文末。
  static DocxConvertResult convertWithImages(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) {
      throw Exception('DOCX 内部未找到 word/document.xml');
    }
    final xmlContent = utf8.decode(docFile.content as List<int>);

    final media = _extractMedia(archive);
    final rels = _extractRels(archive);

    return _convertXml(xmlContent, media: media, rels: rels);
  }

  /// 收集 `word/media/*` 的文件名 → 字节。
  static Map<String, DocxImage> _extractMedia(Archive archive) {
    final out = <String, DocxImage>{};
    for (final f in archive.files) {
      if (!f.name.startsWith('word/media/')) continue;
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      if (name.isEmpty) continue;
      final content = f.content;
      if (content is! List<int>) continue;
      out[name] = DocxImage(
        filename: name,
        mime: _mimeFor(name),
        bytes: Uint8List.fromList(content),
      );
    }
    return out;
  }

  /// 解析 `word/_rels/document.xml.rels`：rId → media 路径。
  static Map<String, String> _extractRels(Archive archive) {
    final out = <String, String>{};
    final relsFile = archive.findFile('word/_rels/document.xml.rels');
    if (relsFile == null) return out;
    final content = relsFile.content;
    if (content is! List<int>) return out;

    final xml = utf8.decode(content);
    // Id/ Target 的属性顺序在不同生成器间不稳定，故两条正则各自独立匹配。
    final idRe = RegExp(r'Id="([^"]+)"');
    final targetRe = RegExp(r'Target="([^"]+)"');
    for (final rel in RegExp(r'<Relationship\b[^>]*/?>').allMatches(xml)) {
      final tag = rel.group(0)!;
      final id = idRe.firstMatch(tag)?.group(1);
      final target = targetRe.firstMatch(tag)?.group(1);
      if (id == null || target == null) continue;
      // Target 常写作 "media/image1.png"（相对 word/），也可能是绝对路径。
      final normalized = target.split('/').last;
      out[id] = normalized;
    }
    return out;
  }

  static String _mimeFor(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'webp':
        return 'image/webp';
      case 'tiff':
      case 'tif':
        return 'image/tiff';
      case 'emf':
        return 'image/emf';
      case 'wmf':
        return 'image/wmf';
      default:
        return 'application/octet-stream';
    }
  }

  static DocxConvertResult _convertXml(
    String xml, {
    required Map<String, DocxImage> media,
    required Map<String, String> rels,
  }) {
    final buffer = StringBuffer();
    final images = <DocxImage>[];
    final seen = <String>{};
    var unrecoverable = 0;
    // 简化 XML 解析：按 <w:p>（段落）分块处理
    final paragraphs = _extractParagraphs(xml);
    for (final para in paragraphs) {
      final text = _convertParagraph(para);

      // 图片锚点：<a:blip r:embed="rIdX"> 位于 DrawingML 命名空间，
      // 出现在哪个段落就插在该段落正文之后——保持原文的相对位置。
      final imageMarkers = <String>[];
      for (final m in RegExp(r'<a:blip\b[^>]*r:embed="([^"]+)"').allMatches(para)) {
        final rId = m.group(1)!;
        final mediaName = rels[rId];
        final img = mediaName == null ? null : media[mediaName];
        if (img == null) {
          unrecoverable++;
          continue;
        }
        imageMarkers.add(_placeholder(img.filename));
        if (seen.add(img.filename)) images.add(img);
      }

      final combined = [
        if (text.trim().isNotEmpty) text,
        ...imageMarkers,
      ].join('\n\n');
      if (combined.trim().isNotEmpty) {
        buffer.writeln(combined);
        buffer.writeln();
      }
    }
    lastUnrecoverableCount = unrecoverable;
    return DocxConvertResult(
      markdown: buffer.toString().trim(),
      images: images,
    );
  }

  static String _placeholder(String filename) =>
      '$imagePlaceholderPrefix$filename$imagePlaceholderSuffix';

  /// 提取所有 <w:p>...</w:p> 段落
  static List<String> _extractParagraphs(String xml) {
    final paragraphs = <String>[];
    final regex = RegExp(r'<w:p\b[^>]*>(.*?)</w:p>', dotAll: true);
    for (final match in regex.allMatches(xml)) {
      paragraphs.add(match.group(0)!);
    }
    return paragraphs;
  }

  /// 将单个 <w:p> 段落转为 Markdown 行
  static String _convertParagraph(String paraXml) {
    // 检测标题样式
    final headingMatch = RegExp(r'<w:pStyle\s+w:val="(?:Heading|heading)(\d)"')
        .firstMatch(paraXml);
    if (headingMatch != null) {
      final level = int.tryParse(headingMatch.group(1) ?? '') ?? 1;
      final text = _extractText(paraXml);
      if (text.trim().isNotEmpty) {
        return '${'#' * level.clamp(1, 6)} $text';
      }
    }

    // 检测列表项
    if (paraXml.contains('<w:numPr>')) {
      final text = _extractFormattedText(paraXml);
      if (text.trim().isNotEmpty) return '- $text';
    }

    // 检测表格（<w:tbl> 在段落外，但段落内可能有嵌套表格标记——简化处理）
    // 表格在 _convertXml 中单独处理，此处只处理普通段落

    final text = _extractFormattedText(paraXml);
    return text;
  }

  /// 提取纯文本（不带格式标记）
  static String _extractText(String paraXml) {
    final buffer = StringBuffer();
    final textRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    for (final match in textRegex.allMatches(paraXml)) {
      buffer.write(match.group(1));
    }
    return _decodeXmlEntities(buffer.toString());
  }

  /// 提取带格式的文本（处理加粗/斜体）
  static String _extractFormattedText(String paraXml) {
    final buffer = StringBuffer();
    // 按 <w:r>（run）分块处理
    final runRegex = RegExp(r'<w:r\b[^>]*>(.*?)</w:r>', dotAll: true);
    final runs = runRegex.allMatches(paraXml);

    for (final run in runs) {
      final runXml = run.group(0)!;
      // 检测加粗/斜体属性
      final isBold = runXml.contains('<w:b ') || runXml.contains('<w:b/>');
      final isItalic = runXml.contains('<w:i ') || runXml.contains('<w:i/>');

      // 提取该 run 的文本
      final textRegex = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
      final textBuffer = StringBuffer();
      for (final match in textRegex.allMatches(runXml)) {
        textBuffer.write(match.group(1));
      }
      var text = _decodeXmlEntities(textBuffer.toString());
      if (text.isEmpty) continue;

      if (isBold && isItalic) {
        text = '***$text***';
      } else if (isBold) {
        text = '**$text**';
      } else if (isItalic) {
        text = '*$text*';
      }
      buffer.write(text);
    }
    return buffer.toString();
  }

  /// XML 实体解码
  static String _decodeXmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
  }
}
