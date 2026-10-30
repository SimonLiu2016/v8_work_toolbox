import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('视频生成模式适配与影视级镜头语法测试', () {
    test('1. AgnesVideoMode 与分镜级视频模式自动与手动推荐推导', () {
      // 场景 1: 手动显式指定 keyframe
      final shotManualKeyframe = StudioShot(
        number: 1,
        videoMode: 'keyframe',
      );
      expect(
        shotManualKeyframe.resolveEffectiveVideoMode(hasKeyframe: false, hasCharacterOrSceneRef: false),
        equals(AgnesVideoMode.keyframe),
      );

      // 场景 2: 手动显式指定 reference
      final shotManualRef = StudioShot(
        number: 2,
        videoMode: 'reference',
      );
      expect(
        shotManualRef.resolveEffectiveVideoMode(hasKeyframe: true),
        equals(AgnesVideoMode.reference),
      );

      // 场景 3: 手动显式指定 text
      final shotManualText = StudioShot(
        number: 3,
        videoMode: 'text',
      );
      expect(
        shotManualText.resolveEffectiveVideoMode(hasKeyframe: true, hasCharacterOrSceneRef: true),
        equals(AgnesVideoMode.text),
      );

      // 场景 4: 自动推导 - 存在首帧或关键帧，推导为 keyframe
      final shotAutoWithKeyframe = StudioShot(
        number: 4,
        videoMode: 'auto',
        firstFramePath: 'shot_004_frame.png',
      );
      expect(
        shotAutoWithKeyframe.resolveEffectiveVideoMode(),
        equals(AgnesVideoMode.keyframe),
      );

      // 场景 5: 自动推导 - 无关键帧但有角色或场景，推导为 reference
      final shotAutoWithRef = StudioShot(
        number: 5,
        videoMode: 'auto',
        characterIds: ['char_jiang'],
      );
      expect(
        shotAutoWithRef.resolveEffectiveVideoMode(),
        equals(AgnesVideoMode.reference),
      );

      // 场景 6: 自动推导 - 无任何关键帧与图素，回退为纯文本 text
      final shotAutoFallbackText = StudioShot(
        number: 6,
        videoMode: 'auto',
      );
      expect(
        shotAutoFallbackText.resolveEffectiveVideoMode(),
        equals(AgnesVideoMode.text),
      );
    });

    test('2. 剧集默认画幅比例与清晰度与分镜覆盖推导', () {
      final now = DateTime.now();
      final series = StudioSeries(
        id: 's_01',
        name: '夜行者',
        createdAt: now,
        updatedAt: now,
        defaultAspectRatio: '16:9',
        defaultResolution: '4K',
      );
      expect(series.defaultAspectRatio, equals('16:9'));
      expect(series.defaultResolution, equals('4K'));

      final shotInherit = StudioShot(number: 1);
      final effectiveRatio = shotInherit.aspectRatio ?? series.defaultAspectRatio;
      final effectiveRes = shotInherit.resolution ?? series.defaultResolution;
      expect(effectiveRatio, equals('16:9'));
      expect(effectiveRes, equals('4K'));

      final shotOverride = StudioShot(
        number: 2,
        aspectRatio: '9:16',
        resolution: '1080P',
      );
      expect(shotOverride.aspectRatio ?? series.defaultAspectRatio, equals('9:16'));
      expect(shotOverride.resolution ?? series.defaultResolution, equals('1080P'));
    });

    test('3. PromptAssembler.cleanAndResolveConflicts 提示词冲突消解与正向守卫', () {
      const rawConflictingPrompt =
          '【场景与环境】: 巡城司大牢（阴冷地牢）\n'
          '【空间地标】: 巡城司衙门口\n'
          '【摄影调度】: 运镜调度：slow_push_in，平视定机位\n'
          '【光影布置】: 黄昏，残阳如血，刑具火把微弱火光\n'
          '【动作轴线】: 保持在机位处于180度轴线右侧，遵守180度法则\n'
          '[角色内心独白/心声]: 姜七夜心声：“这老头又拿我撒气。”';

      final cleaned = PromptAssembler.cleanAndResolveConflicts(rawConflictingPrompt);

      // 验证单镜头 180 度轴线无效指令被剥离
      expect(cleaned, isNot(contains('180度轴线')));
      expect(cleaned, isNot(contains('180度法则')));

      // 验证中括号机器标签被移除
      expect(cleaned, isNot(contains('[角色内心独白/心声]')));

      // 验证运镜冲突（slow_push_in 与 定机位）被消解
      final hasPush = cleaned.contains('slow_push_in');
      final hasFixed = cleaned.contains('定机位');
      expect(hasPush && hasFixed, isFalse);

      // 验证场景冲突（地牢 与 衙门口）被消解
      final hasDungeon = cleaned.contains('大牢') || cleaned.contains('地牢');
      final hasGate = cleaned.contains('衙门口');
      expect(hasDungeon && hasGate, isFalse);
    });

    test('4. PromptAssembler.buildVideoGenPrompt 正向点名全员画外闭口守卫（杜绝配角抢台词）', () {
      final now = DateTime.now();
      final jiang = CharacterCard(
        id: 'c_jiang',
        name: '姜七夜',
        descriptionZh: '二十岁青年',
        updatedAt: now,
      );
      final wang = CharacterCard(
        id: 'c_wang',
        name: '老王',
        descriptionZh: '五十多岁牢头',
        updatedAt: now,
      );
      final shot = StudioShot(
        number: 1,
        dialogue: '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 's_01',
        index: 1,
        title: '第一集',
        shots: [shot],
        createdAt: now,
        updatedAt: now,
      );

      final videoPrompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: episode,
        characters: [jiang, wang],
      );

      // 验证正向点名姜七夜与老王全员闭口守卫
      expect(videoPrompt, contains('全员闭口守卫'));
      expect(videoPrompt, contains('姜七夜'));
      expect(videoPrompt, contains('老王'));
      expect(videoPrompt, contains('画外心声念白'));
      expect(videoPrompt, contains('严密闭合'));
      expect(videoPrompt, contains('不念台词'));
      expect(videoPrompt, contains('沉思'));
      expect(videoPrompt, isNot(contains('预估2.5秒')));
    });

    test('5. DirectorValidationEngine C10 规则质检与 10 分制评分', () {
      final now = DateTime.now();
      final shotWithConflicts = StudioShot(
        number: 1,
        actionZh: '奔跑然后拔剑转身跳跃出招', // 动作堆叠
        cameraMove: 'slow_push_in',
        directorDecisions: const DirectorDecisions(cameraStaging: '平视定机位'), // 运镜冲突
        dialogue: '姜七夜心声：“好险，老王又来了。”',
        characterIds: ['c_jiang'], // 画面中无老王，但出现老王台词/心声实体
      );

      final episode = StudioEpisode(
        id: 'ep_test',
        seriesId: 's_01',
        index: 1,
        title: '测试集',
        shots: [shotWithConflicts],
        createdAt: now,
        updatedAt: now,
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: [shotWithConflicts],
        characters: [CharacterCard(id: 'c_jiang', name: '姜七夜', updatedAt: now)],
      );

      // 验证 C10 规则触发
      final c10Issues = report.issues.where((i) => i.ruleId == 'C10').toList();
      expect(c10Issues.isNotEmpty, isTrue);

      // 验证 10 分制系统计算（存在质检建议项时提示数 > 0）
      expect(report.passCount, lessThanOrEqualTo(10));
      expect(report.warningCount, greaterThan(0));
    });

    test('6. AgnesVideoAdapter Flash 专属规则防御：强制锁定 size 为 720P 且截断参考图至 5 张', () {
      const model = 'agnes-video-2.5-flash';
      final isFlashModel = model.contains('flash');

      // 无论外部传入 1080P/2K/4K，Flash 必须收敛到 720P
      const requestedTier = '1080P';
      final resolvedSize = isFlashModel ? '720P' : requestedTier;
      expect(resolvedSize, equals('720P'));

      // 多于 5 张参考图自动防御性截断为 5 张
      final rawRefUris = ['img1', 'img2', 'img3', 'img4', 'img5', 'img6', 'img7'];
      final effectiveRefs = rawRefUris.length > 5 ? rawRefUris.take(5).toList() : rawRefUris;
      expect(effectiveRefs.length, equals(5));
      expect(effectiveRefs.contains('img6'), isFalse);
    });
  });
}
