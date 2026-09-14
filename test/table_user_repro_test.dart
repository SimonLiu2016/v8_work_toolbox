import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Reproduction test: insert table and modify header & content', (tester) async {
    final note = Note(
      id: 'test-user-repro',
      title: '测试表格插入后修改',
      deltaJson: jsonEncode([
        {'insert': '初始笔记内容\n'},
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

    // 1. 点击插入表格按钮
    final insertBtn = find.byTooltip('插入表格 (选中文字可自动拆行拆列)');
    expect(insertBtn, findsOneWidget);
    await tester.tap(insertBtn);
    await tester.pumpAndSettle();

    print('=== STEP 1: Table inserted ===');

    // 2. 检查是否有 TextField 出现，或者是文本
    final textFields = find.byType(TextField);
    print('Found ${textFields.evaluate().length} TextFields');
    for (final element in textFields.evaluate()) {
      final tf = element.widget as TextField;
      print('TextField controller text: "${tf.controller?.text}", focusNode hasFocus: ${tf.focusNode?.hasFocus}');
    }

    // 3. 尝试在表头 1 输入新文字
    final h1Finder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '表头 1',
    );
    if (h1Finder.evaluate().isNotEmpty) {
      print('h1 TextField found! Entering text...');
      await tester.enterText(h1Finder, '我的自定义表头');
      await tester.pumpAndSettle();
      final updatedH1Finder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '我的自定义表头',
      );
      expect(updatedH1Finder, findsOneWidget);
      final tf = tester.widget<TextField>(updatedH1Finder);
      print('After enterText, h1 text is: "${tf.controller?.text}"');
    } else {
      print('h1 TextField NOT found! Looking for Text widget:');
      final h1TextFinder = find.text('表头 1');
      print('Found "表头 1" Text: ${h1TextFinder.evaluate().length}');
      if (h1TextFinder.evaluate().isNotEmpty) {
        await tester.tap(h1TextFinder);
        await tester.pumpAndSettle();
        print('After tap on "表头 1", textFields count: ${find.byType(TextField).evaluate().length}');
      }
    }

    // 4. 尝试点击内容单元格修改内容
    final contentCellFinder = find.text('内容');
    print('Found "内容" Text widgets: ${contentCellFinder.evaluate().length}');
    if (contentCellFinder.evaluate().isNotEmpty) {
      await tester.tap(contentCellFinder.first);
      await tester.pumpAndSettle();
      print('After tap on first "内容", textFields count: ${find.byType(TextField).evaluate().length}');
      
      // 查找获取焦点的“内容”输入框并输入新内容
      final focusedContentFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
      );
      expect(focusedContentFinder, findsOneWidget);
      await tester.enterText(focusedContentFinder, '自定义单元格内容1');
      await tester.pumpAndSettle();
      print('Successfully modified content cell to: 自定义单元格内容1');
    }

    // 5. 点击“完成编辑”退出编辑态
    final doneBtn = find.byTooltip('完成编辑');
    expect(doneBtn, findsOneWidget);
    await tester.tap(doneBtn);
    await tester.pumpAndSettle();
    print('=== STEP 5: Clicked "完成编辑", checking display mode ===');

    // 验证展示态下文本正确呈现
    expect(find.text('我的自定义表头'), findsOneWidget);
    expect(find.text('自定义单元格内容1'), findsOneWidget);
    print('✅ Display mode correctly shows modified header and content!');

    // 6. 验证在展示态下：直接点击“我的自定义表头”，应该能重新进入编辑模式
    print('=== STEP 6: Tapping "我的自定义表头" in display mode to re-enter edit mode ===');
    await tester.tap(find.text('我的自定义表头'));
    await tester.pumpAndSettle();

    final reEditHeaderFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '我的自定义表头' && w.focusNode?.hasFocus == true,
    );
    print('reEditHeaderFinder count: ${reEditHeaderFinder.evaluate().length}');
    expect(reEditHeaderFinder, findsOneWidget, reason: '点击表头应能重新进入编辑模式并聚焦输入框');

    // 7. 再次修改表头为“第二次修改的表头”
    await tester.enterText(reEditHeaderFinder, '第二次修改的表头');
    await tester.pumpAndSettle();

    // 8. 直接点击另一个内容单元格（无需先退回到展示态）
    final anotherContentFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容',
    );
    expect(anotherContentFinder, findsWidgets);
    await tester.tap(anotherContentFinder.first);
    await tester.pumpAndSettle();
    
    final focusedAnotherFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
    );
    expect(focusedAnotherFinder, findsOneWidget, reason: '直接点击另一个单元格应切换焦点到该单元格');
    await tester.enterText(focusedAnotherFinder, '第二次修改的内容2');
    await tester.pumpAndSettle();

    // 9. 点击外部区域退出编辑
    await tester.tapAt(const Offset(500, 20)); // 点击顶栏区域
    await tester.pumpAndSettle();
    
    // 验证最终修改生效
    expect(find.text('第二次修改的表头'), findsOneWidget);
    expect(find.text('第二次修改的内容2'), findsOneWidget);
    print('✅ Full interactive modification test PASSED!');
  });
}
