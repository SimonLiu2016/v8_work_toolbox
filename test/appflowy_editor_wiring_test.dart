import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';

void main() {
  testWidgets('AppFlowyEditor widget can render document and table', (tester) async {
    const md = '''
# 标题

正文内容

| 列1 | 列2 |
| --- | --- |
| 值1 | 值2 |

- [ ] 待办项
''';
    final doc = AppFlowyCodec.parseToDocument(md);
    final editorState = EditorState(document: doc);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppFlowyEditor(
            editorState: editorState,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('标题', findRichText: true), findsOneWidget);
    expect(find.text('列1', findRichText: true), findsOneWidget);
    expect(find.text('值1', findRichText: true), findsOneWidget);
  });
}
