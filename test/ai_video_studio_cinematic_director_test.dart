import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('AI 影视导演视听语法与分镜无损透传测试', () {
    test('DramaBeat 包含视听导演维度字段且支持序列化', () {
      final beat = DramaBeat(
        id: 'B01',
        sceneId: 'SC001',
        order: 1,
        name: '三楼抛鸡',
        action: '姜七夜从三楼窗台信手将烧鸡掷向长街',
        dialogue: '尝尝醉仙楼的招牌烧鸡',
        dialogueSpeaker: '姜七夜',
        voiceType: UtteranceVoiceType.dialogue,
        shotSize: 'full',
        cameraStaging: '高角度俯拍（三楼向下俯视街道）',
        cameraMove: 'pan_down_follow',
        screenPosition: '画面上方窗台面向下方',
        gazeDirection: '俯视街面',
      );

      final json = beat.toJson();
      expect(json['shot_size'], 'full');
      expect(json['camera_staging'], '高角度俯拍（三楼向下俯视街道）');
      expect(json['camera_move'], 'pan_down_follow');
      expect(json['screen_position'], '画面上方窗台面向下方');
      expect(json['gaze_direction'], '俯视街面');

      final deserialized = DramaBeat.fromJson(json);
      expect(deserialized.shotSize, 'full');
      expect(deserialized.cameraStaging, '高角度俯拍（三楼向下俯视街道）');
      expect(deserialized.cameraMove, 'pan_down_follow');
      expect(deserialized.screenPosition, '画面上方窗台面向下方');
      expect(deserialized.gazeDirection, '俯视街面');
    });

    test('convertScenesToShots 无损透传 AI 导演镜头决策并格式化内心 OS', () {
      final scene = DramaScene(
        id: 'SC001',
        sceneNumber: 1,
        title: '长街天人居',
        location: '长街天人居外',
        setting: '外景',
        timeOfDay: '日景',
        atmosphere: '晴朗长街，微风轻拂',
        primaryLightWorldDirection: '南向正午强日光',
        landmarks: const ['天人居三楼窗台', '青石板街面'],
        characterIds: const ['姜七夜', '余小白'],
        dramaticObjective: '长街截击',
        entryState: '姜七夜凭栏饮酒',
        exitState: '烧鸡落入余小白剑鞘',
        sceneCardId: '',
        beats: [
          const DramaBeat(
            id: 'B01',
            sceneId: 'SC001',
            order: 1,
            name: '三楼俯掷',
            action: '姜七夜从三楼窗台向下掷出烧鸡',
            dialogue: '接好了！',
            dialogueSpeaker: '姜七夜',
            voiceType: UtteranceVoiceType.dialogue,
            shotSize: 'long',
            cameraStaging: '三楼俯视俯角中景',
            cameraMove: 'dramatic_crane_down',
            screenPosition: '画面上方窗沿',
            gazeDirection: '俯视街面',
          ),
          const DramaBeat(
            id: 'B02',
            sceneId: 'SC001',
            order: 2,
            name: '心声思忖',
            action: '余小白仰头凝视坠落之物，眼神微敛',
            dialogue: '这小子身手果然不凡',
            dialogueSpeaker: '余小白',
            voiceType: UtteranceVoiceType.innerVoice,
            shotSize: 'close_up',
            cameraStaging: '地面低角仰拍特写',
            cameraMove: 'slow_push_in',
            screenPosition: '画面中心偏左',
            gazeDirection: '仰视上方天空',
          ),
        ],
      );

      final shots = AiConstraintEngine.convertScenesToShots([scene]);
      expect(shots.length, 2);

      // 验证第 1 镜透传：不是平视也不是 static
      final shot1 = shots[0];
      expect(shot1.shotSize, StudioShotSize.long);
      expect(shot1.cameraMove, 'dramatic_crane_down');
      expect(shot1.directorDecisions.cameraStaging, '三楼俯视俯角中景');
      expect(shot1.continuity.screenPosition, '画面上方窗沿');
      expect(shot1.continuity.gazeDirection, '俯视街面');
      expect(shot1.dialogue, '姜七夜：“接好了！”');
      expect(shot1.voiceType, UtteranceVoiceType.dialogue);

      // 验证第 2 镜透传与内心 OS 格式化
      final shot2 = shots[1];
      expect(shot2.shotSize, StudioShotSize.closeUp);
      expect(shot2.cameraMove, 'slow_push_in');
      expect(shot2.directorDecisions.cameraStaging, '地面低角仰拍特写');
      expect(shot2.continuity.screenPosition, '画面中心偏左');
      expect(shot2.continuity.gazeDirection, '仰视上方天空');
      expect(shot2.dialogue, '余小白（内心 OS）：这小子身手果然不凡');
      expect(shot2.voiceType, UtteranceVoiceType.innerVoice);
      expect(shot2.isInnerVoice, isTrue);

      // 验证 StudioShot 序列化与反序列化保留 voiceType
      final shotJson = shot2.toJson();
      expect(shotJson['voice_type'], 'inner_voice');
      final deserializedShot = StudioShot.fromJson(shotJson);
      expect(deserializedShot.voiceType, UtteranceVoiceType.innerVoice);
      expect(deserializedShot.isInnerVoice, isTrue);
    });

    test('convertScenesToShots 在节拍缺少机位参数时自适应推导高低俯仰视角', () {
      final scene = DramaScene(
        id: 'SC002',
        sceneNumber: 2,
        title: '密室截击',
        location: '密室',
        beats: const [
          DramaBeat(
            id: 'B01',
            sceneId: 'SC002',
            order: 1,
            name: '楼上下掷',
            action: '刺客从三楼窗口向下俯冲掷出毒镖',
          ),
          DramaBeat(
            id: 'B02',
            sceneId: 'SC002',
            order: 2,
            name: '地面迎击',
            action: '侍卫在地面向上挥剑拔刀斩断暗器',
          ),
        ],
      );

      final shots = AiConstraintEngine.convertScenesToShots([scene]);
      expect(shots.length, 2);
      expect(shots[0].directorDecisions.cameraStaging, '高角度俯拍');
      expect(shots[0].continuity.gazeDirection, '低头俯视');
      expect(shots[1].directorDecisions.cameraStaging, '低角度仰拍');
      expect(shots[1].continuity.gazeDirection, '抬头仰视');
    });

    test('validateSchema screenplayGeneration 提取并保留视听导演维度', () {
      final rawData = {
        'scenes': [
          {
            'id': 'SC001',
            'scene_number': 1,
            'title': '天人居',
            'location': '天人居',
            'beats': [
              {
                'id': 'B01',
                'name': '凭栏思忖',
                'action': '姜七夜凭栏沉思',
                'shot_size': 'close_up',
                'camera_staging': '正面微距特写机位',
                'camera_move': 'slow_push_in',
                'screen_position': '主体居中',
                'gaze_direction': '平视正前',
                'voice_type': 'inner_voice',
                'dialogue': '今天真晦气',
              }
            ]
          }
        ]
      };

      final validated = AiConstraintEngine.validateSchema(
        StudioAiTask.screenplayGeneration,
        rawData,
      );
      expect(validated, isNotNull);
      final scenes = validated!['scenes'] as List;
      final beats = (scenes.first as Map)['beats'] as List;
      final beat = beats.first as Map;
      expect(beat['shot_size'], 'close_up');
      expect(beat['camera_staging'], '正面微距特写机位');
      expect(beat['camera_move'], 'slow_push_in');
      expect(beat['screen_position'], '主体居中');
      expect(beat['gaze_direction'], '平视正前');
      expect(beat['voice_type'], 'inner_voice');
    });

    test('PromptAssembler 针对内心独白注入闭口微表情且生视频禁对口型', () {
      final shot = StudioShot(
        number: 2,
        actionZh: '余小白在街面驻足沉思',
        dialogue: '余小白（内心 OS）：这小子身手果然不凡',
        voiceType: UtteranceVoiceType.innerVoice,
        mood: 'suspense',
        cameraMove: 'slow_push_in',
      );

      // 1. 验证生图提示词：正向闭口沉思，负向抑制开口
      final assembled = PromptAssembler.buildShotPrompt(PromptParts(
        actionZh: shot.actionZh,
        dialogue: shot.dialogue,
        voiceType: shot.voiceType,
        productionType: StudioProductionType.drama,
      ));
      expect(assembled.positive, contains('心声独白'));
      expect(assembled.positive, contains('自然闭口与深邃眼神微表情'));
      expect(assembled.positive, contains('严禁张嘴开口'));
      expect(assembled.negative, contains('mouth open'));

      // 2. 验证生视频提示词
      final videoPrompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: StudioEpisode(
          id: 'ep_1',
          seriesId: 'series_1',
          index: 1,
          title: '初遇',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      expect(videoPrompt, contains('[角色内心独白/心声]'));
      expect(videoPrompt, contains('画外心声配音，画面主体保持自然闭口与从容微表情，严禁开口嘴型与画内文字，严禁对口型'));
      expect(videoPrompt, isNot(contains('[角色对白发声]')));
    });

    test('PromptAssembler 在真人实拍模式下安全清洗负向词，不误伤真人质感', () {
      final assembled = PromptAssembler.buildShotPrompt(PromptParts(
        actionZh: '侠客按剑漫步古街',
        productionType: StudioProductionType.drama,
        aestheticStyle: AestheticStyle.fromId('costume_drama_realism'),
        negativeStyleTokens: 'live-action photo, 3D, CGI, 卡通, 写实照片',
      ));

      // 负向词中不应存在对 live-action photo / 写实照片的抑制
      expect(assembled.negative, isNot(contains('live-action photo')));
      expect(assembled.negative, isNot(contains('写实照片')));
      expect(assembled.negative, contains('3D'));
      expect(assembled.negative, contains('CGI'));
    });
  });
}
