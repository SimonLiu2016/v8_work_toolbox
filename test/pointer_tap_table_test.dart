import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Simulate real mouse clicks on table cells', (tester) async {
    final note = Note(
      id: 'test-pointer-tap',
      title: '鼠标真实点击测试',
      deltaJson: jsonEncode([
        {'insert': '第一行文字\n'},
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

    // 1. 点击插入表格
    final insertBtn = find.byTooltip('插入表格 (选中文字可自动拆行拆列)');
    await tester.tap(insertBtn);
    await tester.pumpAndSettle();

    // 2. 查找插入后的表头 1 输入框，并用鼠标真实点击它（使用指针事件模拟真实鼠标点击）
    final h1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    expect(h1Finder, findsOneWidget);
    
    print('Before tap, primaryFocus: ${FocusManager.instance.primaryFocus?.debugLabel}');
    
    // 模拟真实用户用鼠标点击“表头 1”单元格
    await tester.tap(h1Finder);
    await tester.pumpAndSettle();

    print('After tap, primaryFocus: ${FocusManager.instance.primaryFocus?.debugLabel}');
    
    // 检查此时“表头 1”是否还拥有焦点，或者是否被编辑器的 _focusEditor 抢走了焦点！
    final tf = tester.widget<TextField>(h1Finder);
    print('TextField focusNode.hasFocus: ${tf.focusNode?.hasFocus}');
    print('Is primaryFocus on TableCell: ${FocusManager.instance.primaryFocus?.debugLabel?.contains('TableCell')}');

    // 3. 输入修改表头 1
    await tester.enterText(h1Finder, '自定义新表头');
    await tester.pumpAndSettle();
    expect(find.text('自定义新表头'), findsOneWidget);

    // 4. 模拟真实用户用鼠标点击“内容”单元格
    final contentFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容',
    );
    expect(contentFinder, findsWidgets);
    await tester.tap(contentFinder.first);
    await tester.pumpAndSettle();

    final focusedContentFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
    );
    expect(focusedContentFinder, findsOneWidget, reason: '点击内容单元格后该单元格输入框应获得焦点');
    await tester.enterText(focusedContentFinder, '自定义新内容1');
    await tester.pumpAndSettle();
    expect(find.text('自定义新内容1'), findsOneWidget);

    // 5. 点击工具栏“完成编辑”退出编辑态
    final doneBtn = find.byTooltip('完成编辑');
    expect(doneBtn, findsOneWidget);
    await tester.tap(doneBtn);
    await tester.pumpAndSettle();

    // 验证展示态下正常显示
    expect(find.text('自定义新表头'), findsOneWidget);
    expect(find.text('自定义新内容1'), findsOneWidget);

    // 6. 展示态下直接点击“自定义新表头”，验证能重新进入编辑态并可再次修改
    await tester.tap(find.text('自定义新表头'));
    await tester.pumpAndSettle();

    final reEditHeaderFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '自定义新表头' && w.focusNode?.hasFocus == true,
    );
    expect(reEditHeaderFinder, findsOneWidget, reason: '点击表头应重新进入编辑态');
    await tester.enterText(reEditHeaderFinder, '最终确认表头');
    await tester.pumpAndSettle();

    // 7. 展示态下直接点击另一个“内容”单元格
    final anotherContentFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容',
    );
    expect(anotherContentFinder, findsWidgets);
    await tester.tap(anotherContentFinder.first);
    await tester.pumpAndSettle();

    final focusedAnotherFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
    );
    expect(focusedAnotherFinder, findsOneWidget);
    await tester.enterText(focusedAnotherFinder, '最终确认内容2');
    await tester.pumpAndSettle();

    // 8. 再次点击“完成编辑”并保存
    await tester.tap(find.byTooltip('完成编辑'));
    await tester.pumpAndSettle();

    expect(find.text('最终确认表头'), findsOneWidget);
    expect(find.text('最终确认内容2'), findsOneWidget);
    print('✅ All table interaction tests PASSED!');
  });
}
