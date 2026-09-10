import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MarkdownConverter Code Block Embed Tests', () {
    test('converts markdown code fences to enhanced code_block embed', () {
      const md = '''
# 标题

```dart
void main() {
  print("Hello World");
}
```
''';
      final deltaJson = MarkdownConverter.markdownToDelta(md);
      expect(deltaJson, contains('"code_block"'));
      expect(deltaJson, contains('Hello World'));
      expect(deltaJson, contains('"language\\":\\"dart\\"'));

      // 验证反向转换回 Markdown
      final restoredMd = MarkdownConverter.deltaToMarkdown(deltaJson);
      expect(restoredMd, contains('```dart'));
      expect(restoredMd, contains('print("Hello World");'));
      expect(restoredMd, contains('```'));
    });

    test('handles code fence without language as plaintext', () {
      const md = '''
```
echo "simple script"
```
''';
      final deltaJson = MarkdownConverter.markdownToDelta(md);
      expect(deltaJson, contains('"code_block"'));
      expect(deltaJson, contains('simple script'));
      expect(deltaJson, contains('"language\\":\\"plaintext\\"'));
    });
  });

  group('MarkdownConverter Mind Map Embed Tests', () {
    test('converts ```mindmap block into mindmap embed', () {
      final mindmapData = {
        'title': '架构设计',
        'tree': {
          'id': '1',
          'name': '架构设计',
          'children': [
            {'id': '2', 'name': '接入层'},
            {'id': '3', 'name': '服务层'},
          ],
        },
      };
      final md = '```mindmap\n${jsonEncode(mindmapData)}\n```';
      final deltaJson = MarkdownConverter.markdownToDelta(md);

      expect(deltaJson, contains('"mindmap"'));
      expect(deltaJson, contains('架构设计'));
      expect(deltaJson, contains('接入层'));

      // 反向转换
      final restoredMd = MarkdownConverter.deltaToMarkdown(deltaJson);
      expect(restoredMd, contains('```mindmap'));
      expect(restoredMd, contains('服务层'));
    });

    test('auto-detects raw Evernote JSON string as mindmap embed', () {
      final rawEvernoteJson = jsonEncode({
        'id': '1',
        'name': '系统优化',
        'mode': 'mindmap',
        'treeDirection': 'right',
        'children': [
          {'id': '2', 'name': 'Cache'},
          {'id': '3', 'name': '异步并发'},
        ],
      });

      final deltaJson = MarkdownConverter.markdownToDelta(rawEvernoteJson);
      expect(deltaJson, contains('"mindmap"'));
      expect(deltaJson, contains('系统优化'));
      expect(deltaJson, contains('Cache'));
    });
  });
}
