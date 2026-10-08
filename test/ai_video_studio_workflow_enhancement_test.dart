import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  late Directory tempDir;
  late StudioProjectManager manager;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('studio_workflow_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  setUp(() {
    manager = StudioProjectManager.instance;
    manager.resetCachesForTesting();
  });

  test('创意方案持久化与历史加载验证', () async {
    final series = await manager.createSeries(name: '创意测试剧集');

    final idea1 = IdeaDirection(
      id: 'idea-1',
      title: '赛博废墟侦探',
      hook: '在霓虹雨夜追查仿生人失踪案件',
      twist: '凶手竟是自己的复制人',
      pacing: '快节奏悬疑',
      strategy: '主打冷色霓虹美学',
      accepted: false,
      createdAt: DateTime.now(),
    );

    final idea2 = IdeaDirection(
      id: 'idea-2',
      title: '末日方舟',
      hook: '地核熄灭前的最后逃生',
      twist: '方舟其实并没有航行目标',
      pacing: '末日压迫感',
      strategy: '写实废土风格',
      accepted: true,
      createdAt: DateTime.now(),
    );

    await manager.saveIdeaHistory(series.id, [idea1, idea2]);

    final loaded = await manager.listIdeaHistory(series.id);
    expect(loaded.length, 2);
    expect(loaded[0].title, '赛博废墟侦探');
    expect(loaded[0].accepted, isFalse);
    expect(loaded[1].title, '末日方舟');
    expect(loaded[1].accepted, isTrue);
    expect(loaded[1].twist, '方舟其实并没有航行目标');
  });

  test('场景库包含中文描述与参考图持久化验证', () async {
    final series = await manager.createSeries(name: '场景测试剧集');

    final scene = SceneCard(
      id: 'scene-cyber-bar',
      name: '霓虹酒吧',
      descriptionZh: '昏暗地下酒吧，蓝色霓虹招牌闪烁，地面潮湿泛着微光',
      promptEn: 'cyberpunk dive bar, dim interior, glowing neon sign, wet floor reflections',
      referenceImages: ['/path/to/ref1.png', '/path/to/ref2.jpg'],
      updatedAt: DateTime.now(),
    );

    await manager.saveScene(series.id, scene);

    final scenes = await manager.listScenes(series.id);
    expect(scenes.length, 1);
    expect(scenes.first.id, 'scene-cyber-bar');
    expect(scenes.first.name, '霓虹酒吧');
    expect(scenes.first.descriptionZh, contains('昏暗地下酒吧'));
    expect(scenes.first.referenceImages.length, 2);
    expect(scenes.first.referenceImages.last, '/path/to/ref2.jpg');
  });

  test('多分集创建、递增与前情回顾维护', () async {
    final series = await manager.createSeries(name: '分集测试剧集');

    final ep1 = await manager.createEpisode(seriesId: series.id);
    expect(ep1.episode.index, 1);
    expect(ep1.episode.title, '第 1 集');

    await manager.upsertEpisodeMemory(
      seriesId: series.id,
      episodeId: ep1.episode.id,
      title: ep1.episode.title,
      summary: '主角在酒吧收到神秘信件',
      hook: '窗外出现黑衣人身影',
      shotCount: 5,
    );

    final ep2 = await manager.createEpisode(seriesId: series.id);
    expect(ep2.episode.index, 2);
    expect(ep2.episode.title, '第 2 集');
    expect(ep2.memoryContext, contains('主角在酒吧收到神秘信件'));
    expect(ep2.memoryContext, contains('窗外出现黑衣人身影'));

    final allEpisodes = await manager.listEpisodes(series.id);
    expect(allEpisodes.length, 2);
    expect(allEpisodes.map((e) => e.index).toList(), [1, 2]);
  });

  test('分镜场景提示词联动 PromptAssembler 注入验证', () {
    final scene = SceneCard(
      id: 'scene-alley',
      name: '狭窄暗巷',
      promptEn: 'narrow dark alley, damp brick walls, atmospheric mist',
      updatedAt: DateTime.now(),
    );

    final parts = PromptParts(
      styleTokens: 'cinematic 35mm film',
      shotSize: 'close-up shot',
      mood: 'noir lighting',
      shotFunction: 'establishing view',
      scene: scene,
      cameraMove: 'slow dolly zoom',
    );

    final assembled = PromptAssembler.buildShotPrompt(parts);
    expect(assembled.positive, contains('narrow dark alley'));
    expect(assembled.positive, contains('damp brick walls'));
    expect(assembled.positive, contains('cinematic 35mm film'));
    expect(assembled.positive, contains('slow dolly zoom'));
  });
}
