import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/keyframe_visual_critic.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/screenplay_quality_evaluator.dart';

StudioEpisode _createEpisode({
  String id = 'ep_1',
  String screenplayText = '',
  List<StudioShot> shots = const [],
}) {
  return StudioEpisode(
    id: id,
    seriesId: 'series_1',
    title: '测试集',
    index: 1,
    screenplayText: screenplayText,
    shots: shots,
    createdAt: DateTime(2026, 10, 26),
    updatedAt: DateTime(2026, 10, 26),
  );
}

CharacterCard _createChar(String id, String name) {
  return CharacterCard(
    id: id,
    name: name,
    updatedAt: DateTime(2026, 10, 26),
  );
}

void main() {
  group('Stage 1: ScreenplayQualityEvaluator Tests', () {
    test('检出不可拍心理词、文学比喻修辞与时间跨度概括词', () {
      final episode = _createEpisode(
        id: 'ep_1',
        screenplayText: '''
姜七夜心中暗想，此人修为深不可测，仿佛一条伺机而动的毒蛇。
良久之后，他才缓缓开口说道：“你究竟想怎样？”
''',
      );

      final report = ScreenplayQualityEvaluator.evaluate(episode);
      expect(report.isClean, isFalse);
      expect(report.overallScore, lessThanOrEqualTo(85));
      expect(report.issues.any((i) => i.category == ScreenplayIssueCategory.unshootableMental), isTrue);
      expect(report.issues.any((i) => i.category == ScreenplayIssueCategory.literaryMetaphor), isTrue);
      expect(report.issues.any((i) => i.category == ScreenplayIssueCategory.temporalSummary), isTrue);
    });

    test('检出对白超长单气口呼吸过载 (>25字无标点停顿)', () {
      final episode = _createEpisode(
        id: 'ep_2',
        screenplayText: '''
姜七夜冷冷一笑，看着眼前之人说道：“今天无论你耍什么花样都休想从这寒阳城东门离开半步否则就休怪我手中宝刀无情了”。
''',
      );

      final report = ScreenplayQualityEvaluator.evaluate(episode);
      expect(report.issues.any((i) => i.category == ScreenplayIssueCategory.breathOverload), isTrue);
    });

    test('确定性视听外化 (Show, Don\'t Tell) 改写与气口断句', () {
      const rawAction = '他心中暗想此人深不可测，仿佛猛虎卧荒丘，良久之后才动。';
      final rewritten = ScreenplayQualityEvaluator.externalizeActionTextDeterministically(rawAction);
      expect(rewritten.contains('心中暗想'), isFalse);
      expect(rewritten.contains('深不可测'), isFalse);
      expect(rewritten.contains('仿佛'), isFalse);
      expect(rewritten.contains('良久之后'), isFalse);
      expect(rewritten.contains('目光微垂') || rewritten.contains('神色深沉'), isTrue);

      const rawDialogue = '今天无论你耍什么花样都休想从这寒阳城东门离开半步否则就休怪我手中宝刀无情了';
      final pausedDialogue = ScreenplayQualityEvaluator.formatBreathPauseDeterministically(rawDialogue);
      expect(pausedDialogue.contains('……') || pausedDialogue.contains('，'), isTrue);
    });
  });

  group('Stage 2 & 4: DirectorValidationEngine C14~C17 Tests', () {
    test('C14: 连续 3 镜同景别同视角警报与错落调整', () {
      final shots = [
        StudioShot(
          number: 1,
          shotSize: StudioShotSize.medium,
          continuity: const ShotContinuity(cameraAngle: 'eye_level'),
          actionZh: '姜七夜走在街上',
        ),
        StudioShot(
          number: 2,
          shotSize: StudioShotSize.medium,
          continuity: const ShotContinuity(cameraAngle: 'eye_level'),
          actionZh: '余小白喊住姜七夜',
        ),
        StudioShot(
          number: 3,
          shotSize: StudioShotSize.medium,
          continuity: const ShotContinuity(cameraAngle: 'eye_level'),
          actionZh: '姜七夜停下脚步回头',
        ),
      ];

      final episode = _createEpisode(
        id: 'ep_c14',
        shots: shots,
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );
      expect(report.issues.any((i) => i.ruleId == 'C14'), isTrue);

      // 一键错落修复
      final repaired = DirectorValidationEngine.staggerConsecutiveShotScale(episode, 2);
      expect(repaired.shots[1].shotSize, StudioShotSize.closeUp);
    });

    test('C15: 单镜多节拍动作超载警报与一键拆分', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        actionZh: '余小白探出半个身子，随后提着酒杯扬声大喊，紧接着又冷笑连连，转身又坐回酒桌。',
      );

      final episode = _createEpisode(
        id: 'ep_c15',
        shots: [shot],
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: [shot],
      );
      expect(report.issues.any((i) => i.ruleId == 'C15'), isTrue);

      final splitEpisode = DirectorValidationEngine.splitOverloadedShot(episode, 1);
      expect(splitEpisode.shots.length, 2);
      expect(splitEpisode.shots[0].number, 1);
      expect(splitEpisode.shots[1].number, 2);
    });

    test('C16: 垂直高低位同框透视风险与一键裂变为正反打双镜', () {
      final shot = StudioShot(
        number: 2,
        shotSize: StudioShotSize.full,
        characterIds: ['char_yu', 'char_jiang'],
        actionZh: '天人居三楼窗口余小白探身扬手高喊，街道青石路面上姜七夜骑在黑驴背上停下。',
        dialogue: '余小白：“姜七少，上来喝一杯啊！”',
        continuity: const ShotContinuity(
          mountOrVehicle: '黑驴',
          elevationLevel: 'balcony_2f',
          cameraAngle: 'high_angle',
        ),
      );

      final chars = [
        _createChar('char_yu', '余小白'),
        _createChar('char_jiang', '姜七夜'),
      ];

      final episode = _createEpisode(
        id: 'ep_c16',
        shots: [shot],
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: [shot],
        characters: chars,
      );
      expect(report.issues.any((i) => i.ruleId == 'C16'), isTrue);

      // 一键裂变为正反打双镜
      final reversePairEp = DirectorValidationEngine.splitVerticalShotIntoReversePair(
        episode,
        2,
        characters: chars,
      );

      expect(reversePairEp.shots.length, 2);
      final shotA = reversePairEp.shots[0];
      final shotB = reversePairEp.shots[1];

      // A 镜：高位发话者
      expect(shotA.number, 2);
      expect(shotA.characterIds, contains('char_yu'));
      expect(shotA.continuity.cameraAngle, 'high_angle');
      expect(shotA.continuity.elevationLevel, 'balcony_2f');
      expect(shotA.continuity.mountOrVehicle, isEmpty);

      // B 镜：低位倾听者，必须保留坐骑
      expect(shotB.number, 3);
      expect(shotB.characterIds, contains('char_jiang'));
      expect(shotB.continuity.cameraAngle, 'low_angle');
      expect(shotB.continuity.elevationLevel, 'ground');
      expect(shotB.continuity.mountOrVehicle, '黑驴');
      expect(shotB.dialogue, isEmpty);
    });

    test('C17: 首帧姿态断层与剧烈运镜口型互斥', () {
      final shots = [
        StudioShot(
          number: 1,
          assembledPrompt: '青年骑在黑驴背上，漫步在青石板路上',
          actionZh: '姜七夜站在地上迈步走向酒楼',
          continuity: const ShotContinuity(mountOrVehicle: '黑驴'),
        ),
        StudioShot(
          number: 2,
          cameraMove: '快速360度环绕运镜 (Fast Orbit)',
          dialogue: '姜七夜：“借过。”',
          actionZh: '姜七夜开口对余小白说话',
        ),
      ];

      final episode = _createEpisode(
        id: 'ep_c17',
        shots: shots,
      );

      final report = DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
      );
      final c17Issues = report.issues.where((i) => i.ruleId == 'C17').toList();
      expect(c17Issues.length, greaterThanOrEqualTo(2));
      expect(c17Issues.any((i) => i.ruleName.contains('首帧与起始动作断层')), isTrue);
      expect(c17Issues.any((i) => i.ruleName.contains('剧烈运镜与口型互斥')), isTrue);
    });

    test('全链路四阶段质量评分卡计算 (StudioQualityScorecard)', () {
      final episode = _createEpisode(
        id: 'ep_card',
        screenplayText: '姜七夜平静地看着眼前长街。',
        shots: [
          StudioShot(
            number: 1,
            shotSize: StudioShotSize.medium,
            actionZh: '姜七夜停下脚步。',
          ),
        ],
      );

      final scorecard = DirectorValidationEngine.computeScorecard(
        episode: episode,
      );

      expect(scorecard.screenplayScore, inInclusiveRange(0, 100));
      expect(scorecard.storyboardGrammarScore, inInclusiveRange(0, 100));
      expect(scorecard.keyframeAndPromptScore, inInclusiveRange(0, 100));
      expect(scorecard.videoMotionSafetyScore, inInclusiveRange(0, 100));
      expect(scorecard.overallScore, inInclusiveRange(0, 100));
    });
  });

  group('Stage 3: KeyframeVisualCritic Tests', () {
    test('确定性静态审图检出坐骑缺失、双人高低位浮空风险与标签残留', () {
      final shot = StudioShot(
        number: 2,
        shotSize: StudioShotSize.long,
        characterIds: ['char_yu', 'char_jiang'],
        actionZh: '三楼余小白探身大喊，街面姜七夜骑驴停驻。',
        assembledPrompt: '<Picture 1> 余小白站在窗台，严禁平地同高度站立。',
        dialogue: '姜七夜：“借过。”',
        continuity: const ShotContinuity(
          mountOrVehicle: '黑驴',
          elevationLevel: 'balcony_2f',
        ),
      );

      final report = KeyframeVisualCritic.evaluateDeterministically(
        shot: shot,
        characters: [
          _createChar('char_yu', '余小白'),
          _createChar('char_jiang', '姜七夜'),
        ],
      );

      expect(report.passed, isFalse);
      expect(report.characterCountOk, isFalse); // 含 <Picture 1>
      expect(report.spatialElevationOk, isFalse); // 双人高低位 + 否定词
      expect(report.mountPropOk, isFalse); // 生图词未提及黑驴
      expect(report.shotScaleOk, isFalse); // 远景 + 对白
      expect(report.issues.length, greaterThanOrEqualTo(3));
      expect(report.promptFixSuggestion, isNotEmpty);
    });

    test('一键采纳 VLM 修复建议同步更新 assembledPrompt 与坐骑台账', () {
      final shot = StudioShot(
        number: 2,
        actionZh: '姜七夜骑驴停在街心',
        assembledPrompt: '姜七夜站在街心',
        continuity: const ShotContinuity(mountOrVehicle: ''),
        vlmCriticReport: const VlmFrameCriticReport(
          score: 35,
          passed: false,
          mountPropOk: false,
          promptFixSuggestion: '姜七夜稳稳骑在黑驴背上，停在青石街道中央。',
        ),
      );

      final fixedShot = KeyframeVisualCritic.applySuggestedFixToShot(
        shot,
        characters: [_createChar('char_jiang', '姜七夜')],
      );

      expect(fixedShot.assembledPrompt, contains('骑在黑驴背上'));
      expect(fixedShot.continuity.mountOrVehicle, '黑驴');
      expect(fixedShot.vlmCriticReport, isNull);
    });

    test('确定性审图检出风格互斥标签与单人镜头幽灵配角，并实行一票否决（评分<=40）', () {
      final shot = StudioShot(
        number: 2,
        shotSize: StudioShotSize.medium,
        characterIds: ['char_yu'],
        actionZh: '余小白推开客栈窗户向长街张望，大喊喊住姜七夜。',
        assembledPrompt: 'photorealistic 8k, live-action, arri alexa footage, 3D国漫, UE5渲染, 余小白推开木窗。',
      );

      final report = KeyframeVisualCritic.evaluateDeterministically(
        shot: shot,
        characters: [
          _createChar('char_yu', '余小白'),
          _createChar('char_jiang', '姜七夜'),
        ],
      );

      expect(report.passed, isFalse);
      expect(report.score, lessThanOrEqualTo(40));
      expect(report.characterCountOk, isFalse); // 幽灵角色姜七夜
      expect(report.issues.any((i) => i.contains('互斥风格')), isTrue);
      expect(report.issues.any((i) => i.contains('幽灵配角')), isTrue);
    });
  });
}
