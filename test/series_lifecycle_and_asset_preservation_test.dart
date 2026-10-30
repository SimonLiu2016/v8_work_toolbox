import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late StudioProjectManager manager;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_series_lifecycle_test_');
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

  group('StudioSeries 模型与重命名持久化', () {
    test('StudioSeries 序列化支持 ipId 并正确回落 resolvedIpId', () {
      final now = DateTime.now();
      final series = StudioSeries(
        id: 'series_001',
        name: '凡人修仙传·第一季',
        ipId: 'ip_fanren',
        worldview: '宏大修仙宇宙',
        createdAt: now,
        updatedAt: now,
      );

      expect(series.resolvedIpId, 'ip_fanren');
      final json = series.toJson();
      expect(json['ip_id'], 'ip_fanren');

      final deserialized = StudioSeries.fromJson(json);
      expect(deserialized.id, 'series_001');
      expect(deserialized.name, '凡人修仙传·第一季');
      expect(deserialized.ipId, 'ip_fanren');
      expect(deserialized.resolvedIpId, 'ip_fanren');
    });

    test('未指定 ipId 时 resolvedIpId 自动回退为自身 id', () {
      final now = DateTime.now();
      final series = StudioSeries(
        id: 'series_legacy',
        name: '老项目',
        createdAt: now,
        updatedAt: now,
      );

      expect(series.ipId, isEmpty);
      expect(series.resolvedIpId, 'series_legacy');
    });

    test('重命名剧集后 saveSeries 能正确落盘并被 readSeries 读取', () async {
      final series = await manager.createSeries(name: '原剧集名');
      expect(series.name, '原剧集名');

      final renamed = series.copyWith(name: '新修改的短剧名');
      await manager.saveSeries(renamed);

      final reloaded = manager.readSeries(series.id);
      expect(reloaded, isNotNull);
      expect(reloaded!.name, '新修改的短剧名');
    });
  });

  group('剧集制作产物精准删除与 IP 资产保护', () {
    test('删除剧集时清除剧本与分镜媒体，但保留角色卡与场景库', () async {
      // 1. 创建一部剧集
      final series = await manager.createSeries(
        name: '测试大短剧',
        worldview: '仙魔大战世界观',
      );

      // 2. 添加角色卡
      final char = CharacterCard(
        id: 'char_hanli',
        name: '韩立',
        descriptionZh: '身穿朴素长袍的青年修仙者',
        basePromptPositive: 'young cultivator Han Li',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(series.id, char);

      // 3. 添加场景卡
      final scene = SceneCard(
        id: 'scene_valley',
        name: '神手谷',
        descriptionZh: '清幽隐秘的山谷草药园',
        promptEn: 'secluded herbal valley',
        updatedAt: DateTime.now(),
      );
      await manager.saveScene(series.id, scene);

      // 4. 创建一集（包含剧本与分镜）
      final epRes = await manager.createEpisode(
        seriesId: series.id,
        title: '第一集：谷中少年',
        synopsis: '少年初入七玄门',
      );
      final episode = epRes.episode;
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '韩立正在药园采摘药草',
      );
      await manager.saveEpisode(episode.copyWith(shots: [shot]));

      // 验证创建成功
      final episodesBefore = await manager.listEpisodes(series.id);
      expect(episodesBefore, isNotEmpty);
      expect(episodesBefore.first.shots, isNotEmpty);

      final charsBefore = await manager.listCharacters(series.id);
      expect(charsBefore.any((c) => c.name == '韩立'), isTrue);

      final scenesBefore = await manager.listScenes(series.id);
      expect(scenesBefore.any((s) => s.name == '神手谷'), isTrue);

      // 5. 执行安全删除剧集
      await manager.deleteSeries(series.id);

      // 6. 验证：剧集从剧集库中彻底被移除，分集剧本和分镜物理文件已清空
      final seriesListAfter = await manager.listSeries();
      expect(seriesListAfter.any((s) => s.id == series.id), isFalse);

      final epDir = manager.episodesDir(series.id);
      expect(await epDir.exists(), isFalse);

      // 7. 关键验证：IP 主库中的角色卡与场景库完好无损地被持久化保留！
      final availableIps = await manager.listAvailableIps();
      expect(availableIps.any((ip) => ip.id == series.id || ip.name == '测试大短剧'), isTrue);

      final charsAfter = await manager.listCharacters(series.id);
      expect(charsAfter.any((c) => c.name == '韩立'), isTrue);

      final scenesAfter = await manager.listScenes(series.id);
      expect(scenesAfter.any((s) => s.name == '神手谷'), isTrue);
    });

    test('新剧集关联已有 IP 时可直接继承复用角色与场景资产', () async {
      // 1. 创建父 IP
      final parentSeries = await manager.createSeries(
        name: '斗罗宇宙',
        worldview: '武魂大陆觉醒',
      );
      final char = CharacterCard(
        id: 'char_tangsan',
        name: '唐三',
        descriptionZh: '蓝银草魂师',
        basePromptPositive: 'Tang San',
        updatedAt: DateTime.now(),
      );
      await manager.saveCharacter(parentSeries.id, char);

      // 2. 创建关联该 IP 的第二部衍生剧集
      final season2 = await manager.createSeries(
        name: '斗罗外传·海神篇',
        ipId: parentSeries.id,
      );

      expect(season2.ipId, parentSeries.id);
      expect(season2.worldview, '武魂大陆觉醒');

      // 3. 验证第二部剧集能直接读取到父 IP 的角色
      final inheritedChars = await manager.listCharacters(season2.id);
      expect(inheritedChars.any((c) => c.name == '唐三'), isTrue);
    });
  });
}
