import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/screenplay_panel.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_shell.dart';

/// spec: ai-video-studio/script-workshop · 全文文本编辑不丢失用户修改
///
/// 系统没有 markdown → DramaScene 的反向解析，文本模式的编辑只能落在
/// `screenplayText` 里。旧实现在切回结构化视图时无条件用旧 scenes 导出文本
/// 覆盖控制器——用户刚写的台词被静默冲掉。现在的契约是：检测到差异就先问。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('screenplay_text_mode_test');
    AppPaths.overrideRootForTesting(tempDir);
    manager.resetCachesForTesting();
  });

  tearDown(() {
    AppPaths.resetForTesting();
    manager.resetCachesForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  DramaScene sceneOf() => DramaScene(
    id: 'scene-1',
    sceneNumber: 1,
    title: '镇魔司大殿',
    location: '大殿',
    beats: [
      DramaBeat(
        id: 'beat-1',
        sceneId: 'scene-1',
        order: 1,
        name: '授刀',
        action: '东方诏将斩妖刀递与沈长青',
        dialogueSpeaker: '东方诏',
        dialogue: '斩妖除魔，护我人族！',
      ),
    ],
  );

  testWidgets('文本模式有修改时切回结构化视图弹确认', (tester) async {
    late StudioSeries series;
    late StudioEpisode episode;
    await tester.runAsync(() async {
      series = await manager.createSeries(name: '文本模式测试剧');
      final created = await manager.createEpisode(seriesId: series.id);
      episode = created.episode.copyWith(
        scenes: [sceneOf()],
        screenplayText: DramaScene.exportToMarkdown([sceneOf()]),
      );
      await manager.saveEpisode(episode);
    });

    final session = StudioSession();
    session.select(series);
    session.selectEpisode(manager.readEpisode(series.id, episode.id)!);

    await tester.runAsync(() async {
      await manager.listIdeaHistory(series.id);
      await manager.listEpisodes(series.id);
      await manager.listScenes(series.id);
      await manager.listCharacters(series.id);
    });

    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ScreenplayPanel(session: session),
        ),
      ),
    );
    await tester.pump();

    // 切到 Markdown 文本模式。
    await tester.tap(find.byTooltip('切换为 Markdown 文本模式'));
    await tester.pump();
    expect(find.byType(TextField), findsWidgets);

    // 在文本里写一句结构化数据里没有的话。
    await tester.enterText(
      find.byType(TextField).first,
      '用户手写的一句新台词',
    );
    await tester.pump();

    // 切回结构化视图：应弹确认而不是静默覆盖。
    await tester.tap(find.byTooltip('切换为结构化分场视图'));
    await tester.pumpAndSettle();

    expect(find.text('有未同步的文本修改'), findsOneWidget);
    expect(find.text('保留修改'), findsOneWidget);
    expect(find.text('丢弃修改'), findsOneWidget);
  });

  testWidgets('选保留修改后控制器内容不变', (tester) async {
    late StudioSeries series;
    late StudioEpisode episode;
    await tester.runAsync(() async {
      series = await manager.createSeries(name: '保留修改测试剧');
      final created = await manager.createEpisode(seriesId: series.id);
      episode = created.episode.copyWith(
        scenes: [sceneOf()],
        screenplayText: DramaScene.exportToMarkdown([sceneOf()]),
      );
      await manager.saveEpisode(episode);
    });

    final session = StudioSession();
    session.select(series);
    session.selectEpisode(manager.readEpisode(series.id, episode.id)!);

    await tester.runAsync(() async {
      await manager.listIdeaHistory(series.id);
      await manager.listEpisodes(series.id);
      await manager.listScenes(series.id);
      await manager.listCharacters(series.id);
    });

    await tester.binding.setSurfaceSize(const Size(1400, 2400));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ScreenplayPanel(session: session),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('切换为 Markdown 文本模式'));
    await tester.pump();
    const userText = '用户手写的一句新台词';
    await tester.enterText(find.byType(TextField).first, userText);
    await tester.pump();

    await tester.tap(find.byTooltip('切换为结构化分场视图'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留修改'));
    await tester.pumpAndSettle();

    // 对话框关闭，视图切回结构化分场视图（结构化视图不含 maxLines: null 的
    // 全屏编辑器），且用户的编辑没有被覆盖回结构化导出文本。
    expect(find.text('有未同步的文本修改'), findsNothing);
    expect(find.textContaining('### 第1场'), findsNothing);
  });
}
