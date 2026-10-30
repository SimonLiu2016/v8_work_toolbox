// 生成任务：把 StudioTaskQueue 与数据层、引擎适配器接起来的执行体。
//
// 任务完成后的「写回」集中在这里，而不是散在 UI：storyboard.json 是唯一的
// 事实来源，UI 只读它。否则同一个分镜会出现「队列说成功、磁盘说没图」的
// 分裂状态，而那种 bug 只能靠重启复现。

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../models/studio_models.dart';
import 'breakdown_input.dart';
import 'ffmpeg_composer.dart';
import 'image_gen_adapter.dart';
import 'prompt_assembler.dart';
import 'studio_project_manager.dart';
import 'studio_task_queue.dart';
import 'video_gen_adapter.dart';

/// 首尾帧接力的判据（spec: 分镜首帧来源的可信判据）。
///
/// 上一镜的视频尾帧只能作为**同一主体连续动作**的下一镜首帧。正反打、切景
/// 别、换主体都发生在同一个场景卡内——旧实现只比 `sceneId` 相等，于是
/// 「三楼窗口俯拍特写」的尾帧会被塞给「地面街心仰拍中景」当首帧，视频模型
/// 要么把人物换成另一个人，要么在窗户里变出一头驴。
///
/// 四个条件全部取自用户/AI 已声明的字段，不引入新输入：
/// 1. 同一场景卡；
/// 2. 出场主体集合判等（上镜三人、本镜一人同样是切主体）；
/// 3. 非正反打；
/// 4. 景别差不超过 1 档。
bool canRelayFrameFromPrev(StudioShot prevShot, StudioShot shot) {
  if (prevShot.sceneId != shot.sceneId) return false;
  if (prevShot.sceneId.isEmpty) return false;

  final prevIds = prevShot.characterIds.toSet();
  final currIds = shot.characterIds.toSet();
  if (!setEquals(prevIds, currIds)) return false;

  // 空间高度层（elevationLevel）不一致时禁止接力（如二楼 balcony_2f vs 地面 ground）。
  final prevElev = prevShot.continuity.elevationLevel.trim().toLowerCase();
  final currElev = shot.continuity.elevationLevel.trim().toLowerCase();
  if (prevElev.isNotEmpty && currElev.isNotEmpty && prevElev != currElev) {
    return false;
  }

  // 拍摄俯仰角（cameraAngle）不一致时禁止接力（如俯拍 high_angle vs 仰拍 low_angle）。
  final prevAngle = (prevShot.continuity.cameraAngle.trim().isNotEmpty
          ? prevShot.continuity.cameraAngle
          : prevShot.directorDecisions.cameraAngle)
      .trim()
      .toLowerCase();
  final currAngle = (shot.continuity.cameraAngle.trim().isNotEmpty
          ? shot.continuity.cameraAngle
          : shot.directorDecisions.cameraAngle)
      .trim()
      .toLowerCase();
  if (prevAngle.isNotEmpty && currAngle.isNotEmpty && prevAngle != currAngle) {
    return false;
  }

  if (_isReverseShot(prevShot, shot)) return false;

  final rankGap =
      (_shotSizeRank(prevShot.shotSize) - _shotSizeRank(shot.shotSize)).abs();
  return rankGap <= 1;
}

/// 正反打判定：
/// 1. 任一方被显式标记为对峙分工（`confrontation`）；
/// 2. 两镜中一方特写另一方非特写；
/// 3. 两镜的连续性视线方向（`gazeDirection`）或画面站位（`screenPosition`）发生左右/俯仰镜像翻转。
bool _isReverseShot(StudioShot prevShot, StudioShot shot) {
  final ids = {...prevShot.characterIds, ...shot.characterIds};
  for (final id in ids) {
    final prevRole = prevShot.assetBindings[id]?.role;
    final currRole = shot.assetBindings[id]?.role;
    if (prevRole == ShotAssetRole.confrontation ||
        currRole == ShotAssetRole.confrontation) {
      return true;
    }
  }
  final prevClose = prevShot.shotSize == StudioShotSize.closeUp;
  final currClose = shot.shotSize == StudioShotSize.closeUp;
  if (prevClose != currClose) return true;

  final prevGaze = prevShot.continuity.gazeDirection.trim().isNotEmpty
      ? prevShot.continuity.gazeDirection
      : prevShot.directorDecisions.gazeDirection;
  final currGaze = shot.continuity.gazeDirection.trim().isNotEmpty
      ? shot.continuity.gazeDirection
      : shot.directorDecisions.gazeDirection;
  if (_hasOppositeOrientation(prevGaze, currGaze)) {
    return true;
  }

  if (_hasOppositeOrientation(
    prevShot.continuity.screenPosition,
    shot.continuity.screenPosition,
  )) {
    return true;
  }

  return false;
}

