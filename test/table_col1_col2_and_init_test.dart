import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Verify: quiet on note enter, seamless switch between col1 & col2, all cells editable, no leak', (tester) async {
    // 构造带表格的历史笔记（模拟数据库加载，即使旧数据带 autoEdit 也会被彻底免疫）
    final note = Note(
      id: 'test-col1-col2-table',
      title: '表格列切换与静默打开测试',
      deltaJson: jsonEncode([
        {'insert': '前置正文段落\n'},
        {
          'insert': {
            'table': jsonEncode({
              'autoEdit': true, // 旧数据可能带有 autoEdit，验证已被彻底免疫
              'rows': [
                [
                  {'text': '表头_1', 'style': 'header'},
                  {'text': '表头_2', 'style': 'header'},
                ],
                [
                  {'text': '内容_1', 'style': ''},
                  {'text': '内容_2', 'style': ''},
                ],
              ]
            })
          }
        },
        {'insert': '\n后置正文段落\n'},
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

    // =========================================================================
    // 验证点 1：进入已有表格的笔记时，绝不会自动让第一个表头处于编辑状态（静默展示）
    // =========================================================================
    final h1InitialFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头_1',
    );
    expect(h1InitialFinder, findsOneWidget);
    final h1InitialWidget = tester.widget<TextField>(h1InitialFinder);
    expect(
      h1InitialWidget.focusNode?.hasFocus,
      isFalse,
      reason: '进入笔记时表格必须处于静默状态，第 1 列表头绝不可自动处于编辑获焦状态',
    );

    final allTextFields = tester.widgetList<TextField>(find.byType(TextField));
    for (final tf in allTextFields) {
      if (tf.controller?.text != '表格列切换与静默打开测试') {
        expect(tf.focusNode?.hasFocus, isFalse, reason: '所有单元格在进入笔记时都不应处于编辑获焦态');
      }
    }

    // =========================================================================
    // 验证点 2：点击第二列表头，进入编辑状态
    // =========================================================================
    final h2Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头_2',
    );
    expect(h2Finder, findsOneWidget);
    await tester.tap(h2Finder);
    await tester.pumpAndSettle();

    final h2Widget = tester.widget<TextField>(h2Finder);
    expect(h2Widget.focusNode?.hasFocus, isTrue, reason: '点击第 2 列表头应即时获焦进入编辑态');

    await tester.enterText(h2Finder, '新表头_2修改');
    await tester.pumpAndSettle();
    expect(find.text('新表头_2修改'), findsOneWidget);

    // =========================================================================
    // 验证点 3：从第 2 列切换点击第 1 列表头，第 1 列表头必须能够正常进入编辑状态并获焦！
    // =========================================================================
    final h1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头_1',
    );
    expect(h1Finder, findsOneWidget);
    await tester.tap(h1Finder);
    await tester.pumpAndSettle();

    final h1Widget = tester.widget<TextField>(h1Finder);
    expect(h1Widget.focusNode?.hasFocus, isTrue, reason: '从第 2 列切回第 1 列表头，第 1 列表头必须获得焦点！');

    await tester.enterText(h1Finder, '新表头_1修改');
    await tester.pumpAndSettle();
    expect(find.text('新表头_1修改'), findsOneWidget);

    // =========================================================================
    // 验证点 4：点击第 2 列单元格 "内容_2"，第 2 列单元格获焦编辑
    // =========================================================================
    final c2Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容_2',
    );
    expect(c2Finder, findsOneWidget);
    await tester.tap(c2Finder);
    await tester.pumpAndSettle();

    final c2Widget = tester.widget<TextField>(c2Finder);
    expect(c2Widget.focusNode?.hasFocus, isTrue, reason: '点击第 2 列单元格应获焦');

    await tester.enterText(c2Finder, '新内容_2修改');
    await tester.pumpAndSettle();
    expect(find.text('新内容_2修改'), findsOneWidget);

    // =========================================================================
    // 验证点 5：再点击第 1 列单元格 "内容_1"，第 1 列单元格必须能够正常进入编辑状态并获焦！
    // =========================================================================
    final c1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容_1',
    );
    expect(c1Finder, findsOneWidget);
    await tester.tap(c1Finder);
    await tester.pumpAndSettle();

    final c1Widget = tester.widget<TextField>(c1Finder);
    expect(c1Widget.focusNode?.hasFocus, isTrue, reason: '从第 2 列切回第 1 列单元格，第 1 列单元格必须获得焦点！');

    await tester.enterText(c1Finder, '新内容_1修改');
    await tester.pumpAndSettle();
    expect(find.text('新内容_1修改'), findsOneWidget);

    // =========================================================================
    // 验证点 6：检查 Quill 正文是否泄露单元格输入
    // =========================================================================
    final quillEditorFinder = find.byType(QuillEditor);
    expect(quillEditorFinder, findsOneWidget);
    final QuillEditor editorWidget = tester.widget(quillEditorFinder);
    final String plainText = editorWidget.controller.document.toPlainText();

    final editedValues = ['新表头_1修改', '新表头_2修改', '新内容_1修改', '新内容_2修改'];
    for (final val in editedValues) {
      expect(
        plainText.contains(val),
        isFalse,
        reason: '内容 "$val" 绝不可泄露到外部正文段落中！',
      );
    }

    // =========================================================================
    // 验证点 7：点击外部区域（保存并退出编辑）
    // =========================================================================
    await tester.tapAt(const Offset(500, 20));
    await tester.pumpAndSettle();

    for (final val in editedValues) {
      expect(find.text(val), findsOneWidget, reason: '退出编辑后全部修改内容应完整持久化展示');
    }
  });
}
