import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/note_code_block_component.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Image paths containing spaces decode into native image block without percent escaping', () {
    const md = '![attachment](/Users/simon/Library/Application Support/com.v8en.V8WorkToolbox/attachments/photo.png)';
    final doc = AppFlowyCodec.parseToDocument(md);
    expect(doc.root.children.isNotEmpty, isTrue);
    final imageNode = doc.root.children.first;
    expect(imageNode.type, equals(ImageBlockKeys.type));
    final url = (imageNode.attributes[ImageBlockKeys.url] ?? imageNode.attributes['src'] ?? imageNode.attributes['url']).toString();
    expect(url, equals('/Users/simon/Library/Application Support/com.v8en.V8WorkToolbox/attachments/photo.png'));
    expect(url.contains('%20'), isFalse);
  });

  test('Fenced code block parses into code AST and exports correctly', () {
    const md = '''
```dart
void main() {
  print("Hello V8");
}
```
''';
    final doc = AppFlowyCodec.parseToDocument(md);
    expect(doc.root.children.isNotEmpty, isTrue);
    final firstNode = doc.root.children.first;
    expect(firstNode.type == 'code' || firstNode.type == 'code_block', isTrue);
    final exported = AppFlowyCodec.documentToMarkdownString(doc);
    expect(exported, contains('void main()'));
  });

  testWidgets('NoteEditor title input has transparent filled decoration and renders code block directly editable', (tester) async {
    final note = Note(
      id: 'test-fidelity-note',
      title: '保真度测试笔记',
      deltaJson: '''
{
  "document": {
    "type": "page",
    "children": [
      {
        "type": "code_block",
        "attributes": {
          "code": "const a = 42;",
          "language": "javascript"
        }
      }
    ]
  }
}
''',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1024,
            height: 768,
            child: NoteEditor(
              key: const ValueKey('fidelity-editor'),
              note: note,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 验证标题输入框存在且没有被全局暗色填充
    final titleFieldFinder = find.widgetWithText(TextField, '保真度测试笔记');
    expect(titleFieldFinder, findsOneWidget);
    final TextField titleField = tester.widget(titleFieldFinder);
    expect(titleField.decoration?.filled, isFalse);
    expect(titleField.decoration?.fillColor, equals(Colors.transparent));

    // 2. 验证代码块组件存在且直接呈现 TextField（支持内联即时输入，无需点二级“编辑”按钮）
    expect(find.byType(NoteCodeBlockComponentWidget), findsOneWidget);
    final codeFieldFinder = find.descendant(
      of: find.byType(NoteCodeBlockComponentWidget),
      matching: find.byType(TextField),
    );
    expect(codeFieldFinder, findsOneWidget);
    final TextField codeField = tester.widget(codeFieldFinder);
    expect(codeField.controller?.text, equals('const a = 42;'));
    expect(find.text('javascript'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
  });
}
