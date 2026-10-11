import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/components/app_components.dart' show AppButton;
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/ui/toonflow_studio_page.dart';

/// 工具页面的 UI 契约测试（spec: 容器启停与状态呈现 / 数据位置说明）。
///
/// 断言的是 spec 里能机械验证的三件事：
/// 1. 未就绪时「打开工作台」必须禁用；
/// 2. 数据位置卡必须包含 settings.json 的密钥边界声明；
/// 3. 配置卡字段齐全。
void main() {
  setUp(() {
    final tempDir = Directory.systemTemp.createTempSync('tf_ui');
    AppPaths.overrideRootForTesting(tempDir);
    addTearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
  });

  Widget wrap() => MaterialApp(
    theme: AppTheme.darkTheme,
    home: const ToonflowStudioPage(),
  );

  group('页面契约', () {
    testWidgets('未就绪时「打开工作台」禁用', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      final finder = find.widgetWithText(AppButton, '打开工作台');
      expect(finder, findsOneWidget);
      final button = tester.widget<AppButton>(finder);
      expect(button.onPressed, isNull,
          reason: '容器未就绪时不能打开工作台');
    });

    testWidgets('状态徽章显示「未启动」', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('未启动'), findsOneWidget);
    });

    testWidgets('数据位置卡含 settings.json 密钥边界声明', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      // spec 要求这条声明出现在用户首次进入即可见的位置，而不是仅存在于文档。
      expect(
        find.textContaining('settings.json'),
        findsWidgets,
        reason: '密钥边界声明必须可见',
      );
      expect(
        find.textContaining('不读取'),
        findsWidgets,
      );
    });

    testWidgets('配置卡字段齐全', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('Compose 工程目录'), findsOneWidget);
      expect(find.text('HTTP 端口'), findsOneWidget);
      expect(find.text('bun 镜像站'), findsOneWidget);
      expect(find.text('应用退出时停止容器'), findsOneWidget);
    });

    testWidgets('构建区提示首次构建耗时', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      // spike 实测 13 分钟，UI 必须提前告知，否则用户以为卡死。
      expect(find.textContaining('13 分钟'), findsOneWidget);
    });

    testWidgets('能力边界说明不可折叠且默认可见', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.text('能力边界'), findsOneWidget);
      expect(find.textContaining('不内嵌'), findsOneWidget);
      // 不出现 ExpansionTile 这类可折叠容器。
      expect(find.byType(ExpansionTile), findsNothing);
    });

    testWidgets('Docker Desktop 按钮始终可点', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      final finder = find.widgetWithText(AppButton, 'Docker Desktop');
      expect(finder, findsOneWidget);
      final button = tester.widget<AppButton>(finder);
      expect(button.onPressed, isNotNull,
          reason: '用户随时需要能跳到 Docker Desktop 排查');
    });
  });

  group('资产桥面板契约', () {
    testWidgets('面板出现在工具页上', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      // AppSectionHeader 会把标题 toUpperCase：中文不受影响，英文会变大写。
      expect(find.text('资产桥'), findsOneWidget);
      expect(find.text('导出到 TOONFLOW'), findsOneWidget);
      expect(find.text('从 TOONFLOW 归集'), findsOneWidget);
    });

    testWidgets('容器未就绪时导出与扫描都禁用', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();

      // 未选中集已足以禁用；这里额外锁死「容器没跑也不给导」。
      expect(
        tester.widget<AppButton>(find.widgetWithText(AppButton, '导出')).onPressed,
        isNull,
        reason: '容器不在时导出的工作区打不开',
      );
      expect(
        tester
            .widget<AppButton>(find.widgetWithText(AppButton, '扫描新视频'))
            .onPressed,
        isNull,
      );
    });

    // 「不猜测目标集」与导出报告的权限边界文案，需要真实剧集数据才能走到
    // 对应分支，覆盖在 toonflow_asset_bridge_panel_test.dart。这里只锁面板
    // 在场——页面级测试的数据目录是空的，走的是「剧集库是空的」分支。
  });
}
