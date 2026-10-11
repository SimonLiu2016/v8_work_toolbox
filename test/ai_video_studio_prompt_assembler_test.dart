import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

/// `PromptAssembler` 的合并与截断契约测试（spec 4.1 / 4.2 / 4.3）。
///
/// 固定三件事：
/// 1. 段顺序固定——风格、景别、角色、场景、运镜，越靠前越不可牺牲；
/// 2. 形态差异词只追加、去重，不改写用户写下的词；
/// 3. 超限时从尾部丢弃，且 `truncated` 让 UI 能提示用户。
void main() {
  CharacterCard character({
    String base = '',
    String negative = '',
    List<CharacterVariation> variations = const [],
  }) {
    return CharacterCard(
      id: 'c1',
      name: '林晓',
      basePromptPositive: base,
      basePromptNegative: negative,
      variations: variations.isEmpty
          ? const [
              CharacterVariation(id: 'v-default', name: '默认', active: true),
            ]
          : variations,
      updatedAt: DateTime(2026),
    );
  }

  group('段顺序与内容', () {
    test('风格词在景别之前，运镜词在最后', () {
      final result = PromptAssembler.buildShotPrompt(PromptParts(
        styleTokens: 'cinematic still',
        shotSize: ShotSizeTokens.of(StudioShotSize.closeUp),
        mood: MoodTokens.of('warm'),
        shotFunction: ShotFunctionTokens.of(ShotFunction.opening),
        cameraMove: 'slow push-in',
      ));

      final words = result.positive.split(', ');
      expect(words.first, 'masterpiece', reason: '画质基线必须最前');
      expect(words, contains('cinematic still'));
      expect(words, contains('camera: slow push-in'));
      expect(words.last, 'camera: slow push-in', reason: '运镜词最可牺牲，放最后');

      final styleIdx = words.indexOf('cinematic still');
      final shotIdx = words.indexOf(ShotSizeTokens.of(StudioShotSize.closeUp));
      expect(styleIdx, lessThan(shotIdx));
    });

    test('纯动作镜头（无角色无场景）也能出合法 Prompt', () {
      final result = PromptAssembler.buildShotPrompt(const PromptParts());
      expect(result.positive, contains('masterpiece'));
      expect(result.truncated, isFalse);
    });

    test('角色的负向 Prompt 与形态负向差异词都进入 negative', () {
      final result = PromptAssembler.buildShotPrompt(PromptParts(
        character: character(
          base: '1 girl, silver bob hair',
          negative: 'blurry',
          variations: const [
            CharacterVariation(
              id: 'v1',
              name: '战损',
              active: true,
              negativeDelta: 'blood, wounds',
            ),
          ],
        ),
      ));
      expect(result.positive, contains('silver bob hair'));
      expect(result.negative, contains('blurry'));
      expect(result.negative, contains('blood'));
      expect(result.appliedVariationName, '战损');
    });
  });

  group('形态差异词合并', () {
    test('基础词 + 差异词：差异词追加在尾部', () {
      final merged = PromptAssembler.mergeVariation(
        basePrompt: '1 girl, silver hair, black coat',
        positiveDelta: 'torn clothes, bloodstain',
      );
      expect(merged, startsWith('1 girl, silver hair, black coat'));
      expect(merged, contains('torn clothes'));
      expect(merged, contains('bloodstain'));
    });

    test('差异词与基础词重复时去重（否则引擎注意力翻倍）', () {
      final merged = PromptAssembler.mergeVariation(
        basePrompt: 'silver hair, blue eyes',
        positiveDelta: 'silver hair, scar on cheek',
      );
      // "silver hair" 只应出现一次。
      expect('silver hair'.allMatches(merged), hasLength(1));
      expect(merged, contains('scar on cheek'));
    });

    test('差异词完全是基础词子集时返回基础词', () {
      final merged = PromptAssembler.mergeVariation(
        basePrompt: 'silver hair, blue eyes',
        positiveDelta: 'silver hair',
      );
      expect(merged, 'silver hair, blue eyes');
    });

    test('空差异词与原样返回；空基础词则差异词顶上', () {
      expect(
        PromptAssembler.mergeVariation(basePrompt: 'a, b', positiveDelta: ''),
        'a, b',
      );
      expect(
        PromptAssembler.mergeVariation(basePrompt: '', positiveDelta: 'c, d'),
        'c, d',
      );
    });
  });

  group('长度上限与截断', () {
    test('正常 Prompt 不截断', () {
      final result = PromptAssembler.buildShotPrompt(PromptParts(
        styleTokens: 'cinematic still, 8k',
        shotSize: 'close-up',
        character: character(base: '1 girl, silver bob hair, black coat'),
      ));
      expect(result.truncated, isFalse);
      expect(result.droppedSegments, isEmpty);
      expect(PromptAssembler.wordCount(result.positive),
             lessThanOrEqualTo(kMaxPromptWords));
    });

    test('超过 750 词时从尾部丢弃并标记 truncated', () {
      // 造一个 400 词的角色 Prompt 与 360 词的场景 Prompt。
      final longBase = List.generate(400, (i) => 'detail$i').join(', ');
      final longScene = List.generate(360, (i) => 'bg$i').join(', ');

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        styleTokens: 'cinematic still',
        shotSize: 'close-up',
        character: character(base: longBase),
        scene: SceneCard(
          id: 's1',
          name: '雨巷',
          promptEn: longScene,
          updatedAt: DateTime(2026),
        ),
        cameraMove: 'slow push-in',
      ));

      expect(result.truncated, isTrue);
      expect(PromptAssembler.wordCount(result.positive),
             lessThanOrEqualTo(kMaxPromptWords));
      // 被丢的应是尾部段落（运镜词与场景），而不是角色基础词。
      expect(result.positive, contains('detail0'), reason: '角色描述必须保住');
      expect(result.droppedSegments, isNotEmpty);
    });

    test('恰好等于上限时不截断', () {
      // 画质基线 4 词，剩下的用 styleTokens 补足到 750。
      const baselineWords = 4;
      final filler =
          List.generate(kMaxPromptWords - baselineWords, (i) => 'w$i').join(', ');
      final result = PromptAssembler.buildShotPrompt(PromptParts(
        styleTokens: filler,
      ));
      expect(PromptAssembler.wordCount(result.positive), kMaxPromptWords);
      expect(result.truncated, isFalse);
    });

    test('风格词整段超长时，保住基线并丢弃该段', () {
      // 单个段落比整个预算还长：它会被整段丢弃，Prompt 只剩画质基线。
      // 这是有意的取舍——一段吃垮预算的词，说明它是用户误粘的长文，
      // 而那不该把景别、角色、运镜全部挤出 Prompt。
      final filler = List.generate(kMaxPromptWords * 2, (i) => 'w$i').join(', ');
      final result = PromptAssembler.buildShotPrompt(PromptParts(
        styleTokens: filler,
        shotSize: 'close-up',
        cameraMove: 'slow push-in',
      ));
      expect(result.truncated, isTrue);
      expect(PromptAssembler.wordCount(result.positive),
          lessThanOrEqualTo(kMaxPromptWords));
      expect(result.positive, contains('masterpiece'), reason: '画质基线必须保住');
      // 风格词被整段丢下后，景别与运镜词仍有位置。
      expect(result.positive, contains('close-up'));
      expect(result.positive, contains('slow push-in'));
    });
  });

  group('标签映射表', () {
    test('五种景别都有英文摄影词且互不相同', () {
      final tokens = StudioShotSize.values.map(ShotSizeTokens.of).toSet();
      expect(tokens, hasLength(StudioShotSize.values.length));
    });

    test('情绪标签都有光线词', () {
      for (final mood in [
        'depressing', 'excited', 'warm', 'battle',
        'suspense', 'relaxed', 'sad',
      ]) {
        expect(MoodTokens.of(mood), isNot('cinematic lighting'),
               reason: '$mood 应有专属光线词，而不是落到兜底');
      }
    });

    test('未知情绪落到兜底词而不是抛异常', () {
      expect(MoodTokens.of('unknown-mood'), 'cinematic lighting');
    });
  });

  group('连续性台账 → 提示词段', () {
    test('全空台账返回空串', () {
      expect(ContinuityTokens.of(ShotContinuity.empty), '');
    });

    test('只填了部分字段时不产生断句', () {
      // 逐字段拼而不是套模板：用户常常只填一两项，模板会产出
      // 「角色位于，左手持有」这种断句。
      final text = ContinuityTokens.of(const ShotContinuity(
        worldPosition: '巷口左侧',
        holdingRight: '折叠刀',
      ));
      expect(text, '角色位于巷口左侧，右手持有折叠刀');
      expect(text, isNot(contains('，右手持有。')));
    });

    test('stateChanges 每项都带「本镜」前缀', () {
      final text = ContinuityTokens.of(const ShotContinuity(
        worldPosition: '诊室门口',
        stateChanges: ['左袖撕裂', '徽章掉落'],
      ));
      expect(text, contains('本镜左袖撕裂'));
      expect(text, contains('本镜徽章掉落'));
    });
  });

  group('片段提示词组装', () {
    CharacterCard character(String name, {String base = ''}) => CharacterCard(
      id: 'c-$name',
      name: name,
      basePromptPositive: base,
      updatedAt: DateTime(2026),
    );

    SceneCard scene(String name, {String promptEn = ''}) => SceneCard(
      id: 's-$name',
      name: name,
      promptEn: promptEn,
      updatedAt: DateTime(2026),
    );

    test('参考图编号与传入列表一一对应', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          styleTokens: 'cinematic still',
          targetDurationSec: 8,
          characters: [character('林晓', base: '1girl, silver hair')],
          scenes: [scene('雨夜巷道', promptEn: 'rainy alley at night')],
          shots: const [
            SegmentShotParts(
              number: 1,
              actionZh: '女主背靠砖墙猛然回眸',
              cameraMove: 'slow push-in',
              continuity: ShotContinuity(
                worldPosition: '巷口左侧',
                holdingRight: '折叠刀',
              ),
            ),
          ],
        ),
        references: const [
          SegmentReference(label: 'lin.png', usage: '林晓角色参考'),
          SegmentReference(label: 'alley.png', usage: '雨夜巷道场景参考'),
        ],
      );
      expect(result.positive, contains('{{ref 1}}'));
      expect(result.positive, contains('{{ref 2}}'));
      // 编号顺序必须与 references 列表一致：1 是角色、2 是场景。
      expect(result.positive.indexOf('{{ref 1}}'),
          lessThan(result.positive.indexOf('{{ref 2}}')));
      expect(result.missingReferences, isEmpty);
    });

    test('没有参考图时不输出编号，并把缺口报给调用方', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          characters: [character('林晓', base: '1girl')],
          scenes: [scene('雨夜巷道', promptEn: 'rainy alley')],
          shots: const [SegmentShotParts(number: 1, actionZh: '回眸')],
        ),
      );
      expect(result.positive, isNot(contains('{{ref')));
      expect(result.missingReferences, hasLength(2));
      expect(result.missingReferences, contains('林晓 角色参考图'));
      expect(result.missingReferences, contains('雨夜巷道 场景参考图'));
    });

    test('连续性段被钉住：超限时不丢台账', () {
      // 台账段放在尾部附近，正是默认策略最先丢的位置。这里用超长的风格词
      // 把额度撑满，验证台账段仍然保留。
      final filler = List.filled(80, 'fillerword').join(', ');
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          styleTokens: filler,
          shots: const [
            SegmentShotParts(
              number: 1,
              actionZh: '回眸',
              continuity: ShotContinuity(
                worldPosition: '巷口左侧',
                holdingRight: '折叠刀',
              ),
            ),
          ],
        ),
      );
      // 台账段必须留下，无论总长度是否超限。
      expect(result.positive, contains('shot 1 state:'));
      expect(result.positive, contains('右手持有折叠刀'));
      // 超限时被丢的只能是可牺牲段（风格词/逐镜段），不能是台账。
      expect(result.droppedSegments.join(' '), isNot(contains('折叠刀')));
    });

    test('超限时优先丢风格词而不是台账', () {
      // 把风格词撑到超过 750 词：它必须被丢，台账必须留下。
      //
      // 注意：风格词是「单段就超限」的情形。`_joinWithinLimit` 对单段超限的
      // 处理是整段丢弃（与 buildShotPrompt 的既有行为一致），所以这里断言的是
      // 「风格词整段消失、台账留下」，而不是「风格词被部分保留」。
      final filler = List.filled(1200, 'fillerword').join(', ');
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          styleTokens: filler,
          shots: const [
            SegmentShotParts(
              number: 1,
              actionZh: '回眸',
              continuity: ShotContinuity(
                worldPosition: '巷口左侧',
                holdingRight: '折叠刀',
              ),
            ),
          ],
        ),
      );
      expect(result.truncated, isTrue);
      expect(result.positive, contains('右手持有折叠刀'));
    });

    test('多段累积超限时逐段丢弃，台账仍保留', () {
      // 每段都不超限但总和超限：验证丢弃顺序是从尾部往前，且钉住的台账
      // 即使排在尾部也不会被丢。
      //
      // 注意 wordCount 的分词不看中文逗号，所以动作段要用英文逗号连接的词
      // 才能真实累积额度。这里造 700 词风格 + 700 词动作，确保总和超限。
      final filler = List.filled(700, 'styleword').join(', ');
      final action = List.filled(700, 'actionword').join(', ');
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          styleTokens: filler,
          shots: [
            SegmentShotParts(
              number: 1,
              actionZh: action,
              cameraMove: 'slow push-in',
              continuity: const ShotContinuity(
                worldPosition: '巷口左侧',
                holdingRight: '折叠刀',
              ),
            ),
          ],
        ),
      );
      expect(result.truncated, isTrue);
      expect(result.positive, contains('右手持有折叠刀'));
      expect(result.droppedSegments.join(' '), isNot(contains('折叠刀')));
    });

    test('同一角色在多镜出场只写一次身份锚点', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          characters: [character('林晓', base: '1girl, silver hair')],
          shots: const [
            SegmentShotParts(number: 1, actionZh: '回眸'),
            SegmentShotParts(number: 2, actionZh: '咬牙'),
            SegmentShotParts(number: 3, actionZh: '转身'),
          ],
        ),
      );
      final occurrences = '1girl, silver hair'.allMatches(result.positive);
      expect(occurrences, hasLength(1));
      expect(result.positive, contains('shot 1'));
      expect(result.positive, contains('shot 2'));
      expect(result.positive, contains('shot 3'));
    });

    test('目标时长与逐镜段都出现在提示词里', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 12,
          shots: const [SegmentShotParts(number: 1, actionZh: '回眸')],
        ),
      );
      expect(result.positive, contains('12s'));
      expect(result.positive, contains('shot 1'));
    });

    test('空分镜列表不抛异常', () {
      final result = PromptAssembler.buildSegmentPrompt(
        const SegmentPromptParts(),
      );
      expect(result.positive, isNotEmpty);
      expect(result.missingReferences, isEmpty);
    });
  });
}
