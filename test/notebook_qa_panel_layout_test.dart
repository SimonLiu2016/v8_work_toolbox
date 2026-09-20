import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/notebook_qa_panel.dart';

/// 「问我的笔记」面板 header 的窄宽布局契约。
///
/// 面板宽度由 `notebook_page.dart` 以 `SizedBox(width: 360)` 写死。曾因 header 里
/// 一段不换行的说明文字加上 `IconButton` 默认 48px 最小点击区，把右上角的
/// 「清空对话」挤出面板边界，只露出一半。
void main() {
  /// 以与父容器一致的 360px 宽渲染面板。
  Future<void> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 360, child: NotebookQaPanel(onOpenNote: _noop)),
        ),
      ),
    );
  }

  testWidgets('空状态：无溢出、无清空按钮', (tester) async {
    await pumpPanel(tester);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.delete_sweep_outlined), findsNothing);
    expect(find.text('问我的笔记'), findsOneWidget);
  });

  testWidgets('有对话：无 RenderFlex 溢出，清空按钮完整在面板内', (tester) async {
    await pumpPanel(tester);

    // 通过输入框发起一轮问答。NotebookKbService.instance.ask 会因未初始化而
    // 失败——但那也产生一轮 turn（错误态），足以让 header 渲染清空按钮。
    await tester.enterText(find.byType(TextField).first, '豆浆机坏了怎么办');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);

    // 无 RenderFlex overflowed 异常。
    expect(tester.takeException(), isNull);

    // 清空按钮必须完整落在面板边界内。
    // 注意：图标自身只有 15px，按钮的可点区域是外层 SizedBox 的 32×32。
    final panelRect = tester.getRect(find.byType(SizedBox).first);
    final buttonRect = tester.getRect(find.byType(Tooltip).first);
    expect(
      buttonRect.right,
      lessThanOrEqualTo(panelRect.right),
      reason: '清空按钮右边缘不得超出面板右边界',
    );
    expect(
      buttonRect.left,
      greaterThanOrEqualTo(panelRect.left),
      reason: '清空按钮左边缘不得超出面板左边界',
    );
    // 32px 的 tap target：既有可点面积，又不固定消耗 header 的横向余量。
    expect(buttonRect.width, 32);
    expect(buttonRect.height, 32);
  });

  testWidgets('header 不含会挤爆宽度的说明文字', (tester) async {
    await pumpPanel(tester);
    await tester.enterText(find.byType(TextField).first, 'test');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(find.text('问我的笔记'), findsOneWidget);
    expect(
      find.textContaining('必要时可联网兜底'),
      findsNothing,
      reason: '该说明与空状态提示重复，且是 360px 下溢出的来源，应已移除',
    );
  });
}

void _noop(String noteId) {}
