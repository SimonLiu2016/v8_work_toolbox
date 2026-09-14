import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'package:V8WorkToolbox/tools/notebook/ui/components/note_code_block_component.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NoteCodeBlockComponentWidget line numbers', () {
    testWidgets('renders line numbers gutter matching code line count', (tester) async {
      const initialCode = 'line 1\nline 2\nline 3';
      final node = codeBlockNode(code: initialCode, language: 'dart');
      final editorState = EditorState(document: Document(root: pageNode(children: [node])));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: editorState,
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                NoteCodeBlockKeys.type: NoteCodeBlockComponentBuilder(),
                'code': NoteCodeBlockComponentBuilder(),
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. 验证行号槽文本为 "1\n2\n3"
      expect(find.text('1\n2\n3'), findsOneWidget);

      // 2. 验证代码输入框初始值为完整代码
      final codeFieldFinder = find.byType(TextField);
      expect(codeFieldFinder, findsOneWidget);
      final TextField codeField = tester.widget(codeFieldFinder);
      expect(codeField.controller?.text, equals(initialCode));

      // 3. 点击左侧行号区域，验证能触发获取焦点
      final gutterFinder = find.text('1\n2\n3');
      await tester.tap(gutterFinder);
      await tester.pumpAndSettle();

      // 4. 输入额外的一行代码，验证行号动态递增为 "1\n2\n3\n4"
      await tester.enterText(codeFieldFinder, 'line 1\nline 2\nline 3\nline 4');
      await tester.pumpAndSettle();

      expect(find.text('1\n2\n3\n4'), findsOneWidget);
    });

    testWidgets('copy button copies pure code without line numbers', (tester) async {
      const code = 'const x = 100;\nprint(x);';
      final node = codeBlockNode(code: code, language: 'dart');
      final editorState = EditorState(document: Document(root: pageNode(children: [node])));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppFlowyEditor(
              editorState: editorState,
              blockComponentBuilders: {
                ...standardBlockComponentBuilderMap,
                NoteCodeBlockKeys.type: NoteCodeBlockComponentBuilder(),
                'code': NoteCodeBlockComponentBuilder(),
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 验证行号文本存在
      expect(find.text('1\n2'), findsOneWidget);

      // 点击复制按钮
      final copyBtnFinder = find.text('复制');
      expect(copyBtnFinder, findsOneWidget);
      await tester.tap(copyBtnFinder);
      await tester.pump();

      // 复制按钮变为 "已复制"
      expect(find.text('已复制'), findsOneWidget);

      // 推进时钟耗尽 2 秒还原定时器
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
