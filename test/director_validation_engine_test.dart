import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';

void main() {
  group('DirectorValidationEngine C01~C09 Audit Tests', () {
    final now = DateTime.now();

    test('passes completely valid episode and shots', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '测试第一集',
        createdAt: now,
        updatedAt: now,
        protectedContract: const ProtectedContract(
          utterances: [
            ProtectedUtterance(id: 'u1', speaker: '主角', text: '休走！看剑！'),
          ],
        ),
      );

      final shots = [
        StudioShot(
          number: 1,
          sceneId: 'scene_inn',
          characterIds: const ['char_hero'],
          shotSize: StudioShotSize.medium,
          cameraMove: 'push',
          durationSec: 4.0,
          actionZh: '主角拔出佩剑，目光如炬，向前逼近两步',
          dialogue: '主角: 休走！看剑！',
          continuity: const ShotContinuity(
            screenPosition: '画面左侧三分之一，面向右',
            lightingState: '暖色灯笼逆光',
          ),
        ),
        StudioShot(
          number: 2,
          sceneId: 'scene_inn',
          characterIds: const ['char_hero'],
          shotSize: StudioShotSize.closeUp,
          cameraMove: 'pan right',
          durationSec: 3.5,
          actionZh: '剑锋直指前方，主角眼神坚定',
          dialogue: '',
          continuity: const ShotContinuity(
            screenPosition: '画面右侧，面向左',
            lightingState: '暖色灯笼侧光',
          ),
        ),
      ];

      final characters = [
        CharacterCard(id: 'char_hero', name: '主角', updatedAt: now),
      ];
      final scenes = [
        SceneCard(id: 'scene_inn', name: '破庙客栈', updatedAt: now),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
        characters: characters,
        scenes: scenes,
      );

      expect(report.isValid, isTrue);
      expect(report.blockingCount, equals(0));
      expect(report.issues, isEmpty);
    });

    test('C01: detects unregistered characters and scenes', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'unregistered_scene',
          characterIds: ['unregistered_char'],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 4.0,
          actionZh: '站立',
        ),
      ];

      final characters = [
        CharacterCard(id: 'char_valid', name: '注册角色', updatedAt: now),
      ];
      final scenes = [
        SceneCard(id: 'scene_valid', name: '注册场景', updatedAt: now),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
        characters: characters,
        scenes: scenes,
      );

      final c01Issues = report.issues.where((i) => i.ruleId == 'C01').toList();
      expect(c01Issues.length, equals(2));
      expect(c01Issues.any((i) => i.message.contains('未在角色库登记')), isTrue);
      expect(c01Issues.any((i) => i.message.contains('未在场景库登记')), isTrue);
    });

    test('C02: warns on missing protected utterances', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
        protectedContract: const ProtectedContract(
          utterances: [
            ProtectedUtterance(id: 'u2', speaker: '反派', text: '此宝归我了！'),
          ],
        ),
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '反派大笑离去',
          dialogue: '反派: 哈哈哈哈',
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c02Issues = report.issues.where((i) => i.ruleId == 'C02').toList();
      expect(c02Issues.length, equals(1));
      expect(c02Issues.first.message, contains('此宝归我了！'));
    });

    test('C03: warns on combat shot missing physical feedback or steps', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          mood: 'battle',
          actionZh: '双方交战，招式十分好看', // no physical feedback keywords
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c03Issues = report.issues.where((i) => i.ruleId == 'C03').toList();
      expect(c03Issues.length, equals(1));
      expect(c03Issues.first.message, contains('受力反馈'));
    });

    test('C04: blocking on empty action and excessive dialogue load', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 2.0,
          actionZh: '', // Empty actionZh -> blocking
        ),
        const StudioShot(
          number: 2,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 2.0,
          actionZh: '主角说话',
          dialogue: '主角: 这是一段极其冗长并且在两秒钟之内绝对无法念完的台词内容，字数远远超出允许的上限！',
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      expect(report.isValid, isFalse);
      expect(report.blockingCount, greaterThanOrEqualTo(2));
      final c04Issues = report.issues.where((i) => i.ruleId == 'C04').toList();
      expect(c04Issues.any((i) => i.message.contains('为空')), isTrue);
      expect(c04Issues.any((i) => i.message.contains('极限负荷')), isTrue);
    });

    test('C05: warns on 180 axis jump without camera transition', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: ['char1'],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '角色站立对话',
          continuity: ShotContinuity(screenPosition: '左侧三分之一，面向右'),
        ),
        const StudioShot(
          number: 2,
          sceneId: 'scene1',
          characterIds: ['char1'],
          shotSize: StudioShotSize.closeUp,
          cameraMove: 'static', // no pan/orbit
          durationSec: 3.0,
          actionZh: '角色侧脸特写',
          continuity: ShotContinuity(screenPosition: '右侧，面向左'),
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c05Issues = report.issues.where((i) => i.ruleId == 'C05').toList();
      expect(c05Issues.length, equals(1));
      expect(c05Issues.first.message, contains('180° 越轴风险'));
    });

    test('C06: blocking on shot duration out of 2.0s~6.0s bounds', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 1.0, // too short
          actionZh: '闪过一瞬',
        ),
        const StudioShot(
          number: 2,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 8.0, // too long
          actionZh: '漫长的一镜到底',
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c06Issues = report.issues.where((i) => i.ruleId == 'C06').toList();
      expect(c06Issues.length, equals(2));
      expect(report.blockingCount, greaterThanOrEqualTo(2));
    });

    test('C08: blocking on discontinuous shot numbers', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '镜头一',
        ),
        const StudioShot(
          number: 3, // Skipped 2!
          sceneId: 'scene1',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '镜头三',
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c08Issues = report.issues.where((i) => i.ruleId == 'C08').toList();
      expect(c08Issues.length, equals(1));
      expect(c08Issues.first.message, contains('分镜镜号不连续'));
    });

    test('C09: warns on color temperature sudden flip in same scene', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 'series1',
        title: '集数',
        createdAt: now,
        updatedAt: now,
      );

      final shots = [
        const StudioShot(
          number: 1,
          sceneId: 'scene_same',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '冷色蓝光',
          directorDecisions: DirectorDecisions(
            lightingStaging: '冷色月光漫射，蓝色基调',
          ),
        ),
        const StudioShot(
          number: 2,
          sceneId: 'scene_same',
          characterIds: [],
          shotSize: StudioShotSize.medium,
          cameraMove: 'static',
          durationSec: 3.0,
          actionZh: '暖色烛光',
          directorDecisions: DirectorDecisions(
            lightingStaging: '暖色壁炉火光，橙黄基调',
          ),
        ),
      ];

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );

      final c09Issues = report.issues.where((i) => i.ruleId == 'C09').toList();
      expect(c09Issues.length, equals(1));
      expect(c09Issues.first.message, contains('色温发生断崖反转'));
    });
  });

  group('DramaBeat voiceType & Literary Screenplay Export', () {
    test('DramaBeat correctly serializes and deserializes voiceType', () {
      final beat = DramaBeat(
        id: 'B01',
        sceneId: 'SC001',
        order: 1,
        name: '内心吐槽',
        action: '姜七夜骑驴慢行，暗自思忖',
        dialogueSpeaker: '姜七夜',
        dialogue: '今天真晦气，被老王训了一顿。',
        voiceType: UtteranceVoiceType.innerVoice,
      );

      final json = beat.toJson();
      expect(json['voice_type'], 'inner_voice');

      final restored = DramaBeat.fromJson(json);
      expect(restored.voiceType, UtteranceVoiceType.innerVoice);
      expect(restored.dialogueSpeaker, '姜七夜');
    });

    test('DramaScene.exportToMarkdown renders innerVoice as (内心 OS)', () {
      final scene = DramaScene(
        id: 'SC001',
        sceneNumber: 1,
        title: '寒阳城长街',
        location: '天人居门前长街',
        setting: '外景',
        timeOfDay: '黄昏',
        atmosphere: '夕阳斜照',
        beats: const [
          DramaBeat(
            id: 'B01',
            sceneId: 'SC001',
            order: 1,
            name: '骑驴思忖',
            action: '姜七夜骑着高大青驴，慢悠悠走在长街上。',
            dialogueSpeaker: '姜七夜',
            dialogue: '今天真晦气，又被老王训了一顿。',
            voiceType: UtteranceVoiceType.innerVoice,
          ),
          DramaBeat(
            id: 'B02',
            sceneId: 'SC001',
            order: 2,
            name: '楼上呼唤',
            action: '余小白探出半个身子挥手。',
            dialogueSpeaker: '余小白',
            dialogue: '姜小七，上来喝酒！',
            voiceType: UtteranceVoiceType.dialogue,
          ),
        ],
      );

      final md = DramaScene.exportToMarkdown([scene]);
      expect(md, contains('### 第1场 寒阳城长街（外景 / 黄昏 / 天人居门前长街）'));
      expect(md, contains('心声（姜七夜 · 内心 OS）：今天真晦气，又被老王训了一顿。'));
      expect(md, contains('对白（余小白）：姜小七，上来喝酒！'));
    });
  });
}
