import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Table focus transition: single-click cell focus, cell-to-cell switch, and table-to-body focus handover', (tester) async {
    final note = Note(
      id: 'test-focus-transition',
      title: '焦点流转与单次点击测试',
      deltaJson: jsonEncode([
        {'insert': '外部正文段落第一行\n'},
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

    // 2. 插入表格后静默展示，点击表头 1 获焦进入编辑态
    final h1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    expect(h1Finder, findsOneWidget);
    await tester.tap(h1Finder);
    await tester.pumpAndSettle();
    TextField h1Widget = tester.widget(h1Finder);
    expect(h1Widget.focusNode?.hasFocus, isTrue, reason: '点击表头 1 应获焦进入编辑态');

    // 3. 点击第二个表头（表头 2）—— 单次点击直接获焦，无需多次点击
    final h2Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 2',
    );
    expect(h2Finder, findsOneWidget);
    await tester.tap(h2Finder);
    await tester.pumpAndSettle();

    final h2Focused = tester.widget<TextField>(h2Finder);
    expect(h2Focused.focusNode?.hasFocus, isTrue, reason: '单次点击表头 2 应直接切换焦点至表头 2');
    await tester.enterText(h2Finder, '新表头2');
    await tester.pumpAndSettle();
    expect(find.text('新表头2'), findsOneWidget);

    // 4. 点击内容单元格 —— 单次点击直接获焦
    final contentFinders = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容',
    );
    expect(contentFinders, findsWidgets);
    await tester.tap(contentFinders.first);
    await tester.pumpAndSettle();

    final contentFocused = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
    );
    expect(contentFocused, findsOneWidget, reason: '单次点击内容单元格应立刻获焦');
    await tester.enterText(contentFocused, '即时新内容');
    await tester.pumpAndSettle();
    expect(find.text('即时新内容'), findsOneWidget);

    // 5. 点击表格外部区域（例如顶部标题栏）触发 TapRegion.onTapOutside
    await tester.tapAt(const Offset(500, 20));
    await tester.pumpAndSettle();

    // 验证表格成功退出编辑态并持久化展示
    expect(find.text('新表头2'), findsOneWidget);
    expect(find.text('即时新内容'), findsOneWidget);

    // 6. 验证展示态下：单击单元格即刻再次进入编辑态且获焦
    print('Tapping "新表头2"...');
    await tester.tap(find.text('新表头2'));
    await tester.pumpAndSettle();

    final allTfs = find.byType(TextField).evaluate();
    print('Total TextFields found: ${allTfs.length}');
    for (final el in allTfs) {
      final tf = el.widget as TextField;
      print('TextField text: "${tf.controller?.text}", hasFocus: ${tf.focusNode?.hasFocus}');
    }

    final reEditH2Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '新表头2' && w.focusNode?.hasFocus == true,
    );
    expect(reEditH2Finder, findsOneWidget, reason: '展示态下单次点击单元格应即刻重新聚焦');

    // 7. 再次点击“完成编辑”按钮，进入展示态
    final doneBtn = find.byTooltip('完成编辑');
    expect(doneBtn, findsOneWidget);
    await tester.tap(doneBtn);
    await tester.pumpAndSettle();
    expect(find.text('新表头2'), findsOneWidget);

    // 8. 【第一列核心测试】：在展示态下，点击第 1 列（表头 1），断言能够直接进入编辑态并获焦
    final col1TextFinder = find.text('表头 1');
    expect(col1TextFinder, findsOneWidget, reason: '展示态下应该显示第 1 列文本 "表头 1"');
    await tester.tap(col1TextFinder);
    await tester.pumpAndSettle();

    final reEditH1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1' && w.focusNode?.hasFocus == true,
    );
    expect(reEditH1Finder, findsOneWidget, reason: '展示态下点击第 1 列单元格应即刻进入编辑态并获焦');

    // 9. 【双光标防范测试】：当处于表格编辑态时，断言 Quill 编辑器隐藏光标且未获焦，外层无多余光标
    final quillFinder = find.byType(QuillEditor);
    expect(quillFinder, findsOneWidget);
    final QuillEditor qEditor = tester.widget(quillFinder);
    expect(qEditor.config.showCursor, isFalse, reason: '表格编辑态下 Quill 编辑器配置必须隐藏光标，防止正文出现外层光标');
    expect(qEditor.focusNode.hasPrimaryFocus, isFalse, reason: '表格编辑态下主要焦点在单元格内，Quill 主体不应持有 primaryFocus');

    // 10. 点击外部恢复正文编辑态
    await tester.tapAt(const Offset(500, 20));
    await tester.pumpAndSettle();
    expect(reEditH1Finder.evaluate().isEmpty || !tester.widget<TextField>(reEditH1Finder).focusNode!.hasFocus, isTrue, reason: '点击外部退出表格后，单元格应失焦');

    await tester.pump(const Duration(milliseconds: 850));
    await tester.pumpAndSettle();
  });
}
