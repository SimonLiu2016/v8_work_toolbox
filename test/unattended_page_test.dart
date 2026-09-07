import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/unattended_service.dart';
import 'package:V8WorkToolbox/tools/unattended/unattended_page.dart';
import 'package:V8WorkToolbox/tools/registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolRegistry Registration Tests', () {
    test('UnattendedApproverToolDefinition 成功注册在系统分类中', () {
      final tool = ToolRegistry.findById('unattended-approver');
      expect(tool, isNotNull);
      expect(tool?.title, '无人值守助手');
      expect(tool?.category, ToolCategory.system);
    });
  });

  group('UnattendedPage Widget Rendering Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('unattended_page_test_');
      final service = UnattendedService.instance;
      service.customClaudeSettingsPath = '${tempDir.path}/claude_settings.json';
      service.customAgyHooksPath = '${tempDir.path}/agy_hooks.json';
      service.customStateFilePath = '${tempDir.path}/state.json';
      service.customAuditFilePath = '${tempDir.path}/audit.jsonl';
      service.customBinDirPath = '${tempDir.path}/bin';

      await service.init();
      await service.disable();
    });

    tearDown(() async {
      final service = UnattendedService.instance;
      await service.disable();
      service.customClaudeSettingsPath = null;
      service.customAgyHooksPath = null;
      service.customStateFilePath = null;
      service.customAuditFilePath = null;
      service.customBinDirPath = null;

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('页面各功能区域正常布局渲染', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnattendedPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 验证标题与副标题存在
      expect(find.text('无人值守助手'), findsOneWidget);
      expect(find.textContaining('离开电脑时自动审批 AI 工具授权'), findsOneWidget);

      // 验证未激活状态时的卡片元素
      expect(find.text('常规人工确认模式 (自动审批已关闭)'), findsOneWidget);
      expect(find.text('一键开启无人值守'), findsOneWidget);
      expect(find.text('--:--:--'), findsOneWidget);

      // 验证时长预设 Chip 存在
      expect(find.text('30分钟'), findsOneWidget);
      expect(find.text('1小时'), findsOneWidget);
      expect(find.text('2小时'), findsOneWidget);
      expect(find.text('4小时'), findsOneWidget);
      expect(find.text('8小时过夜'), findsOneWidget);

      // 验证全局 Hook 诊断与硬地板
      expect(find.text('全局客户端 Hook 接入'), findsOneWidget);
      expect(find.text('机械安全硬地板 (绝对拦截)'), findsOneWidget);
      expect(find.textContaining('实时审批审计流水'), findsOneWidget);
    });

    testWidgets('点击一键开启无人值守后，UI 切换为激活状态并展现倒计时', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnattendedPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 点击开启
      await tester.tap(find.text('一键开启无人值守'));
      await tester.pumpAndSettle();

      // 验证状态切换为运行中
      expect(find.text('无人值守运行中 (自动放行安全操作)'), findsOneWidget);
      expect(find.text('关闭并恢复人审'), findsOneWidget);

      // 再次点击关闭
      await tester.tap(find.text('关闭并恢复人审'));
      await tester.pumpAndSettle();

      expect(find.text('常规人工确认模式 (自动审批已关闭)'), findsOneWidget);
      expect(find.text('一键开启无人值守'), findsOneWidget);
    });

    testWidgets('打开规则管理弹窗能正常展示', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: UnattendedPage(),
        ),
      );
      await tester.pumpAndSettle();

      final ruleBtn = find.text('规则管理');
      await tester.ensureVisible(ruleBtn);
      await tester.pumpAndSettle();

      await tester.tap(ruleBtn);
      await tester.pumpAndSettle();

      expect(find.text('安全黑名单正则表达式规则'), findsOneWidget);
      expect(find.text('恢复默认预设'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);

      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      expect(find.text('安全黑名单正则表达式规则'), findsNothing);
    });
  });
}
