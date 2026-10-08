// 生成任务：把 StudioTaskQueue 与数据层、引擎适配器接起来的执行体。
//
// 任务完成后的「写回」集中在这里，而不是散在 UI：storyboard.json 是唯一的
// 事实来源，UI 只读它。否则同一个分镜会出现「队列说成功、磁盘说没图」的
// 分裂状态，而那种 bug 只能靠重启复现。

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/studio_models.dart';
import 'image_gen_adapter.dart';
import 'prompt_assembler.dart';
import 'studio_project_manager.dart';
import 'studio_task_queue.dart';
import 'video_gen_adapter.dart';

/// 关键帧生成任务。
///
/// 流程：组装 Prompt → 调图像引擎 → 落盘到 `frames/` → 把相对路径写回
/// `storyboard.json`。任一步失败都向上抛，队列负责把分镜标记为失败。
class ImageGenTask implements StudioTaskRunner, CancellableTaskRunner {
  ImageGenTask({
    required this.taskId,
    required this.seriesId,
    required this.episodeId,
    required this.shotNumber,
    required this.adapter,
    this.character,
    this.variation,
    this.scene,
    this.styleTokens = '',
    this.onPersisted,
  });

  @override
  final String taskId;

  final String seriesId;
  final String episodeId;
  final int shotNumber;
  final ImageGenAdapter adapter;

  /// 出場角色卡与场景卡（可为 null：纯动作镜头）。
  final CharacterCard? character;
  final CharacterVariation? variation;
  final SceneCard? scene;
  final String styleTokens;

  /// 写回完成后的回调（UI 据此刷新该分镜卡片）。
  final void Function(StudioShot updatedShot)? onPersisted;

  bool _cancelled = false;

  /// 队列置位取消意图。合成与落盘之间的安全点会检查它。
  @override
  set cancelled(bool value) => _cancelled = value;

  @override
  bool isCancelled() => _cancelled;

  /// 取角色第一张基准参考图的绝对路径；没有则 null。
  String? _referenceImagePath(
    StudioProjectManager manager,
    CharacterCard? character,
  ) {
    if (character == null || character.referenceImages.isEmpty) return null;
    return p.join(
      manager.characterDir(seriesId, character.id).path,
      character.referenceImages.first,
    );
  }

  @override
  Future<String> run(void Function(double progress) onProgress) async {
    onProgress(0.05);
    final manager = StudioProjectManager.instance;
    final episode = manager.readEpisode(seriesId, episodeId);
    if (episode == null) {
      throw StateError('找不到分镜所属的集：$episodeId');
    }
    final shotIndex = episode.shots.indexWhere((s) => s.number == shotNumber);
    if (shotIndex < 0) {
      throw StateError('该集没有镜号为 $shotNumber 的分镜');
    }
    final shot = episode.shots[shotIndex];

    final assembled = PromptAssembler.buildShotPrompt(PromptParts(
      styleTokens: styleTokens,
      shotSize: ShotSizeTokens.of(shot.shotSize),
      mood: MoodTokens.of(shot.mood),
      shotFunction: ShotFunctionTokens.of(shot.function),
      character: character,
      variation: variation,
      scene: scene,
      cameraMove: shot.cameraMove,
    ));

    // 每次生成都重新组装 Prompt：字段（台词/动作/运镜）可能刚被用户改过，
    // 而磁盘上存的是上一次的 assembledPrompt。缓存 Prompt 会让"改了字段但
    // 图没变"这件事看起来像引擎失灵。
    final outputDir = manager.episodeFramesDir(seriesId, episodeId);
    final outputFile = File(p.join(outputDir.path, 'shot_$shotNumber.png'));

    // 基准参考图：角色有垫图时带上，让引擎有第一张"脸"可循。
    final referencePath = _referenceImagePath(manager, character);

    onProgress(0.15);
    try {
      await adapter.generate(ImageGenRequest(
        prompt: assembled.positive,
        negativePrompt: assembled.negative.isEmpty
            ? PromptAssembler.defaultNegativePrompt
            : assembled.negative,
        shotNumber: shotNumber,
        outputFile: outputFile,
        width: 1080,
        height: 1920,
        referenceImagePath: referencePath,
      ));
    } finally {
      // 引擎失败也要把新组装的 Prompt 留下：用户重试时不该丢字段。
      // 这一步放在 finally 里，成功路径同样受益。
      final updated = episode.shots.toList();
      updated[shotIndex] = shot.copyWith(assembledPrompt: assembled.positive);
      await manager.saveEpisode(episode.copyWith(shots: updated));
    }
    if (_cancelled) throw StateError('任务已被取消');

    onProgress(0.95);
    final updated = episode.shots.toList();
    updated[shotIndex] = shot.copyWith(
      assembledPrompt: assembled.positive,
      framePath: p.basename(outputFile.path),
      status: ShotGenerationStatus.done,
    );
    await manager.saveEpisode(episode.copyWith(shots: updated));
    onPersisted?.call(updated[shotIndex]);
    onProgress(1);
    return p.basename(outputFile.path);
  }
}

