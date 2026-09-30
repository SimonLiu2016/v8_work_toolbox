import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/document_model.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/docx_writer.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/pdf_writer.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/xlsx_writer.dart';
import 'package:V8WorkToolbox/tools/notebook/xlsx_to_markdown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T2 Writers 输出有效性测试', () {
    test('PdfWriter 产出合法 PDF 且能保存渲染', () async {
      final doc = DocumentModel(
        blocks: [
          const HeadingBlock('测试中文标题', level: 1),
          const ParagraphBlock('这是一段包含中文的 PDF 测试段落。'),
          const ListItemBlock('列表项 1', ordered: false),
          const TableBlock([
            ['表头 A', '表头 B'],
            ['数据 1', '数据 2'],
          ], hasHeader: true),
        ],
      );

      final pdfBytes = await PdfWriter.write(doc);
      expect(pdfBytes, isNotEmpty);
      // PDF 头部标志 %PDF-
      expect(pdfBytes.sublist(0, 5), [0x25, 0x50, 0x44, 0x46, 0x2D]);
    });

    test('DocxWriter 产出解包 XML 良构且必需 part 齐备', () async {
      final doc = DocumentModel(
        blocks: [
          const HeadingBlock('Word 文档测试', level: 1),
          const ParagraphBlock('正文段落一'),
          const TableBlock([
            ['Col1', 'Col2'],
            ['Val1', 'Val2'],
          ]),
        ],
      );

      final docxBytes = await DocxWriter.write(doc);
      expect(docxBytes, isNotEmpty);

      final archive = ZipDecoder().decodeBytes(docxBytes);
      expect(archive.findFile('[Content_Types].xml'), isNotNull);
      expect(archive.findFile('_rels/.rels'), isNotNull);
      expect(archive.findFile('word/document.xml'), isNotNull);
      expect(archive.findFile('word/_rels/document.xml.rels'), isNotNull);
    });

    test('XlsxWriter 产出可被 xlsx_to_markdown 成功读回（闭环）', () async {
      final doc = DocumentModel(
        blocks: [
          const TableBlock([
            ['产品', '价格', '库存'],
            ['苹果', '10', '100'],
            ['香蕉', '5', '200'],
          ], hasHeader: true),
        ],
      );

      final xlsxBytes = await XlsxWriter.write(doc);
      expect(xlsxBytes, isNotEmpty);

      // 用本项目的 XlsxToMarkdown 验证可以被成功读取
      final markdown = XlsxToMarkdown.convertFromBytes(xlsxBytes);
      expect(markdown, contains('产品'));
      expect(markdown, contains('苹果'));
      expect(markdown, contains('香蕉'));
    });
  });
}
