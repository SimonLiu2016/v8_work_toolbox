import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/screenplay_panel.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/studio_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('screenplay_novel_adapt_test');
    AppPaths.overrideRootForTesting(tempDir);
    manager.resetCachesForTesting();
  });

  tearDown(() {
    AppPaths.resetForTesting();
    manager.resetCachesForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  DramaScene sampleScene() => DramaScene(
        id: 'SC001',
        sceneNumber: 1,
        title: '青云门山门',
        location: '山门前',
        beats: [
          DramaBeat(
            id: 'B001',
            sceneId: 'SC001',
            order: 1,
            name: '相遇',
            action: '张小凡手握噬魂棍，仰望青云门山门。',
            dialogueSpeaker: '张小凡',
            dialogue: '师姐，我回来了。',
          ),
        ],
      );

  group('StudioSeries novelId 持久化与 copyWith', () {
    test('支持序列化和反序列化 novelId', () {
      final now = DateTime.now();
      final series = StudioSeries(
        id: 'series-novel-1',
        name: '诛仙短剧',
        novelId: 'novel-zhuxian-001',
        createdAt: now,
        updatedAt: now,
      );

      final json = series.toJson();
      expect(json['novel_id'], equals('novel-zhuxian-001'));

      final restored = StudioSeries.fromJson(json);
      expect(restored.novelId, equals('novel-zhuxian-001'));
      expect(restored.name, equals('诛仙短剧'));

      final cleared = restored.copyWith(clearNovelId: true);
      expect(cleared.novelId, isNull);
      expect(cleared.toJson().containsKey('novel_id'), isFalse);
    });
  });

  group('importChapterToEpisode 契约与剧本数据沉淀', () {
    test('单章改编能够完整持久化 ProtectedContract 与 scenes', () async {
      final series = await manager.createSeries(name: '凡人修仙短剧');
      final created = await manager.createEpisode(seriesId: series.id);
      final ep = created.episode;

      const contract = ProtectedContract(
        utterances: [
          ProtectedUtterance(
            id: 'u1',
            speaker: '韩立',
            text: '杀人放火厉飞雨，万人敬仰韩天尊。',
          ),
        ],
        facts: [
          ProtectedFact(
            id: 'f1',
            content: '掌天瓶能吸收日月精华凝聚绿液',
          ),
        ],
      );

      final scene = sampleScene();
      const markdown = '### 第 1 场 青云门山门\n\n张小凡手握噬魂棍，仰望青云门山门。\n\n张小凡: 师姐，我回来了。';

      final updatedSeries = await manager.importChapterToEpisode(
        seriesId: series.id,
        masterExtraction: const {},
        targetEpisodeIndex: ep.index,
        episodeTitle: '第 1 集 重返宗门',
        episodeSynopsis: '韩立易名重返宗门，暗中打探掌天瓶机密。',
        episodeSummary: '韩立进入宗门。',
        episodeHook: '黑衣人现身。',
        scenes: [scene],
        screenplayText: markdown,
        protectedContract: contract,
      );

      expect(updatedSeries.memories.length, equals(1));
      expect(updatedSeries.memories.first.title, equals('第 1 集 重返宗门'));

      final reloadedEp = manager.readEpisode(series.id, ep.id);
      expect(reloadedEp, isNotNull);
      expect(reloadedEp!.scenes.length, equals(1));
      expect(reloadedEp.scenes.first.title, equals('青云门山门'));
      expect(reloadedEp.screenplayText, equals(markdown));
      expect(reloadedEp.protectedContract.utterances.length, equals(1));
      expect(reloadedEp.protectedContract.utterances.first.text,
          equals('杀人放火厉飞雨，万人敬仰韩天尊。'));
      expect(reloadedEp.protectedContract.facts.first.content,
          equals('掌天瓶能吸收日月精华凝聚绿液'));
    });
  });

  group('ScreenplayPanel UI 交互与防误触拦截', () {
    testWidgets('非空场次触发重新生成时弹出防误触覆盖拦截对话框', (tester) async {
      late StudioSeries series;
      late StudioEpisode episode;
      await tester.runAsync(() async {
        series = await manager.createSeries(name: '防误触测试剧');
        final created = await manager.createEpisode(seriesId: series.id);
        episode = created.episode.copyWith(
          scenes: [sampleScene()],
          screenplayText: DramaScene.exportToMarkdown([sampleScene()]),
        );
        await manager.saveEpisode(episode);
      });

      final session = StudioSession();
      session.select(series);
      session.selectEpisode(manager.readEpisode(series.id, episode.id)!);

      await tester.runAsync(() async {
        await manager.listEpisodes(series.id);
        await manager.listScenes(series.id);
        await manager.listCharacters(series.id);
      });

      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ScreenplayPanel(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证已存在的场次显示在界面上
      expect(find.text('青云门山门'), findsOneWidget);
      expect(find.text('从小说正文生成剧本'), findsOneWidget);
      expect(find.text('根据大纲扩写'), findsOneWidget);

      // 点击「根据大纲扩写」，应弹出覆盖拦截警告对话框
      await tester.tap(find.text('根据大纲扩写'));
      await tester.pumpAndSettle();

      expect(find.text('重新生成将覆盖现有剧本'), findsOneWidget);
      expect(find.text('当前集已有编排场次，重新生成将覆盖现有剧本场次与节拍。是否继续？'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('继续并覆盖'), findsOneWidget);

      // 点击取消，弹窗关闭且场次未被清除
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(find.text('重新生成将覆盖现有剧本'), findsNothing);
      expect(find.text('青云门山门'), findsOneWidget);
    });

    testWidgets('空场次状态下中央空白区显示小说改编推荐主按钮与大纲次级按钮', (tester) async {
      late StudioSeries series;
      late StudioEpisode episode;
      await tester.runAsync(() async {
        series = await manager.createSeries(name: '空场次测试剧');
        final created = await manager.createEpisode(seriesId: series.id);
        episode = created.episode;
      });

      final session = StudioSession();
      session.select(series);
      session.selectEpisode(manager.readEpisode(series.id, episode.id)!);

      await tester.runAsync(() async {
        await manager.listEpisodes(series.id);
        await manager.listScenes(series.id);
        await manager.listCharacters(series.id);
      });

      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ScreenplayPanel(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('尚未生成剧本场次'), findsOneWidget);
      expect(find.textContaining('通道 A：原著章节精读改编'), findsOneWidget);
      expect(find.textContaining('通道 B：大纲 AI 快速推演'), findsOneWidget);
      expect(find.textContaining('手动从空白创建第一场'), findsOneWidget);
    });

    testWidgets('Markdown文本模式输入无分场长篇小说正文时浮现改编提示横幅', (tester) async {
      late StudioSeries series;
      late StudioEpisode episode;
      await tester.runAsync(() async {
        series = await manager.createSeries(name: '长文散文测试剧');
        final created = await manager.createEpisode(seriesId: series.id);
        episode = created.episode;
      });

      final session = StudioSession();
      session.select(series);
      session.selectEpisode(manager.readEpisode(series.id, episode.id)!);

      await tester.runAsync(() async {
        await manager.listEpisodes(series.id);
        await manager.listScenes(series.id);
        await manager.listCharacters(series.id);
      });

      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ScreenplayPanel(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到 Markdown 文本模式
      final modeToggle = find.byTooltip('切换为 Markdown 文本模式');
      expect(modeToggle, findsOneWidget);
      await tester.tap(modeToggle);
      await tester.pumpAndSettle();

      // 尚未输入长文本，提示横幅不出现
      expect(find.text('检测到小说正文内容（非结构化分场），是否一键交由 AI 改编为分场文学剧本？'), findsNothing);

      // 输入大于 500 字的纯小说正文（无分场标记）
      final novelProse = '青云门坐落于神州浩土中原，山势雄伟，连绵数百里。' * 25; // 超过 500 字
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, novelProse);
      await tester.pumpAndSettle();

      // 验证探测横幅与一键改编按钮浮现
      expect(find.text('检测到小说正文内容（非结构化分场），是否一键交由 AI 改编为分场文学剧本？'), findsOneWidget);
      expect(find.text('一键 AI 改编为剧本'), findsOneWidget);

      // 点击关闭提示，横幅被隐藏
      final closeButton = find.byTooltip('关闭提示');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.text('检测到小说正文内容（非结构化分场），是否一键交由 AI 改编为分场文学剧本？'), findsNothing);
    });
  });

  group('DramaBeat 道具与手持动作往返序列化', () {
    test('正确序列化与反序列化 props, holdingItem, holdingHand', () {
      final beat = DramaBeat(
        id: 'B001',
        sceneId: 'SC001',
        order: 1,
        name: '亮出信物',
        action: '姜七夜右手抽出淬毒短刃，左手紧握传家玉佩。',
        props: const ['淬毒短刃', '传家玉佩'],
        holdingItem: '淬毒短刃',
        holdingHand: 'right',
      );

      final json = beat.toJson();
      expect(json['props'], equals(['淬毒短刃', '传家玉佩']));
      expect(json['holding_item'], equals('淬毒短刃'));
      expect(json['holding_hand'], equals('right'));

      final restored = DramaBeat.fromJson(json);
      expect(restored.props, equals(['淬毒短刃', '传家玉佩']));
      expect(restored.holdingItem, equals('淬毒短刃'));
      expect(restored.holdingHand, equals('right'));
    });

    test('缺省道具与手持字段安全回退默认值', () {
      final legacyJson = {
        'id': 'B002',
        'scene_id': 'SC001',
        'order': 2,
        'action': '平视前行',
      };

      final beat = DramaBeat.fromJson(legacyJson);
      expect(beat.props, isEmpty);
      expect(beat.holdingItem, isEmpty);
      expect(beat.holdingHand, isEmpty);
    });
  });

  group('convertScenesToShots 道具匹配与手持映射', () {
    test('节拍中 props 与 holdingItem 正确匹配 PropCard 并填充 propIds 与 ShotContinuity', () {
      final now = DateTime.now();
      final prop1 = PropCard(id: 'prop-001', name: '青霜剑', updatedAt: now);
      final prop2 = PropCard(id: 'prop-002', name: '九天玄火鉴', updatedAt: now);
      final scene = DramaScene(
        id: 'SC001',
        title: '演武场',
        beats: [
          DramaBeat(
            id: 'B001',
            sceneId: 'SC001',
            order: 1,
            action: '陆雪琪右手拔出青霜剑，左手捏诀',
            props: ['青霜剑'],
            holdingItem: '青霜剑',
            holdingHand: 'right',
          ),
          DramaBeat(
            id: 'B002',
            sceneId: 'SC001',
            order: 2,
            action: '张小凡双手托举九天玄火鉴',
            props: ['玄火鉴'],
            holdingItem: '玄火鉴',
            holdingHand: 'both',
          ),
        ],
      );

      final shots = AiConstraintEngine.convertScenesToShots(
        [scene],
        props: [prop1, prop2],
      );

      expect(shots.length, equals(2));
      // B001
      expect(shots[0].propIds, contains('prop-001'));
      expect(shots[0].continuity.holdingRight, equals('青霜剑'));
      expect(shots[0].continuity.holdingLeft, isEmpty);

      // B002 模糊匹配 '玄火鉴' 到 '九天玄火鉴'，双手持
      expect(shots[1].propIds, contains('prop-002'));
      expect(shots[1].continuity.holdingRight, equals('玄火鉴'));
      expect(shots[1].continuity.holdingLeft, equals('玄火鉴'));
    });
  });
}
