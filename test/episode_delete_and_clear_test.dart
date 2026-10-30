import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StudioProjectManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_ep_delete_clear_test_');
    AppPaths.overrideRootForTesting(tempDir);
    manager = StudioProjectManager.instance;
    await manager.ensureBaseStructure();
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('分集快捷清理与末集删除 (add-clear-and-delete-last-episode-actions)', () {
    test('deleteLastEpisode 自动删除最大序号分集并级联清理剧情记忆', () async {
      // 1. 创建剧集及角色、场景资产（用于检验资产隔离性）
      final series = await manager.createSeries(
        name: '封神演义·宏大短剧',
        worldview: '殷商末年，神魔混战',
      );
      final character = CharacterCard(
        id: 'char_yangjian',
        name: '杨戬',
        descriptionZh: '三眼少年，银盔亮甲',
        basePromptPositive: 'young warrior Yang Jian',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, character);

      final scene = SceneCard(
        id: 'scene_chengtang',
        name: '陈塘关城楼',
        descriptionZh: '狂风暴雨中的古城楼',
        promptEn: 'ancient fortress in thunderstorm',
        updatedAt: DateTime.now(),
      );
      await manager.saveScene(series.id, scene);

      // 2. 创建 3 个连续分集
      final ep1 = (await manager.createEpisode(seriesId: series.id, title: '出山')).episode;
      final ep2 = (await manager.createEpisode(seriesId: series.id, title: '初战')).episode;
      final ep3 = (await manager.createEpisode(seriesId: series.id, title: '决战')).episode;

      // 注入前情记忆
      await manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: ep1.id,
        title: '出山',
        summary: '杨戬受命下山',
      );
      await manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: ep2.id,
        title: '初战',
        summary: '遭遇魔家四将',
      );
      await manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: ep3.id,
        title: '决战',
        summary: '九曲黄河阵破',
      );

      var episodes = await manager.listEpisodes(series.id);
      expect(episodes.length, 3);
      var currentSeries = manager.readSeries(series.id);
      expect(currentSeries!.memories.length, 3);

      // 3. 执行 deleteLastEpisode
      final deleted = await manager.deleteLastEpisode(series.id);
      expect(deleted, isNotNull);
      expect(deleted!.id, ep3.id);
      expect(deleted.index, 3);
      expect(deleted.title, '决战');

      // 4. 验证分集列表减少且第 3 集目录已被物理移除
      episodes = await manager.listEpisodes(series.id);
      expect(episodes.length, 2);
      expect(episodes.map((e) => e.id), containsAll([ep1.id, ep2.id]));
      expect(episodes.map((e) => e.id), isNot(contains(ep3.id)));

      final ep3Dir = manager.episodeDir(series.id, ep3.id);
      expect(await ep3Dir.exists(), isFalse);

      // 5. 验证剧集记忆中第 3 集记忆已被级联清理
      currentSeries = manager.readSeries(series.id);
      expect(currentSeries!.memories.length, 2);
      expect(currentSeries.memories.any((m) => m.episodeId == ep3.id), isFalse);
      expect(currentSeries.memories.any((m) => m.episodeId == ep1.id), isTrue);

      // 6. 验证 IP 资产库与角色完全不受影响（核心隔离保障）
      final chars = await manager.listCharacters(series.id);
      expect(chars.any((c) => c.id == character.id), isTrue);
      final scenes = await manager.listScenes(series.id);
      expect(scenes.any((s) => s.id == scene.id), isTrue);
    });

    test('clearAllEpisodes 彻底清空所有分集物理目录并重置记忆，且保护 IP 资产', () async {
      // 1. 创建剧集及资产
      final series = await manager.createSeries(
        name: '星际探索',
        worldview: '深空无垠',
      );
      final hero = CharacterCard(
        id: 'char_john',
        name: '宇航员约翰',
        descriptionZh: '资深宇航员',
        basePromptPositive: 'astronaut John',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, hero);

      await manager.createEpisode(seriesId: series.id, title: '启航');
      await manager.createEpisode(seriesId: series.id, title: '迷失');
      await manager.createEpisode(seriesId: series.id, title: '归航');

      expect((await manager.listEpisodes(series.id)).length, 3);

      // 2. 执行 clearAllEpisodes
      final clearedCount = await manager.clearAllEpisodes(series.id);
      expect(clearedCount, 3);

      // 3. 验证分集清空为 0
      final emptyList = await manager.listEpisodes(series.id);
      expect(emptyList, isEmpty);

      final currentSeries = manager.readSeries(series.id);
      expect(currentSeries!.memories, isEmpty);

      // 4. 新建分集自动从第 1 集重新顺番
      final newEp = (await manager.createEpisode(seriesId: series.id)).episode;
      expect(newEp.index, 1);
      expect(newEp.title, '第 1 集');

      // 5. 验证角色资产库不受清空影响
      final readChars = await manager.listCharacters(series.id);
      expect(readChars.length, 1);
      expect(readChars.first.id, hero.id);
    });
  });
}
