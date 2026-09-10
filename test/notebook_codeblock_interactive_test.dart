import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Baseline Plain TextField backspace test', (tester) async {
    final ctrl = TextEditingController(text: 'hello');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: ctrl, autofocus: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(ctrl.text, equals('hello'));

    ctrl.selection = const TextSelection.collapsed(offset: 5);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();

    print('Plain TextField backspace result: "${ctrl.text}"');
  });

  testWidgets('Code block interactive test: click to edit, delete key, and blur to display', (tester) async {
    final note = Note(
      id: 'test-codeblock-interactive',
      title: '代码块交互测试',
      deltaJson: jsonEncode([
        {'insert': '上方正文段落\n'},
        {
          'insert': {
            'code_block': jsonEncode({
              'code': 'first line\nmore code',
              'language': 'dart',
            }),
          },
        },
        {'insert': '\n下方正文段落\n'},
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
            width: 900,
            height: 700,
            child: NoteEditor(note: note),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 初始状态：仅笔记标题有 1 个 TextField，代码块为 HighlightView 展示态
    expect(find.byType(HighlightView), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // 仅标题框
    print('✅ [测试阶段 1] 初始状态确认：代码块处于高亮只读展示状态，无代码块 TextField');

    // 2. 模拟点击代码块高亮区域：触发进入编辑态
    await tester.tap(find.byType(HighlightView));
    await tester.pumpAndSettle();

    // 此时应出现第 2 个 TextField（代码块输入框）
    expect(find.byType(TextField), findsNWidgets(2));
    final codeTextFieldFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text.contains('more code') == true,
    );
    expect(codeTextFieldFinder, findsOneWidget);
    final TextField codeTextField = tester.widget(codeTextFieldFinder);
    expect(codeTextField.focusNode?.hasFocus, isTrue);
    // 验证 QuillEditor 的 showCursor 必须为 false，杜绝代码块最前端出现长竖线光标！
    final QuillEditor editorWidgetDuringEdit = tester.widget(find.byType(QuillEditor));
    expect(editorWidgetDuringEdit.config.showCursor, isFalse);
    print('✅ [测试阶段 2.1] 代码块编辑态确认：Quill showCursor 为 false，彻底无长竖线光标');

    // 3. 验证键盘删除响应：
    final controller = codeTextField.controller!;
    expect(controller.text, equals('first line\nmore code'));

    // 点击该 TextField 确保输入法客户端连接激活
    await tester.tap(codeTextFieldFinder);
    await tester.pumpAndSettle();

    print('当前系统顶级焦点 PrimaryFocus: ${FocusManager.instance.primaryFocus?.debugLabel}');
    print('代码块 focusNode.hasFocus: ${codeTextField.focusNode?.hasFocus}');

    // 将光标定位在末尾 (offset = 20)
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    await tester.pumpAndSettle();

    // 模拟按下 Backspace（退格键）删除 'e'
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    print('Backspace 按下后代码内容: "${controller.text}"');
    expect(controller.text, equals('first line\nmore cod'));
    print('✅ [测试阶段 3.1] Backspace 键成功删除倒数第一个字符');

    // 光标移动到 'first line' 的 'first ' 后面 (offset = 6)，按下 Delete 键（向前删除下个字符）
    controller.selection = const TextSelection.collapsed(offset: 6);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    print('Delete 按下后代码内容: "${controller.text}"');
    expect(!controller.text.contains("first line"), isTrue);
    print('✅ [测试阶段 3.2] Delete 键成功向后删除字符');

    // 4. 测试点击外部正文区域（点击 QuillEditor 外部正文）：触发代码块完成编辑并自动保存恢复展示状态
    await tester.tap(find.byType(QuillEditor));
    await tester.pumpAndSettle();

    final remainingTextFields = find.byType(TextField).evaluate().length;
    print('点击外部正文后 TextField 数量: $remainingTextFields (应为 1，即仅剩标题框)');
    expect(remainingTextFields, equals(1));
    expect(find.byType(HighlightView), findsOneWidget);

    final QuillEditor editorWidgetAfterBlur = tester.widget(find.byType(QuillEditor));
    expect(editorWidgetAfterBlur.config.showCursor, isTrue);
    print('✅ [测试阶段 4] 点击外部正文确认：代码块无需手动点击完成即可自动落盘恢复，正文光标与编辑态顺利接管！');
  });
}
