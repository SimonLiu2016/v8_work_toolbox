import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

void main() {
  group('Inline Reference Injection Tests', () {
    test('injectInlineReferences adds tags to bound entities in action text', () {
      final text = '余小白推开客栈窗户向寒阳城长街张望，呼喊姜七夜。';
      final entityToRefTag = {
        '余小白': '图1',
        '姜七夜': '图2',
        '寒阳城长街': '图3',
      };
      final result = PromptAssembler.injectInlineReferences(
        text: text,
        entityToRefTag: entityToRefTag,
      );
      expect(
        result,
        '余小白(图1)推开客栈窗户向寒阳城长街(图3)张望，呼喊姜七夜(图2)。',
      );
    });

    test('injectInlineReferences does not double-inject on already tagged entities', () {
      final text = '余小白(图1)推开客栈窗户向寒阳城长街(图3)张望。';
      final entityToRefTag = {
        '余小白': '图1',
        '寒阳城长街': '图3',
      };
      final result = PromptAssembler.injectInlineReferences(
        text: text,
        entityToRefTag: entityToRefTag,
      );
      expect(result, '余小白(图1)推开客栈窗户向寒阳城长街(图3)张望。');
    });

    test('injectInlineReferences leaves unbound entities untouched', () {
      final text = '余小白喊住陌生路人。';
      final entityToRefTag = {
        '余小白': '图1',
      };
      final result = PromptAssembler.injectInlineReferences(
        text: text,
        entityToRefTag: entityToRefTag,
      );
      expect(result, '余小白(图1)喊住陌生路人。');
    });
  });

  group('Style Conflict Sanitizer Tests', () {
    test('Sanitizes live-action tokens when project is 3D/Anime', () {
      final prompt =
          'photorealistic 8k, live-action, arri alexa footage, UE5渲染, 3D国漫, 次世代CG, photorealistic 8k, 真人实拍';
      final sanitized = StyleConflictSanitizer.sanitizePrompt(
        text: prompt,
        isLiveAction: false,
      );
      expect(sanitized, isNot(contains('photorealistic')));
      expect(sanitized, isNot(contains('live-action')));
      expect(sanitized, isNot(contains('arri alexa')));
      expect(sanitized, isNot(contains('真人实拍')));
      expect(sanitized, contains('UE5渲染'));
      expect(sanitized, contains('3D国漫'));
      expect(sanitized, contains('次世代CG'));
    });

    test('Sanitizes anime/CG tokens when project is Live-Action', () {
      final prompt =
          'photorealistic 8k, live-action, UE5渲染, 3D国漫, 次世代CG, 35mm lens, 3D国漫';
      final sanitized = StyleConflictSanitizer.sanitizePrompt(
        text: prompt,
        isLiveAction: true,
      );
      expect(sanitized, isNot(contains('UE5渲染')));
      expect(sanitized, isNot(contains('3D国漫')));
      expect(sanitized, isNot(contains('次世代CG')));
      expect(sanitized, contains('photorealistic 8k'));
      expect(sanitized, contains('live-action'));
      expect(sanitized, contains('35mm lens'));
    });

    test('Deduplicates repeated tokens cleanly', () {
      final prompt = 'UE5渲染, 3D国漫, 次世代CG, UE5渲染, 3D国漫';
      final sanitized = StyleConflictSanitizer.sanitizePrompt(
        text: prompt,
        isLiveAction: false,
      );
      expect(sanitized, 'UE5渲染, 3D国漫, 次世代CG');
    });
  });

  group('buildShotPrompt End-to-End Inline Refs & Style Tests', () {
    test('injects inline references and purges style clashes in 3D anime mode', () {
      final char = CharacterCard(
        id: 'char_1',
        name: '余小白',
        descriptionZh: '青年捕快',
        referenceImages: const ['/path/to/yuxiaobai.png'],
        updatedAt: DateTime(2026, 1, 1),
      );
      final scene = SceneCard(
        id: 'scene_1',
        name: '寒阳城长街',
        descriptionZh: '青石板路夜雨',
        referenceImages: const ['/path/to/street.png'],
        updatedAt: DateTime(2026, 1, 1),
      );

      final parts = PromptParts(
        productionType: StudioProductionType.anime3d,
        styleTokens: 'photorealistic 8k, live-action, arri alexa footage, 3D国漫',
        characters: [char],
        scene: scene,
        actionZh: '余小白推开客栈窗户向寒阳城长街张望。',
        shotSize: 'medium',
      );

      final assembled = PromptAssembler.buildShotPrompt(parts);
      // Action contains inline reference
      expect(assembled.positive, contains('余小白(图1)'));
      expect(assembled.positive, contains('寒阳城长街(图2)'));
      // Contains structured mapping
      expect(assembled.positive, contains('【素材绑定映射】'));
      expect(assembled.positive, contains('- 图1: 余小白'));
      expect(assembled.positive, contains('- 图2: 寒阳城长街'));
      // Style conflict eliminated
      expect(assembled.positive, isNot(contains('photorealistic')));
      expect(assembled.positive, isNot(contains('live-action')));
      expect(assembled.positive, isNot(contains('arri alexa')));
    });
  });
}
