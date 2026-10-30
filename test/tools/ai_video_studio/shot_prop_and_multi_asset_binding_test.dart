import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';

void main() {
  group('1. ShotAssetBinding 多图支持与向前兼容测试', () {
    test('单图构造与 materialPath / materialPaths 双向映射', () {
      const binding = ShotAssetBinding(
        materialPath: 'character_front.png',
        role: ShotAssetRole.subject,
      );

      expect(binding.materialPath, equals('character_front.png'));
      expect(binding.materialPaths, equals(['character_front.png']));
      expect(binding.hasExplicitMaterial, isTrue);

      final json = binding.toJson();
      expect(json['material_path'], equals('character_front.png'));
      expect(json['material_paths'], equals(['character_front.png']));
    });

    test('多图构造与 materialPaths 展开', () {
      const binding = ShotAssetBinding(
        materialPaths: ['shot_angle1.png', 'shot_angle2.png'],
        role: ShotAssetRole.confrontation,
      );

      expect(binding.materialPath, equals('shot_angle1.png'));
      expect(binding.materialPaths, equals(['shot_angle1.png', 'shot_angle2.png']));
      expect(binding.hasExplicitMaterial, isTrue);

      final json = binding.toJson();
      expect(json['material_path'], equals('shot_angle1.png'));
      expect(json['material_paths'], equals(['shot_angle1.png', 'shot_angle2.png']));
    });

    test('从旧版 JSON 反序列化 (单 material_path 字符串)', () {
      final legacyJson = {
        'material_path': 'legacy_image.png',
        'role': 'supporting',
      };

      final parsed = ShotAssetBinding.fromJson(legacyJson);
      expect(parsed.materialPath, equals('legacy_image.png'));
      expect(parsed.materialPaths, equals(['legacy_image.png']));
      expect(parsed.role, equals(ShotAssetRole.supporting));
    });

    test('从新版 JSON 反序列化 (material_paths 数组)', () {
      final newJson = {
        'material_path': 'img1.png',
        'material_paths': ['img1.png', 'img2.png', 'img3.png'],
        'role': 'subject',
      };

      final parsed = ShotAssetBinding.fromJson(newJson);
      expect(parsed.materialPath, equals('img1.png'));
      expect(parsed.materialPaths, equals(['img1.png', 'img2.png', 'img3.png']));
    });
  });

  group('2. StudioShot propIds 字段与序列化测试', () {
    test('StudioShot 默认 propIds 为空列表', () {
      const shot = StudioShot(number: 1);
      expect(shot.propIds, isEmpty);
    });

    test('StudioShot copyWith 支持独立更新 propIds', () {
      const shot = StudioShot(number: 1, propIds: ['prop_sword']);
      final updated = shot.copyWith(propIds: ['prop_sword', 'prop_shield']);
      expect(updated.propIds, equals(['prop_sword', 'prop_shield']));
    });

    test('StudioShot 序列化与反序列化包含 prop_ids', () {
      const shot = StudioShot(
        number: 2,
        characterIds: ['char_yu'],
        propIds: ['prop_sword', 'prop_pill'],
        sceneId: 'sc_street',
      );

      final json = shot.toJson();
      expect(json['prop_ids'], equals(['prop_sword', 'prop_pill']));

      final restored = StudioShot.fromJson(json);
      expect(restored.propIds, equals(['prop_sword', 'prop_pill']));
      expect(restored.characterIds, equals(['char_yu']));
      expect(restored.sceneId, equals('sc_street'));
    });

    test('旧版缺少 prop_ids 的 JSON 反序列化平滑兼容', () {
      final legacyShotJson = {
        'number': 3,
        'action_zh': '测试动作',
        'character_ids': ['char_jiang'],
        'scene_id': 'sc_inn',
      };

      final restored = StudioShot.fromJson(legacyShotJson);
      expect(restored.propIds, isEmpty);
      expect(restored.characterIds, equals(['char_jiang']));
    });

    test('videoPromptSourceKeyOf 包含道具排序指纹', () {
      const shot1 = StudioShot(number: 1, actionZh: 'A', propIds: ['prop_b', 'prop_a']);
      const shot2 = StudioShot(number: 1, actionZh: 'A', propIds: ['prop_a', 'prop_b']);
      const shot3 = StudioShot(number: 1, actionZh: 'A', propIds: ['prop_c']);

      expect(shot1.videoPromptSourceKeyOf, equals(shot2.videoPromptSourceKeyOf));
      expect(shot1.videoPromptSourceKeyOf, contains('p=prop_a,prop_b'));
      expect(shot1.videoPromptSourceKeyOf, isNot(equals(shot3.videoPromptSourceKeyOf)));
    });
  });
}
