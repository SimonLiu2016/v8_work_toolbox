import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/shell/tool_panel.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/registry.dart';
import 'package:V8WorkToolbox/components/app_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ToolPanel hover and selection visual hierarchy in light mode', (tester) async {
    final tools = ToolRegistry.publicTools;
    final selectedId = tools.first.id;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        home: Scaffold(
          body: ToolPanel(
            title: '全部工具',
            tools: tools,
            selectedToolId: selectedId,
            isCollapsed: false,
            onToggleCollapse: () {},
            onSelectTool: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final itemFinders = find.byType(AppListItem);
    expect(itemFinders, findsWidgets);

    // 1. 验证选中项 (第一项)
    final firstItem = itemFinders.at(0);
    final firstItemWidget = tester.widget<AppListItem>(firstItem);
    expect(firstItemWidget.isSelected, isTrue);

    // 选中项拥有左侧 Accent 指示条 (width: 3)
    final indicatorFinder = find.descendant(
      of: firstItem,
      matching: find.byWidgetPredicate(
        (w) => w is Container && (w.decoration is BoxDecoration) &&
               (w.decoration as BoxDecoration).color == AppTheme.accentDark,
      ),
    );
    expect(indicatorFinder, findsOneWidget);

    // 2. 模拟鼠标悬停未选中项 (第二项)
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final secondItem = itemFinders.at(1);
    final secondItemWidget = tester.widget<AppListItem>(secondItem);
    expect(secondItemWidget.isSelected, isFalse);

    // 移入第二项
    await gesture.moveTo(tester.getCenter(secondItem));
    await tester.pump(); // 即时刷新（0ms 响应）

    // 验证第二项即时应用了浅色模式悬停色（具有清晰对比度的半透明黑底）
    final secondContainerFinder = find.descendant(
      of: secondItem,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration &&
               ((w.decoration as BoxDecoration).color?.a ?? 0) > 0,
      ),
    );
    expect(secondContainerFinder, findsWidgets);

    // 移出第二项到外部
    await gesture.moveTo(const Offset(0, 0));
    await tester.pump(); // 即时复原

    // 验证第二项悬停即时复原为透明底，无 100ms 拖影延迟
    final secondContainerAfterExit = find.descendant(
      of: secondItem,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration &&
               (w.decoration as BoxDecoration).color == Colors.transparent,
      ),
    );
    expect(secondContainerAfterExit, findsOneWidget);
  });

  testWidgets('ToolPanel hover and selection visual hierarchy in dark mode', (tester) async {
    final tools = ToolRegistry.publicTools;
    final selectedId = tools.first.id;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: ToolPanel(
            title: '全部工具',
            tools: tools,
            selectedToolId: selectedId,
            isCollapsed: false,
            onToggleCollapse: () {},
            onSelectTool: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final itemFinders = find.byType(AppListItem);
    final secondItem = itemFinders.at(1);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // 悬停未选中项
    await gesture.moveTo(tester.getCenter(secondItem));
    await tester.pump();

    // 验证深色模式下悬停具有清晰半透明高光底色
    final secondContainerFinder = find.descendant(
      of: secondItem,
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration &&
               ((w.decoration as BoxDecoration).color?.a ?? 0) > 0,
      ),
    );
    expect(secondContainerFinder, findsWidgets);
  });
}
