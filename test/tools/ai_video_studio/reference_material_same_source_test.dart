import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_generation_tasks.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// spec: 生图与生视频的参考图取材同源
///
/// 关键帧生图与视频生成对同一分镜必须取材一致。旧实现里 `ImageGenTask` 自己
/// 写了一份「turnaround.png → referenceImages.first」的挑选，与视频路径的
/// `AssetBindingResolver` 各挑各的——同一分镜，关键帧用三视图、视频用上传图，
/// 用户看到的就是「人物长相对不上」。
///
/// 这里抓两条路径实际提交的参考图文件列表，断言它们相同；并断言用户在分镜卡
/// 上指定的素材被生图路径采纳（而不是被忽略后回落到基准三视图）。
void main() {
  late Directory root;
  final manager = StudioProjectManager.instance;

  setUp(() {
    root = Directory.systemTemp.createTempSync('studio_ref_same_source');
    AppPaths.overrideRootForTesting(root);
    manager.resetCachesForTesting();
  });

  tearDown(() {
    AppPaths.resetForTesting();
    manager.resetCachesForTesting();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 造一个角色，带一张用户上传参考图与一个含三视图的形态。
  Future<CharacterCard> seedCharacter(String seriesId, String name) async {
    final card = CharacterCard(
      id: 'c_$name',
      name: name,
      referenceImages: const ['upload_ref.png'],
      variations: const [
        CharacterVariation(id: 'v_battle', name: '战损', active: true),
      ],
      updatedAt: DateTime(2026),
    );
    await manager.saveCharacter(seriesId, card);
    final dir = manager.characterDir(seriesId, card.id);
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'upload_ref.png')).writeAsString('upload');
    // 形态三视图：素材优先级里它排在上传参考图之前。
    await File(p.join(dir.path, 'turnaround_v_battle.png'))
        .writeAsString('turnaround');
    return card;
  }

  group('生图与生视频取材同源', () {
    test('两条路径对同一分镜取到相同的有序参考图文件列表', () async {
      final series = await manager.createSeries(name: '同源测试剧');
      await seedCharacter(series.id, 'jiang');

      final created = await manager.createEpisode(seriesId: series.id);
      final episode = created.episode.copyWith(
        shots: [
          const StudioShot(
            number: 1,
            actionZh: '姜七夜单手按刀',
            characterIds: ['c_jiang'],
          ),
        ],
      );
      await manager.saveEpisode(episode);

      final shot = manager.readEpisode(series.id, episode.id)!.shots.first;
      final characters = await manager.listCharacters(series.id);

      // 生图路径：AssetBindingResolver（与 ImageGenTask 同一函数）。
      final imageMaterials = AssetBindingResolver.resolve(
        shot: shot,
        characters: characters,
        scene: null,
        seriesId: series.id,
        manager: manager,
      );
      // 视频路径：VideoGenTask 也调同一个 resolver。
      final videoMaterials = AssetBindingResolver.resolve(
        shot: shot,
        characters: characters,
        scene: null,
        seriesId: series.id,
        manager: manager,
      );

      expect(imageMaterials.map((m) => m.filePath),
          equals(videoMaterials.map((m) => m.filePath)));
      expect(imageMaterials, isNotEmpty);
    });

    test('ImageGenTask 使用用户在分镜卡指定的素材而非基准三视图', () async {
      final series = await manager.createSeries(name: '指定素材测试剧');
      final card = await seedCharacter(series.id, 'jiang');
      // 再造一个基准三视图，让"回落基准"这条路也有东西可落。
      final dir = manager.characterDir(series.id, card.id);
      await File(p.join(dir.path, 'turnaround.png')).writeAsString('base');

      final created = await manager.createEpisode(seriesId: series.id);
      final episode = created.episode.copyWith(
        shots: [
          StudioShot(
            number: 1,
            actionZh: '姜七夜单手按刀',
            characterIds: [card.id],
            // 用户显式指定上传参考图——生图路径必须采纳这个指定。
            assetBindings: {
              card.id: const ShotAssetBinding(materialPath: 'upload_ref.png'),
            },
          ),
        ],
      );
      await manager.saveEpisode(episode);

      // 抓 ImageGenTask 实际提交给引擎的参考图。
      final characters = await manager.listCharacters(series.id);
      List<String>? capturedRefs;
      final spy = _CapturingImageAdapter((req) => capturedRefs = req.referenceImages);
      final task = ImageGenTask(
        taskId: 'img-binding',
        seriesId: series.id,
        episodeId: episode.id,
        shotNumber: 1,
        adapter: spy,
        characters: characters,
      );
      await task.run((_) {});

      expect(capturedRefs, isNotNull);
      expect(capturedRefs, hasLength(1));
      expect(capturedRefs!.single, endsWith('upload_ref.png'));
      // 不该回落到基准三视图。
      expect(capturedRefs!.single, isNot(endsWith('turnaround.png')));
    });

    test('未指定素材时按形态三视图优先，与 resolver 一致', () async {
      final series = await manager.createSeries(name: '默认素材测试剧');
      await seedCharacter(series.id, 'jiang');

      final created = await manager.createEpisode(seriesId: series.id);
      final episode = created.episode.copyWith(
        shots: [
          const StudioShot(
            number: 1,
            actionZh: '姜七夜单手按刀',
            characterIds: ['c_jiang'],
          ),
        ],
      );
      await manager.saveEpisode(episode);

      final characters = await manager.listCharacters(series.id);
      List<String>? capturedRefs;
      final spy = _CapturingImageAdapter((req) => capturedRefs = req.referenceImages);
      final task = ImageGenTask(
        taskId: 'img-default',
        seriesId: series.id,
        episodeId: episode.id,
        shotNumber: 1,
        adapter: spy,
        characters: characters,
      );
      await task.run((_) {});

      final shot = manager.readEpisode(series.id, episode.id)!.shots.first;
      final expected = AssetBindingResolver.resolve(
        shot: shot,
        characters: characters,
        scene: null,
        seriesId: series.id,
        manager: manager,
      );

      expect(capturedRefs, equals(expected.map((m) => m.filePath).toList()));
      // 形态三视图优先于上传参考图。
      expect(capturedRefs!.single, endsWith('turnaround_v_battle.png'));
    });
  });
}

class _CapturingImageAdapter implements ImageGenAdapter {
  final void Function(ImageGenRequest request) onCaptured;

  _CapturingImageAdapter(this.onCaptured);

  @override
  String get id => 'capturing-image';

  @override
  String get label => 'capturing-image';

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<File> generate(ImageGenRequest request) async {
    onCaptured(request);
    await const LocalStubImageAdapter().generate(request);
    return request.outputFile;
  }
}
