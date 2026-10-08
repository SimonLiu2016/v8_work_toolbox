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
}
