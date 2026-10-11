// 生成任务：把 StudioTaskQueue 与数据层、引擎适配器接起来的执行体。
//
// 任务完成后的「写回」集中在这里，而不是散在 UI：storyboard.json 是唯一的
// 事实来源，UI 只读它。否则同一个分镜会出现「队列说成功、磁盘说没图」的
// 分裂状态，而那种 bug 只能靠重启复现。

import 'dart:io';

import 'package:flutter/widgets.dart';
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

  /// 收集本次生图的参考图：角色基准图 + 场景主视图。
  ///
  /// 只取每个卡片的**第一张**——那是用户在卡上主动指定的"这张脸/这个空间"。
  /// 多张全带会让模型在多张相似图之间摇摆，反而破坏一致性。
  List<String> _referenceImages(
    StudioProjectManager manager,
    CharacterCard? character,
    SceneCard? scene,
  ) {
    final result = <String>[];
    void add(String dir, List<String> names) {
      if (names.isEmpty) return;
      final file = File(p.join(dir, names.first));
      if (file.existsSync()) result.add(file.path);
    }

    if (character != null) {
      add(manager.characterDir(seriesId, character.id).path,
          character.referenceImages);
    }
    if (scene != null) {
      add(manager.sceneDir(seriesId, scene.id).path, scene.referenceImages);
    }
    return result;
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
      actionZh: shot.actionZh,
    ));

    // 每次生成都重新组装 Prompt：字段（台词/动作/运镜）可能刚被用户改过，
    // 而磁盘上存的是上一次的 assembledPrompt。缓存 Prompt 会让"改了字段但
    // 图没变"这件事看起来像引擎失灵。
    final outputDir = manager.episodeFramesDir(seriesId, episodeId);
    final outputFile = File(p.join(outputDir.path, 'shot_$shotNumber.png'));

    // 多参考图：角色基准图 + 场景主视图（spec: 图像多参考图契约）。
    //
    // 顺序即提示词里的 `{{ref N}}`——角色在前，因为身份漂移比空间感不对更
    // 致命，模型在只能看一张时会看到它。
    final referenceImages = _referenceImages(manager, character, scene);

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
        referenceImages: referenceImages,
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
    // 关键帧可能覆盖了同名文件（如 shot_1.png），必须主动清除 Flutter 内存中的图片缓存，
    // 否则前端 Image.file 仍会命中旧图，需要重启或重开窗口才能展示。
    try {
      await FileImage(outputFile).evict();
    } catch (_) {}
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

    // 适配器可能被 [NormalizingVideoAdapter] 包着，`is` 判断会失效——先
    // unwrap 再比较（spec: 片段级视频生成任务 / design 决策 5）。
    final effectiveAdapter = forceLocalKenBurns && unwrapVideoAdapter(adapter) is! KenBurnsVideoAdapter
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

/// 片段视频生成任务（spec: 片段级视频生成任务）。
///
/// 与 [VideoGenTask] 的分工：那个以「一镜一张关键帧」为输入，一次调用产出一
/// 个分镜的片段；这个以「整个片段的参考图集合 + 片段提示词」为输入，一次
/// 调用产出覆盖多个分镜的视频（design 决策 3）。
///
/// 提交前做两项本地校验，都不涉及网络：
/// 1. **参考图存在性**——缺图的片段直接拒绝，不提交一个没有一致性约束的请求
///    （spec: 缺少参考图时不静默降级）；
/// 2. **排除镜号**——被单镜覆盖的镜号跳过，片段生成不覆盖用户已单独出的片。
class SegmentVideoGenTask implements StudioTaskRunner, CancellableTaskRunner {
  SegmentVideoGenTask({
    required this.taskId,
    required this.seriesId,
    required this.episodeId,
    required this.segmentId,
    required this.adapter,
    this.onPersisted,
  });

  @override
  final String taskId;

  final String seriesId;
  final String episodeId;
  final String segmentId;
  final VideoGenAdapter adapter;

  final void Function(StudioSegment updatedSegment)? onPersisted;

  bool _cancelled = false;

  /// 队列置位取消意图。提交前、轮询期间与写回前三个安全点读它。
  @override
  set cancelled(bool value) => _cancelled = value;

  @override
  bool isCancelled() => _cancelled;

