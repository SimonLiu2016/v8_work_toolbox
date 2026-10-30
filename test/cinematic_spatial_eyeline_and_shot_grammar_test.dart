import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('漫剧视听空间视线与电影语法测试', () {
    test('1. PromptAssembler.sanitizeInnerMonologue 消除内心 OS 中的老王幽灵角色实体', () {
      final sanitized = PromptAssembler.sanitizeInnerMonologue(
        dialogue: '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
        speaker: '姜七夜',
        inSceneCharacters: ['姜七夜'], // 老王不在场
      );

      // 验证剥离了预估秒数与角色前缀
      expect(sanitized, isNot(contains('预估2.5秒')));
      expect(sanitized, isNot(contains('姜七夜（内心 OS）：')));

      // 验证老王实体名词被脱敏替换为他人，杜绝图像模型误召回老王实体
      expect(sanitized, isNot(contains('老王')));
      expect(sanitized, contains('他人'));
      expect(sanitized, contains('心忖'));
    });

    test('2. PromptAssembler.compileGazeAndEyeline 视线轴线与机位俯仰编译', () {
      // 二楼余小白视角：高角度俯拍 + 向斜下方注视长街
      final highEyeline = PromptAssembler.compileGazeAndEyeline(
        cameraAngle: 'high_angle',
        elevationLevel: 'balcony_2f',
        gazeDirection: '俯视长街',
        gazeTarget: '街面姜七夜',
      );
      expect(highEyeline, contains('高角度俯拍视角'));
      expect(highEyeline, contains('向斜下方长街地面注视'));
      expect(highEyeline, contains('strictly no eye contact with camera'));
      expect(highEyeline, contains('目光聚焦于街面姜七夜'));

      // 街面姜七夜视角：低角度仰拍 + 向斜上方楼台仰视
      final lowEyeline = PromptAssembler.compileGazeAndEyeline(
        cameraAngle: 'low_angle',
        elevationLevel: 'ground',
        gazeDirection: '仰望二楼挑台',
        gazeTarget: '二楼余小白',
      );
      expect(lowEyeline, contains('低角度仰拍视角'));
      expect(lowEyeline, contains('向斜上方楼台仰视'));
      expect(lowEyeline, contains('strictly no eye contact with camera'));
      expect(lowEyeline, contains('目光聚焦于二楼余小白'));
    });

    test('3. PromptAssembler.buildShotPrompt 全局注入防打破第四面墙排他词与闭口守卫', () {
      final prompt = PromptAssembler.buildShotPrompt(PromptParts(
        actionZh: '姜七夜骑着高大毛驴沿长街缓行',
        dialogue: '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
        voiceType: UtteranceVoiceType.innerVoice,
        characters: [
          CharacterCard(
            id: 'c_jiang',
            name: '姜七夜',
            descriptionZh: '俊美从容青年',
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        continuity: const ShotContinuity(
          worldPosition: '长街中央',
          cameraAngle: 'low_angle',
          elevationLevel: 'ground',
          gazeDirection: '仰望二楼',
        ),
      ));

      // 验证正向词包含仰拍视角与视线对齐
      expect(prompt.positive, contains('低角度仰拍视角'));
      expect(prompt.positive, contains('向斜上方楼台仰视'));

      // 验证内心 OS 被脱敏且强调闭口
      expect(prompt.positive, contains('微表情'));
      expect(prompt.positive, isNot(contains('老王')));
      expect(prompt.positive, contains('严禁在画面中渲染心声所指代的非在场第三人'));

      // 验证负向词包含闭口与防直视镜头排他词
      expect(prompt.negative, contains('looking at camera'));
      expect(prompt.negative, contains('eye contact with viewer'));
      expect(prompt.negative, contains('mouth open, speaking, parted lips, talking'));
    });

    test('4. DirectorValidationEngine 审计二楼机位水平平移与地面瞬移冲突 (C05)', () {
      final episode = StudioEpisode(
        id: 'ep_test',
        seriesId: 'series_01',
        title: '第一回',
        index: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        shots: [
          const StudioShot(
            number: 7,
            actionZh: '余小白手扶二楼栏杆向楼下喊话',
            cameraMove: 'slow push-in',
            continuity: ShotContinuity(
              worldPosition: '茶楼二楼挑台',
              elevationLevel: 'balcony_2f',
              cameraAngle: 'high_angle',
            ),
          ),
          const StudioShot(
            number: 8,
            actionZh: '镜头向右平移，长街上华丽马车疾驰而过，红玉郡主掀开轿帘',
            cameraMove: 'pan right',
            continuity: ShotContinuity(
              worldPosition: '茶楼二楼挑台',
              elevationLevel: 'balcony_2f',
              cameraAngle: 'high_angle',
            ),
          ),
        ],
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: episode.shots,
      );

      // 应该捕获 C05 垂直空间运镜冲突
      final c05Issues = report.issues.where((i) => i.ruleId == 'C05' && i.ruleName == '垂直空间运镜冲突').toList();
      expect(c05Issues.isNotEmpty, isTrue);
      expect(c05Issues.first.message, contains('二楼/挑台'));
      expect(c05Issues.first.message, contains('单纯水平平移'));
      expect(c05Issues.first.suggestion, contains('Tilt Down'));
    });

    test('5. DirectorValidationEngine 审计内心戏幽灵角色检查 (C01)', () {
      final episode = StudioEpisode(
        id: 'ep_test_2',
        seriesId: 'series_01',
        title: '第一回',
        index: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
        shots: [
          const StudioShot(
            number: 4,
            actionZh: '姜七夜单人骑驴慢行',
            dialogue: '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
            voiceType: UtteranceVoiceType.innerVoice,
            characterIds: ['c_jiang', 'c_laowang'], // 误将老王填入
            continuity: ShotContinuity(worldPosition: '长街'),
          ),
        ],
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: episode.shots,
        characters: [
          CharacterCard(id: 'c_jiang', name: '姜七夜', updatedAt: DateTime(2026, 1, 1)),
          CharacterCard(id: 'c_laowang', name: '老王', updatedAt: DateTime(2026, 1, 1)),
        ],
      );

      final ghostIssues = report.issues.where((i) => i.ruleName == '内心戏幽灵角色检查').toList();
      expect(ghostIssues.isNotEmpty, isTrue);
      expect(ghostIssues.first.message, contains('内心独白'));
      expect(ghostIssues.first.message, contains('误召唤为出场演员'));
    });

    test('6. ShotContinuity 与 StudioShot 空间高低位与视线字段序列化', () {
      const continuity = ShotContinuity(
        worldPosition: '茶楼二楼栏杆',
        screenPosition: '画面右上方',
        cameraAngle: 'high_angle',
        elevationLevel: 'balcony_2f',
        gazeDirection: '俯视长街地面',
        gazeTarget: '街面姜七夜',
      );

      final json = continuity.toJson();
      expect(json['camera_angle'], equals('high_angle'));
      expect(json['elevation_level'], equals('balcony_2f'));
      expect(json['gaze_direction'], equals('俯视长街地面'));
      expect(json['gaze_target'], equals('街面姜七夜'));

      final recovered = ShotContinuity.fromJson(json);
      expect(recovered.cameraAngle, equals('high_angle'));
      expect(recovered.elevationLevel, equals('balcony_2f'));
      expect(recovered.gazeDirection, equals('俯视长街地面'));
      expect(recovered.gazeTarget, equals('街面姜七夜'));

      const shot = StudioShot(
        number: 5,
        continuity: continuity,
      );
      expect(shot.cameraAngle, equals('high_angle'));
      expect(shot.elevationLevel, equals('balcony_2f'));
      expect(shot.gazeDirection, equals('俯视长街地面'));
      expect(shot.gazeTarget, equals('街面姜七夜'));
    });
  });
}
