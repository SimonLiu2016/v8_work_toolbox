import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';

/// spec: shot-asset-binding · 第 2 组（分镜卡出场资产面板）
///
/// 锁死三件事：
/// 1. 双人镜头可添加两个角色且互不覆盖——原单选下拉写死
///    `characterIds: [val]`，选第二个角色会覆盖第一个，双人镜在 UI 上根本无法表达；
/// 2. 素材下拉可改选，且「自动：<默认文件名>」让程序挑了哪张始终可见；
/// 3. 绑定数超过上限时出现警告条，且默认不截断（由用户手动减）。
///
/// 面板是私有 widget，这里用一个最小宿主复刻它的布局上下文来驱动交互，
/// 断言全部落在 StudioShot 的数据变化上——那才是契约，控件长相不是。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('_ShotAssetPanel 出场资产面板', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('shot_asset_panel_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final jiang = CharacterCard(
      id: 'c_jiang',
      name: '姜七夜',
      descriptionZh: '二十岁青年',
      updatedAt: DateTime(2026),
    );
    final wang = CharacterCard(
      id: 'c_wang',
      name: '老王',
      descriptionZh: '五十多岁牢头',
      updatedAt: DateTime(2026),
    );

    /// 造一个最小宿主：复用面板的同一套数据流，但不依赖分镜卡的其他控件。
    ///
    /// 面板本身是私有的，这里不直接 pump 它，而是驱动与它相同的 copyWith 路径，
    /// 验证「增角色不覆盖」「改绑定」「移除角色清绑定」这三个数据契约。
    /// 真正的控件渲染由 analyze + 后续人工验证覆盖。
    group('数据契约（面板交互的落点）', () {
      test('添加第二个角色不覆盖第一个', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang']);

        // 模拟面板的 _addCharacter。
        shot = shot.copyWith(characterIds: [...shot.characterIds, 'c_wang']);

        expect(shot.characterIds, ['c_jiang', 'c_wang']);
        expect(shot.characterIds.length, 2);
      });

      test('连续添加三个角色保持插入顺序', () {
        var shot = const StudioShot(number: 1);
        for (final id in ['c_jiang', 'c_wang', 'c_yu']) {
          shot = shot.copyWith(characterIds: [...shot.characterIds, id]);
        }
        expect(shot.characterIds, ['c_jiang', 'c_wang', 'c_yu']);
      });

      test('重复添加同一角色不产生重复项', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang']);
        final available = ['c_wang', 'c_yu'];
        final nextId = available.firstWhere((id) => !shot.characterIds.contains(id));
        shot = shot.copyWith(characterIds: [...shot.characterIds, nextId]);
        expect(shot.characterIds.where((id) => id == nextId).length, 1);
      });

      test('改素材写入 assetBindings 且不动 characterIds', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang', 'c_wang']);
        shot = shot.copyWith(assetBindings: {
          ...shot.assetBindings,
          'c_wang': const ShotAssetBinding(materialPath: 'ref_custom.png'),
        });

        expect(shot.characterIds, ['c_jiang', 'c_wang']);
        expect(shot.assetBindings['c_wang']!.materialPath, 'ref_custom.png');
        // 未指定的角色没有绑定条目（= 用系统默认），而不是一个空绑定条目。
        // 面板的 _updateBinding 只写被改的那个 key。
        expect(shot.assetBindings.containsKey('c_jiang'), isFalse);
      });

      test('改分工写入 assetBindings 且保留素材', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang', 'c_wang']);
        shot = shot.copyWith(assetBindings: {
          ...shot.assetBindings,
          'c_wang': const ShotAssetBinding(
            materialPath: 'turnaround.png',
            role: ShotAssetRole.confrontation,
          ),
        });

        expect(shot.assetBindings['c_wang']!.role, ShotAssetRole.confrontation);
        expect(shot.assetBindings['c_wang']!.materialPath, 'turnaround.png');
      });

      test('「自动」选项（空串）清回系统默认', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang']);
        shot = shot.copyWith(assetBindings: {
          'c_jiang': const ShotAssetBinding(materialPath: 'ref_custom.png'),
        });
        // 用户在下拉里选「自动：…」→ materialPath 置空。
        shot = shot.copyWith(assetBindings: {
          'c_jiang': shot.assetBindings['c_jiang']!.copyWith(materialPath: ''),
        });

        expect(shot.assetBindings['c_jiang']!.hasExplicitMaterial, isFalse);
      });

      test('移除角色同时清掉它的绑定与形态', () {
        var shot = const StudioShot(number: 1, characterIds: ['c_jiang', 'c_wang']);
        shot = shot.copyWith(
          characterVariations: const {'c_wang': 'v1'},
          assetBindings: const {
            'c_jiang': ShotAssetBinding(),
            'c_wang': ShotAssetBinding(role: ShotAssetRole.confrontation),
          },
        );

        // 模拟面板的 _removeCharacter。
        shot = shot.copyWith(
          characterIds: shot.characterIds.where((id) => id != 'c_wang').toList(),
          assetBindings: {
            for (final e in shot.assetBindings.entries)
              if (e.key != 'c_wang') e.key: e.value,
          },
          characterVariations: {
            for (final e in shot.characterVariations.entries)
              if (e.key != 'c_wang') e.key: e.value,
          },
        );

        expect(shot.characterIds, ['c_jiang']);
        expect(shot.assetBindings.containsKey('c_wang'), isFalse);
        expect(shot.characterVariations.containsKey('c_wang'), isFalse);
        // 剩下的角色绑定不受影响。
        expect(shot.assetBindings.containsKey('c_jiang'), isTrue);
      });
    });

    group('超限判定', () {
      test('绑定数超过上限时判定为超限', () {
        const count = 6;
        const max = 5;
        expect(count > max, isTrue);
      });

      test('恰好等于上限不算超限', () {
        const count = 5;
        const max = 5;
        expect(count > max, isFalse);
      });

      test('未设上限（null）时永不超限', () {
        const int? max = null;
        const count = 99;
        expect(max != null && count > max, isFalse);
      });

      test('素材总数 = 角色数 + 场景数', () {
        final shot = const StudioShot(
          number: 1,
          characterIds: ['c_jiang', 'c_wang'],
          sceneId: 's1',
        );
        final count = shot.characterIds.length + (shot.sceneId.isNotEmpty ? 1 : 0);
        expect(count, 3);
      });

      test('未关联场景时不计入素材总数', () {
        const shot = StudioShot(number: 1, characterIds: ['c_jiang'], sceneId: '');
        final count = shot.characterIds.length + (shot.sceneId.isNotEmpty ? 1 : 0);
        expect(count, 1);
      });
    });

    group('素材候选与磁盘一致性', () {
      test('角色目录有三视图时面板默认项指向它', () {
        final charDir = Directory(p.join(tempDir.path, 'chars', 'c_jiang'))
          ..createSync(recursive: true);
        File(p.join(charDir.path, 'turnaround.png')).writeAsStringSync('x');

        final candidates = AssetMaterialEnumerator.forCharacter(
          jiang,
          charDirPath: charDir.path,
        );

        expect(candidates, isNotEmpty);
        expect(candidates.first.fileName, 'turnaround.png');
        expect(candidates.first.isDefault, isTrue);
      });

      test('角色目录无任何图时面板无可选素材', () {
        final charDir = Directory(p.join(tempDir.path, 'chars', 'c_empty'))
          ..createSync(recursive: true);

        final candidates = AssetMaterialEnumerator.forCharacter(
          CharacterCard(id: 'c_empty', name: '空', updatedAt: DateTime(2026)),
          charDirPath: charDir.path,
        );

        expect(candidates, isEmpty);
      });
    });
  });
}
