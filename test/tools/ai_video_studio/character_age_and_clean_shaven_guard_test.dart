import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

void main() {
  group('CharacterTurnaroundProportion 标准体态比例中立化', () {
    test('标准比例移除 mature adult anatomy 与 tall and slender figure 偏置', () {
      final anchor = CharacterTurnaroundProportion.standard.positiveAnchor;
      expect(anchor, contains('标准7~8头身成人体态比例'));
      expect(anchor, contains('写实人体结构'));
      expect(anchor, contains('身材修长挺拔匀称'));
    });
  });

  group('PromptAssembler 年龄感知与无须防御守卫 (Clean-shaven Guard)', () {
    test('当中文描述包含白胖少年时自动注入正向与负向无须守卫', () {
      const descZh = '天人居酒楼少东家，姜七夜儿时小弟。油头粉面的白胖少年，面色红润，笑容戏谑。身着花花绿绿的锦缎长衫，腰间挂玉佩；下着宽松锦裤与绣花布鞋，常提酒杯，体态富态。';
      final positivePrompt = CharacterTurnaroundPrompt.build(
        'young wealthy heir, round face, colorful silk robe',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: descZh,
      );

      expect(positivePrompt, contains('面部光洁无须'));
      expect(positivePrompt, contains('少年青涩容貌'));
      expect(positivePrompt, contains('无胡须'));

      final negativePrompt = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'lowres, blurry',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: descZh,
      );

      expect(negativePrompt, contains('胡须'));
      expect(negativePrompt, contains('胡茬'));
    });

    test('当负向词输入中文长胡子时自动激活无须防御', () {
      final positivePrompt = CharacterTurnaroundPrompt.build(
        'a young boy in hanfu',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        negativePrompt: '长胡子, 粗糙',
      );

      expect(positivePrompt, contains('面部光洁无须'));
      expect(positivePrompt, contains('无胡须'));
    });

    test('当描述为成熟蓄须中年时不误触发无须守卫', () {
      const descZh = '天人居酒楼大掌柜，蓄美髯的中年商人，稳重端庄。';
      final positivePrompt = CharacterTurnaroundPrompt.build(
        'middle-aged merchant, trimmed beard, silk robe',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: descZh,
      );

      expect(positivePrompt, isNot(contains('面部光洁无须')));
    });
  });

  group('PromptAssembler 中文差异词映射与形态合成', () {
    test('normalizeDeltaWords 正确将中文自然语言差异词翻译映射为标准英文词', () {
      final boyNorm = PromptAssembler.normalizeDeltaWords('少年, 富态');
      expect(boyNorm, contains('youthful teenager, young boy, clean-shaven'));
      expect(boyNorm, contains('plump wealthy figure, prosperous build'));

      final beardNorm = PromptAssembler.normalizeDeltaWords('长胡子', isNegative: true);
      expect(beardNorm, contains('beard, mustache, facial hair, goatee, stubble'));

      final cleanNorm = PromptAssembler.normalizeDeltaWords('去胡子');
      expect(cleanNorm, contains('clean-shaven, hairless face, smooth chin'));

      final battleNorm = PromptAssembler.normalizeDeltaWords('战损');
      expect(battleNorm, contains('battle damaged, torn clothes, bruised, light wounds'));
    });

    test('mergeVariation 支持中文正向差异词翻译并融入主提示词', () {
      final base = 'round face, colorful silk robe';
      final merged = PromptAssembler.mergeVariation(basePrompt: base, positiveDelta: '少年');
      expect(merged, contains('youthful teenager, young boy, clean-shaven'));
      expect(merged, contains('round face, colorful silk robe'));
    });

    test('mergeNegativeVariation 正确支持中文负向差异词并合并', () {
      final baseNeg = 'lowres, bad anatomy';
      final mergedNeg = PromptAssembler.mergeNegativeVariation(baseNegative: baseNeg, negativeDelta: '长胡子');
      expect(mergedNeg, contains('lowres, bad anatomy'));
      expect(mergedNeg, contains('beard, mustache, facial hair, goatee, stubble'));
    });

    test('buildForVariation 在 inheritBaseFace 为 false 时不绑定底图面容特征', () {
      final character = CharacterCard(
        id: 'c1',
        name: '白胖少年',
        descriptionZh: '油头粉面的白胖少年',
        basePromptPositive: 'young boy, silk robe',
        updatedAt: DateTime(2026, 1, 1),
        variations: [
          CharacterVariation(
            id: 'v1',
            name: '青年形态',
            positiveDelta: '少年',
          ),
        ],
      );

      final withFace = CharacterTurnaroundPrompt.buildForVariation(
        character: character,
        variation: character.variations.first,
        styleTokens: 'traditional anime',
        proportion: CharacterTurnaroundProportion.standard,
        inheritBaseFace: true,
      );
      expect(withFace, contains('完全一致的人物面容身份'));
      expect(withFace, contains('与基准参考图保持相同的五官神态特征'));

      final withoutFace = CharacterTurnaroundPrompt.buildForVariation(
        character: character,
        variation: character.variations.first,
        styleTokens: 'traditional anime',
        proportion: CharacterTurnaroundProportion.standard,
        inheritBaseFace: false,
      );
      expect(withoutFace, isNot(contains('完全一致的人物面容身份')));
      expect(withoutFace, isNot(contains('与基准参考图保持相同的五官神态特征')));
      expect(withoutFace, contains('面部光洁无须'));
    });
  });

  group('AiConstraintEngine 角色提示词翻译规则强化', () {
    test('翻译约束模板明确包含无须守卫与少年体型映射规则', () {
      final prompt = AiConstraintEngine.systemPromptFor(
        StudioAiTask.promptTranslation,
      );
      expect(prompt, contains('clean-shaven, hairless face, smooth bare chin'));
      expect(prompt, contains('youthful teenage face'));
      expect(prompt, contains('chubby build, plump body, fair-skinned'));
      expect(prompt, contains('beard, mustache, facial hair, goatee, stubble'));
    });
  });

  group('全年龄段骨骼防漂移自适应与矮壮体态语义保护 (spec: character-turnaround-sheet)', () {
    test('十六岁矮壮微胖少年（余小白用例）成功注入少年骨架并解绑修长挺拔且采用纯肯定句', () {
      const yuXiaobaiDesc =
          '余小白：十六岁少年，白胖圆脸，油头粉面，鼻头圆润，唇红齿白，头发以头油抹得一丝不乱并束成圆髻，身材矮壮敦实。';

      final ageGroup = CharacterTurnaroundPrompt.detectAgeGroup(
        descriptionZh: yuXiaobaiDesc,
      );
      expect(ageGroup, equals(CharacterAgeGroup.teen));

      final isPlumpOrStout = CharacterTurnaroundPrompt.hasPlumpOrStoutBuild(
        descriptionZh: yuXiaobaiDesc,
      );
      expect(isPlumpOrStout, isTrue);

      final positivePrompt = CharacterTurnaroundPrompt.build(
        '16 years old teenage boy, plump round face, neat topknot, sturdy stocky figure',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: yuXiaobaiDesc,
      );

      // 1. 验证正向注入了纯肯定式少年骨架与青年身长
      expect(positivePrompt, anyOf(contains('接近成年男性的纵向骨骼身长'), contains('青少年身高')));
      expect(positivePrompt, contains('16岁青年男子身量'));
      expect(positivePrompt, contains('身高约168cm'));
      expect(positivePrompt, contains('身长比例符合矮壮敦实设定'));

      // 2. 核心验证：正向绝对严禁出现任何低幼否定词，杜绝“粉色大象效应”
      expect(positivePrompt, isNot(contains('非低幼儿童')));
      expect(positivePrompt, isNot(contains('非幼童童子')));
      expect(positivePrompt, isNot(contains('非小娃娃')));
      expect(positivePrompt, isNot(contains('非低幼矮短')));

      // 3. 核心验证：绝对不可被硬塞“身材修长挺拔匀称”导致 AI 头身比坍塌
      expect(positivePrompt, isNot(contains('身材修长挺拔匀称')));

      // 4. 验证负向强力注入低幼年画娃娃排斥词
      final negativePrompt = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'lowres, blurry',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: yuXiaobaiDesc,
      );
      expect(negativePrompt, contains('低幼儿童'));
      expect(negativePrompt, contains('大头娃娃'));
      expect(negativePrompt, contains('年画福娃'));
      expect(negativePrompt, contains('胡须'));
    });

    test('年龄回溯自愈机制：容貌框缺少数字时自动从总述回溯并置顶注入明确年龄', () {
      // 容貌框只有外貌描述，无年龄数字
      const facialOnly = '白胖圆润，油头粉面，小眼睛狡黠坏笑，黑发油亮，身材矮胖壮实。';
      // 总述中含有真实年龄
      const fullDesc = '十五六岁左右的白胖少年，油头粉面，面露戏谑坏笑时双眼微眯。身穿花花绿绿的富贵绸衫，纨绔少爷。';

      final positivePrompt = CharacterTurnaroundPrompt.build(
        '余小白，白胖圆润，油头粉面，身材矮胖壮实',
        descriptionZh: facialOnly,
        fullDescriptionZh: fullDesc,
        proportion: CharacterTurnaroundProportion.standard,
      );

      // 验证成功从 fullDescriptionZh 抓取到了“十五六岁”并归一化为 16 岁青年置顶
      expect(positivePrompt, contains('16岁青年男子身量'));
      expect(positivePrompt, contains('身高约168cm'));
      expect(positivePrompt, contains('已完成纵向骨架拔高拉伸'));
      expect(positivePrompt, isNot(contains('非低幼儿童')));
      expect(positivePrompt, isNot(contains('非小娃娃')));
    });

    test('幼童设定（7岁小道童）保留童稚体态，不强加成人骨骼与非低幼排斥', () {
      const childDesc = '7岁小道童，稚气未脱，粉雕玉琢的小孩。';

      final ageGroup = CharacterTurnaroundPrompt.detectAgeGroup(
        descriptionZh: childDesc,
      );
      expect(ageGroup, equals(CharacterAgeGroup.child));

      final positivePrompt = CharacterTurnaroundPrompt.build(
        '7 years old little boy daoist, cute kid',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: childDesc,
      );

      expect(positivePrompt, anyOf(contains('真实儿童体态比例'), contains('稚嫩面庞'), contains('稚嫩孩童身形')));
      expect(positivePrompt, isNot(contains('接近成年男性的纵向骨骼身长')));
      expect(positivePrompt, isNot(contains('非低幼儿童')));

      final negativePrompt = CharacterTurnaroundPrompt.buildNegative(
        baseNegative: 'lowres',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: childDesc,
      );
      // 幼童不应排斥低幼儿童
      expect(negativePrompt, isNot(contains('年画福娃')));
    });

    test('老年长者设定正确触发长者身姿与岁月骨相', () {
      const elderDesc = '六十岁白发苍苍的老道长，长者风范。';

      final ageGroup = CharacterTurnaroundPrompt.detectAgeGroup(
        descriptionZh: elderDesc,
      );
      expect(ageGroup, equals(CharacterAgeGroup.elder));

      final positivePrompt = CharacterTurnaroundPrompt.build(
        'elderly taoist master, white hair',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: elderDesc,
      );

      expect(positivePrompt, anyOf(contains('老年骨相与长者体态'), contains('长者身姿与长者骨相')));
    });

    test('青年常规修长身材角色正常保留修长挺拔匀称', () {
      const youthDesc = '李长寿，俊美青年修士，剑眉星目，身材挺拔。';

      final positivePrompt = CharacterTurnaroundPrompt.build(
        'young handsome cultivator, sharp brows',
        styleTokens: 'traditional donghua style',
        proportion: CharacterTurnaroundProportion.standard,
        descriptionZh: youthDesc,
      );

      expect(positivePrompt, contains('身材修长挺拔匀称'));
      expect(positivePrompt, anyOf(contains('骨骼完全成型'), contains('成熟身姿骨相'), contains('完全成型的成年写实骨架')));
    });
  });

  group('场景与道具规范 PromptBuilder 动态模板与排他约束 (Task 2.3)', () {
    test('ScenePromptBuilder 正确注入场景环境规范与人物排斥锁', () {
      final pos = ScenePromptBuilder.buildPositivePrompt(
        basePrompt: '古色古香的客栈大堂，桌椅整齐摆放',
        styleTokens: '3D国漫UE5渲染',
      );
      expect(pos, contains('纯净物理空间空镜头背景板'));
      expect(pos, contains('完全空无一人'));
      expect(pos, contains('虚位以待的无人空间'));

      final neg = ScenePromptBuilder.buildNegativePrompt();
      expect(neg, contains('人物'));
      expect(neg, contains('人群'));
    });

    test('PropPromptBuilder 正确注入道具资产单品设计图规范与手部排斥锁', () {
      final pos = PropPromptBuilder.buildPositivePrompt(
        prompt: '玄铁重剑，剑刃泛着寒光',
        styleTokens: '写实国风',
      );
      expect(pos, contains('专业道具资产概念设计图'));
      expect(pos, contains('纯白无缝背景'));
      expect(pos, contains('静物概念展台'));
      expect(pos, contains('玄铁重剑'));

      final neg = PropPromptBuilder.buildNegativePrompt();
      expect(neg, contains('多件物品'));
      expect(neg, contains('背景杂物'));
      expect(neg, contains('手部'));
      expect(neg, contains('身体遮挡'));
    });
  });
}
