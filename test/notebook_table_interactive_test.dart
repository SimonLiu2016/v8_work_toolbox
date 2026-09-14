import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Table interactive test: render, direct cell click edit, modify header, tab navigation, and blur', (tester) async {
    final note = Note(
      id: 'test-table-interactive',
      title: '表格全功能交互测试',
      deltaJson: jsonEncode([
        {'insert': '上方正文段落\n'},
        {
          'insert': {
            'table': jsonEncode({
              'rows': [
                [
                  {'text': '表头 1', 'style': 'header'},
                  {'text': '表头 2', 'style': 'header'},
                ],
                [
                  {'text': '单元格A', 'style': ''},
                  {'text': '单元格B', 'style': ''},
                ],
              ],
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

    // 1. 验证渲染成功：表格未崩溃，无全屏灰色
    expect(find.text('表头 1'), findsOneWidget);
    expect(find.text('表头 2'), findsOneWidget);
    expect(find.text('单元格A'), findsOneWidget);
    expect(find.text('单元格B'), findsOneWidget);
    print('✅ [测试阶段 1] 初始展示正常：表格无灰色崩溃，正常渲染所有表头和单元格');

    // 2. 直接点击表头单元格：应该立即进入编辑模式，且光标聚焦在表头 1 的 TextField
    await tester.tap(find.text('表头 1'));
    await tester.pumpAndSettle();

    final cell1TextFieldFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    expect(cell1TextFieldFinder, findsOneWidget);
    final TextField cell1TextField = tester.widget(cell1TextFieldFinder);
    expect(cell1TextField.focusNode?.hasFocus, isTrue);

    // 验证 Quill 外层配置隐藏光标且无 primaryFocus
    final QuillEditor editorDuringEdit = tester.widget(find.byType(QuillEditor));
    expect(editorDuringEdit.config.showCursor, isFalse);
    expect(editorDuringEdit.focusNode.hasPrimaryFocus, isFalse);
    print('✅ [测试阶段 2] 直接点击表头单元格进入编辑：输入框已聚焦，Quill 外层长光标已隐藏');

    // 3. 修改表头内容，验证不会跑到外层光标
    await tester.enterText(cell1TextFieldFinder, '更新后的自定义表头1');
    await tester.pumpAndSettle();
    expect(cell1TextField.controller?.text, '更新后的自定义表头1');
    print('✅ [测试阶段 3] 表头修改成功：文字直接在表头单元格输入');

    // 4. 按 Tab 键跳转到下一个单元格 (表头 2)
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final cell2TextFieldFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 2',
    );
    expect(cell2TextFieldFinder, findsOneWidget);
    final TextField cell2TextField = tester.widget(cell2TextFieldFinder);
    expect(cell2TextField.focusNode?.hasFocus, isTrue);
    print('✅ [测试阶段 4] 键盘 Tab 键成功导航至下一个单元格');

    // 5. 点击工具栏“完成编辑”按钮或外部区域退出编辑
    final doneButtonFinder = find.byTooltip('完成编辑');
    expect(doneButtonFinder, findsOneWidget);
    await tester.tap(doneButtonFinder);
    await tester.pumpAndSettle();

    // 验证退出编辑模式后，展示新修改的表头内容
    expect(find.text('更新后的自定义表头1'), findsOneWidget);
    print('✅ [测试阶段 5] 完成编辑后成功保存并展示最新修改的表头');
  });

  testWidgets('Insert table auto-edit test: clicking insert table immediately focuses first cell', (tester) async {
    final note = Note(
      id: 'test-insert-table-autoedit',
      title: '新建插入表格自动编辑测试',
      deltaJson: jsonEncode([
        {'insert': '测试笔记内容\n'},
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

    // 点击工具栏“插入表格”按钮
    final insertTableBtn = find.byTooltip('插入表格 (选中文字可自动拆行拆列)');
    expect(insertTableBtn, findsOneWidget);
    await tester.tap(insertTableBtn);
    await tester.pumpAndSettle();

    // 验证新插入的表格静默展示，不自动抢占焦点
    final firstCellFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    expect(firstCellFinder, findsOneWidget);
    final TextField firstCell = tester.widget(firstCellFinder);
    expect(firstCell.focusNode?.hasFocus, isFalse, reason: '新插入的表格应静默展示，不自动获焦');

    // 点击后精准进入编辑态
    await tester.tap(firstCellFinder);
    await tester.pumpAndSettle();
    final TextField focusedCell = tester.widget(firstCellFinder);
    expect(focusedCell.focusNode?.hasFocus, isTrue, reason: '点击后应获焦进入编辑态');
    print('✅ [测试阶段 6] 插入表格静默展示，点击精准获焦');
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pumpAndSettle();
  });
}