bool _hasOppositeOrientation(String rawA, String rawB) {
  final a = rawA.trim().toLowerCase();
  final b = rawB.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty || a == b) return false;

  int? sideOf(String s) {
    final leftIdx = s.indexOf(RegExp(r'left|左'));
    final rightIdx = s.indexOf(RegExp(r'right|右'));
    if (leftIdx >= 0 && rightIdx < 0) return -1;
    if (rightIdx >= 0 && leftIdx < 0) return 1;
    if (leftIdx >= 0 && rightIdx >= 0) {
      return leftIdx < rightIdx ? -1 : 1;
    }
    return null;
  }

  final sideA = sideOf(a);
  final sideB = sideOf(b);
  if (sideA != null && sideB != null && sideA != sideB) {
    return true;
  }

  int? verticalOf(String s) {
    final upIdx = s.indexOf(RegExp(r'up|仰|上'));
    final downIdx = s.indexOf(RegExp(r'down|俯|下'));
    if (upIdx >= 0 && downIdx < 0) return 1;
    if (downIdx >= 0 && upIdx < 0) return -1;
    if (upIdx >= 0 && downIdx >= 0) {
      return upIdx < downIdx ? 1 : -1;
    }
    return null;
  }

  final vertA = verticalOf(a);
  final vertB = verticalOf(b);
  if (vertA != null && vertB != null && vertA != vertB) {
    return true;
  }
  return false;
}

