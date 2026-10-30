import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('1. 坐骑实体归属与高低落差隔离（Mount Attribution & Balcony Isolation）', () {
    test('三楼窗口角色绝对不承载地面坐骑，地面角色正常绑定坐骑', () {
      final yuChar = CharacterCard(
        id: 'c_yu',
        name: '余小白',
        descriptionZh: '白白胖胖的年轻人',
        updatedAt: DateTime(2026, 10, 26),
      );
      final jiangChar = CharacterCard(
        id: 'c_jiang',
        name: '姜七夜',
        descriptionZh: '姜家七少爷，常骑大黑驴',
        updatedAt: DateTime(2026, 10, 26),
      );

      const continuity = ShotContinuity(
        screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
        mountOrVehicle: '大黑驴',
        elevationLevel: 'balcony_3f',
      );

      // 余小白在三楼窗口高位
      final isYuRiding = PromptAssembler.isCharacterRidingMount(
        character: yuChar,
        continuity: continuity,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯喊住姜七夜',
        isVerticalHighLow: true,
        isCharHigh: true,
      );
      expect(isYuRiding, isFalse, reason: '三楼窗口角色绝对不应骑乘地面大黑驴');

      // 姜七夜在街面
      final isJiangRiding = PromptAssembler.isCharacterRidingMount(
        character: jiangChar,
        continuity: continuity,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯喊住姜七夜',
        isVerticalHighLow: true,
        isCharHigh: false,
      );
      expect(isJiangRiding, isTrue, reason: '处于地面的姜七夜应正常绑定大黑驴坐骑');
    });

    test('resolveCharacterStaging 仅为骑乘者附加坐骑描述，严禁无差别广播', () {
      final yuChar = CharacterCard(
        id: 'c_yu',
        name: '余小白',
        descriptionZh: '白白胖胖，衣着华贵',
        updatedAt: DateTime(2026, 10, 26),
      );
      final jiangChar = CharacterCard(
        id: 'c_jiang',
        name: '姜七夜',
        descriptionZh: '骑着大黑驴的少年',
        updatedAt: DateTime(2026, 10, 26),
      );

      const continuity = ShotContinuity(
        screenPosition: '姜七夜居画面下方街道，余小白位于上方窗框',
        mountOrVehicle: '大黑驴',
        elevationLevel: 'balcony_3f',
      );

      final yuStaging = PromptAssembler.resolveCharacterStaging(
        index: 0,
        totalCount: 2,
        character: yuChar,
        continuity: continuity,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
      );
      expect(yuStaging, isNot(contains('骑在大黑驴上')));
      expect(yuStaging, contains('居高临下俯瞰街面'));

      final jiangStaging = PromptAssembler.resolveCharacterStaging(
        index: 1,
        totalCount: 2,
        character: jiangChar,
        continuity: continuity,
        actionZh: '天人居三楼窗口探出白胖身子，余小白提着酒杯，居高临下扬声喊住姜七夜。',
      );
      expect(jiangStaging, contains('骑在大黑驴上仰头回应'));
    });
  });

  group('2. 机位俯仰与视线朝向分层仲裁（Camera Angle & Gaze Hierarchy）', () {
    test('即使 elevationLevel 为 balcony_3f，显式 low_angle 仰拍绝不反向判定为高角度俯拍', () {
      final text = PromptAssembler.compileGazeAndEyeline(
        cameraAngle: 'low_angle',
        gazeDirection: '仰视',
        elevationLevel: 'balcony_3f',
      );

      expect(text, contains('低角度仰拍视角（low-angle upward perspective）'));
      expect(text, isNot(contains('high-angle downward perspective')));
    });

    test('显式 high_angle 俯拍严格生成高角度俯拍视角', () {
      final text = PromptAssembler.compileGazeAndEyeline(
        cameraAngle: 'high_angle',
        gazeDirection: '俯视街面',
        elevationLevel: 'balcony_3f',
      );

      expect(text, contains('高角度俯拍视角（high-angle downward perspective）'));
      expect(text, isNot(contains('low-angle upward perspective')));
    });

    test('无显式机位时，显式 gazeDirection (仰视) 优先于静态场景高度', () {
      final text = PromptAssembler.compileGazeAndEyeline(
        cameraAngle: '',
        gazeDirection: '仰面注视三楼窗口',
        elevationLevel: 'balcony_3f',
      );

      expect(text, contains('低角度仰拍视角（low-angle upward perspective）'));
      expect(text, isNot(contains('high-angle downward perspective')));
    });
  });

  group('3. 视频生成模式确定性与提示词克隆防护（Mode & Clone Guard）', () {
    test('显式指定 reference 模式时，即使存在本地关键帧，模式依旧保持 reference', () {
      final shot = StudioShot(
        number: 3,
        videoMode: 'reference',
        framePath: 'shot_3.png',
        characterIds: ['c_yu', 'c_jiang'],
      );

      final mode = shot.resolveEffectiveVideoMode(
        hasKeyframe: true,
        hasCharacterOrSceneRef: true,
      );

      expect(mode, equals(AgnesVideoMode.reference));
    });

    test('auto 模式在有关键帧时推荐 keyframe，无关键帧有角色时推荐 reference', () {
      final shotWithoutFrame = StudioShot(
        number: 3,
        videoMode: 'auto',
        characterIds: ['c_yu'],
      );
      expect(
        shotWithoutFrame.resolveEffectiveVideoMode(hasKeyframe: false, hasCharacterOrSceneRef: true),
        equals(AgnesVideoMode.reference),
      );

      final shotWithFrame = StudioShot(
        number: 3,
        videoMode: 'auto',
        framePath: 'shot_3.png',
        characterIds: ['c_yu'],
      );
      expect(
        shotWithFrame.resolveEffectiveVideoMode(hasKeyframe: true, hasCharacterOrSceneRef: true),
        equals(AgnesVideoMode.keyframe),
      );
    });

    test('keyframe 模式下 sanitizeForVideoMode 清洗【同框人物与构图】与素材指代以防克隆', () {
      const rawPrompt = '【素材指代】<Picture 1> = 余小白；<Picture 2> = 姜七夜\n'
          '【同框人物与构图】: 余小白（处于画面前景窗框，形象以<Picture 1>为准）；姜七夜（处于画面地面，形象以<Picture 2>为准）\n'
          '【画面微动作】: 余小白（<Picture 1>）举杯大喊。\n'
          '【空间关系】姜七夜居画面下方街道，余小白位于上方窗框';

      final sanitized = PromptAssembler.sanitizeForVideoMode(
        rawPrompt,
        mode: AgnesVideoMode.keyframe,
        characters: [
          CharacterCard(id: 'c_yu', name: '余小白', updatedAt: DateTime(2026, 10, 26)),
          CharacterCard(id: 'c_jiang', name: '姜七夜', updatedAt: DateTime(2026, 10, 26)),
        ],
      );

      expect(sanitized, isNot(contains('【素材指代】')));
      expect(sanitized, isNot(contains('<Picture 1>')));
      expect(sanitized, isNot(contains('<Picture 2>')));
      expect(sanitized, isNot(contains('【同框人物与构图】')));
      expect(sanitized, contains('【出场人物】: 余小白、姜七夜（首帧已固定同框人物形象与空间布局，严禁多重绘制额外人物）'));
      expect(sanitized, contains('余小白举杯大喊'));
    });
  });
}
