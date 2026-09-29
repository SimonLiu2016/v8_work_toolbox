import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/components/markdown_view.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

/// 共享 markdown 组件的主题对比度契约。
///
/// 防的是「默认值绑定某一主题」：本组件被暗色与浅色容器共用，曾因默认写死
/// 暗色容器的代码底色（`AppTheme.bgCardHover`），浅色面板里的代码文字被
/// 深灰底盖住、与近黑字色叠在一起看不清。
void main() {
  group('代码底色跟随主题', () {
    testWidgets('深色主题下默认取暗色表面色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: AppMarkdownView(data: '用 `字段名` 举例')),
        ),
      );

      // 深色分支的取值必须与改造前一致，三个暗色调用点外观零变化。
      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      final codeSpan = _findSpanWithBackground(selectable.textSpan!);
      expect(codeSpan, isNotNull);
      expect(codeSpan!.style?.backgroundColor, AppTheme.bgCardHover);
    });

    testWidgets('浅色主题下默认取浅中性，而非暗灰', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: AppMarkdownView(data: '用 `字段名` 举例')),
        ),
      );

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      final codeSpan = _findSpanWithBackground(selectable.textSpan!);
      expect(codeSpan, isNotNull);
      expect(
        codeSpan!.style?.backgroundColor,
        isNot(AppTheme.bgCardHover),
        reason: '浅色容器不得落到暗色代码底上',
      );
      // 浅中性：既不是纯白（会与容器背景同色），也不是深灰。
      final bg = codeSpan.style!.backgroundColor!;
      expect(bg.computeLuminance(), greaterThan(0.7));
      expect(bg, isNot(Colors.white));
    });

    testWidgets('显式传参优先于主题推导', (tester) async {
      const explicit = Color(0xFF123456);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppMarkdownView(data: '用 `字段名` 举例', codeBlockColor: explicit),
          ),
        ),
      );

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      final codeSpan = _findSpanWithBackground(selectable.textSpan!);
      expect(codeSpan!.style?.backgroundColor, explicit);
    });

    testWidgets('NotebookLightScope 包裹后代码底色为浅色', (tester) async {
      // 问答面板的真实形态：NotebookLightScope 提供浅色 Theme，内部渲染回答。
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: NotebookLightScopeProbe())),
      );

      final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      final codeSpan = _findSpanWithBackground(selectable.textSpan!);
      expect(codeSpan, isNotNull);
      expect(
        codeSpan!.style?.backgroundColor,
        isNot(AppTheme.bgCardHover),
        reason: 'NotebookLightScope 内的浅色面板不得落到暗色代码底上',
      );
    });
  });
}

/// 在 RichText 树里找第一个带背景色的 TextSpan（即行内 code）。
TextSpan? _findSpanWithBackground(InlineSpan span) {
  if (span is TextSpan) {
    if (span.style?.backgroundColor != null) return span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _findSpanWithBackground(child);
      if (found != null) return found;
    }
  }
  return null;
}

/// 模拟「问我的笔记」面板的浅色边界包裹。
class NotebookLightScopeProbe extends StatelessWidget {
  const NotebookLightScopeProbe({super.key});

  @override
  Widget build(BuildContext context) {
    // 与 NotebookLightScope 内部一致：浅色 Theme。
    return Theme(
      data: AppTheme.lightTheme,
      child: const SizedBox(
        width: 360,
        child: AppMarkdownView(
          data: '用 `字段名` 举例',
          baseStyle: TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
        ),
      ),
    );
  }
}
