import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/notebook_qa_panel.dart';

void main() {
  final testNote = Note(
    id: 'note-test-1',
    title: '用户操作与逻辑流程手册',
    deltaJson: '# 用户手册\n\n1. 登录系统\n2. 提交业务单据',
    isPinned: false,
    isDeleted: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  testWidgets('Scope Bar: 默认绑定 activeNote 且显示移除按钮', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: NotebookQaPanel(
              onOpenNote: (_) {},
              activeNote: testNote,
            ),
          ),
        ),
      ),
    );

    expect(find.text('范围:'), findsOneWidget);
    expect(find.text('用户操作与逻辑流程手册'), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // 点击 ✕ 解除绑定
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.text('全库检索'), findsOneWidget);
    expect(find.text('指定笔记'), findsOneWidget);
  });

  testWidgets('Scope Bar: 无 activeNote 时默认为全库检索', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: NotebookQaPanel(
              onOpenNote: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('全库检索'), findsOneWidget);
    expect(find.text('指定笔记'), findsOneWidget);
  });

  testWidgets('问答卡片操作按钮: 回答后显示保存为新笔记、追加到正文、复制按钮', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: NotebookQaPanel(
              onOpenNote: (_) {},
              activeNote: testNote,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('保存为新笔记'), findsOneWidget);
    expect(find.text('追加到正文'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('@mention 输入联想触发与异常免疫', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: NotebookQaPanel(
              onOpenNote: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '请帮我梳理 @');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('点击追加到正文触发 onAppendToActiveNote 回调', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    String? appendedText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: NotebookQaPanel(
              onOpenNote: (_) {},
              activeNote: testNote,
              onAppendToActiveNote: (text) async {
                appendedText = text;
                return true;
              },
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, '总结当前笔记');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    // 点击追加到正文
    await tester.tap(find.text('追加到正文'));
    await tester.pumpAndSettle();

    expect(appendedText, isNotNull);
    expect(find.text('已成功追加到「用户操作与逻辑流程手册」'), findsOneWidget);
  });
}
