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

  test('VideoGenTask 在缺关键帧时提示先出关键帧', () async {
    final series = await manager.createSeries(name: '雨夜');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode.copyWith(
      shots: [shotOf(1)],
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
        contains('尚未生成关键帧'),
      )),
    );
  });
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
