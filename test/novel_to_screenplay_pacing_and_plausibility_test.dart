import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/screenplay_quality_evaluator.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_preset_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('提示词中枢注册与插槽解析', () {
    test('内置预设清单包含所有新增核心模板', () {
      final presets = StudioPromptTemplate.builtinPresets;
      final ids = presets.map((p) => p.id).toSet();

      expect(ids.contains('screenplay_plausibility_rules'), isTrue);
      expect(ids.contains('screenplay_beat_pacing_rules'), isTrue);
      expect(ids.contains('storyboard_vertical_5d'), isTrue);
      expect(ids.contains('visual_prompt_assembly'), isTrue);
      expect(ids.contains('negative_prompt_library'), isTrue);
      expect(ids.contains('writers_room_master_extract'), isTrue);
      expect(ids.contains('writers_room_season_beats'), isTrue);
      expect(ids.contains('writers_room_dialogue'), isTrue);
    });

    test('resolveSystemPrompt 正确解析插槽变量', () {
      final prompt = AiConstraintEngine.resolveSystemPrompt(
        StudioAiTask.screenplayGeneration,
        slots: {
          'series_name': '测试仙侠大短剧',
          'production_type': 'drama',
        },
      );

      expect(prompt, isNotEmpty);
      expect(prompt, contains('【环境生态与社会常识推演'));
      expect(prompt, contains('【竖屏短剧高能节拍与微动作化法则】'));
    });

    test('scriptBreakdown5D 动态注入竖屏 9:16 工业规范', () {
      final prompt = AiConstraintEngine.resolveSystemPrompt(
        StudioAiTask.scriptBreakdown5D,
      );

      expect(prompt, contains('【竖屏 9:16 短剧视听工业铁律】'));
      expect(prompt, contains('单镜头肉身在场角色 STRICTLY ≤ 3 人'));
    });
  });

  group('环境常识与节拍质检门禁', () {
    test('闹市横尸无人围观触发 ScreenplayQualityEvaluator 穿帮警告', () {
      final now = DateTime.now();
      final episode = StudioEpisode(
        id: 'ep_test',
        seriesId: 'series_test',
        createdAt: now,
        updatedAt: now,
        index: 1,
        title: '长街血案',
        synopsis: '长街上躺着一具尸体',
        scenes: [
          DramaScene(
            id: 'sc_01',
            sceneNumber: 1,
            title: '长街正街',
            location: '城内繁华长街',
            setting: '外景',
            timeOfDay: '日景',
            atmosphere: '街道宽阔',
            beats: [
              DramaBeat(
                id: 'b_01',
                sceneId: 'sc_01',
                order: 1,
                name: '发现死者',
                action: '繁华长街地面上躺着一具死人尸体，主角快步走过。',
                dialogue: '',
              ),
            ],
          ),
        ],
      );

      final report = ScreenplayQualityEvaluator.evaluate(episode);
      final plausibilityIssues = report.issues.where(
        (i) => i.category == ScreenplayIssueCategory.environmentalAnomaly,
      );

      expect(plausibilityIssues, isNotEmpty);
      expect(plausibilityIssues.first.message, contains('公共开放空间'));
      expect(plausibilityIssues.first.message, contains('死伤异常'));
    });

    test('闹市横尸有人围观则不触发穿帮警告', () {
      final now = DateTime.now();
      final episode = StudioEpisode(
        id: 'ep_test_good',
        seriesId: 'series_test',
        createdAt: now,
        updatedAt: now,
        index: 1,
        title: '长街血案有人围观',
        synopsis: '长街上躺着一具尸体，路人围观',
        scenes: [
          DramaScene(
            id: 'sc_01',
            sceneNumber: 1,
            title: '长街正街',
            location: '城内繁华长街',
            setting: '外景',
            timeOfDay: '日景',
            atmosphere: '周围百姓惊慌围观议论',
            beats: [
              DramaBeat(
                id: 'b_01',
                sceneId: 'sc_01',
                order: 1,
                name: '发现死者',
                action: '繁华长街地面上躺着一具死人尸体，数十名路人百姓惊恐围观指点，低声议论纷纷。',
                dialogue: '',
              ),
            ],
          ),
        ],
      );

      final report = ScreenplayQualityEvaluator.evaluate(episode);
      final plausibilityIssues = report.issues.where(
        (i) => i.category == ScreenplayIssueCategory.environmentalAnomaly,
      );

      expect(plausibilityIssues, isEmpty);
    });

    test('分镜同框角色超过 3 人触发 C19 竖屏人数超载审查', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        shotSize: StudioShotSize.medium,
        mood: 'battle',
        function: ShotFunction.burst,
        actionZh: '四人拔剑对峙',
        dialogue: '受死吧！',
        characterIds: ['char_1', 'char_2', 'char_3', 'char_4'],
        sceneId: 'scene_01',
      );

      final now = DateTime.now();
      final episode = StudioEpisode(
        id: 'ep_test',
        seriesId: 'series_test',
        createdAt: now,
        updatedAt: now,
        index: 1,
        title: '对峙',
        synopsis: '四人对峙',
        shots: [shot],
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: [shot],
      );

      final c19Issues = report.issues.where((i) => i.ruleId == 'C19');
      expect(c19Issues, isNotEmpty);
      expect(c19Issues.first.message, contains('超过 3 人'));
    });
  });

  group('PromptAssembler 提示词装配', () {
    test('正确注入通用防崩负向词库', () {
      final assembled = PromptAssembler.buildShotPrompt(
        const PromptParts(
          actionZh: '姜七夜拔刀',
          styleTokens: '3D国漫，电影级光影',
        ),
      );

      expect(assembled.negative, contains('bad anatomy'));
      expect(assembled.negative, contains('deformed'));
    });
  });
}
