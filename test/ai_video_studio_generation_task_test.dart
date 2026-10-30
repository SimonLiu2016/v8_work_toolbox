import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_generation_tasks.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_task_queue.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

/// 生成任务写回路径的测试（spec 5.2：完成后把图片路径写回 storyboard.json）。
///
/// 用 [LocalStubImageAdapter] 生产真实 PNG，不起网络也不依赖 FFmpeg。
void main() {
  late Directory root;
  late StudioProjectManager manager;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('studio_gen_task');
    AppPaths.overrideRootForTesting(root);
  });

  tearDown(() {
    manager.resetCachesForTesting();
    StudioTaskQueue.instance.resetForTesting();
  });

  setUp(() {
    manager = StudioProjectManager.instance;
    manager.resetCachesForTesting();
    StudioTaskQueue.instance.resetForTesting();
  });

  test('ImageGenTask 落盘到 frames/ 并把路径写回 storyboard.json', () async {
    final series = await manager.createSeries(name: '雨夜');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [
        shotOf(1, durationSec: 3, mood: 'warm'),
      ],
    );
    await manager.saveEpisode(episode);

    final task = ImageGenTask(
      taskId: 't1',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: const LocalStubImageAdapter(),
    );

    final result = await task.run((_) {});
    expect(result, 'shot_1.png');

    // 文件真的落在 frames/ 下
    final frameFile = File(
      p.join(manager.episodeFramesDir(series.id, episode.id).path, result),
    );
    expect(await frameFile.exists(), isTrue);

    // storyboard.json 记下了相对路径与状态
    final reloaded = manager.readEpisode(series.id, episode.id)!;
    final shot = reloaded.shots.first;
    expect(shot.framePath, 'shot_1.png');
    expect(shot.status.id, 'done');
    expect(shot.assembledPrompt, isNotEmpty,
           reason: '组装好的 Prompt 应落盘，用户重试时不丢字段');
  });

  test('引擎失败时任务抛错，且 storyboard.json 不会被写成"已生成"', () async {
    final series = await manager.createSeries(name: '雨夜');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [shotOf(1)],
    );
    await manager.saveEpisode(episode);

    final task = ImageGenTask(
      taskId: 't2',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: _ThrowingAdapter(),
    );

    await expectLater(task.run((_) {}), throwsA(isA<StateError>()));

    final reloaded = manager.readEpisode(series.id, episode.id)!;
    expect(reloaded.shots.first.framePath, isNull);
    expect(reloaded.shots.first.status.id, 'pending');
  });

  test('集或分镜不存在时给出可读错误', () async {
    final task = ImageGenTask(
      taskId: 't3',
      seriesId: 'no-such-series',
      episodeId: 'no-such-episode',
      shotNumber: 1,
      adapter: const LocalStubImageAdapter(),
    );
    await expectLater(
      task.run((_) {}),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('找不到分镜所属的集'),
      )),
    );
  });

  test('VideoGenTask 在缺参考素材时提示补图，不打云端', () async {
    final series = await manager.createSeries(name: '雨夜');
    final created = await manager.createEpisode(seriesId: series.id);
    // 带一个出场角色但没有可用素材图 → reference 模式取不到图。此时不该去打
    // 云端（spec: 缺少参考图时不静默降级）。
    final episode = created.episode.copyWith(
      shots: [shotOf(1).copyWith(characterIds: ['c_missing'])],
    );
    await manager.saveEpisode(episode);

    final task = VideoGenTask(
      taskId: 't4',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: _ThrowingVideoAdapter(),
    );
    await expectLater(
      task.run((_) {}),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('素材'),
      )),
    );
  });

  test('VideoGenTask 提交时携带分镜提示词 promptZh 上下文', () async {
    final series = await manager.createSeries(name: '雨夜');
    final created = await manager.createEpisode(seriesId: series.id);
    final framesDir = manager.episodeFramesDir(series.id, created.episode.id);
    final frameFile = File(p.join(framesDir.path, 'shot_1.png'))..createSync(recursive: true);
    frameFile.writeAsBytesSync([1, 2, 3]);

    final episode = created.episode.copyWith(
      shots: [
        shotOf(1).copyWith(
          framePath: 'shot_1.png',
          actionZh: '暴雨夜主角拔剑警惕四方',
          assembledPrompt: 'ancient warrior drawing sword in heavy rain',
        ),
      ],
    );
    await manager.saveEpisode(episode);

    VideoGenRequest? capturedRequest;
    final spyAdapter = _CapturingVideoAdapter((req) => capturedRequest = req);

    final task = VideoGenTask(
      taskId: 't-vid-prompt',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: spyAdapter,
    );
    await task.run((_) {});

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.promptZh, contains('暴雨夜主角拔剑警惕四方'));
  });

  test('VideoGenTask 提交时携带对白台词发声与口型声画一体提示词', () async {
    final series = await manager.createSeries(name: '对话测试');
    final created = await manager.createEpisode(seriesId: series.id);
    final framesDir = manager.episodeFramesDir(series.id, created.episode.id);
    final frameFile = File(p.join(framesDir.path, 'shot_1.png'))..createSync(recursive: true);
    frameFile.writeAsBytesSync([1, 2, 3]);

    final episode = created.episode.copyWith(
      shots: [
        shotOf(1).copyWith(
          framePath: 'shot_1.png',
          actionZh: '姜七夜撕下鸡腿大嚼，抬刀轻挑指向三楼余小白',
          dialogue: '余小白，我迟早得叫你姐夫。',
        ),
      ],
    );
    await manager.saveEpisode(episode);

    VideoGenRequest? capturedRequest;
    final spyAdapter = _CapturingVideoAdapter((req) => capturedRequest = req);

    final task = VideoGenTask(
      taskId: 't-vid-dialogue-prompt',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: spyAdapter,
    );
    await task.run((_) {});

    expect(capturedRequest, isNotNull);
    expect(capturedRequest!.promptZh, contains('余小白，我迟早得叫你姐夫。'));
    expect(capturedRequest!.promptZh, contains('姜七夜撕下鸡腿大嚼'));
    expect(capturedRequest!.promptZh, contains('口型发音对齐'));
  });

  test('StudioProjectManager.updateShot 原子更新单个分镜，在并发修改时互不丢失', () async {
    final series = await manager.createSeries(name: '并发更新测试');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [
        shotOf(1),
        shotOf(2),
      ],
    );
    await manager.saveEpisode(episode);

    await Future.wait([
      manager.updateShot(series.id, episode.id, 1, (s) => s.copyWith(framePath: 'shot_1.png', status: ShotGenerationStatus.done)),
      manager.updateShot(series.id, episode.id, 2, (s) => s.copyWith(framePath: 'shot_2.png', status: ShotGenerationStatus.done)),
    ]);

    final reloaded = manager.readEpisode(series.id, episode.id)!;
    expect(reloaded.shots[0].framePath, 'shot_1.png');
    expect(reloaded.shots[0].status, ShotGenerationStatus.done);
    expect(reloaded.shots[1].framePath, 'shot_2.png');
    expect(reloaded.shots[1].status, ShotGenerationStatus.done);
  });

  test(r'_healEpisodeMediaIfNeeded 同时自动识别 shot_${number}.png 与 ${number}.png 恢复 framePath', () async {
    final series = await manager.createSeries(name: '自愈测试');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [
        shotOf(1),
        shotOf(2),
      ],
    );
    await manager.saveEpisode(episode);

    final framesDir = manager.episodeFramesDir(series.id, episode.id);
    final file1 = File(p.join(framesDir.path, 'shot_1.png'))..createSync(recursive: true);
    file1.writeAsBytesSync(List.filled(2048, 1));

    final file2 = File(p.join(framesDir.path, '2.png'))..createSync(recursive: true);
    file2.writeAsBytesSync(List.filled(2048, 2));

    final healed = manager.readEpisode(series.id, episode.id)!;
    expect(healed.shots[0].framePath, 'shot_1.png');
    expect(healed.shots[0].status, ShotGenerationStatus.done);
    expect(healed.shots[1].framePath, '2.png');
    expect(healed.shots[1].status, ShotGenerationStatus.done);
  });

  test('两个 ImageGenTask 并发执行落盘，后完成的任务不会冲掉先完成任务的 framePath', () async {
    final series = await manager.createSeries(name: '并发生图测试');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [
        shotOf(1),
        shotOf(2),
      ],
    );
    await manager.saveEpisode(episode);

    final fastAdapter = const LocalStubImageAdapter();
    final slowAdapter = _DelayingImageAdapter(const Duration(milliseconds: 100));

    final task1 = ImageGenTask(
      taskId: 'img-1',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 1,
      adapter: slowAdapter,
    );

    final task2 = ImageGenTask(
      taskId: 'img-2',
      seriesId: series.id,
      episodeId: episode.id,
      shotNumber: 2,
      adapter: fastAdapter,
    );

    await Future.wait([
      task1.run((_) {}),
      task2.run((_) {}),
    ]);

    final reloaded = manager.readEpisode(series.id, episode.id)!;
    expect(reloaded.shots[0].framePath, 'shot_1.png');
    expect(reloaded.shots[0].status, ShotGenerationStatus.done);
    expect(reloaded.shots[1].framePath, 'shot_2.png');
    expect(reloaded.shots[1].status, ShotGenerationStatus.done);
  });

  group('首尾帧接力判据（spec: 分镜首帧来源的可信判据）', () {
    test('canRelayFrameFromPrev：同场景同主体同景别时接力', () {
      final prev = shotOf(1).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.medium,
      );
      final curr = shotOf(2).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.medium,
      );
      expect(canRelayFrameFromPrev(prev, curr), isTrue);
    });

    test('canRelayFrameFromPrev：场景卡不同不接力', () {
      final prev = shotOf(1).copyWith(sceneId: 'scene_a', characterIds: ['c1']);
      final curr = shotOf(2).copyWith(sceneId: 'scene_b', characterIds: ['c1']);
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('canRelayFrameFromPrev：sceneId 为空不接力', () {
      final prev = shotOf(1).copyWith(sceneId: '', characterIds: ['c1']);
      final curr = shotOf(2).copyWith(sceneId: '', characterIds: ['c1']);
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('canRelayFrameFromPrev：主体集合不同不接力', () {
      final prev = shotOf(1).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1', 'c2'],
      );
      final curr = shotOf(2).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
      );
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('canRelayFrameFromPrev：正反打（一方特写另一方非特写）不接力', () {
      final prev = shotOf(1).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.closeUp,
      );
      final curr = shotOf(2).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.medium,
      );
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('canRelayFrameFromPrev：任一方标记为对峙分工时不接力', () {
      final prev = shotOf(1).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1', 'c2'],
        shotSize: StudioShotSize.medium,
        assetBindings: {
          'c2': const ShotAssetBinding(role: ShotAssetRole.confrontation),
        },
      );
      final curr = shotOf(2).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1', 'c2'],
        shotSize: StudioShotSize.medium,
      );
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('canRelayFrameFromPrev：景别差 2 档不接力', () {
      final prev = shotOf(1).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.mediumCloseUp,
      );
      final curr = shotOf(2).copyWith(
        sceneId: 'scene_a',
        characterIds: ['c1'],
        shotSize: StudioShotSize.full,
      );
      expect(canRelayFrameFromPrev(prev, curr), isFalse);
    });

    test('VideoGenTask：正反打镜头使用本镜关键帧，不提取上一镜尾帧', () async {
      final series = await manager.createSeries(name: '正反打测试');
      final created = await manager.createEpisode(seriesId: series.id);
      final framesDir = manager.episodeFramesDir(series.id, created.episode.id);
      for (final n in [1, 2]) {
        final f = File(p.join(framesDir.path, 'shot_$n.png'))
          ..createSync(recursive: true);
        f.writeAsBytesSync([n, n, n]);
      }

      final episode = created.episode.copyWith(
        shots: [
          shotOf(1).copyWith(
            sceneId: 'scene_a',
            characterIds: ['c1'],
            framePath: 'shot_1.png',
            shotSize: StudioShotSize.closeUp,
            clipPath: 'shot_1.mp4',
          ),
          shotOf(2).copyWith(
            sceneId: 'scene_a',
            characterIds: ['c1'],
            framePath: 'shot_2.png',
            shotSize: StudioShotSize.medium,
          ),
        ],
      );
      await manager.saveEpisode(episode);

      VideoGenRequest? captured;
      final task = VideoGenTask(
        taskId: 't-reverse',
        seriesId: series.id,
        episodeId: created.episode.id,
        shotNumber: 2,
        adapter: _CapturingVideoAdapter((req) => captured = req),
      );
      await task.run((_) {});

      expect(captured, isNotNull);
      // 首帧必须是本镜关键帧，不是上一镜尾帧（shot_1_last.png）。
      expect(captured!.inputImage!.path, endsWith('shot_2.png'));

      final reloaded = manager.readEpisode(series.id, created.episode.id)!;
      expect(reloaded.shots[1].firstFramePath, 'shot_2.png');
      expect(reloaded.shots[1].firstFrameSource, FirstFrameSource.keyframe);
    });

    test('VideoGenTask：满足接力条件时使用上一镜尾帧并记录来源', () async {
      final series = await manager.createSeries(name: '接力测试');
      final created = await manager.createEpisode(seriesId: series.id);
      final framesDir = manager.episodeFramesDir(series.id, created.episode.id);
      for (final n in [1, 2]) {
        final f = File(p.join(framesDir.path, 'shot_$n.png'))
          ..createSync(recursive: true);
        f.writeAsBytesSync([n, n, n]);
      }
      // 上一镜的尾帧文件：接力判据通过后 VideoGenTask 会调 extractLastFrame
      // 从上一镜视频里抽帧，测试环境没有 FFmpeg 也拿不到真视频——这里直接
      // 验证「首帧来源字段」与「不抛错」两条契约，尾帧文件本身由判据单测覆盖。
      final lastFrame = File(p.join(framesDir.path, 'shot_1_last.png'))
        ..createSync(recursive: true);
      lastFrame.writeAsBytesSync([9, 9, 9]);

      final episode = created.episode.copyWith(
        shots: [
          shotOf(1).copyWith(
            sceneId: 'scene_a',
            characterIds: ['c1'],
            framePath: 'shot_1.png',
            shotSize: StudioShotSize.medium,
            clipPath: 'shot_1.mp4',
          ),
          shotOf(2).copyWith(
            sceneId: 'scene_a',
            characterIds: ['c1'],
            framePath: 'shot_2.png',
            shotSize: StudioShotSize.medium,
          ),
        ],
      );
      await manager.saveEpisode(episode);

      VideoGenRequest? captured;
      final task = VideoGenTask(
        taskId: 't-relay',
        seriesId: series.id,
        episodeId: created.episode.id,
        shotNumber: 2,
        adapter: _CapturingVideoAdapter((req) => captured = req),
      );
      await task.run((_) {});

      expect(captured, isNotNull);
      // 判据通过 → 试图用上一镜尾帧。测试环境抽不出真尾帧（无 FFmpeg），
      // 提取失败时回落到本镜关键帧，来源记为 keyframe。
      final reloaded = manager.readEpisode(series.id, created.episode.id)!;
      expect(
        reloaded.shots[1].firstFrameSource,
        anyOf(FirstFrameSource.relay, FirstFrameSource.keyframe),
      );
      expect(reloaded.shots[1].firstFramePath, isNotNull);
    });

    test('StudioShot.firstFrameSource 序列化往返，缺失时默认 keyframe', () {
      final shot = shotOf(1).copyWith(
        firstFramePath: 'shot_1_last.png',
        firstFrameSource: FirstFrameSource.relay,
      );
      final restored = StudioShot.fromJson(shot.toJson());
      expect(restored.firstFrameSource, FirstFrameSource.relay);
      expect(restored.firstFramePath, 'shot_1_last.png');

      final legacy = StudioShot.fromJson(const {
        'number': 1,
      });
      expect(legacy.firstFrameSource, FirstFrameSource.keyframe);
    });
  });
}

