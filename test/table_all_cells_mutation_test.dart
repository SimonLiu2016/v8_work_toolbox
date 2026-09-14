import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/note_editor.dart';

void main() {
  testWidgets('Every header and cell can be modified, values take effect, and no text leaks outside table', (tester) async {
    final note = Note(
      id: 'test-all-cells-mutation',
      title: '全部单元格逐一修改与防外泄测试',
      deltaJson: jsonEncode([
        {'insert': '【初始前置正文段落】\n'},
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
            width: 1200,
            height: 900,
            child: NoteEditor(note: note),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. 点击工具栏「插入表格」
    final insertBtn = find.byTooltip('插入表格 (选中文字可自动拆行拆列)');
    expect(insertBtn, findsOneWidget);
    await tester.tap(insertBtn);
    await tester.pumpAndSettle();

    // 定义 3x3 共 9 个单元格的目标修改内容
    final newValues = [
      '表头A_新', '表头B_新', '表头C_新',
      '内容_R1C1_新', '内容_R1C2_新', '内容_R1C3_新',
      '内容_R2C1_新', '内容_R2C2_新', '内容_R2C3_新',
    ];

    // 2. 依次修改 3 个表头
    for (int col = 0; col < 3; col++) {
      final oldHeader = '表头 ${col + 1}';
      final hFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == oldHeader,
      );
      expect(hFinder, findsOneWidget, reason: '应该找到初始表头: $oldHeader');
      
      // 点击聚焦
      await tester.tap(hFinder);
      await tester.pumpAndSettle();

      // 输入新内容
      await tester.enterText(hFinder, newValues[col]);
      await tester.pumpAndSettle();

      // 验证单元格内输入生效
      final updatedFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == newValues[col],
      );
      expect(updatedFinder, findsOneWidget, reason: '表头修改为 "${newValues[col]}" 应即时生效');
    }

    // 3. 依次修改 6 个内容单元格
    for (int cellIdx = 3; cellIdx < 9; cellIdx++) {
      final cFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '内容',
      );
      expect(cFinder, findsWidgets, reason: '应该找到剩余未修改的内容单元格');

      // 点击第一个尚未修改的“内容”单元格
      await tester.tap(cFinder.first);
      await tester.pumpAndSettle();

      final focusedFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == '内容' && w.focusNode?.hasFocus == true,
      );
      expect(focusedFinder, findsOneWidget, reason: '点击第 $cellIdx 个内容单元格后应获得焦点');

      // 输入修改
      await tester.enterText(focusedFinder, newValues[cellIdx]);
      await tester.pumpAndSettle();

      // 验证修改生效
      final updatedCellFinder = find.byWidgetPredicate(
        (w) => w is TextField && w.controller?.text == newValues[cellIdx],
      );
      expect(updatedCellFinder, findsOneWidget, reason: '内容单元格修改为 "${newValues[cellIdx]}" 应生效');
    }

    // 4. 【关键防外泄校验】：检查 Quill 正文是否被污染（是否有任何表格输入漏到了表格外部的正文段落）
    final quillEditorFinder = find.byType(QuillEditor);
    expect(quillEditorFinder, findsOneWidget);
    final QuillEditor editorWidget = tester.widget(quillEditorFinder);
    final String docPlainText = editorWidget.controller.document.toPlainText();
    
    // 正文中除了嵌入块占位符（\ufffc）和初始文本外，绝不应包含任何单元格新输入的文字
    for (final val in newValues) {
      expect(
        docPlainText.contains(val),
        isFalse,
        reason: '防外泄断言失败！单元格内容 "$val" 意外泄漏并输入到了表格外正文中！正文当前内容: "$docPlainText"',
      );
    }

    // 5. 点击“完成编辑”退出编辑态
    final doneBtn = find.byTooltip('完成编辑');
    expect(doneBtn, findsOneWidget);
    await tester.tap(doneBtn);
    await tester.pumpAndSettle();

    // 6. 验证展示态下全部 9 个单元格内容均完整准确展示
    for (final val in newValues) {
      expect(find.text(val), findsOneWidget, reason: '展示态下必须正确显示修改后的文本 "$val"');
    }

    // 7. 在展示态下直接点击位于最右下角的单元格（内容_R2C3_新），验证能精准重入编辑态
    await tester.tap(find.text('内容_R2C3_新'));
    await tester.pumpAndSettle();

    final reEditFinder = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '内容_R2C3_新' && w.focusNode?.hasFocus == true,
    );
    expect(reEditFinder, findsOneWidget, reason: '展示态下点击最右下角单元格应成功进入编辑态并聚焦');

    // 二次修改
    await tester.enterText(reEditFinder, '内容_R2C3_二次修改确认');
    await tester.pumpAndSettle();

    // 再次点击完成编辑
    await tester.tap(find.byTooltip('完成编辑'));
    await tester.pumpAndSettle();

    expect(find.text('内容_R2C3_二次修改确认'), findsOneWidget);

    // 再次确认正文无泄露
    final String finalDocPlainText = editorWidget.controller.document.toPlainText();
    expect(finalDocPlainText.contains('内容_R2C3_二次修改确认'), isFalse);
  });
}
