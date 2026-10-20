import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

void main() {
  group('StudioProductionType 3D国漫与类型约束', () {
    test('包含 3D国漫/次世代虚拟剧 类型并拥有预置风格约束', () {
      expect(StudioProductionType.anime3d.label, '3D国漫 / 次世代虚拟剧');
      expect(StudioProductionType.anime3d.defaultPositiveStyle, contains('3D CGI animation'));
      expect(StudioProductionType.anime3d.defaultPositiveStyle, contains('Unreal Engine 5 render'));
      expect(StudioProductionType.anime3d.defaultNegativeStyle, contains('flat anime'));
      expect(StudioProductionType.anime3d.defaultNegativeStyle, contains('live-action photo'));
      expect(StudioProductionType.anime3d.motionTendency, contains('dynamic airborne camera'));
    });

    test('全部 4 种制作类型均具备正面风格、负面风格与运动趋势定义', () {
      for (final type in StudioProductionType.values) {
        expect(type.defaultPositiveStyle, isNotEmpty);
        expect(type.defaultNegativeStyle, isNotEmpty);
        expect(type.motionTendency, isNotEmpty);
      }
    });

    test('PromptAssembler 将制作类型的正面/负面风格组装进分镜画面提示词', () {
      final parts = PromptAssembler.buildShotPrompt(
        PromptParts(
          productionType: StudioProductionType.anime3d,
          mood: 'epic battle',
        ),
      );

      expect(parts.positive, contains('3D CGI animation'));
      expect(parts.positive, contains('epic battle'));
      expect(parts.negative, contains('flat anime'));
      expect(parts.negative, contains('live-action photo'));
    });

    test('PromptAssembler 将动态趋势组装进片段视频提示词', () {
      final parts = PromptAssembler.buildSegmentPrompt(
        SegmentPromptParts(
          productionType: StudioProductionType.anime3d,
          shots: const [],
        ),
      );

      expect(parts.positive, contains('3D CGI animation'));
      expect(parts.positive, contains('dynamic airborne camera'));
    });
  });

  group('StudioProjectManager 场景参考图管理', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('scene_ref_test');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
      await manager.ensureBaseStructure();
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('addSceneReference 复制图片到 scenes 相对目录并返回相对路径', () async {
      final series = await manager.createSeries(
        name: '场景参考图测试',
        productionType: StudioProductionType.anime3d,
      );

      // 验证新建时自动注入了 3D国漫 的默认风格标签
      expect(series.styleTokens, contains('3D CGI animation'));

      final scene = await manager.createScene(
        seriesId: series.id,
        name: '凌霄宝殿',
        descriptionZh: '云雾缭绕的金顶大殿',
      );

      final dummyFile = File(p.join(tempDir.path, 'source_scene.png'));
      await dummyFile.writeAsBytes(utf8.encode('fake-scene-bytes'));

      final relPath = await manager.addSceneReference(
        seriesId: series.id,
        sceneId: scene.id,
        sourceFilePath: dummyFile.path,
      );

      expect(relPath, startsWith('references/'));
      final fullPath = p.join(manager.sceneDir(series.id, scene.id).path, relPath);
      expect(File(fullPath).existsSync(), isTrue);

      // 删除场景会联动清理其参考图目录
      await manager.deleteScene(series.id, scene.id);
      expect(File(fullPath).existsSync(), isFalse);
    });
  });
}
