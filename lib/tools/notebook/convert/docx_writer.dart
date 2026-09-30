import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'document_model.dart';

/// T2 OOXML (DOCX) 写出器——将 [DocumentModel] 转换为 .docx 字节。
///
/// 特性：
/// - 产出符合 OpenXML 规范的最小合法 DOCX 包结构
/// - 支持标题、正文、列表、表格、水平线
/// - 支持将 [DocumentModel.images] 中的图片打包进 `word/media/` 并生成关联关系
class DocxWriter {
  DocxWriter._();

  /// 将 [DocumentModel] 转换为 .docx 文件的原始字节。
  static Future<Uint8List> write(DocumentModel doc) async {
    final archive = Archive();

    // 1. [Content_Types].xml
    final contentTypesXml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\r\n'
        '  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\r\n'
        '  <Default Extension="xml" ContentType="application/xml"/>\r\n'
        '  <Default Extension="png" ContentType="image/png"/>\r\n'
        '  <Default Extension="jpeg" ContentType="image/jpeg"/>\r\n'
        '  <Default Extension="jpg" ContentType="image/jpeg"/>\r\n'
        '  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\r\n'
        '</Types>');
    archive.addFile(ArchiveFile.bytes('[Content_Types].xml', utf8.encode(contentTypesXml.toString())));

    // 2. _rels/.rels
    final rootRelsXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\r\n'
        '  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\r\n'
        '</Relationships>';
    archive.addFile(ArchiveFile.bytes('_rels/.rels', utf8.encode(rootRelsXml)));

    // 3. 处理内嵌图片并构建 word/_rels/document.xml.rels
    final imageRIds = <String, String>{}; // imageKey -> rId
    final docRelsXml = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\r\n');

    var rIdIndex = 1;
    for (final entry in doc.images.entries) {
      final img = entry.value;
      final ext = img.extension;
      final mediaFilename = 'image$rIdIndex.$ext';
      final rId = 'rId${rIdIndex + 1}';
      imageRIds[entry.key] = rId;

      archive.addFile(ArchiveFile.bytes('word/media/$mediaFilename', img.bytes));
      docRelsXml.write('  <Relationship Id="$rId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$mediaFilename"/>\r\n');
      rIdIndex++;
    }
    docRelsXml.write('</Relationships>');
    archive.addFile(ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(docRelsXml.toString())));

    // 4. word/document.xml
    final bodyXml = StringBuffer();
    for (final block in doc.blocks) {
      _writeBlock(block, bodyXml, imageRIds);
    }

    final docXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">\r\n'
        '  <w:body>\r\n'
        '${bodyXml.toString()}'
        '  </w:body>\r\n'
        '</w:document>';
    archive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(docXml)));

    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static void _writeBlock(DocBlock block, StringBuffer buf, Map<String, String> imageRIds) {
    switch (block) {
      case HeadingBlock h:
        final style = switch (h.level) {
          1 => 'Heading1',
          2 => 'Heading2',
          3 => 'Heading3',
          _ => 'Heading4',
        };
        buf.writeln('    <w:p>');
        buf.writeln('      <w:pPr><w:pStyle w:val="$style"/></w:pPr>');
        buf.writeln('      <w:r><w:t>${_escapeXml(h.text)}</w:t></w:r>');
        buf.writeln('    </w:p>');

      case ParagraphBlock p:
        if (p.text.trim().isEmpty) return;
        buf.writeln('    <w:p>');
        buf.writeln('      <w:r><w:t xml:space="preserve">${_escapeXml(p.text)}</w:t></w:r>');
        buf.writeln('    </w:p>');

      case ListItemBlock li:
        buf.writeln('    <w:p>');
        buf.writeln('      <w:r><w:t xml:space="preserve">${li.ordered ? "• " : "- "}${_escapeXml(li.text)}</w:t></w:r>');
        buf.writeln('    </w:p>');

      case CodeBlock c:
        buf.writeln('    <w:p>');
        buf.writeln('      <w:r><w:t xml:space="preserve">${_escapeXml(c.code)}</w:t></w:r>');
        buf.writeln('    </w:p>');

      case HorizontalRuleBlock _:
        buf.writeln('    <w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="auto"/></w:pBdr></w:pPr></w:p>');

      case ImageBlock img:
        final rId = imageRIds[img.imageKey];
        if (rId != null) {
          buf.writeln('    <w:p>');
          buf.writeln('      <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">');
          buf.writeln('        <wp:extent cx="3000000" cy="2000000"/>');
          buf.writeln('        <wp:docPr id="1" name="${_escapeXml(img.imageKey)}"/>');
          buf.writeln('        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">');
          buf.writeln('          <a:blip r:embed="$rId"/>');
          buf.writeln('        </a:graphicData></a:graphic>');
          buf.writeln('      </wp:inline></w:drawing></w:r>');
          buf.writeln('    </w:p>');
        }

      case TableBlock t:
        if (t.rows.isEmpty) return;
        buf.writeln('    <w:tbl>');
        buf.writeln('      <w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>');
        for (final row in t.rows) {
          buf.writeln('      <w:tr>');
          for (final cell in row) {
            buf.writeln('        <w:tc><w:p><w:r><w:t>${_escapeXml(cell)}</w:t></w:r></w:p></w:tc>');
          }
          buf.writeln('      </w:tr>');
        }
        buf.writeln('    </w:tbl>');

      case BlankBlock _:
        buf.writeln('    <w:p/>');
    }
  }

  static String _escapeXml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