/// 景别档位（特写最近、大远景最远）。用于算两镜的景别差。
int _shotSizeRank(StudioShotSize size) {
  switch (size) {
    case StudioShotSize.closeUp:
      return 0;
    case StudioShotSize.mediumCloseUp:
      return 1;
    case StudioShotSize.medium:
      return 2;
    case StudioShotSize.full:
      return 3;
    case StudioShotSize.long:
      return 4;
    case StudioShotSize.extremeLong:
      return 5;
  }
}

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
    this.characters = const [],
    this.characterVariations = const {},
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
  final List<CharacterCard> characters;
  final Map<String, CharacterVariation?> characterVariations;
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

    // 场景卡防漏兜底：若未注入 scene 但分镜指定了 sceneId，自动反查补齐
    final effectiveScene = scene ??
        (shot.sceneId.isNotEmpty
            ? manager.readScene(seriesId, shot.sceneId)
            : null);

    // 形态解析下沉为共享函数（spec: 生图与生视频的参考图取材同源）。旧实现
    // 直接用 UI 传进来的 characterVariations / variation，而那是 UI 侧的
    // _resolveVariation 结果——一旦入口没走 UI（批量路径、重试路径），三级
    // 优先级就退化成 card.activeVariation，用户在分镜卡选的形态悄悄失效。
    final effectiveVariations = <String, CharacterVariation?>{};
    for (final c in characters) {
      effectiveVariations[c.id] = ShotVariationResolver.resolve(
        episode: episode,
        shot: shot,
        character: c,
      );
    }
    final effectivePrimary = character ?? characters.firstOrNull;
    final effectivePrimaryVariation = effectivePrimary != null
        ? effectiveVariations[effectivePrimary.id]
        : null;

    // 参考图取材与视频生成读同一份素材绑定（spec: 生图与生视频的参考图取材
    // 同源）。旧实现自己写了一份「turnaround.png → referenceImages.first」的
    // 挑选，与视频路径的 AssetBindingResolver 各挑各的——同一分镜，关键帧用
    // 三视图、视频用上传图，用户看到的就是「人物长相对不上」。
    //
    // 形态的三级优先级通过临时角色卡喂给 resolver：把 activeVariation 换成
    // 解析结果，resolver 的默认取材就会优先找该形态的三视图。
    final fallbackChar = character;
    final resolverCharacters = <CharacterCard>[
      ...characters,
      if (characters.isEmpty && fallbackChar != null) fallbackChar,
    ];
    final cardsForResolver = <CharacterCard>[
      for (final c in resolverCharacters)
        ShotVariationResolver.resolveCharacterForShot(
          episode: episode,
          shot: shot,
          character: c,
        ),
    ];
    final allProps = await manager.listProps(seriesId);
    final resolvedMaterials = AssetBindingResolver.resolve(
      shot: shot,
      characters: cardsForResolver,
      props: allProps,
      scene: effectiveScene,
      seriesId: seriesId,
      manager: manager,
    );
    final referenceImages = resolvedMaterials.map((m) => m.filePath).toList();
    // 按参考图顺序推出「哪些角色有图」——多图编号段靠它对齐实际提交的数组。
    final charactersWithImages = <CharacterCard>[];
    for (final m in resolvedMaterials) {
      if (m.isScene || m.isProp) continue;
      final card = cardsForResolver.where((c) => c.id == m.assetId).firstOrNull;
      if (card != null && !charactersWithImages.any((c) => c.id == card.id)) {
        charactersWithImages.add(card);
      }
    }
    final hasSceneImage = resolvedMaterials.any((m) => m.isScene);

    final series = manager.readSeries(seriesId);
    final eraGenre = VisualEraGenre.fromId(series?.eraGenre);

    final assembled = PromptAssembler.buildShotPrompt(PromptParts(
      productionType: series?.productionType,
      styleTokens: styleTokens.isNotEmpty ? styleTokens : (series?.styleTokens ?? ''),
      eraGenre: eraGenre,
      negativeStyleTokens: series?.negativeStyleTokens,
      shotSize: ShotSizeTokens.of(shot.shotSize),
      mood: MoodTokens.of(shot.mood),
      shotFunction: ShotFunctionTokens.of(shot.function),
      character: effectivePrimary,
      variation: effectivePrimaryVariation,
      characters: cardsForResolver,
      characterVariations: effectiveVariations,
      scene: effectiveScene,
      cameraMove: shot.cameraMove,
      actionZh: shot.actionZh,
      dialogue: shot.dialogue,
      voiceType: shot.voiceType,
      continuity: shot.continuity,
      directorDecisions: shot.directorDecisions,
      isMultiImage: referenceImages.length >= 2,
      hasCharacterReferences: referenceImages.isNotEmpty &&
          (cardsForResolver.isNotEmpty || effectivePrimary != null),
      charactersWithImages: charactersWithImages,
      hasSceneImage: hasSceneImage,
    ));

    // 每次生成都重新组装 Prompt：字段（台词/动作/运镜）可能刚被用户改过，
    // 而磁盘上存的是上一次的 assembledPrompt。缓存 Prompt 会让"改了字段但
    // 图没变"这件事看起来像引擎失灵。
    final outputDir = manager.episodeFramesDir(seriesId, episodeId);
    final outputFile = File(p.join(outputDir.path, 'shot_$shotNumber.png'));

    // 动态计算生图尺寸（废除写死 1080x1920，支持横竖屏与各档位）
    final effectiveRatio = (shot.aspectRatio != null && shot.aspectRatio!.trim().isNotEmpty)
        ? shot.aspectRatio!.trim()
        : (series?.defaultAspectRatio.trim().isNotEmpty == true
            ? series!.defaultAspectRatio.trim()
            : '9:16');
    final effectiveResolution = (shot.resolution != null && shot.resolution!.trim().isNotEmpty)
        ? shot.resolution!.trim()
        : (series?.defaultResolution.trim().isNotEmpty == true
            ? series!.defaultResolution.trim()
            : '2K');
    final dimension = StudioImageDimensionPreset.fromRatio(
      effectiveRatio,
      size: effectiveResolution,
    );

    onProgress(0.15);
    try {
      await adapter.generate(ImageGenRequest(
        prompt: assembled.positive,
        negativePrompt: assembled.negative.isEmpty
            ? PromptAssembler.defaultNegativePrompt
            : assembled.negative,
        shotNumber: shotNumber,
        outputFile: outputFile,
        width: dimension.width,
        height: dimension.height,
        referenceImages: referenceImages,
      ));
    } finally {
      // 引擎失败也要把新组装的 Prompt 留下：用户重试时不该丢字段。
      // 这一步放在 finally 里，成功路径同样受益。
      await manager.updateShot(
        seriesId,
        episodeId,
        shotNumber,
        (current) => current.copyWith(assembledPrompt: assembled.positive),
      );
    }
    if (_cancelled) throw StateError('任务已被取消');

    onProgress(0.95);
    final updatedShot = await manager.updateShot(
      seriesId,
      episodeId,
      shotNumber,
      (current) {
        final hasClip = current.clipPath != null && current.clipPath!.isNotEmpty;
        return current.copyWith(
          assembledPrompt: assembled.positive,
          framePath: p.basename(outputFile.path),
          status: ShotGenerationStatus.done,
          // 若已有生成的视频，重新生成关键帧后原视频与最新地基脱节，标记为 stale 待重构
          clipStatus: hasClip ? StudioClipStatus.stale : current.clipStatus,
        );
      },
    );
    // 关键帧可能覆盖了同名文件（如 shot_1.png），必须主动清除 Flutter 内存中的图片缓存，
    // 否则前端 Image.file 仍会命中旧图，需要重启或重开窗口才能展示。
    try {
      await FileImage(outputFile).evict();
    } catch (_) {}
    if (updatedShot != null) {
      onPersisted?.call(updatedShot);
    }
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
    final series = manager.readSeries(seriesId);

    // 动态计算视频画幅与分辨率档位
    final effectiveRatio = (shot.aspectRatio != null && shot.aspectRatio!.trim().isNotEmpty)
        ? shot.aspectRatio!.trim()
        : (series?.defaultAspectRatio.trim().isNotEmpty == true
            ? series!.defaultAspectRatio.trim()
            : '9:16');
    final effectiveResolution = (shot.resolution != null && shot.resolution!.trim().isNotEmpty)
        ? shot.resolution!.trim()
        : (series?.defaultResolution.trim().isNotEmpty == true
            ? series!.defaultResolution.trim()
            : '720P');
    final sizeTier = (effectiveResolution.toUpperCase().contains('4K') ||
            effectiveResolution.toUpperCase().contains('2K') ||
            effectiveResolution.toUpperCase().contains('1080'))
        ? '1080P'
        : '720P';

    // 关键帧存在性检查
    final frameName = shot.framePath;
    final hasKeyframe = frameName != null &&
        frameName.isNotEmpty &&
        File(p.join(manager.episodeFramesDir(seriesId, episodeId).path, frameName)).existsSync();

    // 解析分镜生效的视频生成模式
    final effectiveMode = shot.resolveEffectiveVideoMode(
      hasKeyframe: hasKeyframe,
      hasCharacterOrSceneRef: shot.characterIds.isNotEmpty || shot.sceneId.isNotEmpty,
    );

    // 适配器可能被 [NormalizingVideoAdapter] 包着，`is` 判断会失效——先
    // unwrap 再比较（spec: 片段级视频生成任务 / design 决策 5）。
    final effectiveAdapter = forceLocalKenBurns && unwrapVideoAdapter(adapter) is! KenBurnsVideoAdapter
        ? KenBurnsVideoAdapter()
        : adapter;

    // 若为本地动效，严格要求首帧
    if ((forceLocalKenBurns || unwrapVideoAdapter(adapter) is KenBurnsVideoAdapter) && !hasKeyframe) {
      throw StateError('分镜 $shotNumber 使用本地动效模式，尚未生成关键帧，请先生成关键帧');
    }

    final clipsDir = manager.episodeClipsDir(seriesId, episodeId);
    final outputFile = File(p.join(clipsDir.path, 'shot_$shotNumber.mp4'));

    File? inputImageFile;
    File? lastFrameImageFile;
    var firstFrameSource = FirstFrameSource.none;
    final referenceFiles = <File>[];

    // 提取出场人物卡与场景卡，用于组装 Prompt 或多参考图（通过 ShotVariationResolver 唯一激活当前分镜形态）
    final allCharacters = await manager.listCharacters(seriesId);
    final rawShotCharacters = allCharacters
        .where((c) => shot.characterIds.contains(c.id))
        .toList();
    rawShotCharacters.sort((a, b) {
      final aIdx = shot.characterIds.indexOf(a.id);
      final bIdx = shot.characterIds.indexOf(b.id);
      return aIdx.compareTo(bIdx);
    });
    final shotCharacters = <CharacterCard>[
      for (final c in rawShotCharacters)
        ShotVariationResolver.resolveCharacterForShot(
          episode: episode,
          shot: shot,
          character: c,
        ),
    ];

    final allScenes = await manager.listScenes(seriesId);
    final scene = allScenes.where((s) => s.id == shot.sceneId).firstOrNull;

    // 根据模式严格分流素材与互斥校验（官方规范）
    switch (effectiveMode) {
      case AgnesVideoMode.keyframe:
        if (!hasKeyframe) {
          throw StateError('分镜 $shotNumber 在首尾帧（keyframe）模式下尚未生成关键帧，请先生成关键帧');
        }
        final frameFile = File(
          p.join(manager.episodeFramesDir(seriesId, episodeId).path, frameName),
        );
        // 本镜关键帧永远是默认首帧。跨镜尾帧接力只在满足严格判据时才会替换
        // 它——正反打/切景别/换主体同属一个场景卡，旧实现只比 sceneId，会把
        // 「三楼俯拍特写」的尾帧塞给「地面仰拍中景」当首帧（spec: 分镜首帧
        // 来源的可信判据）。
        inputImageFile = frameFile;
        firstFrameSource = FirstFrameSource.keyframe;

        // 连续镜头首尾帧接力：仅当两镜是同一主体的连续动作时才用上一镜尾帧。
        if (shotIndex > 0) {
          final prevShot = episode.shots[shotIndex - 1];
          if (prevShot.clipPath != null && prevShot.clipPath!.isNotEmpty) {
            final prevClipFile = File(p.join(clipsDir.path, prevShot.clipPath!));
            if (prevClipFile.existsSync() &&
                canRelayFrameFromPrev(prevShot, shot)) {
              final framesDir = manager.episodeFramesDir(seriesId, episodeId);
              final prevLastFrameFile =
                  File(p.join(framesDir.path, 'shot_${prevShot.number}_last.png'));
              final extracted = await FfmpegComposer.extractLastFrame(
                videoFile: prevClipFile,
                outputFile: prevLastFrameFile,
              );
              if (extracted != null && extracted.existsSync()) {
                inputImageFile = extracted;
                firstFrameSource = FirstFrameSource.relay;
              }
            }
          }
        }
        break;

      case AgnesVideoMode.reference:
        // 取材统一走 AssetBindingResolver（spec: shot-asset-binding）。
        //
        // 旧实现自己写了一份「referenceImages.first → faceAnchorPath」的挑选
        // 逻辑，与生图路径的 _referenceImages 不一致——同一分镜，关键帧用
        // turnaround.png、视频用上传图，用户看到的就是「人物长相对不上」。
        // 现在两条路径读同一份 assetBindings，编号与 images 数组同序。
        final allProps = await manager.listProps(seriesId);
        final resolved = AssetBindingResolver.resolveWithGaps(
          shot: shot,
          characters: shotCharacters,
          props: allProps,
          scene: scene,
          seriesId: seriesId,
          manager: manager,
        );
        referenceFiles.addAll(resolved.materials.map((m) => File(m.filePath)));
        if (resolved.missing.isNotEmpty) {
          throw StateError(
            '分镜 $shotNumber 的出场资产缺少可用素材图：${resolved.missing.join('、')}。'
            '请在 IP 主库为这些资产上传参考图或生成三视图，'
            '或在分镜卡的出场资产面板中改选其他素材。',
          );
        }
        // 一个素材都没有时，回落到关键帧——那是用户唯一可能已有的图。
        if (referenceFiles.isEmpty) {
          if (hasKeyframe) {
            final f = File(
              p.join(manager.episodeFramesDir(seriesId, episodeId).path, frameName),
            );
            if (f.existsSync()) referenceFiles.add(f);
          }
          if (referenceFiles.isEmpty) {
            throw StateError('分镜 $shotNumber 在参考图（reference）模式下未找到可用的角色或场景参考图片，请先配置角色/场景图片或生成关键帧');
          }
        }
        break;

      case AgnesVideoMode.text:
        inputImageFile = null;
        lastFrameImageFile = null;
        firstFrameSource = FirstFrameSource.none;
        break;

      case AgnesVideoMode.auto:
        break;
    }

    final allProps = await manager.listProps(seriesId);
    // 提示词与提交数组用同一份有序素材列表，编号错位在结构上不可能发生。
    final shotMaterials = AssetBindingResolver.resolve(
      shot: shot,
      characters: shotCharacters,
      props: allProps,
      scene: scene,
      seriesId: seriesId,
      manager: manager,
    );

    // 定制提示词只在来源未失效时使用（spec: 分镜字段变更作废缓存的视频提示词）。
    // 用户在分镜卡改过动作/台词/出场角色/场景/素材绑定后，那份快照就不再反映
    // 最新字段——继续用它，新绑定的 <Picture N> 与最新因果时间轴永远进不去请求。
    final rawPrompt =
        (!shot.isVideoPromptStale && shot.videoPrompt.trim().isNotEmpty)
            ? shot.videoPrompt.trim()
            : PromptAssembler.buildVideoGenPrompt(
                shot: shot,
                episode: episode,
                characters: shotCharacters,
                props: allProps,
                scene: scene,
                materials: shotMaterials,
                videoMode: effectiveMode,
                hasFirstFrame: inputImageFile != null,
              );
    final videoPrompt = PromptAssembler.sanitizeForVideoMode(
      rawPrompt,
      mode: effectiveMode,
      materials: shotMaterials,
      characters: shotCharacters,
    );

    onProgress(0.1);
    await effectiveAdapter.generateVideo(
      VideoGenRequest(
        inputImage: inputImageFile,
        lastFrameImage: lastFrameImageFile,
        referenceImages: referenceFiles,
        promptZh: videoPrompt,
        cameraMove: shot.cameraMove,
        durationSec: shot.durationSec,
        shotNumber: shotNumber,
        outputFile: outputFile,
        productionType: _productionTypeOf(episode),
        mode: effectiveMode,
        sizeTier: sizeTier,
        ratio: effectiveRatio,
        seriesId: seriesId,
        episodeId: episodeId,
        label: '分镜 $shotNumber 视频',
      ),
      onProgress: onProgress,
    );
    if (_cancelled) throw StateError('任务已被取消');

    // 视频生成完毕后，自动抽取本镜最后一帧，为下镜接力打好基础
    String? lastFrameFileName;
    if (outputFile.existsSync()) {
      final framesDir = manager.episodeFramesDir(seriesId, episodeId);
      final lastFrameFile =
          File(p.join(framesDir.path, 'shot_${shotNumber}_last.png'));
      final extracted = await FfmpegComposer.extractLastFrame(
        videoFile: outputFile,
        outputFile: lastFrameFile,
      );
      if (extracted != null) {
        lastFrameFileName = p.basename(extracted.path);
      }
    }

    final updatedShot = await manager.updateShot(
      seriesId,
      episodeId,
      shotNumber,
      (current) => current.copyWith(
        clipPath: p.basename(outputFile.path),
        // firstFramePath 记录**实际提交**的那个文件，firstFrameSource 记录它
        // 是本镜关键帧还是接力自上一镜尾帧。旧实存在接力时把上一镜尾帧的
        // basename 写进来却不标来源，本镜与自己关键帧的关联就此断裂
        // （spec: 首帧路径记录真实使用的文件）。
        firstFramePath: inputImageFile != null
            ? p.basename(inputImageFile.path)
            : current.firstFramePath,
        firstFrameSource: inputImageFile != null
            ? firstFrameSource
            : current.firstFrameSource,
        lastFramePath: lastFrameFileName ?? current.lastFramePath,
        status: ShotGenerationStatus.done,
        clipStatus: StudioClipStatus.valid,
      ),
    );
    if (updatedShot != null) {
      onPersisted?.call(updatedShot);
    }
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
    // 锁定主物理场景（Dominant Primary Scene）：单个视频片段为单次连贯物理镜头，仅绑定首个有效主场景
    String? dominantSceneId;
    for (final s in shots) {
      if (s.sceneId.isNotEmpty) {
        dominantSceneId = s.sceneId;
        break;
      }
    }

    final characters = <CharacterCard>[];
    for (final id in characterIds) {
      final card = manager.readCharacter(seriesId, id);
      if (card != null) characters.add(card);
    }
    final scenes = <SceneCard>[];
    if (dominantSceneId != null) {
      final card = manager.readScene(seriesId, dominantSceneId);
      if (card != null) scenes.add(card);
    }

    // 取材统一走 AssetBindingResolver（spec: shot-asset-binding）。
    //
    // 片段覆盖 N 个分镜，每个分镜可能绑定不同的素材。这里按「首次出场顺序」
    // 合并各分镜的绑定：同一资产在多镜绑定了不同素材时，取首次出镜那份——
    // 片段是一次连贯物理镜头，中途换脸比用错一张图更糟。
    //
    // 旧实现自己写了一份「referenceImages.first」的挑选逻辑，与生图路径和
    // 分镜级视频都不一致；现在三条路径读同一份 assetBindings。
    final allProps = await manager.listProps(seriesId);
    final orderedAssetIds = <String>[];
    for (final shot in shots) {
      for (final cid in shot.characterIds) {
        if (!orderedAssetIds.contains(cid)) orderedAssetIds.add(cid);
      }
      for (final pid in shot.propIds) {
        if (!orderedAssetIds.contains(pid)) orderedAssetIds.add(pid);
      }
    }
    final dominantScene = scenes.isNotEmpty ? scenes.first : null;
    if (dominantScene != null && !orderedAssetIds.contains(dominantScene.id)) {
      orderedAssetIds.add(dominantScene.id);
    }

    final referenceFiles = <File>[];
    final referenceLabels = <String>[];
    final segmentMaterials = <ResolvedAssetMaterial>[];
    for (final assetId in orderedAssetIds) {
      // 找到该资产首次出镜的分镜，用那份绑定。
      final ownerShot = shots.firstWhere(
        (s) =>
            s.characterIds.contains(assetId) ||
            s.propIds.contains(assetId) ||
            s.sceneId == assetId,
        orElse: () => shots.first,
      );
      final isScene = dominantScene != null && assetId == dominantScene.id;
      final isProp = allProps.any((p) => p.id == assetId);
      final assetCharacters = (isScene || isProp)
          ? const <CharacterCard>[]
          : characters.where((c) => c.id == assetId).toList();
      final assetProps = isProp
          ? allProps.where((p) => p.id == assetId).toList()
          : const <PropCard>[];

      final resolved = AssetBindingResolver.resolve(
        shot: ownerShot.copyWith(
          characterIds: (isScene || isProp) ? const [] : [assetId],
          propIds: isProp ? [assetId] : const [],
          sceneId: isScene ? assetId : '',
        ),
        characters: assetCharacters,
        props: assetProps,
        scene: isScene ? dominantScene : null,
        seriesId: seriesId,
        manager: manager,
      );
      if (resolved.isEmpty) {
        // 该资产没有可用素材：角色与道具是硬阻断（片段靠参考图保持一致），
        // 场景只是空间感变弱，跳过即可。
        if (!isScene) {
          final name = assetCharacters.isNotEmpty
              ? assetCharacters.first.name
              : (assetProps.isNotEmpty ? assetProps.first.name : assetId);
          throw StateError(
            '资产「$name」没有可用的素材图。片段生成依赖参考图保持一致，'
            '请在 IP 主库为该资产上传参考图或生成三视图。',
          );
        }
        continue;
      }
      final m = resolved.first;
      referenceFiles.add(File(m.filePath));
      referenceLabels.add(m.assetName);
      segmentMaterials.add(ResolvedAssetMaterial(
        assetId: m.assetId,
        assetName: m.assetName,
        isScene: m.isScene,
        role: m.role,
        filePath: m.filePath,
        index: segmentMaterials.length,
      ));
    }

    // --- 2. 组装片段提示词 ----------------------------------------------
    //
    // 纯函数、每次重算：用户刚改过的分镜字段会立刻反映进来，不需要判断
    // 「何时该重新生成提示词」（design 决策 5）。
    final series = manager.readSeries(seriesId);
    final assembled = PromptAssembler.buildSegmentPrompt(
      SegmentPromptParts(
        productionType: series?.productionType,
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
                  // 出场角色进时间轴：每行的素材指代靠它判定归属。
                  characterIds: s.characterIds,
                  // 真实分镜时长进区间累加：用均摊兜底会让片段提示词的区间与
                  // SRT 游标、剪映导出对不上（spec: 时间区间覆盖片段目标时长）。
                  durationSec: s.durationSec,
                  continuity: s.continuity,
                ))
            .toList(),
        promptNote: segment.promptNote,
      ),
      references: [
        for (final m in segmentMaterials)
          SegmentReference(label: m.assetName, usage: m.assetName),
      ],
      materials: segmentMaterials,
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
        mode: AgnesVideoMode.reference,
        promptZh: assembled.positive,
        cameraMove: shots.first.cameraMove,
        durationSec: segment.targetDurationSec.toDouble(),
        shotNumber: segment.effectiveShotNumbers.first,
        outputFile: outputFile,
        productionType: series?.productionType.id ?? 'drama',
        // 台账上下文：任务创建即计费，这几个字段决定重启后能否把云端任务
        // 对回这个片段。缺一个，取回的视频就不知道该写进哪里。
        seriesId: seriesId,
        episodeId: episodeId,
        segmentId: segmentId,
        label: '片段视频 $segmentId',
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
    final currentAdapter = adapter;
    final int? maxRefs = currentAdapter is NormalizingVideoAdapter
        ? currentAdapter.capability.maxReferenceImages
        : 8;
    final int degraded = (maxRefs != null && referenceFiles.length > maxRefs)
        ? (referenceFiles.length - maxRefs)
        : 0;

    // 关键修复：长异步生成完成后，重新从磁盘读取剧集最新状态，
    // 避免覆盖并发生成的其他大段（如 seg-3、seg-4 相互覆盖）。
    final latestEpisode = manager.readEpisode(seriesId, episodeId) ?? episode;
    final latestSegIndex =
        latestEpisode.segments.indexWhere((s) => s.id == segmentId);
    final targetSegment = latestSegIndex >= 0
        ? latestEpisode.segments[latestSegIndex]
        : segment;

    final updatedSegments = latestEpisode.segments.toList();
    final updatedSegment = targetSegment.copyWith(
      clipPath: p.basename(outputFile.path),
      status: SegmentStatus.done,
      degradedRefCount: degraded,
      submittedDurationSec: submittedDuration,
    );
    if (latestSegIndex >= 0) {
      updatedSegments[latestSegIndex] = updatedSegment;
    } else {
      updatedSegments.add(updatedSegment);
    }
    await manager.saveEpisode(latestEpisode.copyWith(segments: updatedSegments));
    onPersisted?.call(updatedSegment);
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
