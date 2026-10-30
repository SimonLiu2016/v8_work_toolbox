import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('writers_room_materialization_test_');
    AppPaths.overrideRootForTesting(tempDir);
  });

  tearDown(() async {
    AiConstraintEngine.resetForTesting();
    AppPaths.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ChatResult chatOf(String text) => ChatResult(
    text: text,
    usedProviderId: 'deepseek',
    usedModel: 'deepseek-chat',
    routingTrace: const [],
  );

  group('分集独立无克隆与多季物化落盘测试 (fix-writers-room-dynamic-beats-and-multi-season-materialization)', () {
    test('Task 1: AI 动态节拍拒绝机械克隆拉伸，清洗 (节拍 X) 后缀并保留真实集数', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "season_title": "寒阳死囚",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "牢狱绝境", "episode_range": "1-2", "core_conflict": "生死逃生", "turning_point": "觉醒天赋"},
    {"arc_number": 2, "title": "杀出重围", "episode_range": "3-4", "core_conflict": "斩杀狱卒", "turning_point": "获得佩剑"}
  ],
  "episodes": [
    {"episode_number": 1, "title": "寒阳死囚 (节拍 1)", "conflict": "叶辰在死牢中苏醒，面临明日处斩危机", "characters": ["叶辰"], "hook": "锁链深处传来神秘震动", "duration_sec": 90},
    {"episode_number": 2, "title": "寒阳死囚 (节拍 2)", "conflict": "狱卒索贿施暴，叶辰暗中聚气反抗", "characters": ["叶辰", "狱卒王五"], "hook": "神秘玉佩突然发出温热微光", "duration_sec": 90},
    {"episode_number": 3, "title": "破茧破壁 (节拍 3)", "conflict": "玉佩灵力灌注，暗杀值守狱长夺钥", "characters": ["叶辰", "狱长赵六"], "hook": "警报声响彻整个黑狱通道", "duration_sec": 90},
    {"episode_number": 4, "title": "夺路狂飙", "conflict": "合围之下纵身跃下黑水深渊", "characters": ["叶辰"], "hook": "水底竟然浮现万年玄冰巨棺", "duration_sec": 90}
  ]
}
''');
      };

      final result = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '囚徒逆袭',
        seriesName: '绝世剑神',
        episodeCount: 4,
        targetDurationSec: 90,
      );

      final episodes = result.data['episodes'] as List;
      // 验证绝不人为线性拉伸/映射克隆为 80 集
      expect(episodes.length, 4);

      // 验证 "(节拍 X)" 机械后缀被彻底剥除
      expect(episodes[0]['title'], '寒阳死囚');
      expect(episodes[1]['title'], '寒阳死囚');
      expect(episodes[2]['title'], '破茧破壁');
      expect(episodes[3]['title'], '夺路狂飙');

      // 验证集数编号与独立性
      expect(episodes[0]['episode_number'], 1);
      expect(episodes[1]['episode_number'], 2);
      expect(episodes[2]['episode_number'], 3);
      expect(episodes[3]['episode_number'], 4);
      expect(episodes[0]['conflict'], contains('面临明日处斩危机'));
      expect(episodes[1]['conflict'], contains('狱卒索贿施暴'));
    });

    test('Task 2: 定稿同步支持多季物化衍生，独立季共享 resolvedIpId 与世界观并落盘策划案与剧集', () async {
      // 1. 创建第 1 季主剧集
      var s1 = await manager.createSeries(
        name: '寒门崛起',
        productionType: StudioProductionType.drama,
        worldview: '架空历史，权谋争锋',
      );
      s1 = s1.copyWith(novelId: 'novel_12345');
      await manager.saveSeries(s1);

      final sharedIpId = s1.resolvedIpId;
      expect(sharedIpId, isNotEmpty);

      // 2. 模拟定稿多季物化流程：给第 1 季写入分集与记忆钩子
      final s1Created = await manager.createEpisode(
        seriesId: s1.id,
        title: '第 1 集 · 寒门陋室',
        synopsis: '主角穿越至寒门陋室，面对逼债恶霸。',
      );
      await manager.upsertEpisodeMemory(
        seriesId: s1.id,
        episodeId: s1Created.episode.id,
        title: s1Created.episode.title,
        summary: s1Created.episode.synopsis,
        hook: '债主拔刀相向，门外传来县太爷传唤铜锣声。',
      );

      // 保存第 1 季研讨室策划案
      final profileS1 = {
        'version': 1,
        'novel_id': 'novel_12345',
        'season_number': 1,
        'season_title': '第1季',
        'seasons_roadmap': [
          {'season_number': 1, 'season_title': '第1季 · 科举扬名', 'episodes_count': 12},
          {'season_number': 2, 'season_title': '第2季 · 京城风云', 'episodes_count': 16},
          {'season_number': 3, 'season_title': '第3季 · 执掌天下', 'episodes_count': 20},
        ],
        'episodes': [
          {'episode_number': 1, 'title': '寒门陋室', 'conflict': '逼债', 'hook': '县太爷传唤'},
        ],
      };
      await manager.saveWritersRoomData(s1.id, profileS1);

      // 3. 物化衍生第 2 季与第 3 季
      final roadmap = profileS1['seasons_roadmap'] as List<Map<String, dynamic>>;
      for (int i = 1; i < roadmap.length; i++) {
        final seasonPlan = roadmap[i];
        final seasonNum = seasonPlan['season_number'] as int;
        final seasonTitle = seasonPlan['season_title'] as String;
        final targetSeriesName = '寒门崛起 · 第 $seasonNum 季';

        // 创建衍生季剧集并继承 novelId 与 ipId
        var derivedSeries = await manager.createSeries(
          name: targetSeriesName,
          productionType: s1.productionType,
          worldview: s1.worldview,
          ipId: sharedIpId,
        );
        derivedSeries = derivedSeries.copyWith(novelId: s1.novelId);
        await manager.saveSeries(derivedSeries);

        // 验证衍生季共享 IP 空间
        expect(derivedSeries.resolvedIpId, sharedIpId);
        expect(derivedSeries.worldview, s1.worldview);
        expect(derivedSeries.novelId, s1.novelId);

        // 写入研讨室快照
        final derivedProfile = Map<String, dynamic>.from(profileS1);
        derivedProfile['season_number'] = seasonNum;
        derivedProfile['season_title'] = seasonTitle;
        await manager.saveWritersRoomData(derivedSeries.id, derivedProfile);
        expect(manager.writersRoomFile(derivedSeries.id).existsSync(), isTrue);

        // 写入分集大纲骨架
        final epCount = seasonPlan['episodes_count'] as int;
        for (int epIdx = 1; epIdx <= epCount; epIdx++) {
          final createdEp = await manager.createEpisode(
            seriesId: derivedSeries.id,
            title: '第 $epIdx 集 · $seasonTitle-节拍$epIdx',
          );
          expect(createdEp.episode.seriesId, derivedSeries.id);
        }

        final seasonEpisodes = await manager.listEpisodes(derivedSeries.id);
        expect(seasonEpisodes.length, epCount);
      }

      // 4. 验证全部剧集项目
      final allSeries = await manager.listSeries();
      expect(allSeries.length, 3);
      final names = allSeries.map((s) => s.name).toList();
      expect(names, contains('寒门崛起'));
      expect(names, contains('寒门崛起 · 第 2 季'));
      expect(names, contains('寒门崛起 · 第 3 季'));

      // 验证第 2 季与第 3 季与第 1 季具有相同 resolvedIpId，可无缝共享所有角色与世界观
      for (final s in allSeries) {
        expect(s.resolvedIpId, sharedIpId);
      }
    });

    test('Task 3: 大集数 (> 20 集) 自动按大幕分批推演，防 4096 Token 截断并聚合完整全季', () async {
      int callIdx = 0;
      final progressLog = <String>[];

      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        callIdx++;
        if (callIdx == 1) {
          // 大幕规划
          return chatOf('''
{
  "season_title": "大奉打更人 · 第1季",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "牢狱脱困与初入打更人", "episode_range": "1-15", "core_conflict": "炼金秘方自救", "turning_point": "得魏渊赏识"},
    {"arc_number": 2, "title": "税银大案与云鹿书院", "episode_range": "16-30", "core_conflict": "侦破假银迷局", "turning_point": "名震京城"}
  ]
}
''');
        }

        if (callIdx == 2) {
          // 批次 1 (1~15)
          final eps = [
            for (int i = 1; i <= 15; i++)
              '{"episode_number": $i, "title": "第$i集·脱困", "conflict": "危机$i", "characters": ["许七安"], "hook": "钩子$i", "duration_sec": 90}'
          ].join(',');
          return chatOf('{"episodes": [$eps]}');
        }

        // 批次 2 (16~30)
        final eps = [
          for (int i = 16; i <= 30; i++)
            '{"episode_number": $i, "title": "第$i集·破案", "conflict": "案情$i", "characters": ["许七安", "魏渊"], "hook": "钩子$i", "duration_sec": 90}'
        ].join(',');
        return chatOf('{"episodes": [$eps]}');
      };

      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '打更人逆袭断案',
        seriesName: '大奉打更人',
        episodeCount: 30,
        targetDurationSec: 90,
        onProgress: (msg, prog) => progressLog.add(msg),
      );

      expect(callIdx, 3);
      final eps = res.data['episodes'] as List;
      expect(eps.length, 30);
      expect(eps.first['episode_number'], 1);
      expect(eps.last['episode_number'], 30);
      expect(eps.first['arc_name'], '牢狱脱困与初入打更人');
      expect(eps.last['arc_name'], '税银大案与云鹿书院');
      expect(progressLog.any((p) => p.contains('正在构建全季宏观大篇章结构')), isTrue);
      expect(progressLog.any((p) => p.contains('牢狱脱困与初入打更人')), isTrue);
      expect(progressLog.any((p) => p.contains('税银大案与云鹿书院')), isTrue);
    });

    test('Task 4: StudioEpisode 原著章节映射字段序列化与向后兼容反序列化', () {
      final now = DateTime.now();
      // 1. 序列化验证
      final ep = StudioEpisode(
        id: 'ep_test_1',
        seriesId: 'series_test',
        index: 1,
        title: '拜师入谷',
        synopsis: '拜入墨大夫门下',
        novelChapterRange: '1-3',
        novelChapterIndices: const [1, 2, 3],
        createdAt: now,
        updatedAt: now,
      );
      final json = ep.toJson();
      expect(json['novel_chapter_range'], '1-3');
      expect(json['novel_chapter_indices'], [1, 2, 3]);

      // 2. 正常反序列化验证
      final restored = StudioEpisode.fromJson(json);
      expect(restored.novelChapterRange, '1-3');
      expect(restored.novelChapterIndices, [1, 2, 3]);

      // 3. 历史遗留旧数据反序列化（缺省字段向后兼容）
      final legacyJson = {
        'id': 'ep_legacy',
        'series_id': 'series_test',
        'index': 5,
        'title': '旧分集',
        'synopsis': '大纲',
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };
      final legacyEp = StudioEpisode.fromJson(legacyJson);
      expect(legacyEp.novelChapterRange, '');
      expect(legacyEp.novelChapterIndices, isEmpty);
    });

    test('Task 5: parseChapterRange 智能解析与平滑插值兜底算法', () {
      // 1. 标准横杠/波浪线范围
      final r1 = AiConstraintEngine.parseChapterRange('1-3');
      expect(r1.rangeDesc, '1-3');
      expect(r1.indices, [1, 2, 3]);

      final r2 = AiConstraintEngine.parseChapterRange('第10章~第12章');
      expect(r2.rangeDesc, '10-12');
      expect(r2.indices, [10, 11, 12]);

      // 2. 逗号/顿号离散列表
      final r3 = AiConstraintEngine.parseChapterRange('1, 3, 5');
      expect(r3.rangeDesc, '1-5');
      expect(r3.indices, [1, 3, 5]);

      final r4 = AiConstraintEngine.parseChapterRange('第2章、第3章');
      expect(r4.rangeDesc, '2-3');
      expect(r4.indices, [2, 3]);

      // 3. 纯单数字
      final r5 = AiConstraintEngine.parseChapterRange('8');
      expect(r5.rangeDesc, '8');
      expect(r5.indices, [8]);

      // 4. 空输入结合全季章节平滑插值 (60集对应原著1~120章)
      final rEp1 = AiConstraintEngine.parseChapterRange(
        '',
        fallbackEpisodeIndex: 1,
        totalEpisodes: 60,
        seasonChaptersRange: '1-120',
      );
      expect(rEp1.indices, [1, 2]);
      expect(rEp1.rangeDesc, '1-2');

      final rEp60 = AiConstraintEngine.parseChapterRange(
        null,
        fallbackEpisodeIndex: 60,
        totalEpisodes: 60,
        seasonChaptersRange: '1-120',
      );
      expect(rEp60.indices, [119, 120]);
      expect(rEp60.rangeDesc, '119-120');

      // 5. 极端兜底 (无任何范围时回退为单集集序号)
      final rFallback = AiConstraintEngine.parseChapterRange('', fallbackEpisodeIndex: 7);
      expect(rFallback.rangeDesc, '7');
      expect(rFallback.indices, [7]);
    });

    test('Task 6: planWritersRoomSeasonBeats 自动生成并规整化每集原著章节映射', () async {
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        return chatOf('''
{
  "season_title": "凡人修仙 · 第1季",
  "target_duration_sec": 90,
  "macro_arcs": [
    {"arc_number": 1, "title": "拜师神手谷", "episode_range": "1-2", "chapter_range": "1-6", "core_conflict": "拜师学艺", "turning_point": "获得灵瓶"}
  ],
  "episodes": [
    {"episode_number": 1, "title": "神秘药园", "chapter_range": "1-3", "conflict": "墨大夫试探灵根", "characters": ["韩立", "墨大夫"], "hook": "暗门突然打开", "duration_sec": 90},
    {"episode_number": 2, "title": "长春功法", "chapter_range": "4-6", "conflict": "暗中苦修长春功", "characters": ["韩立"], "hook": "绿液滴落草药飞速生长", "duration_sec": 90}
  ]
}
''');
      };

      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: '凡人修仙路',
        seriesName: '凡人修仙传',
        episodeCount: 2,
        targetDurationSec: 90,
        adaptedChaptersRange: '1-6',
      );

      final episodes = res.data['episodes'] as List;
      expect(episodes.length, 2);
      expect(episodes[0]['chapter_range'], '1-3');
      expect(episodes[0]['chapter_indices'], [1, 2, 3]);
      expect(episodes[1]['chapter_range'], '4-6');
      expect(episodes[1]['chapter_indices'], [4, 5, 6]);

      // 持久化到剧集库并验证重新读取
      final series = await manager.createSeries(
        name: '凡人修仙传',
        productionType: StudioProductionType.drama,
      );
      final ep1 = StudioEpisode(
        id: 'ep_1',
        seriesId: series.id,
        index: 1,
        title: episodes[0]['title'] as String,
        synopsis: episodes[0]['conflict'] as String,
        novelChapterRange: episodes[0]['chapter_range'] as String,
        novelChapterIndices: (episodes[0]['chapter_indices'] as List).cast<int>(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await manager.saveEpisode(ep1);

      final loadedEps = await manager.listEpisodes(series.id);
      expect(loadedEps.length, 1);
      expect(loadedEps.first.novelChapterRange, '1-3');
      expect(loadedEps.first.novelChapterIndices, [1, 2, 3]);
    });
  });
}
