import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/document_model.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/flatten.dart';

void main() {
  group('Flatten 导出测试', () {
    test('toMarkdown 正确渲染标题、列表、引用图片与表格', () {
      final doc = DocumentModel(
        blocks: [
          const HeadingBlock('标题一', level: 1),
          const ParagraphBlock('正文段落'),
          const ListItemBlock('有序项', ordered: true),
          const ListItemBlock('无序项', ordered: false),
          const ImageBlock('image1.png', altText: '示例图片'),
          const TableBlock([
            ['Col1', 'Col2'],
            ['Val1', 'Val2'],
          ], hasHeader: true),
        ],
      );

      final md = Flatten.toMarkdown(doc);
      expect(md, contains('# 标题一'));
      expect(md, contains('正文段落'));
      expect(md, contains('1. 有序项'));
      expect(md, contains('- 无序项'));
      expect(md, contains('![示例图片](image1.png)'));
      expect(md, contains('| Col1 | Col2 |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| Val1 | Val2 |'));
    });

    test('toText 纯文本导出跳过图片并保留段落', () {
      final doc = DocumentModel(
        blocks: [
          const HeadingBlock('Main Title', level: 1),
          const ParagraphBlock('First paragraph.'),
          const ImageBlock('skip_me.jpg'),
          const ParagraphBlock('Second paragraph.'),
        ],
      );

      final text = Flatten.toText(doc);
      expect(text, contains('Main Title'));
      expect(text, contains('First paragraph.'));
      expect(text, contains('Second paragraph.'));
      expect(text.contains('skip_me.jpg'), isFalse);
    });

    test('toCsv 只输出第一个表格，非表格文档返回空字符串', () {
      final docWithTable = DocumentModel(
        blocks: [
          const TableBlock([
            ['Name', 'Desc'],
            ['Widget', 'A nice, useful tool'],
          ]),
        ],
      );
      final csv = Flatten.toCsv(docWithTable);
      expect(csv, contains('Name,Desc'));
      expect(csv, contains('Widget,"A nice, useful tool"'));

      final docWithoutTable = DocumentModel(
        blocks: [const ParagraphBlock('No tables here')],
      );
      expect(Flatten.toCsv(docWithoutTable), isEmpty);
    });
  });
}
