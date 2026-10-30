import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_shell.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/novel_database.dart';
import 'package:V8WorkToolbox/tools/novel_manager/services/novel_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  final manager = StudioProjectManager.instance;
  late NovelRepository novelRepo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('writers_room_persistence_test_');
    AppPaths.overrideRootForTesting(tempDir);
    novelRepo = NovelRepository.instance;
  });

  tearDown(() async {
    await NovelDatabase.instance.closeForTesting();
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('研讨室策划数据持久化与剧本工作台大纲桥接测试 (persist-writers-room-and-bridge-screenplay-workflow)', () {
    test('Task 1.1: saveWritersRoomData 与 readWritersRoomData 落盘与读取', () async {
      final series = await manager.createSeries(
        name: '修仙之逆天改命',
        productionType: StudioProductionType.drama,
        worldview: '九天十地，诸宗林立',
      );

      final dummyProfile = {
        'version': 1,
        'novel_id': 'novel_test_999',
        'novel_title': '修仙测试小说',
        'chapters_summary': '第一章至第十章',
        'master_plot': '少年被逐出门派，获得上古残卷后逆袭复仇。',
        'seasons_roadmap': [
          {
            'season': 1,
            'title': '破茧而出',
            'episodes_count': 12,
            'logline': '初入外门，在绝境中觉醒上古血脉',
          },
          {
            'season': 2,
            'title': '风起云涌',
            'episodes_count': 16,
            'logline': '离开宗门入世历练，结识红颜并斩杀强敌',
          },
        ],
        'macro_arcs': [
          {'title': '主角成长弧光', 'description': '从懦弱自卑到杀伐果断'},
        ],
        'must_keep': ['宗门大比废灵根逆袭', '藏经阁偶遇守阁长老'],
        'can_cut': ['冗长的药草辨识细节'],
        'can_modify': ['配角感情线适度前置'],
        'characters': [
          {'name': '林云', 'role': '主角', 'personality': '坚毅沉稳'},
          {'name': '苏晴', 'role': '女主', 'personality': '清冷孤傲'},
        ],
        'character_relations': [
          {'source': '林云', 'target': '苏晴', 'relation': '萍水相逢后暗生情愫'},
        ],
        'episodes': [
          {
            'episode': 1,
            'title': '废柴受辱',
            'synopsis': '林云在外门大比被陷害重伤，绝望中坠入后山寒潭。',
            'hook': '寒潭深处亮起猩红眼眸，古老的低语在他脑海响起。',
          },
          {
            'episode': 2,
            'title': '龙魂苏醒',
            'synopsis': '林云吸收残魂之力脱胎换骨，重返宗门立誓复仇。',
            'hook': '执事长老在暗处冷笑，已备下致命杀局。',
          },
        ],
      };

      // 保存策划案
      await manager.saveWritersRoomData(series.id, dummyProfile);

      // 验证物理文件存在
      final file = manager.writersRoomFile(series.id);
      expect(file.existsSync(), isTrue);

      // 读取并比对内容
      final loaded = await manager.readWritersRoomData(series.id);
      expect(loaded, isNotNull);
      expect(loaded!['novel_id'], equals('novel_test_999'));
      expect(loaded['master_plot'], contains('少年被逐出门派'));
      expect((loaded['seasons_roadmap'] as List).length, equals(2));
      expect((loaded['episodes'] as List).length, equals(2));
      expect(loaded['episodes'][0]['hook'], contains('寒潭深处亮起猩红眼眸'));
    });

    test('Task 2.1 & 2.2: novelId 严格绑定至 StudioSeries 并与原著章节序号对齐', () async {
      // 1. 在小说库中创建一本小说与两章
      final novel = NovelMetadata(
        id: 'novel_xianxia_link_01',
        title: '剑破九霄',
        author: '网络作者',
        status: NovelStatus.completed,
        genre: '玄幻',
        tags: const ['剑道', '热血'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await novelRepo.saveNovel(novel);
      await novelRepo.saveChapter(
        novelId: novel.id,
        chapterIndex: 1,
        title: '第一章 剑冢拔剑',
        content: '万柄残剑齐齐轰鸣，少年拔出了锈迹斑斑的铁剑。',
      );
      await novelRepo.saveChapter(
        novelId: novel.id,
        chapterIndex: 2,
        title: '第二章 初试锋芒',
        content: '一剑寒芒起，挑落门派大师兄。',
      );

      // 2. 创建剧集并持久化 novelId
      var series = await manager.createSeries(
        name: '剑破九霄短剧',
        productionType: StudioProductionType.drama,
        worldview: '以剑证道',
      );
      series = series.copyWith(novelId: novel.id);
      await manager.saveSeries(series);

      // 验证重新读取后 novelId 依然完好
      final reloadedSeries = manager.readSeries(series.id);
      expect(reloadedSeries, isNotNull);
      expect(reloadedSeries!.novelId, equals('novel_xianxia_link_01'));

      // 3. 验证通过 novelId 能够顺畅拉取原著小说与对应集数的章节
      final linkedNovel = await novelRepo.getNovel(reloadedSeries.novelId!);
      expect(linkedNovel, isNotNull);
      expect(linkedNovel!.title, equals('剑破九霄'));

      final chapters = await novelRepo.getChapterIndices(linkedNovel.id);
      expect(chapters.length, equals(2));
      // 分集 1 对应章节 1
      expect(chapters.any((c) => c.chapterIndex == 1), isTrue);
      // 分集 2 对应章节 2
      expect(chapters.any((c) => c.chapterIndex == 2), isTrue);
    });

    test('Task 3.1: 分集同步 synopsis 与 EpisodeMemory hook 完整保留且可关联', () async {
      final series = await manager.createSeries(
        name: '断章钩子测试剧',
        productionType: StudioProductionType.drama,
        worldview: '悬疑反转短剧',
      );

      // 创建第 1 集并设置 synopsis
      final createdResult = await manager.createEpisode(
        seriesId: series.id,
        title: '引子与杀局',
        synopsis: '调查员发现废弃工厂内的密室，死者正是三年前失踪的未婚妻。',
      );
      final ep = createdResult.episode;

      // 写入 EpisodeMemory
      await manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: ep.id,
        title: ep.title,
        summary: ep.synopsis,
        hook: '死者的手机突然屏幕亮起，屏幕上赫然显示一条来自调查员本人的未读短信。',
      );

      final updatedSeries = manager.readSeries(series.id);
      expect(updatedSeries, isNotNull);
      final mem = updatedSeries!.memories.where((m) => m.episodeId == ep.id).firstOrNull;
      expect(mem, isNotNull);
      expect(mem!.hook, contains('死者的手机突然屏幕亮起'));
      expect(mem.summary, contains('调查员发现废弃工厂内的密室'));
    });

    test('Task 4.1: StudioSession 广播更新时触发监听器重新拉取', () async {
      final session = StudioSession();
      int notifyCount = 0;
      session.addListener(() {
        notifyCount++;
      });

      final series = await manager.createSeries(
        name: '会话更新测试剧',
        productionType: StudioProductionType.drama,
      );

      session.select(series);
      expect(notifyCount, greaterThan(0));

      final prevCount = notifyCount;
      final updatedSeries = series.copyWith(name: '修改后的剧名');
      session.updateSeries(updatedSeries);
      expect(notifyCount, equals(prevCount + 1));
      expect(session.series?.name, equals('修改后的剧名'));
    });
  });
}
