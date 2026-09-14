import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Table: Delete key deletion, cell drag-selection, and outside tap to resume text editing', (tester) async {
    final note = Note(
      id: 'test-table-delete-drag',
      title: '测试删除与拖选及外部切换',
      deltaJson: jsonEncode([
        {'insert': '外部正文段落第一行\n外部正文段落第二行\n'},
      ]),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isPinned: false,
      isDeleted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          FlutterQuillLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh', 'CN'),
          Locale('en', 'US'),
        ],
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: NoteEditor(note: note),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 插入表格
    final insertBtn = find.byTooltip('插入表格 (选中文字可自动拆行拆列)');
    expect(insertBtn, findsOneWidget);
    await tester.tap(insertBtn);
    await tester.pumpAndSettle();

    // 2. 点击表头 1 进入编辑并获得焦点
    final h1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    expect(h1Finder, findsOneWidget);
    await tester.tap(h1Finder);
    await tester.pumpAndSettle();

    final h1Widget = tester.widget<TextField>(h1Finder);
    expect(h1Widget.focusNode?.hasFocus, isTrue, reason: '点击表头 1 后应该获得焦点');

    // 3. 测试 Delete / Backspace 按键删除
    // 先修改为 "ABCD"
    await tester.enterText(h1Finder, 'ABCD');
    await tester.pumpAndSettle();
    expect(find.text('ABCD'), findsOneWidget);

    final abcdFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'ABCD',
    );
    final abcdWidget = tester.widget<TextField>(abcdFinder);

    // 将光标定位在末尾 (offset: 4)
    abcdWidget.controller!.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    // 按下 Backspace / Delete 键
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    // 应该删除了末尾字符 'D'，变成 'ABC'
    expect(abcdWidget.controller!.text, 'ABC', reason: '按 Delete/Backspace 键应成功删除光标前字符');

    // 4. 测试选区删除：选中 'BC'
    abcdWidget.controller!.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    // 应该删除了选中的 'BC'，只剩 'A'
    expect(abcdWidget.controller!.text, 'A', reason: '按 Delete/Backspace 键应成功删除选中区域内容');

    // 5. 测试点击外部正文段落切换焦点
    // 寻找正文 QuillEditor
    final quillFinder = find.byType(QuillEditor);
    expect(quillFinder, findsOneWidget);
    final QuillEditor qEditor = tester.widget(quillFinder);

    // 点击正文文字区域（位于 QuillEditor 内部的文本行）
    final quillTopLeft = tester.getTopLeft(find.byType(QuillEditor));
    await tester.tapAt(quillTopLeft + const Offset(30, 20));
    await tester.pumpAndSettle();

    // 验证：表格单元格失去焦点并持久化
    for (final el in find.byType(TextField).evaluate()) {
      final tf = el.widget as TextField;
      print('AFTER OUTSIDE TAP: text="${tf.controller?.text}", hasFocus=${tf.focusNode?.hasFocus}');
    }
    expect(qEditor.focusNode.hasFocus, isTrue, reason: '点击外部正文后，正文编辑器应获得焦点');
    expect(qEditor.controller.selection.isValid, isTrue, reason: '点击外部正文后，正文光标应正常就位');

    print('✅ Delete按键、选区删除与正文焦点无缝切换全部验证通过！');
  });
}
