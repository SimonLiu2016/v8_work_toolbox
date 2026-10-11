import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/components/app_components.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/services/toonflow_asset_bridge.dart';
import 'package:V8WorkToolbox/tools/toonflow_studio/ui/toonflow_asset_bridge_panel.dart';

/// 资产桥面板的契约测试（spec: 导回的扫描与归集 / 写画布内容的权限边界）。
///
/// 页面级测试只能看到「剧集库为空」的分支，这里用真实剧集数据把选择器跑起来，
/// 才能验证 spec 真正关心的两件事：
/// 1. 未选中集时，导出/扫描/归集全部禁用，且界面说明「不猜测目标集」；
/// 2. 容器未运行时同样禁用——工作区归容器管，容器不在时导出的东西打不开。
void main() {
  late Directory tempDir;
  late StudioProjectManager manager;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('tf_bridge_ui');
    AppPaths.overrideRootForTesting(tempDir);
    manager = StudioProjectManager.instance;
    // 造一个剧集 + 一集：选择器有东西可选，_hasTarget 仍为 false。
    final series = await manager.createSeries(name: 'UI 验证剧集');
    await manager.createEpisode(seriesId: series.id, title: '来客');
  });

  tearDown(() {
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Widget wrap() => MaterialApp(
    theme: AppTheme.darkTheme,
    home: const Scaffold(body: ToonflowAssetBridgePanel()),
  );

  /// 等面板的 `_loadSeries()` 落地。列表加载是 async 的，不 pump 就还是空态。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text('剧集库是空的').evaluate().isEmpty) break;
    }
  }

  testWidgets('剧集选择器列出真实剧集', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('剧集库是空的'), findsNothing);
    expect(find.text('剧集'), findsOneWidget);
    expect(find.text('集'), findsOneWidget);
  });

  testWidgets('未选中集时三个动作全禁用，并说明不猜测目标集', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, '导出')).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, '扫描新视频'))
          .onPressed,
      isNull,
    );
    // 没有候选可勾选时归集按钮同样禁用。
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, '归集选中'))
          .onPressed,
      isNull,
    );

    // spec: 未选择集时不猜测目标。这句话必须出现在界面上，而不是只在文档里。
    expect(find.textContaining('不猜测目标集'), findsOneWidget);
  });

  testWidgets('容器未运行时给出醒目提示', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    // 面板不猜容器状态，直接听 compose service 单例；测试里它必然是 idle。
    expect(find.textContaining('容器未运行'), findsOneWidget);
    expect(find.byType(AppBanner), findsWidgets);
  });

  testWidgets('选中集后导出按钮解禁（容器未运行仍禁用）', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    // 选剧集。tap 要落在 DropdownButton 本体上——label 是普通 Text，点它不
    // 会展开 overlay。
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    final seriesItem = find.text('UI 验证剧集');
    expect(seriesItem, findsWidgets,
        reason: 'overlay 里应出现剧集选项');
    await tester.tap(seriesItem);
    await tester.pumpAndSettle();

    // 选集（等 _loadEpisodes 落地）。
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    final episodeItem = find.textContaining('第 1 集');
    expect(episodeItem, findsWidgets, reason: 'overlay 里应出现集选项');
    await tester.tap(episodeItem);
    await tester.pumpAndSettle();

    // 已选中目标集：禁用理由只剩「容器未运行」。
    expect(find.textContaining('不猜测目标集'), findsNothing);
    expect(
      tester.widget<AppButton>(find.widgetWithText(AppButton, '导出')).onPressed,
      isNull,
      reason: '容器未运行时导出打不开工作区，仍须禁用',
    );
  });

  testWidgets('归集目标开关默认片段级', (tester) async {
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('归集为片段（segments/）'), findsOneWidget);
  });

  testWidgets('导出报告明确说明未创建连线、未触发生成', (tester) async {
    // spec: 写画布内容的权限边界——报告必须说清"没做什么"，否则用户以为
    // 漫剧已经在生成了。
    const result = ExportResult(
      ok: true,
      workspaceDir: '/tmp/toonflow_data/workspaces/s1',
      writtenFiles: <String>['画布1.json', 'assets/n1/content.md'],
      skippedNotes: <String>['角色「沈舟」没有参考图'],
    );

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: ExportReportCard(result: result)),
    ));
    await tester.pump();

    expect(find.text('已写入 2 个文件'), findsOneWidget);
    expect(find.textContaining('未创建任何连线'), findsOneWidget);
    expect(find.textContaining('未触发生成'), findsOneWidget);
    expect(find.textContaining('用它的 Agent 完成连线与生成'), findsOneWidget);
    // 跳过提示也要出现在报告里，不能只写进日志。
    expect(find.textContaining('没有参考图'), findsOneWidget);
  });
}
