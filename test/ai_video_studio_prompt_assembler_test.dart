import 'dart:convert';
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
      expect(words.first, 'authentic film texture', reason: '画质基线必须最前');
      expect(words, contains('cinematic still'));
      expect(words, contains('camera: slow push-in'));
      expect(words.last, 'camera: slow push-in', reason: '运镜词最可牺牲，放最后');

      final styleIdx = words.indexOf('cinematic still');
      final shotIdx = words.indexOf(ShotSizeTokens.of(StudioShotSize.closeUp));
      expect(styleIdx, lessThan(shotIdx));
    });

    test('纯动作镜头（无角色无场景）也能出合法 Prompt，且包含防塑料 AI 负向词', () {
      final result = PromptAssembler.buildShotPrompt(const PromptParts());
      expect(result.positive, contains('authentic film texture'));
      expect(result.negative, contains('plastic skin'));
      expect(result.negative, contains('3d render doll'));
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
      final base = PromptAssembler.buildShotPrompt(const PromptParts()).positive;
      final baselineWords = PromptAssembler.wordCount(base);
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
      expect(result.positive, contains('authentic film texture'), reason: '画质基线必须保住');
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
          SegmentReference(label: 'lin.png', usage: '林晓'),
          SegmentReference(label: 'alley.png', usage: '雨夜巷道'),
        ],
      );
      expect(result.positive, contains('<Picture 1>'));
      expect(result.positive, contains('<Picture 2>'));
      // 编号顺序必须与 references 列表一致：1 是角色、2 是场景。
      expect(result.positive.indexOf('<Picture 1>'),
          lessThan(result.positive.indexOf('<Picture 2>')));
      expect(result.positive, isNot(contains('{{ref')));
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
      expect(result.positive, isNot(contains('<Picture')));
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
      expect(result.positive, contains('右手持有折叠刀'));
      expect(result.positive, isNot(contains('shot 1 state:')));
      // 超限时被丢的只能是可牺牲段（风格词/逐镜段），不能是台账。
      expect(result.droppedSegments.join(' '), isNot(contains('折叠刀')));
    });

    test('超限时优先丢风格词而不是台账', () {
      // 把风格词撑到超过 750 词：它必须被丢，台账必须留下。
      //
      // 注意：风格词是「单段就超限」的情形。`_joinWithinLimit` 对单段超限的
      // 处理是整段丢弃（与 buildShotPrompt 的既有行为一致），所以这里断言的是
      // 「风格词整段消失、台账留下」，而不是「风格词被部分保留」。
      // 用不重复的词避免被 deduplicatePhrases 智能去重。
      final filler = List.generate(1200, (i) => 'fillerword$i').join(', ');
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
      // 用不重复的词避免被 deduplicatePhrases 智能去重。
      final filler = List.generate(700, (i) => 'styleword$i').join(', ');
      final action = List.generate(700, (i) => 'actionword$i').join(', ');
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
      expect(result.positive, contains('回眸'));
      expect(result.positive, contains('咬牙'));
      expect(result.positive, contains('转身'));
      expect(result.positive, isNot(contains('shot 1')));
    });

    test('目标时长不泄露进提示词文本，动作自然整合', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          targetDurationSec: 12,
          shots: const [SegmentShotParts(number: 1, actionZh: '回眸')],
        ),
      );
      expect(result.positive, isNot(contains('12s')));
      expect(result.positive, isNot(contains('continuous single take')));
      expect(result.positive, contains('回眸'));
      expect(result.positive, isNot(contains('shot 1')));
    });

    test('空分镜列表不抛异常', () {
      final result = PromptAssembler.buildSegmentPrompt(
        const SegmentPromptParts(),
      );
      expect(result.positive, isNotEmpty);
      expect(result.missingReferences, isEmpty);
    });

    test('deduplicatePhrases 短语去重与互斥渲染器过滤', () {
      const input =
          '3D CGI animation, modern Chinese fantasy donghua, exquisite 3D render, '
          'Unreal Engine 5 render, Octane render, cinematic lighting, '
          '3D CGI animation, modern Chinese fantasy donghua, cinematic lighting';
      final cleaned = PromptAssembler.deduplicatePhrases(input);
      expect(cleaned, isNot(contains('Octane render')));
      expect(cleaned, contains('Unreal Engine 5 render'));
      expect(
        '3D CGI animation'.allMatches(cleaned),
        hasLength(1),
      );
      expect(
        'cinematic lighting'.allMatches(cleaned),
        hasLength(1),
      );
    });

    test('filterEmptySceneTokens 有角色时剔除空镜排他词，无角色时保留', () {
      const sceneWithEmpty =
          'ancient tavern, dim warm lighting, empty room, architectural interior, no humans';
      final filteredWithChars = PromptAssembler.filterEmptySceneTokens(
        sceneWithEmpty,
        hasCharacters: true,
      );
      expect(filteredWithChars, isNot(contains('empty room')));
      expect(filteredWithChars, isNot(contains('architectural interior')));
      expect(filteredWithChars, isNot(contains('no humans')));
      expect(filteredWithChars, contains('ancient tavern'));

      final keptWithoutChars = PromptAssembler.filterEmptySceneTokens(
        sceneWithEmpty,
        hasCharacters: false,
      );
      expect(keptWithoutChars, contains('empty room'));
      expect(keptWithoutChars, contains('no humans'));
    });

    test('对白保留为时间区间内的配音行，剧本标头被剥离，锁定主物理场景，机位协调', () {
      final result = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          productionType: StudioProductionType.anime3d,
          styleTokens:
              '3D CGI animation, modern Chinese fantasy donghua, Octane render',
          characters: [character('余小白', base: 'chubby young master')],
          scenes: [
            scene('酒楼', promptEn: 'ancient tavern, empty room, no humans'),
            scene('长街', promptEn: 'stone archway, street entrance'),
          ],
          shots: const [
            SegmentShotParts(
              number: 7,
              actionZh: '余小白双手端着盘子狠狠砸出',
              dialogue: '姜七夜，你给我站住！',
              cameraMove: 'static',
            ),
            SegmentShotParts(
              number: 8,
              actionZh: '长街两侧行人猛然止步避让',
              dialogue: '快躲开！',
              cameraMove: 'static',
            ),
          ],
        ),
        references: const [
          SegmentReference(label: 'yu.png', usage: '余小白'),
          SegmentReference(label: 'tavern.png', usage: '酒楼'),
          SegmentReference(label: 'street.png', usage: '长街'),
        ],
      );

      // 1. 去重与渲染器互斥：anime3d 默认 UE5，Octane render 被清洗
      expect(result.positive, isNot(contains('Octane render')));
      expect(result.positive, contains('Unreal Engine 5 render'));

      // 2. 官方 Picture 素材占位符
      expect(result.positive, contains('<Picture 1>'));
      expect(result.positive, contains('<Picture 2>'));
      expect(result.positive, isNot(contains('{{ref')));

      // 3. 锁定主场景，过滤第二场景与空镜词
      expect(result.positive, contains('scene: ancient tavern <Picture 2>'));
      expect(result.positive, isNot(contains('empty room')));
      expect(result.positive, isNot(contains('no humans')));
      expect(result.positive, isNot(contains('stone archway')));

      // 4. 剧本符号剥离（对白不再被剥，改为时间区间内的配音行——见
      //    fix-shot-causality-inversion-in-video-prompts：旧实现把 dialogue 整段
      //    删掉，导致片段提示词一句台词都没有，模型自己编谁在什么时间做什么）
      expect(result.positive, isNot(contains('dialogue:')));
      expect(result.positive, isNot(contains('shot 7 |')));
      expect(result.positive, isNot(contains('camera: static')));
      expect(result.positive, contains('对白：姜七夜，你给我站住！'));
      expect(result.positive, contains('对白：快躲开！'));
      // 对白是配音轨内容，画面全员闭口——含对白后必须补这层守卫。
      expect(result.positive, contains('声音与画面约束'));
      // 动作叙事不再被逗号压成一行，时间区间与动作/对白分行呈现。
      expect(result.positive, isNot(contains('余小白双手端着盘子狠狠砸出，长街两侧行人猛然止步避让')));
      expect(result.positive, contains('动作：余小白双手端着盘子狠狠砸出'));

      // 5. 机位协调：静态机位映射，屏蔽全局 dynamic airborne camera
      expect(result.positive, contains('static camera, steady composition'));
      expect(result.positive, isNot(contains('dynamic airborne camera')));
    });
  });

  group('四段式摄影机调度与多平台编译器', () {
    test('CameraStagingCompiler 生成四段式调度', () {
      final staging1 = CameraStagingCompiler.compile4Stage(
        cameraMove: 'low angle push-in',
        subjectName: '韩立',
        triggerAction: '反手掷出毒粉',
        endSettling: '锁定墨大夫面部特写定格',
      );
      expect(staging1, contains('起始：low angle push-in'));
      expect(staging1, contains('跟随：聚焦韩立'));
      expect(staging1, contains('触发：反手掷出毒粉'));
      expect(staging1, contains('落点：锁定墨大夫面部特写定格'));

      // 已有 cameraStaging 时直接返回
      final staging2 = CameraStagingCompiler.compile4Stage(
        cameraMove: 'push-in',
        cameraStaging: '由胸部中景急推至刀尖特写定格',
      );
      expect(staging2, '由胸部中景急推至刀尖特写定格');
    });

    test('SeedanceTaskCompiler 编译即梦执行稿及 Handoff 接力参数', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 3.5,
        shotSize: StudioShotSize.mediumCloseUp,
        mood: 'battle',
        function: ShotFunction.burst,
        actionZh: '墨大夫挥刃疾刺韩立咽喉',
        dialogue: '纳命来！',
        characterIds: ['c1'],
        sceneId: 's1',
        cameraMove: 'whip pan',
        directorDecisions: const DirectorDecisions(
          physicalMomentum: '重心完全前压',
          lightingStaging: '冷白闪电主光',
        ),
        combatSteps: const [
          CombatStep(
            stepIndex: 1,
            actorName: '墨大夫',
            targetNames: ['韩立'],
            intent: '直刺咽喉',
            attack: '右手短刃刺击',
            defense: '后仰闪避',
            impact: '刀锋擦过发丝',
            displacement: '前冲一丈',
            nextLink: '反手毒粉',
            duty: CombatShotDuty.impact,
          ),
        ],
        continuity: const ShotContinuity(
          dynamicExitState: DynamicExitState(
            supportFoot: '右脚前跨',
            velocityVector: '前冲2m/s',
            unfinishedPhase: '出招中途余势',
          ),
        ),
      );

      final segment = StudioSegment(
        id: 'SEG001',
        targetDurationSec: 4,
        shotNumbers: const [1],
      );

      final seedance = SeedanceTaskCompiler.compileSegment(
        segment: segment,
        shots: [shot],
        characters: [
          CharacterCard(
            id: 'c1',
            name: '墨大夫',
            descriptionZh: '面色铁青枯瘦老者，青袍配短刃',
            updatedAt: DateTime(2026),
          ),
        ],
        scenes: [
          SceneCard(
            id: 's1',
            name: '神手谷密室',
            descriptionZh: '药架密布的昏暗石室',
            updatedAt: DateTime(2026),
          ),
        ],
      );

      expect(seedance, contains('【单段目标时长】4秒'));
      expect(seedance, contains('主体【墨大夫】：面色铁青枯瘦老者'));
      expect(seedance, contains('场景【神手谷密室】'));
      expect(seedance, contains('[0.0s - 3.5s] 镜号 1'));
      expect(seedance, contains('物理动势：重心完全前压'));
      expect(seedance, contains('攻防因果链：'));
      expect(seedance, contains('【剪辑接力 (Handoff Continuity)】'));
      expect(seedance, contains('出口接力：支撑脚=右脚前跨，末速度=前冲2m/s，未完成动势=出招中途余势'));
    });

    test('PhotorealisticPromptCompiler 编译原生纯中文结构化导演叙事提示词', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 4.0,
        shotSize: StudioShotSize.medium,
        mood: 'suspense',
        function: ShotFunction.opening,
        actionZh: '韩立背抵药架侧身戒备',
        dialogue: '（压低声音）弟子不知。',
        cameraMove: 'slow push-in',
        directorDecisions: const DirectorDecisions(
          physicalMomentum: '下沉重心贴墙蓄势',
          lightingStaging: '微弱暖油灯与冷窗光',
        ),
      );

      final prose = PhotorealisticPromptCompiler.compileShot(
        shot: shot,
        character: CharacterCard(
          id: 'c2',
          name: '韩立',
          descriptionZh: '肤色微黑的朴素青年',
          updatedAt: DateTime(2026),
        ),
      );

      expect(prose, contains('【出场主体】韩立（肤色微黑的朴素青年）'));
      expect(prose, contains('韩立背抵药架侧身戒备'));
      expect(prose, contains('物理动势（下沉重心贴墙蓄势）'));
      expect(prose, contains('【镜头景别与运镜】中景'));
      expect(prose, contains('光影氛围：微弱暖油灯与冷窗光'));
      expect(prose, contains('画外配音: "（压低声音）弟子不知。"'));
      expect(prose, contains('闭口神态'));
      expect(prose, contains('严禁开口嘴型与画内文字'));
      expect(prose, isNot(contains('Phase 1')));
      expect(prose, isNot(contains('Subject:')));
    });

    test('PhotorealisticPromptCompiler 彻底剔除英文伪渲染器咒语并优先拉取中文服饰', () {
      final shot = StudioShot(
        number: 1,
        durationSec: 3.5,
        shotSize: StudioShotSize.full,
        actionZh: '姜七夜单手拔长刀出鞘，刀尖贯穿整只烤鸡，大口撕咬咀嚼',
        cameraMove: '全景平视跟随',
      );

      final prose = PhotorealisticPromptCompiler.compileShot(
        shot: shot,
        character: CharacterCard(
          id: 'c-jiang',
          name: '姜七夜',
          descriptionZh: '俊美腹黑的巡城卫狱卒',
          facialFeaturesZh: '二十岁出头，剑眉英挺，身姿挺拔',
          defaultAttireZh: '着暗青色巡城卫制服，腰系朴素革带',
          basePromptPositive: 'handsome young man, 3D CGI animation, Unreal Engine 5 render, Octane render',
          updatedAt: DateTime(2026),
        ),
        scene: SceneCard(
          id: 's-changjie',
          name: '寒阳城长街',
          descriptionZh: '寒阳城长街，黄昏斜阳穿透长街，远处朱漆酒楼天人居矗立',
          promptEn: 'ancient chinese street, UE5 render, Octane render',
          updatedAt: DateTime(2026),
        ),
        styleTokens: 'UE5 render, Octane render, 3D CGI animation, 国风次世代',
      );

      // 验证彻底过滤掉英文伪渲染器咒语
      expect(prose, isNot(contains('UE5')));
      expect(prose, isNot(contains('Octane')));
      expect(prose, isNot(contains('3D CGI')));
      expect(prose, isNot(contains('Unreal Engine')));
      expect(prose, contains('【画风基调】国风次世代'));

      // 验证优先提取中文容貌与服饰
      expect(prose, contains('二十岁出头，剑眉英挺，身姿挺拔'));
      expect(prose, contains('着暗青色巡城卫制服，腰系朴素革带'));
      expect(prose, isNot(contains('handsome young man')));

      // 验证中文场景提取
      expect(prose, contains('寒阳城长街，黄昏斜阳穿透长街，远处朱漆酒楼天人居矗立'));
    });

    test('PhotorealisticPromptCompiler 严格音画分流：角色内心 OS 保持闭口与从容微表情', () {
      final shot = StudioShot(
        number: 2,
        durationSec: 4.0,
        shotSize: StudioShotSize.mediumCloseUp,
        actionZh: '姜七夜咬着烤鸡，神色从容，嘴角掠过戏谑笑意',
        dialogue: '姜七夜（内心 OS）：高空抛物啊，放在我前世，至少拘你半个月。',
      );

      final prose = PhotorealisticPromptCompiler.compileShot(shot: shot);

      expect(prose, contains('【声音与画面约束】'));
      expect(prose, contains('角色心声/画外音: "姜七夜（内心 OS）：高空抛物啊，放在我前世，至少拘你半个月。"'));
      expect(prose, contains('画面主体保持自然闭口与从容微表情'));
      expect(prose, contains('严禁开口嘴型与画内文字'));
    });

    test('PhotorealisticPromptCompiler.compileSegment 编译多镜中文剧本段落', () {
      final shots = [
        StudioShot(
          number: 1,
          durationSec: 3.0,
          shotSize: StudioShotSize.medium,
          actionZh: '姜七夜骑高大青驴缓行',
        ),
        StudioShot(
          number: 2,
          durationSec: 4.0,
          shotSize: StudioShotSize.closeUp,
          actionZh: '姜七夜抬头望向酒楼窗口',
          dialogue: '余小白（大喊）：姜七夜你这个王八蛋！',
        ),
      ];

      final segmentProse = PhotorealisticPromptCompiler.compileSegment(
        segment: const StudioSegment(
          id: 'seg1',
          targetDurationSec: 7,
          boundaryReason: '长街偶遇',
          shotNumbers: [1, 2],
        ),
        shots: shots,
      );

      expect(segmentProse, contains('【分镜 1（3.0秒）】'));
      expect(segmentProse, contains('【分镜 2（4.0秒）】'));
      expect(segmentProse, contains('姜七夜骑高大青驴缓行'));
      expect(segmentProse, contains('余小白（大喊）：姜七夜你这个王八蛋！'));
      expect(segmentProse, isNot(contains('[Shot 1')));
    });

    test('H3CsvCompiler 编译符合规范的六列 CSV（UTF-8 BOM 与 CRLF）', () {
      final episode = StudioEpisode(
        id: 'ep1',
        seriesId: 's1',
        title: '密室对决',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final shot = StudioShot(
        number: 1,
        durationSec: 3.5,
        shotSize: StudioShotSize.closeUp,
        mood: 'battle',
        function: ShotFunction.burst,
        actionZh: '刀锋相碰火星四溅',
        dialogue: '受死！',
      );

      final bytes = H3CsvCompiler.compileCsvBytes(
        episode: episode,
        shots: [shot],
      );

      // 验证 UTF-8 BOM: 0xEF, 0xBB, 0xBF
      expect(bytes.length, greaterThan(3));
      expect(bytes[0], 0xEF);
      expect(bytes[1], 0xBB);
      expect(bytes[2], 0xBF);

      // 解码并验证 CRLF 与六列表头
      final csvString = utf8.decode(bytes.sublist(3));
      expect(csvString, contains('\r\n'));
      expect(csvString, startsWith('序号,图片提示词,视频提示词,首帧提示词,尾帧提示词,文案\r\n'));

      final rows = csvString.split('\r\n').where((r) => r.isNotEmpty).toList();
      expect(rows.length, 2); // 表头 + 1行数据
      final cols = rows[0].split(',');
      expect(cols, ['序号', '图片提示词', '视频提示词', '首帧提示词', '尾帧提示词', '文案']);
    });
  });

  group('Agnes 官方多图与提示词结构契约 (align-keyframe-prompt-and-scene-reference-with-agnes-spec)', () {
    test('多图模式生成符合 Agnes 官方规范的自然语言声明与保留要求', () {
      final char1 = CharacterCard(
        id: 'c-jiang',
        name: '姜七夜',
        basePromptPositive: 'handsome young guard',
        updatedAt: DateTime(2026),
      );
      final char2 = CharacterCard(
        id: 'c-wang',
        name: '老王',
        basePromptPositive: 'veteran guard with beard',
        updatedAt: DateTime(2026),
      );
      final sceneJail = SceneCard(
        id: 's-jail',
        name: '巡城司大牢',
        descriptionZh: '青石条地面泛着水光，粗木铁栏向暗处延伸，柏木旧案摆放油灯与刑架',
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        characters: [char1, char2],
        scene: sceneJail,
        actionZh: '姜七夜单手按刀，手指轻敲刀鞘，神态不羁',
        dialogue: '老王，别紧张。',
        isMultiImage: true,
      ));

      // 验证自然语言多图声明
      expect(result.positive, contains('【参考图角色与保留要求】:'));
      expect(result.positive, contains('将第1张图作为主要角色（姜七夜），第2张图作为次要角色（老王），第3张图作为背景场景参考（巡城司大牢）'));
      expect(result.positive, contains('严格保留角色的面容身形与服装特征'));
      expect(result.positive, contains('保留场景图中的建筑材质与环境光影风格，镜头根据当前分镜动作动态取景'));
    });

    test('核心动作与戏剧焦点置顶前置，注意力权重纠偏', () {
      final char = CharacterCard(
        id: 'c-jiang',
        name: '姜七夜',
        basePromptPositive: 'handsome guard in dark cyan uniform',
        updatedAt: DateTime(2026),
      );
      final scene = SceneCard(
        id: 's-jail',
        name: '巡城司大牢',
        descriptionZh: '粗木铁栏与泛黄囚册',
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        character: char,
        scene: scene,
        actionZh: '姜七夜拔刀横斩，刀锋带起凌厉寒光',
        dialogue: '谁敢动他！',
        dialogueSpeaker: '姜七夜',
        styleTokens: 'UE5 3D国漫渲染',
      ));

      // 验证动作焦点段位于主体与场景之前
      expect(result.positive, contains('【核心视觉动作与焦点】: 姜七夜拔刀横斩，刀锋带起凌厉寒光，姜七夜说话态势：“谁敢动他！”'));
      final actionIdx = result.positive.indexOf('【核心视觉动作与焦点】');
      final charIdx = result.positive.indexOf('【出场主体】');
      final sceneIdx = result.positive.indexOf('【场景物理环境】');
      final styleIdx = result.positive.indexOf('UE5 3D国漫渲染');

      expect(actionIdx, lessThan(charIdx), reason: '核心动作必须置于角色描述之前');
      expect(charIdx, lessThan(sceneIdx), reason: '角色主体置于场景物理环境之前');
      expect(sceneIdx, lessThan(styleIdx), reason: '场景环境置于风格画质基线之前');
    });

    test('优先提取场景卡与七方位视角的中文物理细节（descriptionZh）', () {
      final scene = SceneCard(
        id: 's-jail',
        name: '巡城司大牢',
        descriptionZh: '巡城司大牢值房，青石条地面泛着水光，粗木铁栏向暗处延伸，柏木旧案摆放油灯与刑架',
        promptEn: 'ancient jail room, iron bars',
        spatialViews: {
          'front': const SceneDirectionalView(
            direction: SceneDirection.front,
            descriptionZh: '正前方正面正对粗木牢门与暗红色封条',
            promptEn: 'front view of heavy jail door',
          ),
        },
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        scene: scene,
        cameraDirection: SceneDirection.front,
        actionZh: '脚步声回荡在幽深走廊',
      ));

      expect(result.positive, contains('巡城司大牢值房，青石条地面泛着水光'));
      expect(result.positive, contains('视角空间：正前方正面正对粗木牢门与暗红色封条'));
      expect(result.positive, contains('front view of heavy jail door'));
    });

    test('室内/地下大牢场景画风自适应净化：剔除云海雾气并注入室内微光', () {
      final jailScene = SceneCard(
        id: 's-jail',
        name: '巡城司大牢',
        descriptionZh: '阴暗潮湿的值房水牢',
        updatedAt: DateTime(2026),
      );

      const xianxiaStyle =
          'UE5渲染，3D国漫，次世代CG，PBR物理材质，超精细发丝，体积光，云海雾气，全局光照，开阔天空，群山，日出日落，宏大构图';

      final indoorResult = PromptAssembler.buildShotPrompt(PromptParts(
        scene: jailScene,
        styleTokens: xianxiaStyle,
        actionZh: '老王战战兢兢递过钥匙',
      ));

      // 验证室外天空云海互斥词被完全剥离
      expect(indoorResult.positive, isNot(contains('云海雾气')));
      expect(indoorResult.positive, isNot(contains('开阔天空')));
      expect(indoorResult.positive, isNot(contains('群山')));
      expect(indoorResult.positive, isNot(contains('日出日落')));
      // 验证注入了室内微光
      expect(indoorResult.positive, contains('室内局部微光，环境阴影与真实空间质感'));
      // 验证保留了核心国漫材质词
      expect(indoorResult.positive, contains('UE5渲染'));
      expect(indoorResult.positive, contains('3D国漫'));
      expect(indoorResult.positive, contains('PBR物理材质'));

      // 对比验证：室外场景（长街/山门）保留云海与开阔天空
      final outdoorScene = SceneCard(
        id: 's-mountain',
        name: '青云山门',
        descriptionZh: '开阔山道与汉白玉石阶',
        updatedAt: DateTime(2026),
      );

      final outdoorResult = PromptAssembler.buildShotPrompt(PromptParts(
        scene: outdoorScene,
        styleTokens: xianxiaStyle,
        actionZh: '仙鹤振翅掠过山门',
      ));

      expect(outdoorResult.positive, contains('云海雾气'));
      expect(outdoorResult.positive, contains('开阔天空'));
      expect(outdoorResult.positive, contains('群山'));
    });

    test('多参考图分镜生图剥离主库静态容貌，仅输出画内站位（姜七夜与老王大牢分镜）', () {
      final char1 = CharacterCard(
        id: 'c-jiang',
        name: '姜七夜',
        basePromptPositive: '二十岁出头剑眉星目身着玄青色巡城司制服腰挎雁翎刀',
        updatedAt: DateTime(2026),
      );
      final char2 = CharacterCard(
        id: 'c-wang',
        name: '老王',
        basePromptPositive: '五十余岁面容枯瘦褶皱身着洗得发白的狱卒灰袍',
        updatedAt: DateTime(2026),
      );
      final jailScene = SceneCard(
        id: 's-jail',
        name: '巡城司大牢',
        descriptionZh: '阴暗潮湿的值房水牢',
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        characters: [char1, char2],
        scene: jailScene,
        actionZh: '单手按刀，垂眸立于案前，指尖有节奏地轻敲刀鞘',
        continuity: const ShotContinuity(worldPosition: '案前'),
        isMultiImage: true,
      ));

      // 验证彻底剔除 500+ 字静态容貌档案长文
      expect(result.positive, isNot(contains('二十岁出头剑眉星目身着玄青色巡城司制服腰挎雁翎刀')));
      expect(result.positive, isNot(contains('五十余岁面容枯瘦褶皱身着洗得发白的狱卒灰袍')));

      // 验证站位解耦：专职描述画内空间主客关系
      expect(
        result.positive,
        contains(
          '【同框人物与站位】: 2 people in scene，姜七夜居中案前近景（主景核心焦点），老王立于右侧对峙（次景呼应）',
        ),
      );

      // 验证核心动作前置强化
      expect(
        result.positive,
        contains('【核心视觉动作与焦点】: 单手按刀，垂眸立于案前，指尖有节奏地轻敲刀鞘'),
      );

      // 验证动态取景指令
      expect(
        result.positive,
        contains('保留场景图中的建筑材质与环境光影风格，镜头根据当前分镜动作动态取景'),
      );
    });

    test('单角色在具备参考图时剥离静态容貌，仅输出主体焦点与即时变体', () {
      final char = CharacterCard(
        id: 'c-jiang',
        name: '姜七夜',
        faceAnchorPath: 'face_anchor.png',
        basePromptPositive: 'handsome young guard in dark cyan uniform',
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        character: char,
        variation: const CharacterVariation(
          id: 'v-damaged',
          name: '战损',
          positiveDelta: '战损血痕，右臂衣袖撕裂',
          active: true,
        ),
        actionZh: '挥刀斩断锁链',
        hasCharacterReferences: true,
      ));

      // 验证剥离静态外观
      expect(result.positive, isNot(contains('handsome young guard in dark cyan uniform')));
      // 验证保留即时变体增量
      expect(
        result.positive,
        contains('【出场主体】: 姜七夜（画面核心主体，当前状态：战损血痕，右臂衣袖撕裂）'),
      );
      // 验证核心动作
      expect(result.positive, contains('【核心视觉动作与焦点】: 挥刀斩断锁链'));
    });

    test('纯文本生图模式（无任何参考图）保留 basePromptPositive 兜底外观描述', () {
      final char = CharacterCard(
        id: 'c-jiang',
        name: '姜七夜',
        basePromptPositive: 'handsome young guard in dark cyan uniform',
        updatedAt: DateTime(2026),
      );

      final result = PromptAssembler.buildShotPrompt(PromptParts(
        character: char,
        actionZh: '立于窗前',
        hasCharacterReferences: false,
        isMultiImage: false,
      ));

      // 纯文生图保留 base 描述
      expect(result.positive, contains('handsome young guard in dark cyan uniform'));
    });
  });
}

