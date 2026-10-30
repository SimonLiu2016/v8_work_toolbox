import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('台词纯净化 (cleanDialogueForSpeech)', () {
    test('剥离预估时长注记、内心 OS 标记与角色名前缀', () {
      expect(
        PromptAssembler.cleanDialogueForSpeech(
          '姜七夜（内心 OS）：又来了，这老头每月俸禄被扣，就拿我撒气。（预估3.0秒）',
        ),
        '又来了，这老头每月俸禄被扣，就拿我撒气。',
      );

      expect(
        PromptAssembler.cleanDialogueForSpeech(
          '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
        ),
        '今天真晦气，又被老王训了一顿。',
      );

      expect(
        PromptAssembler.cleanDialogueForSpeech(
          '老王：“姜七夜！你还有没有点规矩？老子跟你说话，你竟敢走神？！”（预估3.0秒）',
        ),
        '姜七夜！你还有没有点规矩？老子跟你说话，你竟敢走神？！',
      );

      expect(
        PromptAssembler.cleanDialogueForSpeech(
          '（内心 OS）：小心驶得万年船。(预估 4.0s)',
        ),
        '小心驶得万年船。',
      );

      expect(
        PromptAssembler.cleanDialogueForSpeech(
          '“姜捕快，这边请。”',
        ),
        '姜捕快，这边请。',
      );
    });
  });

  group('说话人精准提取 (extractSpeakerName)', () {
    test('从内心独白与常规对白头部正确提取说话人', () {
      expect(
        PromptAssembler.extractSpeakerName('姜七夜（内心 OS）：今天真晦气...'),
        '姜七夜',
      );

      expect(
        PromptAssembler.extractSpeakerName('老王：“姜七夜！你还有没有点规矩？...”'),
        '老王',
      );

      expect(
        PromptAssembler.extractSpeakerName('余小白：姜七少，快走！'),
        '余小白',
      );

      expect(
        PromptAssembler.extractSpeakerName('“没有前缀的台词”', defaultSpeaker: '姜七夜'),
        '姜七夜',
      );
    });
  });

  group('本地节拍转换隔离心声实体 (convertScenesToShots)', () {
    test('内心独白中心声提及非在场第三人时，不将第三人加入出场角色 characterIds', () {
      final now = DateTime.now();
      final charJiang = CharacterCard(
        id: 'char_jiang',
        name: '姜七夜',
        facialFeaturesZh: '青年捕快，剑眉星目，黑色束发',
        descriptionZh: '姜七夜，黑衣捕快',
        updatedAt: now,
      );

      final charWang = CharacterCard(
        id: 'char_wang',
        name: '老王',
        facialFeaturesZh: '身形干瘦，头发花白稀疏，面容浮肿',
        descriptionZh: '老王，老狱卒',
        updatedAt: now,
      );

      final scene = DramaScene(
        id: 'scene_1',
        sceneNumber: 1,
        title: '长街疾行',
        beats: [
          DramaBeat(
            id: 'beat_4',
            sceneId: 'scene_1',
            order: 4,
            name: '心生晦气',
            action: '姜七夜低头快步疾行在长街冷雨中',
            dialogue: '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。（预估2.5秒）',
            voiceType: UtteranceVoiceType.innerVoice,
          ),
        ],
      );

      final shots = AiConstraintEngine.convertScenesToShots(
        [scene],
        characters: [charJiang, charWang],
        sceneCards: [],
      );

      expect(shots.length, 1);
      final shot = shots.first;

      // 姜七夜作为说话人应该在场
      expect(shot.characterIds.contains('char_jiang'), isTrue);
      // 老王仅在姜七夜的心声中被提及，非在场实体，严禁进入 characterIds
      expect(shot.characterIds.contains('char_wang'), isFalse);

      // 验证台词已被规整为干净格式，不包含预估秒数
      expect(shot.dialogue, '姜七夜（内心 OS）：今天真晦气，又被老王训了一顿。');
    });
  });

  group('同框多角色容貌发型文本锁定 (resolveCharacterStaging)', () {
    test('在存在参考图的多角色同框站位中追加容貌与发型描述', () {
      final now = DateTime.now();
      final charWang = CharacterCard(
        id: 'char_wang',
        name: '老王',
        facialFeaturesZh: '身形干瘦如枯柴，头发花白稀疏，面容浮肿，三角眼，蒜头鼻',
        descriptionZh: '老王，身穿破旧差服',
        updatedAt: now,
      );

      final staging = PromptAssembler.resolveCharacterStaging(
        index: 1,
        totalCount: 2,
        character: charWang,
        actionZh: '老王怒斥姜七夜',
      );

      expect(staging.contains('老王'), isTrue);
      // 必须包含头发与容貌特征文本
      expect(staging.contains('容貌特征：身形干瘦如枯柴，头发花白稀疏'), isTrue);
    });
  });

  group('视频生成提示词纯净化 (buildVideoGenPrompt)', () {
    test('视频生成提示词中的心声不包含秒数注记与冒号前缀', () {
      final now = DateTime.now();
      final shot = StudioShot(
        number: 2,
        dialogue: '姜七夜（内心 OS）：又来了，这老头每月俸禄被扣，就拿我撒气。（预估3.0秒）',
        voiceType: UtteranceVoiceType.innerVoice,
        actionZh: '姜七夜面无表情垂手而立',
      );

      final prompt = PromptAssembler.buildVideoGenPrompt(
        shot: shot,
        episode: StudioEpisode(
          id: 'ep_1',
          seriesId: 'series_1',
          title: '初入天牢',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(prompt.contains('（预估3.0秒）'), isFalse);
      expect(prompt.contains('预估'), isFalse);
      expect(prompt.contains('“又来了，这老头每月俸禄被扣，就拿我撒气。”'), isTrue);
    });
  });
}