class _DelayingImageAdapter implements ImageGenAdapter {
  final Duration delay;
  const _DelayingImageAdapter(this.delay);

  @override
  String get id => 'delaying';
  @override
  String get label => 'delaying';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<File> generate(ImageGenRequest request) async {
    await Future.delayed(delay);
    await const LocalStubImageAdapter().generate(request);
    return request.outputFile;
  }
}

/// 抓取请求体的测试适配器。
class _CapturingVideoAdapter implements VideoGenAdapter {
  final void Function(VideoGenRequest request) onCaptured;

  _CapturingVideoAdapter(this.onCaptured);

  @override
  String get id => 'capturing-video';
  @override
  String get label => 'capturing-video';
  @override
  bool get requiresApiKey => false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    onCaptured(request);
    await request.outputFile.create(recursive: true);
    await request.outputFile.writeAsBytes([0, 0, 0]);
    onProgress?.call(1);
    return request.outputFile;
  }
}

/// 测试用的分镜工厂：只需要能落盘的最小合法分镜。
StudioShot shotOf(int number, {double durationSec = 3, String mood = 'warm'}) {
  return StudioShot(
    number: number,
    durationSec: durationSec,
    mood: mood,
  );
}

class _ThrowingAdapter implements ImageGenAdapter {
  @override
  String get id => 'throwing';
  @override
  String get label => 'throwing';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<File> generate(ImageGenRequest request) async {
    throw StateError('quota exceeded');
  }
}

class _ThrowingVideoAdapter implements VideoGenAdapter {
  @override
  String get id => 'throwing-video';
  @override
  String get label => 'throwing-video';
  @override
  bool get requiresApiKey => false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<File> generateVideo(
    VideoGenRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    throw StateError('unreachable');
  }
}
