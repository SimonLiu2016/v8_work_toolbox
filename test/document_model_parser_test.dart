import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/document_model.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/parsers/csv_parser.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/parsers/md_parser.dart';
import 'package:V8WorkToolbox/tools/notebook/convert/parsers/txt_parser.dart';

void main() {
  group('TxtParser', () {
    test('解析多段文本和空行', () {
      const input = '段落一第一行\n段落一第二行\n\n段落二\n\n\n段落三';
      final doc = TxtParser.parseText(input);

      expect(doc.sourceFormat, 'txt');
      expect(doc.hasText, isTrue);

      final paragraphs = doc.blocks.whereType<ParagraphBlock>().toList();
      expect(paragraphs.length, 3);
      expect(paragraphs[0].text, '段落一第一行\n段落一第二行');
      expect(paragraphs[1].text, '段落二');
      expect(paragraphs[2].text, '段落三');
    });
  });

  group('CsvParser', () {
    test('解析带引号和逗号的 CSV', () {
      const csv = 'Name,Age,"City, State"\nAlice,30,"New York, NY"\nBob,25,"San Francisco, CA"';
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final doc = CsvParser.parse(bytes);

      expect(doc.sourceFormat, 'csv');
      expect(doc.blocks.length, 1);
      expect(doc.blocks.first, isA<TableBlock>());

      final table = doc.blocks.first as TableBlock;
      expect(table.hasHeader, isTrue);
      expect(table.rows.length, 3);
      expect(table.rows[0], ['Name', 'Age', 'City, State']);
      expect(table.rows[1], ['Alice', '30', 'New York, NY']);
      expect(table.rows[2], ['Bob', '25', 'San Francisco, CA']);
    });
  });

  group('MdParser', () {
    test('解析标题、列表、代码块与表格', () {
      const md = '''
# 标题一
这是一段正文。

- 项目 1
- 项目 2

```dart
void main() => print("hello");
```

| 姓名 | 年龄 |
| --- | --- |
| 张三 | 18 |
''';
      final doc = MdParser.parseText(md);

      expect(doc.blocks.any((b) => b is HeadingBlock && b.level == 1 && b.text == '标题一'), isTrue);
      expect(doc.blocks.any((b) => b is ParagraphBlock && b.text == '这是一段正文。'), isTrue);
      expect(doc.blocks.whereType<ListItemBlock>().length, 2);
      expect(doc.blocks.any((b) => b is CodeBlock && b.language == 'dart'), isTrue);
      expect(doc.blocks.any((b) => b is TableBlock && b.rows.length == 2), isTrue);
    });
  });

  group('DocumentModel 文本抽取与翻译替换闭环', () {
    test('extractTexts 提取并 applyTranslations 替换', () {
      final doc = DocumentModel(
        blocks: [
          const HeadingBlock('Chapter 1', level: 1),
          const ParagraphBlock('Hello world.'),
          const ListItemBlock('Item A', ordered: false),
          const CodeBlock('const x = 1;', language: 'js'), // 代码块不送译
          const TableBlock([
            ['Header A', 'Header B'],
            ['Cell 1', 'Cell 2'],
          ]),
        ],
      );

      final texts = doc.extractTexts();
      expect(texts, ['Chapter 1', 'Hello world.', 'Item A', 'Header A', 'Header B', 'Cell 1', 'Cell 2']);

      final translations = [
        '第一章',
        '你好世界。',
        '条目 A',
        '表头甲',
        '表头乙',
        '单元格一',
        '单元格二',
      ];

      final translatedDoc = doc.applyTranslations(translations);
      final newTexts = translatedDoc.extractTexts();
      expect(newTexts, translations);

      // 代码块依然未动
      final codeBlock = translatedDoc.blocks.whereType<CodeBlock>().first;
      expect(codeBlock.code, 'const x = 1;');
    });
  });
}
