import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../document_model.dart';

/// DOCX → DocumentModel 解析器。
///
/// 复用 docx_to_markdown.dart 的 ZIP+XML 逻辑，产出 DocumentModel。
class DocxParser {
  DocxParser._();

  /// 从 DOCX 字节解析为 DocumentModel。
  /// 无法解析的元素降级为空段落，不抛异常。
  static DocumentModel parse(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final docFile = archive.findFile('word/document.xml');
      if (docFile == null) return _empty();

      final xmlContent = utf8.decode(docFile.content as List<int>);
      final media = _extractMedia(archive);
      final rels = _extractRels(archive);
      return _parseXml(xmlContent, media: media, rels: rels);
    } catch (_) {
      return _empty();
    }
  }

  static DocumentModel _empty() =>
      const DocumentModel(blocks: [], sourceFormat: 'docx');

  // ─── media & rels ─────────────────────────────────────────────────────────

  static Map<String, _MediaEntry> _extractMedia(Archive archive) {
    final out = <String, _MediaEntry>{};
    for (final f in archive.files) {
      if (!f.name.startsWith('word/media/')) continue;
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      if (name.isEmpty) continue;
      final content = f.content;
      out[name] = _MediaEntry(
        filename: name,
        mime: _mimeFor(name),
        bytes: Uint8List.fromList(content),
      );
    }
    return out;
  }

  static Map<String, String> _extractRels(Archive archive) {
    final out = <String, String>{};
    final relsFile = archive.findFile('word/_rels/document.xml.rels');
    if (relsFile == null) return out;
    final content = relsFile.content;
    final xml = utf8.decode(content);
    final idRe = RegExp(r'Id="([^"]+)"');
    final targetRe = RegExp(r'Target="([^"]+)"');
    for (final rel in RegExp(r'<Relationship\b[^>]*/?>').allMatches(xml)) {
      final tag = rel.group(0)!;
      final id = idRe.firstMatch(tag)?.group(1);
      final target = targetRe.firstMatch(tag)?.group(1);
      if (id == null || target == null) continue;
      out[id] = target.split('/').last;
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
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  // ─── XML 解析 ─────────────────────────────────────────────────────────────

  static DocumentModel _parseXml(
    String xml, {
    required Map<String, _MediaEntry> media,
    required Map<String, String> rels,
  }) {
    final blocks = <DocBlock>[];
    final images = <String, DocImage>{};

    // 提取表格（<w:tbl>）
    final tableRe = RegExp(r'<w:tbl\b[^>]*>(.*?)</w:tbl>', dotAll: true);
    // 提取段落（<w:p>）
    final paraRe = RegExp(r'<w:p\b[^>]*>(.*?)</w:p>', dotAll: true);

    // 先找所有表格的位置，后续段落解析时跳过表格内部
    final tableMatches = tableRe.allMatches(xml).toList();
    final tableRanges = tableMatches
        .map((m) => (start: m.start, end: m.end))
        .toList();

    // 表格处理
    for (final m in tableMatches) {
      final tblXml = m.group(0)!;
      final rows = _parseTable(tblXml);
      if (rows.isNotEmpty) {
        blocks.add(TableBlock(rows, hasHeader: rows.length > 1));
      }
    }

    // 段落处理（跳过表格内部的段落）
    for (final m in paraRe.allMatches(xml)) {
      // 跳过属于表格内的段落
      bool inTable = false;
      for (final range in tableRanges) {
        if (m.start >= range.start && m.end <= range.end) {
          inTable = true;
          break;
        }
      }
      if (inTable) continue;

      final paraXml = m.group(0)!;
      final block = _parseParagraph(paraXml);
      if (block != null) blocks.add(block);

      // 图片
      for (final img in RegExp(r'<a:blip\b[^>]*r:embed="([^"]+)"')
          .allMatches(paraXml)) {
        final rId = img.group(1)!;
        final mediaName = rels[rId];
        final entry = mediaName == null ? null : media[mediaName];
        if (entry == null) continue;
        final key = entry.filename;
        if (!images.containsKey(key)) {
          images[key] = DocImage(
            key: key,
            bytes: entry.bytes,
            mimeType: entry.mime,
          );
        }
        blocks.add(ImageBlock(key));
      }
    }

    // 如果块全是来自重排序（表格先加），重新按 XML 出现顺序重建
    // 简化：直接按上述顺序（先段落/图片，然后单独处理表格）
    // 实际上按文档顺序处理更合理，但上述实现将表格单独提取，顺序可能错乱。
    // 重做：按文档出现顺序处理（段落+表格交替）
    return _parseXmlOrdered(xml, media: media, rels: rels);
  }

  static DocumentModel _parseXmlOrdered(
    String xml, {
    required Map<String, _MediaEntry> media,
    required Map<String, String> rels,
  }) {
    final blocks = <DocBlock>[];
    final images = <String, DocImage>{};

    // 用状态机按出现顺序处理 <w:tbl> 和 <w:p>
    var pos = 0;
    while (pos < xml.length) {
      // 找下一个 <w:tbl 或 <w:p
      final tblIdx = xml.indexOf('<w:tbl', pos);
      final paraIdx = xml.indexOf('<w:p', pos);

      if (tblIdx == -1 && paraIdx == -1) break;

      if (tblIdx != -1 && (paraIdx == -1 || tblIdx < paraIdx)) {
        // 处理表格
        final end = xml.indexOf('</w:tbl>', tblIdx);
        if (end == -1) break;
        final tblXml = xml.substring(tblIdx, end + '</w:tbl>'.length);
        final rows = _parseTable(tblXml);
        if (rows.isNotEmpty) {
          blocks.add(TableBlock(rows, hasHeader: rows.length > 1));
        }
        pos = end + '</w:tbl>'.length;
      } else {
        // 处理段落
        // 确保段落不在表格内（再次检查，跳过那些会被 tbl 处理的）
        if (tblIdx != -1 && paraIdx > tblIdx) {
          // 跳过表格
          final end = xml.indexOf('</w:tbl>', tblIdx);
          if (end != -1) {
            pos = end + '</w:tbl>'.length;
            continue;
          }
        }

        final end = xml.indexOf('</w:p>', paraIdx);
        if (end == -1) break;
        final paraXml = xml.substring(paraIdx, end + '</w:p>'.length);

        // 处理段落 block
        final block = _parseParagraph(paraXml);
        if (block != null) blocks.add(block);

        // 处理图片
        for (final img in RegExp(r'<a:blip\b[^>]*r:embed="([^"]+)"')
            .allMatches(paraXml)) {
          final rId = img.group(1)!;
          final mediaName = rels[rId];
          final entry = mediaName == null ? null : media[mediaName];
          if (entry == null) continue;
          final key = entry.filename;
          if (!images.containsKey(key)) {
            images[key] = DocImage(
              key: key,
              bytes: entry.bytes,
              mimeType: entry.mime,
            );
          }
          blocks.add(ImageBlock(key));
        }

        pos = end + '</w:p>'.length;
      }
    }

    return DocumentModel(
      blocks: blocks,
      images: images,
      sourceFormat: 'docx',
    );
  }

  static List<List<String>> _parseTable(String tblXml) {
    final rows = <List<String>>[];
    final rowRe = RegExp(r'<w:tr\b[^>]*>(.*?)</w:tr>', dotAll: true);
    final cellRe = RegExp(r'<w:tc\b[^>]*>(.*?)</w:tc>', dotAll: true);
    for (final rowM in rowRe.allMatches(tblXml)) {
      final cells = <String>[];
      for (final cellM in cellRe.allMatches(rowM.group(1)!)) {
        cells.add(_extractText(cellM.group(1)!));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  static DocBlock? _parseParagraph(String paraXml) {
    // 标题样式
    final headingMatch =
        RegExp(r'<w:pStyle\s+w:val="(?:Heading|heading)(\d)"')
            .firstMatch(paraXml);
    if (headingMatch != null) {
      final level = (int.tryParse(headingMatch.group(1) ?? '') ?? 1).clamp(1, 6);
      final text = _extractText(paraXml);
      if (text.trim().isNotEmpty) {
        return HeadingBlock(text, level: level);
      }
      return null;
    }

    // 列表
    if (paraXml.contains('<w:numPr>')) {
      final text = _extractText(paraXml);
      if (text.trim().isNotEmpty) {
        return ListItemBlock(text, ordered: false);
      }
      return null;
    }

    // 普通段落
    final text = _extractText(paraXml);
    if (text.trim().isEmpty) return const BlankBlock();
    return ParagraphBlock(text);
  }

  static String _extractText(String xml) {
    final buffer = StringBuffer();
    final textRe = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
    for (final m in textRe.allMatches(xml)) {
      buffer.write(m.group(1));
    }
    return _decode(buffer.toString());
  }

  static String _decode(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}

class _MediaEntry {
  const _MediaEntry({
    required this.filename,
    required this.mime,
    required this.bytes,
  });

  final String filename;
  final String mime;
  final Uint8List bytes;
}
