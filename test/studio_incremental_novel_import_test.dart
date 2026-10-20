import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('studio_incremental_test');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDownAll(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('StudioProjectManager 增量小说导入与资产合并测试', () {
    test('mergeMasterAssets: 增量追加角色、场景与世界观，保留已有角色的提示词', () async {
      // 1. 创建新剧集
      final series = await manager.createSeries(
        name: '修仙传奇',
        productionType: StudioProductionType.drama,
        worldview: '仙凡两隔，弱肉强食。',
      );

      // 2. 事先手动录入一个角色（带有自定义正向 Prompt）
      await manager.saveCharacter(
        series.id,
        CharacterCard(
          id: 'char_hanli',
          name: '韩立',
          descriptionZh: '资质平庸但心志坚定的修仙者',
          basePromptPositive: 'masterpiece, best quality, young daoist holding small green bottle',
          updatedAt: DateTime.now(),
        ),
      );

      // 3. 模拟 Pass 1 提取的 IP 资产
      final masterExtraction = {
        'worldview': '宗门林立，尔虞我诈。',
        'style_tokens': '水墨修仙写意风',
        'characters': [
          {
            'name': '韩立',
            'role': '主角',
            'description': '更新后的生平：偶得神秘小绿瓶',
            'prompt_positive': 'generic prompt to be ignored if preserved',
          },
          {
            'name': '南宫婉',
            'role': '女主',
            'description': '掩月宗结丹期女修',
            'prompt_positive': 'fairy maiden, white veil',
          },
        ],
        'scenes': [
          {
            'name': '七玄门神手谷',
            'description': '药香弥漫的山谷茅屋',
            'prompt_en': 'peaceful mountain valley, herb garden',
          },
        ],
      };

      // 4. 执行增量合并
      final updatedSeries = await manager.mergeMasterAssets(
        seriesId: series.id,
        masterExtraction: masterExtraction,
      );

      // 验证世界观已增量追加，而非覆盖
      expect(updatedSeries.worldview, contains('仙凡两隔，弱肉强食。'));
      expect(updatedSeries.worldview, contains('宗门林立，尔虞我诈。'));
      expect(updatedSeries.styleTokens, contains('水墨修仙写意风'));

      // 验证角色库
      final chars = await manager.listCharacters(series.id);
      expect(chars.length, equals(2));

      final hanli = chars.firstWhere((c) => c.name == '韩立');
      // 已有角色的自定义 prompt 与已有外貌描述得到保护
      expect(hanli.basePromptPositive, equals('masterpiece, best quality, young daoist holding small green bottle'));
      expect(hanli.descriptionZh, equals('资质平庸但心志坚定的修仙者'));

      final nangong = chars.firstWhere((c) => c.name == '南宫婉');
      expect(nangong.descriptionZh, contains('掩月宗结丹期女修'));

      // 验证场景库
      final scenes = await manager.listScenes(series.id);
      expect(scenes.length, equals(1));
      expect(scenes.first.name, equals('七玄门神手谷'));
    });

    test('importChapterToEpisode: 单章导入至指定集，保留已有其他集数', () async {
      // 1. 创建剧集并已存在第 1 集
      final series = await manager.createSeries(
        name: '凡人修仙',
        productionType: StudioProductionType.drama,
      );
      final ep1Result = await manager.createEpisode(seriesId: series.id, title: '初入七玄门');

      // 2. 单章导入沉淀至第 2 集
      final masterExtraction = {
        'worldview': '魔道入侵越国修仙界。',
        'characters': [
          {
            'name': '墨大夫',
            'role': '反派',
            'description': '神手谷毒医',
          },
        ],
        'scenes': [
          {
            'name': '嘉元城',
            'description': '凡间大都市',
          },
        ],
      };

      const adaptedFullSynopsis = '【开局抓手】暴雨之夜，韩立推开神手谷密室木门，赫然发现墨大夫面色铁青，手中短刃寒光逼人。'
          '【矛盾推进】墨大夫步步紧逼逼问长春功第四层口诀，韩立借取药引为由退至药柜死角，暗中将毒粉藏于指缝周旋试探。'
          '【核心高潮】墨大夫骤然暴起施展鹰爪功锁喉，韩立生死一线间反手掷出毒粉迷其双目，二人近身扭打撞翻药架，短刃脱手刺入地面。'
          '【本集断点】墨大夫虽中剧毒却突然发出诡异怪笑，双目泛起渗人幽绿荧光，夺舍残魂破体而出悬浮半空。';

      await manager.importChapterToEpisode(
        seriesId: series.id,
        masterExtraction: masterExtraction,
        targetEpisodeIndex: 2,
        episodeTitle: '墨大夫的图谋',
        episodeSynopsis: adaptedFullSynopsis,
        episodeSummary: '【第2集前情】墨大夫图谋夺舍未果。',
        episodeHook: '长春功第四层的隐秘即将揭晓。',
      );

      // 验证剧集列表中包含第 1 集与第 2 集，原有第 1 集未被删除
      final episodes = await manager.listEpisodes(series.id);
      expect(episodes.length, equals(2));
      expect(episodes.any((e) => e.id == ep1Result.episode.id), isTrue);

      final ep2 = episodes.firstWhere((e) => e.title == '墨大夫的图谋');
      // 验证完整大纲（包含四个戏剧阶段，且字数 > 200 字）完整保存，无截断
      expect(ep2.synopsis, equals(adaptedFullSynopsis));
      expect(ep2.synopsis, contains('【开局抓手】'));
      expect(ep2.synopsis, contains('【核心高潮】'));
      expect(ep2.synopsis, contains('【本集断点】'));

      // 验证剧情记忆中包含了第 2 集总结与悬念
      final updatedSeries = manager.readSeries(series.id)!;
      expect(updatedSeries.memories.any((m) => m.summary.contains('墨大夫图谋夺舍未果')), isTrue);
      expect(updatedSeries.memories.any((m) => m.hook.contains('长春功第四层的隐秘即将揭晓')), isTrue);

      // 验证资产已增量注入
      final chars = await manager.listCharacters(series.id);
      expect(chars.any((c) => c.name == '墨大夫'), isTrue);
    });

    test('importChapterToEpisode: 写入 screenplayText 并在覆盖已有集时重置陈旧 shots', () async {
      final series = await manager.createSeries(
        name: '诛仙测试',
        productionType: StudioProductionType.anime3d,
      );

      // 创建第 1 集并注入一些旧 shots
      final ep1 = await manager.createEpisode(seriesId: series.id, title: '旧第1集');
      final episodeWithOldShots = ep1.episode.copyWith(
        shots: [
          const StudioShot(
            number: 1,
            durationSec: 4.0,
            shotSize: StudioShotSize.medium,
            mood: 'warm',
            function: ShotFunction.opening,
            actionZh: '旧动作描述',
            dialogue: '旧台词',
          ),
        ],
      );
      await manager.saveEpisode(episodeWithOldShots);

      // 导入新小说章节到第 1 集
      const newScreenplay = '### 第1场 草庙村（外景 / 黄昏）\n**动作**：张小凡走在乡间小路。';
      await manager.importChapterToEpisode(
        seriesId: series.id,
        masterExtraction: const {},
        targetEpisodeIndex: 1,
        episodeTitle: '草庙村惊变',
        episodeSynopsis: '草庙村突遭横祸，张小凡拜入青云门。' * 5,
        episodeSummary: '前情摘要',
        episodeHook: '结尾悬念',
        screenplayText: newScreenplay,
      );

      final reloaded = manager.readEpisode(series.id, ep1.episode.id)!;
      expect(reloaded.title, '草庙村惊变');
      expect(reloaded.screenplayText, newScreenplay);
      // 验证陈旧 shots 被重置清空，杜绝混淆
      expect(reloaded.shots, isEmpty);
    });
  });
}
