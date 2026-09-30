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

/// 1x1 像素的 PNG（最小可用图片字节）
final _pngBytes = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AEBjB1LhwAAAABJRU5ErkJggg=='));

/// 构造含内嵌图片的 DOCX。图片按 [anchors] 指定的段落下标插入
/// `<a:blip r:embed>`，rels 把 rId 映射到 word/media/<name>。
Uint8List _buildDocxWithImages(
  String documentXml, {
  required List<String> mediaNames,
  required Map<String, String> rels,
}) {
  final archive = Archive();
  archive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(documentXml)));
  for (final name in mediaNames) {
    archive.addFile(ArchiveFile.bytes('word/media/$name', _pngBytes));
  }
  final relXml = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8"?>\r\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  rels.forEach((id, target) {
    relXml.write('<Relationship Id="$id" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/$target"/>');
  });
  relXml.write('</Relationships>');
  archive.addFile(
      ArchiveFile.bytes('word/_rels/document.xml.rels', utf8.encode(relXml.toString())));
  archive.addFile(ArchiveFile.bytes(
      '[Content_Types].xml',
      utf8.encode('<?xml version="1.0"?>\r\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>')));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// 图片锚点的最小 DrawingML 包裹——只要 blip 引用对，其余标签可极简。
String _blip(String rId) =>
    '<w:r><w:drawing><wp:inline xmlns:wp="urn:x"><a:graphic xmlns:a="urn:a"><a:blip r:embed="$rId"/></a:graphic></wp:inline></w:drawing></w:r>';

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

  group('DocxToMarkdown 内嵌图片', () {
    test('图片按原文位置插入，而非全部挤到文末', () {
      final xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>第一段正文</w:t></w:r>${_blip('rId1')}</w:p>
    <w:p><w:r><w:t>第二段正文</w:t></w:r></w:p>
    <w:p><w:r><w:t>第三段正文</w:t></w:r>${_blip('rId2')}</w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildDocxWithImages(
        xml,
        mediaNames: ['image1.png', 'image2.png'],
        rels: {'rId1': 'image1.png', 'rId2': 'image2.png'},
      );

      final result = DocxToMarkdown.convertWithImages(bytes);

      // 图片数与源一致
      expect(result.images.length, 2);
      // 顺序即出现顺序
      expect(result.images.map((i) => i.filename), ['image1.png', 'image2.png']);

      // 位置：image1 必须在"第二段正文"之前，image2 必须在其后——
      // 这正是"不挤到文末"的断言。
      final md = result.markdown;
      final i1 = md.indexOf(DocxToMarkdown.imagePlaceholderPrefix);
      final p2 = md.indexOf('第二段正文');
      final i2 = md.lastIndexOf(DocxToMarkdown.imagePlaceholderPrefix);
      expect(i1, greaterThan(-1));
      expect(i1, lessThan(p2), reason: 'image1 应在第二段之前');
      expect(i2, greaterThan(p2), reason: 'image2 应在第二段之后');

      // 字节完整带出
      expect(result.images.first.bytes, isNotEmpty);
      expect(result.images.first.mime, 'image/png');
    });

    test('旧 API 不含图片二进制，但保留占位标记', () {
      final xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>带图段落</w:t></w:r>${_blip('rId1')}</w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildDocxWithImages(
        xml,
        mediaNames: ['a.png'],
        rels: {'rId1': 'a.png'},
      );
      final md = DocxToMarkdown.convertFromBytes(bytes);
      expect(md, contains('{{attachment:local:a.png}}'));
      // 不应出现 base64 或原始字节
      expect(md, isNot(contains('iVBOR')));
    });

    test('rels 缺失的图片计入 unrecoverable，不静默丢弃', () {
      final xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>段落</w:t></w:r>${_blip('rIdMissing')}</w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildDocxWithImages(
        xml,
        mediaNames: ['image1.png'],
        rels: {'rId1': 'image1.png'},
      );
      final result = DocxToMarkdown.convertWithImages(bytes);
      expect(result.images, isEmpty);
      expect(DocxToMarkdown.lastUnrecoverableCount, 1);
    });

    test('同一张图被多次引用只提取一次', () {
      final xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p>${_blip('rId1')}</w:p>
    <w:p><w:r><w:t>中间</w:t></w:r></w:p>
    <w:p>${_blip('rId1')}</w:p>
  </w:body>
</w:document>
''';
      final bytes = _buildDocxWithImages(
        xml,
        mediaNames: ['dup.png'],
        rels: {'rId1': 'dup.png'},
      );
      final result = DocxToMarkdown.convertWithImages(bytes);
      expect(result.images.length, 1);
      // 两处都有占位标记
      expect(
        DocxToMarkdown.imagePlaceholderPrefix.allMatches(result.markdown).length,
        2,
      );
    });

    test('无图片文档的 images 为空（不污染既有路径）', () {
      const xml = '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>纯文本</w:t></w:r></w:p></w:body>
</w:document>
''';
      final result = DocxToMarkdown.convertWithImages(_buildMinimalDocx(xml));
      expect(result.images, isEmpty);
      expect(result.markdown, contains('纯文本'));
      expect(DocxToMarkdown.lastUnrecoverableCount, 0);
    });
  });
}
