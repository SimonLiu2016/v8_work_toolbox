import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

/// spec: shot-asset-binding · 第 1 组（素材绑定数据模型）
///
/// 锁死两件事：
/// 1. 候选枚举只列磁盘上真实存在的图，且默认项与生图路径的取材回退一致
///    ——这是「关键帧用三视图、视频用上传图」这条分裂的根治点；
/// 2. `assetBindings` 序列化往返不丢字段，旧 JSON 缺字段时按空绑定解析。
void main() {
  group('ShotAssetBinding', () {
    test('默认未显式指定素材', () {
      const b = ShotAssetBinding();
      expect(b.hasExplicitMaterial, isFalse);
      expect(b.materialPath, '');
      expect(b.role, ShotAssetRole.subject);
    });

    test('显式指定素材后 hasExplicitMaterial 为真', () {
      const b = ShotAssetBinding(materialPath: 'turnaround.png');
      expect(b.hasExplicitMaterial, isTrue);
    });

    test('序列化往返保留 materialPath 与 role', () {
      const b = ShotAssetBinding(
        materialPath: 'turnaround_var_123.png',
        role: ShotAssetRole.confrontation,
      );
      final restored = ShotAssetBinding.fromJson(b.toJson());
      expect(restored.materialPath, 'turnaround_var_123.png');
      expect(restored.role, ShotAssetRole.confrontation);
    });

    test('未知 role id 回落到 subject 而非抛异常', () {
      final b = ShotAssetBinding.fromJson({
        'material_path': 'a.png',
        'role': 'not_a_role',
      });
      expect(b.role, ShotAssetRole.subject);
    });

    test('copyWith 可单独改 materialPath 或 role', () {
      const b = ShotAssetBinding(materialPath: 'a.png');
      expect(b.copyWith(role: ShotAssetRole.supporting).materialPath, 'a.png');
      expect(b.copyWith(materialPath: 'b.png').role, ShotAssetRole.subject);
    });

    test('ShotAssetRole 全部有非空 id 与 label', () {
      for (final r in ShotAssetRole.values) {
        expect(r.id, isNotEmpty);
        expect(r.label, isNotEmpty);
      }
      // id 互不相同，否则序列化后无法区分。
      final ids = ShotAssetRole.values.map((r) => r.id).toSet();
      expect(ids.length, ShotAssetRole.values.length);
    });
  });

  group('StudioShot.assetBindings', () {
    test('默认为空绑定', () {
      const shot = StudioShot(number: 1);
      expect(shot.assetBindings, isEmpty);
    });

    test('copyWith 可替换 assetBindings', () {
      const shot = StudioShot(number: 1);
      final updated = shot.copyWith(assetBindings: {
        'c1': const ShotAssetBinding(role: ShotAssetRole.confrontation),
      });
      expect(updated.assetBindings.length, 1);
      expect(updated.assetBindings['c1']!.role, ShotAssetRole.confrontation);
    });

    test('序列化往返后 assetBindings 不丢', () {
      final shot = StudioShot(
        number: 1,
        assetBindings: const {
          'c1': ShotAssetBinding(materialPath: 'turnaround.png'),
          's1': ShotAssetBinding(materialPath: 'view_front.png'),
        },
      );
      final restored = StudioShot.fromJson(shot.toJson());
      expect(restored.assetBindings.length, 2);
      expect(restored.assetBindings['c1']!.materialPath, 'turnaround.png');
      expect(restored.assetBindings['s1']!.materialPath, 'view_front.png');
    });

    test('空绑定不写盘（JSON 里无 asset_bindings 键）', () {
      const shot = StudioShot(number: 1);
      expect(shot.toJson().containsKey('asset_bindings'), isFalse);
    });

    test('旧 JSON 缺 asset_bindings 时解析为空绑定而非抛异常', () {
      final restored = StudioShot.fromJson(const {
        'number': 1,
        'character_ids': ['c1'],
        'scene_id': 's1',
      });
      expect(restored.assetBindings, isEmpty);
      // 其余字段不受影响。
      expect(restored.characterIds, ['c1']);
      expect(restored.sceneId, 's1');
    });

    test('asset_bindings 值不是 Map 时按空绑定兜底', () {
      final restored = StudioShot.fromJson(const {
        'number': 1,
        'asset_bindings': {'c1': 'not-a-map'},
      });
      expect(restored.assetBindings.length, 1);
      expect(restored.assetBindings['c1']!.materialPath, '');
      expect(restored.assetBindings['c1']!.role, ShotAssetRole.subject);
    });
  });

  group('AssetMaterialEnumerator 候选枚举', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('asset_material_test');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// 在临时目录造一个文件。
    File makeFile(String name) {
      final f = File('${dir.path}/$name');
      f.writeAsStringSync('x');
      return f;
    }

    CharacterCard charWith({List<String> refs = const []}) => CharacterCard(
          id: 'c1',
          name: '姜七夜',
          descriptionZh: '二十岁青年',
          referenceImages: refs,
          updatedAt: DateTime(2026),
        );

    test('只列磁盘上存在的图', () {
      makeFile('turnaround.png');
      final c = charWith(refs: ['ghost.png']); // 声明了但文件不存在
      final candidates = AssetMaterialEnumerator.forCharacter(
        c,
        charDirPath: dir.path,
      );
      expect(candidates.map((e) => e.fileName), ['turnaround.png']);
      expect(candidates.any((e) => e.fileName == 'ghost.png'), isFalse);
    });

    test('首个存在的候选即系统默认', () {
      makeFile('turnaround.png');
      makeFile('face_anchor.png');
      final candidates = AssetMaterialEnumerator.forCharacter(
        charWith(),
        charDirPath: dir.path,
      );
      expect(candidates.first.fileName, 'turnaround.png');
      expect(candidates.first.isDefault, isTrue);
      // 只有一个是默认。
      expect(candidates.where((e) => e.isDefault).length, 1);
    });

    test('候选顺序即取材优先级：三视图先于面部锚点先于上传图', () {
      makeFile('turnaround.png');
      makeFile('face_anchor.png');
      makeFile('ref_a.png');
      final candidates = AssetMaterialEnumerator.forCharacter(
        charWith(refs: ['ref_a.png']).copyWith(faceAnchorPath: 'face_anchor.png'),
        charDirPath: dir.path,
      );
      expect(candidates.map((e) => e.fileName), [
        'turnaround.png',
        'face_anchor.png',
        'ref_a.png',
      ]);
      // 面部锚点的标签要与上传参考图区分，用户才知道选的是什么。
      expect(candidates[1].label, '面部锚点');
      expect(candidates[2].label, '上传参考图');
    });

    test('形态专属三视图优先于角色基准三视图', () {
      makeFile('turnaround.png');
      makeFile('turnaround_v1.png');
      final v = CharacterVariation(
        id: 'v1',
        name: '劲装',
        turnaroundPath: 'turnaround_v1.png',
      );
      final candidates = AssetMaterialEnumerator.forCharacter(
        charWith(),
        activeVariation: v,
        charDirPath: dir.path,
      );
      expect(candidates.first.fileName, 'turnaround_v1.png');
      expect(candidates.first.isDefault, isTrue);
      expect(candidates.first.label, '形态三视图');
    });

    test('同一文件不重复列出', () {
      makeFile('turnaround.png');
      // turnaround.png 同时是「基准三视图」和上传参考图里的一项。
      final candidates = AssetMaterialEnumerator.forCharacter(
        charWith(refs: ['turnaround.png']),
        charDirPath: dir.path,
      );
      expect(candidates.where((e) => e.fileName == 'turnaround.png').length, 1);
    });

    test('无任何可用素材时返回空列表', () {
      final candidates = AssetMaterialEnumerator.forCharacter(
        charWith(),
        charDirPath: dir.path,
      );
      expect(candidates, isEmpty);
    });

    test('场景候选按七方位视角优先于上传参考图', () {
      makeFile('view_front.png');
      makeFile('view_back.png');
      final scene = SceneCard(
        id: 's1',
        name: '衙门',
        promptEn: 'yamen',
        referenceImages: ['upload.png'],
        spatialViews: {
          'front': SceneDirectionalView(
            direction: SceneDirection.front,
            imagePath: 'view_front.png',
          ),
          'back': SceneDirectionalView(
            direction: SceneDirection.back,
            imagePath: 'view_back.png',
          ),
        },
        updatedAt: DateTime(2026),
      );
      makeFile('upload.png');
      final candidates = AssetMaterialEnumerator.forScene(
        scene,
        sceneDirPath: dir.path,
      );
      expect(candidates.first.fileName, 'view_front.png');
      expect(candidates.first.isDefault, isTrue);
      expect(candidates.map((e) => e.fileName), contains('upload.png'));
    });

    test('defaultMaterialFor 与候选列表首项一致', () {
      makeFile('turnaround.png');
      final viaHelper = AssetMaterialEnumerator.defaultMaterialFor(
        isScene: false,
        character: charWith(),
        assetDirPath: dir.path,
      );
      final viaList = AssetMaterialEnumerator.forCharacter(
        charWith(),
        charDirPath: dir.path,
      );
      expect(viaHelper, viaList.first.fileName);
    });

    test('defaultMaterialFor 无素材时返回 null', () {
      expect(
        AssetMaterialEnumerator.defaultMaterialFor(
          isScene: false,
          character: charWith(),
          assetDirPath: dir.path,
        ),
        isNull,
      );
    });
  });
}
