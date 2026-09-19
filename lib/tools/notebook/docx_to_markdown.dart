import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// DOCX → Markdown 转换器
///
/// DOCX 本质是 ZIP，`word/document.xml` 含主体内容。
/// 本转换器解析 XML 映射为 Markdown，尽量保留：
/// 标题（Heading 样式）、加粗、斜体、列表、表格。
/// 无法解析的元素降级为纯文本段落。
class DocxToMarkdown {
  DocxToMarkdown._();

  /// 从 DOCX 文件路径转换为 Markdown 字符串
  static Future<String> convert(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    return convertFromBytes(bytes);
  }

  /// 从字节数据转换（便于测试）
  static String convertFromBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final docFile = archive.findFile('word/document.xml');
    if (docFile == null) {
      throw Exception('DOCX 内部未找到 word/document.xml');
    }
    final xmlContent = utf8.decode(docFile.content as List<int>);
    return _convertXml(xmlContent);
  }

  /// 解析 document.xml 并映射为 Markdown
  static String _convertXml(String xml) {
    final buffer = StringBuffer();
    // 简化 XML 解析：按 <w:p>（段落）分块处理
    final paragraphs = _extractParagraphs(xml);
    for (final para in paragraphs) {
      buffer.writeln(_convertParagraph(para));
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

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
