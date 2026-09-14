import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('NoteEditor mounts cleanly with finite bounds and renders content without layout exceptions', (tester) async {
    final note = Note(
      id: 'test-note-1',
      title: '关于系统架构优化的设计与实践',
      deltaJson: '{"document":{"type":"page","children":[{"type":"paragraph","data":{"delta":[{"insert":"这是测试笔记的正文内容，应当清晰可见！"}]}}]}}',
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
              key: const ValueKey('test-editor-key'),
              note: note,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 验证 NoteEditor 成功挂载
    expect(find.byType(NoteEditor), findsOneWidget);

    // 2. 验证 AppFlowyEditor 在树中且具有明确尺寸
    final appFlowyEditorFinder = find.byType(AppFlowyEditor);
    expect(appFlowyEditorFinder, findsOneWidget);

    final RenderBox renderBox = tester.renderObject(appFlowyEditorFinder);
    expect(renderBox.size.width, greaterThan(500));
    expect(renderBox.size.height, greaterThan(400));

    // 3. 验证无 SingleChildScrollView 直接包裹 AppFlowyEditor (解决无限高冲突)
    final directParent = find.ancestor(
      of: appFlowyEditorFinder,
      matching: find.byType(SingleChildScrollView),
    );
    expect(directParent, findsNothing);

    // 4. 验证笔记标题正确渲染
    expect(find.text('关于系统架构优化的设计与实践'), findsOneWidget);

    // 5. 模拟用户点击空白区域，触发轻触聚焦
    await tester.tap(appFlowyEditorFinder);
    await tester.pumpAndSettle();

    // 无任何未捕获的 Flutter 异常
    expect(tester.takeException(), isNull);
  });

  testWidgets('NoteEditor handles empty/null deltaJson note gracefully', (tester) async {
    final emptyNote = Note(
      id: 'test-note-empty',
      title: '空笔记测试',
      deltaJson: '',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: NoteEditor(
              note: emptyNote,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(AppFlowyEditor), findsOneWidget);
    final RenderBox box = tester.renderObject(find.byType(AppFlowyEditor));
    expect(box.size.width, greaterThan(400));
    expect(box.size.height, greaterThan(300));
    expect(tester.takeException(), isNull);
  });
}
