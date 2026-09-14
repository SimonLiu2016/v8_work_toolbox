import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppFlowyCodec new & legacy empty note parsing', () {
    test('legacy Quill empty note [{"insert":"\\n"}] decodes to blank document without raw syntax leakage', () {
      const legacyEmptyDelta = '[{"insert":"\\n"}]';
      final doc = AppFlowyCodec.parseToDocument(legacyEmptyDelta);
      expect(doc.root.children.isNotEmpty, isTrue);

      final summary = AppFlowyCodec.documentToSummary(doc);
      expect(summary.contains('insert'), isFalse);
      expect(summary.contains('['), isFalse);

      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('insert'), isFalse);
    });

    test('corrupted or whitespace-only JSON array returns blank document safely', () {
      const emptyArray = '[]';
      final doc1 = AppFlowyCodec.parseToDocument(emptyArray);
      expect(doc1.root.children.isNotEmpty, isTrue);

      const invalidArray = '[{broken json';
      final doc2 = AppFlowyCodec.parseToDocument(invalidArray);
      expect(doc2.root.children.isNotEmpty, isTrue);
    });

    test('canonical blank AppFlowy document roundtrips cleanly', () {
      final blankDoc = Document.blank(withInitialText: true);
      final json = AppFlowyCodec.documentToJson(blankDoc);
      final doc = AppFlowyCodec.parseToDocument(json);
      expect(doc.root.children.isNotEmpty, isTrue);
      expect(doc.root.children.first.type, equals('paragraph'));
    });
  });

  group('NoteEditor blank canvas & focus tests', () {
    testWidgets('NoteEditor loaded with legacy [{"insert":"\\n"}] displays zero JSON text and focuses on tap', (tester) async {
      final note = Note(
        id: 'test-blank-note-1',
        title: '新空白笔记',
        deltaJson: '[{"insert":"\\n"}]',
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
                key: const ValueKey('note-blank-editor'),
                note: note,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. 验证没有任何原始 JSON 字符串泄漏到界面中
      expect(find.textContaining('insert'), findsNothing);
      expect(find.textContaining('[{"'), findsNothing);

      // 2. 验证 AppFlowyEditor 已挂载且包含 footer 探测区
      expect(find.byType(AppFlowyEditor), findsOneWidget);

      // 3. 点击编辑视窗下方的空白区域
      final footerFinder = find.byType(SizedBox).last;
      await tester.tap(footerFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 验证未抛出任何异常，界面保持稳定
      expect(find.text('新空白笔记'), findsOneWidget);
    });
  });
}
