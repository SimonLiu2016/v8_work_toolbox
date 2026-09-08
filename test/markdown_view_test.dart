import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/components/markdown_view.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 将组件置于最小可用的 Material 脚手架中。
  Widget harness(Widget child) {
    return MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('AppMarkdownView 基础渲染', () {
    testWidgets('渲染 markdown 标题而非字面语法字符', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '## 归属分析')));

      // 标题文本可见，且字面 "##" 不应作为独立文本节点出现
      expect(find.textContaining('归属分析'), findsOneWidget);
      expect(find.text('## 归属分析'), findsNothing);
    });

    testWidgets('渲染加粗行内强调', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '**安全**清理')));
      expect(find.textContaining('安全清理'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
    });

    testWidgets('渲染无序列表条目', (tester) async {
      await tester.pumpWidget(
        harness(const AppMarkdownView(data: '- 第一项\n- 第二项')),
      );
      expect(find.textContaining('第一项'), findsOneWidget);
      expect(find.textContaining('第二项'), findsOneWidget);
    });

    testWidgets('渲染内联 code 与代码块', (tester) async {
      await tester.pumpWidget(
        harness(
          const AppMarkdownView(data: '运行 `npm install`，例如：\n\n```sh\nnpm install\n```'),
        ),
      );
      expect(find.textContaining('npm install'), findsWidgets);
    });

    testWidgets('空字符串不抛异常', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '')));
      expect(tester.takeException(), isNull);
    });
  });

  group('AppMarkdownView 可访问性与交互', () {
    testWidgets('默认开启文本选择（对齐替换前的 SelectableText 行为）', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '可被选择的正文')));

      // selectable 生效时 markdown 内部走 SelectableText.rich
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.selectable, isTrue);
    });

    testWidgets('selectable=false 时透传关闭', (tester) async {
      await tester.pumpWidget(
        harness(const AppMarkdownView(data: '不可选择', selectable: false)),
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.selectable, isFalse);
    });
  });

  group('AppMarkdownView 样式派生', () {
    testWidgets('默认使用 AppTheme.fontBody 作为正文字体', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '段落文本')));
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.styleSheet!.p, AppTheme.fontBody);
    });

    testWidgets('baseStyle 覆盖后正文与加粗样式同步派生', (tester) async {
      const base = TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.6);
      await tester.pumpWidget(harness(const AppMarkdownView(data: '段落', baseStyle: base)));

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.styleSheet!.p, base);
      expect(markdown.styleSheet!.strong?.fontWeight, FontWeight.w700);
      expect(markdown.styleSheet!.strong?.fontSize, 14);
    });

    testWidgets('标题字号锚定绝对值，不随 baseStyle 放大', (tester) async {
      const largeBase = TextStyle(fontSize: 28, color: AppTheme.textPrimary);
      await tester.pumpWidget(harness(const AppMarkdownView(data: '# H1', baseStyle: largeBase)));

      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      // baseStyle 28 不应导致 h1 变成 28+
      expect(markdown.styleSheet!.h1!.fontSize, 20);
      expect(markdown.styleSheet!.h2!.fontSize, 17);
    });

    testWidgets('自定义 codeBlockColor 生效于代码块与内联 code', (tester) async {
      final custom = AppTheme.warning;
      await tester.pumpWidget(
        harness(AppMarkdownView(data: '```sh\nls\n```', codeBlockColor: custom)),
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

      expect(
        (markdown.styleSheet!.codeblockDecoration as BoxDecoration).color,
        custom,
      );
      expect(markdown.styleSheet!.code!.backgroundColor, custom);
    });
  });

  group('AppMarkdownView maxHeight 滚动容器', () {
    testWidgets('未设置 maxHeight 时不额外包裹滚动视图', (tester) async {
      await tester.pumpWidget(harness(const AppMarkdownView(data: '内容')));
      expect(find.descendant(of: find.byType(AppMarkdownView), matching: find.byType(SingleChildScrollView)), findsNothing);
    });

    testWidgets('设置 maxHeight 时内部包裹可滚动容器且内容仍可见', (tester) async {
      await tester.pumpWidget(
        harness(const AppMarkdownView(data: '内容', maxHeight: 120)),
      );
      expect(find.descendant(of: find.byType(AppMarkdownView), matching: find.byType(SingleChildScrollView)), findsOneWidget);
      expect(find.textContaining('内容'), findsOneWidget);
    });
  });
}
