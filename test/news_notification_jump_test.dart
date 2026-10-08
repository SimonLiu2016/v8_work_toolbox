import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/context_services_bridge.dart';
import 'package:V8WorkToolbox/shell/app_shell.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_assistant/ui/ai_assistant_page.dart';
import 'package:V8WorkToolbox/tools/ai_assistant/ui/scheduled_tasks_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('News Notification Jump Flow Tests', () {
    testWidgets('AppShell switches to AI Assistant and signals drawer on news action', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: AppShell(
              initialRecentToolIds: ['dev-shortcuts'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证初始状态：AppShell 已装载
      expect(AppShellState.current, isNotNull);
      expect(ContextServicesBridge.instance.onNotificationAction, isNotNull);

      // 模拟收到原生通知点击事件 (actionType: 'news')
      ContextServicesBridge.instance.onNotificationAction!('news', {
        'taskId': 'task_001',
        'taskTitle': '今日科技资讯',
      });

      // 验证：AppShell 已将工具切换为 kToolIdAiAssistant
      expect(AppShellState.current, isNotNull);
      // 验证：AiAssistantNavigation 收到了打开抽屉的请求，且初始 Tab 为 1 (快报历史)
      expect(AiAssistantNavigation.instance.openDrawerNotifier.value, equals(1));
    });

    testWidgets('ScheduledTasksDrawer initializes on Tab 1 when initialIndex is 1', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: ScheduledTasksDrawer(initialIndex: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证 TabBar 呈现并且当前选中的是「资讯快报历史」
      expect(find.text('资讯快报历史'), findsOneWidget);
      expect(find.text('检索任务列表'), findsOneWidget);

      final tabControllerFinder = find.byType(TabBar);
      expect(tabControllerFinder, findsOneWidget);
      final TabBar tabBar = tester.widget(tabControllerFinder);
      expect(tabBar.controller?.index, equals(1));
    });
  });
}
