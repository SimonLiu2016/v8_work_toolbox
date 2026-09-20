import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/docx_to_markdown.dart';

/// 构造最小化 DOCX 字节流（ZIP 含 word/document.xml）
Uint8List _buildMinimalDocx(String documentXml) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(documentXml)));
  archive.addFile(ArchiveFile.bytes(
      '[Content_Types].xml',
      utf8.encode('<?xml version="1.0"?>\r\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>')));
  final encoded = ZipEncoder().encode(archive)!;
  return Uint8List.fromList(encoded);
}

void main() {
  group('DocxToMarkdown', () {
    test('纯文本段落提取', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>这是一段纯文本。</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('这是一段纯文本。'));
    });

    test('标题映射为 Markdown 标题', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>文档标题</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>二级标题</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('# 文档标题'));
      expect(md, contains('## 二级标题'));
    });

    test('加粗和斜体保留', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t>加粗</w:t></w:r>
      <w:r><w:rPr><w:i/></w:rPr><w:t>斜体</w:t></w:r>
      <w:r><w:rPr><w:b/><w:i/></w:rPr><w:t>加粗斜体</w:t></w:r>
    </w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('**加粗**'));
      expect(md, contains('*斜体*'));
      expect(md, contains('***加粗斜体***'));
    });

    test('列表项映射为 Markdown 列表', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>第一项</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr><w:r><w:t>第二项</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('- 第一项'));
      expect(md, contains('- 第二项'));
    });

    test('XML 实体解码', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>A &amp; B &lt; C &gt; D</w:t></w:r></w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('A & B < C > D'));
    });

    test('空文档返回空字符串', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body></w:body>
</w:document>
''';
      final bytes = _buildMinimalDocx(xml);
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md.trim(), isEmpty);
    });
  });
}