/// 视频片段生成任务。
///
/// 三种制作类型的默认策略见 [VideoGenAdapterFactory]。云端 I2V 的轮询与
/// 超时（默认 5 分钟）都在适配器内，这里只负责把产物落盘并写回。
class VideoGenTask implements StudioTaskRunner, CancellableTaskRunner {
  VideoGenTask({
    required this.taskId,
    required this.seriesId,
    required this.episodeId,
    required this.shotNumber,
    required this.adapter,
    this.forceLocalKenBurns = false,
    this.onPersisted,
  });

  @override
  final String taskId;

  final String seriesId;
  final String episodeId;
  final int shotNumber;
  final VideoGenAdapter adapter;

  /// 单镜覆盖：用户在某个分镜上强制用本地动效（spec 允许单镜覆盖）。
  final bool forceLocalKenBurns;

  final void Function(StudioShot updatedShot)? onPersisted;

  bool _cancelled = false;

  /// 队列置位取消意图。调用引擎之前与写回之前的检查会读它。
  @override
  set cancelled(bool value) => _cancelled = value;

  @override
  bool isCancelled() => _cancelled;

  @override
  Future<String> run(void Function(double progress) onProgress) async {
    final manager = StudioProjectManager.instance;
    final episode = manager.readEpisode(seriesId, episodeId);
    if (episode == null) {
      throw StateError('找不到分镜所属的集：$episodeId');
    }
    final shotIndex = episode.shots.indexWhere((s) => s.number == shotNumber);
    if (shotIndex < 0) {
      throw StateError('该集没有镜号为 $shotNumber 的分镜');
    }
    final shot = episode.shots[shotIndex];

    // 没有关键帧就没法 I2V，也没有 Ken Burns 的输入。这时不给用户一个
    // "视频生成失败" 的谜，而是明确告诉他先出关键帧。
    final frameName = shot.framePath;
    if (frameName == null || frameName.isEmpty) {
      throw StateError('分镜 $shotNumber 尚未生成关键帧，请先生成关键帧');
    }
    final frameFile = File(
      p.join(manager.episodeFramesDir(seriesId, episodeId).path, frameName),
    );
    if (!frameFile.existsSync()) {
      throw StateError('关键帧文件缺失：$frameName，请重新生成关键帧');
    }

    final effectiveAdapter = forceLocalKenBurns && adapter is! KenBurnsVideoAdapter
        ? KenBurnsVideoAdapter()
        : adapter;

    final clipsDir = manager.episodeClipsDir(seriesId, episodeId);
    final outputFile =
        File(p.join(clipsDir.path, 'shot_$shotNumber.mp4'));

    onProgress(0.1);
    await effectiveAdapter.generateVideo(
      VideoGenRequest(
        inputImage: frameFile,
        cameraMove: shot.cameraMove,
        durationSec: shot.durationSec,
        shotNumber: shotNumber,
        outputFile: outputFile,
        productionType: _productionTypeOf(episode),
      ),
      onProgress: onProgress,
    );
    if (_cancelled) throw StateError('任务已被取消');

    final updated = episode.shots.toList();
    updated[shotIndex] = shot.copyWith(
      clipPath: p.basename(outputFile.path),
      status: ShotGenerationStatus.done,
    );
    await manager.saveEpisode(episode.copyWith(shots: updated));
    onPersisted?.call(updated[shotIndex]);
    onProgress(1);
    return p.basename(outputFile.path);
  }

  /// 从剧集主库读制作类型（决定 Ken Burns 动效的默认选择）。
  String _productionTypeOf(StudioEpisode episode) {
    final series =
        StudioProjectManager.instance.readSeries(episode.seriesId);
    return series?.productionType.id ?? 'drama';
  }
}
