import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';

void main() {
  test('AppFlowyCodec parse markdown, serialize JSON, and extract summary', () {
    const md = '''
# 欢迎使用新笔记本

这是使用 **AppFlowy Editor** 的新一代笔记系统。

- [ ] 任务一
- [x] 任务二

| 表头 A | 表头 B |
| --- | --- |
| 单元格 1 | 单元格 2 |
''';

    final doc = AppFlowyCodec.parseToDocument(md);
    expect(doc.root.children.isNotEmpty, isTrue);

    final summary = AppFlowyCodec.documentToSummary(doc);
    expect(summary.contains('欢迎使用新笔记本'), isTrue);

    final json = AppFlowyCodec.documentToJson(doc);
    expect(json.contains('"document"'), isTrue);

    final doc2 = AppFlowyCodec.parseToDocument(json);
    expect(doc2.root.children.length, equals(doc.root.children.length));

    final md2 = AppFlowyCodec.documentToMarkdownString(doc2);
    expect(md2.contains('欢迎使用新笔记本'), isTrue);
  });

  test('AppFlowyCodec parse markdown with images and tables', () {
    const md = '''
# 标题

![测试图片](/path/to/test.png)

```mindmap
{"root":{"text":"核心主题"}}
```
''';

    final doc = AppFlowyCodec.parseToDocument(md);
    expect(doc.root.children.length, equals(3));
    expect(doc.root.children[0].type, equals('heading'));
    expect(doc.root.children[1].type, equals('image'));
    expect(doc.root.children[2].type, equals('mindmap'));
    expect(doc.root.children[2].attributes['data'], contains('核心主题'));

    final exportedMd = AppFlowyCodec.documentToMarkdownString(doc);
    expect(exportedMd, contains('```mindmap'));
    expect(exportedMd, contains('核心主题'));
  });

  test('AppFlowyCodec parses image paths containing spaces (macOS Application Support)', () {
    const spacePathMd = '![image](/Users/simon/Library/Application Support/com.v8en.V8WorkToolbox/notebook_attachments/74fa450f-0b49-4717-9e16-c0e6c406d6c9.png)';
    final doc = AppFlowyCodec.parseToDocument(spacePathMd);
    expect(doc.root.children.isNotEmpty, isTrue);
    expect(doc.root.children.first.type, equals('image'));
    expect(doc.root.children.first.attributes['url'], contains('Application Support'));
  });
}