  @override
  Future<String> run(void Function(double progress) onProgress) async {
    final manager = StudioProjectManager.instance;
    final episode = manager.readEpisode(seriesId, episodeId);
    if (episode == null) {
      throw StateError('找不到片段所属的集：$episodeId');
    }
    final segIndex = episode.segments.indexWhere((s) => s.id == segmentId);
    if (segIndex < 0) {
      throw StateError('该集没有 id 为 $segmentId 的片段');
    }
    final segment = episode.segments[segIndex];
    if (segment.effectiveShotNumbers.isEmpty) {
      throw StateError('片段 $segmentId 的所有分镜都已单独出片，没有可生成的内容');
    }

    // --- 1. 收集出场角色与场景，解析参考图 ------------------------------
    //
    // 参考图只认每个角色的**第一张**基准图：那是用户在角色卡上主动指定的
    // 「这张脸」。多张全带会让模型在多张相似人脸间摇摆，反而破坏一致性。
    final shots = episode.shots
        .where((s) => segment.effectiveShotNumbers.contains(s.number))
        .toList();
    final characterIds = <String>{
      for (final s in shots) ...s.characterIds,
    };
    final sceneIds = <String>{
      for (final s in shots)
        if (s.sceneId.isNotEmpty) s.sceneId,
    };

    final characters = <CharacterCard>[];
    for (final id in characterIds) {
      final card = manager.readCharacter(seriesId, id);
      if (card != null) characters.add(card);
    }
    final scenes = <SceneCard>[];
    for (final id in sceneIds) {
      final card = manager.readScene(seriesId, id);
      if (card != null) scenes.add(card);
    }

    final referenceFiles = <File>[];
    final referenceLabels = <String>[];
    for (final c in characters) {
      if (c.referenceImages.isEmpty) {
        throw StateError(
          '角色「${c.name}」没有基准参考图。片段生成依赖参考图保持人物一致，'
          '请先在 IP 主库为该角色上传参考图，或改用分镜级生成。',
        );
      }
      final file = File(
        p.join(manager.characterDir(seriesId, c.id).path, c.referenceImages.first),
      );
      if (!file.existsSync()) {
        throw StateError('角色「${c.name}」的参考图文件缺失，请重新上传');
      }
      referenceFiles.add(file);
      referenceLabels.add(c.name);
    }
    for (final s in scenes) {
      if (s.referenceImages.isEmpty) continue;
      final file = File(
        p.join(manager.sceneDir(seriesId, s.id).path, s.referenceImages.first),
      );
      if (!file.existsSync()) continue;
      referenceFiles.add(file);
      referenceLabels.add(s.name);
    }

    // --- 2. 组装片段提示词 ----------------------------------------------
    //
    // 纯函数、每次重算：用户刚改过的分镜字段会立刻反映进来，不需要判断
    // 「何时该重新生成提示词」（design 决策 5）。
    final series = manager.readSeries(seriesId);
    final assembled = PromptAssembler.buildSegmentPrompt(
      SegmentPromptParts(
        styleTokens: series?.styleTokens ?? '',
        targetDurationSec: segment.targetDurationSec,
        characters: characters,
        scenes: scenes,
        shots: shots
            .map((s) => SegmentShotParts(
                  number: s.number,
                  actionZh: s.actionZh,
                  dialogue: s.dialogue,
                  cameraMove: s.cameraMove,
                  continuity: s.continuity,
                ))
            .toList(),
        promptNote: segment.promptNote,
      ),
      references: [
        for (var i = 0; i < referenceFiles.length; i++)
          SegmentReference(label: referenceLabels[i], usage: referenceLabels[i]),
      ],
    );
    // 角色缺图时组装器会把缺口报回来。上面已经逐个查过并抛了更具体的错，
    // 这里再兜一层：场景缺图不该阻断生成（场景约束缺失只是空间感变弱）。
    if (assembled.missingReferences
        .any((m) => characters.any((c) => m.startsWith(c.name)))) {
      throw StateError('片段提示词缺少角色参考图绑定，已阻止生成');
    }

    if (_cancelled) throw StateError('任务已被取消');
    onProgress(0.1);

    // --- 3. 提交生成 ----------------------------------------------------
    final segmentsDir = manager.episodeSegmentsDir(seriesId, episodeId);
    final outputFile = File(p.join(segmentsDir.path, '${segment.id}.mp4'));

    await adapter.generateVideo(
      VideoGenRequest(
        // 片段级不带首帧：输入是参考图集合，不是某一张关键帧。
        inputImage: null,
        referenceImages: referenceFiles,
        promptZh: assembled.positive,
        cameraMove: shots.first.cameraMove,
        durationSec: segment.targetDurationSec.toDouble(),
        shotNumber: segment.effectiveShotNumbers.first,
        outputFile: outputFile,
        productionType: series?.productionType.id ?? 'drama',
      ),
      onProgress: (v) => onProgress(0.1 + v * 0.85),
    );
    if (_cancelled) throw StateError('任务已被取消');

    // 规整包装器把吸附结果挂在 [NormalizingVideoAdapter.lastChanges] 上；
    // 本地 Ken Burns 不包规整层，提交时长就是请求时长。
    final submittedDuration = submittedDurationOf(
      adapter,
      segment.targetDurationSec,
    );

    // --- 4. 写回 --------------------------------------------------------
    //
    // 降级数量与「实际提交时长」一并落盘：用户得知道「我传了 3 张只用了 1 张」
    // 与「我请求 15s 提交的是 12s」，否则会以为约束与参数都生效了
    // （design 决策 4 / spec: 分镜看板展示本次提交的实际参数）。
    final degraded = referenceFiles.length - 1;
    final updated = episode.segments.toList();
    updated[segIndex] = segment.copyWith(
      clipPath: p.basename(outputFile.path),
      status: SegmentStatus.done,
      degradedRefCount: degraded < 0 ? 0 : degraded,
      submittedDurationSec: submittedDuration,
    );
    await manager.saveEpisode(episode.copyWith(segments: updated));
    onPersisted?.call(updated[segIndex]);
    onProgress(1);
    return p.basename(outputFile.path);
  }
}

/// 取回适配器的内层实现。被规整包装器包住时这是唯一能拿到真实类型的途径。
VideoGenAdapter unwrapVideoAdapter(VideoGenAdapter adapter) =>
    adapter is NormalizingVideoAdapter ? adapter.unwrap() : adapter;

/// 本次实际提交给模型的时长（秒）。
///
/// 规整包装器吸附后会记录变更，这里把「时长 Xs → Ys」里的 Y 取出来；没有
/// 吸附记录时说明提交的就是请求值。本地 Ken Burns 不走规整层，同样返回请求值。
int submittedDurationOf(VideoGenAdapter adapter, int requested) {
  final inner = unwrapVideoAdapter(adapter);
  if (inner is! NormalizingVideoAdapter) return requested;
  for (final change in inner.lastChanges) {
    final match = RegExp(r'时长 (\d+)s → (\d+)s').firstMatch(change);
    if (match != null) return int.parse(match.group(2)!);
  }
  return requested;
}
